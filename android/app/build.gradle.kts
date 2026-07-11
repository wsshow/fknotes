import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val environmentKeystorePath =
    System.getenv("ANDROID_KEYSTORE_PATH")?.takeIf { it.isNotBlank() }
val environmentSigningAvailable =
    listOf(
        environmentKeystorePath,
        System.getenv("ANDROID_KEYSTORE_PASSWORD"),
        System.getenv("ANDROID_KEY_PASSWORD"),
        System.getenv("ANDROID_KEY_ALIAS"),
    ).all { !it.isNullOrBlank() }
val releaseSigningAvailable =
    keystorePropertiesFile.exists() || environmentSigningAvailable

fun releaseSigningValue(
    environmentName: String,
    propertyName: String,
): String =
    System.getenv(environmentName)?.takeIf { it.isNotBlank() }
        ?: keystoreProperties.getProperty(propertyName)
        ?: error("Missing Android release signing value: $environmentName")

android {
    namespace = "com.fknotes.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.fknotes.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningAvailable) {
            create("release") {
                keyAlias = releaseSigningValue("ANDROID_KEY_ALIAS", "keyAlias")
                keyPassword = releaseSigningValue("ANDROID_KEY_PASSWORD", "keyPassword")
                storeFile = file(releaseSigningValue("ANDROID_KEYSTORE_PATH", "storeFile"))
                storePassword =
                    releaseSigningValue("ANDROID_KEYSTORE_PASSWORD", "storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
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

dependencies {
    // The Flutter bridge only bundles Latin recognition by default.
    // FK Notes runs the on-device Chinese recognizer explicitly.
    implementation("com.google.mlkit:text-recognition-chinese:16.0.1")
}
