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

tasks.whenTaskAdded {
    if (name.contains("ArtProfile")) {
        enabled = false
    }
}

tasks.matching { it.name == "packageDebugUnitTestForUnitTest" }.configureEach {
    mustRunAfter("copyFlutterAssetsDebug")
}

val ndkVersionPin = "28.2.13676358"

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
    compileSdkExtension = 19 
    ndkVersion = ndkVersionPin
    buildToolsVersion = "37.0.0"

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
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

    // Robolectric needs the merged manifest/resources available to unit
    // tests (Context, ContentResolver, DocumentFile.fromFile all rely on
    // it). Added alongside the ChunkedFileEngineTest suite -- see that
    // test's class doc for what it covers.
    testOptions {
        unitTests {
            isIncludeAndroidResources = true
        }
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
    implementation("androidx.media3:media3-exoplayer:1.11.0")
    implementation("androidx.media3:media3-ui:1.11.0")
    implementation("androidx.media3:media3-session:1.11.0")
    implementation("androidx.media3:media3-datasource:1.11.0")
    implementation("androidx.pdf:pdf-viewer-fragment:1.0.0-alpha19")
    implementation("androidx.pdf:pdf-core:1.0.0-alpha19")
    implementation("com.google.android.material:material:1.13.0")
    implementation("androidx.exifinterface:exifinterface:1.3.7")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
    // Added for ChunkedFileEngineTest, which needs a real (shadowed)
    // Context/ContentResolver to exercise DocumentFile-backed reads --
    // ChunkedFileEngine previously had zero test coverage despite being the
    // shared chunked-read/seek/cache engine gocryptfs and Cryptomator route
    // every read through, including a documented, unmitigated eviction
    // race (see the comment above ChunkedFileEngine.openReads).
    testImplementation("org.robolectric:robolectric:4.13")
    testImplementation("androidx.test:core:1.6.1")
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