package com.aeidolon.vaultexplorer.reader

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.ByteArrayOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class EpubPackageTest {

    private fun epub(files: Map<String, String>): ByteArraySource {
        val out = ByteArrayOutputStream()
        ZipOutputStream(out).use { zos ->
            for ((name, text) in files) {
                zos.putNextEntry(ZipEntry(name))
                zos.write(text.toByteArray())
                zos.closeEntry()
            }
        }
        return ByteArraySource(out.toByteArray())
    }

    private val container = """<?xml version="1.0"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
        </container>"""

    @Test
    fun `parses metadata, spine and an EPUB 3 navigation document`() {
        val opf = """<?xml version="1.0"?>
            <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                <dc:title>A Tale</dc:title><dc:creator>Ann</dc:creator><dc:creator>Bo</dc:creator>
                <dc:language>en</dc:language>
                <meta name="cover" content="cov"/>
              </metadata>
              <manifest>
                <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
                <item id="c1" href="text/ch%201.xhtml" media-type="application/xhtml+xml"/>
                <item id="c2" href="text/ch2.xhtml" media-type="application/xhtml+xml"/>
                <item id="cov" href="img/cover.jpg" media-type="image/jpeg"/>
              </manifest>
              <spine page-progression-direction="rtl"><itemref idref="c1"/><itemref idref="c2" linear="no"/></spine>
            </package>"""
        val nav = """<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>
              <nav epub:type="toc"><ol>
                <li><a href="text/ch%201.xhtml">One&nbsp;1</a>
                  <ol><li><a href="text/ch2.xhtml#s1"><span>Sub</span></a></li></ol></li>
              </ol></nav></body></html>"""
        val src = epub(
            mapOf(
                "META-INF/container.xml" to container,
                "OEBPS/content.opf" to opf,
                "OEBPS/nav.xhtml" to nav,
                "OEBPS/text/ch 1.xhtml" to "<html/>",
                "OEBPS/text/ch2.xhtml" to "<html/>",
                "OEBPS/img/cover.jpg" to "x",
            ),
        )
        val pkg = EpubPackage.parse(src, ZipReader.readDirectory(src))

        assertEquals("A Tale", pkg.title)
        assertEquals("Ann, Bo", pkg.author)
        assertEquals("en", pkg.language)
        assertEquals("rtl", pkg.direction)
        assertEquals("OEBPS/img/cover.jpg", pkg.coverPath)
        assertEquals(listOf("OEBPS/text/ch 1.xhtml", "OEBPS/text/ch2.xhtml"), pkg.spine.map { it.path })
        assertEquals(listOf(true, false), pkg.spine.map { it.linear })

        assertEquals(2, pkg.toc.size)
        assertEquals("One\u00A01", pkg.toc[0].title)
        assertEquals(0, pkg.toc[0].level)
        assertEquals("Sub", pkg.toc[1].title)
        assertEquals(1, pkg.toc[1].level)
        assertEquals("OEBPS/text/ch2.xhtml", pkg.toc[1].path)
        assertEquals("s1", pkg.toc[1].fragment)
    }

    @Test
    fun `falls back to the EPUB 2 NCX`() {
        val opf = """<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Old</dc:title></metadata>
              <manifest>
                <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
                <item id="a" href="a.html" media-type="application/xhtml+xml"/>
                <item id="b" href="b.html" media-type="application/xhtml+xml"/>
              </manifest>
              <spine toc="ncx"><itemref idref="a"/><itemref idref="b"/></spine></package>"""
        val ncx = """<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/"><docTitle><text>Old</text></docTitle>
              <navMap>
                <navPoint id="1"><navLabel><text>Part A</text></navLabel><content src="a.html"/>
                  <navPoint id="2"><navLabel><text>Inner</text></navLabel><content src="b.html#x"/></navPoint>
                </navPoint>
              </navMap></ncx>"""
        val src = epub(
            mapOf(
                "META-INF/container.xml" to container,
                "OEBPS/content.opf" to opf,
                "OEBPS/toc.ncx" to ncx,
                "OEBPS/a.html" to "<html/>",
                "OEBPS/b.html" to "<html/>",
            ),
        )
        val pkg = EpubPackage.parse(src, ZipReader.readDirectory(src))
        assertEquals(listOf("Part A", "Inner"), pkg.toc.map { it.title })
        assertEquals(listOf(0, 1), pkg.toc.map { it.level })
        assertEquals("x", pkg.toc[1].fragment)
        assertEquals("", pkg.direction)
        assertEquals("", pkg.coverPath)
    }

    @Test
    fun `a zip that is not an epub is rejected`() {
        val src = epub(mapOf("readme.txt" to "hi"))
        try {
            EpubPackage.parse(src, ZipReader.readDirectory(src))
            fail("expected NOT_FOUND")
        } catch (e: BookFormatException) {
            assertEquals(BookError.NOT_FOUND, e.error)
        }
    }

    @Test
    fun `spine entries that are missing from the zip are dropped`() {
        val opf = """<package xmlns="http://www.idpf.org/2007/opf"><manifest>
              <item id="a" href="a.xhtml" media-type="application/xhtml+xml"/>
              <item id="gone" href="gone.xhtml" media-type="application/xhtml+xml"/></manifest>
              <spine><itemref idref="a"/><itemref idref="gone"/></spine></package>"""
        val src = epub(
            mapOf("META-INF/container.xml" to container, "OEBPS/content.opf" to opf, "OEBPS/a.xhtml" to "<html/>"),
        )
        val pkg = EpubPackage.parse(src, ZipReader.readDirectory(src))
        assertEquals(listOf("OEBPS/a.xhtml"), pkg.spine.map { it.path })
    }

    @Test
    fun `resolvePath folds dots, decodes percent escapes and keeps a literal plus`() {
        assertEquals("OEBPS/text/a b.xhtml", EpubPackage.resolvePath("OEBPS/text", "a%20b.xhtml"))
        assertEquals("OEBPS/img/c.png", EpubPackage.resolvePath("OEBPS/text", "../img/./c.png"))
        assertEquals("x/a+b.html", EpubPackage.resolvePath("x", "a+b.html#frag"))
        assertEquals("top.html", EpubPackage.resolvePath("deep/er", "/top.html"))
        assertTrue(EpubPackage.resolvePath("", "../../up.html") == "up.html")
    }
}
