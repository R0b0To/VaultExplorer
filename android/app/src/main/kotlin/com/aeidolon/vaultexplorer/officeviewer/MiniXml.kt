package com.aeidolon.vaultexplorer.officeviewer

import java.io.InputStreamReader
import java.io.Reader

/**
 * A small, dependency-free, namespace-aware XML reader for the Office viewer.
 *
 * Why not `XmlPullParser` / `javax.xml`: this code has to run on a plain JVM
 * (unit tests) and on Android identically, has to canonicalise namespace
 * prefixes (Office writers are free to pick any prefix, see [CANON]), and must
 * never resolve entities or external subsets. `<!DOCTYPE ...>` is skipped
 * without being interpreted, so there is no entity expansion at all (no XXE,
 * no billion-laughs); only the five predefined entities and numeric character
 * references are decoded.
 *
 * Element and attribute names come out as `prefix:local` where `prefix` is
 * the canonical one for the namespace URI (`w:p`, `a:t`, `text:p`, ...), or
 * just `local` for the spreadsheetml / package-relationship namespaces.
 */
internal class XmlLimitException(message: String) : Exception(message)

internal class XmlNode(val name: String, attrs: Map<String, String>?) {
    private val attributes: Map<String, String> = attrs ?: emptyMap()
    private var kids: ArrayList<XmlNode>? = null

    /** Non-null for a text node (name is "#text"). */
    var text: String? = null
        private set

    val children: List<XmlNode> get() = kids ?: emptyList()

    fun attr(n: String): String? = attributes[n]

    fun add(child: XmlNode) {
        (kids ?: ArrayList<XmlNode>().also { kids = it }).add(child)
    }

    /** Element children only (text nodes dropped). */
    val elements: List<XmlNode> get() = children.filter { it.text == null }

    fun first(n: String): XmlNode? = children.firstOrNull { it.text == null && it.name == n }

    fun all(n: String): List<XmlNode> = children.filter { it.text == null && it.name == n }

    /** Depth-first search for the first descendant named [n]. */
    fun find(n: String): XmlNode? {
        for (c in children) {
            if (c.text != null) continue
            if (c.name == n) return c
            c.find(n)?.let { return it }
        }
        return null
    }

    /** All descendants named [n], document order. [stopAt] prunes recursion. */
    fun findAll(n: String, stopAt: String? = null, out: MutableList<XmlNode> = ArrayList()): MutableList<XmlNode> {
        for (c in children) {
            if (c.text != null) continue
            if (c.name == n) {
                out.add(c)
                if (stopAt == null || n != stopAt) c.findAll(n, stopAt, out)
            } else {
                c.findAll(n, stopAt, out)
            }
        }
        return out
    }

    /** Concatenated text of all descendant text nodes. */
    fun textContent(): String {
        val sb = StringBuilder()
        collectText(sb)
        return sb.toString()
    }

    private fun collectText(sb: StringBuilder) {
        text?.let { sb.append(it); return }
        for (c in children) c.collectText(sb)
    }

    companion object {
        fun textNode(s: String): XmlNode = XmlNode("#text", null).also { it.text = s }
    }
}

