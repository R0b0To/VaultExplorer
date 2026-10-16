#include "doc_pdf.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <string>

namespace docscan {
namespace {

constexpr double kLongSidePt = 842.0;  // A4 long side

struct Writer {
    std::vector<uint8_t> out;
    std::vector<size_t> offsets;  // offsets[i] = byte offset of object i+1

    void raw(const std::string& s) { out.insert(out.end(), s.begin(), s.end()); }
    void raw(const uint8_t* p, size_t n) { out.insert(out.end(), p, p + n); }
    void beginObject(int id) {
        if (offsets.size() < static_cast<size_t>(id)) offsets.resize(id);
        offsets[id - 1] = out.size();
        raw(std::to_string(id) + " 0 obj\n");
    }
    void endObject() { raw("endobj\n"); }
};

std::string num(double v) {
    char buf[32];
    std::snprintf(buf, sizeof(buf), "%.2f", v);
    return buf;
}

}  // namespace

bool readJpegInfo(const uint8_t* d, size_t n, int* width, int* height, int* components) {
    if (!d || n < 4 || d[0] != 0xFF || d[1] != 0xD8) return false;
    size_t i = 2;
    while (i + 1 < n) {
        if (d[i] != 0xFF) return false;  // lost marker sync
        while (i < n && d[i] == 0xFF) ++i;  // fill bytes
        if (i >= n) return false;
        const uint8_t m = d[i++];
        if (m == 0x01 || (m >= 0xD0 && m <= 0xD8)) continue;  // markers without a length
        if (m == 0xD9 || m == 0xDA) return false;             // image data before any frame header
        if (i + 2 > n) return false;
        const size_t len = (static_cast<size_t>(d[i]) << 8) | d[i + 1];
        if (len < 2 || i + len > n) return false;
        const bool isSof = m >= 0xC0 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC;
        if (isSof) {
            // C0 baseline, C1 extended sequential, C2 progressive. Lossless and
            // arithmetic-coded variants are not valid DCTDecode input here.
            if (m > 0xC2 || len < 8 || d[i + 2] != 8) return false;
            const int h = (d[i + 3] << 8) | d[i + 4];
            const int w = (d[i + 5] << 8) | d[i + 6];
            const int comps = d[i + 7];
            if (w <= 0 || h <= 0 || (comps != 1 && comps != 3)) return false;
            if (len < static_cast<size_t>(8 + 3 * comps)) return false;
            *width = w;
            *height = h;
            *components = comps;
            return true;
        }
        i += len;
    }
    return false;
}

std::vector<uint8_t> buildPdf(const std::vector<PdfPage>& pages) {
    if (pages.empty()) return {};
    struct Info {
        int width, height, components;
    };
    std::vector<Info> info(pages.size());
    for (size_t i = 0; i < pages.size(); ++i)
        if (!readJpegInfo(pages[i].jpeg, pages[i].jpegSize, &info[i].width, &info[i].height, &info[i].components))
            return {};

    // Object layout: 1 catalog, 2 page tree, then per page: page, content, image.
    const int pageCount = static_cast<int>(pages.size());
    Writer w;
    w.raw("%PDF-1.4\n%\xE2\xE3\xCF\xD3\n");

    w.beginObject(1);
    w.raw("<< /Type /Catalog /Pages 2 0 R >>\n");
    w.endObject();

    w.beginObject(2);
    std::string kids;
    for (int i = 0; i < pageCount; ++i) kids += std::to_string(3 + i * 3) + " 0 R ";
    w.raw("<< /Type /Pages /Count " + std::to_string(pageCount) + " /Kids [" + kids + "] >>\n");
    w.endObject();

    for (int i = 0; i < pageCount; ++i) {
        const PdfPage& pg = pages[i];
        const Info& im = info[i];
        const double scale = kLongSidePt / std::max(im.width, im.height);
        const std::string wPt = num(im.width * scale), hPt = num(im.height * scale);
        const int pageId = 3 + i * 3, contentId = pageId + 1, imageId = pageId + 2;

        w.beginObject(pageId);
        w.raw("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 " + wPt + " " + hPt +
              "] /Resources << /XObject << /Im0 " + std::to_string(imageId) +
              " 0 R >> >> /Contents " + std::to_string(contentId) + " 0 R >>\n");
        w.endObject();

        const std::string content = "q " + wPt + " 0 0 " + hPt + " 0 0 cm /Im0 Do Q\n";
        w.beginObject(contentId);
        w.raw("<< /Length " + std::to_string(content.size()) + " >>\nstream\n" + content + "endstream\n");
        w.endObject();

        w.beginObject(imageId);
        w.raw("<< /Type /XObject /Subtype /Image /Width " + std::to_string(im.width) + " /Height " +
              std::to_string(im.height) + " /ColorSpace /" + (im.components == 1 ? "DeviceGray" : "DeviceRGB") +
              " /BitsPerComponent 8 /Filter /DCTDecode /Length " + std::to_string(pg.jpegSize) + " >>\nstream\n");
        w.raw(pg.jpeg, pg.jpegSize);
        w.raw("\nendstream\n");
        w.endObject();
    }

    const size_t xrefPos = w.out.size();
    const int objectCount = 2 + pageCount * 3;
    w.raw("xref\n0 " + std::to_string(objectCount + 1) + "\n");
    w.raw("0000000000 65535 f \n");
    for (int i = 0; i < objectCount; ++i) {
        char line[32];
        std::snprintf(line, sizeof(line), "%010zu 00000 n \n", w.offsets[i]);
        w.raw(line);
    }
    w.raw("trailer\n<< /Size " + std::to_string(objectCount + 1) + " /Root 1 0 R >>\nstartxref\n" +
          std::to_string(xrefPos) + "\n%%EOF\n");
    return std::move(w.out);
}

}  // namespace docscan
