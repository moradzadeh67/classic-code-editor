import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing values live OUTSIDE the repository so credentials are never committed.
// The build looks for a key.properties file in this order:
//   1. android/key.properties (next to this module)
//   2. $HOME/Desktop/classic_code_editor-key.properties (kept out of the repo)
//   3. the path in the RELEASE_KEY_PROPERTIES environment variable (for CI)
// When none of them exist the release build falls back to the debug keys, so the project
// still builds for anyone who clones it.
val keystorePropertiesFile: File? = listOfNotNull(
    rootProject.file("key.properties").takeIf { it.exists() },
    File(System.getProperty("user.home"), "Desktop/classic_code_editor-key.properties")
        .takeIf { it.exists() },
    System.getenv("RELEASE_KEY_PROPERTIES")?.let { File(it) }?.takeIf { it.exists() },
).firstOrNull()

val keystoreProperties = Properties().apply {
    keystorePropertiesFile?.let { FileInputStream(it).use { input -> load(input) } }
}

android {
    namespace = "io.github.moradzadeh67.classic_code_editor"
    // file_picker (via flutter_plugin_android_lifecycle) requires compiling against
    // Android API 36 or newer, which is higher than the Flutter default.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.github.moradzadeh67.classic_code_editor"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
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
        if (keystorePropertiesFile != null) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Uses the upload key when key.properties is available, and falls back to the
            // debug keys otherwise so `flutter run --release` still works for fresh clones.
            signingConfig = if (keystorePropertiesFile != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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
