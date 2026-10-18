package com.aeidolon.vaultexplorer.officeviewer

/**
 * `.docx` / `.docm` / `.dotx` -> HTML "reading view": headings, character
 * formatting, nested lists with their numbering, tables (spans, shading),
 * images, text boxes and footnotes. Page layout (margins, headers/footers,
 * columns) is deliberately not reproduced.
 */
internal class DocxConverter(private val pkg: OfficePackage, private val res: DocResources) {

    private class StyleInfo(val id: String, val name: String, val basedOn: String?) {
        var bold: Boolean? = null
        var italic: Boolean? = null
        var underline: Boolean? = null
        var strike: Boolean? = null
        var color: String? = null
        var outline: Int? = null
        var jc: String? = null
        var numId: String? = null
        var numLvl: Int = 0
    }

    private class LevelInfo(val numFmt: String, val start: Int)

    private data class Fmt(
        val b: Boolean = false, val i: Boolean = false, val u: Boolean = false, val s: Boolean = false,
        val script: Int = 0, val color: String? = null, val highlight: Boolean = false, val link: String? = null,
    )

    private class Seg(val fmt: Fmt, val html: StringBuilder, val mergeable: Boolean)

    private class ParaCtx {
        val segs = ArrayList<Seg>()
        val extra = StringBuilder()
        var pageBreak = false
        fun add(fmt: Fmt, html: String, mergeable: Boolean = true) {
            val last = segs.lastOrNull()
            if (last != null && last.mergeable && mergeable && last.fmt == fmt) last.html.append(html)
            else segs.add(Seg(fmt, StringBuilder(html), mergeable))
        }
        val isBlank: Boolean
            get() = extra.isEmpty() && segs.all { it.mergeable && it.html.isBlank() }
    }

    private val styles = HashMap<String, StyleInfo>()
    private val numToAbstract = HashMap<String, String>()
    private val abstractLevels = HashMap<String, HashMap<Int, LevelInfo>>()
    private val startOverride = HashMap<String, Int>()
    private val counters = HashMap<String, Int>()
    private var rels: Map<String, Relationship> = emptyMap()
    private val footnoteNodes = HashMap<String, XmlNode>()
    private val usedNotes = ArrayList<String>()
    private lateinit var mainPart: String

    var title: String? = null
        private set

    fun convert(): String {
        mainPart = mainPartName(pkg, "word/document.xml")
        val doc = try { pkg.tree(mainPart) } catch (e: XmlLimitException) {
            throw OfficeException(OfficeError.TOO_LARGE, e.message ?: "XML too large", e)
        } ?: throw OfficeException(OfficeError.UNSUPPORTED, "no main document part")
        rels = readRelationships(pkg, mainPart)
        title = documentTitle(pkg)
        val dir = mainPart.substringBeforeLast('/', "")
        fun sibling(n: String) = if (dir.isEmpty()) n else "$dir/$n"
        loadStyles(sibling("styles.xml"))
        loadNumbering(sibling("numbering.xml"))
        loadNotes(sibling("footnotes.xml"), "w:footnote")
        loadNotes(sibling("endnotes.xml"), "w:endnote")

        val body = doc.first("w:body") ?: throw OfficeException(OfficeError.UNSUPPORTED, "no w:body")
        val out = StringBuilder()
        out.append("<article class=\"paper\">")
        renderBlocks(body, out)
        renderNotes(out)
        out.append("</article>")
        return out.toString()
    }

    // ── styles / numbering / notes ────────────────────────────────────────

    private fun onOff(n: XmlNode?): Boolean? {
        if (n == null) return null
        val v = n.attr("w:val")?.lowercase()
        return !(v == "0" || v == "false" || v == "off")
    }

    private fun colorOf(rPr: XmlNode?): String? {
        val v = rPr?.first("w:color")?.attr("w:val") ?: return null
        return hexColor(v)
    }

    private fun underlineOf(rPr: XmlNode?): Boolean? {
        val n = rPr?.first("w:u") ?: return null
        return n.attr("w:val")?.lowercase() != "none"
    }

