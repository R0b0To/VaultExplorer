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

// ── Patch JNI CMakeLists.txt during Gradle Configuration Phase ─────────────
fun patchJniInPubCache() {
    val pubCacheEnv = System.getenv("PUB_CACHE")
    val userHome = System.getProperty("user.home")
    val localAppData = System.getenv("LOCALAPPDATA")

    val possibleCacheDirs = listOfNotNull(
        pubCacheEnv?.let { File(it) },
        File(userHome, ".pub-cache"),
        File("/tmp/.pub-cache"),
        rootProject.file("../.pub-cache"),
        if (localAppData != null) File(localAppData, "Pub/Cache") else null,
        File(userHome, "AppData/Local/Pub/Cache")
    )

    val existingDirs = possibleCacheDirs.filter { dir -> dir.exists() }

    var foundCount = 0
    var patchedCount = 0

    existingDirs.forEach { cacheDir ->
        cacheDir.walkTopDown()
            .filter { it.isFile && it.name == "CMakeLists.txt" && it.path.contains("jni-") }
            .forEach { cmakeFile ->
                foundCount++
                var text = cmakeFile.readText()
                    .replace("add_link_options(\"-Wl,--build-id=none\")\n", "")
                    .replace("add_link_options(\"-Wl,--build-id=none\")", "")

                if (!text.contains("CMAKE_SHARED_LINKER_FLAGS")) {
                    val patch = """
                        set(CMAKE_SHARED_LINKER_FLAGS "${'$'}{CMAKE_SHARED_LINKER_FLAGS} -Wl,--build-id=none")
                        add_compile_options("-ffile-prefix-map=${'$'}{CMAKE_SOURCE_DIR}=/jni")
                    """.trimIndent()
                    text = "$text\n$patch\n"
                    cmakeFile.writeText(text)
                    patchedCount++
                    logger.lifecycle("patch_jni_reproducibility: patched ${cmakeFile.absolutePath}")
                }
            }
    }
}

patchJniInPubCache()

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