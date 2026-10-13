import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firma de release. Las claves NO van en el repositorio:
// - En la PC: android/key.properties (ignorado por git).
// - En GitHub Actions / Codemagic: se genera desde los secretos del repositorio.
// Si no existe, en la PC se firma con la clave de debug (solo para probar: esas
// APK no se pueden actualizar encima de una firmada con la clave de release).
// En el servidor de compilación (CI=true) la falta de clave detiene la build.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keystorePropertiesFile.exists()
if (hasReleaseKey) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "cu.garajetcg.garaje_tcg"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "cu.garajetcg.garaje_tcg"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
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
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else if (System.getenv("CI") == "true") {
                // En GitHub Actions / Codemagic NUNCA se firma con la clave de
                // debug: cambiaría el ANDROID_ID y todas las licencias emitidas
                // dejarían de valer. Mejor que la compilación falle.
                throw GradleException(
                    "Faltan los secretos de firma (KEYSTORE_BASE64, KEYSTORE_PASSWORD, " +
                        "KEY_ALIAS, KEY_PASSWORD). No se compila la APK de release."
                )
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
