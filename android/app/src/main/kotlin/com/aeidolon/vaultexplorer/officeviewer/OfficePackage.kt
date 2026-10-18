package com.aeidolon.vaultexplorer.officeviewer

import java.io.ByteArrayInputStream
import java.util.zip.ZipInputStream

/** Why a document could not be converted. Mapped to localized text in Dart. */
internal enum class OfficeError { ENCRYPTED, UNSUPPORTED, TOO_LARGE }

internal class OfficeException(val error: OfficeError, message: String, cause: Throwable? = null) :
    Exception(message, cause)

/**
 * An OOXML / ODF package read fully into memory with hard limits, so a
 * hostile or corrupt file can neither exhaust memory nor burn unbounded CPU
 * (zip bombs). Nothing is ever written to disk.
 *
 * Parts that look like media are kept only up to [MEDIA_ENTRY_CAP] each;
 * larger ones are dropped (the converters render a placeholder). Any other
 * part over [PART_CAP], or an archive whose total inflated size passes
 * [INFLATE_BUDGET], is rejected as [OfficeError.TOO_LARGE].
 */
internal class OfficePackage private constructor(private val parts: Map<String, ByteArray>) {

    fun has(name: String): Boolean = parts.containsKey(normalize(name))

    fun bytes(name: String): ByteArray? = parts[normalize(name)]

    fun tree(name: String): XmlNode? = bytes(name)?.let { XmlPull.parseTree(it) }

    val names: Set<String> get() = parts.keys

    companion object {
        const val PART_CAP = 64 * 1024 * 1024
        const val MEDIA_ENTRY_CAP = 8 * 1024 * 1024
        const val INFLATE_BUDGET = 512L * 1024 * 1024
        const val RETAINED_BUDGET = 128L * 1024 * 1024
        const val MAX_ENTRIES = 20_000

        private val MEDIA_EXT = setOf(
            "png", "jpg", "jpeg", "jpe", "gif", "bmp", "webp", "svg", "tif", "tiff",
            "emf", "wmf", "wdp", "jxr", "mp3", "mp4", "wav", "mov", "avi", "wmv", "m4a", "bin", "ole",
        )

        fun normalize(name: String): String {
            val parts = ArrayList<String>()
            for (seg in name.replace('\\', '/').split('/')) {
                when (seg) {
                    "", "." -> {}
                    ".." -> if (parts.isNotEmpty()) parts.removeAt(parts.size - 1)
                    else -> parts.add(seg)
                }
            }
            return parts.joinToString("/")
        }

        /** Resolves [target] (as written in a .rels file) against the part that owns the rels. */
        fun resolve(basePartName: String, target: String): String {
            if (target.startsWith("/")) return normalize(target)
            val dir = basePartName.substringBeforeLast('/', "")
            return normalize(if (dir.isEmpty()) target else "$dir/$target")
        }

        fun isCompoundFile(b: ByteArray): Boolean =
            b.size >= 8 && b[0] == 0xD0.toByte() && b[1] == 0xCF.toByte() && b[2] == 0x11.toByte() &&
                b[3] == 0xE0.toByte() && b[4] == 0xA1.toByte() && b[5] == 0xB1.toByte() &&
                b[6] == 0x1A.toByte() && b[7] == 0xE1.toByte()

        fun isZip(b: ByteArray): Boolean =
            b.size >= 4 && b[0] == 'P'.code.toByte() && b[1] == 'K'.code.toByte() &&
                (b[2] == 3.toByte() || b[2] == 5.toByte() || b[2] == 7.toByte())

        fun open(bytes: ByteArray): OfficePackage {
            if (!isZip(bytes)) throw OfficeException(OfficeError.UNSUPPORTED, "not a ZIP package")
            val parts = LinkedHashMap<String, ByteArray>()
            var inflated = 0L
            var retained = 0L
            var entries = 0
            val buf = ByteArray(64 * 1024)
            try {
                ZipInputStream(ByteArrayInputStream(bytes)).use { zin ->
                    while (true) {
                        val e = zin.nextEntry ?: break
                        if (e.isDirectory) continue
                        if (++entries > MAX_ENTRIES) throw OfficeException(OfficeError.TOO_LARGE, "too many entries")
                        val name = normalize(e.name)
                        val ext = name.substringAfterLast('.', "").lowercase()
                        val isMedia = ext in MEDIA_EXT
                        val cap = if (isMedia) MEDIA_ENTRY_CAP else PART_CAP
                        val out = java.io.ByteArrayOutputStream()
                        var size = 0L
                        var dropped = false
                        while (true) {
                            val n = zin.read(buf)
                            if (n < 0) break
                            inflated += n
                            if (inflated > INFLATE_BUDGET) throw OfficeException(OfficeError.TOO_LARGE, "archive inflates too large")
                            size += n
                            if (size > cap) {
                                if (!isMedia) throw OfficeException(OfficeError.TOO_LARGE, "part too large: $name")
                                dropped = true
                                out.reset()
                                continue // keep draining (counted in the inflate budget)
                            }
                            if (!dropped) out.write(buf, 0, n)
                        }
                        if (dropped) continue
                        retained += size
                        if (retained > RETAINED_BUDGET) {
                            if (isMedia) continue
                            throw OfficeException(OfficeError.TOO_LARGE, "package too large")
                        }
                        parts[name] = out.toByteArray()
                    }
                }
            } catch (e: OfficeException) {
                throw e
            } catch (e: java.util.zip.ZipException) {
                throw OfficeException(OfficeError.UNSUPPORTED, "corrupt ZIP: ${e.message}", e)
            } catch (e: java.io.IOException) {
                throw OfficeException(OfficeError.UNSUPPORTED, "unreadable ZIP: ${e.message}", e)
            }
            if (parts.isEmpty()) throw OfficeException(OfficeError.UNSUPPORTED, "empty package")
            return OfficePackage(parts)
        }
    }
}

