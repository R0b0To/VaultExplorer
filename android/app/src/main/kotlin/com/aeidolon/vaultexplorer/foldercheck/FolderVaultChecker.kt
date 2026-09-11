package com.aeidolon.vaultexplorer.foldercheck

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile

import com.aeidolon.vaultexplorer.container.VaultBackendRegistry
import com.aeidolon.vaultexplorer.cryfs.CryfsSession
import com.aeidolon.vaultexplorer.cryptomator.CryptomatorSession
import com.aeidolon.vaultexplorer.gocryptfs.GocryptfsSession

enum class FolderVaultIssueSeverity(val wire: Int) { INFO(0), WARNING(1), CRITICAL(2) }

data class FolderVaultIssue(
    val severity: FolderVaultIssueSeverity,
    val path: String,
    val message: String,
)

data class FolderVaultCheckReport(
    val formatWire: String,
    val filesScanned: Int,
    val issues: List<FolderVaultIssue>,
    val deepScanPerformed: Boolean,
) {
    val healthy: Boolean get() = issues.none { it.severity != FolderVaultIssueSeverity.INFO }
}

sealed class FolderVaultCheckOutcome {
    data class Success(val report: FolderVaultCheckReport) : FolderVaultCheckOutcome()
    data class InvalidVault(val message: String) : FolderVaultCheckOutcome()
    object WrongPassword : FolderVaultCheckOutcome()
}

data class FolderVaultRepairReport(
    val formatWire: String,
    val fixedCount: Int,
    val recoveredCount: Int,
    val removedCount: Int,
    val remainingIssues: List<FolderVaultIssue>,
) {
    val healthy: Boolean get() = remainingIssues.none { it.severity != FolderVaultIssueSeverity.INFO }
}

sealed class FolderVaultRepairOutcome {
    data class Success(val report: FolderVaultRepairReport) : FolderVaultRepairOutcome()
    data class InvalidVault(val message: String) : FolderVaultRepairOutcome()
    object WrongPassword : FolderVaultRepairOutcome()
}

/**
 * Entry point for the folder-vault Check & Repair tool. This used to be a
 * single ~1250-line object holding check/repair logic for all three
 * directory-vault formats; it's now a thin dispatcher over
 * GocryptfsVaultCheck, CryptomatorVaultCheck and CryfsVaultCheck, each in its
 * own file, matching how every other format-specific concern in this
 * codebase is already organized (see the cryptomator/, gocryptfs/, cryfs/
 * session packages). The data classes above are unchanged from before the
 * split, so nothing importing FolderVaultIssue/FolderVaultCheckOutcome/etc.
 * needs to change.
 */
object FolderVaultChecker {

    fun check(
        context: Context,
        vaultRootUri: Uri,
        formatWire: String,
        password: CharArray?,
        mountedVolId: Int? = null,
        log: (String) -> Unit = {},
    ): FolderVaultCheckOutcome {
        val root = DocumentFile.fromTreeUri(context, vaultRootUri)
            ?: return FolderVaultCheckOutcome.InvalidVault("Cannot access the selected folder.")
        val session = mountedVolId?.let { VaultBackendRegistry.get(it) }
        if (mountedVolId != null && session == null) {
            return FolderVaultCheckOutcome.InvalidVault(
                "This vault isn't open anymore -- pick it again and enter its password for a deep scan.",
            )
        }
        return try {
            when (formatWire) {
                "gocryptfs" -> GocryptfsVaultCheck.checkGocryptfs(context, root, password, session as? GocryptfsSession, log)
                "cryfs" -> CryfsVaultCheck.checkCryfs(context, root, password, session as? CryfsSession, log)
                "cryptomator", "directory_vault" -> CryptomatorVaultCheck.checkCryptomator(context, root, password, session as? CryptomatorSession, log)
                else -> FolderVaultCheckOutcome.InvalidVault("Unsupported folder vault format: $formatWire")
            }
        } finally {
            password?.fill(' ')
        }
    }

    fun repair(
        context: Context,
        vaultRootUri: Uri,
        formatWire: String,
        password: CharArray?,
        mountedVolId: Int? = null,
        log: (String) -> Unit = {},
    ): FolderVaultRepairOutcome {
        val root = DocumentFile.fromTreeUri(context, vaultRootUri)
            ?: return FolderVaultRepairOutcome.InvalidVault("Cannot access the selected folder.")
        val session = mountedVolId?.let { VaultBackendRegistry.get(it) }
        if (mountedVolId != null && session == null) {
            return FolderVaultRepairOutcome.InvalidVault(
                "This vault isn't open anymore -- pick it again and enter its password to repair.",
            )
        }
        return try {
            when (formatWire) {
                "gocryptfs" -> GocryptfsVaultCheck.repairGocryptfs(context, root, password, session as? GocryptfsSession, log)
                "cryptomator", "directory_vault" -> CryptomatorVaultCheck.repairCryptomator(context, root, password, session as? CryptomatorSession, log)
                else -> FolderVaultRepairOutcome.InvalidVault("Automatic repair is currently supported for Cryptomator and gocryptfs vaults.")
            }
        } finally {
            password?.fill(' ')
        }
    }
}
