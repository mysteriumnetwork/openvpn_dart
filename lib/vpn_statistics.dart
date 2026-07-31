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
