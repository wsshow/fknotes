import java.io.FileInputStream
import java.io.File
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
val debugReleaseSigningRequested =
    System.getenv("FKNOTES_SIGN_DEBUG_WITH_RELEASE") == "1"

if (debugReleaseSigningRequested && !releaseSigningAvailable) {
    error(
        "FKNOTES_SIGN_DEBUG_WITH_RELEASE=1 requires android/key.properties " +
            "or the ANDROID_KEYSTORE_* environment variables",
    )
}

val mnnRuntimeDirectory = layout.buildDirectory.dir("mnn-runtime").get().asFile
val prepareMnnRuntime by tasks.registering(Exec::class) {
    commandLine(
        rootProject.file("../tool/prepare_mnn_runtime.sh").absolutePath,
        mnnRuntimeDirectory.absolutePath,
    )
    outputs.file(File(mnnRuntimeDirectory, ".ready-3.6.0-split-v4"))
}

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
        externalNativeBuild {
            cmake {
                arguments(
                    "-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON",
                    "-DMNN_RUNTIME_ROOT=${File(mnnRuntimeDirectory, "android/jni/arm64-v8a").absolutePath}",
                    "-DMNN_HEADERS_ROOT=${File(mnnRuntimeDirectory, "android/include").absolutePath}",
                )
            }
        }
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
        debug {
            if (debugReleaseSigningRequested) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
        release {
            signingConfig = signingConfigs.findByName("release")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDir(File(mnnRuntimeDirectory, "android/jni"))
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

tasks.configureEach {
    if (
        name == "preBuild" ||
        name.startsWith("configureCMake") ||
        name.startsWith("buildCMake") ||
        (name.startsWith("merge") && name.endsWith("JniLibFolders"))
    ) {
        dependsOn(prepareMnnRuntime)
    }
}

dependencies {
    implementation("com.google.ai.edge.litertlm:litertlm-android:0.14.0")
    // The Flutter bridge only bundles Latin recognition by default.
    // FK Notes runs the on-device Chinese recognizer explicitly.
    implementation("com.google.mlkit:text-recognition-chinese:16.0.1")
}
