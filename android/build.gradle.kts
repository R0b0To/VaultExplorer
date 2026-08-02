import com.android.build.gradle.LibraryExtension

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val ndkVersionPin = "28.0.13004108" // r28

// ── Overrides ndkVersion & CMake prefix-maps across ALL pub packages (including :jni) ──
subprojects {
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