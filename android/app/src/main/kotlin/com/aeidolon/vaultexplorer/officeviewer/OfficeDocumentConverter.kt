package com.aeidolon.vaultexplorer.officeviewer

import java.util.Locale

/**
 * Entry point: turns an Office / OpenDocument file (as bytes) into a
 * self-contained, script-free HTML page plus in-memory image resources.
 *
 * The format is decided from the file's *content* first (package layout /
 * container streams), with the extension only as a tie-breaker, so a
 * mis-named file still opens. Nothing is written to disk and no network
 * access is made.
 */
internal object OfficeDocumentConverter {

    fun convert(bytes: ByteArray, extension: String, opts: ViewOptions): ConvertedDocument {
        val ext = extension.lowercase(Locale.ROOT).removePrefix(".")
        val res = DocResources()
        return try {
            when {
                OfficePackage.isCompoundFile(bytes) -> convertCompound(bytes, ext, res, opts)
                OfficePackage.isZip(bytes) -> convertPackage(bytes, ext, res, opts)
                else -> throw OfficeException(OfficeError.UNSUPPORTED, "unrecognised file signature")
            }
        } catch (e: OfficeException) {
            throw e
        } catch (e: XmlLimitException) {
            throw OfficeException(OfficeError.TOO_LARGE, e.message ?: "document too complex", e)
        } catch (e: OutOfMemoryError) {
            throw OfficeException(OfficeError.TOO_LARGE, "out of memory", null)
        } catch (e: Exception) {
            throw OfficeException(OfficeError.UNSUPPORTED, "conversion failed: ${e.javaClass.simpleName}: ${e.message}", e)
        }
    }

    private fun convertCompound(bytes: ByteArray, ext: String, res: DocResources, opts: ViewOptions): ConvertedDocument {
        val cfb = CompoundFile(bytes)
        if (cfb.has("EncryptedPackage") || cfb.has("EncryptionInfo")) {
            throw OfficeException(OfficeError.ENCRYPTED, "password-protected Office file")
        }
        if (cfb.has("PowerPoint Document")) {
            val c = PptConverter(cfb, opts)
            val body = c.convert()
            return ConvertedDocument(pageHtml(c.title, body, "", opts), res.all, c.title)
        }
        // legacy .doc / .xls (and anything else) are not supported
        throw OfficeException(OfficeError.UNSUPPORTED, "legacy binary format .$ext")
    }

    private enum class Kind { DOCX, PPTX, XLSX, ODT, ODP, ODS }

    private fun sniff(pkg: OfficePackage, ext: String): Kind? {
        pkg.bytes("mimetype")?.toString(Charsets.US_ASCII)?.trim()?.let { mt ->
            when {
                mt.startsWith("application/vnd.oasis.opendocument.text") -> return Kind.ODT
                mt.startsWith("application/vnd.oasis.opendocument.presentation") -> return Kind.ODP
                mt.startsWith("application/vnd.oasis.opendocument.spreadsheet") -> return Kind.ODS
            }
        }
        val main = try { mainPartName(pkg, "") } catch (e: Exception) { "" }
        return when {
            main.startsWith("word/") || pkg.has("word/document.xml") -> Kind.DOCX
            main.startsWith("ppt/") || pkg.has("ppt/presentation.xml") -> Kind.PPTX
            main.startsWith("xl/") || pkg.has("xl/workbook.xml") -> Kind.XLSX
            pkg.has("content.xml") -> when (ext) { "odp", "otp" -> Kind.ODP; "ods", "ots" -> Kind.ODS; else -> Kind.ODT }
            else -> null
        }
    }

    private fun convertPackage(bytes: ByteArray, ext: String, res: DocResources, opts: ViewOptions): ConvertedDocument {
        val pkg = OfficePackage.open(bytes)
        val kind = sniff(pkg, ext) ?: throw OfficeException(OfficeError.UNSUPPORTED, "not an Office package")
        var css = ""
        val title: String?
        val body: String
        when (kind) {
            Kind.DOCX -> { val c = DocxConverter(pkg, res); body = c.convert(); title = c.title }
            Kind.PPTX -> { val c = PptxConverter(pkg, res, opts); body = c.convert(); title = c.title }
            Kind.XLSX -> { val c = XlsxConverter(pkg); body = c.convert(); title = c.title; css = SheetGrid.CSS + c.css }
            Kind.ODT -> { val c = OdfConverter(pkg, res, opts); body = c.convertText(); title = c.title }
            Kind.ODP -> { val c = OdfConverter(pkg, res, opts); body = c.convertPresentation(); title = c.title }
            Kind.ODS -> { val c = OdfConverter(pkg, res, opts); body = c.convertSpreadsheet(); title = c.title; css = SheetGrid.CSS + c.css }
        }
        return ConvertedDocument(pageHtml(title, body, css, opts), res.all, title)
    }
}