/** Canonical prefix per namespace URI. `""` means "no prefix". */
private val CANON: Map<String, String> = buildMap {
    fun both(ecma: String, strict: String, prefix: String) { put(ecma, prefix); put(strict, prefix) }
    both("http://schemas.openxmlformats.org/wordprocessingml/2006/main", "http://purl.oclc.org/ooxml/wordprocessingml/main", "w")
    both("http://schemas.openxmlformats.org/drawingml/2006/main", "http://purl.oclc.org/ooxml/drawingml/main", "a")
    both("http://schemas.openxmlformats.org/presentationml/2006/main", "http://purl.oclc.org/ooxml/presentationml/main", "p")
    both("http://schemas.openxmlformats.org/officeDocument/2006/relationships", "http://purl.oclc.org/ooxml/officeDocument/relationships", "r")
    both("http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing", "http://purl.oclc.org/ooxml/drawingml/wordprocessingDrawing", "wp")
    both("http://schemas.openxmlformats.org/drawingml/2006/picture", "http://purl.oclc.org/ooxml/drawingml/picture", "pic")
    both("http://schemas.openxmlformats.org/spreadsheetml/2006/main", "http://purl.oclc.org/ooxml/spreadsheetml/main", "")
    put("http://schemas.openxmlformats.org/package/2006/relationships", "")
    put("http://schemas.openxmlformats.org/package/2006/metadata/core-properties", "cp")
    put("http://schemas.openxmlformats.org/markup-compatibility/2006", "mc")
    put("http://schemas.microsoft.com/office/word/2010/wordprocessingShape", "wps")
    put("urn:schemas-microsoft-com:vml", "v")
    put("http://purl.org/dc/elements/1.1/", "dc")
    put("urn:oasis:names:tc:opendocument:xmlns:office:1.0", "office")
    put("urn:oasis:names:tc:opendocument:xmlns:text:1.0", "text")
    put("urn:oasis:names:tc:opendocument:xmlns:table:1.0", "table")
    put("urn:oasis:names:tc:opendocument:xmlns:drawing:1.0", "draw")
    put("urn:oasis:names:tc:opendocument:xmlns:style:1.0", "style")
    put("urn:oasis:names:tc:opendocument:xmlns:presentation:1.0", "presentation")
    put("urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0", "fo")
    put("urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0", "svg")
    put("urn:oasis:names:tc:opendocument:xmlns:manifest:1.0", "manifest")
    put("urn:oasis:names:tc:opendocument:xmlns:meta:1.0", "meta")
    put("urn:oasis:names:tc:opendocument:xmlns:datastyle:1.0", "number")
    put("http://www.w3.org/1999/xlink", "xlink")
}

/**
 * Streaming pull parser. Call [next] until it returns [Event.EOF]; after each
 * call the `name`/`attrs`/`text` properties describe the current event.
 */
internal class XmlPull(private val reader: Reader) {
    enum class Event { START, END, TEXT, EOF }

    var name: String = ""
        private set
    var attrs: Map<String, String> = emptyMap()
        private set
    var text: String = ""
        private set

    private var peeked = -2
    private var pendingEnd = false
    private val nsStack = ArrayList<Map<String, String>?>()
    private val nameStack = ArrayList<String>()

    private fun read(): Int {
        if (peeked != -2) { val c = peeked; peeked = -2; return c }
        return reader.read()
    }

    private fun peek(): Int {
        if (peeked == -2) peeked = reader.read()
        return peeked
    }

    private fun lookupUri(prefix: String): String? {
        for (i in nsStack.indices.reversed()) {
            nsStack[i]?.get(prefix)?.let { return it }
        }
        return if (prefix == "xml") "xml" else null
    }

    private fun canonical(prefix: String, local: String, isAttr: Boolean): String {
        if (prefix.isEmpty()) {
            if (isAttr) return local
            val uri = lookupUri("") ?: return local
            val p = CANON[uri] ?: return local
            return if (p.isEmpty()) local else "$p:$local"
        }
        val uri = lookupUri(prefix) ?: return "$prefix:$local"
        if (uri == "xml") return "xml:$local"
        val p = CANON[uri] ?: return "$prefix:$local"
        return if (p.isEmpty()) local else "$p:$local"
    }

