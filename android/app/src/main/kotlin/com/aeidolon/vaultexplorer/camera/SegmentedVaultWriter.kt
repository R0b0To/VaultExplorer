package com.aeidolon.vaultexplorer.camera

import com.aeidolon.vaultexplorer.VeLog
import com.aeidolon.vaultexplorer.automation.VaultAutomationFolderOps
import com.aeidolon.vaultexplorer.container.ContainerFileSystem
import java.io.File

private const val TAG = "SegmentedVaultWriter"

/**
 * Saves the parts of a segmented recording straight into a vault, one by one,
 * as each part is closed. This is what a recording with no UI behind it (the
 * automation service) uses in place of the review-and-save step: there is
 * nobody to confirm anything, so every finished part is written, committed and
 * its plaintext temp file wiped as soon as it exists. Whatever is lost to a
 * crash or a kill is then at most the part still being recorded.
 *
 * Parts are named after the recording's own vault path, with the part number
 * added before the extension (see [partPath]): `Clips/VID_20261025_101500.mp4`
 * becomes `Clips/VID_20261025_101500_part001.mp4`, `..._part002.mp4` and so
 * on. A part name that is already taken in the vault is skipped (the vault
 * refuses to overwrite, and a part must never replace a file that was there
 * before), so numbering can have gaps but never collides.
 *
 * [save] calls are serialized: parts are numbered in the order they are saved,
 * so callers must hand them over in recording order.
 */
class SegmentedVaultWriter(
    private val volId: Int,
    private val basePath: String,
) {
    companion object {
        /**
         * Path of part [index] (1-based) of the recording at [basePath]: the
         * number goes before the extension of the file name, and is appended
         * when the name has none. A dot that only starts the file name (a
         * hidden file) or belongs to a folder name is not an extension.
         */
        fun partPath(basePath: String, index: Int): String {
            val suffix = "_part" + index.toString().padStart(3, '0')
            val slash = basePath.lastIndexOf('/')
            val dot = basePath.lastIndexOf('.')
            return if (dot > slash + 1) {
                basePath.substring(0, dot) + suffix + basePath.substring(dot)
            } else {
                basePath + suffix
            }
        }
    }

    private val lock = Any()

    /** Names already present in the target folder, plus the ones used so far. */
    private val takenNames: MutableSet<String> = HashSet()
    private var nextIndex = 1

    @Volatile
    var savedCount = 0
        private set

    @Volatile
    var failedCount = 0
        private set

    init {
        val parent = basePath.substringBeforeLast('/', "")
        try {
            ContainerFileSystem.listDirectory(volId, parent)?.forEach { raw ->
                VaultAutomationFolderOps.parseDirEntry(raw)?.let { takenNames.add(it.name) }
            }
        } catch (e: Exception) {
            // Without the listing a clash is only caught by the vault itself
            // refusing the write, which fails that one part.
            VeLog.w(TAG, e) { "could not list $parent to avoid existing names" }
        }
    }

    /**
     * Writes [file] into the vault as the next part and wipes it, whatever the
     * outcome. Returns whether the part is safely in the vault.
     */
    fun save(file: File): Boolean = synchronized(lock) {
        val path = nextFreePath()
        val ok = try {
            VaultVideoRecorder.streamFileToSinkAndWipe(file, VaultChunkWriter(volId, path)) &&
                ContainerFileSystem.finishWrite(volId, path)
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "saving a part failed" }
            false
        }
        if (ok) {
            savedCount++
        } else {
            failedCount++
            // A failed write can leave a truncated file behind. The name was
            // free when it was picked, so this can only remove that debris,
            // never a file that was already in the vault.
            try {
                ContainerFileSystem.deleteFile(volId, path)
            } catch (_: Exception) {
            }
            VaultVideoRecorder.secureDeleteFile(file)
        }
        ok
    }

    private fun nextFreePath(): String {
        while (true) {
            val candidate = partPath(basePath, nextIndex++)
            val name = candidate.substringAfterLast('/')
            if (takenNames.add(name)) return candidate
        }
    }
}
