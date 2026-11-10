import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

/**
 * Upload-key signing, read from `android/key.properties`.
 *
 * The file is written by CI from repository secrets and is git-ignored. This
 * block did not exist: the release build type was hardwired to the *debug*
 * signing config, so every APK the pipeline produced was debug-signed — which
 * Play Console rejects outright, and which also breaks in-place updates because
 * the key differs between machines.
 *
 * When the file is absent (a fresh clone, a local `flutter run --release`) the
 * build falls back to debug keys rather than failing, so onboarding still works.
 * The APK is simply not publishable, which is the correct outcome.
 */
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasUploadKey = keystorePropertiesFile.exists()
if (hasUploadKey) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "app.examvault"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.examvault"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // 23 = Android 6.0. Required by flutter_secure_storage (AES-GCM Keystore)
        // and by the FCM SDK. Covers effectively the whole Indian Android market.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasUploadKey) {
            create("release") {
                // Paths are relative to `android/app`, which is where Gradle
                // resolves storeFile from.
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Use the upload key when configured; debug keys otherwise, so a
            // fresh clone can still build but cannot accidentally be shipped.
            signingConfig = if (hasUploadKey) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
