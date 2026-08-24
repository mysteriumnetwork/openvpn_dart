import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openvpn_dart/openvpn_dart.dart';
import 'package:openvpn_dart/vpn_status.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('id.mysteriumvpn.openvpn_flutter/vpncontrol');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late OpenVPNDart openVpn;
  late List<MethodCall> calls;
  Object? statusResponse;
  Object? checkConfigurationResponse;
  String? failWith;

  setUp(() {
    openVpn = OpenVPNDart();
    calls = <MethodCall>[];
    statusResponse = 'disconnected';
    checkConfigurationResponse = true;
    failWith = null;

    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (failWith == call.method) {
        throw PlatformException(code: '-1', message: 'native said no');
      }
      switch (call.method) {
        case 'status':
          return statusResponse;
        case 'checkTunnelConfiguration':
          return checkConfigurationResponse;
        default:
          return null;
      }
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('getVPNStatus', () {
    test('maps the native status string', () async {
      statusResponse = 'connected';

      expect(await openVpn.getVPNStatus(), ConnectionStatus.connected);
    });

    test('treats a missing status as disconnected', () async {
      statusResponse = null;

      expect(await openVpn.getVPNStatus(), ConnectionStatus.disconnected);
    });

    test('maps anything unrecognised to unknown', () async {
      statusResponse = 'reconnecting';

      expect(await openVpn.getVPNStatus(), ConnectionStatus.unknown);
    });
  });

  group('isConnected', () {
    test('is true only for the connected state', () async {
      statusResponse = 'connected';
      expect(await openVpn.isConnected(), isTrue);

      statusResponse = 'connecting';
      expect(await openVpn.isConnected(), isFalse);
    });
  });

  group('connect', () {
    test('refuses to run before initialize', () async {
      expect(openVpn.connect('client\n'), throwsA(isA<StateError>()));
      expect(calls.where((c) => c.method == 'connect'), isEmpty);
    });

    test('forwards the configuration once initialized', () async {
      await openVpn.initialize();
      await openVpn.connect('client\nremote 192.0.2.1\n');

      final call = calls.firstWhere((c) => c.method == 'connect');
      expect(call.arguments, {'config': 'client\nremote 192.0.2.1\n'});
    });

    test('surfaces a native rejection as an ArgumentError', () async {
      await openVpn.initialize();
      failWith = 'connect';

      expect(openVpn.connect('bad config'), throwsA(isA<ArgumentError>()));
    });
  });

  group('initialize', () {
    test('passes the NetworkExtension identifiers through', () async {
      await openVpn.initialize(
        providerBundleIdentifier: 'network.mysterium.ext',
        localizedDescription: 'Mysterium VPN',
      );

      final call = calls.firstWhere((c) => c.method == 'initialize');
      expect(call.arguments, {
        'providerBundleIdentifier': 'network.mysterium.ext',
        'localizedDescription': 'Mysterium VPN',
      });
    });

    test('wraps a native failure', () async {
      failWith = 'initialize';

      expect(openVpn.initialize(), throwsA(isA<Exception>()));
    });
  });

  group('tunnel configuration', () {
    test('checkTunnelConfiguration reports the native answer', () async {
      checkConfigurationResponse = true;
      expect(await openVpn.checkTunnelConfiguration(), isTrue);

      checkConfigurationResponse = null;
      expect(await openVpn.checkTunnelConfiguration(), isFalse);
    });

    test('checkTunnelConfiguration surfaces a native failure', () async {
      failWith = 'checkTunnelConfiguration';

      expect(openVpn.checkTunnelConfiguration(), throwsA(isA<Exception>()));
    });

    test('setupTunnel and removeTunnelConfiguration delegate to the platform', () async {
      await openVpn.setupTunnel();
      await openVpn.removeTunnelConfiguration();

      expect(calls.map((c) => c.method), containsAll(['setupTunnel', 'removeTunnelConfiguration']));
    });

    test('setupTunnel surfaces a native failure', () async {
      failWith = 'setupTunnel';

      expect(openVpn.setupTunnel(), throwsA(isA<Exception>()));
    });
  });

  group('disconnect', () {
    test('asks the platform to stop the tunnel', () async {
      openVpn.disconnect();
      await Future<void>.delayed(Duration.zero);

      expect(calls.map((c) => c.method), contains('disconnect'));
    });
  });

  group('ensureTapDriver', () {
    test('is a no-op off Windows', () async {
      expect(await openVpn.ensureTapDriver(), isTrue);
      expect(calls.where((c) => c.method == 'ensureTapDriver'), isEmpty);
    });
  });

  group('statusStream', () {
    const statusChannel = EventChannel('id.mysteriumvpn.openvpn_flutter/vpnstatus');

    Future<List<ConnectionStatus>> streamOf(List<String> events) {
      messenger.setMockStreamHandler(
        statusChannel,
        MockStreamHandler.inline(
          onListen: (arguments, sink) {
            for (final event in events) {
              sink.success(event);
            }
            sink.endOfStream();
          },
        ),
      );
      return openVpn.statusStream().toList();
    }

    tearDown(() => messenger.setMockStreamHandler(statusChannel, null));

    test('maps native events and drops consecutive duplicates', () async {
      expect(await streamOf(['connecting', 'connecting', 'connected']), [
        ConnectionStatus.connecting,
        ConnectionStatus.connected,
      ]);
    });

    test('normalises casing and whitespace', () async {
      expect(await streamOf([' CONNECTED ']), [ConnectionStatus.connected]);
    });

    test('treats idle, invalid and empty as disconnected', () async {
      expect(await streamOf(['idle', 'invalid', '']), [
        ConnectionStatus.disconnected,
        ConnectionStatus.disconnected,
        ConnectionStatus.disconnected,
      ]);
    });
  });
}
