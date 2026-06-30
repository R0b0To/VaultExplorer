package com.aeidolon.vaultexplorer

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.Assert.*

@RunWith(AndroidJUnit4::class)
class RequireActiveSessionInstrumentedTest {

    @Test
    fun listDirectoryNative_onUnlockedVolume_returnsNullNotEmptyArray() {
        // volId 7 deliberately has no active session in this test.
        val volId = 7
        VeraCryptSession.removeSession(volId)

        val result = VeraCryptEngine.listDirectoryNative(
            VeraCryptEngine.SESSION_FD_UNUSED,
            VeraCryptEngine.SESSION_PW_UNUSED,
            VeraCryptEngine.SESSION_PIM_UNUSED,
            "",
            volId
        )

        // Before the fix: this would fall through into prepareSession's
        // derivation path with password="" and fail in a way indistinguishable
        // from "wrong password" or "corrupt header" — same null result, but for
        // the wrong reason and without the explicit log line.
        // After the fix: requireActiveSession() rejects immediately.
        assertNull(result)
@Test
fun listDirectoryNative_onUnlockedVolume_throwsIllegalStateExceptionNotUnlocked() {
    val volId = 7
    VeraCryptSession.removeSession(volId)

    val ex = assertThrows(IllegalStateException::class.java) {
        VeraCryptEngine.listDirectoryNative(
            VeraCryptEngine.SESSION_FD_UNUSED,
            VeraCryptEngine.SESSION_PW_UNUSED,
            VeraCryptEngine.SESSION_PIM_UNUSED,
            "",
            volId
        )
    }
    assertTrue(ex.message!!.startsWith("NOT_UNLOCKED"))
}
    }
}