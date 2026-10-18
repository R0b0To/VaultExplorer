package com.aeidolon.vaultexplorer.officeviewer

import java.math.BigDecimal
import java.math.MathContext
import java.math.RoundingMode
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.format.TextStyle
import java.util.Locale

/**
 * Renders spreadsheet number formats (`#,##0.00`, `0%`, `yyyy-mm-dd`, ...).
 * Covers what real workbooks overwhelmingly use; anything exotic degrades to
 * the General rendering instead of failing.
 */
internal object XlFormat {

    val BUILTIN: Map<Int, String> = mapOf(
        0 to "General", 1 to "0", 2 to "0.00", 3 to "#,##0", 4 to "#,##0.00",
        9 to "0%", 10 to "0.00%", 11 to "0.00E+00", 12 to "# ?/?", 13 to "# ??/??",
        14 to "yyyy-mm-dd", 15 to "d-mmm-yy", 16 to "d-mmm", 17 to "mmm-yy",
        18 to "h:mm AM/PM", 19 to "h:mm:ss AM/PM", 20 to "h:mm", 21 to "h:mm:ss", 22 to "yyyy-mm-dd h:mm",
        37 to "#,##0_);(#,##0)", 38 to "#,##0_);[Red](#,##0)", 39 to "#,##0.00_);(#,##0.00)",
        40 to "#,##0.00_);[Red](#,##0.00)", 45 to "mm:ss", 46 to "[h]:mm:ss", 47 to "mm:ss.0",
        48 to "##0.0E+0", 49 to "@",
    )

    private sealed class Tok {
        class Lit(val s: String) : Tok()
        class Ch(val c: Char) : Tok()
        class Elapsed(val unit: Char, val width: Int) : Tok()
    }

    private fun tokenize(section: String): List<Tok> {
        val out = ArrayList<Tok>()
        var i = 0
        while (i < section.length) {
            val c = section[i]
            when {
                c == '"' -> {
                    val end = section.indexOf('"', i + 1).let { if (it < 0) section.length else it }
                    out.add(Tok.Lit(section.substring(i + 1, end)))
                    i = end + 1
                }
                c == '\\' && i + 1 < section.length -> { out.add(Tok.Lit(section[i + 1].toString())); i += 2 }
                c == '_' && i + 1 < section.length -> { out.add(Tok.Lit(" ")); i += 2 }
                c == '*' && i + 1 < section.length -> i += 2
                c == '[' -> {
                    val end = section.indexOf(']', i).let { if (it < 0) section.length - 1 else it }
                    val inner = section.substring(i + 1, end)
                    val lower = inner.lowercase(Locale.ROOT)
                    if (lower.isNotEmpty() && lower.all { it == 'h' } || lower.isNotEmpty() && lower.all { it == 'm' } ||
                        lower.isNotEmpty() && lower.all { it == 's' }
                    ) out.add(Tok.Elapsed(lower[0], lower.length))
                    else if (inner.startsWith("$")) {
                        val sym = inner.substring(1).substringBefore('-')
                        if (sym.isNotEmpty()) out.add(Tok.Lit(sym))
                    }
                    i = end + 1
                }
                else -> { out.add(Tok.Ch(c)); i++ }
            }
        }
        return out
    }

    private fun splitSections(code: String): List<String> {
        val parts = ArrayList<String>()
        val sb = StringBuilder()
        var inQuote = false
        var i = 0
        while (i < code.length) {
            val c = code[i]
            if (c == '"') inQuote = !inQuote
            if (c == '\\' && i + 1 < code.length) { sb.append(c).append(code[i + 1]); i += 2; continue }
            if (c == ';' && !inQuote) { parts.add(sb.toString()); sb.setLength(0) } else sb.append(c)
            i++
        }
        parts.add(sb.toString())
        return parts
    }

