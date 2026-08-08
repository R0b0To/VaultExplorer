package com.aeidolon.vaultexplorer.syncbridge

import java.io.File

/**
 * Every AIDL method that takes a `relativePath` (openBlockForRead/Write,
 * finalizeBlockWrite, deleteBlock) resolves it against a vault's root
 * directory before touching a file. [resolve] is the single choke point
 * that does that — see docs/architecture.md §8.2, ownership rule 8.
 *
 * `relativePath` arrives from VaultSync Bridge, a network-connected
 * process this app does not control the code of, so it is untrusted input
 * even though the two apps are signed by the same maintainer: treat it the
 * same way a server treats a client-supplied path.
 */
object PathValidator {

    class InvalidPathException(message: String) : Exception(message)

    /**
     * Resolves [relativePath] against [root], rejecting anything that
     * would escape [root]. Rejects: absolute paths, empty segments after
     * normalization, `.`/`..` segments, and any resolved canonical path
     * that is not a descendant of `root`'s canonical path (defends
     * against symlink tricks a malformed/malicious vault directory could
     * otherwise use).
     */
    fun resolve(root: File, relativePath: String): File {
        if (relativePath.isBlank()) {
            throw InvalidPathException("empty relativePath")
        }
        if (relativePath.startsWith("/") || relativePath.startsWith("\\")) {
            throw InvalidPathException("absolute relativePath rejected: $relativePath")
        }
        val segments = relativePath.split('/', '\\')
        for (segment in segments) {
            if (segment.isEmpty() || segment == "." || segment == "..") {
                throw InvalidPathException("illegal path segment '$segment' in $relativePath")
            }
        }
        val rootCanonical = root.canonicalFile
        val candidate = File(root, relativePath)
        // canonicalFile resolves symlinks; a vault directory shouldn't
        // contain any, but this is defense-in-depth rather than trust.
        val candidateCanonical = candidate.canonicalFile
        if (candidateCanonical != rootCanonical &&
            !candidateCanonical.path.startsWith(rootCanonical.path + File.separator)
        ) {
            throw InvalidPathException("relativePath escapes vault root: $relativePath")
        }
        return candidate
    }

    /** Staging files live under a hidden per-vault-root directory, never
     *  under the same relative path as the live file (docs/architecture.md
     *  ADR-S-003 in vaultsync-bridge, mirrored here as the server side of
     *  that contract). */
    fun stagingDir(root: File): File = File(root, ".vaultsync-staging").apply { mkdirs() }

    fun stagingFile(root: File): File = File(stagingDir(root), java.util.UUID.randomUUID().toString())
}
