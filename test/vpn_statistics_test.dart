import 'package:flutter_test/flutter_test.dart';
import 'package:openvpn_dart/vpn_statistics.dart';

void main() {
  const status =
      'OpenVPN STATISTICS\n'
      'Updated,Sat Aug 24 12:00:00 2026\n'
      'TUN/TAP read bytes,111\n'
      'TUN/TAP write bytes,222\n'
      'TCP/UDP read bytes,54321\n'
      'TCP/UDP write bytes,12345\n'
      'Auth read bytes,999\n'
      'END\n';

  group('VPNStatistics.fromStatusFile', () {
    test('reads the wire byte counters', () {
      final stats = VPNStatistics.fromStatusFile(status);

      expect(stats!.totalDownload, 54321);
      expect(stats.totalUpload, 12345);
      expect(stats.latestHandshake, 0);
    });

    test('tolerates CRLF line endings', () {
      final stats = VPNStatistics.fromStatusFile(status.replaceAll('\n', '\r\n'));

      expect(stats!.totalDownload, 54321);
      expect(stats.totalUpload, 12345);
    });

    test('returns null for an empty payload', () {
      expect(VPNStatistics.fromStatusFile(''), isNull);
    });

    test('returns null when the wire counters are absent', () {
      expect(
        VPNStatistics.fromStatusFile('OpenVPN STATISTICS\nTUN/TAP read bytes,111\nEND\n'),
        isNull,
      );
    });
  });
}
