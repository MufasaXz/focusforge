// `import java.util.Properties` is required: inside a Gradle Kotlin script the
// bare name `java` resolves to the Java plugin extension, so `java.util.X`
// silently fails to resolve.
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing material lives outside version control — see android/key.properties.
// On F-Droid's build machines that file does not exist, so its absence is a
// supported state rather than an error: the release build then produces an
// unsigned APK, which F-Droid signs with the key it holds for this app. The
// signing config is therefore only created when there is something to put in
// it — an empty one fails AGP's own signing validation and takes the build
// down with it.
val keystoreProperties = Properties()
run {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { keystoreProperties.load(it) }
}
val hasReleaseKey = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "dev.focusforge.focusforge"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.focusforge.focusforge"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                // All three schemes on purpose:
                //  v1 (JAR)      — required by Android 6 and below (minSdk is 24, so
                //                  it is only a compatibility belt-and-braces here).
                //  v2 (APK Sig)  — Android 7+; whole-file integrity, faster verify.
                //  v3 (APK Sig)  — Android 9+; adds key rotation support.
                // AGP disables v1 by default once minSdk >= 24, so it is forced on.
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }

    // The dependency-metadata block AGP stamps into the APK is rejected by
    // F-Droid, which requires it off — and it is of no use to anyone else.
    dependenciesInfo {
        includeInApk = false
        includeInBundle = false
    }

    buildTypes {
        release {
            if (hasReleaseKey) {
                signingConfig = signingConfigs.getByName("release")
            }
            // R8 runs on the release build. It drops the parts of the Flutter
            // embedding the app never reaches, and the one that matters is the
            // Play Store deferred-components support: it is compiled against
            // Play Core, so leaving it in drags Play Core type references into
            // the dex of an app that has no Play Services at all — which is
            // what F-Droid's scanner (and any other scanner) flags. Shrinking
            // also takes the APK down by several megabytes.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

// The delivered file says what it is — `focusforge-1.0.0.apk`, not
// `app-release.apk`. A copy rather than a rename: the Flutter tool reads the
// APK it expects at the path it expects, and the build directory carries both
// names. The version is the app's own, so the two cannot drift apart.
//
// It hangs off the assemble task rather than being a task of its own: a task
// that declares `outputs/flutter-apk` as an output has Gradle's stale-output
// cleanup delete the `app-release.apk` the Flutter plugin puts there.
tasks.matching { it.name == "assembleRelease" }.configureEach {
    doLast {
        copy {
            from(layout.buildDirectory.file("outputs/apk/release/app-release.apk"))
            into(layout.buildDirectory.dir("outputs/flutter-apk"))
            rename { "focusforge-${flutter.versionName}.apk" }
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
