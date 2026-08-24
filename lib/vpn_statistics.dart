/// Cumulative traffic statistics for the current VPN session.
///
/// Shape mirrors `wireguard_dart`'s `TunnelStatistics` so apps can present OpenVPN and
/// WireGuard usage uniformly. [latestHandshake] has no meaning for OpenVPN and is always 0.
class VPNStatistics {
  /// Total bytes downloaded (received) this session.
  final int totalDownload;

  /// Total bytes uploaded (sent) this session.
  final int totalUpload;

  /// Epoch millis of the last handshake. Always 0 for OpenVPN (no equivalent).
  final int latestHandshake;

  const VPNStatistics({
    required this.totalDownload,
    required this.totalUpload,
    this.latestHandshake = 0,
  });

  factory VPNStatistics.fromJson(Map<String, dynamic> json) => VPNStatistics(
    totalDownload: (json['totalDownload'] as num?)?.toInt() ?? 0,
    totalUpload: (json['totalUpload'] as num?)?.toInt() ?? 0,
    latestHandshake: (json['latestHandshake'] as num?)?.toInt() ?? 0,
  );

  /// Parses OpenVPN's `--status` file (format version 1), as produced on Windows.
  ///
  /// Uses the `TCP/UDP` wire counters rather than `TUN/TAP`, which count plaintext
  /// bytes before encryption and so would not line up with what the other
  /// platforms report. Returns null when neither wire counter is present.
  static VPNStatistics? fromStatusFile(String status) {
    int? totalDownload;
    int? totalUpload;

    for (final rawLine in status.split('\n')) {
      final parts = rawLine.trim().split(',');
      if (parts.length < 2) {
        continue;
      }
      final value = int.tryParse(parts[1]);
      if (value == null) {
        continue;
      }
      if (parts[0] == 'TCP/UDP read bytes') {
        totalDownload = value;
      } else if (parts[0] == 'TCP/UDP write bytes') {
        totalUpload = value;
      }
    }

    if (totalDownload == null && totalUpload == null) {
      return null;
    }
    return VPNStatistics(totalDownload: totalDownload ?? 0, totalUpload: totalUpload ?? 0);
  }

  @override
  bool operator ==(Object other) =>
      other is VPNStatistics &&
      other.totalDownload == totalDownload &&
      other.totalUpload == totalUpload &&
      other.latestHandshake == latestHandshake;

  @override
  int get hashCode => Object.hash(totalDownload, totalUpload, latestHandshake);

  @override
  String toString() =>
      'VPNStatistics(down: $totalDownload, up: $totalUpload, handshake: $latestHandshake)';
}
