package com.aeidolon.vaultexplorer.reader

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.ByteArrayOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/** [EpubPackage.findCoverPath]: which entry an EPUB's thumbnail is taken from. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class EpubCoverTest {

    private val container = """<?xml version="1.0"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
        </container>"""

    /** An EPUB whose package document has the given [metadata] and [manifest] lines. */
    private fun epub(
        metadata: String = "",
        manifest: String = "",
        spine: String = """<itemref idref="c1"/>""",
        extraFiles: List<String> = emptyList(),
    ): Pair<ByteArraySource, ZipDirectory> {
        val opf = """<?xml version="1.0"?>
            <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>T</dc:title>$metadata</metadata>
              <manifest>
                <item id="c1" href="text/c1.xhtml" media-type="application/xhtml+xml"/>
                $manifest
              </manifest>
              <spine>$spine</spine>
            </package>"""
        val out = ByteArrayOutputStream()
        ZipOutputStream(out).use { zos ->
            fun put(name: String, text: String) {
                zos.putNextEntry(ZipEntry(name))
                zos.write(text.toByteArray())
                zos.closeEntry()
            }
            put("META-INF/container.xml", container)
            put("OEBPS/content.opf", opf)
            put("OEBPS/text/c1.xhtml", "<html/>")
            for (f in extraFiles) put(f, "x")
        }
        val src = ByteArraySource(out.toByteArray())
        return src to ZipReader.readDirectory(src)
    }

    private fun cover(
        metadata: String = "",
        manifest: String = "",
        spine: String = """<itemref idref="c1"/>""",
        files: List<String> = emptyList(),
    ): String? {
        val (src, dir) = epub(metadata, manifest, spine, files)
        return EpubPackage.findCoverPath(src, dir)
    }

    @Test
    fun `EPUB 3 cover-image property`() {
        assertEquals(
            "OEBPS/img/front.jpg",
            cover(
                manifest = """<item id="i" href="img/front.jpg" media-type="image/jpeg" properties="cover-image"/>""",
                files = listOf("OEBPS/img/front.jpg"),
            ),
        )
    }

    @Test
    fun `EPUB 2 meta cover names a manifest id`() {
        assertEquals(
            "OEBPS/img/cover.png",
            cover(
                metadata = """<meta name="cover" content="cov"/>""",
                manifest = """<item id="cov" href="img/cover.png" media-type="image/png"/>""",
                files = listOf("OEBPS/img/cover.png"),
            ),
        )
    }

    @Test
    fun `EPUB 2 meta cover that is an href rather than an id`() {
        assertEquals(
            "OEBPS/images/c.jpg",
            cover(
                metadata = """<meta name="cover" content="images/c.jpg"/>""",
                manifest = """<item id="img1" href="images/c.jpg" media-type="image/jpeg"/>""",
                files = listOf("OEBPS/images/c.jpg"),
            ),
        )
    }

    @Test
    fun `percent-encoded and dot-dot hrefs resolve to the real entry`() {
        assertEquals(
            "OEBPS/img/my cover.jpg",
            cover(
                manifest = """<item id="i" href="text/../img/my%20cover.jpg" media-type="image/jpeg" properties="cover-image"/>""",
                files = listOf("OEBPS/img/my cover.jpg"),
            ),
        )
    }

    @Test
    fun `a cover page that is XHTML is not an image, so it is skipped`() {
        assertNull(
            cover(
                metadata = """<meta name="cover" content="coverpage"/>""",
                manifest = """<item id="coverpage" href="text/cover.xhtml" media-type="application/xhtml+xml"/>""",
                files = listOf("OEBPS/text/cover.xhtml"),
            ),
        )
    }

    @Test
    fun `an SVG cover is skipped because the bitmap decoder cannot read it`() {
        assertNull(
            cover(
                manifest = """<item id="i" href="cover.svg" media-type="image/svg+xml" properties="cover-image"/>""",
                files = listOf("OEBPS/cover.svg"),
            ),
        )
    }

    @Test
    fun `falls back to an image that calls itself the cover`() {
        assertEquals(
            "OEBPS/img/cover.jpg",
            cover(
                manifest = """
                    <item id="p1" href="img/page1.jpg" media-type="image/jpeg"/>
                    <item id="x" href="img/cover.jpg" media-type="image/jpeg"/>""",
                files = listOf("OEBPS/img/page1.jpg", "OEBPS/img/cover.jpg"),
            ),
        )
        // ...by manifest id too.
        assertEquals(
            "OEBPS/img/0001.jpg",
            cover(
                manifest = """<item id="cover-image" href="img/0001.jpg" media-type="image/jpeg"/>""",
                files = listOf("OEBPS/img/0001.jpg"),
            ),
        )
    }

    @Test
    fun `a back cover is not mistaken for the cover`() {
        assertNull(
            cover(
                manifest = """<item id="b" href="img/back_cover.jpg" media-type="image/jpeg"/>""",
                files = listOf("OEBPS/img/back_cover.jpg"),
            ),
        )
    }

    @Test
    fun `a declared cover wins over a name that merely looks like one`() {
        assertEquals(
            "OEBPS/img/real.jpg",
            cover(
                manifest = """
                    <item id="decoy" href="img/cover.jpg" media-type="image/jpeg"/>
                    <item id="r" href="img/real.jpg" media-type="image/jpeg" properties="cover-image"/>""",
                files = listOf("OEBPS/img/cover.jpg", "OEBPS/img/real.jpg"),
            ),
        )
    }

    @Test
    fun `a cover the manifest names but the archive lacks is no cover`() {
        assertNull(
            cover(
                manifest = """<item id="i" href="img/gone.jpg" media-type="image/jpeg" properties="cover-image"/>""",
            ),
        )
    }

    @Test
    fun `a missing media type is judged by the extension`() {
        assertEquals(
            "OEBPS/c.jpeg",
            cover(
                manifest = """<item id="i" href="c.jpeg" media-type="" properties="cover-image"/>""",
                files = listOf("OEBPS/c.jpeg"),
            ),
        )
    }

    @Test
    fun `a book with no cover at all yields null`() {
        assertNull(cover())
    }

    @Test
    fun `an empty reading order does not stop the cover being found`() {
        // EpubPackage.parse refuses this book outright; its cover is still fine.
        assertEquals(
            "OEBPS/cover.jpg",
            cover(
                manifest = """<item id="i" href="cover.jpg" media-type="image/jpeg" properties="cover-image"/>""",
                spine = "",
                files = listOf("OEBPS/cover.jpg"),
            ),
        )
    }
}
