import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openvpn_dart/openvpn_dart.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('id.mysteriumvpn.openvpn_flutter/vpncontrol');
  final openVpn = OpenVPNDart();

  Object? statisticsResponse;
  var throwPlatformException = false;

  void mockChannel({bool implemented = true}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        if (call.method == 'tunnelStatistics') {
          if (!implemented) {
            throw MissingPluginException();
          }
          if (throwPlatformException) {
            throw PlatformException(code: '-1', message: 'not connected');
          }
          return statisticsResponse;
        }
        return null;
      },
    );
  }

  setUp(() {
    statisticsResponse = null;
    throwPlatformException = false;
    mockChannel();
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
  });

  group('tunnelStatistics', () {
    test('parses JSON on Android', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      statisticsResponse = jsonEncode({
        'totalDownload': 300,
        'totalUpload': 200,
        'latestHandshake': 0,
      });

      final stats = await openVpn.tunnelStatistics();

      expect(stats!.totalDownload, 300);
      expect(stats.totalUpload, 200);
    });

    test('parses JSON on iOS', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      statisticsResponse = jsonEncode({'totalDownload': 7, 'totalUpload': 3, 'latestHandshake': 0});

      expect((await openVpn.tunnelStatistics())!.totalDownload, 7);
    });

    test('parses the status file on Windows', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      statisticsResponse =
          'OpenVPN STATISTICS\nTCP/UDP read bytes,54321\nTCP/UDP write bytes,12345\nEND\n';

      final stats = await openVpn.tunnelStatistics();

      expect(stats!.totalDownload, 54321);
      expect(stats.totalUpload, 12345);
    });

    test('returns null when the platform returns null', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

      expect(await openVpn.tunnelStatistics(), isNull);
    });

    test('returns null when the platform reports an error', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      throwPlatformException = true;

      expect(await openVpn.tunnelStatistics(), isNull);
    });

    test('returns null when the platform has no implementation', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      mockChannel(implemented: false);

      expect(await openVpn.tunnelStatistics(), isNull);
    });
  });
}