    private fun loadStyles(part: String) {
        val root = try { pkg.tree(part) } catch (e: XmlLimitException) { null } ?: return
        for (s in root.all("w:style")) {
            val id = s.attr("w:styleId") ?: continue
            val info = StyleInfo(id, s.first("w:name")?.attr("w:val") ?: id, s.first("w:basedOn")?.attr("w:val"))
            val rPr = s.first("w:rPr")
            val pPr = s.first("w:pPr")
            info.bold = onOff(rPr?.first("w:b"))
            info.italic = onOff(rPr?.first("w:i"))
            info.underline = underlineOf(rPr)
            info.strike = onOff(rPr?.first("w:strike"))
            info.color = colorOf(rPr)
            info.outline = pPr?.first("w:outlineLvl")?.attr("w:val")?.toIntOrNull()
            info.jc = pPr?.first("w:jc")?.attr("w:val")
            pPr?.first("w:numPr")?.let { np ->
                info.numId = np.first("w:numId")?.attr("w:val")
                info.numLvl = np.first("w:ilvl")?.attr("w:val")?.toIntOrNull() ?: 0
            }
            styles[id] = info
        }
    }

    private fun <T> styleProp(id: String?, sel: (StyleInfo) -> T?): T? {
        var cur = id
        var steps = 0
        while (cur != null && steps++ < 24) {
            val s = styles[cur] ?: return null
            sel(s)?.let { return it }
            cur = s.basedOn
        }
        return null
    }

    private fun loadNumbering(part: String) {
        val root = try { pkg.tree(part) } catch (e: XmlLimitException) { null } ?: return
        for (an in root.all("w:abstractNum")) {
            val id = an.attr("w:abstractNumId") ?: continue
            val levels = HashMap<Int, LevelInfo>()
            for (l in an.all("w:lvl")) {
                val ilvl = l.attr("w:ilvl")?.toIntOrNull() ?: continue
                levels[ilvl] = LevelInfo(
                    l.first("w:numFmt")?.attr("w:val") ?: "decimal",
                    l.first("w:start")?.attr("w:val")?.toIntOrNull() ?: 1,
                )
            }
            abstractLevels[id] = levels
        }
        for (n in root.all("w:num")) {
            val numId = n.attr("w:numId") ?: continue
            n.first("w:abstractNumId")?.attr("w:val")?.let { numToAbstract[numId] = it }
            for (o in n.all("w:lvlOverride")) {
                val il = o.attr("w:ilvl")?.toIntOrNull() ?: continue
                o.first("w:startOverride")?.attr("w:val")?.toIntOrNull()?.let { startOverride["$numId:$il"] = it }
            }
        }
    }

    private fun loadNotes(part: String, tag: String) {
        val root = try { pkg.tree(part) } catch (e: XmlLimitException) { null } ?: return
        for (f in root.all(tag)) {
            val id = f.attr("w:id") ?: continue
            val type = f.attr("w:type")
            if (type == "separator" || type == "continuationSeparator" || type == "continuationNotice") continue
            footnoteNodes[id] = f
        }
    }

    private fun renderNotes(out: StringBuilder) {
        if (usedNotes.isEmpty()) return
        out.append("<div class=\"fnotes\">")
        for ((idx, id) in usedNotes.withIndex()) {
            val node = footnoteNodes[id] ?: continue
            out.append("<p><sup class=\"fn\">").append(idx + 1).append("</sup> ")
            var first = true
            for (p in node.all("w:p")) {
                val ctx = ParaCtx()
                walkInline(p, Fmt(), ctx)
                val inline = renderInline(ctx)
                if (inline.isBlank()) continue
                if (!first) out.append(' ')
                out.append(inline)
                first = false
            }
            out.append("</p>")
        }
        out.append("</div>")
    }

    // ── block level ───────────────────────────────────────────────────────

    private fun renderBlocks(container: XmlNode, out: StringBuilder) {
        val lists = ListBuilder(out)
        renderBlockList(container, out, lists)
        lists.closeAll()
    }

