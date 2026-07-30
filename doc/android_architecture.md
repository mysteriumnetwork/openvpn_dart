# Android implementation — maintainer guide

How the Android side of `openvpn_dart` works, why it's built this way, and how to maintain it.
For **consumer setup** (how an app uses the plugin) see the README "Android Setup"; for the
**AAR build provenance** see [`android/localmaven/PROVENANCE.md`](../android/localmaven/PROVENANCE.md).

## Overview

```
Dart  (lib/openvpn_dart.dart)
  │  MethodChannel  id.mysteriumvpn.openvpn_flutter/vpncontrol
  │  EventChannel   id.mysteriumvpn.openvpn_flutter/vpnstatus
  ▼
OpenvpnDartPlugin.kt        FlutterPlugin + ActivityAware; channel routing + VpnService.prepare()
  │                          permission flow (mirrors wireguard_dart)
  ▼
OpenVPNBackend.kt           process-wide singleton: status StateFlow, connect/disconnect,
  │                          VpnStatus state + byte-count listeners, notification channels
  ▼
ics-openvpn  (AAR)          de.blinkt.openvpn.* — ConfigParser, VpnProfile, VPNLaunchHelper,
                             OpenVPNService (the VpnService), VpnStatus, ProfileManager
```

The channel names and method set are **fixed by the existing Dart + iOS implementation** — Android
just implements the same contract. No Dart API changes were needed beyond the additive
`tunnelStatistics()`.

## File map (`android/src/main/kotlin/com/mysteriumvpn/openvpn_dart/`)

| File | Responsibility |
|---|---|
| `OpenvpnDartPlugin.kt` | Registers the two channels; routes method calls; runs the VPN-consent flow (`VpnService.prepare` → `startActivityForResult` → `onActivityResult`); collects `OpenVPNBackend.statusFlow` → event channel. |
| `OpenVPNBackend.kt` | Singleton. Owns status (`StateFlow<ConnectionStatus>`), drives connect (parse config → `setTemporaryProfile` → `VPNLaunchHelper.startOpenVpn`) and disconnect (bind `IOpenVPNServiceInternal` → `stopVPN`). Listens to `VpnStatus` for state + byte counts. Creates notification channels. |
| `ConnectionStatus.kt` | Maps ics `ConnectionStatus.LEVEL_*` → the Dart-facing enum. Unit-tested. |
| `ConnectionStatusBroadcaster.kt` | `EventChannel.StreamHandler`; posts status names on the main thread. |
| `AndroidManifest.xml` | Minimal — the AAR's manifest contributes `OpenVPNService` (+`BIND_VPN_SERVICE`), `OpenVPNStatusService`, and permissions via merge. |
| `build.gradle` | Depends on the local-maven AAR + coroutines + androidx; ships `consumer-rules.pro`. |

## Key design decisions

- **Single process.** The AAR is patched to drop ics's `android:process=":openvpn"`, so
  `OpenVPNService` runs in the app's main process. This is **required**: `VpnStatus` and
  `ProfileManager` are per-process statics — with a separate process the temporary profile we
  register isn't visible to the service, and status can't reach our listener without a fragile,
  ANR-prone cross-process bridge. (Consistent with how `wireguard_dart` runs in-process.)
- **Notification channels created by us.** ics normally creates them in `ICSOpenVPNApplication`,
  but the host app keeps its own `Application` class, so `OpenVPNBackend.init()` creates them —
  otherwise `OpenVPNService.startForeground()` throws `CannotPostForegroundServiceNotification…`.
- **Status mapping** lives in one place (`ConnectionStatus.fromIcs`). `disconnecting` has no ics
  equivalent — it's set locally when we initiate a stop.
- **Statistics** come from `VpnStatus.addByteCountListener`; `OpenVPNBackend` tracks cumulative
  totals (reset per connect) and the plugin returns them as JSON for `tunnelStatistics()`.

## The AAR (`network.mysterium.openvpn:icsopenvpn`)

Built from source from `schwabe/ics-openvpn` (not a third-party prebuilt — the only ready-made one
shipped EOL OpenSSL). It's repackaged from an `application` module to a `library`, security-hardened,
and styled to match the app's WireGuard notification. Full change list + pinned SHAs +
reproduction steps: [`PROVENANCE.md`](../android/localmaven/PROVENANCE.md).

**To rebuild / bump the ics-openvpn version:**
```bash
brew install swig                      # one-time (macOS); also needs Android NDK + JDK 17
scripts/build_android_aar.sh 0.7.55-myst
```
The script clones the pinned tag, applies `scripts/icsopenvpn-mysterium-*.patch`, builds all 4 ABIs,
verifies the output, and stages it into `android/localmaven/`. Then update the coordinate in
`android/build.gradle` and the SHA-256 in `PROVENANCE.md` (the script prints both). Editing the
patch: apply it to a fresh clone, make changes, then `git diff` to regenerate the patch.

> The AAR is delivered via a committed local-maven repo. Bumping its version is only needed when the
> ics-openvpn source changes — not on every plugin edit. For incidental local rebuilds use
> `./gradlew --refresh-dependencies` rather than bumping.

## Consumer requirements (recap)

1. Expose the bundled local-maven repo (or a published mirror).
2. `useLegacyPackaging = true` — ics **executes** `libovpnexec.so`, which requires native libs
   extracted to disk (AGP defaults to `extractNativeLibs=false`, which breaks the spawn).
3. Request `POST_NOTIFICATIONS` at runtime (Android 13+) to show the foreground notification.

## Gotchas (lessons learned)

- **Channel names** must be `id.mysteriumvpn.openvpn_flutter/{vpncontrol,vpnstatus}` — the original
  stub used `openvpn_dart` and was entirely unwired.
- **`extractNativeLibs=false`** → native process can't spawn (`NullPointerException` on `Process`).
- **Missing notification channels** → `startForeground` crash.
- **`keepVPNAlive`** schedules a persisted JobScheduler job that needs `RECEIVE_BOOT_COMPLETED`;
  the AAR patch makes it non-persisted since we don't auto-start on boot.
- **Notification tap** must open the host app's launcher (ics points it at its own stripped
  `.activities.MainActivity`); avoid `FLAG_ACTIVITY_REORDER_TO_FRONT` (black screen after the app is
  swiped from recents).
- **AAR is GPLv2** (ics-openvpn) — see the README licensing note.
