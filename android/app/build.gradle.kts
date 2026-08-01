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


// ── Reproducibility fix for the `jni` pub package's native build ───────────
// Replaces the old approach of walking the pub cache and rewriting
// CMakeLists.txt in place (fragile: mutates a shared cache dir, depends on
// matching a version-specific folder name, needs manual idempotency
// bookkeeping). This is F-Droid's documented approach for this exact
// package: https://f-droid.org/docs/Reproducible_Builds/#cmake -- configure
// the `jni` library subproject's own externalNativeBuild directly through
// Gradle's project graph instead of touching files on disk.
rootProject.subprojects {
    plugins.withId("com.android.library") {
        if (name == "jni") {
            extensions.configure<LibraryExtension>("android") {
                defaultConfig {
                    externalNativeBuild {
                        cmake {
                            arguments += "-DCMAKE_SHARED_LINKER_FLAGS=-Wl,--build-id=none"
                            cFlags += "-ffile-prefix-map=${rootDir}=/jni"
                            cppFlags += "-ffile-prefix-map=${rootDir}=/jni"
                        }
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
    ndkVersion = flutter.ndkVersion
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
                    "-DCMAKE_SHARED_LINKER_FLAGS=-Wl,-z,max-page-size=16384 -Wl,--build-id=none",
                    "-DCMAKE_MODULE_LINKER_FLAGS=-Wl,-z,max-page-size=16384 -Wl,--build-id=none"
                )
                val repoRootDir = rootProject.file("..").canonicalPath
                val prefixMap = "-ffile-prefix-map=$repoRootDir=/build"
                cFlags("-O3", "-funroll-loops", prefixMap)
                cppFlags("-O3", "-funroll-loops", prefixMap)
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

tasks.named("preBuild").configure {
    dependsOn(buildPdfJs)
}