    fun isDateFormat(code: String): Boolean {
        val sections = splitSections(code)
        val toks = tokenize(sections[0])
        if (toks.any { it is Tok.Elapsed }) return true
        val raw = toks.filterIsInstance<Tok.Ch>().map { it.c.lowercaseChar() }
        if (raw.any { it == 'y' || it == 'd' || it == 'h' || it == 's' }) return true
        // a lone "m" with nothing numeric around it is a month
        return raw.contains('m') && raw.none { it == '0' || it == '#' || it == '?' }
    }

    fun general(d: Double): String {
        if (d.isNaN() || d.isInfinite()) return "#NUM!"
        if (d == 0.0) return "0"
        val a = Math.abs(d)
        if (a >= 1e11 || a < 1e-4) {
            var s = String.format(Locale.ROOT, "%.5E", d)
            s = s.replace(Regex("(\\.\\d*?)0+E"), "$1E").replace(".E", "E")
            return s
        }
        return BigDecimal(java.lang.Double.toString(d)).round(MathContext(10, RoundingMode.HALF_UP))
            .stripTrailingZeros().toPlainString()
    }

    fun format(value: Double, code: String, date1904: Boolean): String {
        if (code.isEmpty() || code.equals("General", ignoreCase = true) || code == "@") return general(value)
        if (value.isNaN() || value.isInfinite()) return general(value)
        val sections = splitSections(code)
        if (isDateFormat(code)) {
            return try { formatDate(value, tokenize(sections[0]), date1904) } catch (e: Exception) { general(value) }
        }
        var idx = 0
        var negativeHandled = false
        if (value < 0 && sections.size >= 2) { idx = 1; negativeHandled = true }
        else if (value == 0.0 && sections.size >= 3) idx = 2
        val section = sections[idx]
        val abs = if (negativeHandled) Math.abs(value) else value
        return try {
            formatNumber(abs, section)
        } catch (e: Exception) {
            general(value)
        }
    }

    private fun formatNumber(value: Double, section: String): String {
        if (section.trim().equals("General", ignoreCase = true)) return general(value)
        val toks = tokenize(section)
        val isPh = { t: Tok -> t is Tok.Ch && (t.c == '0' || t.c == '#' || t.c == '?') }
        val sci = toks.indices.firstOrNull { k ->
            val t = toks[k] as? Tok.Ch
            val n = toks.getOrNull(k + 1) as? Tok.Ch
            t != null && (t.c == 'E' || t.c == 'e') && n != null && (n.c == '+' || n.c == '-')
        }
        val limit = sci ?: toks.size
        val first = (0 until limit).firstOrNull { isPh(toks[it]) } ?: -1
        if (first < 0) {
            // purely literal format: "Yes", "n/a", ...
            return toks.joinToString("") { if (it is Tok.Lit) it.s else (it as? Tok.Ch)?.c?.toString() ?: "" }
        }
        var start = first
        if (start > 0 && (toks[start - 1] as? Tok.Ch)?.c == '.') start-- // ".00"
        val last = (0 until limit).last { isPh(toks[it]) }
        val prefix = StringBuilder()
        val suffix = StringBuilder()
        var percent = 0
        fun lit(t: Tok, sb: StringBuilder) {
            when (t) {
                is Tok.Lit -> sb.append(t.s)
                is Tok.Ch -> if (t.c == '%') { percent++; sb.append('%') } else if (t.c != '@') sb.append(t.c)
                else -> {}
            }
        }
        for (k in 0 until start) lit(toks[k], prefix)
        var scaling = 0
        val scientific = sci != null
        val expSign = sci != null && (toks[sci + 1] as Tok.Ch).c == '+'
        var tail = last + 1
        if (sci != null) {
            tail = sci + 2
            while (tail < toks.size && (toks[tail] as? Tok.Ch)?.c == '0') tail++
        } else {
            while (tail < toks.size && (toks[tail] as? Tok.Ch)?.c == ',') { scaling++; tail++ }
        }
        for (k in tail until toks.size) lit(toks[k], suffix)

        val intPattern = StringBuilder()
        val fracPattern = StringBuilder()
        var seenDot = false
        var thousands = false
        for (k in start..last) {
            val c = (toks[k] as? Tok.Ch)?.c ?: continue
            when {
                c == '.' -> seenDot = true
                c == ',' -> if (!seenDot) thousands = true
                c == '/' -> throw IllegalArgumentException("fraction format")
                c == '0' || c == '#' || c == '?' -> if (seenDot) fracPattern.append(c) else intPattern.append(c)
            }
        }
        var v = value
        repeat(percent) { v *= 100.0 }
        repeat(scaling) { v /= 1000.0 }
        val neg = v < 0
        v = Math.abs(v)

        val body: String
        if (scientific) {
            val s = String.format(Locale.ROOT, "%.${fracPattern.length}E", v)
            body = if (expSign) s else s.replace("E+", "E")
        } else {
            val dec = fracPattern.length
            val bd = BigDecimal(java.lang.Double.toString(v)).setScale(dec, RoundingMode.HALF_UP)
            val plain = bd.toPlainString()
            var intStr = plain.substringBefore('.')
            var fracStr = if (plain.contains('.')) plain.substringAfter('.') else ""
            // optional (#) trailing fraction digits drop their zeros
            var cut = fracStr.length
            while (cut > 0 && fracPattern[cut - 1] != '0' && fracStr[cut - 1] == '0') cut--
            fracStr = fracStr.substring(0, cut)
            val minInt = intPattern.count { it == '0' }
            if (intStr == "0" && minInt == 0) intStr = ""
            if (intStr.length < minInt) intStr = "0".repeat(minInt - intStr.length) + intStr
            if (thousands) intStr = intStr.reversed().chunked(3).joinToString(",").reversed()
            body = if (fracStr.isNotEmpty()) "$intStr.$fracStr" else intStr
        }
        val shown = if (body.isEmpty()) "0" else body
        return (if (neg && shown.any { it in '1'..'9' }) "-" else "") + prefix + shown + suffix
    }