    fun next(): Event {
        if (pendingEnd) {
            pendingEnd = false
            name = nameStack.removeAt(nameStack.size - 1)
            nsStack.removeAt(nsStack.size - 1)
            return Event.END
        }
        while (true) {
            val c = peek()
            if (c == -1) return Event.EOF
            if (c != '<'.code) {
                val sb = StringBuilder()
                while (true) {
                    val d = peek()
                    if (d == -1 || d == '<'.code) break
                    read()
                    if (d == '&'.code) readEntity(sb) else sb.append(d.toChar())
                }
                if (nameStack.isEmpty()) continue // text outside the root element
                text = sb.toString()
                return Event.TEXT
            }
            read() // '<'
            val d = peek()
            when {
                d == '?'.code -> { skipUntil("?>"); continue }
                d == '!'.code -> {
                    read()
                    if (peek() == '-'.code) { skipUntil("-->"); continue }
                    if (peek() == '['.code) { // <![CDATA[ ... ]]>
                        skipLiteral("[CDATA[")
                        val sb = StringBuilder()
                        readUntil("]]>", sb)
                        if (nameStack.isEmpty()) continue
                        text = sb.toString()
                        return Event.TEXT
                    }
                    skipDoctype(); continue
                }
                d == '/'.code -> {
                    read()
                    val sb = StringBuilder()
                    while (true) { val e = read(); if (e == -1 || e == '>'.code) break; sb.append(e.toChar()) }
                    if (nameStack.isEmpty()) throw XmlLimitException("unbalanced end tag")
                    name = nameStack.removeAt(nameStack.size - 1)
                    nsStack.removeAt(nsStack.size - 1)
                    return Event.END
                }
                else -> return readStartTag()
            }
        }
    }

    private fun readStartTag(): Event {
        val raw = StringBuilder()
        while (true) {
            val c = peek()
            if (c == -1 || c == '>'.code || c == '/'.code || c.toChar().isWhitespace()) break
            raw.append(read().toChar())
        }
        val rawAttrs = ArrayList<Pair<String, String>>()
        var selfClosing = false
        while (true) {
            skipSpace()
            val c = peek()
            if (c == -1) break
            if (c == '>'.code) { read(); break }
            if (c == '/'.code) { read(); if (peek() == '>'.code) read(); selfClosing = true; break }
            val an = StringBuilder()
            while (true) {
                val e = peek()
                if (e == -1 || e == '='.code || e == '>'.code || e == '/'.code || e.toChar().isWhitespace()) break
                an.append(read().toChar())
            }
            skipSpace()
            if (peek() != '='.code) { rawAttrs.add(an.toString() to ""); continue }
            read(); skipSpace()
            val q = read()
            val av = StringBuilder()
            if (q == '"'.code || q == '\''.code) {
                while (true) {
                    val e = read()
                    if (e == -1 || e == q) break
                    if (e == '&'.code) readEntity(av) else av.append(e.toChar())
                }
            }
            rawAttrs.add(an.toString() to av.toString())
        }
        var decls: HashMap<String, String>? = null
        for ((k, v) in rawAttrs) {
            if (k == "xmlns") (decls ?: HashMap<String, String>().also { decls = it })[""] = v
            else if (k.startsWith("xmlns:")) (decls ?: HashMap<String, String>().also { decls = it })[k.substring(6)] = v
        }
        nsStack.add(decls)
        val rs = raw.toString()
        val colon = rs.indexOf(':')
        name = if (colon < 0) canonical("", rs, false) else canonical(rs.substring(0, colon), rs.substring(colon + 1), false)
        var map: HashMap<String, String>? = null
        for ((k, v) in rawAttrs) {
            if (k == "xmlns" || k.startsWith("xmlns:")) continue
            val i = k.indexOf(':')
            val key = if (i < 0) k else canonical(k.substring(0, i), k.substring(i + 1), true)
            (map ?: HashMap<String, String>().also { map = it })[key] = v
        }
        attrs = map ?: emptyMap()
        nameStack.add(name)
        if (selfClosing) pendingEnd = true
        return Event.START
    }

    private fun skipSpace() { while (true) { val c = peek(); if (c != -1 && c.toChar().isWhitespace()) read() else break } }

    private fun skipLiteral(s: String) { for (ch in s) if (peek() == ch.code) read() }

    private fun skipUntil(end: String) { readUntil(end, null) }

