#include "xfer_split.h"

#include <algorithm>
#include <cctype>

namespace xfer {

namespace {

std::string padded(int n, size_t width) {
    std::string s = std::to_string(n);
    if (s.size() < width) s.insert(0, width - s.size(), '0');
    return s;
}

bool allDigits(const std::string& s) {
    return !s.empty() && std::all_of(s.begin(), s.end(), [](unsigned char c) { return std::isdigit(c) != 0; });
}

bool ieq(char a, char b) { return std::tolower(static_cast<unsigned char>(a)) == std::tolower(static_cast<unsigned char>(b)); }

bool startsWithNoCase(const std::string& s, const char* prefix) {
    size_t i = 0;
    for (; prefix[i]; ++i)
        if (i >= s.size() || !ieq(s[i], prefix[i])) return false;
    return true;
}

void setError(std::string* e, const char* msg) {
    if (e) *e = msg;
}

}  // namespace

std::string partName(const std::string& displayName, int index) { return displayName + "." + padded(index, 3); }

std::vector<std::string> resolvePartSequence(const std::string& firstName,
                                             const std::function<bool(const std::string&)>& exists) {
    // Kotlin: ^(.*)\.(\d+|part\d+)$, case-insensitive. The suffix cannot contain a dot, so only
    // the last dot can split the name that way.
    const size_t dot = firstName.rfind('.');
    if (dot == std::string::npos) return {firstName};
    const std::string base = firstName.substr(0, dot);
    const std::string suffix = firstName.substr(dot + 1);
    const bool isPartWord = startsWithNoCase(suffix, "part") && allDigits(suffix.substr(4));
    if (!isPartWord && !allDigits(suffix)) return {firstName};
    const size_t padWidth = suffix.size();

    std::vector<std::string> parts;
    for (int n = 1;; ++n) {
        const std::string name = isPartWord ? base + ".part" + std::to_string(n) : base + "." + padded(n, padWidth);
        if (!exists(name)) break;
        parts.push_back(name);
    }
    return parts.empty() ? std::vector<std::string>{firstName} : parts;
}

std::string guessFormat(const std::string& displayName) {
    std::string lower = displayName;
    std::transform(lower.begin(), lower.end(), lower.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    if (lower.find("luks") != std::string::npos) return "LUKS";
    if (lower.find("bitlocker") != std::string::npos) return "BITLOCKER";
    return "VERACRYPT";
}

namespace {
void jsonString(std::string& out, const std::string& s) {
    out.push_back('"');
    for (unsigned char c : s) {
        switch (c) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            case '\b': out += "\\b"; break;
            case '\f': out += "\\f"; break;
            default:
                if (c < 0x20) {
                    static const char* kHex = "0123456789abcdef";
                    out += "\\u00";
                    out.push_back(kHex[c >> 4]);
                    out.push_back(kHex[c & 0x0F]);
                } else {
                    out.push_back(static_cast<char>(c));   // UTF-8 passes through unescaped
                }
        }
    }
    out.push_back('"');
}
}  // namespace

std::string manifestJson(const std::string& displayName, const std::string& format, uint64_t totalSizeBytes,
                         uint64_t chunkSizeBytes) {
    std::string j = "{\"displayName\":";
    jsonString(j, displayName);
    j += ",\"format\":";
    jsonString(j, format);
    j += ",\"totalSizeBytes\":" + std::to_string(totalSizeBytes);
    j += ",\"chunkSizeBytes\":" + std::to_string(chunkSizeBytes);
    j += "}";
    return j;
}

Result splitStream(ByteSource& src, uint64_t totalSize, uint64_t chunkSize, const PartOpener& openPart,
                   Observer* obs, int* partsWritten, std::string* error) {
    if (partsWritten) *partsWritten = 0;
    if (chunkSize == 0) { setError(error, "part size must be positive"); return Result::Failed; }
    if (totalSize == 0) { setError(error, "could not determine source file size"); return Result::Failed; }

    std::vector<uint8_t> buf(kChunkBytes);
    std::unique_ptr<ByteSink> cur;
    uint64_t inPart = 0, done = 0;
    int index = 0;

    auto fail = [&](Result r, const char* msg) {
        if (cur) cur->discard();   // earlier, finished parts stay
        cur.reset();
        setError(error, msg);
        return r;
    };

    for (;;) {
        if (obs && obs->cancelled()) return fail(Result::Cancelled, "cancelled");
        const uint64_t room = chunkSize - inPart;   // > 0: a full part is closed right away
        const size_t want = static_cast<size_t>(std::min<uint64_t>(buf.size(), room));
        const int64_t n = src.read(buf.data(), want);
        if (n < 0) return fail(Result::Failed, "read error");
        if (n == 0) break;
        if (!cur) {
            cur = openPart(index + 1);
            if (!cur) return fail(Result::Failed, "could not create part");
            ++index;
            inPart = 0;
        }
        if (!cur->write(buf.data(), static_cast<size_t>(n))) return fail(Result::Failed, "write error");
        inPart += static_cast<uint64_t>(n);
        done += static_cast<uint64_t>(n);
        if (obs) obs->onProgress(done, totalSize);
        if (inPart >= chunkSize) {
            if (!cur->close()) return fail(Result::Failed, "could not finish part");
            cur.reset();
            inPart = 0;
        }
    }
    if (cur && !cur->close()) return fail(Result::Failed, "could not finish part");
    if (partsWritten) *partsWritten = index;
    if (index == 0) { setError(error, "source is empty"); return Result::Failed; }
    return Result::Ok;
}

Result joinStreams(const std::vector<ByteSource*>& parts, uint64_t totalSize, ByteSink& out, Observer* obs,
                   std::string* error) {
    std::vector<uint8_t> buf(kChunkBytes);
    uint64_t done = 0;
    auto fail = [&](Result r, const char* msg) {
        out.discard();
        setError(error, msg);
        return r;
    };
    for (ByteSource* part : parts) {
        if (!part) return fail(Result::Failed, "missing part");
        for (;;) {
            if (obs && obs->cancelled()) return fail(Result::Cancelled, "cancelled");
            const int64_t n = part->read(buf.data(), buf.size());
            if (n < 0) return fail(Result::Failed, "read error");
            if (n == 0) break;
            if (!out.write(buf.data(), static_cast<size_t>(n))) return fail(Result::Failed, "write error");
            done += static_cast<uint64_t>(n);
            if (obs) obs->onProgress(done, totalSize);
        }
    }
    if (!out.close()) return fail(Result::Failed, "could not finish output");
    return Result::Ok;
}

}  // namespace xfer