    private fun blocksToString(container: XmlNode): String {
        val sb = StringBuilder()
        renderBlocks(container, sb)
        return sb.toString()
    }

    private fun renderBlockList(container: XmlNode, out: StringBuilder, lists: ListBuilder) {
        for (c in container.elements) {
            when (c.name) {
                "w:p" -> renderParagraph(c, out, lists)
                "w:tbl" -> { lists.closeAll(); renderTable(c, out) }
                "w:sdt" -> c.first("w:sdtContent")?.let { renderBlockList(it, out, lists) }
                "w:sdtContent", "w:customXml", "w:ins" -> renderBlockList(c, out, lists)
            }
        }
    }

    private fun paragraphStyleId(pPr: XmlNode?): String? = pPr?.first("w:pStyle")?.attr("w:val")

    /** 1..6 for headings, 0 for "Title", -1 for "Subtitle", null for body text. */
    private fun headingKind(styleId: String?, pPr: XmlNode?): Int? {
        var cur = styleId
        var steps = 0
        while (cur != null && steps++ < 24) {
            val s = styles[cur]
            val nm = (s?.name ?: cur).lowercase().trim()
            val m = HEADING.matchEntire(nm)
            if (m != null) return m.groupValues[1].toInt().coerceAtMost(6)
            if (nm == "title") return 0
            if (nm == "subtitle") return -1
            cur = s?.basedOn
        }
        val ol = pPr?.first("w:outlineLvl")?.attr("w:val")?.toIntOrNull()
            ?: styleProp(styleId) { it.outline }
        if (ol != null && ol in 0..8) return (ol + 1).coerceAtMost(6)
        return null
    }

    private fun renderParagraph(p: XmlNode, out: StringBuilder, lists: ListBuilder) {
        val pPr = p.first("w:pPr")
        val styleId = paragraphStyleId(pPr)
        val kind = headingKind(styleId, pPr)

        var base = Fmt()
        if (kind == null) {
            base = base.copy(
                b = styleProp(styleId) { it.bold } ?: false,
                i = styleProp(styleId) { it.italic } ?: false,
                u = styleProp(styleId) { it.underline } ?: false,
                s = styleProp(styleId) { it.strike } ?: false,
                color = styleProp(styleId) { it.color },
            )
        }
        val ctx = ParaCtx()
        walkInline(p, base, ctx)
        val inline = renderInline(ctx)

        if (pPr?.first("w:pageBreakBefore") != null && onOff(pPr.first("w:pageBreakBefore")) == true) {
            lists.closeAll(); out.append("<hr class=\"pb\">")
        }

        // numbering: direct numPr wins over the style's numPr
        var numId = pPr?.first("w:numPr")?.first("w:numId")?.attr("w:val")
        var ilvl = pPr?.first("w:numPr")?.first("w:ilvl")?.attr("w:val")?.toIntOrNull()
        if (numId == null && pPr?.first("w:numPr") == null) {
            numId = styleProp(styleId) { it.numId }
            ilvl = styleProp(styleId) { s -> if (s.numId != null) s.numLvl else null }
        }
        val isList = kind == null && numId != null && numId != "0" && !ctx.isBlank

        val bidi = onOff(pPr?.first("w:bidi")) == true
        val jc = pPr?.first("w:jc")?.attr("w:val") ?: styleProp(styleId) { it.jc }
        val align = when (jc) {
            "center" -> "center"
            "both", "distribute" -> "justify"
            "right", "end" -> if (bidi) null else "right"
            else -> null
        }
        val attrs = buildString {
            if (bidi) append(" dir=\"rtl\"")
            if (align != null) append(" style=\"text-align:").append(align).append('"')
        }

        if (isList) {
            val lvl = (ilvl ?: 0).coerceIn(0, 8)
            val abstractId = numToAbstract[numId!!]
            val info = abstractLevels[abstractId]?.get(lvl)
            val fmt = info?.numFmt ?: "bullet"
            val ordered = fmt != "bullet" && fmt != "none"
            val key = "$numId:$lvl"
            // a shallower item restarts the counters of every deeper level of this list
            counters.keys.filter { k ->
                k.startsWith("$numId:") && (k.substringAfter(':').toIntOrNull() ?: -1) > lvl
            }.forEach { counters.remove(it) }
            val first = !counters.containsKey(key)
            val startVal = startOverride[key] ?: info?.start ?: 1
            val n = if (first) startVal else counters[key]!! + 1
            counters[key] = n
            val css = when (fmt) {
                "decimal" -> null
                "lowerLetter" -> "lower-alpha"
                "upperLetter" -> "upper-alpha"
                "lowerRoman" -> "lower-roman"
                "upperRoman" -> "upper-roman"
                "decimalZero" -> "decimal-leading-zero"
                "none" -> "none"
                else -> null
            }
            lists.item(lvl, numId, ordered, css, n, inline + ctx.extra)
        } else {
            lists.closeAll()
            when {
                ctx.isBlank -> {
                    val spacer = "<p class=\"sp\"></p>"
                    if (!ctx.pageBreak && !out.endsWith(spacer) && out.length > "<article class=\"paper\">".length) out.append(spacer)
                }
                kind == null -> out.append("<p").append(attrs).append('>').append(inline).append("</p>").append(ctx.extra)
                kind == -1 -> out.append("<p class=\"subtitle\"").append(attrs).append('>').append(inline).append("</p>").append(ctx.extra)
                kind == 0 -> out.append("<h1 class=\"title\"").append(attrs).append('>').append(inline).append("</h1>").append(ctx.extra)
                else -> out.append("<h").append(kind).append(attrs).append('>').append(inline)
                    .append("</h").append(kind).append('>').append(ctx.extra)
            }
        }
        if (ctx.pageBreak) { lists.closeAll(); out.append("<hr class=\"pb\">") }
    }

