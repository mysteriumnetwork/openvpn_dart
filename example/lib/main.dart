import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:openvpn_dart/openvpn_dart.dart';
import 'package:openvpn_dart/vpn_statistics.dart';
import 'package:openvpn_dart/vpn_status.dart';
import 'package:permission_handler/permission_handler.dart';

final _messengerKey = GlobalKey<ScaffoldMessengerState>();

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpenVPN Dart',
      scaffoldMessengerKey: _messengerKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6C5CE7)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C5CE7),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const VpnHomePage(),
    );
  }
}

class VpnHomePage extends StatefulWidget {
  const VpnHomePage({super.key});

  @override
  State<VpnHomePage> createState() => _VpnHomePageState();
}

class _VpnHomePageState extends State<VpnHomePage> {
  final OpenVPNDart _vpn = OpenVPNDart();
  // Intentionally empty — each tester pastes their own .ovpn (use a per-device config to
  // avoid the multi-device single-session reconnect loop).
  final TextEditingController _configController = TextEditingController();

  StreamSubscription<ConnectionStatus>? _statusSub;
  Timer? _statsTimer;

  ConnectionStatus _status = ConnectionStatus.unknown;
  VPNStatistics? _stats;
  String? _initError;

  @override
  void initState() {
    super.initState();
    _statusSub = _vpn.statusStream().listen(_onStatusChanged);
    _initialize();
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _statusSub?.cancel();
    _configController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      await _vpn.initialize(
        providerBundleIdentifier: Platform.isIOS
            ? "com.mysteriumvpn.openvpnDartExample.VPNExtension"
            : "com.mysteriumvpn.openvpnDartExample.VPNMExtension",
        localizedDescription: "MYST Example OVPN",
      );
      // Reflect the current status on launch.
      final current = await _vpn.getVPNStatus();
      _onStatusChanged(current);
      if (mounted) setState(() => _initError = null);
    } catch (e) {
      if (mounted) setState(() => _initError = e.toString());
    }
  }

  void _onStatusChanged(ConnectionStatus status) {
    if (!mounted) return;
    // Live data-usage polling is only meaningful while the tunnel is up.
    if (status == ConnectionStatus.connected) {
      setState(() => _status = status);
      _startStatsPolling();
    } else {
      _stopStatsPolling();
      setState(() {
        _status = status;
        _stats = null;
      });
    }
  }

  void _startStatsPolling() {
    if (_statsTimer != null) return;
    _refreshStats();
    _statsTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _refreshStats(),
    );
  }

  void _stopStatsPolling() {
    _statsTimer?.cancel();
    _statsTimer = null;
  }

  Future<void> _refreshStats() async {
    final stats = await _vpn.tunnelStatistics();
    // Only rebuild when the numbers actually change (avoids a 1s whole-page rebuild on idle).
    if (mounted && stats != null && stats != _stats) {
      setState(() => _stats = stats);
    }
  }

  Future<void> _connect() async {
    final cfg = _configController.text.trim();
    if (cfg.isEmpty) {
      _snack("Paste an OpenVPN config first", isError: true);
      return;
    }
    try {
      await _vpn.connect(cfg);
    } catch (e) {
      _snack("Failed to connect: $e", isError: true);
    }
  }

  void _disconnect() {
    // disconnect() is fire-and-forget (void); progress arrives via the status stream.
    _vpn.disconnect();
  }

  void _snack(String message, {bool isError = false}) {
    final scheme = Theme.of(context).colorScheme;
    final fg = isError ? scheme.onErrorContainer : scheme.onSecondaryContainer;
    _messengerKey.currentState
      ?..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor:
              isError ? scheme.errorContainer : scheme.secondaryContainer,
          elevation: 3,
          margin: const EdgeInsets.all(12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: Duration(seconds: isError ? 5 : 3),
          content: Row(
            children: [
              Icon(isError ? Icons.error_outline : Icons.check_circle_outline,
                  color: fg, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(message, style: TextStyle(color: fg))),
            ],
          ),
        ),
      );
  }

  bool get _isBusy =>
      _status == ConnectionStatus.connecting ||
      _status == ConnectionStatus.disconnecting;
  bool get _isConnected => _status == ConnectionStatus.connected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OpenVPN Dart'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_initError != null) _ErrorBanner(_initError!),
            _StatusCard(status: _status, stats: _stats),
            const SizedBox(height: 16),
            _ConfigField(controller: _configController, enabled: !_isConnected && !_isBusy),
            const SizedBox(height: 16),
            _PrimaryButton(
              status: _status,
              isBusy: _isBusy,
              isConnected: _isConnected,
              onConnect: _connect,
              onDisconnect: _disconnect,
            ),
            const SizedBox(height: 8),
            _PermissionsCard(vpn: _vpn, status: _status, snack: _snack),
            const SizedBox(height: 8),
            _AdvancedSection(vpn: _vpn, snack: _snack),
          ],
        ),
      ),
    );
  }
}

