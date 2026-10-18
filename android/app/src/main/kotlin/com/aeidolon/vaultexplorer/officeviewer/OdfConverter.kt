package com.aeidolon.vaultexplorer.officeviewer

/**
 * OpenDocument text (.odt/.ott), presentations (.odp/.otp) and spreadsheets
 * (.ods/.ots) -> the same HTML reading views as the OOXML converters.
 * Encrypted packages (`manifest:encryption-data`) are reported, not decoded.
 */
internal class OdfConverter(
    private val pkg: OfficePackage,
    private val res: DocResources,
    private val opts: ViewOptions,
) {
    var title: String? = null
        private set
    val css = StringBuilder()

    private class OStyle(val name: String, val parent: String?) {
        var bold: Boolean? = null
        var italic: Boolean? = null
        var underline: Boolean? = null
        var strike: Boolean? = null
        var color: String? = null
        var script: Int? = null
        var align: String? = null
        var rtl: Boolean? = null
        var background: String? = null
        var hidden = false
    }

    private class ListLevel(val ordered: Boolean, val cssType: String?, val start: Int)

    private val styles = HashMap<String, OStyle>()
    private val listStyles = HashMap<String, HashMap<Int, ListLevel>>()
    private val notes = ArrayList<String>()
    private val listCounters = HashMap<String, Int>()
    private lateinit var content: XmlNode

    fun mimeKind(): String? {
        val mt = pkg.bytes("mimetype")?.toString(Charsets.US_ASCII)?.trim() ?: return null
        return when {
            mt.startsWith("application/vnd.oasis.opendocument.text") -> "odt"
            mt.startsWith("application/vnd.oasis.opendocument.presentation") -> "odp"
            mt.startsWith("application/vnd.oasis.opendocument.spreadsheet") -> "ods"
            else -> null
        }
    }

    private fun checkEncryption() {
        val manifest = try { pkg.tree("META-INF/manifest.xml") } catch (e: XmlLimitException) { null } ?: return
        if (manifest.find("manifest:encryption-data") != null) {
            throw OfficeException(OfficeError.ENCRYPTED, "encrypted OpenDocument package")
        }
    }

    private fun load() {
        checkEncryption()
        content = try { pkg.tree("content.xml") } catch (e: XmlLimitException) {
            throw OfficeException(OfficeError.TOO_LARGE, e.message ?: "XML too large", e)
        } ?: throw OfficeException(OfficeError.UNSUPPORTED, "no content.xml")
        title = documentTitle(pkg)
        val stylesRoot = try { pkg.tree("styles.xml") } catch (e: XmlLimitException) { null }
        collectStyles(stylesRoot)
        collectStyles(content)
    }

    // ── styles ────────────────────────────────────────────────────────────

    private fun collectStyles(root: XmlNode?) {
        if (root == null) return
        for (holder in listOf("office:styles", "office:automatic-styles")) {
            val h = root.first(holder) ?: continue
            for (s in h.all("style:style")) {
                val name = s.attr("style:name") ?: continue
                val st = OStyle(name, s.attr("style:parent-style-name"))
                s.first("style:text-properties")?.let { tp ->
                    val fw = tp.attr("fo:font-weight")
                    if (fw != null) st.bold = fw == "bold" || (fw.toIntOrNull() ?: 0) >= 600
                    tp.attr("fo:font-style")?.let { st.italic = it == "italic" || it == "oblique" }
                    tp.attr("style:text-underline-style")?.let { st.underline = it != "none" }
                    tp.attr("style:text-line-through-style")?.let { st.strike = it != "none" }
                    hexColor(tp.attr("fo:color"))?.let { st.color = it }
                    tp.attr("style:text-position")?.let { pos ->
                        val first = pos.trim().split(' ').firstOrNull() ?: ""
                        st.script = when {
                            first.startsWith("super") -> 1
                            first.startsWith("sub") -> 2
                            first.endsWith("%") -> first.dropLast(1).toIntOrNull()?.let { if (it > 0) 1 else if (it < 0) 2 else 0 }
                            else -> null
                        }
                        if (st.script == 0) st.script = null
                    }
                }
                s.first("style:paragraph-properties")?.let { pp ->
                    pp.attr("fo:text-align")?.let { st.align = it }
                    pp.attr("style:writing-mode")?.let { st.rtl = it.startsWith("rl") }
                }
                s.first("style:table-properties")?.let { tp -> if (tp.attr("table:display") == "false") st.hidden = true }
                s.first("style:table-cell-properties")?.let { cp ->
                    hexColor(cp.attr("fo:background-color"))?.let { st.background = it }
                }
                styles[name] = st
            }
            for (ls in h.all("text:list-style")) {
                val name = ls.attr("style:name") ?: continue
                val levels = HashMap<Int, ListLevel>()
                for (l in ls.elements) {
                    val lvl = l.attr("text:level")?.toIntOrNull() ?: continue
                    when (l.name) {
                        "text:list-level-style-number" -> {
                            val fmt = l.attr("style:num-format") ?: "1"
                            levels[lvl - 1] = ListLevel(
                                fmt.isNotEmpty(),
                                when (fmt) { "a" -> "lower-alpha"; "A" -> "upper-alpha"; "i" -> "lower-roman"; "I" -> "upper-roman"; "" -> "none"; else -> null },
                                l.attr("text:start-value")?.toIntOrNull() ?: 1,
                            )
                        }
                        "text:list-level-style-bullet", "text:list-level-style-image" ->
                            levels[lvl - 1] = ListLevel(false, null, 1)
                    }
                }
                listStyles[name] = levels
            }
        }
    }

    private fun <T> styleProp(name: String?, sel: (OStyle) -> T?): T? {
        var cur = name
        var steps = 0
        while (cur != null && steps++ < 24) {
            val s = styles[cur] ?: return null
            sel(s)?.let { return it }
            cur = s.parent
        }
        return null
    }

    private fun styleChainHas(name: String?, target: String): Boolean {
        var cur = name
        var steps = 0
        while (cur != null && steps++ < 24) {
            if (cur == target) return true
            cur = styles[cur]?.parent
        }
        return false
    }

    // ── text documents ────────────────────────────────────────────────────

    private class Inline {
        val sb = StringBuilder()
        val extra = StringBuilder()
        var lastSpace = true
        var hasContent = false
        fun text(s: String) {
            for (ch in s) {
                if (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r') {
                    if (!lastSpace) sb.append(' ')
                    lastSpace = true
                } else {
                    when (ch) {
                        '&' -> sb.append("&amp;"); '<' -> sb.append("&lt;"); '>' -> sb.append("&gt;")
                        '"' -> sb.append("&quot;"); '\'' -> sb.append("&#39;"); else -> sb.append(ch)
                    }
                    lastSpace = false
                    hasContent = true
                }
            }
        }
        fun raw(h: String, content: Boolean = true) { sb.append(h); lastSpace = false; if (content) hasContent = true }
    }

    fun convertText(): String {
        load()
        val body = content.first("office:body")?.first("office:text")
            ?: throw OfficeException(OfficeError.UNSUPPORTED, "no office:text")
        val out = StringBuilder("<article class=\"paper\">")
        renderBlocks(body, out)
        if (notes.isNotEmpty()) {
            out.append("<div class=\"fnotes\">")
            for ((i, n) in notes.withIndex()) out.append("<p><sup class=\"fn\">").append(i + 1).append("</sup> ").append(n).append("</p>")
            out.append("</div>")
        }
        out.append("</article>")
        return out.toString()
    }

    private fun renderBlocks(container: XmlNode, out: StringBuilder) {
        for (c in container.elements) {
            when (c.name) {
                "text:h" -> heading(c, out)
                "text:p" -> paragraph(c, out)
                "text:list" -> renderList(c, 0, null, out)
                "table:table" -> textTable(c, out)
                "text:section", "text:index-body", "text:table-of-content", "text:illustration-index",
                "text:table-index", "text:object-index", "text:user-index", "text:alphabetical-index",
                "text:bibliography", "text:index-title" -> renderBlocks(c, out)
                "draw:frame" -> {
                    val ctx = Inline(); frame(c, ctx); out.append(ctx.sb).append(ctx.extra)
                }
            }
        }
    }

    private fun inlineOf(node: XmlNode): Inline {
        val ctx = Inline()
        inline(node, ctx)
        return ctx
    }

    private fun attrsFor(styleName: String?): String {
        val sb = StringBuilder()
        if (styleProp(styleName) { it.rtl } == true) sb.append(" dir=\"rtl\"")
        val align = when (styleProp(styleName) { it.align }) {
            "center" -> "center"
            "justify" -> "justify"
            "end", "right" -> if (styleProp(styleName) { it.rtl } == true) null else "right"
            else -> null
        }
        if (align != null) sb.append(" style=\"text-align:").append(align).append('"')
        return sb.toString()
    }

    private fun heading(h: XmlNode, out: StringBuilder) {
        val ctx = inlineOf(h)
        val lvl = (h.attr("text:outline-level")?.toIntOrNull() ?: 1).coerceIn(1, 6)
        out.append("<h").append(lvl).append(attrsFor(h.attr("text:style-name"))).append('>').append(ctx.sb)
            .append("</h").append(lvl).append('>').append(ctx.extra)
    }

    private fun paragraph(p: XmlNode, out: StringBuilder) {
        val ctx = inlineOf(p)
        val style = p.attr("text:style-name")
        if (!ctx.hasContent && ctx.extra.isEmpty()) {
            val spacer = "<p class=\"sp\"></p>"
            if (!out.endsWith(spacer) && out.length > "<article class=\"paper\">".length) out.append(spacer)
            return
        }
        when {
            styleChainHas(style, "Title") -> out.append("<h1 class=\"title\"").append(attrsFor(style)).append('>').append(ctx.sb).append("</h1>")
            styleChainHas(style, "Subtitle") -> out.append("<p class=\"subtitle\"").append(attrsFor(style)).append('>').append(ctx.sb).append("</p>")
            else -> out.append("<p").append(attrsFor(style)).append('>').append(ctx.sb).append("</p>")
        }
        out.append(ctx.extra)
    }

    private fun renderList(list: XmlNode, depth: Int, inheritedStyle: String?, out: StringBuilder) {
        val styleName = list.attr("text:style-name") ?: inheritedStyle
        val level = styleName?.let { listStyles[it]?.get(depth) }
        val ordered = level?.ordered ?: false
        val key = styleName ?: ""
        val continues = depth == 0 && ordered && list.attr("text:continue-numbering") == "true"
        val base = if (continues) (listCounters[key] ?: 0) else (level?.start ?: 1) - 1
        val start = base + 1
        out.append(if (ordered) "<ol" else "<ul")
        if (ordered && start != 1) out.append(" start=\"").append(start).append('"')
        if (level?.cssType != null) out.append(" style=\"list-style-type:").append(level.cssType).append('"')
        out.append('>')
        var count = 0
        for (item in list.elements) {
            if (item.name != "text:list-item" && item.name != "text:list-header") continue
            val hasBlock = item.elements.any { it.name == "text:p" || it.name == "text:h" || it.name == "table:table" }
            if (!hasBlock) {
                // an item that only wraps a deeper list (as LibreOffice writes outline levels): no empty bullet
                for (c in item.elements) if (c.name == "text:list") renderList(c, depth + 1, styleName, out)
                continue
            }
            count++
            out.append("<li>")
            for (c in item.elements) {
                when (c.name) {
                    "text:p", "text:h" -> paragraphInItem(c, out)
                    "text:list" -> renderList(c, depth + 1, styleName, out)
                    "table:table" -> textTable(c, out)
                }
            }
            out.append("</li>")
        }
        if (depth == 0 && ordered) listCounters[key] = base + count
        out.append(if (ordered) "</ol>" else "</ul>")
    }

    private fun paragraphInItem(p: XmlNode, out: StringBuilder) {
        val ctx = inlineOf(p)
        if (!ctx.hasContent && ctx.extra.isEmpty()) return
        out.append("<p").append(attrsFor(p.attr("text:style-name"))).append('>').append(ctx.sb).append("</p>").append(ctx.extra)
    }

    private fun inline(node: XmlNode, ctx: Inline) {
        for (c in node.children) {
            if (c.text != null) { ctx.text(c.text!!); continue }
            when (c.name) {
                "text:span" -> {
                    val inner = Inline().also { it.lastSpace = ctx.lastSpace }
                    inline(c, inner)
                    ctx.lastSpace = inner.lastSpace
                    val sn = c.attr("text:style-name")
                    ctx.raw(
                        wrapInline(
                            inner.sb.toString(),
                            styleProp(sn) { it.bold } == true, styleProp(sn) { it.italic } == true,
                            styleProp(sn) { it.underline } == true, styleProp(sn) { it.strike } == true,
                            styleProp(sn) { it.script } ?: 0, styleProp(sn) { it.color }, null,
                        ),
                        inner.hasContent,
                    )
                    ctx.extra.append(inner.extra)
                }
                "text:a" -> {
                    val inner = Inline().also { it.lastSpace = ctx.lastSpace }
                    inline(c, inner)
                    ctx.lastSpace = inner.lastSpace
                    ctx.raw(wrapInline(inner.sb.toString(), false, false, false, false, 0, null, c.attr("xlink:href") ?: ""), inner.hasContent)
                    ctx.extra.append(inner.extra)
                }
                "text:s" -> ctx.raw("&nbsp;".repeat((c.attr("text:c")?.toIntOrNull() ?: 1).coerceIn(1, 200)), false)
                "text:tab" -> ctx.raw("&emsp;", false)
                "text:line-break" -> ctx.raw("<br>", false)
                "text:note" -> {
                    val body = c.first("text:note-body")
                    if (body != null) {
                        val parts = body.all("text:p").map { inlineOf(it).sb.toString() }.filter { it.isNotBlank() }
                        notes.add(parts.joinToString(" "))
                        ctx.raw("<sup class=\"fn\">${notes.size}</sup>", true)
                    }
                }
                "draw:frame" -> frame(c, ctx)
                "draw:image" -> image(c, null, null, ctx)
                "draw:custom-shape", "draw:text-box" -> textBox(c, ctx)
                "text:ruby" -> c.first("text:ruby-base")?.let { inline(it, ctx) }
                "office:annotation", "office:annotation-end", "text:bookmark", "text:bookmark-start",
                "text:bookmark-end", "text:soft-page-break", "text:reference-mark", "text:change",
                "text:change-start", "text:change-end", "text:sequence-decls", "text:tracked-changes" -> {}
                else -> inline(c, ctx)
            }
        }
    }

    private fun cssLength(v: String?): Int? {
        if (v == null) return null
        val m = LENGTH.matchEntire(v.trim()) ?: return null
        val n = m.groupValues[1].toDoubleOrNull() ?: return null
        val px = when (m.groupValues[2]) {
            "cm" -> n * 96 / 2.54; "mm" -> n * 96 / 25.4; "in" -> n * 96; "pt" -> n * 96 / 72
            "pc" -> n * 16; "px" -> n; else -> return null
        }
        return px.toInt().takeIf { it in 1..4000 }
    }

    private fun frame(f: XmlNode, ctx: Inline) {
        val width = cssLength(f.attr("svg:width"))
        val alt = f.first("svg:desc")?.textContent() ?: f.first("svg:title")?.textContent()
        var handled = false
        for (c in f.elements) {
            when (c.name) {
                "draw:image" -> { image(c, width, alt, ctx); handled = true }
                "draw:text-box" -> { textBox(c, ctx); handled = true }
                "draw:object", "draw:object-ole", "draw:plugin" -> {
                    if (!handled) ctx.raw("<span class=\"ph\">\u25A2</span>"); handled = true
                }
            }
        }
    }

    private fun image(img: XmlNode, width: Int?, alt: String?, ctx: Inline) {
        val href = img.attr("xlink:href")
        val bytes = href?.let { pkg.bytes(OfficePackage.normalize(it.removePrefix("./"))) }
        val mime = href?.let { imageMime(it) }
        val url = if (bytes != null && mime != null) res.add(href, mime, bytes) else null
        if (url == null) { ctx.raw("<span class=\"ph\">\u25A2</span>"); return }
        val sb = StringBuilder("<img src=\"").append(url).append("\" alt=\"").append(esc(alt ?: "")).append('"')
        if (width != null) sb.append(" style=\"width:").append(width).append("px;max-width:100%\"")
        ctx.raw(sb.append('>').toString())
    }

    private fun textBox(box: XmlNode, ctx: Inline) {
        val sb = StringBuilder()
        renderBlocks(box, sb)
        if (sb.isNotEmpty()) ctx.extra.append("<div class=\"textbox\">").append(sb).append("</div>")
    }

    private fun textTable(tbl: XmlNode, out: StringBuilder) {
        out.append("<div class=\"scroll\"><table>")
        tableRows(tbl) { row ->
            out.append("<tr>")
            for (cell in row.elements) {
                if (cell.name == "table:covered-table-cell") continue
                if (cell.name != "table:table-cell") continue
                val reps = (cell.attr("table:number-columns-repeated")?.toIntOrNull() ?: 1).coerceIn(1, 30)
                val empty = cell.elements.isEmpty()
                repeat(if (empty) 1 else reps) {
                    out.append("<td")
                    cell.attr("table:number-columns-spanned")?.toIntOrNull()?.takeIf { it > 1 }?.let { out.append(" colspan=\"").append(it).append('"') }
                    cell.attr("table:number-rows-spanned")?.toIntOrNull()?.takeIf { it > 1 }?.let { out.append(" rowspan=\"").append(it).append('"') }
                    styleProp(cell.attr("table:style-name")) { it.background }?.let { out.append(" style=\"background:").append(it).append('"') }
                    out.append('>')
                    renderBlocks(cell, out)
                    out.append("</td>")
                }
            }
            out.append("</tr>")
        }
        out.append("</table></div>")
    }

    /** Visits every `table:table-row`, flattening header-rows / row-groups / rows wrappers. */
    private fun tableRows(node: XmlNode, visit: (XmlNode) -> Unit) {
        for (c in node.elements) when (c.name) {
            "table:table-row" -> visit(c)
            "table:table-header-rows", "table:table-row-group", "table:table-rows" -> tableRows(c, visit)
        }
    }

    // ── presentations ─────────────────────────────────────────────────────

    fun convertPresentation(): String {
        load()
        val pres = content.first("office:body")?.first("office:presentation")
            ?: throw OfficeException(OfficeError.UNSUPPORTED, "no office:presentation")
        val out = StringBuilder()
        var n = 0
        for (page in pres.all("draw:page")) {
            if (++n > 1000) break
            out.append("<section class=\"paper slide\"><div class=\"num\">").append(n).append("</div>")
            val titles = ArrayList<String>()
            val body = StringBuilder()
            slideShapes(page, titles, body)
            if (titles.isNotEmpty()) out.append("<h2 class=\"st\">").append(titles.joinToString("<br>")).append("</h2>")
            out.append(body)
            page.first("presentation:notes")?.let { nt ->
                val nb = StringBuilder()
                for (fr in nt.findAll("draw:frame")) {
                    if (fr.attr("presentation:class") != "notes") continue
                    fr.first("draw:text-box")?.let { renderBlocks(it, nb) }
                }
                if (nb.isNotEmpty()) out.append("<details class=\"notes\"><summary>").append(esc(opts.notesLabel)).append("</summary>").append(nb).append("</details>")
            }
            out.append("</section>")
        }
        if (n == 0) throw OfficeException(OfficeError.UNSUPPORTED, "no slides")
        return out.toString()
    }

    private fun slideShapes(node: XmlNode, titles: MutableList<String>, body: StringBuilder) {
        for (c in node.elements) {
            when (c.name) {
                "draw:frame" -> {
                    val cls = c.attr("presentation:class")
                    if (cls == "page-number" || cls == "date-time" || cls == "footer" || cls == "header" || cls == "notes") continue
                    val tb = c.first("draw:text-box")
                    when {
                        tb != null && (cls == "title") -> {
                            for (p in tb.findAll("text:p")) { val h = inlineOf(p).sb.toString(); if (h.isNotBlank()) titles.add(h) }
                        }
                        tb != null -> {
                            val sb = StringBuilder(); renderBlocks(tb, sb)
                            if (cls == "subtitle") body.append(sb.toString().replace("<p>", "<p class=\"subtitle\">")) else body.append(sb)
                        }
                        c.first("table:table") != null -> textTable(c.first("table:table")!!, body)
                        c.first("draw:image") != null -> {
                            val ctx = Inline(); frame(c, ctx); body.append("<p>").append(ctx.sb).append("</p>")
                        }
                        c.first("draw:object") != null -> body.append("<p><span class=\"ph\">\uD83D\uDCCA</span></p>")
                    }
                }
                "draw:custom-shape" -> {
                    val sb = StringBuilder(); renderBlocks(c, sb); body.append(sb)
                }
                "draw:g" -> slideShapes(c, titles, body)
            }
        }
    }

    // ── spreadsheets ──────────────────────────────────────────────────────

    fun convertSpreadsheet(): String {
        load()
        val sp = content.first("office:body")?.first("office:spreadsheet")
            ?: throw OfficeException(OfficeError.UNSUPPORTED, "no office:spreadsheet")
        val all = sp.all("table:table")
        val visible = all.filter { styles[it.attr("table:style-name")]?.hidden != true }.ifEmpty { all }
        val sheets = visible.take(100).map { sheet(it) }
        if (sheets.isEmpty()) throw OfficeException(OfficeError.UNSUPPORTED, "no sheets")
        val out = StringBuilder()
        SheetGrid.render(sheets, out, css)
        return out.toString()
    }

    private fun cellDisplay(cell: XmlNode): String {
        val ps = cell.all("text:p")
        if (ps.isEmpty()) return ""
        return ps.joinToString("\n") { p ->
            val ctx = Inline(); inlineTextOnly(p, ctx); ctx.sb.toString().let { unescapeBasic(it) }
        }
    }

    private fun inlineTextOnly(node: XmlNode, ctx: Inline) {
        for (c in node.children) {
            if (c.text != null) { ctx.text(c.text!!); continue }
            when (c.name) {
                "text:s" -> ctx.raw(" ".repeat((c.attr("text:c")?.toIntOrNull() ?: 1).coerceIn(1, 200)), false)
                "text:tab" -> ctx.raw(" ", false)
                "text:line-break" -> ctx.raw("\n", false)
                "office:annotation" -> {}
                else -> inlineTextOnly(c, ctx)
            }
        }
    }

    private fun unescapeBasic(s: String) = s.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"").replace("&#39;", "'").replace("&amp;", "&")

    private fun sheet(t: XmlNode): GridSheet {
        val rows = ArrayList<List<GCell?>>()
        val rowNumbers = ArrayList<Int>()
        var maxCol = -1
        var rowNo = 0
        var cells = 0
        var truncated = false
        val hiddenCols = HashSet<Int>()
        var colIdx = 0
        // columns (hidden/collapsed)
        fun walkCols(n: XmlNode) {
            for (c in n.elements) when (c.name) {
                "table:table-column" -> {
                    val rep = (c.attr("table:number-columns-repeated")?.toIntOrNull() ?: 1).coerceAtMost(MAX_COLS)
                    if (c.attr("table:visibility") == "collapse") for (i in 0 until rep) if (colIdx + i < MAX_COLS) hiddenCols.add(colIdx + i)
                    colIdx += rep
                }
                "table:table-column-group", "table:table-header-columns", "table:table-columns" -> walkCols(c)
            }
        }
        walkCols(t)

        fun visitRow(row: XmlNode) {
            val rep = (row.attr("table:number-rows-repeated")?.toIntOrNull() ?: 1).coerceAtLeast(1)
            val hidden = row.attr("table:visibility").let { it == "collapse" || it == "filter" }
            val list = ArrayList<GCell?>()
            var col = 0
            var rowHasContent = false
            for (cell in row.elements) {
                if (cell.name != "table:table-cell" && cell.name != "table:covered-table-cell") continue
                val crep = (cell.attr("table:number-columns-repeated")?.toIntOrNull() ?: 1).coerceAtLeast(1)
                val covered = cell.name == "table:covered-table-cell"
                val text = if (covered) "" else cellDisplay(cell)
                val vt = cell.attr("office:value-type")
                val numeric = vt == "float" || vt == "percentage" || vt == "currency" || vt == "date" || vt == "time"
                val bg = styleProp(cell.attr("table:style-name")) { it.background }
                val bold = styleProp(cell.attr("table:style-name")) { it.bold } == true
                val italic = styleProp(cell.attr("table:style-name")) { it.italic } == true
                val color = styleProp(cell.attr("table:style-name")) { it.color }
                val colspan = cell.attr("table:number-columns-spanned")?.toIntOrNull() ?: 1
                val rowspan = cell.attr("table:number-rows-spanned")?.toIntOrNull() ?: 1
                val styled = bg != null || bold || italic || (color != null && color != "#000000")
                val isEmptyCell = text.isEmpty() && !styled && !covered
                val use = if (isEmptyCell) minOf(crep, 30) else minOf(crep, 100)
                if (isEmptyCell && col >= MAX_COLS) { col += crep; continue }
                for (k in 0 until use) {
                    if (col >= MAX_COLS) { truncated = true; break }
                    if (!isEmptyCell) {
                        var cls = ""
                        if (styled) {
                            cls = "o" + Integer.toHexString((bg + bold + italic + color).hashCode())
                            if (css.indexOf(".grid td.$cls{") < 0) {
                                css.append(".grid td.").append(cls).append('{')
                                if (bold) css.append("font-weight:700;")
                                if (italic) css.append("font-style:italic;")
                                if (color != null && color != "#000000") css.append("color:").append(color).append(';')
                                if (bg != null && bg != "#ffffff") css.append("background:").append(bg).append(';')
                                css.append('}')
                            }
                        }
                        while (list.size < col) list.add(null)
                        list.add(GCell(text, cls, colspan.coerceIn(1, MAX_COLS), rowspan.coerceIn(1, 10_000), covered, numeric && text.isNotEmpty()))
                        rowHasContent = true
                        if (col > maxCol) maxCol = col
                        if (++cells > MAX_CELLS) truncated = true
                    } else {
                        while (list.size <= col) list.add(null)
                    }
                    col++
                }
                if (use < crep) col += crep - use
                if (cells > MAX_CELLS) break
            }
            // trailing empty rows are dropped later; interior empty rows keep a bounded repeat
            val times = if (rowHasContent) minOf(rep, 50) else minOf(rep, 20)
            for (k in 0 until times) {
                if (rows.size >= MAX_ROWS) { truncated = true; return }
                if (!hidden) { rows.add(if (k == 0) list else ArrayList(list)); rowNumbers.add(rowNo + k + 1) }
            }
            rowNo += rep
        }

        fun walkRows(n: XmlNode) {
            for (c in n.elements) {
                if (truncated) return
                when (c.name) {
                    "table:table-row" -> visitRow(c)
                    "table:table-header-rows", "table:table-row-group", "table:table-rows" -> walkRows(c)
                }
            }
        }
        walkRows(t)

        // drop trailing rows that have no cells at all
        while (rows.isNotEmpty() && rows.last().all { it == null }) { rows.removeAt(rows.size - 1); rowNumbers.removeAt(rowNumbers.size - 1) }
        return GridSheet(t.attr("table:name") ?: "Sheet", rows, rowNumbers, maxCol + 1, truncated, hiddenCols)
    }

    private companion object {
        const val MAX_ROWS = 10_000
        const val MAX_COLS = 200
        const val MAX_CELLS = 300_000
        val LENGTH = Regex("(-?[0-9.]+)(cm|mm|in|pt|pc|px)")
    }
}
