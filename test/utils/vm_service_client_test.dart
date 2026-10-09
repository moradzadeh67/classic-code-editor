import 'package:borland_dart/utils/vm_service_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// Verifying that the HTTP VM Service URI printed by the Dart VM is translated
/// into a usable WebSocket endpoint is the foundation of the debugger's ability
/// to attach to a running isolate.
void main() {
  group('VmServiceClient.webSocketUriFor', () {
    test('maps an http service root to the /ws endpoint', () {
      expect(
        VmServiceClient.webSocketUriFor('http://127.0.0.1:1234/').toString(),
        'ws://127.0.0.1:1234/ws',
      );
    });

    test('adds the trailing slash when the URI omits it', () {
      expect(
        VmServiceClient.webSocketUriFor('http://127.0.0.1:1234').toString(),
        'ws://127.0.0.1:1234/ws',
      );
    });

    test('preserves an auth-code path segment', () {
      expect(
        VmServiceClient.webSocketUriFor('http://127.0.0.1:1234/AbCdEf=/')
            .toString(),
        'ws://127.0.0.1:1234/AbCdEf=/ws',
      );
    });

    test('uses the secure scheme for https endpoints', () {
      expect(
        VmServiceClient.webSocketUriFor('https://example.com/token/')
            .toString(),
        'wss://example.com/token/ws',
      );
    });
  });
}
