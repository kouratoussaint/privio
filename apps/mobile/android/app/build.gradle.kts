plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.privio.app"
    // SDK 37 exigé par permission_handler_android 14.x. N'affecte que les API disponibles
    // à la compilation : minSdk (24) et targetSdk (défaut Flutter) restent inchangés.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Identifiant à déclarer tel quel dans le projet Firebase (étape 4).
        applicationId = "com.privio.app"
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

    // Clé de signature STABLE fournie par la CI (secrets GitHub), jamais versionnée.
    // Sans elle (poste de développement), la clé de debug locale est utilisée.
    val keystorePath = System.getenv("PRIVIO_KEYSTORE_PATH")
    signingConfigs {
        if (keystorePath != null) {
            create("privio") {
                storeFile = file(keystorePath)
                storePassword = System.getenv("PRIVIO_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("PRIVIO_KEY_ALIAS")
                keyPassword = System.getenv("PRIVIO_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePath != null) {
                signingConfigs.getByName("privio")
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

dependencies {
    // Thèmes AppCompat : exigés par l'empreinte digitale (local_auth) sur Android 7 et 8.
    implementation("androidx.appcompat:appcompat:1.7.1")
}
