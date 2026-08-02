import com.android.build.gradle.LibraryExtension

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// r28c, not plain r28 (28.0.13004108). The `jni` pub package's own native
// build resolves android.ndkVersion to 28.2.13676358 (r28c) regardless of
// what we set here -- AGP locks in the NDK version for CXX/CMake
// configuration earlier than this afterEvaluate override can reach, so
// trying to force it down to plain r28 just produces:
//   [CXX1104] NDK from ndk.dir at .../28.0.13004108 had version
//   [28.0.13004108] which disagrees with android.ndkVersion [28.2.13676358]
// NDKs are ABI-backward-compatible within a series, so pinning everything
// (this file, app/build.gradle.kts, build-release.yml's sdkmanager install,
// and metadata/com.aeidolon.vaultexplorer.yml's `ndk:` field) to r28c is
// the actual fix, not a workaround around the fix.
val ndkVersionPin = "28.2.13676358" // r28c

// ── Overrides ndkVersion AFTER subprojects evaluate ────────────────────────
// Kept as a safety net for any other native subproject that doesn't pin its
// own ndkVersion -- it just won't be the thing that saves :jni specifically,
// since that one pins its own version early enough to win regardless.
subprojects {
    afterEvaluate {
        plugins.withId("com.android.library") {
            val subprojectName = name
            extensions.configure<LibraryExtension>("android") {
                ndkVersion = ndkVersionPin
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
}

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