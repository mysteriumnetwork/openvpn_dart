import 'package:flutter_test/flutter_test.dart';
import 'package:openvpn_dart/vpn_statistics.dart';

void main() {
  group('VPNStatistics.fromJson', () {
    test('reads the counters the native side sends', () {
      final stats = VPNStatistics.fromJson({
        'totalDownload': 54321,
        'totalUpload': 12345,
        'latestHandshake': 0,
      });

      expect(stats.totalDownload, 54321);
      expect(stats.totalUpload, 12345);
      expect(stats.latestHandshake, 0);
    });

    test('defaults missing fields to zero', () {
      final stats = VPNStatistics.fromJson({});

      expect(stats.totalDownload, 0);
      expect(stats.totalUpload, 0);
      expect(stats.latestHandshake, 0);
    });

    test('accepts doubles, which JSON decoding can produce for whole numbers', () {
      final stats = VPNStatistics.fromJson({'totalDownload': 12.0, 'totalUpload': 8.0});

      expect(stats.totalDownload, 12);
      expect(stats.totalUpload, 8);
    });
  });

  group('VPNStatistics equality', () {
    test('two samples with the same counters compare equal', () {
      const a = VPNStatistics(totalDownload: 1, totalUpload: 2);
      const b = VPNStatistics(totalDownload: 1, totalUpload: 2);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a changed counter compares unequal', () {
      const a = VPNStatistics(totalDownload: 1, totalUpload: 2);

      expect(a, isNot(const VPNStatistics(totalDownload: 9, totalUpload: 2)));
    });
  });
}
