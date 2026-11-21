package com.aeidolon.vaultexplorer.panorama

import java.io.ByteArrayOutputStream

/** Writes the Google photo-sphere (GPano) XMP block that 360° viewers look for. */
internal object PanoramaXmp {
    private const val HEADER = "http://ns.adobe.com/xap/1.0/\u0000"

    fun build(
        fullWidth: Int,
        fullHeight: Int,
        cropWidth: Int,
        cropHeight: Int,
        cropLeft: Int,
        cropTop: Int,
    ): String = buildString {
        append("<?xpacket begin=\"\uFEFF\" id=\"W5M0MpCehiHzreSzNTczkc9d\"?>\n")
        append("<x:xmpmeta xmlns:x=\"adobe:ns:meta/\">")
        append("<rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\">")
        append("<rdf:Description rdf:about=\"\" xmlns:GPano=\"http://ns.google.com/photos/1.0/panorama/\"")
        append(" GPano:UsePanoramaViewer=\"True\"")
        append(" GPano:ProjectionType=\"equirectangular\"")
        append(" GPano:CaptureSoftware=\"VaultExplorer\"")
        append(" GPano:StitchingSoftware=\"VaultExplorer\"")
        append(" GPano:InitialViewHeadingDegrees=\"0\"")
        append(" GPano:FullPanoWidthPixels=\"$fullWidth\"")
        append(" GPano:FullPanoHeightPixels=\"$fullHeight\"")
        append(" GPano:CroppedAreaImageWidthPixels=\"$cropWidth\"")
        append(" GPano:CroppedAreaImageHeightPixels=\"$cropHeight\"")
        append(" GPano:CroppedAreaLeftPixels=\"$cropLeft\"")
        append(" GPano:CroppedAreaTopPixels=\"$cropTop\"/>")
        append("</rdf:RDF></x:xmpmeta>\n")
        append("<?xpacket end=\"w\"?>")
    }

    /** Inserts [xmp] as an APP1 segment right after the JPEG's SOI marker. */
    fun inject(jpeg: ByteArray, xmp: String): ByteArray {
        if (jpeg.size < 4 || jpeg[0] != 0xFF.toByte() || jpeg[1] != 0xD8.toByte()) return jpeg
        val payload = (HEADER + xmp).toByteArray(Charsets.UTF_8)
        val segmentLength = payload.size + 2
        if (segmentLength > 0xFFFF) return jpeg
        val out = ByteArrayOutputStream(jpeg.size + payload.size + 4)
        out.write(jpeg, 0, 2)
        out.write(0xFF)
        out.write(0xE1)
        out.write((segmentLength shr 8) and 0xFF)
        out.write(segmentLength and 0xFF)
        out.write(payload)
        out.write(jpeg, 2, jpeg.size - 2)
        return out.toByteArray()
    }
}
