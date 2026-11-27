package com.aeidolon.vaultexplorer.handlers

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Runs the shared known-answer table in test/fixtures/import_policy_golden.tsv against the Kotlin side of the
 * import policy (uniqueNameAgainst, fitsWithinSafetyMargin, foldName). The Dart side
 * (test/core/engine/desktop/desktop_import_policy_test.dart) runs the exact same file against
 * lib/core/engine/desktop/desktop_import_policy.dart.
 *
 * Dart owns import policy (docs/architecture.md, invariant 12) and the two implementations are hand-maintained
 * mirrors; this test does not unify them, it makes sure a rule changed on one side and forgotten on the other
 * fails a test instead of drifting. Add a row to the table and both tests pick it up.
 */
class ImportExportHandlersGoldenTest {

    // Gradle runs unit tests with the module directory (android/app) as the working directory, so the fixture,
    // which lives at the repository root for `flutter test`, is two levels up -- the same convention as
    // FilesystemNameValidatorGoldenTest. If this stops finding the file, fix the path rather than skipping the test.
    private val fixtureFile = File("../../test/fixtures/import_policy_golden.tsv")

    @Test
    fun `shared import-policy golden table is readable`() {
        assertTrue(
            "Expected ${fixtureFile.path} (resolved from ${fixtureFile.absolutePath}).",
            fixtureFile.exists(),
        )
    }

    @Test
    fun `every row agrees with ImportExportHandlers`() {
        val failures = mutableListOf<String>()
        var rows = 0
        for (line in fixtureFile.readLines()) {
            if (line.isBlank() || line.startsWith("#")) continue
            val f = line.split('\t')
            rows++
            when (f[0]) {
                "unique" -> {
                    val taken: Set<String> = if (f[2] == "-") emptySet() else f[2].split('|').toSet()
                    val got = ImportExportHandlers.uniqueNameAgainst(taken, f[3], caseSensitive = f[1] == "true")
                    if (got != f[4]) {
                        failures.add("unique \"${f[3]}\" vs {${f[2]}} (caseSensitive=${f[1]}): expected \"${f[4]}\", got \"$got\"")
                    }
                }
                "margin" -> {
                    val got = ImportExportHandlers.fitsWithinSafetyMargin(f[1].toLong(), f[2].toLong())
                    if (got != (f[3] == "true")) {
                        failures.add("margin ${f[1]} into ${f[2]}: expected ${f[3]}, got $got")
                    }
                }
                "fold" -> {
                    val got = ImportExportHandlers.foldName(f[2], f[1] == "true")
                    if (got != f[3]) {
                        failures.add("fold \"${f[2]}\" (caseSensitive=${f[1]}): expected \"${f[3]}\", got \"$got\"")
                    }
                }
                else -> failures.add("unknown row kind \"${f[0]}\"")
            }
        }
        assertTrue("The golden table has no rows", rows > 0)
        assertEquals(
            "One or more rows disagree between the shared table and ImportExportHandlers.kt -- see " +
                "lib/core/engine/desktop/desktop_import_policy.dart for the Dart side.",
            emptyList<String>(),
            failures,
        )
    }
}
