import 'package:ccpocket/models/machine.dart';
import 'package:ccpocket/services/macremote_bootstrap_service.dart';
import 'package:ccpocket/services/machine_manager_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class _FakeSecureStorage implements FlutterSecureStorage {
  final values = <String, String>{};

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const targetIpv6Url = 'ws://[2408:824e:158d:5a80:875:122:45bf:5441]:8766';
  const targetIpv6Host = '2408:824e:158d:5a80:875:122:45bf:5441';
  const targetPort = 8766;
  const targetName = 'Macremote';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('parseBootstrapEndpoint', () {
    test('parses bracketed global IPv6 literal with ws:// scheme', () {
      final endpoint = parseBootstrapEndpoint(targetIpv6Url);
      expect(endpoint, isNotNull);
      expect(endpoint!.host, targetIpv6Host);
      expect(endpoint.port, targetPort);
      expect(endpoint.useSsl, isFalse);
      expect(endpoint.wsUrl, targetIpv6Url);
    });

    test('parses bare bracketed IPv6 host:port without scheme', () {
      final endpoint = parseBootstrapEndpoint('[$targetIpv6Host]:$targetPort');
      expect(endpoint, isNotNull);
      expect(endpoint!.host, targetIpv6Host);
      expect(endpoint.port, targetPort);
      expect(endpoint.useSsl, isFalse);
      expect(endpoint.wsUrl, targetIpv6Url);
    });

    test('parses secure wss:// URL', () {
      final endpoint = parseBootstrapEndpoint('wss://bridge.example.com:8765');
      expect(endpoint, isNotNull);
      expect(endpoint!.host, 'bridge.example.com');
      expect(endpoint.port, 8765);
      expect(endpoint.useSsl, isTrue);
      expect(endpoint.wsUrl, 'wss://bridge.example.com:8765');
    });

    test('parses http/https URLs and converts to ws/wss', () {
      final httpEndpoint = parseBootstrapEndpoint('http://192.168.1.50:8765');
      expect(httpEndpoint, isNotNull);
      expect(httpEndpoint!.useSsl, isFalse);
      expect(httpEndpoint.wsUrl, 'ws://192.168.1.50:8765');

      final httpsEndpoint = parseBootstrapEndpoint(
        'https://[$targetIpv6Host]:$targetPort',
      );
      expect(httpsEndpoint, isNotNull);
      expect(httpsEndpoint!.useSsl, isTrue);
      expect(
        httpsEndpoint.wsUrl,
        'wss://[2408:824e:158d:5a80:875:122:45bf:5441]:8766',
      );
    });

    test('handles default port when omitted', () {
      final standard = parseBootstrapEndpoint('ws://192.168.1.50');
      expect(standard, isNotNull);
      expect(standard!.port, 8765);

      final secure = parseBootstrapEndpoint('wss://secure.example.com');
      expect(secure, isNotNull);
      expect(secure!.port, 443);
    });

    test('returns null for empty or invalid inputs', () {
      expect(parseBootstrapEndpoint(''), isNull);
      expect(parseBootstrapEndpoint('   '), isNull);
      expect(parseBootstrapEndpoint('invalid://bad:url'), isNull);
      expect(parseBootstrapEndpoint('ftp://192.168.1.1:8765'), isNull);
      expect(parseBootstrapEndpoint('ws://192.168.1.1:0'), isNull);
      expect(parseBootstrapEndpoint('ws://192.168.1.1:65536'), isNull);
    });
  });

  group('MacremoteBootstrapConfig', () {
    test('defaults to unconfigured when environment defines are empty', () {
      final config = MacremoteBootstrapConfig.fromEnvironment();
      expect(config.isConfigured, isFalse);
    });

    test('recognizes configured state with valid parameters', () {
      const config = MacremoteBootstrapConfig(
        bridgeUrl: targetIpv6Url,
        bridgeName: targetName,
        autoConnect: true,
      );
      expect(config.isConfigured, isTrue);
      expect(config.bridgeUrl, targetIpv6Url);
      expect(config.bridgeName, targetName);
      expect(config.autoConnect, isTrue);
    });

    test('isConfigured is false when autoConnect is disabled', () {
      const config = MacremoteBootstrapConfig(
        bridgeUrl: targetIpv6Url,
        bridgeName: targetName,
        autoConnect: false,
      );
      expect(config.isConfigured, isFalse);
    });
  });

  group('bootstrapMacremoteBridge', () {
    test(
      'seeds bridge_url preference and favorite Machine on fresh install',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final secureStorage = _FakeSecureStorage();
        final manager = MachineManagerService(prefs, secureStorage);

        const config = MacremoteBootstrapConfig(
          bridgeUrl: targetIpv6Url,
          bridgeName: targetName,
          autoConnect: true,
        );

        final result = await bootstrapMacremoteBridge(
          prefs: prefs,
          machineManager: manager,
          config: config,
          uuid: const Uuid(),
        );

        expect(result, isTrue);
        expect(prefs.getString('bridge_url'), targetIpv6Url);

        final machines = manager.currentMachines;
        expect(machines, hasLength(1));
        final seeded = machines.single;
        expect(seeded.name, targetName);
        expect(seeded.host, targetIpv6Host);
        expect(seeded.port, targetPort);
        expect(seeded.useSsl, isFalse);
        expect(seeded.connectionMode, BridgeConnectionMode.standardOnly);
        expect(seeded.hasResolvedTransport, isTrue);
        expect(seeded.isFavorite, isTrue);
        expect(seeded.hasApiKey, isFalse);
        expect(seeded.wsUrl, targetIpv6Url);
        expect(seeded.httpUrl, 'http://[$targetIpv6Host]:$targetPort');

        manager.dispose();
      },
    );

    test('does not overwrite existing user bridge_url and machines', () async {
      const userCustomUrl = 'ws://192.168.1.100:8765';
      SharedPreferences.setMockInitialValues({'bridge_url': userCustomUrl});
      final prefs = await SharedPreferences.getInstance();
      final secureStorage = _FakeSecureStorage();
      final manager = MachineManagerService(prefs, secureStorage);
      await manager.init();

      const config = MacremoteBootstrapConfig(
        bridgeUrl: targetIpv6Url,
        bridgeName: targetName,
        autoConnect: true,
      );

      final result = await bootstrapMacremoteBridge(
        prefs: prefs,
        machineManager: manager,
        config: config,
      );

      expect(result, isTrue);
      // Existing user bridge_url must NOT be overwritten
      expect(prefs.getString('bridge_url'), userCustomUrl);
      // No new machine seeded when user already configured bridge_url
      expect(manager.currentMachines, isEmpty);

      manager.dispose();
    });

    test(
      'is idempotent on repeated launches and does not create duplicates',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final secureStorage = _FakeSecureStorage();
        final manager = MachineManagerService(prefs, secureStorage);

        const config = MacremoteBootstrapConfig(
          bridgeUrl: targetIpv6Url,
          bridgeName: targetName,
          autoConnect: true,
        );

        // Launch 1 (fresh install)
        final res1 = await bootstrapMacremoteBridge(
          prefs: prefs,
          machineManager: manager,
          config: config,
        );
        expect(res1, isTrue);
        expect(prefs.getString('bridge_url'), targetIpv6Url);
        expect(manager.currentMachines, hasLength(1));
        final originalMachineId = manager.currentMachines.single.id;

        // Launch 2 (subsequent app start)
        final res2 = await bootstrapMacremoteBridge(
          prefs: prefs,
          machineManager: manager,
          config: config,
        );
        expect(res2, isTrue);
        expect(prefs.getString('bridge_url'), targetIpv6Url);
        expect(manager.currentMachines, hasLength(1));
        expect(manager.currentMachines.single.id, originalMachineId);

        manager.dispose();
      },
    );

    test('migrates unusable loopback 127.0.0.1 endpoint and machine in AnyCoding builds', () async {
      SharedPreferences.setMockInitialValues({
        'bridge_url': 'ws://127.0.0.1:8765',
      });
      final prefs = await SharedPreferences.getInstance();
      final secureStorage = _FakeSecureStorage();
      final manager = MachineManagerService(prefs, secureStorage);
      await manager.init();

      // Seed a legacy loopback machine
      await manager.addMachine(
        const Machine(
          id: 'legacy-loopback-1',
          name: 'Local Bridge',
          host: '127.0.0.1',
          port: 8765,
          useSsl: false,
          isFavorite: true,
        ),
      );

      const config = MacremoteBootstrapConfig(
        bridgeUrl: targetIpv6Url,
        bridgeName: 'AnyCoding Mac',
        autoConnect: true,
      );

      final result = await bootstrapMacremoteBridge(
        prefs: prefs,
        machineManager: manager,
        config: config,
        isAnyCodingBrand: true,
      );

      expect(result, isTrue);
      // bridge_url should be migrated from 127.0.0.1 to preset IPv6 URL
      expect(prefs.getString('bridge_url'), targetIpv6Url);

      // The loopback machine should be migrated to preset endpoint
      expect(manager.currentMachines, hasLength(1));
      final migrated = manager.currentMachines.single;
      expect(migrated.id, 'legacy-loopback-1');
      expect(migrated.name, 'AnyCoding Mac');
      expect(migrated.host, targetIpv6Host);
      expect(migrated.port, targetPort);
      expect(migrated.wsUrl, targetIpv6Url);
      expect(migrated.isFavorite, isTrue);

      manager.dispose();
    });

    test(
      'migrates the previously shipped AnyCoding IPv6 preset on upgrade',
      () async {
        const retiredUrl = 'ws://[2408:824e:1562:9420::6f1]:8766';
        const retiredHost = '2408:824e:1562:9420::6f1';
        SharedPreferences.setMockInitialValues({'bridge_url': retiredUrl});
        final prefs = await SharedPreferences.getInstance();
        final secureStorage = _FakeSecureStorage();
        final manager = MachineManagerService(prefs, secureStorage);
        await manager.init();

        await manager.addMachine(
          const Machine(
            id: 'retired-anycoding-preset',
            name: 'AnyCoding Mac',
            host: retiredHost,
            port: targetPort,
            useSsl: false,
            isFavorite: true,
          ),
        );

        const config = MacremoteBootstrapConfig(
          bridgeUrl: targetIpv6Url,
          bridgeName: 'AnyCoding Mac',
          autoConnect: true,
        );

        final result = await bootstrapMacremoteBridge(
          prefs: prefs,
          machineManager: manager,
          config: config,
          isAnyCodingBrand: true,
        );

        expect(result, isTrue);
        expect(prefs.getString('bridge_url'), targetIpv6Url);
        expect(manager.currentMachines, hasLength(1));
        final migrated = manager.currentMachines.single;
        expect(migrated.id, 'retired-anycoding-preset');
        expect(migrated.host, targetIpv6Host);
        expect(migrated.port, targetPort);
        expect(migrated.wsUrl, targetIpv6Url);
        expect(migrated.isFavorite, isTrue);

        manager.dispose();
      },
    );

    test('preserves genuine custom LAN endpoint in AnyCoding builds', () async {
      const customLanUrl = 'ws://192.168.1.188:8765';
      SharedPreferences.setMockInitialValues({'bridge_url': customLanUrl});
      final prefs = await SharedPreferences.getInstance();
      final secureStorage = _FakeSecureStorage();
      final manager = MachineManagerService(prefs, secureStorage);
      await manager.init();

      await manager.addMachine(
        const Machine(
          id: 'custom-lan-1',
          name: 'My Custom Server',
          host: '192.168.1.188',
          port: 8765,
          useSsl: false,
          isFavorite: true,
        ),
      );

      const config = MacremoteBootstrapConfig(
        bridgeUrl: targetIpv6Url,
        bridgeName: 'AnyCoding Mac',
        autoConnect: true,
      );

      final result = await bootstrapMacremoteBridge(
        prefs: prefs,
        machineManager: manager,
        config: config,
        isAnyCodingBrand: true,
      );

      expect(result, isTrue);
      // Genuine custom LAN URL must be preserved
      expect(prefs.getString('bridge_url'), customLanUrl);
      expect(manager.currentMachines, hasLength(1));
      expect(manager.currentMachines.single.host, '192.168.1.188');

      manager.dispose();
    });

    test(
      'deletes loopback machine when preset machine already exists',
      () async {
        SharedPreferences.setMockInitialValues({'bridge_url': targetIpv6Url});
        final prefs = await SharedPreferences.getInstance();
        final secureStorage = _FakeSecureStorage();
        final manager = MachineManagerService(prefs, secureStorage);
        await manager.init();

        await manager.addMachine(
          const Machine(
            id: 'preset-machine-1',
            name: 'AnyCoding Mac',
            host: targetIpv6Host,
            port: targetPort,
            useSsl: false,
            isFavorite: true,
          ),
        );
        await manager.addMachine(
          const Machine(
            id: 'legacy-loopback-2',
            name: 'Localhost',
            host: 'localhost',
            port: 8765,
            useSsl: false,
          ),
        );

        const config = MacremoteBootstrapConfig(
          bridgeUrl: targetIpv6Url,
          bridgeName: 'AnyCoding Mac',
          autoConnect: true,
        );

        final result = await bootstrapMacremoteBridge(
          prefs: prefs,
          machineManager: manager,
          config: config,
          isAnyCodingBrand: true,
        );

        expect(result, isTrue);
        expect(manager.currentMachines, hasLength(1));
        expect(manager.currentMachines.single.id, 'preset-machine-1');

        manager.dispose();
      },
    );

    test('restoreMacremotePresetConnection restores preset endpoint and favorite machine', () async {
      SharedPreferences.setMockInitialValues({
        'bridge_url': 'ws://10.0.0.99:8765',
      });
      final prefs = await SharedPreferences.getInstance();
      final secureStorage = _FakeSecureStorage();
      final manager = MachineManagerService(prefs, secureStorage);
      await manager.init();

      const config = MacremoteBootstrapConfig(
        bridgeUrl: targetIpv6Url,
        bridgeName: 'AnyCoding Mac',
        autoConnect: true,
      );

      final restoredUrl = await restoreMacremotePresetConnection(
        prefs: prefs,
        machineManager: manager,
        config: config,
      );

      expect(restoredUrl, targetIpv6Url);
      expect(prefs.getString('bridge_url'), targetIpv6Url);
      expect(manager.currentMachines, hasLength(1));
      expect(manager.currentMachines.single.host, targetIpv6Host);
      expect(manager.currentMachines.single.isFavorite, isTrue);

      manager.dispose();
    });
  });
}
