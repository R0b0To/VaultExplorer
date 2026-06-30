package com.aeidolon.vaultexplorer

import java.io.FileNotFoundException

/**
 * Typed wrapper for VeraCrypt document IDs used by [VeraCryptDocumentsProvider].
 *
 * Wire format:  "<volId>:<type>:<fatPath>"
 *   volId   — integer in [0, MAX_VOLUMES); directly indexes [VeraCryptSession.locks]
 *   type    — "dir" or "file"
 *   fatPath — FAT path relative to the volume root; empty string = volume root
 *
 * All construction must go through [parse], which validates the volId range and
 * throws [FileNotFoundException] on any malformed input. This is the single
 * guard against ArrayIndexOutOfBoundsException on VeraCryptSession.locks[volId]
 * that was previously re-implemented (incompletely) in every Provider override.
 */
data class DocumentId(
    val volId: Int,
    val type: String,     // "dir" or "file"
    val fatPath: String,  // empty = volume root
) {
    val isDir: Boolean get() = type == "dir"

    /** Reconstructs the canonical wire string. */
    override fun toString(): String = "$volId:$type:$fatPath"

    companion object {
        /**
         * Parses and validates [raw].
         *
         * @param raw   the raw document ID string; may be null.
         * @param label human-readable noun for error messages ("document", "parent", …).
         * @throws FileNotFoundException on null input, wrong segment count,
         *   non-integer volId, or volId outside [0, MAX_VOLUMES).
         */
        @Throws(FileNotFoundException::class)
        fun parse(raw: String?, label: String = "document"): DocumentId {
            val id = raw ?: throw FileNotFoundException("Missing $label ID")
            val parts = id.split(":")
            if (parts.size < 2) {
                throw FileNotFoundException("Malformed $label ID (expected <volId>:<type>[:<path>]): $id")
            }
            val volIdInt = parts[0].toIntOrNull()
                ?: throw FileNotFoundException("Non-integer volume ID in $label ID: $id")
            if (volIdInt < 0 || volIdInt >= VeraCryptSession.MAX_VOLUMES) {
                throw FileNotFoundException(
                    "Volume ID $volIdInt is out of range [0, ${VeraCryptSession.MAX_VOLUMES}) in $label ID: $id"
                )
            }
            return DocumentId(
                volId   = volIdInt,
                type    = parts[1],
                fatPath = parts.drop(2).joinToString(":"),
            )
        }
    }
}