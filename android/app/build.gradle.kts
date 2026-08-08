import java.util.Properties

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.devtools.ksp") // Room's annotation processor, for SyncLedgerDb (docs/architecture.md §8)
}

val syncApiVersion: String = gradle.extra["syncApiVersion"] as String

tasks.whenTaskAdded {
    if (name.contains("ArtProfile")) {
        enabled = false
    }
}

// Single source of truth for the NDK pin
val ndkVersionPin = "28.2.13676358" // r28c -- see android/build.gradle.kts for why not plain r28

// Resolve target ABI from ENV or Flutter's target-platform property
val targetAbi: String? = System.getenv("VAULTEXPLORER_TARGET_ABI")
    ?: when (providers.gradleProperty("target-platform").orNull) {
        "android-arm64" -> "arm64-v8a"
        "android-arm"   -> "armeabi-v7a"
        "android-x64"   -> "x86_64"
        "android-x86"   -> "x86"
        else            -> null
    }

android {
    namespace = "com.aeidolon.vaultexplorer"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = ndkVersionPin
    buildToolsVersion = "34.0.0"

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }

    buildFeatures {
        // VaultSyncBridgeService's public (syncapi) and internal
        // (ILedgerWriter) AIDL surfaces — docs/architecture.md §8.
        aidl = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    packaging {
        jniLibs {
            pickFirsts += "lib/**/libc++_shared.so"
            useLegacyPackaging = true
        }
    }

    defaultConfig {
        applicationId = "com.aeidolon.vaultexplorer"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        externalNativeBuild {
            cmake {
                arguments(
                    "-DCMAKE_BUILD_TYPE=Release",
                    "-DCMAKE_SHARED_LINKER_FLAGS=-Wl,-z,max-page-size=16384 -Wl,--build-id=none,--hash-style=gnu",
                    "-DCMAKE_MODULE_LINKER_FLAGS=-Wl,-z,max-page-size=16384 -Wl,--build-id=none,--hash-style=gnu"
                )
                val repoRootDir = rootProject.file("..").canonicalPath
                val prefixMap = "-ffile-prefix-map=$repoRootDir=/build"
                cFlags("-O3", "-funroll-loops", prefixMap, "-fno-ident")
                cppFlags("-O3", "-funroll-loops", prefixMap, "-fno-ident")

                targetAbi?.let { abi ->
                    abiFilters.clear()
                    abiFilters.add(abi)
                }
            }
        }

        // Restricts AGP JNI packaging to the single target ABI across all libraries/plugins
        targetAbi?.let { abi ->
            ndk {
                abiFilters.clear()
                abiFilters.add(abi)
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
            isMinifyEnabled = true
            isShrinkResources = true
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                null
            }

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )

            vcsInfo.include = false
        }
    }

    dependenciesInfo {
        includeInApk = false
        includeInBundle = false
    }
}

kotlin {
    jvmToolchain(21)
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_21
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.documentfile:documentfile:1.0.1")
    testImplementation("junit:junit:4.13.2")

    // docs/architecture.md §8 — VaultSync Bridge boundary.
    implementation("com.aeidolon.vaultsync:syncapi:$syncApiVersion")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    implementation("androidx.room:room-runtime:2.7.1")
    implementation("androidx.room:room-ktx:2.7.1")
    ksp("androidx.room:room-compiler:2.7.1")
}

androidComponents {
    onVariants { variant ->
        targetAbi?.let { target ->
            val excludes = mutableListOf<String>()
            if (target != "arm64-v8a") excludes.add("lib/arm64-v8a/*")
            if (target != "armeabi-v7a") excludes.add("lib/armeabi-v7a/*")
            if (target != "x86_64") excludes.add("lib/x86_64/*")
            if (target != "x86") excludes.add("lib/x86/*")

            variant.packaging.jniLibs.excludes.addAll(excludes)
        }
    }
}