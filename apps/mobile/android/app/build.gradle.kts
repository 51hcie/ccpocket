import java.util.Properties
import java.io.FileInputStream

// Generate dummy google-services.json if not present (for OSS builds without Firebase config).
// The app will build and run but push notifications will not work.
val googleServicesFile = file("google-services.json")
if (!googleServicesFile.exists()) {
    googleServicesFile.writeText("""
{
  "project_info": {
    "project_number": "000000000000",
    "project_id": "dummy-project",
    "storage_bucket": "dummy-project.appspot.com"
  },
  "client": [
    {
      "client_info": {
        "mobilesdk_app_id": "1:000000000000:android:0000000000000000",
        "android_client_info": {
          "package_name": "com.k9i.ccpocket"
        }
      },
      "api_key": [
        {
          "current_key": "AIzaSyDummy0000000000000000000000000000"
        }
      ]
    }
  ],
  "configuration_version": "1"
}
""".trimIndent())
    logger.warn("google-services.json not found. A dummy was generated. Push notifications will not work.")
}

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("keystore.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.k9i.ccpocket"
    compileSdk = 36
    // The 16 KB page-aligned irondash fork requires NDK 29.
    ndkVersion = "29.0.13846066"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.k9i.ccpocket"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        resourceConfigurations += listOf("en", "ja", "zh-rCN")
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            val keyAliasProp = keystoreProperties["keyAlias"] as? String
            val keyPasswordProp = keystoreProperties["keyPassword"] as? String
            val storeFilePath = keystoreProperties["storeFile"] as? String
            val storePasswordProp = keystoreProperties["storePassword"] as? String

            if (storeFilePath.isNullOrBlank() || storePasswordProp.isNullOrBlank() || keyAliasProp.isNullOrBlank() || keyPasswordProp.isNullOrBlank()) {
                throw GradleException("keystore.properties is present but missing required keys: storeFile, storePassword, keyAlias, keyPassword")
            }

            val rawStoreFile = file(storeFilePath)
            val customStoreFile = if (rawStoreFile.isAbsolute) rawStoreFile else rootProject.file(storeFilePath)
            if (!customStoreFile.exists()) {
                throw GradleException("Keystore file specified in keystore.properties does not exist: ${customStoreFile.absolutePath}")
            }

            getByName("debug") {
                keyAlias = keyAliasProp
                keyPassword = keyPasswordProp
                storeFile = customStoreFile
                storePassword = storePasswordProp
            }
            create("release") {
                keyAlias = keyAliasProp
                keyPassword = keyPasswordProp
                storeFile = customStoreFile
                storePassword = storePasswordProp
            }
        }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