    // ── inline level ──────────────────────────────────────────────────────

    private fun walkInline(node: XmlNode, base: Fmt, ctx: ParaCtx) {
        for (c in node.elements) {
            when (c.name) {
                "w:r" -> processRun(c, base, ctx)
                "w:hyperlink" -> {
                    val rid = c.attr("r:id")
                    val link = if (rid != null) rels[rid]?.target ?: "" else c.attr("w:anchor")?.let { "#$it" } ?: ""
                    walkInline(c, base.copy(link = link), ctx)
                }
                "w:ins", "w:smartTag", "w:fldSimple", "w:sdtContent", "w:customXml", "w:dir", "w:bdo", "w:moveTo" ->
                    walkInline(c, base, ctx)
                "w:sdt" -> c.first("w:sdtContent")?.let { walkInline(it, base, ctx) }
                "mc:AlternateContent" -> (c.first("mc:Choice") ?: c.first("mc:Fallback"))?.let { walkInline(it, base, ctx) }
                "w:drawing" -> drawing(c, ctx)
                "w:pict", "w:object" -> pict(c, ctx)
            }
        }
    }

    private fun processRun(r: XmlNode, base: Fmt, ctx: ParaCtx) {
        var f = base
        val rPr = r.first("w:rPr")
        if (rPr != null) {
            if (onOff(rPr.first("w:vanish")) == true) return
            rPr.first("w:rStyle")?.attr("w:val")?.let { cid ->
                f = f.copy(
                    b = styleProp(cid) { it.bold } ?: f.b,
                    i = styleProp(cid) { it.italic } ?: f.i,
                    u = styleProp(cid) { it.underline } ?: f.u,
                    s = styleProp(cid) { it.strike } ?: f.s,
                    color = styleProp(cid) { it.color } ?: f.color,
                )
            }
            onOff(rPr.first("w:b"))?.let { f = f.copy(b = it) }
            onOff(rPr.first("w:i"))?.let { f = f.copy(i = it) }
            underlineOf(rPr)?.let { f = f.copy(u = it) }
            onOff(rPr.first("w:strike"))?.let { f = f.copy(s = it) }
            colorOf(rPr)?.let { f = f.copy(color = it) }
            when (rPr.first("w:vertAlign")?.attr("w:val")) {
                "superscript" -> f = f.copy(script = 1)
                "subscript" -> f = f.copy(script = 2)
            }
            val hl = rPr.first("w:highlight")?.attr("w:val")
            if (hl != null && hl != "none") f = f.copy(highlight = true)
        }
        for (c in r.elements) {
            when (c.name) {
                "w:t" -> ctx.add(f, esc(c.textContent()))
                "w:tab", "w:ptab" -> ctx.add(f, "&emsp;")
                "w:br", "w:cr" -> if (c.attr("w:type") == "page") ctx.pageBreak = true else ctx.add(f, "<br>", mergeable = false)
                "w:noBreakHyphen" -> ctx.add(f, "\u2011")
                "w:softHyphen" -> ctx.add(f, "\u00ad")
                "w:drawing" -> drawing(c, ctx)
                "w:pict", "w:object" -> pict(c, ctx)
                "mc:AlternateContent" -> (c.first("mc:Choice") ?: c.first("mc:Fallback"))?.let { walkInline(it, f, ctx) }
                "w:footnoteReference", "w:endnoteReference" -> {
                    val id = c.attr("w:id")
                    if (id != null && footnoteNodes.containsKey(id)) {
                        usedNotes.add(id)
                        ctx.add(Fmt(), "<sup class=\"fn\">${usedNotes.size}</sup>", mergeable = false)
                    }
                }
            }
        }
    }

