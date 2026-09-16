import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// 1. Check both android/key.properties and android/app/key.properties
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties").let { file ->
    if (file.exists()) file else project.file("key.properties")
}

if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.ndrrmo.alertu.alertu_flutter"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.ndrrmo.alertu.alertu_flutter"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        create("release") {
            val storeFilePath = keystoreProperties["storeFile"] as String?

            // 2. Only apply release signing if storeFile actually exists
            if (!storeFilePath.isNullOrEmpty()) {
                val keystoreFile = rootProject.file(storeFilePath).let { f ->
                    if (f.exists()) f else project.file(storeFilePath)
                }

                if (keystoreFile.exists()) {
                    keyAlias = keystoreProperties["keyAlias"] as String?
                    keyPassword = keystoreProperties["keyPassword"] as String?
                    storeFile = keystoreFile
                    storePassword = keystoreProperties["storePassword"] as String?
                    enableV1Signing = true
                    enableV2Signing = true
                }
            }
        }
    }

    buildTypes {
        release {
            // 3. Fallback to debug signing if release config is incomplete
            val releaseConfig = signingConfigs.getByName("release")
            signingConfig = if (releaseConfig.storeFile != null) releaseConfig else signingConfigs.getByName("debug")

            isMinifyEnabled = false
            isShrinkResources = false
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
    implementation(platform("com.google.firebase:firebase-bom:34.15.0"))
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

configurations.all {
    resolutionStrategy {
        dependencySubstitution {
            substitute(module("io.agora.rtc:agora-special-full:4.6.2.70"))
                .using(module("io.agora.rtc:full-sdk:4.6.2"))
        }
    }
}