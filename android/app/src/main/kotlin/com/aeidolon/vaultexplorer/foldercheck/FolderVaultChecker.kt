package com.aeidolon.vaultexplorer.foldercheck

import android.content.Context
import android.net.Uri

import com.aeidolon.vaultexplorer.container.ContainerFormat
import com.aeidolon.vaultexplorer.container.VaultBackendRegistry
import com.aeidolon.vaultexplorer.foldervault.FolderVaultOpener
import com.aeidolon.vaultexplorer.foldervault.NativeVaultSession

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
 * Android entry point of the folder-vault Check & Repair tool. The tool itself is platform-neutral C++
 * (cpp/foldervault/fv_check*.cpp, working through the same storage abstraction as the vault engines), so a desktop
 * build gets it unchanged. All that is left here is Android policy: which storage reaches the folder (verified raw
 * path or SAF), turning the Dart arguments into native arguments, and the result array into the data classes above.
 *
 * [password]: optional for a check (omitting it runs the structure-only scan). [mountedVolId]: the volume slot of the
 * same vault when it is unlocked in this app -- its session keys are then used (inside the native core) in place of
 * the password. [opId] > 0 streams the step-by-step log to Dart's live log panel.
 */
object FolderVaultChecker {

    private class Wire(val format: Int, val sentinel: String, val formatWire: String, val container: ContainerFormat)

    private fun wireOf(formatWire: String): Wire? = when (formatWire) {
        "gocryptfs" -> Wire(0, "gocryptfs.conf", "gocryptfs", ContainerFormat.GOCRYPTFS)
        "cryptomator", "directory_vault" -> Wire(1, "masterkey.cryptomator", "cryptomator", ContainerFormat.CRYPTOMATOR)
        "cryfs" -> Wire(2, "cryfs.config", "cryfs", ContainerFormat.CRYFS)
        else -> null
    }

    private fun severityOf(code: String?): FolderVaultIssueSeverity = when (code) {
        "2" -> FolderVaultIssueSeverity.CRITICAL
        "1" -> FolderVaultIssueSeverity.WARNING
        else -> FolderVaultIssueSeverity.INFO
    }

    /** (severity, path, message) triples starting at [from]. */
    private fun issuesFrom(a: Array<String>, from: Int): List<FolderVaultIssue> {
        val out = ArrayList<FolderVaultIssue>()
        var i = from
        while (i + 2 < a.size) {
            out.add(FolderVaultIssue(severityOf(a[i]), a[i + 1], a[i + 2]))
            i += 3
        }
        return out
    }

    /** The native handle of the unlocked vault in slot [volId], if it is a folder vault of [wire]'s format. */
    private fun sessionHandle(volId: Int?, wire: Wire): Long? {
        if (volId == null) return 0L
        val session = VaultBackendRegistry.get(volId) as? NativeVaultSession ?: return null
        // A session of another format would only be ignored; the password path is then used.
        return if (session.format == wire.container) session.nativeHandle() else 0L
    }

    fun check(
        context: Context,
        vaultRootUri: Uri,
        formatWire: String,
        password: CharArray?,
        mountedVolId: Int? = null,
        opId: Int = -1,
    ): FolderVaultCheckOutcome {
        try {
            val wire = wireOf(formatWire) ?: return FolderVaultCheckOutcome.InvalidVault("Unsupported folder vault format: $formatWire")
            val handle = sessionHandle(mountedVolId, wire)
                ?: return FolderVaultCheckOutcome.InvalidVault(
                    "This vault isn't open anymore -- pick it again and enter its password for a deep scan.",
                )
            val r = FolderVaultOpener.checkOrRepair(context, vaultRootUri, wire.format, wire.sentinel, false, password, handle, opId)
            return when (r.getOrNull(0)) {
                "0" -> FolderVaultCheckOutcome.Success(
                    FolderVaultCheckReport(
                        formatWire = wire.formatWire,
                        filesScanned = r.getOrNull(1)?.toIntOrNull() ?: 0,
                        issues = issuesFrom(r, 3),
                        deepScanPerformed = r.getOrNull(2) == "1",
                    ),
                )
                "1" -> FolderVaultCheckOutcome.WrongPassword
                else -> FolderVaultCheckOutcome.InvalidVault(r.getOrNull(1) ?: "The check failed.")
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
        opId: Int = -1,
    ): FolderVaultRepairOutcome {
        try {
            val wire = wireOf(formatWire) ?: return FolderVaultRepairOutcome.InvalidVault("Unsupported folder vault format: $formatWire")
            val handle = sessionHandle(mountedVolId, wire)
                ?: return FolderVaultRepairOutcome.InvalidVault(
                    "This vault isn't open anymore -- pick it again and enter its password to repair.",
                )
            val r = FolderVaultOpener.checkOrRepair(context, vaultRootUri, wire.format, wire.sentinel, true, password, handle, opId)
            return when (r.getOrNull(0)) {
                "0" -> FolderVaultRepairOutcome.Success(
                    FolderVaultRepairReport(
                        formatWire = wire.formatWire,
                        fixedCount = r.getOrNull(1)?.toIntOrNull() ?: 0,
                        recoveredCount = r.getOrNull(2)?.toIntOrNull() ?: 0,
                        removedCount = r.getOrNull(3)?.toIntOrNull() ?: 0,
                        remainingIssues = issuesFrom(r, 4),
                    ),
                )
                "1" -> FolderVaultRepairOutcome.WrongPassword
                else -> FolderVaultRepairOutcome.InvalidVault(r.getOrNull(1) ?: "The repair failed.")
            }
        } finally {
            password?.fill(' ')
        }
    }
}
