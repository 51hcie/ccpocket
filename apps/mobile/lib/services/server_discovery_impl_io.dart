import 'package:bonsoir/bonsoir.dart';

import '../core/logger.dart';

Future<BonsoirDiscovery> startDiscovery({
  required void Function(String name, String host, int port, bool authRequired)
  onResolved,
  required void Function(String host, int port) onLost,
}) async {
  final discovery = BonsoirDiscovery(type: '_ccpocket._tcp');
  await discovery.ready;

  discovery.eventStream?.listen((event) {
    switch (event.type) {
      case BonsoirDiscoveryEventType.discoveryServiceResolved:
        final service = event.service;
        if (service is ResolvedBonsoirService) {
          final host = service.host ?? service.name;
          onResolved(
            service.name,
            host,
            service.port,
            service.attributes['auth'] == 'required',
          );
        }
      case BonsoirDiscoveryEventType.discoveryServiceLost:
        final service = event.service;
        if (service != null) {
          final host = service is ResolvedBonsoirService
              ? (service.host ?? service.name)
              : service.name;
          onLost(host, service.port);
        }
      default:
        break;
    }
  });

  await discovery.start();
  logger.info('[discovery] Started scanning for _ccpocket._tcp');
  return discovery;
}

Future<void> stopDiscovery(dynamic discovery) async {
  if (discovery is BonsoirDiscovery && !discovery.isStopped) {
    await discovery.stop();
  }
}
