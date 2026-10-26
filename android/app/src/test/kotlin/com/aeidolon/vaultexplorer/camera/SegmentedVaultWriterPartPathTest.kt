package com.aeidolon.vaultexplorer.camera

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The names a segmented automation recording gives its parts. The pattern is
 * what people will script against (and what sorts the parts in order), so it is
 * pinned down here rather than left to the writer's file I/O.
 */
class SegmentedVaultWriterPartPathTest {

    @Test
    fun `number goes before the extension`() {
        assertEquals(
            "VID_20260823_153000_part001.mp4",
            SegmentedVaultWriter.partPath("VID_20260823_153000.mp4", 1),
        )
    }

    @Test
    fun `numbers are zero padded to three digits and keep growing past that`() {
        assertEquals("a_part012.m4a", SegmentedVaultWriter.partPath("a.m4a", 12))
        assertEquals("a_part999.m4a", SegmentedVaultWriter.partPath("a.m4a", 999))
        assertEquals("a_part1000.m4a", SegmentedVaultWriter.partPath("a.m4a", 1000))
    }

    @Test
    fun `folders in the path are kept`() {
        assertEquals(
            "Clips/Night/rec_part002.mp4",
            SegmentedVaultWriter.partPath("Clips/Night/rec.mp4", 2),
        )
    }

    @Test
    fun `only the last extension is moved`() {
        assertEquals(
            "take.final_part003.mp4",
            SegmentedVaultWriter.partPath("take.final.mp4", 3),
        )
    }

    @Test
    fun `a name without an extension gets the number appended`() {
        assertEquals("recording_part001", SegmentedVaultWriter.partPath("recording", 1))
    }

    @Test
    fun `a dot in a folder name is not an extension`() {
        assertEquals(
            "my.clips/recording_part001",
            SegmentedVaultWriter.partPath("my.clips/recording", 1),
        )
    }

    @Test
    fun `a leading dot starts a hidden file name and is not an extension`() {
        assertEquals(".hidden_part001", SegmentedVaultWriter.partPath(".hidden", 1))
        assertEquals("dir/.hidden_part001", SegmentedVaultWriter.partPath("dir/.hidden", 1))
    }
}
