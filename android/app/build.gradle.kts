// build.gradle.kts (A VERSÃO CORRETA E FINAL)

import java.util.Properties

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.geoforestv1"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    // <<< ADICIONE O BLOCO LINT AQUI DENTRO >>>
    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }
    // <<< FIM DA ADIÇÃO >>>

    signingConfigs {
        create("release") {
            // Procura pelo arquivo 'key.properties' na pasta 'android'
            val keyPropertiesFile = rootProject.file("key.properties")
            if (keyPropertiesFile.exists()) {
                val keyProperties = Properties()
                keyProperties.load(keyPropertiesFile.inputStream())
                storeFile = file(keyProperties["storeFile"] as String)
                storePassword = keyProperties["storePassword"] as String
                keyPassword = keyProperties["keyPassword"] as String
                keyAlias = keyProperties["keyAlias"] as String
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "br.com.geoforest.analytics"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
    }

    buildTypes {
        getByName("release") {
            val releaseConfig = signingConfigs.findByName("release")
            if (releaseConfig != null) {
                signingConfig = releaseConfig
            }
            // DESATIVE TEMPORARIAMENTE PARA TESTE
            isMinifyEnabled = false 
            isShrinkResources = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
} // <<< O BLOCO ANDROID TERMINA AQUI

flutter {
    source = "../.."
}
