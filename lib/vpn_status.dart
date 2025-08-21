///Stages of vpn connections
enum VPNStatus {
  prepare('prepare'),
  authenticating('authenticating'),
  connecting('connecting'),
  authentication('authentication'),
  connected('connected'),
  disconnected('disconnected'),
  disconnecting('disconnecting'),
  denied('denied'),
  error('error'),
  waitConnection('wait_connection'),
  vpnGenerateConfig('vpn_generate_config'),
  getConfig('get_config'),
  tcpConnect('tcp_connect'),
  udpConnect('udp_connect'),
  assignIp('assign_ip'),
  resolve('resolve'),
  exiting('exiting'),
  unknown('unknown');

  final String id;

  const VPNStatus(this.id);

  @override
  String toString() {
    return id;
  }
}