/** One relationship from a `.rels` part. */
internal class Relationship(val id: String, val type: String, val target: String, val external: Boolean)

/** Reads `<base dir>/_rels/<base file>.rels` and resolves targets to full part names. */
internal fun readRelationships(pkg: OfficePackage, partName: String): Map<String, Relationship> {
    val dir = partName.substringBeforeLast('/', "")
    val file = partName.substringAfterLast('/')
    val relsName = if (dir.isEmpty()) "_rels/$file.rels" else "$dir/_rels/$file.rels"
    val root = try { pkg.tree(relsName) } catch (e: XmlLimitException) { null } ?: return emptyMap()
    val out = LinkedHashMap<String, Relationship>()
    for (r in root.all("Relationship")) {
        val id = r.attr("Id") ?: continue
        val target = r.attr("Target") ?: continue
        val external = r.attr("TargetMode").equals("External", ignoreCase = true)
        out[id] = Relationship(
            id,
            r.attr("Type") ?: "",
            if (external) target else OfficePackage.resolve(partName, target),
            external,
        )
    }
    return out
}

/** Finds the main part (`word/document.xml`, `ppt/presentation.xml`, ...) via `_rels/.rels`. */
internal fun mainPartName(pkg: OfficePackage, fallback: String): String {
    val root = try { pkg.tree("_rels/.rels") } catch (e: XmlLimitException) { null }
    val target = root?.all("Relationship")
        ?.firstOrNull { it.attr("Type")?.endsWith("/officeDocument") == true }
        ?.attr("Target")
    return if (target != null) OfficePackage.resolve("", target) else fallback
}

/** `dc:title` from `docProps/core.xml` (OOXML) or `meta.xml` (ODF), if any. */
internal fun documentTitle(pkg: OfficePackage): String? {
    for (name in listOf("docProps/core.xml", "meta.xml")) {
        val t = try { pkg.tree(name) } catch (e: XmlLimitException) { null } ?: continue
        val title = t.find("dc:title")?.textContent()?.trim()
        if (!title.isNullOrEmpty()) return title
    }
    return null
}
