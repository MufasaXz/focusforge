pluginManagement {
    // Pinned Flutter build plugin supports the AGP 9 DSL; see its patch note.
    includeBuild("../third_party/flutter_gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.3.1" apply false
    id("com.google.gms.google-services") version "4.5.0" apply false
}

include(":app")
