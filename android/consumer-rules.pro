# Keep the ics-openvpn engine + our plugin from being stripped/obfuscated by R8.
# JNI and AIDL rely on exact class/method names; stripping them breaks release builds
# ("connects in debug, fails in release/Play").
-keep class de.blinkt.openvpn.** { *; }
-keep interface de.blinkt.openvpn.** { *; }
-keepclassmembers class de.blinkt.openvpn.** {
    native <methods>;
}
-keep class net.openvpn.ovpn3.** { *; }
-keep class com.mysteriumvpn.openvpn_dart.** { *; }