// --- Status + live data usage ------------------------------------------------

class _StatusCard extends StatefulWidget {
  const _StatusCard({required this.status, required this.stats});

  final ConnectionStatus status;
  final VPNStatistics? stats;

  @override
  State<_StatusCard> createState() => _StatusCardState();
}

class _StatusCardState extends State<_StatusCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  ConnectionStatus get status => widget.status;

  bool get _transitioning =>
      status == ConnectionStatus.connecting ||
      status == ConnectionStatus.disconnecting;

  @override
  void initState() {
    super.initState();
    _syncSpin();
  }

  @override
  void didUpdateWidget(_StatusCard old) {
    super.didUpdateWidget(old);
    _syncSpin();
  }

  void _syncSpin() {
    if (_transitioning) {
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      _spin
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _color(scheme);
    final icon = Icon(_icon, color: color, size: 40);
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: color.withValues(alpha: 0.15),
              child: _transitioning
                  ? RotationTransition(turns: _spin, child: icon)
                  : icon,
            ),
            const SizedBox(height: 12),
            Text(
              _label,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            if (status == ConnectionStatus.connected) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _Meter(
                    icon: Icons.arrow_upward,
                    label: "Upload",
                    value: _format(widget.stats?.totalUpload),
                  ),
                  _Meter(
                    icon: Icons.arrow_downward,
                    label: "Download",
                    value: _format(widget.stats?.totalDownload),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _color(ColorScheme s) => switch (status) {
        ConnectionStatus.connected => Colors.green,
        ConnectionStatus.connecting || ConnectionStatus.disconnecting =>
          Colors.orange,
        ConnectionStatus.disconnected || ConnectionStatus.unknown =>
          s.onSurfaceVariant,
      };

  IconData get _icon => switch (status) {
        ConnectionStatus.connected => Icons.shield,
        ConnectionStatus.connecting || ConnectionStatus.disconnecting =>
          Icons.sync,
        ConnectionStatus.disconnected => Icons.shield_outlined,
        ConnectionStatus.unknown => Icons.help_outline,
      };

  String get _label => switch (status) {
        ConnectionStatus.connected => "Connected",
        ConnectionStatus.connecting => "Connecting…",
        ConnectionStatus.disconnecting => "Disconnecting…",
        ConnectionStatus.disconnected => "Disconnected",
        ConnectionStatus.unknown => "Unknown",
      };
}

class _Meter extends StatelessWidget {
  const _Meter({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

// --- Config input ------------------------------------------------------------

class _ConfigField extends StatelessWidget {
  const _ConfigField({required this.controller, required this.enabled});

  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      minLines: 5,
      maxLines: 10,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      decoration: InputDecoration(
        labelText: 'OpenVPN config (.ovpn)',
        helperText: enabled
            ? 'Paste your own .ovpn config — required to connect (use a per-device config)'
            : 'Disconnect to edit the config',
        alignLabelWithHint: true,
        border: const OutlineInputBorder(),
        suffixIcon: enabled && controller.text.isNotEmpty
            ? IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.clear),
                onPressed: () => controller.clear(),
              )
            : null,
      ),
    );
  }
}

// --- Primary connect/disconnect button ---------------------------------------

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.status,
    required this.isBusy,
    required this.isConnected,
    required this.onConnect,
    required this.onDisconnect,
  });

  final ConnectionStatus status;
  final bool isBusy;
  final bool isConnected;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 52,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: isConnected ? scheme.error : scheme.primary,
        ),
        onPressed: isBusy ? null : (isConnected ? onDisconnect : onConnect),
        icon: isBusy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Icon(isConnected ? Icons.stop : Icons.power_settings_new),
        label: Text(
          isBusy
              ? (status == ConnectionStatus.connecting
                    ? 'Connecting…'
                    : 'Disconnecting…')
              : (isConnected ? 'Disconnect' : 'Connect'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

// --- Permissions (VPN consent + notifications), checked on launch ------------

class _PermissionsCard extends StatefulWidget {
  const _PermissionsCard({
    required this.vpn,
    required this.status,
    required this.snack,
  });

  final OpenVPNDart vpn;
  final ConnectionStatus status;
  final void Function(String, {bool isError}) snack;

  @override
  State<_PermissionsCard> createState() => _PermissionsCardState();
}

class _PermissionsCardState extends State<_PermissionsCard> {
  bool? _vpnGranted;
  PermissionStatus? _notif;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(_PermissionsCard old) {
    super.didUpdateWidget(old);
    // A live tunnel implies VPN consent was granted — re-check when it connects.
    if (old.status != widget.status &&
        widget.status == ConnectionStatus.connected) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    try {
      final granted = await widget.vpn.checkTunnelConfiguration();
      if (mounted) setState(() => _vpnGranted = granted);
    } catch (_) {
      if (mounted) setState(() => _vpnGranted = null);
    }
    final n = await Permission.notification.status;
    if (mounted) setState(() => _notif = n);
  }

  Future<void> _grantVpn() async {
    try {
      final granted = await widget.vpn.requestPermissionAndroid();
      if (mounted) setState(() => _vpnGranted = granted);
      if (!granted) widget.snack('VPN permission was not granted', isError: true);
    } catch (e) {
      widget.snack('VPN permission request failed: $e', isError: true);
    }
  }

  Future<void> _grantNotif() async {
    var s = await Permission.notification.request();
    if (s.isPermanentlyDenied) await openAppSettings();
    if (mounted) setState(() => _notif = s);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                Text('Permissions',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  tooltip: 'Re-check',
                  icon: const Icon(Icons.refresh),
                  onPressed: _refresh,
                ),
              ],
            ),
          ),
          _PermissionRow(
            grantedIcon: Icons.vpn_key,
            deniedIcon: Icons.vpn_key_off,
            title: 'VPN permission',
            granted: _vpnGranted,
            grantedText: 'Granted',
            deniedText: 'Required to start the tunnel',
            onGrant: _grantVpn,
          ),
          _PermissionRow(
            grantedIcon: Icons.notifications_active,
            deniedIcon: Icons.notifications_off,
            title: 'Notifications',
            granted: _notif?.isGranted,
            grantedText: 'Granted',
            deniedText: 'Needed to show the VPN notification',
            onGrant: _grantNotif,
          ),
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.grantedIcon,
    required this.deniedIcon,
    required this.title,
    required this.granted,
    required this.grantedText,
    required this.deniedText,
    required this.onGrant,
  });

  final IconData grantedIcon;
  final IconData deniedIcon;
  final String title;
  final bool? granted; // null = checking
  final String grantedText;
  final String deniedText;
  final VoidCallback onGrant;

  @override
  Widget build(BuildContext context) {
    final isGranted = granted == true;
    return ListTile(
      leading: Icon(
        isGranted ? grantedIcon : deniedIcon,
        color: isGranted ? Colors.green : null,
      ),
      title: Text(title),
      subtitle: Text(
        granted == null ? 'Checking…' : (isGranted ? grantedText : deniedText),
      ),
      trailing: granted == null
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : (isGranted
                ? const Icon(Icons.check_circle, color: Colors.green)
                : FilledButton.tonal(
                    onPressed: onGrant, child: const Text('Grant'))),
    );
  }
}

