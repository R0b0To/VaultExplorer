import java.util.Properties

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val buildFfmpeg = tasks.register<Exec>("buildFfmpegAndroid") {
    description = "Builds libavcodec/avformat/avutil/swscale/swresample from source " +
            "for every target ABI (scripts/build_ffmpeg_android.sh). No-op if already built. " +
            "This replaces manually copying prebuilt .so files into cpp/ffmpeg/ -- required " +
            "so the app can be built entirely from source (F-Droid) and so CI/Play builds " +
            "don't depend on a binary that isn't in version control."
    workingDir = rootProject.file("..")
    commandLine("bash", "scripts/build_ffmpeg_android.sh")
    inputs.file("../../scripts/build_ffmpeg_android.sh")
    outputs.dir("src/main/cpp/ffmpeg")
}

android {
    namespace = "com.aeidolon.vaultexplorer"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    packaging {
        jniLibs {
            pickFirsts += "lib/**/libc++_shared.so"
        }
    }

    defaultConfig {
        applicationId = "com.aeidolon.vaultexplorer"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        externalNativeBuild {
            cmake {
                arguments(
                    "-DCMAKE_BUILD_TYPE=Release",
                    "-DCMAKE_SHARED_LINKER_FLAGS=-Wl,-z,max-page-size=16384",
                    "-DCMAKE_MODULE_LINKER_FLAGS=-Wl,-z,max-page-size=16384"
                )
                cFlags("-O3", "-funroll-loops")
                cppFlags("-O3", "-funroll-loops")
            }
        }
    }

    if (keystorePropertiesFile.exists()) {
        signingConfigs {
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
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
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
    implementation("androidx.documentfile:documentfile:1.0.1")
    testImplementation("junit:junit:4.13.2")
}

tasks.matching { it.name.startsWith("externalNativeBuild") || it.name.startsWith("configureCMake") }
    .configureEach { dependsOn(buildFfmpeg) }
tasks.named("preBuild").configure { dependsOn(buildFfmpeg) }