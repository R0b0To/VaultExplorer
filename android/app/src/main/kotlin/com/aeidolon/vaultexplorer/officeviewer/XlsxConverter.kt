package com.aeidolon.vaultexplorer.officeviewer

/**
 * `.xlsx` / `.xlsm` / `.xltx` -> one table per visible sheet. Shows cached
 * values (formulas are never evaluated), number and date formats, merged
 * cells, bold/italic/colour/fill and alignment. Charts, images, conditional
 * formatting and column widths are not reproduced. Sheets are streamed and
 * capped at [MAX_ROWS] x [MAX_COLS] cells so a huge workbook stays usable.
 */
internal class XlsxConverter(private val pkg: OfficePackage) {
    var title: String? = null
        private set
    val css = StringBuilder()

    private class Xf(
        val code: String, val isDate: Boolean, val bold: Boolean, val italic: Boolean,
        val color: String?, val fill: String?, val halign: String?, val wrap: Boolean,
    )

    private var date1904 = false
    private val sst = ArrayList<String>()
    private val xfs = ArrayList<Xf>()
    private val xfClass = HashMap<Int, String>()

    fun convert(): String {
        val main = mainPartName(pkg, "xl/workbook.xml")
        val wb = try { pkg.tree(main) } catch (e: XmlLimitException) {
            throw OfficeException(OfficeError.TOO_LARGE, e.message ?: "XML too large", e)
        } ?: throw OfficeException(OfficeError.UNSUPPORTED, "no workbook part")
        val rels = readRelationships(pkg, main)
        date1904 = wb.find("workbookPr")?.attr("date1904").let { it == "1" || it == "true" }
        title = documentTitle(pkg)

        val dir = main.substringBeforeLast('/', "")
        fun sibling(n: String) = if (dir.isEmpty()) n else "$dir/$n"
        val sstPart = rels.values.firstOrNull { it.type.endsWith("/sharedStrings") }?.target ?: sibling("sharedStrings.xml")
        loadSharedStrings(sstPart)
        val stylesPart = rels.values.firstOrNull { it.type.endsWith("/styles") }?.target ?: sibling("styles.xml")
        loadStyles(stylesPart)

        class SheetRef(val name: String, val part: String, val hidden: Boolean)
        val refs = ArrayList<SheetRef>()
        wb.find("sheets")?.all("sheet")?.forEach { s ->
            val rel = rels[s.attr("r:id")] ?: return@forEach
            if (rel.external || !pkg.has(rel.target)) return@forEach
            if (rel.type.endsWith("/chartsheet")) return@forEach
            val state = s.attr("state")
            refs.add(SheetRef(s.attr("name") ?: "Sheet", rel.target, state == "hidden" || state == "veryHidden"))
        }
        if (refs.isEmpty()) throw OfficeException(OfficeError.UNSUPPORTED, "no worksheets")
        val visible = refs.filter { !it.hidden }.ifEmpty { refs }

        val sheets = visible.take(MAX_SHEETS).map { parseSheet(it.name, it.part) }
        val out = StringBuilder()
        SheetGrid.render(sheets, out, css)
        return out.toString()
    }

    // ── shared strings & styles ───────────────────────────────────────────

    private fun loadSharedStrings(part: String) {
        val bytes = pkg.bytes(part) ?: return
        val p = XmlPull.reader(bytes)
        var cur: StringBuilder? = null
        var inPh = false
        var capture = false
        while (true) {
            when (p.next()) {
                XmlPull.Event.START -> when (p.name) {
                    "si" -> cur = StringBuilder()
                    "rPh" -> inPh = true
                    "t" -> capture = cur != null && !inPh
                }
                XmlPull.Event.TEXT -> if (capture) cur?.append(p.text)
                XmlPull.Event.END -> when (p.name) {
                    "t" -> capture = false
                    "rPh" -> inPh = false
                    "si" -> { sst.add(cur?.toString() ?: ""); cur = null }
                }
                XmlPull.Event.EOF -> return
            }
        }
    }

    private fun argb(n: XmlNode?): String? = hexColor(n?.attr("rgb")?.let { if (it.length == 8) it.substring(2) else it })

