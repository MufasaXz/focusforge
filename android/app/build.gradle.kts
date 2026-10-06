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
val keystoreProperties = Properties()
run {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { keystoreProperties.load(it) }
}

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
        create("release") {
            if (keystoreProperties.getProperty("storeFile") != null) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
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

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
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
