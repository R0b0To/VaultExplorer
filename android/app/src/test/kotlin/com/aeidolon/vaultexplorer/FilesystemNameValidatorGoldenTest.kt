package com.aeidolon.vaultexplorer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Runs the shared golden cases in test/fixtures/filename_validation_golden.json
 * against the Kotlin side of the filename validator. The Dart side
 * (test/core/filesystem/filename_validation_golden_test.dart) runs the
 * exact same file against FilesystemRules/validateEntryName.
 *
 * The two validators are intentionally kept as separate, hand-maintained
 * implementations across the JNI boundary (docs/architecture.md, ADR-005
 * item 3) rather than unified into one. This test doesn't change that; it
 * exists so that if a rule changes on one side and someone forgets to
 * mirror it on the other, a test fails immediately instead of the two
 * implementations silently drifting apart. Add a case to the JSON file and
 * both this test and the Dart one pick it up.
 */
class FilesystemNameValidatorGoldenTest {

    // Gradle's default working directory for `:app:testDebugUnitTest` is
    // the module directory (android/app), so the shared fixture -- which
    // lives at the repo root so the Dart side can read it the normal way
    // `flutter test` expects -- is two levels up from here. If this ever
    // starts failing because the file can't be found, the fix is to update
    // this path (or the Gradle working directory), not to skip the test.
    private val fixtureFile = File("../../test/fixtures/filename_validation_golden.json")

    private fun kindFor(name: String): FilesystemNameValidator.Kind = when (name) {
        "ENCRYPTED_VAULT" -> FilesystemNameValidator.Kind.ENCRYPTED_VAULT
        "UNKNOWN_CONSERVATIVE" -> FilesystemNameValidator.Kind.UNKNOWN_CONSERVATIVE
        else -> error("Unknown golden-fixture kind: \"$name\"")
    }

    @Test
    fun `shared filename-validation golden fixture is readable`() {
        assertTrue(
            "Expected ${fixtureFile.path} (resolved from ${fixtureFile.absolutePath}). " +
                "This test (and its Dart counterpart, filename_validation_golden_test.dart) " +
                "both depend on this exact relative path; if Gradle's test working directory " +
                "has changed, fix the path here rather than skipping the test.",
            fixtureFile.exists(),
        )
    }

    @Test
    fun `all golden cases agree with the Kotlin validator`() {
        val root = MiniJsonParser(fixtureFile.readText()).parse() as Map<*, *>
        @Suppress("UNCHECKED_CAST")
        val cases = root["cases"] as List<Map<String, Any?>>

        val failures = mutableListOf<String>()
        for (case in cases) {
            val name = case["name"] as String
            val kind = kindFor(case["kind"] as String)
            val expectedValid = case["valid"] as Boolean
            val note = case["note"] as String?

            val issues = FilesystemNameValidator.validate(name, kind)
            val actuallyValid = issues.isEmpty()
            if (actuallyValid != expectedValid) {
                val label = "\"$name\" on ${case["kind"]}" + (note?.let { " ($it)" } ?: "")
                failures.add(
                    "$label: expected valid=$expectedValid but got valid=$actuallyValid" +
                        if (issues.isNotEmpty()) " (issues: ${issues.joinToString(", ")})" else "",
                )
            }
        }

        assertEquals(
            "One or more golden cases disagree between the fixture and " +
                "FilesystemNameValidator.kt -- see docs/architecture.md ADR-005 item 3.",
            emptyList<String>(),
            failures,
        )
    }
}

/**
 * A deliberately minimal JSON reader, not a general-purpose one: it
 * supports exactly the subset of JSON used by
 * test/fixtures/filename_validation_golden.json (objects, arrays, strings
 * with standard escapes including \\uXXXX, booleans, and null) and nothing
 * else -- no numbers, since the fixture doesn't use any. This exists so the
 * golden-fixture cross-check doesn't require adding a JSON library
 * dependency just to read one small test fixture. If a future case needs a
 * JSON feature this doesn't support, extend this parser rather than
 * reaching for a fuller one for this single use.
 */
private class MiniJsonParser(private val text: String) {
    private var pos = 0

    fun parse(): Any? {
        skipWhitespace()
        val value = parseValue()
        skipWhitespace()
        return value
    }

    private fun parseValue(): Any? {
        skipWhitespace()
        return when (text[pos]) {
            '{' -> parseObject()
            '[' -> parseArray()
            '"' -> parseString()
            else -> parseLiteral()
        }
    }

    private fun parseLiteral(): Any? = when {
        text.startsWith("true", pos) -> {
            pos += 4
            true
        }
        text.startsWith("false", pos) -> {
            pos += 5
            false
        }
        text.startsWith("null", pos) -> {
            pos += 4
            null
        }
        else -> error(
            "Unexpected token at position $pos: '" +
                text.substring(pos, minOf(pos + 20, text.length)) + "'",
        )
    }

    private fun parseObject(): Map<String, Any?> {
        val result = LinkedHashMap<String, Any?>()
        expect('{')
        skipWhitespace()
        if (peek() == '}') {
            pos++
            return result
        }
        while (true) {
            skipWhitespace()
            val key = parseString()
            skipWhitespace()
            expect(':')
            val value = parseValue()
            result[key] = value
            skipWhitespace()
            when (peek()) {
                ',' -> pos++
                '}' -> {
                    pos++
                    return result
                }
                else -> error("Expected ',' or '}' at position $pos")
            }
        }
    }

    private fun parseArray(): List<Any?> {
        val result = mutableListOf<Any?>()
        expect('[')
        skipWhitespace()
        if (peek() == ']') {
            pos++
            return result
        }
        while (true) {
            result.add(parseValue())
            skipWhitespace()
            when (peek()) {
                ',' -> pos++
                ']' -> {
                    pos++
                    return result
                }
                else -> error("Expected ',' or ']' at position $pos")
            }
        }
    }

    private fun parseString(): String {
        expect('"')
        val sb = StringBuilder()
        while (peek() != '"') {
            val c = text[pos]
            if (c == '\\') {
                pos++
                when (val esc = text[pos]) {
                    '"' -> sb.append('"')
                    '\\' -> sb.append('\\')
                    '/' -> sb.append('/')
                    'b' -> sb.append('\b')
                    'f' -> sb.append('\u000C')
                    'n' -> sb.append('\n')
                    'r' -> sb.append('\r')
                    't' -> sb.append('\t')
                    'u' -> {
                        val hex = text.substring(pos + 1, pos + 5)
                        sb.append(hex.toInt(16).toChar())
                        pos += 4
                    }
                    else -> error("Unknown escape sequence '\\$esc' at position $pos")
                }
                pos++
            } else {
                sb.append(c)
                pos++
            }
        }
        pos++ // consume closing quote
        return sb.toString()
    }

    private fun peek(): Char = text[pos]

    private fun expect(c: Char) {
        check(text[pos] == c) { "Expected '$c' at position $pos, found '${text[pos]}'" }
        pos++
    }

    private fun skipWhitespace() {
        while (pos < text.length && text[pos].isWhitespace()) pos++
    }
}
