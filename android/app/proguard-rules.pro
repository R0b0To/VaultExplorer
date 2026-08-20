# --- Native (JNI) upcall targets ------------------------------------------
# JNI_OnLoad in jni_runtime.cpp resolves these classes and members by
# string name (FindClass/GetStaticMethodID/ThrowNew) exactly once, at
# native-library load time. That reference is invisible to R8's static
# analysis -- it's opaque native code -- so without an explicit keep these
# would look unused and get stripped or renamed, which fails at runtime
# (JNI_OnLoad returns JNI_ERR and the native engine never comes up) rather
# than at compile time. This replaces a blanket
# `-keep class com.aeidolon.vaultexplorer.** { *; }` that kept (and left
# unobfuscated) the entire app package -- everything below is the actual,
# audited set of classes/members native code touches by name; see each
# FindClass/GetStaticMethodID call in jni_runtime.cpp and
# session_guard.cpp/session_bridge.cpp for the corresponding site.
-keep class com.aeidolon.vaultexplorer.bridge.UsbBlockBridge {
    static byte[] readSectors(int, long, int);
    static boolean writeSectors(int, long, int, byte[]);
}
-keep class com.aeidolon.vaultexplorer.bridge.UnlockProgressBridge {
    static void reportProgress(int, int, int, int, int, int, int);
}
-keep class com.aeidolon.vaultexplorer.bridge.HiddenVolumeProtectionBridge {
    static void reportTriggered(int);
}
-keep class com.aeidolon.vaultexplorer.bridge.SplitJoinProgressBridge {
    static void reportProgress(int, long, long);
}
-keep class com.aeidolon.vaultexplorer.bridge.RepairLogBridge {
    static void reportLog(int, java.lang.String);
}
-keep class com.aeidolon.vaultexplorer.cancellation.SplitJoinCancellation {
    static boolean isCancelled(int);
}
# ThrowNew(g_unlockCancelledExceptionClass, "CANCELLED") needs the class
# name and its single (String) constructor intact -- see that class's own
# doc comment for why there's deliberately no default-value overload.
-keep class com.aeidolon.vaultexplorer.cancellation.UnlockCancelledException {
    <init>(java.lang.String);
}

# Prevent ProGuard/R8 from renaming any native methods or their containing
# classes. Broader than just our package on purpose: this is what actually
# protects any class that declares `external fun`, via the JVM's default
# Java_com_aeidolon_vaultexplorer_..._methodName symbol lookup -- the
# keep-all above was not what covered this case.
-keepclasseswithmembernames class * {
    native <methods>;
}

# --- Manifest-declared components -----------------------------------------
# Belt-and-suspenders alongside AGP's manifest-driven keep-rule generation:
# these are resolved by fully-qualified class name from
# AndroidManifest.xml (launcher activity, provider authorities, service
# name for the foreground-service intent), not from application code, so
# a purely code-based reachability analysis could plausibly miss why they
# need to survive.
-keep class com.aeidolon.vaultexplorer.MainActivity
-keep class com.aeidolon.vaultexplorer.container.ContainerDocumentsProvider
-keep class com.aeidolon.vaultexplorer.pdf.VaultPdfContentProvider
-keep class com.aeidolon.vaultexplorer.service.VaultKeepAliveService

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