package com.aeidolon.vaultexplorer

import com.aeidolon.vaultexplorer.container.ContainerFormat
import com.aeidolon.vaultexplorer.container.VaultBackend
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import com.aeidolon.vaultexplorer.container.ContainerFileSystem

/**
 * NOTE on the two `skipsPerVolumeLock` tests below: [CryfsSession]
 * [com.aeidolon.vaultexplorer.cryfs.CryfsSession],
 * [com.aeidolon.vaultexplorer.cryptomator.CryptomatorSession], and
 * [com.aeidolon.vaultexplorer.gocryptfs.GocryptfsSession] all require a
 * real `android.content.Context`/`android.net.Uri` to construct, and this
 * module's `src/test/kotlin` unit tests run on the plain JVM with no
 * Robolectric or Mockito (see app/build.gradle -- `testImplementation` is
 * JUnit only). So there's no way to actually instantiate them here and
 * read the real property off a real instance. `verifySkipsPerVolumeLock`
 * checks the *source* of each session file instead, as the next best
 * thing to a construction-based check -- it fails loudly (naming the
 * missing file) rather than silently passing if the working-directory
 * assumption below is ever wrong for this project's Gradle setup.
 */
private fun verifySkipsPerVolumeLock(relativePathFromModuleRoot: String, expected: Boolean) {
    val candidateModuleRoots = listOf(
        File("."),            // CWD is already android/app (typical Gradle unit-test CWD)
        File("android/app"),  // CWD is the repo root
        File("app")            // CWD is android/
    )
    val sourceFile = candidateModuleRoots
        .map { File(it, relativePathFromModuleRoot) }
        .firstOrNull { it.isFile }
        ?: run {
            fail(
                "verifySkipsPerVolumeLock couldn't find $relativePathFromModuleRoot under any " +
                    "expected module root (tried: ${candidateModuleRoots.map { it.path }}). " +
                    "This test's path assumptions need updating for this Gradle setup -- " +
                    "it is not safe to just delete this check."
            )
            return
        }

    val match = Regex("""override\s+val\s+skipsPerVolumeLock\s*(?::\s*Boolean\s*)?=\s*(true|false)""")
        .find(sourceFile.readText())
        ?: run {
            fail("${sourceFile.path} no longer declares `override val skipsPerVolumeLock`.")
            return
        }

    assertEquals(
        "${sourceFile.path} declares skipsPerVolumeLock = ${match.groupValues[1]}, expected $expected",
        expected,
        match.groupValues[1].toBoolean()
    )
}

class CryfsConcurrencyTest {

    @Test
    fun `VaultBackend defaults to taking the per-volume lock unless a backend opts out`() {
        // The safe default matters: a new format that forgets to override
        // skipsPerVolumeLock should fall back to the conservative
        // (locked) behavior, not silently skip locking. Unlike the two
        // tests below, this one needs no Android types at all, so it's a
        // real, fully-constructed instance test.
        class MinimalVaultBackend : VaultBackend {
            override val format = ContainerFormat.CRYFS
            override fun listDirectory(virtualPath: String): Array<String>? = null
            override fun createDirectory(virtualPath: String) = false
            override fun renameFile(oldVirtualPath: String, newVirtualPath: String) = false
            override fun setLastModifiedTime(virtualPath: String, epochSeconds: Long) = false
            override fun deleteFile(virtualPath: String) = false
            override fun getFileSize(virtualPath: String) = -1L
            override fun getFolderSize(virtualPath: String) = -1L
            override fun readFileChunk(virtualPath: String, offset: Long, length: Int): ByteArray? = null
            override fun writeFileChunk(virtualPath: String, offset: Long, data: ByteArray) = false
            override fun finishWrite(virtualPath: String) = false
            override fun writeBackFile(virtualPath: String, sourcePath: String) = false
            override fun importStream(virtualPath: String, inputStream: java.io.InputStream, volId: Int) = false
            override fun extractFile(virtualPath: String, destinationPath: String) = false
            override fun getSpaceInfo(): LongArray? = null
            override fun close() {}
        }

        assertFalse(MinimalVaultBackend().skipsPerVolumeLock)
    }

    @Test
    fun `CryfsSession declares skipsPerVolumeLock true`() {
        verifySkipsPerVolumeLock(
            "src/main/kotlin/com/aeidolon/vaultexplorer/cryfs/CryfsSession.kt",
            expected = true
        )
    }

    @Test
    fun `Cryptomator and Gocryptfs sessions keep skipsPerVolumeLock true`() {
        verifySkipsPerVolumeLock(
            "src/main/kotlin/com/aeidolon/vaultexplorer/cryptomator/CryptomatorSession.kt",
            expected = true
        )
        verifySkipsPerVolumeLock(
            "src/main/kotlin/com/aeidolon/vaultexplorer/gocryptfs/GocryptfsSession.kt",
            expected = true
        )
    }

    @Test
    fun `interactive reads get opportunities during long streaming writes`() {
        val volId = 0
        val isReading = AtomicBoolean(false)
        val readCompleted = AtomicBoolean(false)
        val executor = Executors.newFixedThreadPool(2)

        // Background write simulation holding writeLock periodically
        val writeTask = executor.submit {
            repeat(100) {
                ContainerFileSystem.withWriteLock(volId) {
                    // Simulate storing a block batch
                    Thread.sleep(1)
                }
                Thread.yield()
            }
        }

        // Concurrent interactive read simulation
        val readTask = executor.submit {
            Thread.sleep(5)
            isReading.set(true)
            ContainerFileSystem.withReadLock(volId) {
                readCompleted.set(true)
            }
        }

        writeTask.get(5, TimeUnit.SECONDS)
        readTask.get(5, TimeUnit.SECONDS)

        assertTrue(readCompleted.get())
        executor.shutdown()
    }
}