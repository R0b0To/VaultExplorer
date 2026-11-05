#include "fv_common.h"

#include <atomic>
#include <cstring>

namespace fv {

void secureZero(void* p, size_t n) {
    if (!p || n == 0) return;
    volatile uint8_t* v = static_cast<volatile uint8_t*>(p);
    for (size_t i = 0; i < n; i++) v[i] = 0;
    std::atomic_signal_fence(std::memory_order_seq_cst);
}

std::string normalizePath(std::string_view p) {
    size_t b = 0, e = p.size();
    while (b < e && p[b] == '/') b++;
    while (e > b && p[e - 1] == '/') e--;
    return std::string(p.substr(b, e - b));
}

std::string parentOf(std::string_view n) {
    size_t i = n.rfind('/');
    return i == std::string_view::npos ? std::string() : std::string(n.substr(0, i));
}

std::string nameOf(std::string_view n) {
    size_t i = n.rfind('/');
    return i == std::string_view::npos ? std::string(n) : std::string(n.substr(i + 1));
}

std::string joinPath(std::string_view parent, std::string_view name) {
    if (parent.empty()) return std::string(name);
    std::string r(parent);
    r.push_back('/');
    r.append(name);
    return r;
}

std::vector<std::string> splitSegments(std::string_view p) {
    std::vector<std::string> out;
    size_t i = 0;
    while (i <= p.size()) {
        size_t j = p.find('/', i);
        if (j == std::string_view::npos) j = p.size();
        if (j > i) out.emplace_back(p.substr(i, j - i));
        i = j + 1;
    }
    return out;
}

std::string toHex(const uint8_t* p, size_t n) {
    static const char* d = "0123456789abcdef";
    std::string s;
    s.resize(n * 2);
    for (size_t i = 0; i < n; i++) { s[2 * i] = d[p[i] >> 4]; s[2 * i + 1] = d[p[i] & 15]; }
    return s;
}

static int hexVal(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

bool fromHex(std::string_view s, Bytes& out) {
    if (s.size() % 2) return false;
    out.resize(s.size() / 2);
    for (size_t i = 0; i < out.size(); i++) {
        int a = hexVal(s[2 * i]), b = hexVal(s[2 * i + 1]);
        if (a < 0 || b < 0) return false;
        out[i] = (uint8_t)((a << 4) | b);
    }
    return true;
}

std::string base64Encode(const uint8_t* p, size_t n, bool urlSafe, bool pad) {
    const char* tbl = urlSafe
        ? "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
        : "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    std::string out;
    out.reserve((n + 2) / 3 * 4);
    size_t i = 0;
    for (; i + 3 <= n; i += 3) {
        uint32_t v = ((uint32_t)p[i] << 16) | ((uint32_t)p[i + 1] << 8) | p[i + 2];
        out.push_back(tbl[v >> 18]); out.push_back(tbl[(v >> 12) & 63]);
        out.push_back(tbl[(v >> 6) & 63]); out.push_back(tbl[v & 63]);
    }
    if (i + 1 == n) {
        uint32_t v = (uint32_t)p[i] << 16;
        out.push_back(tbl[v >> 18]); out.push_back(tbl[(v >> 12) & 63]);
        if (pad) out.append("==");
    } else if (i + 2 == n) {
        uint32_t v = ((uint32_t)p[i] << 16) | ((uint32_t)p[i + 1] << 8);
        out.push_back(tbl[v >> 18]); out.push_back(tbl[(v >> 12) & 63]); out.push_back(tbl[(v >> 6) & 63]);
        if (pad) out.push_back('=');
    }
    return out;
}

bool base64Decode(std::string_view s, Bytes& out) {
    out.clear();
    uint32_t acc = 0;
    int bits = 0;
    size_t end = s.size();
    while (end > 0 && s[end - 1] == '=') end--;
    for (size_t i = 0; i < end; i++) {
        char c = s[i];
        int v;
        if (c >= 'A' && c <= 'Z') v = c - 'A';
        else if (c >= 'a' && c <= 'z') v = c - 'a' + 26;
        else if (c >= '0' && c <= '9') v = c - '0' + 52;
        else if (c == '+' || c == '-') v = 62;
        else if (c == '/' || c == '_') v = 63;
        else return false;
        acc = (acc << 6) | (uint32_t)v;
        bits += 6;
        if (bits >= 8) { bits -= 8; out.push_back((uint8_t)((acc >> bits) & 0xFF)); }
    }
    // A single dangling sextet cannot encode a byte: reject like java.util.Base64.
    if (end % 4 == 1) return false;
    return true;
}

std::string base32Encode(const uint8_t* p, size_t n) {
    static const char* alpha = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
    std::string out;
    uint64_t buffer = 0;
    int bitsLeft = 0;
    for (size_t i = 0; i < n; i++) {
        buffer = (buffer << 8) | p[i];
        bitsLeft += 8;
        while (bitsLeft >= 5) {
            bitsLeft -= 5;
            out.push_back(alpha[(buffer >> bitsLeft) & 0x1F]);
        }
        buffer &= ((uint64_t)1 << bitsLeft) - 1;
    }
    if (bitsLeft > 0) out.push_back(alpha[(buffer << (5 - bitsLeft)) & 0x1F]);
    return out;
}

bool isValidUtf8(std::string_view s) {
    size_t i = 0, n = s.size();
    while (i < n) {
        uint8_t c = (uint8_t)s[i];
        if (c < 0x80) { i++; continue; }
        size_t len; uint32_t cp;
        if ((c & 0xE0) == 0xC0) { len = 2; cp = c & 0x1F; }
        else if ((c & 0xF0) == 0xE0) { len = 3; cp = c & 0x0F; }
        else if ((c & 0xF8) == 0xF0) { len = 4; cp = c & 0x07; }
        else return false;
        if (i + len > n) return false;
        for (size_t k = 1; k < len; k++) {
            uint8_t cc = (uint8_t)s[i + k];
            if ((cc & 0xC0) != 0x80) return false;
            cp = (cp << 6) | (cc & 0x3F);
        }
        if (len == 2 && cp < 0x80) return false;
        if (len == 3 && cp < 0x800) return false;
        if (len == 4 && (cp < 0x10000 || cp > 0x10FFFF)) return false;
        if (cp >= 0xD800 && cp <= 0xDFFF) return false;
        i += len;
    }
    return true;
}

static std::atomic<NormalizerFn> g_normalizer{nullptr};
void setNfcNormalizer(NormalizerFn fn) { g_normalizer.store(fn); }

std::string nfc(const std::string& s) {
    bool ascii = true;
    for (unsigned char c : s) if (c >= 0x80) { ascii = false; break; }
    if (ascii) return s;
    NormalizerFn fn = g_normalizer.load();
    return fn ? fn(s) : s;
}

static std::atomic<LogFn> g_logger{nullptr};
void setLogger(LogFn fn) { g_logger.store(fn); }
void logMsg(LogLevel lvl, const char* tag, const std::string& msg) {
    LogFn fn = g_logger.load();
    if (fn) fn(lvl, tag, msg);
}

}  // namespace fv