    private fun renderInline(ctx: ParaCtx): String {
        val sb = StringBuilder()
        for (s in ctx.segs) {
            var h = s.html.toString()
            if (!s.mergeable) { sb.append(h); continue }
            val f = s.fmt
            if (h.isEmpty()) continue
            if (f.b) h = "<strong>$h</strong>"
            if (f.i) h = "<em>$h</em>"
            if (f.u) h = "<u>$h</u>"
            if (f.s) h = "<s>$h</s>"
            if (f.script == 1) h = "<sup>$h</sup>" else if (f.script == 2) h = "<sub>$h</sub>"
            if (f.highlight) h = "<mark>$h</mark>"
            if (f.color != null && f.color != "#000000") h = "<span style=\"color:${f.color}\">$h</span>"
            if (f.link != null) {
                h = if (f.link.isEmpty()) "<span class=\"lnk\">$h</span>"
                else "<span class=\"lnk\" title=\"${esc(f.link)}\">$h</span>"
            }
            sb.append(h)
        }
        return sb.toString()
    }

    private fun placeholder(glyph: String) = "<span class=\"ph\">$glyph</span>"

    private fun collectBlips(n: XmlNode, out: MutableList<XmlNode>) {
        for (c in n.elements) {
            if (c.name == "w:txbxContent") continue
            if (c.name == "a:blip") out.add(c) else collectBlips(c, out)
        }
    }

    private fun imageHtml(partName: String, widthPx: Int?, alt: String?): String {
        val mime = imageMime(partName)
        val bytes = pkg.bytes(partName)
        val url = if (mime != null && bytes != null) res.add(partName, mime, bytes) else null
        if (url == null) return placeholder("\u25A2")
        val sb = StringBuilder("<img src=\"").append(url).append("\" alt=\"").append(esc(alt ?: "")).append('"')
        if (widthPx != null && widthPx in 1..4000) sb.append(" style=\"width:").append(widthPx).append("px;max-width:100%\"")
        return sb.append('>').toString()
    }

    private fun drawing(d: XmlNode, ctx: ParaCtx) {
        val ext = d.find("wp:extent")
        val widthPx = ext?.attr("cx")?.toLongOrNull()?.let { (it / 9525L).toInt() }
        val alt = d.find("wp:docPr")?.attr("descr")
        val blips = ArrayList<XmlNode>()
        collectBlips(d, blips)
        for (b in blips) {
            val rid = b.attr("r:embed")
            val target = rid?.let { rels[it] }
            if (target == null || target.external) { ctx.add(Fmt(), placeholder("\u25A2"), mergeable = false); continue }
            ctx.add(Fmt(), imageHtml(target.target, widthPx, alt), mergeable = false)
        }
        for (tb in d.findAll("w:txbxContent", stopAt = "w:txbxContent")) {
            ctx.extra.append("<div class=\"textbox\">").append(blocksToString(tb)).append("</div>")
        }
        if (blips.isEmpty() && d.find("w:txbxContent") == null &&
            d.find("a:graphicData")?.attr("uri")?.endsWith("/chart") == true
        ) ctx.add(Fmt(), placeholder("\uD83D\uDCCA"), mergeable = false)
    }

