package com.aeidolon.vaultexplorer.officeviewer

import java.util.Locale

/** HTML-escapes [s] for use in text nodes and double-quoted attributes. */
internal fun esc(s: String): String {
    var needs = false
    for (ch in s) if (ch == '&' || ch == '<' || ch == '>' || ch == '"' || ch == '\'') { needs = true; break }
    if (!needs) return s
    val sb = StringBuilder(s.length + 16)
    for (ch in s) when (ch) {
        '&' -> sb.append("&amp;")
        '<' -> sb.append("&lt;")
        '>' -> sb.append("&gt;")
        '"' -> sb.append("&quot;")
        '\'' -> sb.append("&#39;")
        else -> sb.append(ch)
    }
    return sb.toString()
}

/** Accepts only `RRGGBB` / `#RRGGBB`; anything else is rejected (no CSS injection). */
internal fun hexColor(s: String?): String? {
    if (s == null) return null
    val t = s.trim().removePrefix("#")
    if (t.length != 6) return null
    for (ch in t) if (!(ch in '0'..'9' || ch in 'a'..'f' || ch in 'A'..'F')) return null
    return "#" + t.lowercase(Locale.ROOT)
}

/** What the Dart side tells the converter about the surrounding app theme and strings. */
internal class ViewOptions(
    val dark: Boolean = false,
    background: String? = null,
    foreground: String? = null,
    muted: String? = null,
    accent: String? = null,
    val notesLabel: String = "Notes",
) {
    val background: String = hexColor(background) ?: if (dark) "#121316" else "#eceef2"
    val foreground: String = hexColor(foreground) ?: if (dark) "#e4e2e6" else "#1b1b1f"
    val muted: String = hexColor(muted) ?: if (dark) "#9a9aa5" else "#5f6068"
    val accent: String = hexColor(accent) ?: "#3b6fd4"
}

internal class DocResource(val mime: String, val bytes: ByteArray)

/**
 * In-memory resources (images) a converted page refers to by relative URL.
 * The WebView plugin serves them from memory under the page's virtual origin;
 * nothing touches the disk or the network.
 */
internal class DocResources {
    private val items = LinkedHashMap<String, DocResource>()
    private val byKey = HashMap<String, String?>()
    private var total = 0L

    val all: Map<String, DocResource> get() = items

    /** Adds [bytes] once per [key]; returns the relative URL, or null when over budget. */
    fun add(key: String, mime: String, bytes: ByteArray): String? {
        if (byKey.containsKey(key)) return byKey[key]
        val url: String? = if (items.size >= MAX_RESOURCES || total + bytes.size > BUDGET) null else {
            val ext = when (mime) {
                "image/jpeg" -> "jpg"; "image/svg+xml" -> "svg"; else -> mime.substringAfter('/')
            }
            val u = "r/${items.size + 1}.$ext"
            items[u] = DocResource(mime, bytes)
            total += bytes.size
            u
        }
        byKey[key] = url
        return url
    }

    companion object {
        const val MAX_RESOURCES = 3000
        const val BUDGET = 48L * 1024 * 1024
    }
}

/** Mime type for image parts a WebView can draw; null for EMF/WMF/TIFF etc. */
internal fun imageMime(partName: String): String? =
    when (partName.substringAfterLast('.', "").lowercase(Locale.ROOT)) {
        "png" -> "image/png"
        "jpg", "jpeg", "jpe", "jfif" -> "image/jpeg"
        "gif" -> "image/gif"
        "bmp" -> "image/bmp"
        "webp" -> "image/webp"
        "svg" -> "image/svg+xml"
        else -> null
    }

internal class ConvertedDocument(
    val html: String,
    val resources: Map<String, DocResource>,
    val title: String?,
)

/** Lays out nested `<ul>`/`<ol>` from a flat sequence of (level, list identity) items. */
internal class ListBuilder(private val out: StringBuilder) {
    private class Lvl(val tag: String, val key: String, var liOpen: Boolean)

    private val stack = ArrayList<Lvl>()

    val isOpen: Boolean get() = stack.isNotEmpty()

    fun item(level: Int, key: String, ordered: Boolean, cssType: String?, start: Int, content: String) {
        val lvl = level.coerceIn(0, 8)
        while (stack.size > lvl + 1) closeTop()
        if (stack.size == lvl + 1 && stack[lvl].key != key) closeTop()
        while (stack.size < lvl + 1) {
            val tag = if (ordered) "ol" else "ul"
            out.append('<').append(tag)
            if (ordered && start != 1) out.append(" start=\"").append(start).append('"')
            if (cssType != null) out.append(" style=\"list-style-type:").append(cssType).append('"')
            out.append('>')
            stack.add(Lvl(tag, key, false))
        }
        val top = stack.last()
        if (top.liOpen) out.append("</li>")
        out.append("<li>").append(content)
        top.liOpen = true
    }

    private fun closeTop() {
        val t = stack.removeAt(stack.size - 1)
        if (t.liOpen) out.append("</li>")
        out.append("</").append(t.tag).append('>')
    }

    fun closeAll() {
        while (stack.isNotEmpty()) closeTop()
    }
}