    private fun loadStyles(part: String) {
        val root = try { pkg.tree(part) } catch (e: XmlLimitException) { null }
        if (root == null) { xfs.add(Xf("General", false, false, false, null, null, null, false)); return }
        val custom = HashMap<Int, String>()
        root.first("numFmts")?.all("numFmt")?.forEach { n ->
            val id = n.attr("numFmtId")?.toIntOrNull() ?: return@forEach
            custom[id] = n.attr("formatCode") ?: "General"
        }
        class Font(val b: Boolean, val i: Boolean, val color: String?)
        val fonts = root.first("fonts")?.all("font")?.map { f ->
            fun on(n: XmlNode?) = n != null && n.attr("val") != "0" && n.attr("val") != "false"
            Font(on(f.first("b")), on(f.first("i")), argb(f.first("color")))
        } ?: emptyList()
        val fills = root.first("fills")?.all("fill")?.map { f ->
            val pf = f.first("patternFill")
            if (pf != null && pf.attr("patternType") == "solid") argb(pf.first("fgColor")) else null
        } ?: emptyList()
        val cellXfs = root.first("cellXfs")?.all("xf") ?: emptyList()
        for (x in cellXfs) {
            val id = x.attr("numFmtId")?.toIntOrNull() ?: 0
            val code = custom[id] ?: XlFormat.BUILTIN[id] ?: "General"
            val font = fonts.getOrNull(x.attr("fontId")?.toIntOrNull() ?: -1)
            val fill = fills.getOrNull(x.attr("fillId")?.toIntOrNull() ?: -1)
            val al = x.first("alignment")
            xfs.add(
                Xf(
                    code, XlFormat.isDateFormat(code), font?.b == true, font?.i == true,
                    font?.color, fill, al?.attr("horizontal"),
                    al?.attr("wrapText").let { it == "1" || it == "true" },
                ),
            )
        }
        if (xfs.isEmpty()) xfs.add(Xf("General", false, false, false, null, null, null, false))
    }

    /** CSS class for a cell style, or "" when it has no visual rules. Rules go to [css]. */
    private fun classFor(xfIndex: Int): String {
        xfClass[xfIndex]?.let { return it }
        val xf = xfs.getOrNull(xfIndex)
        val rules = StringBuilder()
        if (xf != null) {
            if (xf.bold) rules.append("font-weight:700;")
            if (xf.italic) rules.append("font-style:italic;")
            if (xf.color != null && xf.color != "#000000") rules.append("color:").append(xf.color).append(';')
            if (xf.fill != null && xf.fill != "#ffffff") rules.append("background:").append(xf.fill).append(';')
            when (xf.halign) {
                "left" -> rules.append("text-align:left;")
                "center", "centerContinuous" -> rules.append("text-align:center;")
                "right" -> rules.append("text-align:right;")
            }
        }
        val cls = StringBuilder()
        if (rules.isNotEmpty()) {
            cls.append('x').append(xfIndex)
            css.append(".grid td.x").append(xfIndex).append('{').append(rules).append('}')
        }
        if (xf?.wrap == true) { if (cls.isNotEmpty()) cls.append(' '); cls.append('w') }
        return cls.toString().also { xfClass[xfIndex] = it }
    }

    // ── sheet parsing ─────────────────────────────────────────────────────

    private fun parseRef(ref: String): Pair<Int, Int>? {
        var i = 0
        var col = 0
        while (i < ref.length && ref[i].isLetter()) { col = col * 26 + (ref[i].uppercaseChar() - 'A' + 1); i++ }
        if (i == 0 || i == ref.length) return null
        val row = ref.substring(i).toIntOrNull() ?: return null
        return (row - 1) to (col - 1)
    }

