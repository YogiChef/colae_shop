import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = project.file("../key.properties")

if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
    println("✅ LOADED key.properties SUCCESS")
    println("   storePassword = ${keystoreProperties.getProperty("storePassword")}")
    println("   keyAlias       = ${keystoreProperties.getProperty("keyAlias")}")
    println("   storeFile      = ${keystoreProperties.getProperty("storeFile")}")
} else {
    println("❌ key.properties NOT FOUND at: ${keystorePropertiesFile.absolutePath}")
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.colae.shop"
    compileSdk = 36
    ndkVersion = "30.0.14904198"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.colae.shop"
        minSdk = 26
        targetSdk = 36
        versionCode = 7
        versionName = "1.0.0+7"
        multiDexEnabled = true
    }

    signingConfigs {
    create("release") {
        keyAlias = keystoreProperties.getProperty("keyAlias")
        keyPassword = keystoreProperties.getProperty("keyPassword")
        storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
        storePassword = keystoreProperties.getProperty("storePassword")
    }
   
}
packaging {
        jniLibs {
            useLegacyPackaging = true 
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:34.12.0"))
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}