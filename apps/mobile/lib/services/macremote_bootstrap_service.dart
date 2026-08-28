import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../constants/brand_config.dart';
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
/// - `ws://[2408:824e:1562:9420::6f1]:8766`
/// - `[2408:824e:1562:9420::6f1]:8766`
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
/// and [MachineManagerService] on fresh install or upgrades from legacy loopback endpoints.
///
/// Rules:
/// 1. If [config] is unconfigured or disabled, returns `false` (no-op).
/// 2. If in AnyCoding brand (`isAnyCodingBrand` or `BrandConfig.isAnyCoding`) and [kPrefKeyBridgeUrl]
///    is empty OR points to a clearly unusable legacy loopback host (e.g. 127.0.0.1, localhost, ::1),
///    migrates/seeds [kPrefKeyBridgeUrl] to the preset [parsed.wsUrl]. Genuine custom LAN/public endpoints are preserved.
/// 3. In AnyCoding brand, any legacy loopback [Machine] entries in [machineManager] are migrated/cleaned up.
/// 4. On fresh install, seeds [kPrefKeyBridgeUrl] and adds the favorite [Machine] into [machineManager].
Future<bool> bootstrapMacremoteBridge({
  required SharedPreferences prefs,
  required MachineManagerService machineManager,
  MacremoteBootstrapConfig? config,
  Uuid? uuid,
  bool? isAnyCodingBrand,
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

  final isAnyCoding = isAnyCodingBrand ?? BrandConfig.isAnyCoding;

  // 1. Seed or migrate bridge_url preference
  final existingUrl = prefs.getString(kPrefKeyBridgeUrl);
  final hasUserBridgeUrl = existingUrl != null && existingUrl.trim().isNotEmpty;
  var didMigrateUrl = false;

  if (!hasUserBridgeUrl) {
    await prefs.setString(kPrefKeyBridgeUrl, parsed.wsUrl);
    logger.info(
      '[MacremoteBootstrap] Seeded $kPrefKeyBridgeUrl preference: ${parsed.wsUrl}',
    );
  } else if (isAnyCoding) {
    final existingParsed = parseBootstrapEndpoint(existingUrl);
    final isLegacyLoopback =
        existingParsed != null && isLoopbackOrLocalhost(existingParsed.host);
    if (isLegacyLoopback) {
      await prefs.setString(kPrefKeyBridgeUrl, parsed.wsUrl);
      didMigrateUrl = true;
      logger.info(
        '[MacremoteBootstrap] Migrated legacy loopback $kPrefKeyBridgeUrl ($existingUrl) to preset: ${parsed.wsUrl}',
      );
    }
  }

  // 2. Ensure machines are loaded in MachineManagerService
  await machineManager.init();
  var existingPresetMachine = machineManager.findByHostPort(
    parsed.host,
    parsed.port,
  );

  // 3. In AnyCoding builds, migrate legacy loopback machine entries
  if (isAnyCoding) {
    final machines = List<Machine>.from(machineManager.currentMachines);
    for (final m in machines) {
      if (isLoopbackOrLocalhost(m.host)) {
        if (existingPresetMachine != null) {
          // Preset machine already exists, delete unusable loopback machine
          await machineManager.deleteMachine(m.id);
          logger.info(
            '[MacremoteBootstrap] Removed unusable legacy loopback machine: ${m.displayName} (${m.host}:${m.port})',
          );
        } else {
          // Migrate legacy loopback machine to preset endpoint
          final migratedMachine = m.copyWith(
            host: parsed.host,
            port: parsed.port,
            useSsl: parsed.useSsl,
            connectionMode: parsed.useSsl
                ? BridgeConnectionMode.secureOnly
                : BridgeConnectionMode.standardOnly,
            hasResolvedTransport: true,
            isFavorite: true,
            name: (m.name == null ||
                    m.name == 'Local Bridge' ||
                    m.name == 'Macremote' ||
                    m.name == 'AnyCoding Mac')
                ? (effectiveConfig.bridgeName ?? 'AnyCoding Mac')
                : m.name,
          );
          await machineManager.updateMachine(migratedMachine);
          existingPresetMachine = migratedMachine;
          logger.info(
            '[MacremoteBootstrap] Migrated legacy loopback machine ${m.id} to preset: ${migratedMachine.displayName} (${parsed.wsUrl})',
          );
        }
      }
    }
  }

  // 4. Seed favorite preset machine if no machine exists for this endpoint
  if (existingPresetMachine == null && (!hasUserBridgeUrl || didMigrateUrl)) {
    final effectiveUuid = uuid ?? const Uuid();
    final machine = Machine(
      id: effectiveUuid.v4(),
      name: effectiveConfig.bridgeName ?? (isAnyCoding ? 'AnyCoding Mac' : 'Macremote'),
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

/// Explicitly restores the AnyCoding preset connection into [SharedPreferences]
/// and [MachineManagerService], returning the restored preset URL.
Future<String?> restoreMacremotePresetConnection({
  required SharedPreferences prefs,
  required MachineManagerService machineManager,
  MacremoteBootstrapConfig? config,
}) async {
  final effectiveConfig = config ?? MacremoteBootstrapConfig.fromEnvironment();
  var bridgeUrl = effectiveConfig.bridgeUrl;
  if ((bridgeUrl == null || bridgeUrl.trim().isEmpty) && BrandConfig.isAnyCoding) {
    bridgeUrl = BrandConfig.defaultAnyCodingBridgeUrl;
  }
  if (bridgeUrl == null || bridgeUrl.trim().isEmpty) {
    return null;
  }
  final parsed = parseBootstrapEndpoint(bridgeUrl);
  if (parsed == null) return null;

  await prefs.setString(kPrefKeyBridgeUrl, parsed.wsUrl);

  await machineManager.init();
  var machine = machineManager.findByHostPort(parsed.host, parsed.port);
  if (machine != null) {
    if (!machine.isFavorite) {
      await machineManager.updateMachine(machine.copyWith(isFavorite: true));
    }
  } else {
    const uuid = Uuid();
    machine = Machine(
      id: uuid.v4(),
      name: effectiveConfig.bridgeName ??
          (BrandConfig.isAnyCoding ? 'AnyCoding Mac' : 'Macremote'),
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
  }

  logger.info(
    '[MacremoteBootstrap] Restored preset connection: ${machine.displayName} (${parsed.wsUrl})',
  );
  return parsed.wsUrl;
}