    private fun parseSheet(name: String, part: String): GridSheet {
        val rows = ArrayList<ArrayList<GCell?>>()
        val rowNumbers = ArrayList<Int>()
        val rowIndex = HashMap<Int, Int>()
        val merges = ArrayList<IntArray>()
        val hiddenCols = HashSet<Int>()
        var maxCol = -1
        var truncated = false
        var cells = 0

        val p = XmlPull.reader(pkg.bytes(part) ?: ByteArray(0))
        var curRow: ArrayList<GCell?>? = null
        var skipRow = false
        var nextRowNo = 0
        var nextCol = 0
        // current cell
        var inCell = false
        var cType: String? = null
        var cStyle = 0
        var cCol = 0
        var cValue: StringBuilder? = null
        var cInline: StringBuilder? = null
        var inInline = false
        var inPh = false
        var captureV = false
        var captureT = false
        var stop = false

        loop@ while (!stop) {
            when (p.next()) {
                XmlPull.Event.START -> when (p.name) {
                    "col" -> if (p.attrs["hidden"].let { it == "1" || it == "true" }) {
                        val mn = p.attrs["min"]?.toIntOrNull() ?: 0
                        val mx = (p.attrs["max"]?.toIntOrNull() ?: mn).coerceAtMost(MAX_COLS)
                        for (c in mn..mx) if (c >= 1) hiddenCols.add(c - 1)
                    }
                    "row" -> {
                        val r = (p.attrs["r"]?.toIntOrNull()?.minus(1)) ?: nextRowNo
                        nextRowNo = r + 1
                        nextCol = 0
                        if (rows.size >= MAX_ROWS || r >= 1_048_576) { truncated = true; stop = true; continue@loop }
                        skipRow = p.attrs["hidden"].let { it == "1" || it == "true" }
                        if (!skipRow) {
                            curRow = ArrayList()
                            rows.add(curRow)
                            rowNumbers.add(r + 1)
                            rowIndex[r] = rows.size - 1
                        } else curRow = null
                    }
                    "c" -> if (curRow != null) {
                        inCell = true
                        cType = p.attrs["t"]
                        cStyle = p.attrs["s"]?.toIntOrNull() ?: 0
                        val ref = p.attrs["r"]?.let { parseRef(it) }
                        cCol = ref?.second ?: nextCol
                        nextCol = cCol + 1
                        cValue = null
                        cInline = null
                    } else { inCell = false }
                    "v" -> if (inCell) { cValue = StringBuilder(); captureV = true }
                    "is" -> if (inCell) { cInline = StringBuilder(); inInline = true }
                    "rPh" -> inPh = true
                    "t" -> captureT = inInline && !inPh
                    "mergeCell" -> {
                        val ref = p.attrs["ref"]
                        if (ref != null && ':' in ref) {
                            val a = parseRef(ref.substringBefore(':'))
                            val b = parseRef(ref.substringAfter(':'))
                            if (a != null && b != null) merges.add(intArrayOf(a.first, a.second, b.first, b.second))
                        }
                    }
                }
                XmlPull.Event.TEXT -> {
                    if (captureV) cValue?.append(p.text)
                    if (captureT) cInline?.append(p.text)
                }
                XmlPull.Event.END -> when (p.name) {
                    "v" -> captureV = false
                    "t" -> captureT = false
                    "rPh" -> inPh = false
                    "is" -> inInline = false
                    "c" -> if (inCell) {
                        inCell = false
                        val row = curRow
                        if (row != null && cCol < MAX_COLS) {
                            val text = cellText(cType, cValue?.toString(), cInline?.toString(), cStyle)
                            val numeric = (cType == null || cType == "n") && cValue != null
                            if (text.isNotEmpty() || classFor(cStyle).isNotEmpty()) {
                                while (row.size <= cCol) row.add(null)
                                row[cCol] = GCell(text, classFor(cStyle), numeric = numeric && text.isNotEmpty())
                                if (cCol > maxCol) maxCol = cCol
                                if (++cells > MAX_CELLS) { truncated = true; stop = true }
                            }
                        } else if (row != null) truncated = true
                    }
                    "row" -> { curRow = null; skipRow = false }
                }
                XmlPull.Event.EOF -> break@loop
            }
        }

        // merged cells: spans count only the rows that were actually emitted
        for (m in merges) {
            val (r1, c1, r2, c2) = m.toList()
            if (c1 >= MAX_COLS) continue
            val presentRows = (r1..r2).mapNotNull { rowIndex[it] }
            val first = presentRows.firstOrNull() ?: continue
            val cEnd = minOf(c2, MAX_COLS - 1)
            fun cellAt(ri: Int, c: Int): GCell? = rows[ri].getOrNull(c)
            fun setCell(ri: Int, c: Int, cell: GCell) { val r = rows[ri]; while (r.size <= c) r.add(null); r[c] = cell }
            val master = cellAt(first, c1) ?: GCell("").also { setCell(first, c1, it) }
            master.colspan = cEnd - c1 + 1
            master.rowspan = presentRows.size
            for (ri in presentRows) for (c in c1..cEnd) {
                if (ri == first && c == c1) continue
                val existing = cellAt(ri, c)
                if (existing != null) existing.covered = true else setCell(ri, c, GCell("", covered = true))
            }
            if (cEnd > maxCol) maxCol = cEnd
        }
        return GridSheet(name, rows, rowNumbers, maxCol + 1, truncated, hiddenCols)
    }

    private fun cellText(type: String?, v: String?, inline: String?, style: Int): String {
        return when (type) {
            "s" -> v?.trim()?.toIntOrNull()?.let { sst.getOrNull(it) } ?: ""
            "inlineStr" -> inline ?: v ?: ""
            "str", "e", "d" -> v ?: ""
            "b" -> if (v?.trim() == "1") "TRUE" else "FALSE"
            else -> {
                val raw = v?.trim() ?: return inline ?: ""
                val d = raw.toDoubleOrNull() ?: return raw
                val xf = xfs.getOrNull(style)
                XlFormat.format(d, xf?.code ?: "General", date1904)
            }
        }
    }

    private companion object {
        const val MAX_ROWS = 10_000
        const val MAX_COLS = 200
        const val MAX_CELLS = 300_000
        const val MAX_SHEETS = 100
    }
}
