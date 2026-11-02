package com.aeidolon.vaultexplorer.reader

/**
 * Page model for a horizontally paged EPUB chapter (CSS columns, one column per
 * screen, scrolled by the WebView).
 *
 * Pages sit at multiples of the viewport width and the last page is pinned to
 * the real maximum scroll offset. The layout width is rarely an exact multiple
 * of the viewport (sub-pixel rounding, an overflowing table), so a few pixels
 * of overshoot are ignored rather than counted as a page of their own. Without
 * that tolerance the reader can sit one pixel short of "the end", never report
 * that it reached it, and so never move on to the next chapter.
 *
 * All values are physical scroll offsets in pixels (0 = left edge); mapping to
 * reading order for right-to-left books is the caller's job.
 */
internal object PageMath {

    fun maxOffset(contentPx: Int, viewportPx: Int): Int =
        (contentPx - viewportPx).coerceAtLeast(0)

    /** Index of the last page; a chapter that fits one screen has only page 0. */
    fun lastPage(contentPx: Int, viewportPx: Int, slopPx: Int): Int {
        if (viewportPx <= 0) return 0
        val max = maxOffset(contentPx, viewportPx)
        if (max <= slopPx) return 0
        return (max - slopPx + viewportPx - 1) / viewportPx
    }

    /** Scroll offset that shows [page]; pages outside the chapter are clamped. */
    fun offsetOfPage(page: Int, contentPx: Int, viewportPx: Int, slopPx: Int): Int {
        if (viewportPx <= 0) return 0
        val last = lastPage(contentPx, viewportPx, slopPx)
        val p = page.coerceIn(0, last)
        return if (p >= last) maxOffset(contentPx, viewportPx) else p * viewportPx
    }

    /** The page that [offset] is showing (or is closest to, mid-drag). */
    fun pageAtOffset(offset: Int, contentPx: Int, viewportPx: Int, slopPx: Int): Int {
        if (viewportPx <= 0) return 0
        val last = lastPage(contentPx, viewportPx, slopPx)
        if (offset >= maxOffset(contentPx, viewportPx) - slopPx) return last
        return ((offset + viewportPx / 2) / viewportPx).coerceIn(0, last)
    }
}
