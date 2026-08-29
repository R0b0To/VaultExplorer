package com.aeidolon.vaultexplorer

import java.io.FileNotFoundException
import com.aeidolon.vaultexplorer.container.ContainerSessionRegistry


data class DocumentId(
    val volId: Int,
    val type: String,     // "dir" or "file"
    val fatPath: String,  // empty = volume root
    val mimeTypeOverride: String? = null,
) {
    val isDir: Boolean get() = type == "dir"

    /**
     * Reconstructs the canonical wire string handed to SAF clients.
     *
     * The leading field is [ContainerSession.stableId] for whatever vault
     * currently occupies [volId] -- not [volId] itself. [volId] is only
     * ever "the first free slot at the moment this particular vault was
     * unlocked" (see ContainerSessionRegistry.getFreeVolumeId), so it's
     * reused by whichever vault happens to unlock next; a document ID
     * that embedded it directly would silently start pointing at a
     * different vault after a relock in a different order. Falls back to
     * the raw [volId] only if the session has already vanished by the
     * time this is stringified (e.g. a notifyChange fired during
     * teardown) -- an edge case where there's no vault left to name
     * stably anyway, so there's nothing better to fall back to.
     */
    override fun toString(): String {
        val rootId = ContainerSessionRegistry.activeSessions[volId]?.stableId ?: volId.toString()
        val base = "$rootId:$type:$fatPath"
        return if (mimeTypeOverride != null) {
            "$base?mimeType=$mimeTypeOverride"
        } else {
            base
        }
    }

    companion object {
        /**
         * Parses and validates [raw].
         *
         * The leading field is normally a [ContainerSession.stableId]
         * (see [toString]), resolved back to the live [volId] currently
         * hosting that vault via [ContainerSessionRegistry
         * .getVolumeIdByStableId]. A bare integer is also accepted as a
         * fallback for document IDs a SAF client cached before this
         * stable-ID scheme existed -- best-effort only, since that's
         * exactly the ambiguous slot number this change exists to stop
         * relying on; it just avoids breaking already-open documents
         * from the *current* app process rather than pretending to fix
         * ones a client bookmarked across a previous relock.
         *
         * @param raw   the raw document ID string; may be null.
         * @param label human-readable noun for error messages ("document", "parent", …).
         * @throws FileNotFoundException on null input, wrong segment count,
         *   or a root ID that names no vault mounted right now.
         */
        @Throws(FileNotFoundException::class)
        fun parse(raw: String?, label: String = "document"): DocumentId {
            val id = raw ?: throw FileNotFoundException("Missing $label ID")

            val actualId = id.substringBefore("?mimeType=")
            val mimeTypeOverride = if (id.contains("?mimeType=")) {
                id.substringAfter("?mimeType=")
            } else {
                null
            }

            val parts = actualId.split(":")
            if (parts.size < 2) {
                throw FileNotFoundException("Malformed $label ID (expected <rootId>:<type>[:<path>]): $id")
            }
            val rootIdStr = parts[0]
            val volIdInt = ContainerSessionRegistry.getVolumeIdByStableId(rootIdStr)
                ?: rootIdStr.toIntOrNull()?.takeIf { it in 0 until ContainerSessionRegistry.MAX_VOLUMES }
                ?: throw FileNotFoundException(
                    "No mounted vault matches root ID '$rootIdStr' in $label ID: $id (vault may be locked)"
                )
            return DocumentId(
                volId = volIdInt,
                type = parts[1],
                fatPath = parts.drop(2).joinToString(":"),
                mimeTypeOverride = mimeTypeOverride,
            )
        }
    }
}