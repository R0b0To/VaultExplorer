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

# ── Reproducible Builds: pin class renaming ────────────────────────────────
# Without this, R8 assigns short obfuscated names (a, b, c... y0.i, y0.j...)
# to classes in whatever order it happens to process them internally. That
# processing order is not part of R8's guaranteed public contract -- it can
# differ between build environments (different R8/AGP versions, different
# JDK vendor/version running Gradle, different classpath jar ordering from
# dependency resolution, etc.), even when the input source and dependency
# versions are byte-identical. That's what produced the
#   'Ly0/j;' vs 'Ly0/i;'
# mismatch between the GitHub Actions and F-Droid builds.
#
# -repackageclasses forces every renamed class into ONE fixed package,
# which collapses R8's naming space down to something it assigns purely
# from the (deterministic, sorted) set of kept/processed class names,
# removing the environment-sensitive ordering as a variable.
-repackageclasses 'o'
-flattenpackagehierarchy 'o'
-allowaccessmodification