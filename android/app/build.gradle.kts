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

// ── From-source build steps, run automatically before every build ─────────
// Both are the single source of truth for local dev, the GitHub Actions
// release workflow, and F-Droid's build alike -- none of those pipelines
// vendor a prebuilt file or duplicate a patch script of their own anymore.

val buildPdfJs = tasks.register<Exec>("buildPdfJsAssets") {
    description = "Builds the pdf.js viewer bundle from source " +
            "(scripts/build_pdfjs.sh). No-op if already built."
    val repoRoot = rootProject.file("..")
    workingDir = repoRoot
    commandLine("bash", "scripts/build_pdfjs.sh")
    inputs.file(repoRoot.resolve("scripts/build_pdfjs.sh"))
    outputs.dir("src/main/assets/pdfjs")
}

val patchJniForReproducibility = tasks.register("patchJniForReproducibility") {
    description = "Patches the jni pub package's own CMakeLists.txt so " +
            "libdartjni.so doesn't embed a random build ID -- otherwise " +
            "breaks F-Droid Reproducible Builds verification."

    doLast {
        val pubCacheEnv = System.getenv("PUB_CACHE")
        val userHome = System.getProperty("user.home")
        val localAppData = System.getenv("LOCALAPPDATA")

        val possibleCacheDirs = listOfNotNull(
            pubCacheEnv?.let { File(it) },
            File(userHome, ".pub-cache"),
            if (localAppData != null) File(localAppData, "Pub/Cache") else null,
            File(userHome, "AppData/Local/Pub/Cache")
        )

        val pubCacheDir = possibleCacheDirs.firstOrNull { it.exists() }
        if (pubCacheDir == null) {
            logger.warn("warning: pub cache directory not found -- skipping patchJniForReproducibility.")
            return@doLast
        }

        val hostedDirs = listOf(
            File(pubCacheDir, "hosted/pub.dev"),
            File(pubCacheDir, "hosted/pub.dartlang.org")
        )

        val jniDir = hostedDirs.firstOrNull { it.exists() }
            ?.listFiles { file -> file.isDirectory && file.name.startsWith("jni-") }
            ?.firstOrNull()

        if (jniDir == null) {
            logger.warn("warning: no jni-* package found under pub cache -- skipping.")
            return@doLast
        }

        var patchedCount = 0
        jniDir.walkTopDown()
            .filter { it.isFile && it.name == "CMakeLists.txt" }
            .forEach { cmakeFile ->
                val content = cmakeFile.readText()
                if (!content.contains("-Wl,--build-id=none")) {
                    cmakeFile.appendText("\nadd_link_options(\"-Wl,--build-id=none\")\n")
                    patchedCount++
                }
            }

        logger.lifecycle("patch_jni_reproducibility: patched $patchedCount CMakeLists.txt file(s) under ${jniDir.absolutePath}")
    }
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
                // -ffile-prefix-map normalizes the absolute source/build
                // path baked into debug info and __FILE__/assert strings,
                // so the same source produces byte-identical output
                // whether it's checked out to /home/runner/work/... on
                // GitHub Actions or wherever F-Droid's buildserver checks
                // it out to. Required for F-Droid Reproducible Builds
                // verification -- this is the correct way to normalize the
                // build path, unlike forcing both environments to use the
                // same literal absolute directory.
                val prefixMap = "-ffile-prefix-map=${rootProject.rootDir}=/build"
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

// patchJniForReproducibility must run after `flutter pub get` has actually
// populated the pub-cache with the jni package -- true by the time preBuild
// fires in every real invocation (flutter build/run always resolves
// dependencies before touching Gradle), so no explicit ordering needed
// beyond both being preBuild dependencies.
tasks.named("preBuild").configure {
    dependsOn(buildPdfJs)
    dependsOn(patchJniForReproducibility)
}