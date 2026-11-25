# Changelog

## Unreleased

### Changed
- **`disconnect()` returns `Future<void>`** (was `void`) and completes once the platform has
  handled the request — on Windows, after `openvpn.exe` has been terminated and has exited, or has
  been given five seconds to. Await it before quitting the app: the old fire-and-forget call let
  `exit(0)` end the app with the teardown still queued. A failure the platform reports now reaches
  the caller instead of becoming an unhandled async error; Windows does not report one, and only
  logs a stop that fails.
- **Windows: a tunnel is no longer carried over to the next launch.** The plugin used to re-attach
  at startup to a running `openvpn.exe` and report `connected`. See the two Windows fixes below.

### Fixed
- **Windows: the tunnel outlived the app.** Quitting with a tunnel up, a crash, or ending the app
  from Task Manager left `openvpn.exe` running and the machine still routed through it.
  `openvpn.exe` now runs in a kill-on-close job object, so it ends with the app however the app
  ends.
- **Windows: startup could take over another program's OpenVPN.** The re-attach matched any process
  named `openvpn.exe` — OpenVPN GUI's or OpenVPN Connect's included — and a later disconnect
  terminated it. Only this plugin's own copy is considered now, by path, and only to end one that
  outlived the app that started it.
- **Windows: disconnecting froze the window for up to a second.** The stop runs on the platform
  thread, where it slept for 100 ms and then waited for the status monitor thread to finish its
  one-second sleep. The sleep is gone and the monitor is woken at once, so a stop now takes as long
  as `openvpn.exe` takes to exit. A reconnect, which stops the old tunnel first, gains the same.
- **Windows: connecting after the status monitor had failed crashed the app.** A monitor thread
  that ended on an exception stayed joinable, and the next `connect()` started a new one over it,
  which terminates the process. The `openvpn.exe` it had been watching was left running too.
  `connect()` now stops whatever is actually left of the previous connection first.
- **Android: a `.ovpn` with no client-auth directive crashed the host app process on connect.**
  `connect()` now rejects such a config with `err_connect`, and the bundled AAR fails it as an
  ordinary keystore error instead of `NullPointerException: alias == null` — which also covers the
  system-initiated service restart, a path `connect()` never sees.
- **Android: `ForegroundServiceDidNotStartInTimeException` on connect.** `OpenVPNService` now always
  posts its foreground notification in `onStartCommand` instead of skipping it whenever the host app
  had a notification on screen.
- **Android: `ActivityNotFoundException` from `LaunchVPN`.** It no longer tries to open ics's log
  window, which cannot exist under a host app's package.

  AAR-side detail for all three: [`android/localmaven/PROVENANCE.md`](android/localmaven/PROVENANCE.md).

### Added
- **Tunnel statistics beyond Android.** `tunnelStatistics()` now works on iOS/macOS (the
  packet-tunnel extension answers an `OPENVPN_STATS` app message with the same JSON shape Android
  returns) and on Windows (OpenVPN writes a `--status` file, parsed in Dart via
  `VPNStatistics.fromStatusFile`). Host apps must forward `handleAppMessage` as the example
  extensions do. The Windows status file refreshes every 5s, so counters there step rather than
  stream. `latestHandshake` stays 0 on every platform — OpenVPN has no handshake.
- **Android support** via the ics-openvpn engine, bundled as a from-source AAR
  (`network.mysterium.openvpn:icsopenvpn`, built from `schwabe/ics-openvpn` v0.7.55 with current
  OpenSSL 3.4.1 / OpenVPN 2.7). See [`android/localmaven/PROVENANCE.md`](android/localmaven/PROVENANCE.md).
  - `OpenVPNService` runs in the app's main process and is registered with `BIND_VPN_SERVICE`.
  - Foreground notification styled to match `wireguard_dart` (VPN-key icon, profile-name title,
    cumulative `↑/↓` totals); no pause action.
  - Security-hardened AAR: stripped `QUERY_ALL_PACKAGES` and the exported remote-control API
    surface; no imposed app icon/label/theme.
- **`tunnelStatistics()`** — returns cumulative session traffic as `VPNStatistics`
  (`totalDownload`, `totalUpload`, `latestHandshake`). Implemented on Android.
- Reproducible AAR build pipeline: `scripts/build_android_aar.sh` + `scripts/icsopenvpn-mysterium-*.patch`.
- Redesigned example app (Material 3): paste-a-config field, live data usage, permission status,
  connect/disconnect with animated state.

### Notes
- Android consumers must add the bundled Maven repo and set `useLegacyPackaging = true`
  (see the README "Android Setup").
- ics-openvpn is GPLv2 — see the README licensing note.

## 0.0.1

* Initial release: iOS/macOS (NetworkExtension) and Windows (bundled OpenVPN) support.
