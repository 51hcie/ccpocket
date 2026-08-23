import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/logger.dart';
import '../models/machine.dart';
import '../utils/network_endpoint.dart';
import 'machine_manager_service.dart';

/// Configuration for dedicated Macremote bridge bootstrapping.
class MacremoteBootstrapConfig {
  final String? bridgeUrl;
  final String? bridgeName;
  final bool autoConnect;

  const MacremoteBootstrapConfig({
    this.bridgeUrl,
    this.bridgeName,
    this.autoConnect = false,
  });

  /// Reads configuration from compile-time `--dart-define` variables.
  factory MacremoteBootstrapConfig.fromEnvironment() {
    const rawUrl = String.fromEnvironment('MACREMOTE_BRIDGE_URL');
    const rawName = String.fromEnvironment('MACREMOTE_BRIDGE_NAME');
    const autoConnect = bool.fromEnvironment(
      'MACREMOTE_AUTO_CONNECT',
      defaultValue: false,
    );

    final url = rawUrl.trim();
    if (url.isEmpty) {
      return const MacremoteBootstrapConfig(
        bridgeUrl: null,
        bridgeName: null,
        autoConnect: false,
      );
    }

    final name = rawName.trim().isEmpty ? 'Macremote' : rawName.trim();
    return MacremoteBootstrapConfig(
      bridgeUrl: url,
      bridgeName: name,
      autoConnect: autoConnect,
    );
  }

  /// Whether a valid bootstrap configuration is present and enabled.
  bool get isConfigured =>
      bridgeUrl != null && bridgeUrl!.trim().isNotEmpty && autoConnect;
}

/// Parsed endpoint information for bootstrapping a bridge connection.
class BootstrapEndpoint {
  final String host;
  final int port;
  final bool useSsl;
  final String wsUrl;

  const BootstrapEndpoint({
    required this.host,
    required this.port,
    required this.useSsl,
    required this.wsUrl,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BootstrapEndpoint &&
          runtimeType == other.runtimeType &&
          host == other.host &&
          port == other.port &&
          useSsl == other.useSsl &&
          wsUrl == other.wsUrl;

  @override
  int get hashCode => Object.hash(host, port, useSsl, wsUrl);

  @override
  String toString() =>
      'BootstrapEndpoint(host: $host, port: $port, useSsl: $useSsl, wsUrl: $wsUrl)';
}

/// Parses a raw bridge URL into a validated [BootstrapEndpoint].
///
/// Supports:
/// - `ws://[2408:824e:158d:5a80:875:122:45bf:5441]:8766`
/// - `[2408:824e:158d:5a80:875:122:45bf:5441]:8766`
/// - `ws://192.168.1.100:8765`
/// - `wss://example.com:8765`
BootstrapEndpoint? parseBootstrapEndpoint(String rawUrl) {
  var trimmed = rawUrl.trim();
  if (trimmed.isEmpty) return null;

  // Reject explicit invalid port 0
  if (trimmed.contains(RegExp(r':0+(/|$)'))) {
    return null;
  }

  // If a scheme is explicitly provided, verify it is a supported protocol
  final schemeIndex = trimmed.indexOf('://');
  if (schemeIndex != -1) {
    final scheme = trimmed.substring(0, schemeIndex).toLowerCase();
    if (scheme != 'ws' &&
        scheme != 'wss' &&
        scheme != 'http' &&
        scheme != 'https') {
      return null;
    }
  }

  // Handle bare host:port or [ipv6]:port by prepending ws://
  if (!trimmed.startsWith('ws://') &&
      !trimmed.startsWith('wss://') &&
      !trimmed.startsWith('http://') &&
      !trimmed.startsWith('https://')) {
    trimmed = 'ws://$trimmed';
  } else if (trimmed.startsWith('http://')) {
    trimmed = 'ws://${trimmed.substring(7)}';
  } else if (trimmed.startsWith('https://')) {
    trimmed = 'wss://${trimmed.substring(8)}';
  }

  final Uri uri;
  try {
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null || parsed.host.isEmpty) return null;
    uri = parsed;
  } catch (_) {
    return null;
  }

  if (uri.hasPort && (uri.port <= 0 || uri.port > 65535)) return null;

  final useSsl = uri.scheme == 'wss';
  final host = normalizeHostInput(uri.host);
  if (host.isEmpty) return null;

  final port = uri.hasPort ? uri.port : (useSsl ? 443 : 8765);
  if (port <= 0 || port > 65535) return null;

  final wsUrl = formatUriOrigin(
    scheme: useSsl ? 'wss' : 'ws',
    host: host,
    port: port,
  );

  return BootstrapEndpoint(
    host: host,
    port: port,
    useSsl: useSsl,
    wsUrl: wsUrl,
  );
}

/// Key in [SharedPreferences] where the default bridge URL is stored.
const String kPrefKeyBridgeUrl = 'bridge_url';

/// Bootstraps preset Macremote bridge configuration into [SharedPreferences]
/// and [MachineManagerService] on fresh install.
///
/// Rules:
/// 1. If [config] is unconfigured or disabled, returns `false` (no-op).
/// 2. If [kPrefKeyBridgeUrl] is already present in [prefs], does NOT overwrite it.
/// 3. If a machine with matching endpoint identity exists in [machineManager], does NOT overwrite or duplicate it.
/// 4. On fresh install, seeds [kPrefKeyBridgeUrl] and adds the favorite [Machine] into [machineManager].
Future<bool> bootstrapMacremoteBridge({
  required SharedPreferences prefs,
  required MachineManagerService machineManager,
  MacremoteBootstrapConfig? config,
  Uuid? uuid,
}) async {
  final effectiveConfig = config ?? MacremoteBootstrapConfig.fromEnvironment();
  if (!effectiveConfig.isConfigured) {
    return false;
  }

  final parsed = parseBootstrapEndpoint(effectiveConfig.bridgeUrl!);
  if (parsed == null) {
    logger.warning(
      '[MacremoteBootstrap] Failed to parse bridge URL: ${effectiveConfig.bridgeUrl}',
    );
    return false;
  }

  // 1. Seed bridge_url preference if no existing preference is set
  final existingUrl = prefs.getString(kPrefKeyBridgeUrl);
  final hasUserBridgeUrl = existingUrl != null && existingUrl.trim().isNotEmpty;
  if (!hasUserBridgeUrl) {
    await prefs.setString(kPrefKeyBridgeUrl, parsed.wsUrl);
    logger.info(
      '[MacremoteBootstrap] Seeded $kPrefKeyBridgeUrl preference: ${parsed.wsUrl}',
    );
  }

  // 2. Ensure machines are loaded in MachineManagerService
  await machineManager.init();
  final existingMachine = machineManager.findByHostPort(
    parsed.host,
    parsed.port,
  );

  // 3. Seed favorite machine if no machine exists for this endpoint
  if (existingMachine == null && !hasUserBridgeUrl) {
    final effectiveUuid = uuid ?? const Uuid();
    final machine = Machine(
      id: effectiveUuid.v4(),
      name: effectiveConfig.bridgeName ?? 'Macremote',
      host: parsed.host,
      port: parsed.port,
      useSsl: parsed.useSsl,
      connectionMode: parsed.useSsl
          ? BridgeConnectionMode.secureOnly
          : BridgeConnectionMode.standardOnly,
      hasResolvedTransport: true,
      isFavorite: true,
    );
    await machineManager.addMachine(machine);
    logger.info(
      '[MacremoteBootstrap] Seeded favorite machine: ${machine.displayName} (${parsed.wsUrl})',
    );
  }

  return true;
}