    private fun readUntil(end: String, sb: StringBuilder?) {
        val win = StringBuilder()
        while (true) {
            val c = read()
            if (c == -1) return
            win.append(c.toChar())
            if (win.length > end.length) { sb?.append(win[0]); win.deleteCharAt(0) }
            if (win.length == end.length && win.toString() == end) return
        }
    }

    private fun skipDoctype() {
        var depth = 0
        while (true) {
            val c = read()
            if (c == -1) return
            if (c == '['.code) depth++
            else if (c == ']'.code) depth--
            else if (c == '>'.code && depth <= 0) return
        }
    }

    private fun readEntity(sb: StringBuilder) {
        val ent = StringBuilder()
        while (true) {
            val c = peek()
            if (c == -1 || c == ';'.code || c == '<'.code || c == '&'.code || ent.length > 12) break
            ent.append(read().toChar())
        }
        val terminated = peek() == ';'.code
        if (terminated) read()
        val e = ent.toString()
        val decoded: String? = when {
            e == "lt" -> "<"
            e == "gt" -> ">"
            e == "amp" -> "&"
            e == "quot" -> "\""
            e == "apos" -> "'"
            e.startsWith("#x") || e.startsWith("#X") -> e.substring(2).toIntOrNull(16)?.let { cp(it) }
            e.startsWith("#") -> e.substring(1).toIntOrNull()?.let { cp(it) }
            else -> null
        }
        if (terminated && decoded != null) sb.append(decoded)
        else { sb.append('&').append(e); if (terminated) sb.append(';') }
    }

    private fun cp(v: Int): String? =
        if (v in 0x20..0x10FFFF && v !in 0xD800..0xDFFF || v == 9 || v == 10 || v == 13) String(Character.toChars(v)) else null

    companion object {
        /** Opens [bytes] as UTF-8 (default) or UTF-16 (BOM). */
        fun reader(bytes: ByteArray): XmlPull {
            var off = 0
            var cs: java.nio.charset.Charset = Charsets.UTF_8
            fun b(i: Int) = bytes[i].toInt() and 0xFF
            if (bytes.size >= 3 && b(0) == 0xEF && b(1) == 0xBB && b(2) == 0xBF) off = 3
            else if (bytes.size >= 2 && b(0) == 0xFF && b(1) == 0xFE) { cs = Charsets.UTF_16LE; off = 2 }
            else if (bytes.size >= 2 && b(0) == 0xFE && b(1) == 0xFF) { cs = Charsets.UTF_16BE; off = 2 }
            val reader = InputStreamReader(java.io.ByteArrayInputStream(bytes, off, bytes.size - off), cs)
            return XmlPull(java.io.BufferedReader(reader, 1 shl 16))
        }

        /** Parses a whole part into a tree. Bounded depth and node count. */
        fun parseTree(bytes: ByteArray, maxNodes: Int = 4_000_000, maxDepth: Int = 400): XmlNode {
            val p = reader(bytes)
            val stack = ArrayList<XmlNode>()
            var root: XmlNode? = null
            var count = 0
            while (true) {
                when (p.next()) {
                    Event.START -> {
                        if (++count > maxNodes) throw XmlLimitException("too many XML nodes")
                        if (stack.size >= maxDepth) throw XmlLimitException("XML too deeply nested")
                        val n = XmlNode(p.name, p.attrs)
                        if (stack.isEmpty()) root = n else stack.last().add(n)
                        stack.add(n)
                    }
                    Event.END -> if (stack.isNotEmpty()) stack.removeAt(stack.size - 1)
                    Event.TEXT -> {
                        if (stack.isEmpty()) continue
                        if (++count > maxNodes) throw XmlLimitException("too many XML nodes")
                        stack.last().add(XmlNode.textNode(p.text))
                    }
                    Event.EOF -> return root ?: throw XmlLimitException("empty XML document")
                }
            }
        }
    }
}
