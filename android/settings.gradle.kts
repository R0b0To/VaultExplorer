pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
    id("com.google.devtools.ksp") version "2.3.10" apply false
}

include(":app")

val syncApiDir = rootDir.resolve("../vaultsync-syncapi")
check(syncApiDir.resolve("VERSION").isFile) {
    "vaultsync-syncapi submodule not found at $syncApiDir.\n" +
        "Run 'git submodule update --init --recursive' from the repo root, then re-sync."
}

run {
    val sdkDir = java.util.Properties().apply {
        file("local.properties").inputStream().use { load(it) }
    }.getProperty("sdk.dir")
    if (sdkDir != null) {
        val syncApiProps = java.util.Properties()
        syncApiProps.setProperty("sdk.dir", sdkDir)
        syncApiDir.resolve("local.properties").outputStream().use {
            syncApiProps.store(it, null)
        }
    }
}

includeBuild(syncApiDir) {
    dependencySubstitution {
        substitute(module("com.aeidolon.vaultsync:syncapi"))
            .using(project(":syncapi"))
    }
}

gradle.extra["syncApiVersion"] = syncApiDir.resolve("VERSION").readText().trim()