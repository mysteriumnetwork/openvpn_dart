plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.mysteriumvpn.openvpn_dart_example"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.mysteriumvpn.openvpn_dart_example"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // Exercise R8 so the plugin's consumer-rules.pro keep rules are verified (the
            // de.blinkt.openvpn JNI/AIDL classes must survive minification).
            isMinifyEnabled = true
            isShrinkResources = true
        }
    }

    // REQUIRED by ics-openvpn: it executes libovpnexec.so as a process, which only works if the
    // native libs are extracted to disk. Modern AGP defaults to extractNativeLibs=false, so the
    // binary can't be spawned (NullPointerException on Process). Apps consuming openvpn_dart must
    // set this too.
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

flutter {
    source = "../.."
}