    private fun formatDate(serial: Double, toks: List<Tok>, date1904: Boolean): String {
        if (serial < 0) throw IllegalArgumentException("negative date")
        val millis = Math.round(serial * 86_400_000.0)
        val base: LocalDate = when {
            date1904 -> LocalDate.of(1904, 1, 1)
            serial < 60 -> LocalDate.of(1899, 12, 31)
            else -> LocalDate.of(1899, 12, 30)
        }
        val dt: LocalDateTime = base.atStartOfDay().plusNanos(millis * 1_000_000L)
        val locale = Locale.getDefault()
        val text = toks.joinToString("") { if (it is Tok.Ch) it.c.toString() else if (it is Tok.Lit) "\u0000" + it.s + "\u0000" else "" }
        val hasAmPm = Regex("a[mp]?/[pm]?", RegexOption.IGNORE_CASE).containsMatchIn(text.replace(Regex("\u0000[^\u0000]*\u0000"), ""))

        // Walk tokens, grouping runs of the same date letter.
        data class Unit(val letter: Char, val count: Int, val lit: String?, val elapsed: Tok.Elapsed? = null)
        val units = ArrayList<Unit>()
        var i = 0
        while (i < toks.size) {
            val t = toks[i]
            if (t is Tok.Elapsed) { units.add(Unit(t.unit, t.width, null, t)); i++; continue }
            if (t is Tok.Lit) { units.add(Unit(' ', 0, t.s)); i++; continue }
            val c = (t as Tok.Ch).c
            val lc = c.lowercaseChar()
            if (lc == 'y' || lc == 'm' || lc == 'd' || lc == 'h' || lc == 's') {
                var n = 1
                while (i + n < toks.size && (toks[i + n] as? Tok.Ch)?.c?.lowercaseChar() == lc) n++
                units.add(Unit(lc, n, null))
                i += n
                continue
            }
            // AM/PM, A/P
            val rest = StringBuilder()
            var j = i
            while (j < toks.size && j < i + 5 && toks[j] is Tok.Ch) { rest.append((toks[j] as Tok.Ch).c); j++ }
            val r = rest.toString()
            if (r.length >= 5 && r.substring(0, 5).equals("AM/PM", ignoreCase = true)) {
                units.add(Unit('P', 2, r.substring(0, 5))); i += 5; continue
            }
            if (r.length >= 3 && r.substring(0, 3).equals("A/P", ignoreCase = true)) {
                units.add(Unit('P', 1, r.substring(0, 3))); i += 3; continue
            }
            units.add(Unit(' ', 0, c.toString()))
            i++
        }
        val sb = StringBuilder()
        var skipTo = -1
        for ((k, u) in units.withIndex()) {
            if (k < skipTo) continue
            when {
                u.elapsed != null -> {
                    val total = when (u.letter) {
                        'h' -> Math.floor(serial * 24.0)
                        'm' -> Math.floor(serial * 1440.0)
                        else -> Math.floor(serial * 86400.0)
                    }.toLong()
                    sb.append(total.toString().padStart(u.count, '0'))
                }
                u.lit != null && u.letter == ' ' -> sb.append(u.lit)
                u.letter == 'P' -> {
                    val pm = dt.hour >= 12
                    val sample = u.lit!!
                    val upper = sample[0].isUpperCase()
                    val s = if (u.count == 2) (if (pm) "PM" else "AM") else (if (pm) "P" else "A")
                    sb.append(if (upper) s else s.lowercase(Locale.ROOT))
                }
                u.letter == 'y' -> sb.append(if (u.count >= 3) dt.year.toString().padStart(4, '0') else (dt.year % 100).toString().padStart(2, '0'))
                u.letter == 'd' -> when {
                    u.count == 1 -> sb.append(dt.dayOfMonth)
                    u.count == 2 -> sb.append(dt.dayOfMonth.toString().padStart(2, '0'))
                    u.count == 3 -> sb.append(dt.dayOfWeek.getDisplayName(TextStyle.SHORT, locale))
                    else -> sb.append(dt.dayOfWeek.getDisplayName(TextStyle.FULL, locale))
                }
                u.letter == 'h' -> {
                    val h = if (hasAmPm) ((dt.hour + 11) % 12) + 1 else dt.hour
                    sb.append(if (u.count >= 2) h.toString().padStart(2, '0') else h.toString())
                }
                u.letter == 's' -> {
                    sb.append(if (u.count >= 2) dt.second.toString().padStart(2, '0') else dt.second.toString())
                    // fractional seconds: "." followed by zero placeholders right after the seconds field
                    var j = k + 1
                    if (units.getOrNull(j)?.lit == ".") {
                        j++
                        var n = 0
                        while (units.getOrNull(j)?.lit == "0") { n++; j++ }
                        if (n > 0) {
                            sb.append('.').append(String.format(Locale.ROOT, "%09d", dt.nano).substring(0, Math.min(n, 9)))
                            skipTo = j
                        }
                    }
                }
                u.letter == 'm' -> {
                    // minute if adjacent to an hour field (before) or a seconds field (after), else month
                    var prevHour = false
                    for (b in k - 1 downTo 0) {
                        val pu = units[b]
                        if (pu.letter == ' ' && pu.elapsed == null) continue
                        prevHour = pu.letter == 'h'; break
                    }
                    var nextSec = false
                    for (b in k + 1 until units.size) {
                        val nu = units[b]
                        if (nu.letter == ' ' && nu.elapsed == null) continue
                        nextSec = nu.letter == 's'; break
                    }
                    if (prevHour || nextSec) sb.append(if (u.count >= 2) dt.minute.toString().padStart(2, '0') else dt.minute.toString())
                    else when (u.count) {
                        1 -> sb.append(dt.monthValue)
                        2 -> sb.append(dt.monthValue.toString().padStart(2, '0'))
                        3 -> sb.append(dt.month.getDisplayName(TextStyle.SHORT, locale))
                        4 -> sb.append(dt.month.getDisplayName(TextStyle.FULL, locale))
                        else -> sb.append(dt.month.getDisplayName(TextStyle.NARROW, locale))
                    }
                }
            }
        }
        return sb.toString()
    }
}
