import com.android.build.api.variant.LibraryAndroidComponentsExtension

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val ndkVersionPin = "28.2.13676358" // r28c

// Helper to determine target ABI from ENV or Flutter's target-platform property
val targetAbi: String? = System.getenv("VAULTEXPLORER_TARGET_ABI")
    ?: when (providers.gradleProperty("target-platform").orNull) {
        "android-arm64" -> "arm64-v8a"
        "android-arm"   -> "armeabi-v7a"
        "android-x64"   -> "x86_64"
        "android-x86"   -> "x86"
        else            -> null
    }

// ── Overrides ndkVersion & abiFilters AFTER library DSL evaluates ────────────
subprojects {
    plugins.withId("com.android.library") {
        // Gradle 9 requires the launcher explicitly for library tests using JUnit Platform.
        dependencies.add("testRuntimeOnly", "org.junit.platform:junit-platform-launcher:1.11.4")
        val subprojectName = name
        val subprojectDir = projectDir
        extensions.configure<LibraryAndroidComponentsExtension>("androidComponents") {
            finalizeDsl { android ->
                android.ndkVersion = ndkVersionPin
                android.defaultConfig {
                    // Restrict library plugin NDK & CMake builds (like :jni) to target ABI
                    targetAbi?.let { abi ->
                        ndk {
                            abiFilters.clear()
                            abiFilters.add(abi)
                        }
                        externalNativeBuild {
                            cmake {
                                abiFilters.clear()
                                abiFilters.add(abi)
                            }
                        }
                    }

                    externalNativeBuild {
                        cmake {
                            arguments += "-DCMAKE_SHARED_LINKER_FLAGS=-Wl,--build-id=none,--hash-style=gnu"
                            arguments += "-DCMAKE_MODULE_LINKER_FLAGS=-Wl,--build-id=none,--hash-style=gnu"
                            cFlags += listOf("-ffile-prefix-map=$subprojectDir=/native-$subprojectName", "-fno-ident")
                            cppFlags += listOf("-ffile-prefix-map=$subprojectDir=/native-$subprojectName", "-fno-ident")
                        }
                    }
                }
            }
        }
    }
}

// ── Flutter Build Directory Relocation ───────────────────────────────────────
val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}