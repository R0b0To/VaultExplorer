package com.aeidolon.vaultexplorer

/**
 * Kotlin mirror of `lib/core/filesystem/{filesystem_type,name_validation}.dart`,
 * for the one code path that never passes through Dart: SAF import
 * (`ImportExportHandlers.kt`). See docs/architecture.md ADR-002 for why a
 * name that fails here is *skipped*, not mutated -- this object only
 * classifies, exactly like its Dart counterpart; it never returns a
 * different string than it was given.
 *
 * Kept as a hand-maintained mirror rather than a shared implementation --
 * see ADR-005 item 3 for the tracked follow-up on unifying the two across
 * the JNI boundary. Every rule here should match the corresponding rule in
 * `filesystem_type.dart`'s `FilesystemRules` table; if you change one,
 * change both.
 */
object FilesystemNameValidator {

    /** Mirrors Dart's `FilesystemType`. Import only ever validates against
     *  [ENCRYPTED_VAULT] (CryFS/Cryptomator/gocryptfs destinations) or
     *  [UNKNOWN_CONSERVATIVE] (everything else -- see [kindFor]). */
    enum class Kind { ENCRYPTED_VAULT, UNKNOWN_CONSERVATIVE }

    data class Rules(
        val illegalChars: Set<Char>,
        val disallowControlChars: Boolean,
        val disallowReservedDeviceNames: Boolean,
        val disallowTrailingSpaceOrDot: Boolean,
        val maxComponentLengthBytes: Int,
    )

    private val windowsFamilyIllegal = setOf('"', '*', '/', ':', '<', '>', '?', '\\', '|')

    private val rulesFor = mapOf(
        Kind.ENCRYPTED_VAULT to Rules(
            illegalChars = setOf('/'),
            disallowControlChars = false,
            disallowReservedDeviceNames = false,
            disallowTrailingSpaceOrDot = false,
            maxComponentLengthBytes = 1024,
        ),
        // Union of fat32/exfat/ntfs/ext -- the same conservative default
        // `FilesystemType.unknownConservative` uses on the Dart side, for
        // exactly the same reason: the concrete on-disk kind of a native
        // disk-image container isn't known at this call site (ADR-005).
        Kind.UNKNOWN_CONSERVATIVE to Rules(
            illegalChars = windowsFamilyIllegal,
            disallowControlChars = true,
            disallowReservedDeviceNames = true,
            disallowTrailingSpaceOrDot = true,
            maxComponentLengthBytes = 255,
        ),
    )

    private val reservedDeviceBaseNames = setOf(
        "CON", "PRN", "AUX", "NUL",
        "COM0", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
        "LPT0", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
    )

    /** Which [Kind] a destination volume's names should be validated
     *  against -- mirrors `resolveFilesystemType()` in
     *  `mounted_container_filesystem.dart`. */
    fun kindFor(volId: Int): Kind {
        val format = VaultBackendRegistry.get(volId)?.format
        return if (format == ContainerFormat.CRYFS || format == ContainerFormat.CRYPTOMATOR || format == ContainerFormat.GOCRYPTFS) {
            Kind.ENCRYPTED_VAULT
        } else {
            Kind.UNKNOWN_CONSERVATIVE
        }
    }

    private fun isReservedDeviceName(name: String): Boolean {
        val base = name.substringBefore('.')
        return reservedDeviceBaseNames.contains(base.uppercase())
    }

    /**
     * Validates [name] as a single path component. Never mutates [name].
     * Returns every reason it's invalid (empty if valid) so a caller can
     * log/report the specific problem rather than a generic "skipped".
     */
    fun validate(name: String, kind: Kind): List<String> {
        val rules = rulesFor.getValue(kind)
        val issues = mutableListOf<String>()

        if (name.isEmpty()) {
            return listOf("name is empty")
        }
        if (name == "." || name == "..") {
            issues.add("\"$name\" is a reserved navigation name")
        }

        for ((i, c) in name.withIndex()) {
            if (c in rules.illegalChars) {
                issues.add("\"$c\" at position ${i + 1} is not allowed")
                continue
            }
            val isControl = c.code <= 0x1F || c.code == 0x7F
            if (isControl && rules.disallowControlChars) {
                issues.add("position ${i + 1} is a non-printable control character")
            }
        }

        if (rules.disallowReservedDeviceNames && isReservedDeviceName(name)) {
            issues.add("\"$name\" is a reserved device name (CON/PRN/AUX/NUL/COM0-9/LPT0-9)")
        }

        if (rules.disallowTrailingSpaceOrDot) {
            if (name.endsWith(' ')) issues.add("name can't end with a space")
            if (name.endsWith('.')) issues.add("name can't end with a \".\"")
        }

        val byteLength = name.toByteArray(Charsets.UTF_8).size
        if (byteLength > rules.maxComponentLengthBytes) {
            issues.add("name is $byteLength bytes long; limit is ${rules.maxComponentLengthBytes}")
        }

        return issues
    }

    fun isValid(name: String, kind: Kind): Boolean = validate(name, kind).isEmpty()
}
