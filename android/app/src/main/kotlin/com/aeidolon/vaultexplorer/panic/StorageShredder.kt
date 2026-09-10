package com.aeidolon.vaultexplorer.panic

import android.content.Context
import java.io.File
import com.aeidolon.vaultexplorer.SecureFileWipe
import com.aeidolon.vaultexplorer.VeLog
import org.json.JSONArray

object StorageShredder {
    private const val TAG = "PanicManager_Storage"

    fun securelyClearPrefsFile(context: Context, prefsName: String): Boolean {
        var ok = true
        try {
            context.getSharedPreferences(prefsName, Context.MODE_PRIVATE).edit().clear().commit()
        } catch (e: Exception) {
            VeLog.w(TAG, e) { "securelyClearPrefsFile: clear() failed" }
            ok = false
        }
        val prefsFile = File(File(context.applicationInfo.dataDir, "shared_prefs"), "$prefsName.xml")
        if (prefsFile.exists() && !SecureFileWipe.secureDeleteFile(prefsFile)) {
            ok = false
        }
        return ok
    }

    /**
     * Tier 1 helper: Clears remembered vault passwords, PINs, patterns, and cached derived keys,
     * resetting containers to manual password entry in containers_v2.json while keeping the vault
     * cards on the dashboard and keeping master password and app settings untouched.
     */
    fun clearVaultCredentials(context: Context): Int {
        var count = 0

        // 1. Clear vc2_derived_keys shared preferences
        try {
            val derivedPrefs = context.getSharedPreferences("vc2_derived_keys", Context.MODE_PRIVATE)
            count += derivedPrefs.all.size
            derivedPrefs.edit().clear().commit()
        } catch (e: Exception) {
            VeLog.w(TAG, e) { "clearVaultCredentials: clear vc2_derived_keys failed" }
        }

        // 2. Clear vault password, pin, pattern keys from vaultexplorer_app_secure_storage
        try {
            val securePrefs = context.getSharedPreferences("vaultexplorer_app_secure_storage", Context.MODE_PRIVATE)
            val editor = securePrefs.edit()
            for (key in securePrefs.all.keys) {
                if (key.startsWith("vc2_pw_") ||
                    key.startsWith("vc2_pattern_") ||
                    key.startsWith("vc2_pin_hash_")
                ) {
                    editor.remove(key)
                    count++
                }
            }
            editor.commit()
        } catch (e: Exception) {
            VeLog.w(TAG, e) { "clearVaultCredentials: clear vault keys from secure storage failed" }
        }

        // 3. Purge AndroidKeyStore aliases for cached derived keys (prefix vc2_derived_)
        try {
            val keyStore = java.security.KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            val aliases = java.util.Collections.list(keyStore.aliases())
            for (alias in aliases) {
                if (alias.startsWith("vc2_derived_")) {
                    keyStore.deleteEntry(alias)
                    count++
                }
            }
        } catch (e: Exception) {
            VeLog.w(TAG, e) { "clearVaultCredentials: purge vc2_derived_ keystore aliases failed" }
        }

        // 4. Update containers_v2.json in app_flutter so containers reset to manual password
        try {
            val dataDir = File(context.applicationInfo.dataDir)
            val appFlutterDir = File(dataDir, "app_flutter")
            val containersFile = File(appFlutterDir, "containers_v2.json")
            if (containersFile.exists()) {
                val jsonStr = containersFile.readText()
                val jsonArray = JSONArray(jsonStr)
                for (i in 0 until jsonArray.length()) {
                    val obj = jsonArray.getJSONObject(i)
                    obj.put("rememberPassword", false)
                    obj.put("unlockMethod", "password")
                    obj.put("cacheDerivedKey", false)
                }
                containersFile.writeText(jsonArray.toString())
                count++
            }
        } catch (e: Exception) {
            VeLog.w(TAG, e) { "clearVaultCredentials: update containers_v2.json failed" }
        }

        VeLog.i(TAG) { "clearVaultCredentials: cleared $count vault credential item(s)" }
        return count
    }

    /**
     * Tier 2 helper: Identity Reset.
     * Deletes containers_v2.json and app_settings.json, purging all knowledge of saved vaults
     * and resetting app settings/master password to factory defaults without deleting external vault files.
     */
    fun purgeCredentialStores(context: Context): Int {
        var cleared = 0
        val names = PanicPurgeRegistry.credentialPrefsNames
        for (name in names) {
            if (securelyClearPrefsFile(context, name)) cleared++
        }

        val dataDir = File(context.applicationInfo.dataDir)
        val appFlutterDir = File(dataDir, "app_flutter")
        if (appFlutterDir.exists()) {
            val containersFile = File(appFlutterDir, "containers_v2.json")
            if (containersFile.exists() && SecureFileWipe.secureDeleteFile(containersFile)) {
                cleared++
            }
            val settingsFile = File(appFlutterDir, "app_settings.json")
            if (settingsFile.exists() && SecureFileWipe.secureDeleteFile(settingsFile)) {
                cleared++
            }
        }

        VeLog.i(TAG) { "purgeCredentialStores: cleared $cleared store(s)/file(s)" }
        return cleared
    }

    fun wipeDirectoryRecursively(dir: File?): Int {
        if (dir == null || !dir.exists()) return 0
        var wiped = 0
        try {
            dir.walkBottomUp().forEach { entry ->
                if (entry == dir) return@forEach
                try {
                    if (entry.isFile) {
                        if (SecureFileWipe.secureDeleteFile(entry)) wiped++
                    } else if (entry.isDirectory) {
                        entry.delete()
                    }
                } catch (e: Exception) {
                    VeLog.w(TAG, e) { "wipeDirectoryRecursively: failed on one entry, continuing" }
                }
            }
        } catch (e: Exception) {
            VeLog.w(TAG, e) { "wipeDirectoryRecursively: failed partway through ${dir.name}" }
        }
        return wiped
    }

    /**
     * Tier 3 Nuclear Wipe: shreds EVERYTHING inside dataDir (including app_flutter,
     * files, cache, shared_prefs, databases, no_backup), skipping only the system "lib" directory.
     * Also wipes all external files and cache directories.
     */
    fun wipeAllInternalStorage(context: Context): Int {
        val dataDir = File(context.applicationInfo.dataDir)
        var total = 0
        if (dataDir.exists()) {
            dataDir.listFiles()?.forEach { entry ->
                if (entry.name != "lib") {
                    total += if (entry.isDirectory) {
                        wipeDirectoryRecursively(entry)
                    } else if (entry.isFile) {
                        if (SecureFileWipe.secureDeleteFile(entry)) 1 else 0
                    } else 0
                }
            }
        }

        val appFlutterDir = File(dataDir, "app_flutter")
        if (appFlutterDir.exists()) {
            total += wipeDirectoryRecursively(appFlutterDir)
        }
        total += wipeDirectoryRecursively(context.filesDir)
        total += wipeDirectoryRecursively(context.cacheDir)
        total += wipeDirectoryRecursively(context.noBackupFilesDir)

        context.getExternalFilesDirs(null)?.forEach { extDir ->
            total += wipeDirectoryRecursively(extDir)
        }
        context.externalCacheDirs?.forEach { extCache ->
            total += wipeDirectoryRecursively(extCache)
        }

        VeLog.i(TAG) { "wipeAllInternalStorage: wiped $total file(s)" }
        return total
    }
}