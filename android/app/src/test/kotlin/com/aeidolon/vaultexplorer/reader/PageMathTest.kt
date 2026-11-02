package com.aeidolon.vaultexplorer.reader

import org.junit.Assert.assertEquals
import org.junit.Test

class PageMathTest {

    private val view = 1000
    private val slop = 10

    private fun last(content: Int) = PageMath.lastPage(content, view, slop)
    private fun offset(page: Int, content: Int) = PageMath.offsetOfPage(page, content, view, slop)
    private fun page(offset: Int, content: Int) = PageMath.pageAtOffset(offset, content, view, slop)

    @Test
    fun chapterThatFitsOneScreenHasOnePage() {
        assertEquals(0, last(1000))
        assertEquals(0, last(1004))
        assertEquals(0, offset(3, 1000))
        assertEquals(0, page(0, 1000))
    }

    @Test
    fun exactMultipleOfViewport() {
        assertEquals(3, last(4000))
        assertEquals(0, offset(0, 4000))
        assertEquals(2000, offset(2, 4000))
        assertEquals(3000, offset(3, 4000))
        assertEquals(3, page(3000, 4000))
    }

    @Test
    fun fewPixelsOfOvershootDoNotCreateAnExtraPage() {
        // 4002px of content: the last page is the real end, not a fifth page.
        assertEquals(3, last(4002))
        assertEquals(3002, offset(3, 4002))
        // Resting on 3000px counts as being on the last page, so a swipe from
        // there is a request for the next chapter rather than a no-op.
        assertEquals(3, page(3000, 4002))
        assertEquals(3, page(3002, 4002))
    }

    @Test
    fun realPartialLastPageIsKept() {
        // 4100px: 100px of genuine content past the fourth screen.
        assertEquals(4, last(4100))
        assertEquals(3100, offset(4, 4100))
        assertEquals(3, page(3000, 4100))
        assertEquals(4, page(3100, 4100))
    }

    @Test
    fun pagesOutsideTheChapterAreClamped() {
        assertEquals(0, offset(-1, 4000))
        assertEquals(3000, offset(9, 4000))
    }

    @Test
    fun midDragOffsetsRoundToTheNearestPage() {
        assertEquals(1, page(1400, 4000))
        assertEquals(2, page(1600, 4000))
    }

    @Test
    fun zeroViewportIsSafe() {
        assertEquals(0, PageMath.lastPage(4000, 0, slop))
        assertEquals(0, PageMath.offsetOfPage(2, 4000, 0, slop))
        assertEquals(0, PageMath.pageAtOffset(500, 4000, 0, slop))
    }
}
