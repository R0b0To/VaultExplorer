package com.aeidolon.vaultexplorer.reader

import android.util.Xml
import org.xmlpull.v1.XmlPullParser
import java.io.ByteArrayInputStream
import java.net.URLDecoder
import java.security.MessageDigest

class EpubSpineItem(val path: String, val linear: Boolean)

/** One table-of-contents row. [path] is a zip entry path, [fragment] the `#id` part. */
class EpubTocItem(val title: String, val path: String, val fragment: String, val level: Int)

/** Prefix XOR parameters for the two EPUB font-embedding obfuscation schemes. */
class FontObfuscation(val key: ByteArray, val prefixLength: Int)

/**
 * What the reader needs to know about a book: reading order (the "playlist"),
 * table of contents, and a little metadata. All paths are zip entry paths,
 * already percent-decoded and normalised, so they can be looked up in a
 * [ZipDirectory] as they are.
 */
class EpubPackage(
    val title: String,
    val author: String,
    val language: String,
    /** `rtl`, `ltr` or empty when the book does not say. */
    val direction: String,
    val fixedLayout: Boolean,
    val coverPath: String,
    val coverSize: Long,
    val fontObfuscation: Map<String, FontObfuscation>,
    val spine: List<EpubSpineItem>,
    val toc: List<EpubTocItem>,
) {
    fun toMap(): Map<String, Any> = mapOf(
        "title" to title,
        "author" to author,
        "language" to language,
        "direction" to direction,
        "fixedLayout" to fixedLayout,
        "coverPath" to coverPath,
        "coverSize" to coverSize,
        "spine" to spine.map { mapOf("path" to it.path, "linear" to it.linear) },
        "toc" to toc.map {
            mapOf("title" to it.title, "path" to it.path, "fragment" to it.fragment, "level" to it.level)
        },
    )

    companion object {
        private const val MAX_XML_BYTES = 8L * 1024 * 1024

        fun parse(src: BookByteSource, dir: ZipDirectory): EpubPackage {
            fun read(path: String): ByteArray {
                val entry = dir.find(path)
                    ?: throw BookFormatException(BookError.NOT_FOUND, "Missing $path")
                return ZipReader.readEntry(src, entry, MAX_XML_BYTES)
            }

            val opfPath = parseRootfile(read("META-INF/container.xml"))
                ?: throw BookFormatException(BookError.NOT_FOUND, "container.xml names no package document")
            val opfDir = opfPath.substringBeforeLast('/', "")
            val opf = parseOpf(read(opfPath), opfDir)
            if (opf.spine.isEmpty()) {
                throw BookFormatException(BookError.NOT_FOUND, "Package document has an empty reading order")
            }

            // EPUB 3 navigation document first, EPUB 2 NCX second. A table of
            // contents that fails to parse is not worth failing the book for.
            var toc: List<EpubTocItem> = emptyList()
            val navItem = opf.manifest.values.firstOrNull { "nav" in it.properties.split(' ') }
            if (navItem != null) {
                val navPath = resolvePath(opfDir, navItem.href)
                toc = runCatching { parseNav(read(navPath), navPath.substringBeforeLast('/', "")) }
                    .getOrDefault(emptyList())
            }
            if (toc.isEmpty()) {
                val ncxItem = opf.manifest[opf.tocId]
                    ?: opf.manifest.values.firstOrNull { it.mediaType == "application/x-dtbncx+xml" }
                if (ncxItem != null) {
                    val ncxPath = resolvePath(opfDir, ncxItem.href)
                    toc = runCatching { parseNcx(read(ncxPath), ncxPath.substringBeforeLast('/', "")) }
                        .getOrDefault(emptyList())
                }
            }

            val coverItem = opf.manifest.values.firstOrNull { "cover-image" in it.properties.split(' ') }
                ?: opf.manifest[opf.coverId]

            val coverPath = coverItem?.let { resolvePath(opfDir, it.href) } ?: ""
            val fontObfuscation = runCatching {
                val encryption = dir.find("META-INF/encryption.xml")
                    ?: return@runCatching emptyMap<String, FontObfuscation>()
                parseFontObfuscation(
                    ZipReader.readEntry(src, encryption, MAX_XML_BYTES),
                    opf,
                )
            }.getOrDefault(emptyMap())
            return EpubPackage(
                title = opf.title,
                author = opf.authors.joinToString(", "),
                language = opf.language,
                direction = opf.direction,
                fixedLayout = opf.renditionLayout == "pre-paginated",
                coverPath = coverPath,
                coverSize = dir.find(coverPath)?.size ?: 0L,
                fontObfuscation = fontObfuscation,
                spine = opf.spine.mapNotNull { ref ->
                    val item = opf.manifest[ref.idref] ?: return@mapNotNull null
                    val path = resolvePath(opfDir, item.href)
                    if (dir.find(path) == null) null else EpubSpineItem(path, ref.linear)
                },
                toc = toc.filter { dir.find(it.path) != null },
            )
        }

        // -- OPF ----------------------------------------------------------

        private class ManifestItem(val href: String, val mediaType: String, val properties: String)
        private class ItemRef(val idref: String, val linear: Boolean)
        private class Opf(
            val title: String,
            val authors: List<String>,
            val language: String,
            val direction: String,
            val renditionLayout: String,
            val uniqueIdentifier: String,
            val identifiers: Map<String, String>,
            val coverId: String,
            val tocId: String,
            val manifest: Map<String, ManifestItem>,
            val spine: List<ItemRef>,
        )

        private fun parseRootfile(bytes: ByteArray): String? {
            val p = newParser(bytes)
            while (p.next() != XmlPullParser.END_DOCUMENT) {
                if (p.eventType == XmlPullParser.START_TAG && p.localName() == "rootfile") {
                    val path = p.getAttributeValue(null, "full-path")
                    if (!path.isNullOrBlank()) return resolvePath("", path)
                }
            }
            return null
        }

        private fun parseOpf(bytes: ByteArray, @Suppress("UNUSED_PARAMETER") opfDir: String): Opf {
            val p = newParser(bytes)
            var title = ""
            val authors = ArrayList<String>()
            var language = ""
            var direction = ""
            var coverId = ""
            var tocId = ""
            var renditionLayout = ""
            var uniqueIdentifier = ""
            val identifiers = LinkedHashMap<String, String>()
            val manifest = LinkedHashMap<String, ManifestItem>()
            val spine = ArrayList<ItemRef>()
            var inMetadata = false

            while (p.next() != XmlPullParser.END_DOCUMENT) {
                if (p.eventType == XmlPullParser.END_TAG) {
                    if (p.localName() == "metadata") inMetadata = false
                    continue
                }
                if (p.eventType != XmlPullParser.START_TAG) continue
                when (p.localName()) {
                    "package" -> uniqueIdentifier = p.getAttributeValue(null, "unique-identifier") ?: ""
                    "metadata" -> inMetadata = true
                    "title" -> if (inMetadata && title.isEmpty()) title = readText(p)
                    "creator" -> if (inMetadata) readText(p).takeIf { it.isNotEmpty() }?.let { authors.add(it) }
                    "language" -> if (inMetadata && language.isEmpty()) language = readText(p)
                    "identifier" -> if (inMetadata) {
                        val id = p.getAttributeValue(null, "id")
                        val value = readText(p)
                        if (!id.isNullOrEmpty()) identifiers[id] = value
                    }
                    "meta" -> if (inMetadata) {
                        if (p.getAttributeValue(null, "name") == "cover") {
                            coverId = p.getAttributeValue(null, "content") ?: ""
                        }
                        if (p.getAttributeValue(null, "property") == "rendition:layout") {
                            renditionLayout = readText(p)
                        }
                    }
                    "item" -> {
                        val id = p.getAttributeValue(null, "id")
                        val href = p.getAttributeValue(null, "href")
                        if (id != null && href != null) {
                            manifest[id] = ManifestItem(
                                href = href,
                                mediaType = p.getAttributeValue(null, "media-type") ?: "",
                                properties = p.getAttributeValue(null, "properties") ?: "",
                            )
                        }
                    }
                    "spine" -> {
                        tocId = p.getAttributeValue(null, "toc") ?: ""
                        direction = p.getAttributeValue(null, "page-progression-direction") ?: ""
                    }
                    "itemref" -> p.getAttributeValue(null, "idref")?.let {
                        spine.add(ItemRef(it, p.getAttributeValue(null, "linear") != "no"))
                    }
                }
            }
            return Opf(
                title, authors, language, direction, renditionLayout, uniqueIdentifier,
                identifiers, coverId, tocId, manifest, spine,
            )
        }

        private fun parseFontObfuscation(
            bytes: ByteArray,
            opf: Opf,
        ): Map<String, FontObfuscation> {
            val idValue = opf.identifiers[opf.uniqueIdentifier].orEmpty()
            val parser = newParser(bytes)
            val result = LinkedHashMap<String, FontObfuscation>()
            var fontKey: ByteArray? = null
            var prefix = 0
            while (parser.next() != XmlPullParser.END_DOCUMENT) {
                if (parser.eventType != XmlPullParser.START_TAG) continue
                when (parser.localName()) {
                    "EncryptedData" -> {
                        fontKey = null
                        prefix = 0
                    }
                    "EncryptionMethod" -> {
                        val algorithm = parser.getAttributeValue(null, "Algorithm") ?: ""
                        when (algorithm) {
                            "http://www.idpf.org/2008/embedding" -> {
                                val id = idValue.filterNot(Char::isWhitespace).toByteArray(Charsets.UTF_8)
                                fontKey = if (id.isEmpty()) null else MessageDigest.getInstance("SHA-1").digest(id)
                                prefix = 1040
                            }
                            "http://ns.adobe.com/pdf/enc#RC" -> {
                                val uuid = Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
                                    .find(idValue)?.value?.replace("-", "")
                                fontKey = uuid?.chunked(2)?.map { it.toInt(16).toByte() }?.toByteArray()
                                prefix = 1024
                            }
                        }
                    }
                    "CipherReference" -> {
                        val uri = parser.getAttributeValue(null, "URI") ?: continue
                        val key = fontKey ?: continue
                        // CipherReference URIs are rooted at the OCF container,
                        // alongside META-INF, rather than beside the OPF file.
                        val path = resolvePath("", uri)
                        if (prefix > 0) result[path] = FontObfuscation(key, prefix)
                    }
                }
            }
            return result
        }

        // -- Tables of contents ------------------------------------------

        private fun parseNav(bytes: ByteArray, baseDir: String): List<EpubTocItem> {
            val p = newParser(bytes)
            val out = ArrayList<EpubTocItem>()
            var inToc = false
            var olDepth = 0
            while (p.next() != XmlPullParser.END_DOCUMENT) {
                when (p.eventType) {
                    XmlPullParser.START_TAG -> when (p.localName()) {
                        "nav" -> if (!inToc) {
                            val type = p.getAttributeValue(null, "epub:type")
                                ?: p.getAttributeValue(null, "type") ?: ""
                            if ("toc" in type.split(' ')) {
                                inToc = true
                                olDepth = 0
                            }
                        }
                        "ol" -> if (inToc) olDepth++
                        "a" -> if (inToc) {
                            val href = p.getAttributeValue(null, "href")
                            val label = readText(p)
                            if (!href.isNullOrBlank() && label.isNotEmpty()) {
                                out.add(
                                    EpubTocItem(
                                        label,
                                        resolvePath(baseDir, href),
                                        href.substringAfter('#', ""),
                                        (olDepth - 1).coerceAtLeast(0),
                                    ),
                                )
                            }
                        }
                    }
                    XmlPullParser.END_TAG -> when (p.localName()) {
                        "ol" -> if (inToc) olDepth--
                        "nav" -> if (inToc) return out
                    }
                }
            }
            return out
        }

        private fun parseNcx(bytes: ByteArray, baseDir: String): List<EpubTocItem> {
            val p = newParser(bytes)
            val out = ArrayList<EpubTocItem>()
            var depth = 0
            var title = ""
            while (p.next() != XmlPullParser.END_DOCUMENT) {
                when (p.eventType) {
                    XmlPullParser.START_TAG -> when (p.localName()) {
                        "navPoint" -> { depth++; title = "" }
                        // `text` also appears under docTitle; only a navPoint's label counts.
                        "text" -> if (depth > 0 && title.isEmpty()) title = readText(p)
                        "content" -> if (depth > 0) {
                            val src = p.getAttributeValue(null, "src")
                            if (!src.isNullOrBlank() && title.isNotEmpty()) {
                                out.add(
                                    EpubTocItem(
                                        title,
                                        resolvePath(baseDir, src),
                                        src.substringAfter('#', ""),
                                        depth - 1,
                                    ),
                                )
                            }
                        }
                    }
                    XmlPullParser.END_TAG -> if (p.localName() == "navPoint") depth--
                }
            }
            return out
        }

        // -- helpers ------------------------------------------------------

        private fun newParser(bytes: ByteArray): XmlPullParser {
            val p = Xml.newPullParser()
            runCatching { p.setFeature(XmlPullParser.FEATURE_PROCESS_NAMESPACES, false) }
            runCatching { p.setFeature("http://xmlpull.org/v1/doc/features.html#relaxed", true) }
            p.setInput(ByteArrayInputStream(bytes), null)
            // XHTML navigation documents use HTML entities XML does not define.
            for ((name, value) in HTML_ENTITIES) {
                runCatching { p.defineEntityReplacementText(name, value) }
            }
            return p
        }

        private val HTML_ENTITIES = listOf(
            "nbsp" to "\u00A0", "copy" to "\u00A9", "mdash" to "\u2014", "ndash" to "\u2013",
            "hellip" to "\u2026", "lsquo" to "\u2018", "rsquo" to "\u2019",
            "ldquo" to "\u201C", "rdquo" to "\u201D",
        )

        private fun XmlPullParser.localName(): String = (name ?: "").substringAfter(':')

        /** Text of the element the parser is on; leaves it on that element's end tag. */
        private fun readText(p: XmlPullParser): String {
            val sb = StringBuilder()
            var depth = 1
            while (depth > 0) {
                when (p.nextToken()) {
                    XmlPullParser.TEXT,
                    XmlPullParser.CDSECT,
                    XmlPullParser.IGNORABLE_WHITESPACE,
                    -> sb.append(p.text)
                    XmlPullParser.ENTITY_REF -> {
                        val entityName = p.name
                        sb.append(
                            HTML_ENTITIES.firstOrNull { it.first == entityName }?.second
                                ?: p.text.orEmpty(),
                        )
                    }
                    XmlPullParser.START_TAG -> depth++
                    XmlPullParser.END_TAG -> depth--
                    XmlPullParser.END_DOCUMENT -> depth = 0
                }
            }
            return sb.toString().replace(WHITESPACE, " ").trim()
        }

        private val WHITESPACE = Regex("\\s+")

        /** [href] relative to [baseDir], percent-decoded, `.`/`..` folded, fragment dropped. */
        fun resolvePath(baseDir: String, href: String): String {
            val bare = href.substringBefore('#')
            val decoded = try {
                // A literal '+' is not a space in a URL path.
                URLDecoder.decode(bare.replace("+", "%2B"), "UTF-8")
            } catch (_: Exception) {
                bare
            }
            val combined = when {
                decoded.startsWith("/") -> decoded
                baseDir.isEmpty() -> decoded
                else -> "$baseDir/$decoded"
            }
            val parts = ArrayList<String>()
            for (seg in combined.split('/')) {
                when (seg) {
                    "", "." -> Unit
                    ".." -> if (parts.isNotEmpty()) parts.removeAt(parts.size - 1)
                    else -> parts.add(seg)
                }
            }
            return parts.joinToString("/")
        }
    }
}
