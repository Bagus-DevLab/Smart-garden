plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")  // ← TAMBAHKAN INI (bukan apply plugin)
}

android {
    namespace = "com.example.ptoject_akhir_kelas"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
        // BEDA DISINI: Pakai "is" di depan dan pakai "="
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        // BEDA DISINI: Pakai kutip dua "1.8"
        jvmTarget = "1.8"
    }

    defaultConfig {
        applicationId = "com.example.ptoject_akhir_kelas"
        minSdk = flutter.minSdkVersion  // ← Pastikan 21
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true  // ← Tambahkan ini
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Gunakan kurung () untuk semua implementation
    implementation(platform("com.google.firebase:firebase-bom:32.7.0"))


    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}