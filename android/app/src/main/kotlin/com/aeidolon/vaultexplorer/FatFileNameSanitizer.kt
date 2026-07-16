package com.aeidolon.vaultexplorer

/**
 * Kotlin-side counterpart to lib/utils/filename_utils.dart's
 * sanitizeFatFileName(), for the one code path that builds FAT paths
 * without ever passing through Dart: MainActivity's SAF import flow
 * (importEntryRecursive and its two call sites in configureFlutterEngine).
 *
 * A file or folder picked from the device (Android SAF DocumentFile.name)
 * can legally contain a `|` or start with "[DIR] " if its source filesystem
 * permitted it — most commonly ext2/3/4 on a Linux-formatted drive, or a
 * name synced in from a Linux machine. See raw_entry.dart's doc comment for
 * exactly how those two shapes corrupt buildDirectoryListing()'s
 * "name|size|ts" wire format for that one entry once it lands in the
 * container.
 */
object FatFileNameSanitizer {
    private val invalidChars = Regex("[\\\\/:*?\"<>|]")

    fun sanitize(name: String): String {
        var result = invalidChars.replace(name, "_")
        if (result.startsWith("[DIR] ")) {
            result = "(DIR) " + result.substring(6)
        }
        return result
    }
}