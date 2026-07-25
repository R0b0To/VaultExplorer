package com.aeidolon.vaultexplorer

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService

/**
 * SAF pickers for every vault type: the classic single-file
 * ACTION_OPEN_DOCUMENT picker for VeraCrypt/LUKS/BitLocker containers, the
 * ACTION_OPEN_DOCUMENT_TREE folder picker for the three directory-backed
 * vault formats (Cryptomator, gocryptfs, CryFS), and the multi-select
 * keyfile picker. Each pick launcher must be registered on the Activity
 * before it leaves the CREATED state, so this class has to be constructed
 * as an eager (non-lazy) MainActivity property — see the launcher
 * properties below, and [NativeOpSupport]'s doc comment for the related
 * "don't touch Context in a constructor" trap this class avoids by only
 * ever reading activity.contentResolver inside a launcher callback (never
 * at construction time).
 */
class VaultPickerHandlers(
    private val activity: MainActivity,
    private val pendingResult: PendingActivityResult,
    private val ioExecutor: ExecutorService,
) {
    private fun detectVaultFormatInFolder(uri: Uri): String? {
        if (com.aeidolon.vaultexplorer.cryfs.CryfsVault.looksLikeVault(activity, uri)) return "cryfs"
        if (com.aeidolon.vaultexplorer.cryptomator.CryptomatorVault.looksLikeVault(activity, uri)) return "cryptomator"
        if (com.aeidolon.vaultexplorer.gocryptfs.GocryptfsVault.looksLikeVault(activity, uri)) return "gocryptfs"
        return null
    }

    private val pickContainerLauncher = activity.registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { activityResult ->
        val res = pendingResult.take() ?: return@registerForActivityResult
        val data = activityResult.data
        if (activityResult.resultCode == Activity.RESULT_OK && data?.data != null) {
            val uri = data.data!!
            ioExecutor.execute {
                try {
                    activity.contentResolver.takePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                    )
                } catch (_: SecurityException) {}
                val name = UriNameResolver.resolve(activity.contentResolver, uri)
                activity.runOnUiThread {
                    res.success(mapOf(
                        "uri" to uri.toString(),
                        "displayName" to name
                    ))
                }
            }
        } else {
            res.success(null)
        }
    }

    private val pickCryptomatorVaultLauncher = activity.registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { activityResult ->
        val res = pendingResult.take() ?: return@registerForActivityResult
        val data = activityResult.data
        if (activityResult.resultCode == Activity.RESULT_OK && data?.data != null) {
            val uri = data.data!!
            ioExecutor.execute {
                try {
                    activity.contentResolver.takePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                    )
                } catch (_: SecurityException) {}
                val format = detectVaultFormatInFolder(uri)
                val name = UriNameResolver.resolve(activity.contentResolver, uri)
                activity.runOnUiThread {
                    res.success(mapOf(
                        "uri" to uri.toString(),
                        "displayName" to name,
                        "looksLikeVault" to (format != null),
                        "format" to format,
                    ))
                }
            }
        } else {
            res.success(null)
        }
    }

    private val pickGocryptfsVaultLauncher = activity.registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { activityResult ->
        val res = pendingResult.take() ?: return@registerForActivityResult
        val data = activityResult.data
        if (activityResult.resultCode == Activity.RESULT_OK && data?.data != null) {
            val uri = data.data!!
            ioExecutor.execute {
                try {
                    activity.contentResolver.takePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                    )
                } catch (_: SecurityException) {}
                val format = detectVaultFormatInFolder(uri)
                val name = UriNameResolver.resolve(activity.contentResolver, uri)
                activity.runOnUiThread {
                    res.success(mapOf(
                        "uri" to uri.toString(),
                        "displayName" to name,
                        "looksLikeVault" to (format != null),
                        "format" to format,
                    ))
                }
            }
        } else {
            res.success(null)
        }
    }

    private val pickCryfsVaultLauncher = activity.registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { activityResult ->
        val res = pendingResult.take() ?: return@registerForActivityResult
        val data = activityResult.data
        if (activityResult.resultCode == Activity.RESULT_OK && data?.data != null) {
            val uri = data.data!!
            ioExecutor.execute {
                try {
                    activity.contentResolver.takePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                    )
                } catch (_: SecurityException) {}
                val format = detectVaultFormatInFolder(uri)
                val name = UriNameResolver.resolve(activity.contentResolver, uri)
                activity.runOnUiThread {
                    res.success(mapOf(
                        "uri" to uri.toString(),
                        "displayName" to name,
                        "looksLikeVault" to (format != null),
                        "format" to format,
                    ))
                }
            }
        } else {
            res.success(null)
        }
    }

    private val pickKeyfilesLauncher = activity.registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { activityResult ->
        val res = pendingResult.take() ?: return@registerForActivityResult
        val data = activityResult.data
        if (activityResult.resultCode != Activity.RESULT_OK || data == null) {
            res.success(null)
            return@registerForActivityResult
        }
        val uris = mutableListOf<Uri>()
        data.clipData?.let { clip ->
            for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri)
        }
        if (uris.isEmpty()) data.data?.let { uris.add(it) }

        val picked = uris.mapNotNull { uri ->
            try {
                activity.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            } catch (_: SecurityException) {}
            try {
                mapOf(
                    "uri" to uri.toString(),
                    "displayName" to UriNameResolver.resolve(activity.contentResolver, uri)
                )
            } catch (_: Exception) { null }
        }
        res.success(picked)
    }

    fun handlePickContainer(call: MethodCall, result: MethodChannel.Result) {
        pendingResult.stash(result)
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
        }
        pickContainerLauncher.launch(intent)
    }

    fun handlePickCryptomatorVault(call: MethodCall, result: MethodChannel.Result) {
        pendingResult.stash(result)
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
        pickCryptomatorVaultLauncher.launch(intent)
    }

    fun handlePickGocryptfsVault(call: MethodCall, result: MethodChannel.Result) {
        pendingResult.stash(result)
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
        pickGocryptfsVaultLauncher.launch(intent)
    }

    fun handlePickCryfsVault(call: MethodCall, result: MethodChannel.Result) {
        pendingResult.stash(result)
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
        pickCryfsVaultLauncher.launch(intent)
    }

    fun handlePickKeyfiles(call: MethodCall, result: MethodChannel.Result) {
        pendingResult.stash(result)
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        }
        pickKeyfilesLauncher.launch(intent)
    }
}
