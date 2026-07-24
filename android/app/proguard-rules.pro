#Keep the entire package that interacts with your native C++ code
-keep class com.aeidolon.vaultexplorer.** { *; }
-keepclassmembers class com.aeidolon.vaultexplorer.** { *; }
-keep class org.videolan.libvlc.** { *; }

# Prevent ProGuard/R8 from renaming any native methods or their containing classes
-keepclasseswithmembernames class * {
    native <methods>;
}