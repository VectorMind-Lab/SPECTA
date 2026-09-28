import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------------------------------------------------------------------------
// Phase 2L — release signing.
//
// The credentials live in `android/key.properties`, which is git-ignored
// alongside the git-ignored `*.jks` keystore itself, so no password and no
// private key can reach the repository even by accident. This file therefore
// only ever names the properties; it never contains a secret.
//
// A release build that cannot find those credentials is REFUSED rather than
// silently signed with the debug key, which is the whole point: a debug-signed
// artifact must never be mistaken for a distributable one.
// ---------------------------------------------------------------------------
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val releaseSigningRequested: Boolean =
    gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }

if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
} else if (releaseSigningRequested) {
    throw GradleException(
        "Release signing is not configured: android/key.properties is missing.\n" +
            "Restore your keystore and credentials (see docs/RELEASE.md), then " +
            "retry. This build is refused instead of falling back to the debug " +
            "keystore, because a debug-signed artifact is not distributable."
    )
}

android {
    namespace = "net.specta.app"
    compileSdk = flutter.compileSdkVersion
    // The Flutter default and the version every current plugin in the
    // dependency tree requires. (An earlier interrupted download had left a
    // malformed 1 KB stub here - AGP error CXX1101 - which was repaired by
    // deleting the stub and letting AGP re-download the real NDK.)
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "net.specta.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Registered only when the credentials exist, so a machine without them
        // (a fresh clone, or CI with no secrets) can still run debug builds. The
        // release path is protected by the check above instead.
        if (keystorePropertiesFile.exists()) {
            create("release") {
                storeFile = rootProject.file(
                    keystoreProperties.getProperty("storeFile")
                )
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Deliberately NOT `signingConfigs.getByName("debug")` any more.
            signingConfig = signingConfigs.findByName("release")

            // Minification review (Phase 2L): R8/shrinking stays OFF for V1.
            //
            // Three dependencies in this build carry native code or rely on
            // reflection — media_kit (libmpv), flutter_js (QuickJS) and
            // background_downloader (the plugin's task/WorkManager classes) —
            // and no Android device or emulator is available in this
            // environment to verify a shrunk build at runtime. Turning it on
            // would trade a modest size win for an unverifiable crash risk in
            // the playback and download paths. docs/RELEASE.md records what to
            // add (proguard rules plus real-device verification) before it is
            // enabled.
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
