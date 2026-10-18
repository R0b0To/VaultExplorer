package com.aeidolon.vaultexplorer.share

import com.aeidolon.vaultexplorer.DirEntryWire
import com.aeidolon.vaultexplorer.container.FolderZipWriter
import java.io.File
import java.io.FileInputStream
import java.io.IOException
import java.nio.ByteBuffer

/**
 * [FolderZipWriter.Source] over ordinary files on device storage -- the
 * decoy's local storage explorer, where the "vault" is just a directory on
 * the phone.
 *
 * Paths are absolute filesystem paths, which is what [FolderZipWriter]
 * already builds by appending `/name` to whatever root it is given. Pure
 * JVM (no Android types) so it can be unit tested against a temp directory.
 *
 * Every failure is loud rather than a quiet omission: an unreadable folder
 * (`listFiles()` returning null) surfaces as "could not list", and a file
 * that can't be opened throws, so a shared archive is either complete or
 * visibly failed -- see [FolderZipWriter]'s failure semantics.
 */
class RawFolderSource : FolderZipWriter.Source {

    override fun list(dirPath: String): Array<String>? {
        val children = File(dirPath).listFiles() ?: return null
        return Array(children.size) { i ->
            val child = children[i]
            val isDir = child.isDirectory
            DirEntryWire.encode(
                name = child.name,
                isDir = isDir,
                sizeBytes = if (isDir) 0L else child.length(),
                mtimeUnixSecs = child.lastModified() / 1000L,
            )
        }
    }

    override fun openFile(path: String): FolderZipWriter.FileReader {
        val file = File(path)
        val input = FileInputStream(file) // FileNotFoundException is an IOException
        return try {
            val channel = input.channel
            val fileLength = file.length()
            object : FolderZipWriter.FileReader {
                override val size: Long = fileLength

                override fun read(offset: Long, buffer: ByteArray, length: Int): Int {
                    val n = channel.read(ByteBuffer.wrap(buffer, 0, length), offset)
                    // FileChannel signals EOF with -1; the reader contract uses 0.
                    return if (n < 0) 0 else n
                }

                override fun close() {
                    try { input.close() } catch (_: IOException) {}
                }
            }
        } catch (e: Throwable) {
            try { input.close() } catch (_: IOException) {}
            throw e
        }
    }
}
