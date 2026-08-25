import 'package:ccpocket/utils/network_endpoint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('network endpoint formatting', () {
    test('keeps IPv4 and DNS hosts unchanged', () {
      expect(formatHostPort('192.168.1.1', 9000), '192.168.1.1:9000');
      expect(
        formatUriOrigin(scheme: 'wss', host: 'bridge.example.com', port: 443),
        'wss://bridge.example.com:443',
      );
    });

    test('brackets IPv6 hosts and strips input brackets', () {
      expect(formatHostPort('::1', 8765), '[::1]:8765');
      expect(formatHostPort('[::1]', 8765), '[::1]:8765');
      expect(normalizeHostInput(' [::1] '), '::1');
      expect(
        formatHostPort('2408:824e:158d:5a80:875:122:45bf:5441', 8766),
        '[2408:824e:158d:5a80:875:122:45bf:5441]:8766',
      );
      expect(
        formatUriOrigin(
          scheme: 'http',
          host: '2408:824e:158d:5a80:875:122:45bf:5441',
          port: 8766,
        ),
        'http://[2408:824e:158d:5a80:875:122:45bf:5441]:8766',
      );
      expect(
        formatUriOrigin(
          scheme: 'wss',
          host: '[2408:824e:158d:5a80:875:122:45bf:5441]',
          port: 8766,
        ),
        'wss://[2408:824e:158d:5a80:875:122:45bf:5441]:8766',
      );
    });

    test('encodes an IPv6 zone separator only in URI output', () {
      expect(normalizeHostInput('[fe80::1%25en0]'), 'fe80::1%en0');
      expect(
        formatUriOrigin(scheme: 'ws', host: 'fe80::1%en0', port: 8765),
        'ws://[fe80::1%25en0]:8765',
      );
    });

    test('canonical identity ignores host case but preserves zone case', () {
      expect(
        endpointIdentityKey('[FDBD:DC01::1]', 8765),
        '[fdbd:dc01::1]:8765',
      );
      expect(endpointIdentityKey('FE80::1%En0', 8765), '[fe80::1%En0]:8765');
    });

    test('canonical identity normalizes expanded and embedded IPv6 forms', () {
      expect(
        endpointIdentityKey('0:0:0:0:0:0:0:1', 8765),
        endpointIdentityKey('::1', 8765),
      );
      expect(
        endpointIdentityKey('::ffff:192.0.2.128', 8765),
        endpointIdentityKey('0:0:0:0:0:ffff:c000:0280', 8765),
      );
    });

    test('omits the port when one is not supplied', () {
      expect(formatUriOrigin(scheme: 'https', host: '::1'), 'https://[::1]');
    });
  });

  group('isLoopbackOrLocalhost', () {
    test('identifies loopback IPv4 and localhost aliases', () {
      expect(isLoopbackOrLocalhost('127.0.0.1'), isTrue);
      expect(isLoopbackOrLocalhost('127.0.0.2'), isTrue);
      expect(isLoopbackOrLocalhost('127.10.20.30'), isTrue);
      expect(isLoopbackOrLocalhost('localhost'), isTrue);
      expect(isLoopbackOrLocalhost('LOCALHOST'), isTrue);
      expect(isLoopbackOrLocalhost('0.0.0.0'), isTrue);
    });

    test('identifies loopback IPv6 literals and forms', () {
      expect(isLoopbackOrLocalhost('::1'), isTrue);
      expect(isLoopbackOrLocalhost('[::1]'), isTrue);
      expect(isLoopbackOrLocalhost('0:0:0:0:0:0:0:1'), isTrue);
      expect(isLoopbackOrLocalhost('::'), isTrue);
      expect(isLoopbackOrLocalhost('[::]'), isTrue);
    });

    test('does not classify LAN, public IPv4, IPv6, or domains as loopback', () {
      expect(isLoopbackOrLocalhost('192.168.1.1'), isFalse);
      expect(isLoopbackOrLocalhost('10.0.0.1'), isFalse);
      expect(isLoopbackOrLocalhost('172.16.0.1'), isFalse);
      expect(isLoopbackOrLocalhost('2408:824e:158d:5a80:875:122:45bf:5441'), isFalse);
      expect(isLoopbackOrLocalhost('[2408:824e:158d:5a80:875:122:45bf:5441]'), isFalse);
      expect(isLoopbackOrLocalhost('macremote.local'), isFalse);
      expect(isLoopbackOrLocalhost('api.anycoding.com'), isFalse);
    });
  });
}
