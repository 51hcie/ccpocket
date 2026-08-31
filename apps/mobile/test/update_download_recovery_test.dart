import 'dart:async';
import 'dart:io';

import 'package:ccpocket/services/android_bridge_update_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Directory temp;
  final bytes = [1, 2, 3, 4];
  BridgeReleaseManifest manifest({String? hash}) => BridgeReleaseManifest(
    versionCode: 230,
    versionName: 'test',
    size: bytes.length,
    sha256: hash ?? sha256.convert(bytes).toString(),
    buildTime: '',
    downloadPath: '/api/update/download',
  );
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('update-test-');
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test(
    'real HTTP stalled transfer aborts and retries without partial APK',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = http.Client();
      var attempts = 0;
      server.listen((request) async {
        attempts++;
        request.response.contentLength = bytes.length;
        if (attempts == 1) {
          request.response.add([1]);
          await request.response.flush();
        } else {
          request.response.add(bytes);
          await request.response.close();
        }
      });
      try {
        final service = AndroidBridgeUpdateService(
          client: client,
          temporaryDirectory: () async => temp,
          downloadTimeout: const Duration(milliseconds: 150),
        );
        final path = await service.downloadAndVerifyApk(
          bridgeUrl: 'ws://127.0.0.1:${server.port}',
          manifest: manifest(),
        );
        expect(attempts, 2);
        expect(await File(path).readAsBytes(), bytes);
        expect(await temp.list().length, 1);
      } finally {
        client.close();
        await server.close(force: true);
      }
    },
  );

  test(
    'header timeout retries on current route and verifies complete APK',
    () async {
      final urls = <String>[];
      Future<void>? aborted;
      final service = AndroidBridgeUpdateService(
        temporaryDirectory: () async => temp,
        downloadTimeout: const Duration(milliseconds: 30),
        client: MockClient.streaming((request, _) async {
          urls.add(request.url.host);
          if (urls.length == 1) {
            aborted = (request as http.Abortable).abortTrigger;
            return Completer<http.StreamedResponse>().future;
          }
          return http.StreamedResponse(Stream.value(bytes), 200);
        }),
      );
      final path = await service.downloadAndVerifyApk(
        bridgeUrl: 'ws://old-route:8766',
        manifest: manifest(),
        retryBridgeUrl: () async => 'ws://new-route:8766',
      );
      expect(urls, ['old-route', 'new-route']);
      await aborted;
      expect(await File(path).readAsBytes(), bytes);
    },
  );

  test(
    'stalled bodies stop after three attempts and remove partial files',
    () async {
      var attempts = 0;
      var cancellations = 0;
      final service = AndroidBridgeUpdateService(
        temporaryDirectory: () async => temp,
        downloadTimeout: const Duration(milliseconds: 30),
        client: MockClient.streaming((_, __) async {
          attempts++;
          final stream = StreamController<List<int>>(
            onCancel: () {
              cancellations++;
            },
          );
          stream.add([1]);
          return http.StreamedResponse(stream.stream, 200);
        }),
      );
      await expectLater(
        service.downloadAndVerifyApk(
          bridgeUrl: 'ws://route:8766',
          manifest: manifest(),
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(attempts, 3);
      expect(cancellations, 3);
      expect(await temp.list().toList(), isEmpty);
    },
  );

  test(
    'successful repeated downloads reuse one package; bad retry preserves it',
    () async {
      final service = AndroidBridgeUpdateService(
        temporaryDirectory: () async => temp,
        client: MockClient.streaming(
          (_, _) async => http.StreamedResponse(Stream.value(bytes), 200),
        ),
      );
      final first = await service.downloadAndVerifyApk(
        bridgeUrl: 'ws://route:8766',
        manifest: manifest(),
      );
      final second = await service.downloadAndVerifyApk(
        bridgeUrl: 'ws://route:8766',
        manifest: manifest(),
      );
      expect(first, second);
      expect(await temp.list().length, 1);
      await expectLater(
        service.downloadAndVerifyApk(
          bridgeUrl: 'ws://route:8766',
          manifest: manifest(hash: 'bad'),
        ),
        throwsA(isA<Exception>()),
      );
      expect(await File(first).readAsBytes(), bytes);
      expect(await temp.list().length, 1);
    },
  );

  test(
    'cancel during real stalled body aborts without retry or residue',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = http.Client();
      final cancellation = UpdateDownloadCancellation();
      var requests = 0;
      server.listen((request) async {
        requests++;
        request.response.bufferOutput = false;
        request.response.contentLength = 4;
        request.response.add([1]);
        await request.response.flush();
      });
      try {
        final service = AndroidBridgeUpdateService(
          client: client,
          temporaryDirectory: () async => temp,
        );
        await expectLater(
          service
              .downloadAndVerifyApk(
                bridgeUrl: 'ws://127.0.0.1:${server.port}',
                manifest: manifest(),
                cancellation: cancellation,
                onProgress: (received, _) {
                  if (received > 0) cancellation.cancel();
                },
              )
              .timeout(const Duration(seconds: 3)),
          throwsA(isA<UpdateDownloadCancelled>()),
        );
        expect(requests, 1);
        expect(await temp.list().toList(), isEmpty);
      } finally {
        client.close();
        await server.close(force: true);
      }
    },
  );

  test('cancel before start sends nothing', () async {
    final token = UpdateDownloadCancellation()..cancel();
    var requests = 0;
    final service = AndroidBridgeUpdateService(
      client: MockClient((_) async {
        requests++;
        return http.Response('', 200);
      }),
    );
    await expectLater(
      service.downloadAndVerifyApk(
        bridgeUrl: 'ws://route:8766',
        manifest: manifest(),
        cancellation: token,
      ),
      throwsA(isA<UpdateDownloadCancelled>()),
    );
    expect(requests, 0);
  });

  for (final failure in ['hash', 'size', 'status']) {
    test('$failure failure is not retried or retained', () async {
      var attempts = 0;
      final service = AndroidBridgeUpdateService(
        temporaryDirectory: () async => temp,
        client: MockClient.streaming((_, __) async {
          attempts++;
          return http.StreamedResponse(
            Stream.value(failure == 'size' ? [1] : bytes),
            failure == 'status' ? 206 : 200,
          );
        }),
      );
      await expectLater(
        service.downloadAndVerifyApk(
          bridgeUrl: 'ws://route:8766',
          manifest: manifest(hash: failure == 'hash' ? 'bad' : null),
        ),
        throwsA(isA<Exception>()),
      );
      expect(attempts, 1);
      expect(await temp.list().toList(), isEmpty);
    });
  }
}
