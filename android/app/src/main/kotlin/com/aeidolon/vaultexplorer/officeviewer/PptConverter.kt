package com.aeidolon.vaultexplorer.officeviewer

import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Legacy binary PowerPoint (`.ppt`, PowerPoint 97-2003): text only.
 *
 * Reads the "PowerPoint Document" stream's record tree and collects the text
 * atoms of every slide (placeholder text from the SlideListWithText list plus
 * text boxes from each slide's drawing) and of its speaker notes. Pictures,
 * layout and formatting are not recovered; for those the user can still send
 * the file to another app.
 */
internal class PptConverter(private val cfb: CompoundFile, private val opts: ViewOptions) {
    var title: String? = null
        private set

    private class TextRun(val type: Int, val text: String)

    private class SlideData(val slideId: Long) {
        val runs = ArrayList<TextRun>()
    }

    private val cp1252 = java.nio.charset.Charset.forName("windows-1252")
    private var textBudget = 4_000_000

    // slides from the SlideListWithText (instance 0), in presentation order
    private val listed = ArrayList<SlideData>()
    // text found inside each `Slide` container, in stream order
    private val drawings = ArrayList<List<TextRun>>()
    // notes text by the slideId they belong to
    private val notes = HashMap<Long, MutableList<String>>()

    fun convert(): String {
        val data = cfb.stream("PowerPoint Document")
            ?: throw OfficeException(OfficeError.UNSUPPORTED, "no PowerPoint Document stream")
        val bb = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN)
        walk(bb, 0, data.size, 0, Ctx.NONE, null)

        val useMerged = listed.isNotEmpty() && drawings.size == listed.size
        val slides: List<List<TextRun>> = when {
            useMerged -> listed.mapIndexed { i, s -> merge(s.runs, drawings[i]) }
            listed.isNotEmpty() -> listed.map { it.runs }
            else -> drawings
        }
        if (slides.isEmpty()) throw OfficeException(OfficeError.UNSUPPORTED, "no slides")

        val out = StringBuilder()
        for ((i, runs) in slides.take(1000).withIndex()) {
            out.append("<section class=\"paper slide\"><div class=\"num\">").append(i + 1).append("</div>")
            val titles = runs.filter { it.type == 0 || it.type == 6 }
            if (titles.isNotEmpty()) {
                out.append("<h2 class=\"st\">")
                    .append(titles.joinToString("<br>") { paragraphs(it.text).joinToString("<br>") { p -> esc(p) } })
                    .append("</h2>")
            }
            val list = ListBuilder(out)
            for (r in runs) {
                if (r.type == 0 || r.type == 6 || r.type == 2) continue
                val asList = r.type == 1 || r.type == 7 || r.type == 8
                val cls = if (r.type == 5) " class=\"subtitle\"" else ""
                for (p in paragraphs(r.text)) {
                    val html = esc(p).replace("\u000B", "<br>")
                    if (asList) list.item(0, "u", false, null, 1, html)
                    else { list.closeAll(); out.append("<p").append(cls).append('>').append(html).append("</p>") }
                }
                if (!asList) list.closeAll()
            }
            list.closeAll()
            val slideId = if (listed.size > i) listed[i].slideId else -1L
            notes[slideId]?.filter { it.isNotBlank() }?.takeIf { it.isNotEmpty() }?.let { ns ->
                out.append("<details class=\"notes\"><summary>").append(esc(opts.notesLabel)).append("</summary>")
                for (n in ns) for (p in paragraphs(n)) out.append("<p>").append(esc(p)).append("</p>")
                out.append("</details>")
            }
            out.append("</section>")
        }
        return out.toString()
    }

    private fun merge(listedRuns: List<TextRun>, drawn: List<TextRun>): List<TextRun> {
        val seen = HashSet<String>()
        val out = ArrayList<TextRun>()
        for (r in listedRuns) if (seen.add(r.text)) out.add(r)
        for (r in drawn) if (seen.add(r.text)) out.add(r)
        return out
    }

    private fun paragraphs(text: String): List<String> =
        text.split('\r', '\n').map { it.trim('\u0000') }.filter { it.isNotBlank() }

    private enum class Ctx { NONE, SLIDE, NOTES, LIST_SLIDES, LIST_NOTES, SKIP }

    private class Sink(val runs: MutableList<TextRun>) {
        var lastType = 4
    }

    private var currentListSlide: SlideData? = null
    private var currentListNotesId = -1L
    private var notesAtomSlideId = -1L
    private var notesBucket: MutableList<TextRun>? = null

    private fun walk(bb: ByteBuffer, start: Int, end: Int, depth: Int, ctx: Ctx, sink: Sink?) {
        if (depth > 24) return
        var off = start
        while (off + 8 <= end) {
            val verInst = bb.getShort(off).toInt() and 0xFFFF
            val type = bb.getShort(off + 2).toInt() and 0xFFFF
            val len = bb.getInt(off + 4)
            val body = off + 8
            if (len < 0 || body.toLong() + len > end) return
            val ver = verInst and 0xF
            val inst = verInst shr 4

            when (type) {
                0x03EE -> { // Slide
                    val s = Sink(ArrayList())
                    walk(bb, body, body + len, depth + 1, Ctx.SLIDE, s)
                    drawings.add(s.runs)
                }
                0x03F0 -> { // Notes
                    val s = Sink(ArrayList())
                    notesAtomSlideId = -1L
                    walk(bb, body, body + len, depth + 1, Ctx.NOTES, s)
                    val id = notesAtomSlideId
                    val texts = s.runs.filter { it.type == 2 }.map { it.text }
                    if (id >= 0 && texts.isNotEmpty()) notes.getOrPut(id) { ArrayList() }.addAll(texts)
                }
                0x03F8 -> {} // MainMaster: skip (template text such as "Click to edit...")
                0x0FF0 -> { // SlideListWithText: 0 = slides, 1 = masters, 2 = notes
                    when (inst) {
                        0 -> walk(bb, body, body + len, depth + 1, Ctx.LIST_SLIDES, null)
                        2 -> walk(bb, body, body + len, depth + 1, Ctx.LIST_NOTES, null)
                    }
                }
                0x03F1 -> if (ctx == Ctx.NOTES && len >= 4) notesAtomSlideId = bb.getInt(body).toLong() and 0xFFFFFFFFL
                0x03F3 -> if (len >= 16) { // SlidePersistAtom
                    val slideId = bb.getInt(body + 12).toLong() and 0xFFFFFFFFL
                    if (ctx == Ctx.LIST_SLIDES) {
                        val sd = SlideData(slideId)
                        listed.add(sd)
                        currentListSlide = sd
                    } else if (ctx == Ctx.LIST_NOTES) currentListNotesId = slideId
                }
                0x0F9F -> if (len >= 4) { // TextHeaderAtom
                    val t = bb.getInt(body)
                    sink?.lastType = t
                    if (ctx == Ctx.LIST_SLIDES || ctx == Ctx.LIST_NOTES) listType = t
                }
                0x0FA0, 0x0FA8 -> {
                    val text = readText(bb, body, len, type == 0x0FA0)
                    if (text.isNotEmpty()) {
                        when (ctx) {
                            Ctx.SLIDE, Ctx.NOTES -> sink?.let { it.runs.add(TextRun(it.lastType, text)); it.lastType = 4 }
                            Ctx.LIST_SLIDES -> currentListSlide?.runs?.add(TextRun(listType, text))
                            Ctx.LIST_NOTES -> if (currentListNotesId >= 0) notes.getOrPut(currentListNotesId) { ArrayList() }.add(text)
                            else -> {}
                        }
                    }
                }
                else -> if (ver == 0xF && ctx != Ctx.SKIP && ctx != Ctx.NONE) {
                    walk(bb, body, body + len, depth + 1, ctx, sink)
                } else if (ver == 0xF && ctx == Ctx.NONE && type == 0x03E8) {
                    walk(bb, body, body + len, depth + 1, ctx, sink) // Document container wraps the lists
                }
            }
            off = body + len
        }
    }

    private var listType = 4

    private fun readText(bb: ByteBuffer, off: Int, len: Int, utf16: Boolean): String {
        if (len <= 0 || textBudget <= 0) return ""
        val n = minOf(len, textBudget)
        textBudget -= n
        val bytes = ByteArray(n)
        bb.position(off); bb.get(bytes, 0, n)
        return if (utf16) String(bytes, 0, n and 1.inv(), Charsets.UTF_16LE) else String(bytes, cp1252)
    }
}