internal const val BASE_CSS = """
:root{color-scheme:light}
*{box-sizing:border-box}
html{-webkit-text-size-adjust:100%}
body{margin:0;padding:12px;background:var(--bg);color:var(--fg);font:16px/1.5 system-ui,-apple-system,Roboto,sans-serif}
.paper{background:#fff;color:#1b1b1f;max-width:880px;margin:0 auto 14px;padding:22px 24px;border-radius:6px;box-shadow:0 1px 3px rgba(0,0,0,.28);overflow-wrap:anywhere}
.paper p{margin:0 0 .7em}
.paper h1{font-size:1.7em;margin:.8em 0 .4em}.paper h2{font-size:1.4em;margin:.8em 0 .4em}.paper h3{font-size:1.2em;margin:.8em 0 .4em}
.paper h4,.paper h5,.paper h6{font-size:1.05em;margin:.8em 0 .4em}
.paper ul,.paper ol{margin:0 0 .7em;padding-left:1.6em}
.paper li{margin:.15em 0}
.paper .subtitle{color:#5f6068;font-size:1.15em}
.paper table{border-collapse:collapse;margin:0 0 1em}
.paper td,.paper th{border:1px solid #c9c9d0;padding:4px 8px;vertical-align:top;text-align:start}
.paper td>p:last-child{margin-bottom:0}
.paper p,.paper li,.paper td,.paper th{white-space:pre-wrap}
.paper li>p{margin:0}
.paper table.nb td,.paper table.nb th{border-color:transparent}
.paper blockquote{margin:0 0 .7em;padding-inline-start:12px;border-inline-start:3px solid #c9c9d0}
.scroll{overflow-x:auto;margin:0 0 1em}
.paper img{max-width:100%;height:auto}
.lnk{color:#1a56c8;text-decoration:underline}
.ph{display:inline-block;padding:2px 8px;border:1px dashed #9a9aa5;color:#777;border-radius:4px;font-size:.85em}
.pb{border:0;border-top:1px dashed #c4c4cc;margin:1.2em 0}
.sp{height:.6em;margin:0!important}
.textbox{border:1px solid #d5d5dc;padding:8px 12px;margin:0 0 .8em;border-radius:4px;background:#fafafc}
.fnotes{border-top:1px solid #c9c9d0;margin-top:1.4em;padding-top:.6em;font-size:.9em;color:#44444c}
.fnotes p{margin:0 0 .3em}
sup.fn{font-size:.75em}
.slide{position:relative;padding-top:34px}
.slide .num{position:absolute;top:8px;inset-inline-start:12px;font-size:.8em;color:#777;background:#eef0f5;border-radius:10px;padding:0 9px}
.slide h2.st{margin-top:.2em}
.slide.hidden{opacity:.65}
details.notes{margin-top:.8em;border-top:1px dashed #c4c4cc;padding-top:.5em;color:#44444c;font-size:.92em}
details.notes summary{cursor:pointer;color:#5f6068}
"""

/** Wraps [body] into a full, script-free, network-free HTML page. */
internal fun pageHtml(title: String?, body: String, extraCss: String, opts: ViewOptions): String {
    val sb = StringBuilder(body.length + 4096)
    sb.append("<!DOCTYPE html><html><head><meta charset=\"utf-8\">")
    sb.append("<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">")
    sb.append("<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; img-src 'self'; style-src 'unsafe-inline'\">")
    sb.append("<title>").append(esc(title ?: "")).append("</title><style>")
    sb.append(":root{--bg:").append(opts.background).append(";--fg:").append(opts.foreground)
        .append(";--muted:").append(opts.muted).append(";--accent:").append(opts.accent).append("}")
    sb.append(BASE_CSS).append(extraCss)
    sb.append("</style></head><body>").append(body).append("</body></html>")
    return sb.toString()
}


/** Wraps already-escaped inline HTML in the formatting tags shared by the PPTX and ODF converters. */
internal fun wrapInline(
    html: String, bold: Boolean, italic: Boolean, underline: Boolean, strike: Boolean,
    script: Int, color: String?, link: String?,
): String {
    if (html.isEmpty()) return html
    var h = html
    if (bold) h = "<strong>$h</strong>"
    if (italic) h = "<em>$h</em>"
    if (underline) h = "<u>$h</u>"
    if (strike) h = "<s>$h</s>"
    if (script == 1) h = "<sup>$h</sup>" else if (script == 2) h = "<sub>$h</sub>"
    if (color != null && color != "#000000") h = "<span style=\"color:$color\">$h</span>"
    if (link != null) {
        h = if (link.isEmpty()) "<span class=\"lnk\">$h</span>"
        else "<span class=\"lnk\" title=\"${esc(link)}\">$h</span>"
    }
    return h
}

/** Spreadsheet column name for a 0-based index: 0 -> A, 25 -> Z, 26 -> AA. */
internal fun colName(index: Int): String {
    var n = index
    val sb = StringBuilder()
    do {
        sb.append('A' + (n % 26))
        n = n / 26 - 1
    } while (n >= 0)
    return sb.reverse().toString()
}