    private fun pict(p: XmlNode, ctx: ParaCtx) {
        for (im in p.findAll("v:imagedata")) {
            val rid = im.attr("r:id") ?: continue
            val target = rels[rid]
            if (target == null || target.external) continue
            ctx.add(Fmt(), imageHtml(target.target, null, null), mergeable = false)
        }
        for (tb in p.findAll("w:txbxContent", stopAt = "w:txbxContent")) {
            ctx.extra.append("<div class=\"textbox\">").append(blocksToString(tb)).append("</div>")
        }
    }

    // ── tables ────────────────────────────────────────────────────────────

    private class TCell(val node: XmlNode, val col: Int, val span: Int, val vmerge: String?)

    private fun renderTable(tbl: XmlNode, out: StringBuilder) {
        val rows = ArrayList<List<TCell>>()
        val rowNodes = tbl.all("w:tr")
        for (tr in rowNodes) {
            var col = 0
            val cells = ArrayList<TCell>()
            for (tc in tr.all("w:tc")) {
                val tcPr = tc.first("w:tcPr")
                val span = (tcPr?.first("w:gridSpan")?.attr("w:val")?.toIntOrNull() ?: 1).coerceIn(1, 200)
                val vm = tcPr?.first("w:vMerge")
                val vmerge = if (vm == null) null else if (vm.attr("w:val") == "restart") "restart" else "cont"
                cells.add(TCell(tc, col, span, vmerge))
                col += span
            }
            rows.add(cells)
        }
        val skip = HashSet<Long>()
        fun key(r: Int, c: Int) = r.toLong() * 100_000L + c
        val noBorders = tbl.first("w:tblPr")?.first("w:tblBorders")?.let { b ->
            val sides = listOf("w:top", "w:left", "w:bottom", "w:right", "w:insideH", "w:insideV", "w:start", "w:end")
            val present = sides.mapNotNull { b.first(it) }
            present.isNotEmpty() && present.all { it.attr("w:val") == "nil" || it.attr("w:val") == "none" }
        } ?: false

        out.append("<div class=\"scroll\"><table")
        if (noBorders) out.append(" class=\"nb\"")
        out.append('>')
        for ((ri, cells) in rows.withIndex()) {
            val isHeader = rowNodes[ri].first("w:trPr")?.first("w:tblHeader") != null
            out.append("<tr>")
            for (cell in cells) {
                if (key(ri, cell.col) in skip) continue
                var rowspan = 1
                if (cell.vmerge == "restart") {
                    var r2 = ri + 1
                    while (r2 < rows.size) {
                        val below = rows[r2].firstOrNull { it.col == cell.col && it.vmerge == "cont" } ?: break
                        skip.add(key(r2, below.col))
                        rowspan++
                        r2++
                    }
                } else if (cell.vmerge == "cont") {
                    continue // continuation without a matching restart: nothing to draw
                }
                val tag = if (isHeader) "th" else "td"
                out.append('<').append(tag)
                if (cell.span > 1) out.append(" colspan=\"").append(cell.span).append('"')
                if (rowspan > 1) out.append(" rowspan=\"").append(rowspan).append('"')
                val fill = hexColor(cell.node.first("w:tcPr")?.first("w:shd")?.attr("w:fill"))
                if (fill != null) out.append(" style=\"background:").append(fill).append('"')
                out.append('>')
                renderBlocks(cell.node, out)
                out.append("</").append(tag).append('>')
            }
            out.append("</tr>")
        }
        out.append("</table></div>")
    }

    private companion object {
        val HEADING = Regex("heading\\s*([1-9])")
    }
}
