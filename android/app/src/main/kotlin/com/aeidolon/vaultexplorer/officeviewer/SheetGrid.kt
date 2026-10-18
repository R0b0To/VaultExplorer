package com.aeidolon.vaultexplorer.officeviewer

/** One rendered spreadsheet cell. Merges are pre-resolved by the producer. */
internal class GCell(
    val text: String,
    val cls: String = "",
    var colspan: Int = 1,
    var rowspan: Int = 1,
    var covered: Boolean = false,
    val numeric: Boolean = false,
)

/** A sheet ready to render. Each row is a dense list of cells; null = empty cell. */
internal class GridSheet(
    val name: String,
    val rows: List<List<GCell?>>,
    /** The spreadsheet row number shown for each entry of [rows]. */
    val rowNumbers: List<Int>,
    val columnCount: Int,
    val truncated: Boolean,
    val hiddenColumns: Set<Int> = emptySet(),
)

internal object SheetGrid {

    const val CSS = """
.sheet{max-width:none;padding:10px}
.grid{font-size:.88em}
.grid th{background:#eef0f5;color:#555;font-weight:500;text-align:center;position:sticky;top:0}
.grid th.rn{position:sticky;inset-inline-start:0;min-width:2.2em;text-align:center}
.grid td{white-space:nowrap;vertical-align:bottom}
.grid td.w{white-space:pre-wrap;min-width:12em}
.grid td.n{text-align:right}
.grid tr.more td{color:#888;text-align:center}
.tabin{position:absolute;opacity:0;pointer-events:none}
.tabbar{display:flex;gap:6px;overflow-x:auto;position:sticky;top:0;z-index:5;background:var(--bg);padding:2px 0 10px}
.tabbar label{flex:0 0 auto;padding:6px 14px;border-radius:16px;background:rgba(127,127,127,.22);color:var(--fg);font-size:.9em;white-space:nowrap}
.panels>section{display:none}
"""

    private fun cellHtml(c: GCell, out: StringBuilder) {
        out.append("<td")
        val classes = buildString {
            if (c.numeric) append("n ")
            if (c.cls.isNotEmpty()) append(c.cls)
        }.trim()
        if (classes.isNotEmpty()) out.append(" class=\"").append(classes).append('"')
        if (c.colspan > 1) out.append(" colspan=\"").append(c.colspan).append('"')
        if (c.rowspan > 1) out.append(" rowspan=\"").append(c.rowspan).append('"')
        out.append('>')
        out.append(esc(c.text).replace("\n", "<br>"))
        out.append("</td>")
    }

    fun renderTable(sheet: GridSheet, out: StringBuilder) {
        out.append("<div class=\"scroll\"><table class=\"grid\"><thead><tr><th class=\"rn\"></th>")
        for (c in 0 until sheet.columnCount) {
            if (c in sheet.hiddenColumns) continue
            out.append("<th>").append(colName(c)).append("</th>")
        }
        out.append("</tr></thead><tbody>")
        for ((ri, row) in sheet.rows.withIndex()) {
            out.append("<tr><th class=\"rn\">").append(sheet.rowNumbers.getOrElse(ri) { ri + 1 }).append("</th>")
            for (c in 0 until sheet.columnCount) {
                if (c in sheet.hiddenColumns) continue
                val cell = row.getOrNull(c)
                if (cell == null) { out.append("<td></td>"); continue }
                if (cell.covered) continue
                cellHtml(cell, out)
            }
            out.append("</tr>")
        }
        if (sheet.truncated) {
            out.append("<tr class=\"more\"><td colspan=\"").append(sheet.columnCount + 1).append("\">\u22EF</td></tr>")
        }
        out.append("</tbody></table></div>")
    }

    /** Renders all sheets, with CSS-only tabs (no JavaScript) when there is more than one. */
    fun render(sheets: List<GridSheet>, out: StringBuilder, cssOut: StringBuilder) {
        if (sheets.isEmpty()) { out.append("<article class=\"paper\"></article>"); return }
        if (sheets.size == 1) {
            out.append("<section class=\"paper sheet\">")
            renderTable(sheets[0], out)
            out.append("</section>")
            return
        }
        out.append("<div class=\"tabs\">")
        for (i in sheets.indices) {
            out.append("<input class=\"tabin\" type=\"radio\" name=\"sh\" id=\"sh").append(i).append('"')
            if (i == 0) out.append(" checked")
            out.append('>')
        }
        out.append("<div class=\"tabbar\">")
        for ((i, s) in sheets.withIndex()) {
            out.append("<label for=\"sh").append(i).append("\">").append(esc(s.name)).append("</label>")
        }
        out.append("</div><div class=\"panels\">")
        for ((i, s) in sheets.withIndex()) {
            out.append("<section class=\"paper sheet\" id=\"p").append(i).append("\">")
            renderTable(s, out)
            out.append("</section>")
            cssOut.append("#sh").append(i).append(":checked~.panels #p").append(i).append("{display:block}")
            cssOut.append("#sh").append(i).append(":checked~.tabbar label[for=sh").append(i)
                .append("]{background:var(--accent);color:#fff}")
        }
        out.append("</div></div>")
    }
}
