package com.aeidolon.vaultexplorer.syncbridge

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import java.security.MessageDigest

/**
 * Dual IPC security (docs/architecture.md §8, mirrors vaultsync-bridge
 * ADR-S-007): [VaultSyncBridgeService] is already gated by the
 * `signature`-level `com.aeidolon.vaultexplorer.permission.BIND_SYNC_BRIDGE`
 * permission declared in AndroidManifest.xml, but that alone only proves
 * the caller shares *some* signing identity path the OS accepts for
 * "signature" — reproducible-build distribution (F-Droid) can mean the
 * two apps end up signed by different-but-both-legitimate keys (F-Droid's
 * own reproducible-build signer vs. this maintainer's upstream key). This
 * class is the second, explicit check: an allowlist of pinned SHA-256
 * signing-certificate digests, checked again on every call (not just at
 * bind time — see VaultSyncBridgeService's `requireCaller()`), so rotating
 * or adding a legitimate distribution channel is a data change here, not
 * a manifest change that would also have to loosen the OS-level check.
 */
object CallerVerifier {

    /**
     * Populate via BuildConfig / a resource overlay per distribution
     * channel — deliberately empty in source so no channel's real digest
     * ships in a place a diff against this public repo could be used to
     * spoof it. See README "Signing" for how release builds populate
     * this (each maintainer-controlled build config sets its own list;
     * F-Droid's reproducible build adds its own signer's digest to a
     * server-side-configured overlay, not to this file).
     */
    private val pinnedDigestsHex: Set<String> by lazy {
        // TODO(release-config): replace with the real allowlist before
        // shipping — see the class doc comment above. Left empty here so
        // an unconfigured build fails closed (denies every caller) rather
        // than silently trusting nothing-in-particular.
        emptySet()
    }

    fun check(context: Context, callingUid: Int): Boolean {
        val packageManager = context.packageManager
        val packages = packageManager.getPackagesForUid(callingUid) ?: return false
        return packages.any { packageName -> isPinnedPackage(packageManager, packageName) }
    }

    private fun isPinnedPackage(packageManager: PackageManager, packageName: String): Boolean {
        val digests = signingDigestsHex(packageManager, packageName)
        if (digests.isEmpty()) return false
        return digests.any { it in pinnedDigestsHex }
    }

    private fun signingDigestsHex(packageManager: PackageManager, packageName: String): List<String> {
        return try {
            val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val info = packageManager.getPackageInfo(
                    packageName,
                    PackageManager.GET_SIGNING_CERTIFICATES,
                )
                val signingInfo = info.signingInfo ?: return emptyList()
                if (signingInfo.hasMultipleSigners()) {
                    // Multiple signers is never expected for either app;
                    // fail closed rather than guess which one matters.
                    signingInfo.apkContentsSigners
                } else {
                    signingInfo.signingCertificateHistory
                }
            } else {
                @Suppress("DEPRECATION")
                val info = packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
                @Suppress("DEPRECATION")
                info.signatures ?: return emptyList()
            }
            signatures.map { sha256Hex(it.toByteArray()) }
        } catch (e: PackageManager.NameNotFoundException) {
            emptyList()
        }
    }

    private fun sha256Hex(bytes: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
        return digest.joinToString(separator = "") { "%02x".format(it) }
    }
}
