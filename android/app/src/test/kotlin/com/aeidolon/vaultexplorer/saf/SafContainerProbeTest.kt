package com.aeidolon.vaultexplorer.saf

import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.FileNotFoundException

/**
 * classifyOpenFailure decides what a failed ContentResolver.openFileDescriptor
 * means for a container: a refused grant must become an explicit read-only
 * mount, a provider that doesn't implement rw must keep using the staging
 * proxy, and anything unknown must not be mistaken for either.
 */
class SafContainerProbeTest {

    @Test
    fun securityExceptionIsPermissionDenied() {
        val e = SecurityException(
            "Permission Denial: writing com.android.externalstorage.ExternalStorageProvider uri " +
                "content://com.android.externalstorage.documents/document/primary%3Aa.hc from pid=1, uid=2 " +
                "requires that you obtain access using ACTION_OPEN_DOCUMENT or related APIs",
        )
        assertEquals(OpenFailureKind.PERMISSION_DENIED, classifyOpenFailure(e))
    }

    @Test
    fun securityExceptionWinsEvenWhenMessageMentionsMode() {
        val e = SecurityException("write mode rw not permitted")
        assertEquals(OpenFailureKind.PERMISSION_DENIED, classifyOpenFailure(e))
    }

    @Test
    fun fileNotFoundWithErrnoTextIsPermissionDenied() {
        listOf(
            "open failed: EACCES (Permission denied)",
            "open failed: EPERM (Operation not permitted)",
            "open failed: EROFS (Read-only file system)",
            "Permission denied",
        ).forEach { msg ->
            assertEquals(msg, OpenFailureKind.PERMISSION_DENIED, classifyOpenFailure(FileNotFoundException(msg)))
        }
    }

    @Test
    fun missingFileIsNotPermissionDenied() {
        val e = FileNotFoundException("open failed: ENOENT (No such file or directory)")
        assertEquals(OpenFailureKind.OTHER, classifyOpenFailure(e))
    }

    @Test
    fun unsupportedModeKeepsTheProxy() {
        assertEquals(OpenFailureKind.UNSUPPORTED_MODE, classifyOpenFailure(UnsupportedOperationException()))
        assertEquals(
            OpenFailureKind.UNSUPPORTED_MODE,
            classifyOpenFailure(FileNotFoundException("Unsupported mode: rw")),
        )
        assertEquals(
            OpenFailureKind.UNSUPPORTED_MODE,
            classifyOpenFailure(IllegalArgumentException("Unsupported mode")),
        )
    }

    @Test
    fun unknownFailuresAreOther() {
        assertEquals(OpenFailureKind.OTHER, classifyOpenFailure(IllegalStateException("provider died")))
        assertEquals(OpenFailureKind.OTHER, classifyOpenFailure(RuntimeException()))
    }
}
