#include "xfer_host.h"

#include <fstream>
#include <system_error>

namespace fs = std::filesystem;

namespace xfer {

fs::path pathFromUtf8(const std::string& utf8) { return fs::path(std::u8string(utf8.begin(), utf8.end())); }

std::string utf8FromPath(const fs::path& p) {
    const std::u8string u = p.u8string();
    return std::string(u.begin(), u.end());
}

namespace {

void setError(std::string* e, const std::string& msg) {
    if (e) *e = msg;
}

class FileSource final : public ByteSource {
public:
    explicit FileSource(const fs::path& p) : in_(p, std::ios::binary) {}
    bool ok() const { return in_.is_open() && in_.good(); }
    int64_t read(uint8_t* buf, size_t n) override {
        in_.read(reinterpret_cast<char*>(buf), static_cast<std::streamsize>(n));
        const std::streamsize got = in_.gcount();
        if (got > 0) return static_cast<int64_t>(got);
        return in_.eof() ? 0 : -1;
    }

private:
    std::ifstream in_;
};

class FileSink final : public ByteSink {
public:
    explicit FileSink(const fs::path& p) : path_(p), out_(p, std::ios::binary | std::ios::trunc) {}
    bool ok() const { return out_.is_open() && out_.good(); }
    bool write(const uint8_t* data, size_t n) override {
        out_.write(reinterpret_cast<const char*>(data), static_cast<std::streamsize>(n));
        return out_.good();
    }
    bool close() override {
        if (finished_) return true;
        out_.flush();
        const bool good = out_.good();
        out_.close();
        finished_ = good && !out_.fail();
        return finished_;
    }
    void discard() override {
        if (finished_) return;
        if (out_.is_open()) out_.close();
        std::error_code ec;
        fs::remove(path_, ec);
        finished_ = true;   // nothing left to finish or discard
    }
    ~FileSink() override {
        // A sink dropped without close() or discard() is an abandoned write: leave no partial file.
        if (!finished_) discard();
    }

private:
    fs::path path_;
    std::ofstream out_;
    bool finished_ = false;
};

}  // namespace

std::unique_ptr<ByteSource> openFileSource(const fs::path& file, std::string* error, uint64_t* size) {
    std::error_code ec;
    if (!fs::is_regular_file(file, ec)) {
        setError(error, "not a readable file: " + utf8FromPath(file));
        return nullptr;
    }
    if (size) {
        const auto sz = fs::file_size(file, ec);
        if (ec) {
            setError(error, "cannot determine file size: " + utf8FromPath(file));
            return nullptr;
        }
        *size = static_cast<uint64_t>(sz);
    }
    auto src = std::make_unique<FileSource>(file);
    if (!src->ok()) {
        setError(error, "cannot open: " + utf8FromPath(file));
        return nullptr;
    }
    return src;
}

std::unique_ptr<ByteSink> createFileSink(const fs::path& file, std::string* error) {
    auto sink = std::make_unique<FileSink>(file);
    if (!sink->ok()) {
        setError(error, "cannot create: " + utf8FromPath(file));
        std::error_code ec;
        fs::remove(file, ec);   // a failed create may still have left an empty file behind
        return nullptr;
    }
    return sink;
}

Result hashFile(const fs::path& file, const std::vector<HashAlgo>& algos, Observer* obs, std::vector<Digest>& out,
                std::string* error) {
    uint64_t size = 0;
    auto src = openFileSource(file, error, &size);
    if (!src) return Result::Failed;
    const Result r = hashStream(*src, algos, size, obs, out);
    if (r == Result::Failed) setError(error, "hashing failed: " + utf8FromPath(file));
    return r;
}

Result splitFile(const fs::path& source, const fs::path& destDir, uint64_t chunkSize, Observer* obs,
                 SplitSummary* summary, std::string* error) {
    uint64_t total = 0;
    auto src = openFileSource(source, error, &total);
    if (!src) return Result::Failed;

    std::error_code ec;
    fs::create_directories(destDir, ec);
    if (!fs::is_directory(destDir, ec)) {
        setError(error, "cannot use destination folder: " + utf8FromPath(destDir));
        return Result::Failed;
    }

    const std::string displayName = utf8FromPath(source.filename());
    auto opener = [&](int index) -> std::unique_ptr<ByteSink> {
        return createFileSink(destDir / pathFromUtf8(partName(displayName, index)));
    };
    int parts = 0;
    const Result r = splitStream(*src, total, chunkSize, opener, obs, &parts, error);
    if (r != Result::Ok) return r;

    // Best effort, for other split/join tools that expect a manifest beside the parts. The parts
    // are complete and valid without it, so a failure here is not a failure of the split.
    if (auto manifest = createFileSink(destDir / "manifest.json")) {
        const std::string json = manifestJson(displayName, guessFormat(displayName), total, chunkSize);
        if (!manifest->write(reinterpret_cast<const uint8_t*>(json.data()), json.size()) || !manifest->close())
            manifest->discard();
    }
    if (summary) {
        summary->displayName = displayName;
        summary->totalSize = total;
        summary->parts = parts;
    }
    return Result::Ok;
}

Result joinFiles(const fs::path& firstPart, const fs::path& output, Observer* obs, std::string* error) {
    fs::path dir = firstPart.parent_path();
    if (dir.empty()) dir = ".";
    const std::string firstName = utf8FromPath(firstPart.filename());
    const std::vector<std::string> names = resolvePartSequence(firstName, [&](const std::string& n) {
        std::error_code ec;
        return fs::exists(dir / pathFromUtf8(n), ec);
    });

    std::vector<std::unique_ptr<ByteSource>> owned;
    std::vector<ByteSource*> sources;
    uint64_t total = 0;
    for (const std::string& n : names) {
        const fs::path p = dir / pathFromUtf8(n);
        std::error_code ec;
        if (fs::exists(output, ec) && fs::equivalent(p, output, ec)) {
            setError(error, "the output file is one of the parts");
            return Result::Failed;
        }
        uint64_t sz = 0;
        auto src = openFileSource(p, error, &sz);
        if (!src) return Result::Failed;
        total += sz;
        sources.push_back(src.get());
        owned.push_back(std::move(src));
    }

    auto sink = createFileSink(output, error);
    if (!sink) return Result::Failed;
    return joinStreams(sources, total, *sink, obs, error);
}

}  // namespace xfer
