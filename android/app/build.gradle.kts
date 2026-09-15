import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing reads key.properties at the project root, next to pubspec.yaml.
// Without that file, release builds are signed with the debug key instead, so
// `flutter run --release` still works on a machine that has no upload key. CI
// refuses to publish an APK signed that way.
val signingProperties = Properties().apply {
    val propertiesFile = rootProject.file("../key.properties")
    if (propertiesFile.exists()) propertiesFile.inputStream().use { load(it) }
}
val hasReleaseKey = signingProperties.getProperty("storeFile") != null

android {
    namespace = "com.ionel.notes"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications schedules with java.time, which older
        // Android versions only have through desugaring.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.ionel.notes"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Set from pubspec.yaml, or from --build-name and --build-number, which
        // the release workflow passes.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                // A relative store path is taken from the project root.
                storeFile = rootProject.file("..").resolve(signingProperties.getProperty("storeFile"))
                storePassword = signingProperties.getProperty("storePassword")
                keyAlias = signingProperties.getProperty("keyAlias")
                keyPassword = signingProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (hasReleaseKey) "release" else "debug")
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
