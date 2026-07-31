# Keep the entire package that interacts with your native C++ code
-keep class com.aeidolon.vaultexplorer.** { *; }
-keepclassmembers class com.aeidolon.vaultexplorer.** { *; }

# Prevent ProGuard/R8 from renaming any native methods or their containing classes
-keepclasseswithmembernames class * {
    native <methods>;
}

# Force deterministic R8 obfuscation and constant SourceFile attribute for Reproducible Builds
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile