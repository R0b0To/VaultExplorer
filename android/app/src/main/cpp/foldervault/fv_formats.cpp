#include "fv_formats.h"

#include "fv_cryfs.h"
#include "fv_cryptomator.h"
#include "fv_gocryptfs.h"

namespace fv {

const char* formatWireName(VaultFormat format) {
    switch (format) {
        case VaultFormat::Gocryptfs: return "gocryptfs";
        case VaultFormat::Cryptomator: return "cryptomator";
        case VaultFormat::Cryfs: return "cryfs";
    }
    return "";
}

bool formatFromWireName(const std::string& name, VaultFormat& out) {
    if (name == "gocryptfs") { out = VaultFormat::Gocryptfs; return true; }
    if (name == "cryptomator" || name == "directory_vault") { out = VaultFormat::Cryptomator; return true; }
    if (name == "cryfs") { out = VaultFormat::Cryfs; return true; }
    return false;
}

const char* configFileName(VaultFormat format) {
    switch (format) {
        case VaultFormat::Gocryptfs: return gocryptfs::kConfigName;
        case VaultFormat::Cryptomator: return cryptomator::kMasterkeyFile;
        case VaultFormat::Cryfs: return cryfs::kConfigName;
    }
    return "";
}

bool looksLikeVault(VaultFormat format, Storage& storage) {
    DirEntry e;
    return storage.stat(configFileName(format), e) && !e.isDir;
}

bool validateConfigFile(VaultFormat format, const Bytes& content, std::string& reason) {
    try {
        switch (format) {
            case VaultFormat::Gocryptfs:
                (void)gocryptfs::Config::parse(std::string(content.begin(), content.end()));
                return true;
            case VaultFormat::Cryptomator:
                (void)cryptomator::MasterkeyFile::parse(std::string(content.begin(), content.end()));
                return true;
            case VaultFormat::Cryfs:
                // Every genuine cryfs.config is padded to a fixed total size.
                if (content.size() < 1024) { reason = "Doesn't look like a genuine cryfs.config."; return false; }
                cryfs::checkConfigEnvelope(content);
                return true;
        }
    } catch (const std::exception& e) {
        reason = e.what();
        if (reason.empty()) reason = std::string("Malformed ") + configFileName(format);
        return false;
    }
    reason = "Unknown folder vault format.";
    return false;
}

GocryptfsCipher gocryptfsCipherFromName(const std::string& name) {
    if (name == "xchacha20-poly1305") return GocryptfsCipher::XChaCha20Poly1305;
    if (name == "aes-siv") return GocryptfsCipher::AesSiv;
    return GocryptfsCipher::Aes256Gcm;
}

void normalizeCryfsCreateOptions(CryfsCreateOptions& o) {
    const CryfsCreateOptions defaults;
    if (o.cipher != "xchacha20-poly1305" && o.cipher != "aes-256-gcm") o.cipher = defaults.cipher;
    if (o.blocksizeBytes < kCryfsMinBlockSize || o.blocksizeBytes > kCryfsMaxBlockSize) o.blocksizeBytes = defaults.blocksizeBytes;
}

}  // namespace fv
