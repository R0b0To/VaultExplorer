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

# Disable class/method symbol obfuscation to eliminate DEX naming divergences across CPU core counts
-dontobfuscate