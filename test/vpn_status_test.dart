import 'package:flutter_test/flutter_test.dart';
import 'package:openvpn_dart/vpn_status.dart';

void main() {
  group('ConnectionStatus.fromString', () {
    test('maps every state the native side reports', () {
      expect(ConnectionStatus.fromString('connecting'), ConnectionStatus.connecting);
      expect(ConnectionStatus.fromString('connected'), ConnectionStatus.connected);
      expect(ConnectionStatus.fromString('disconnecting'), ConnectionStatus.disconnecting);
      expect(ConnectionStatus.fromString('disconnected'), ConnectionStatus.disconnected);
    });

    test('falls back to unknown rather than throwing on anything else', () {
      expect(ConnectionStatus.fromString(''), ConnectionStatus.unknown);
      expect(ConnectionStatus.fromString('CONNECTED'), ConnectionStatus.unknown);
      expect(ConnectionStatus.fromString('reconnecting'), ConnectionStatus.unknown);
    });
  });
}
