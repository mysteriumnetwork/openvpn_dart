# Changelog

## Unreleased

### Added
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
