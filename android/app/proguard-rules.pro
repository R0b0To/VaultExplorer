# Keep the entire package that interacts with native C++ code
-keep class com.aeidolon.vaultexplorer.** { *; }
-keepclassmembers class com.aeidolon.vaultexplorer.** { *; }

# Prevent ProGuard/R8 from renaming any native methods or their containing classes
-keepclasseswithmembernames class * {
    native <methods>;
}

# Force deterministic R8 builds
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# Strip verbose/debug logging from release builds (defense-in-depth on top of
# not interpolating decrypted paths/filenames into log calls in the first
# place). Log.e/Log.w are kept since they carry no path data after the
# redaction pass and are useful for crash triage.
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
}

# Media3 / ExoPlayer — native player pipeline
-keep class androidx.media3.** { *; }
-dontwarn androidx.media3.**