// --- Advanced (secondary plugin methods) -------------------------------------

class _AdvancedSection extends StatelessWidget {
  const _AdvancedSection({required this.vpn, required this.snack});

  final OpenVPNDart vpn;
  final void Function(String, {bool isError}) snack;

  Future<void> _run(String label, Future<Object?> Function() action) async {
    try {
      final r = await action();
      snack('$label: ${r ?? 'ok'}');
    } catch (e) {
      snack('$label failed: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ExpansionTile(
        leading: const Icon(Icons.tune),
        title: const Text('Advanced'),
        childrenPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () =>
                    _run('Permission granted', vpn.checkTunnelConfiguration),
                child: const Text('Check permission'),
              ),
              OutlinedButton(
                onPressed: () => _run('Setup tunnel', vpn.setupTunnel),
                child: const Text('Setup tunnel'),
              ),
              OutlinedButton(
                onPressed: () =>
                    _run('Remove tunnel', vpn.removeTunnelConfiguration),
                child: const Text('Remove tunnel'),
              ),
              OutlinedButton(
                onPressed: () =>
                    _run('Status', () async => (await vpn.getVPNStatus()).name),
                child: const Text('Status'),
              ),
              if (Platform.isWindows)
                OutlinedButton(
                  onPressed: () => _run('TAP driver', vpn.ensureTapDriver),
                  child: const Text('Install TAP driver'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Init error: $message',
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// Human-readable byte count (B / KB / MB / GB).
String _format(int? bytes) {
  final b = bytes ?? 0;
  const kb = 1024, mb = kb * 1024, gb = mb * 1024;
  if (b >= gb) return '${(b / gb).toStringAsFixed(2)} GB';
  if (b >= mb) return '${(b / mb).toStringAsFixed(2)} MB';
  if (b >= kb) return '${(b / kb).toStringAsFixed(1)} KB';
  return '$b B';
}
