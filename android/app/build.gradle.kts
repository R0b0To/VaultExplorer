import java.util.Properties
import com.android.build.gradle.LibraryExtension

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


// ── Reproducibility fix for pub packages' native builds ────────────────────
// Replaces the old approach of walking the pub cache and rewriting
// CMakeLists.txt in place (fragile: mutates a shared cache dir, depends on
// matching a version-specific folder name, needs manual idempotency
// bookkeeping). This is F-Droid's documented approach for this exact
// package: https://f-droid.org/docs/Reproducible_Builds/#cmake -- configure
// each native library subproject's own externalNativeBuild directly through
// Gradle's project graph instead of touching files on disk.
//
// NOTE on a bug this fixes: the original version of this block used bare
// `rootDir` in the prefix-map source (`-ffile-prefix-map=${rootDir}=/jni`).
// `rootDir` on a Gradle Project always resolves to the *root* project's
// directory (i.e. android/), no matter which project's script block you
// read it from -- it is not "the current project's directory". The `jni`
// pub package's sources compile from inside PUB_CACHE (e.g.
// $PUB_CACHE/hosted/pub.dev/jni-<version>/), which is never a subpath of
// android/, so that prefix-map never matched anything and was a silent
// no-op: the built library kept embedding the absolute PUB_CACHE path,
// which differs between every build environment (CI uses one PUB_CACHE
// location, the F-Droid buildserver recipe another, an unset local shell a
// third). `projectDir`, used below, is each subproject's own directory and
// is correct regardless of where PUB_CACHE happens to point.
//
// Applied to every native-code Android library subproject rather than just
// "jni" by name, so any pub package added later that ships its own
// CMake/NDK build gets the same fix automatically instead of silently
// falling back to unreproducible defaults.
rootProject.subprojects {
    plugins.withId("com.android.library") {
        val subprojectName = name
        extensions.configure<LibraryExtension>("android") {
            defaultConfig {
                externalNativeBuild {
                    cmake {
                        arguments += "-DCMAKE_SHARED_LINKER_FLAGS=-Wl,--build-id=none,--hash-style=gnu"
                        arguments += "-DCMAKE_MODULE_LINKER_FLAGS=-Wl,--build-id=none,--hash-style=gnu"
                        cFlags += listOf("-ffile-prefix-map=${projectDir}=/native-$subprojectName", "-fno-ident")
                        cppFlags += listOf("-ffile-prefix-map=${projectDir}=/native-$subprojectName", "-fno-ident")
                    }
                }
            }
        }
    }
}

// ── From-source build steps ───────────────────────────────────────────────
val buildPdfJs = tasks.register<Exec>("buildPdfJsAssets") {
    description = "Builds the pdf.js viewer bundle from source (scripts/build_pdfjs.sh)."
    val repoRoot = rootProject.file("..")
    workingDir = repoRoot
    commandLine("bash", "scripts/build_pdfjs.sh")
    inputs.file(repoRoot.resolve("scripts/build_pdfjs.sh"))
    outputs.dir("src/main/assets/pdfjs")
}

android {
    namespace = "com.aeidolon.vaultexplorer"
    compileSdk = flutter.compileSdkVersion
    // Pinned explicitly (not `flutter.ndkVersion`) to match the exact NDK
    // both build-release.yml and metadata/com.aeidolon.vaultexplorer.yml
    // install. `flutter.ndkVersion` is whatever the local Flutter SDK
    // install declares as its default, which can drift silently between
    // machines/Flutter patch releases even when everything else matches --
    // and different NDK builds are one of the two things (along with build
    // paths) that reliably produce different native library bytes.
    ndkVersion = "28.2.13676358" // r28d
    // Pinned below compile-tools 35: apksigner from build-tools >=35.0.0-rc1
    // produces APKs that fail apksigcopier verification even when byte-
    // identical. https://f-droid.org/docs/Reproducible_Builds/#apksigner-from-build-tools--3500-rc1-outputs-unverifiable-apks
    buildToolsVersion = "34.0.0"

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
            }
        }
    }

    // Per-ABI product flavors for F-Droid submission. F-Droid's build model
    // is one metadata Build entry = one versionCode = one output APK -- it
    // does not support a single build producing several simultaneous
    // outputs the way `flutter build apk --split-per-abi` does (confirmed
    // against the current Build Metadata Reference: `output:` is documented
    // singular, and reports of --split-per-abi's multi-output failing the
    // buildserver). The documented mechanism for multiple ABI-specific APKs
    // is one Build entry per flavor, combined with `VercodeOperation` for
    // distinct versionCodes -- see metadata/com.aeidolon.vaultexplorer.yml.
    // Each entry's flavor is selected by passing its name as an argument to
    // scripts/reproducible_build.sh, not via metadata's `gradle:` field --
    // this project needs `flutter build apk`, not a bare
    // `gradle assemble<Flavor>Release`, since only `flutter build` runs the
    // Dart-side codegen/asset bundling a raw Gradle invocation wouldn't.
    //
    // Flavor names here must stay in sync with both of those.
    flavorDimensions += "abi"
    productFlavors {
        create("arm64") {
            dimension = "abi"
            ndk { abiFilters += "arm64-v8a" }
            externalNativeBuild { cmake { abiFilters += "arm64-v8a" } }
        }
        create("armeabi") {
            dimension = "abi"
            ndk { abiFilters += "armeabi-v7a" }
            externalNativeBuild { cmake { abiFilters += "armeabi-v7a" } }
        }
        create("x64") {
            dimension = "abi"
            ndk { abiFilters += "x86_64" }
            externalNativeBuild { cmake { abiFilters += "x86_64" } }
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

            // AGP >=8.3 bundles META-INF/version-control-info.textproto by
            // default, which includes `local_root_path: "$PROJECT_DIR"` --
            // an absolute filesystem path, embedded verbatim. GitHub
            // Actions, the F-Droid buildserver, and local dev all check
            // this repo out to different absolute paths, so leaving this on
            // guarantees a diff regardless of anything else here.
            // https://f-droid.org/docs/Reproducible_Builds/#vcs-info
            vcsInfo.include = false
        }
    }
}

// Must exactly match the multiplier/offsets in
// metadata/com.aeidolon.vaultexplorer.yml's `VercodeOperation` list -- the
// F-Droid buildserver checks the built APK's manifest versionCode against
// what the metadata declares for that Build entry and fails the build on
// a mismatch (this is not just cosmetic bookkeeping).
val abiVersionCodeOffsets = mapOf(
    "arm64" to 1,
    "armeabi" to 2,
    "x64" to 3,
)

androidComponents {
    onVariants { variant ->
        val offset = abiVersionCodeOffsets[variant.flavorName] ?: return@onVariants
        variant.outputs.forEach { output ->
            output.versionCode.set(flutter.versionCode * 100 + offset)
        }
    }
}

kotlin {
    // Forces Gradle to provision/select an actual JDK 17 toolchain (via the
    // Foojay resolver) for both Kotlin and the Java compile tasks it
    // configures in this Android project, regardless of whatever JDK
    // happens to be on PATH/JAVA_HOME on the machine invoking Gradle.
    // `compileOptions.sourceCompatibility`/`targetCompatibility` above and
    // `jvmTarget` below only constrain the *language level* of the output,
    // not which JDK build actually runs the compiler -- two different JDK
    // 17 distributions (or a JDK 21 run in "17 mode") can still emit
    // slightly different classes.dex bytes. See F-Droid's "Mismatched
    // Toolchains" section.
    jvmToolchain(17)
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

tasks.named("preBuild").configure {
    dependsOn(buildPdfJs)
}