package com.aeidolon.vaultexplorer.officeviewer

/**
 * `.pptx` / `.pptm` / `.ppsx` -> one card per slide in reading order: title,
 * text (with bullet nesting), pictures, tables and speaker notes. Slide
 * geometry, backgrounds and animations are not reproduced.
 */
internal class PptxConverter(
    private val pkg: OfficePackage,
    private val res: DocResources,
    private val opts: ViewOptions,
) {
    var title: String? = null
        private set

    private class SlideCtx(val rels: Map<String, Relationship>, val body: StringBuilder) {
        val titles = ArrayList<String>()
    }

    fun convert(): String {
        val main = mainPartName(pkg, "ppt/presentation.xml")
        val pres = try { pkg.tree(main) } catch (e: XmlLimitException) {
            throw OfficeException(OfficeError.TOO_LARGE, e.message ?: "XML too large", e)
        } ?: throw OfficeException(OfficeError.UNSUPPORTED, "no presentation part")
        val rels = readRelationships(pkg, main)
        val slideParts = ArrayList<String>()
        pres.find("p:sldIdLst")?.all("p:sldId")?.forEach { id ->
            rels[id.attr("r:id")]?.takeIf { !it.external && pkg.has(it.target) }?.let { slideParts.add(it.target) }
        }
        if (slideParts.isEmpty()) {
            val re = Regex("ppt/slides/slide(\\d+)\\.xml")
            pkg.names.mapNotNull { n -> re.matchEntire(n)?.let { n to it.groupValues[1].toInt() } }
                .sortedBy { it.second }.forEach { slideParts.add(it.first) }
        }
        if (slideParts.isEmpty()) throw OfficeException(OfficeError.UNSUPPORTED, "no slides")

        title = documentTitle(pkg)
        val out = StringBuilder()
        for ((i, part) in slideParts.take(MAX_SLIDES).withIndex()) renderSlide(i + 1, part, out)
        return out.toString()
    }

    private fun renderSlide(index: Int, part: String, out: StringBuilder) {
        val root = try { pkg.tree(part) } catch (e: XmlLimitException) { null }
        val hidden = root?.attr("show") == "0"
        out.append("<section class=\"paper slide").append(if (hidden) " hidden" else "").append("\">")
        out.append("<div class=\"num\">").append(index).append("</div>")
        if (root == null) { out.append("</section>"); return }
        val ctx = SlideCtx(readRelationships(pkg, part), StringBuilder())
        root.first("p:cSld")?.first("p:spTree")?.let { walkShapes(it, ctx) }
        if (ctx.titles.isNotEmpty()) {
            out.append("<h2 class=\"st\">").append(ctx.titles.joinToString("<br>")).append("</h2>")
            if (title == null && index == 1) title = null
        }
        out.append(ctx.body)
        notesHtml(ctx.rels)?.let { out.append(it) }
        out.append("</section>")
    }

    private fun notesHtml(slideRels: Map<String, Relationship>): String? {
        val rel = slideRels.values.firstOrNull { it.type.endsWith("/notesSlide") && !it.external } ?: return null
        val notes = try { pkg.tree(rel.target) } catch (e: XmlLimitException) { null } ?: return null
        val nRels = readRelationships(pkg, rel.target)
        val sb = StringBuilder()
        val tree = notes.first("p:cSld")?.first("p:spTree") ?: return null
        for (sp in tree.findAll("p:sp")) {
            val type = sp.first("p:nvSpPr")?.first("p:nvPr")?.first("p:ph")?.attr("type")
            if (type != "body") continue
            val tx = sp.first("p:txBody") ?: continue
            renderParas(tx.all("a:p"), false, sb, nRels)
        }
        if (sb.isEmpty()) return null
        return "<details class=\"notes\"><summary>${esc(opts.notesLabel)}</summary>$sb</details>"
    }

    private fun walkShapes(tree: XmlNode, ctx: SlideCtx) {
        for (c in tree.elements) {
            when (c.name) {
                "p:sp" -> shape(c, ctx)
                "p:pic" -> picture(c, ctx)
                "p:graphicFrame" -> graphicFrame(c, ctx)
                "p:grpSp" -> walkShapes(c, ctx)
                "mc:AlternateContent" -> (c.first("mc:Choice") ?: c.first("mc:Fallback"))?.let { walkShapes(it, ctx) }
            }
        }
    }

    private fun shape(sp: XmlNode, ctx: SlideCtx) {
        val ph = sp.first("p:nvSpPr")?.first("p:nvPr")?.first("p:ph")
        val type = ph?.attr("type")
        if (type == "sldNum" || type == "dt" || type == "ftr" || type == "hdr") return
        val tx = sp.first("p:txBody") ?: return
        val paras = tx.all("a:p")
        when (type) {
            "title", "ctrTitle" -> for (p in paras) {
                val h = inline(p, ctx.rels)
                if (h.isNotBlank()) ctx.titles.add(h)
            }
            "subTitle" -> for (p in paras) {
                val h = inline(p, ctx.rels)
                if (h.isNotBlank()) ctx.body.append("<p class=\"subtitle\">").append(h).append("</p>")
            }
            else -> renderParas(paras, ph != null && (type == null || type == "body" || type == "obj"), ctx.body, ctx.rels)
        }
    }

    private fun picture(pic: XmlNode, ctx: SlideCtx) {
        val blip = pic.find("a:blip") ?: return
        val alt = pic.first("p:nvPicPr")?.first("p:cNvPr")?.attr("descr")
        ctx.body.append("<p>").append(image(blip, ctx.rels, alt)).append("</p>")
    }

    private fun image(blip: XmlNode, rels: Map<String, Relationship>, alt: String?): String {
        val rel = blip.attr("r:embed")?.let { rels[it] }
        if (rel == null || rel.external) return "<span class=\"ph\">\u25A2</span>"
        val mime = imageMime(rel.target)
        val bytes = pkg.bytes(rel.target)
        val url = if (mime != null && bytes != null) res.add(rel.target, mime, bytes) else null
        if (url == null) return "<span class=\"ph\">\u25A2</span>"
        return "<img src=\"$url\" alt=\"${esc(alt ?: "")}\">"
    }

    private fun graphicFrame(gf: XmlNode, ctx: SlideCtx) {
        val data = gf.find("a:graphicData")
        val tbl = data?.first("a:tbl")
        if (tbl != null) { table(tbl, ctx); return }
        val uri = data?.attr("uri") ?: ""
        ctx.body.append("<p><span class=\"ph\">")
            .append(if (uri.endsWith("/chart")) "\uD83D\uDCCA" else "\u25A2").append("</span></p>")
    }

    private fun table(tbl: XmlNode, ctx: SlideCtx) {
        val out = ctx.body
        out.append("<div class=\"scroll\"><table>")
        for (tr in tbl.all("a:tr")) {
            out.append("<tr>")
            for (tc in tr.all("a:tc")) {
                if (tc.attr("hMerge") == "1" || tc.attr("vMerge") == "1") continue
                out.append("<td")
                tc.attr("gridSpan")?.toIntOrNull()?.takeIf { it > 1 }?.let { out.append(" colspan=\"").append(it).append('"') }
                tc.attr("rowSpan")?.toIntOrNull()?.takeIf { it > 1 }?.let { out.append(" rowspan=\"").append(it).append('"') }
                val fill = hexColor(tc.first("a:tcPr")?.first("a:solidFill")?.first("a:srgbClr")?.attr("val"))
                if (fill != null) out.append(" style=\"background:").append(fill).append('"')
                out.append('>')
                tc.first("a:txBody")?.let { renderParas(it.all("a:p"), false, out, ctx.rels) }
                out.append("</td>")
            }
            out.append("</tr>")
        }
        out.append("</table></div>")
    }

    private fun renderParas(paras: List<XmlNode>, bulletDefault: Boolean, out: StringBuilder, rels: Map<String, Relationship>) {
        val lists = ListBuilder(out)
        for (p in paras) {
            val html = inline(p, rels)
            if (html.isBlank()) continue
            val pPr = p.first("a:pPr")
            val lvl = pPr?.attr("lvl")?.toIntOrNull() ?: 0
            val auto = pPr?.first("a:buAutoNum")
            val bullet = pPr?.first("a:buNone") == null && (pPr?.first("a:buChar") != null || auto != null || bulletDefault)
            if (bullet) {
                val css = when (auto?.attr("type")?.substringBefore("Paren")?.substringBefore("Period")?.substringBefore("Plain")) {
                    "alphaLc" -> "lower-alpha"
                    "alphaUc" -> "upper-alpha"
                    "romanLc" -> "lower-roman"
                    "romanUc" -> "upper-roman"
                    else -> null
                }
                lists.item(lvl, if (auto != null) "o" else "u", auto != null, css, auto?.attr("startAt")?.toIntOrNull() ?: 1, html)
            } else {
                lists.closeAll()
                val attrs = buildString {
                    if (pPr?.attr("rtl") == "1") append(" dir=\"rtl\"")
                    when (pPr?.attr("algn")) {
                        "ctr" -> append(" style=\"text-align:center\"")
                        "r" -> if (pPr.attr("rtl") != "1") append(" style=\"text-align:right\"")
                        "just" -> append(" style=\"text-align:justify\"")
                    }
                }
                out.append("<p").append(attrs).append('>').append(html).append("</p>")
            }
        }
        lists.closeAll()
    }

    private fun inline(p: XmlNode, rels: Map<String, Relationship>): String {
        val sb = StringBuilder()
        for (c in p.elements) {
            when (c.name) {
                "a:r", "a:fld" -> {
                    val t = c.first("a:t")?.textContent() ?: continue
                    val rPr = c.first("a:rPr")
                    val link = rPr?.first("a:hlinkClick")?.let { h -> h.attr("r:id")?.let { rels[it]?.target } ?: "" }
                    val baseline = rPr?.attr("baseline")?.toIntOrNull() ?: 0
                    sb.append(
                        wrapInline(
                            esc(t),
                            bold = rPr?.attr("b") == "1",
                            italic = rPr?.attr("i") == "1",
                            underline = rPr?.attr("u").let { it != null && it != "none" },
                            strike = rPr?.attr("strike").let { it != null && it != "noStrike" },
                            script = if (baseline > 0) 1 else if (baseline < 0) 2 else 0,
                            color = hexColor(rPr?.first("a:solidFill")?.first("a:srgbClr")?.attr("val")),
                            link = link,
                        ),
                    )
                }
                "a:br" -> sb.append("<br>")
            }
        }
        return sb.toString()
    }

    private companion object {
        const val MAX_SLIDES = 1000
    }
}
