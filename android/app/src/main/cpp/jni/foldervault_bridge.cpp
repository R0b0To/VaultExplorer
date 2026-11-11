// JNI bridge for the platform-neutral folder-vault core (../foldervault).
//
// Kotlin side: com.aeidolon.vaultexplorer.foldervault.NativeFolderVault
// (external funs) and FolderVaultStorage (the callback interface JniStorage
// drives when a vault folder is only reachable through SAF / the mirror).
//
// Strings cross the boundary through UTF-16 <-> UTF-8 conversion (NOT
// NewStringUTF/GetStringUTFChars, which speak "modified UTF-8" and corrupt
// 4-byte characters such as emoji in file names).
#include <jni.h>
#include <android/log.h>

#include <atomic>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include "jni_bridge_common.h"
#include "jni_callbacks.h"
#include "foldervault/fv_vault.h"

namespace {

constexpr const char* TAG = "FolderVault";

// ---------------------------------------------------------------- JNIEnv --

struct ThreadEnv {
    JNIEnv* env = nullptr;
    bool attached = false;
    ThreadEnv() {
        if (!g_vm) return;
        if (g_vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) == JNI_OK) return;
#ifdef __ANDROID__
        const jint rc = g_vm->AttachCurrentThread(&env, nullptr);                              // NDK signature
#else
        const jint rc = g_vm->AttachCurrentThread(reinterpret_cast<void**>(&env), nullptr);    // HotSpot jni.h (host checks)
#endif
        if (rc == JNI_OK) attached = true; else env = nullptr;
    }
    ~ThreadEnv() { if (attached && g_vm) g_vm->DetachCurrentThread(); }
};
JNIEnv* threadEnv() {
    static thread_local ThreadEnv te;
    return te.env;
}

// ------------------------------------------------------------ UTF helpers --

std::string toUtf8(JNIEnv* env, jstring js) {
    if (!js) return std::string();
    const jchar* u = env->GetStringChars(js, nullptr);
    jsize n = env->GetStringLength(js);
    std::string out;
    out.reserve((size_t)n);
    for (jsize i = 0; i < n; i++) {
        uint32_t cp = u[i];
        if (cp >= 0xD800 && cp <= 0xDBFF && i + 1 < n && u[i + 1] >= 0xDC00 && u[i + 1] <= 0xDFFF) {
            cp = 0x10000 + ((cp - 0xD800) << 10) + (u[i + 1] - 0xDC00);
            i++;
        } else if (cp >= 0xD800 && cp <= 0xDFFF) {
            cp = 0xFFFD;   // lone surrogate
        }
        if (cp < 0x80) out.push_back((char)cp);
        else if (cp < 0x800) { out.push_back((char)(0xC0 | (cp >> 6))); out.push_back((char)(0x80 | (cp & 0x3F))); }
        else if (cp < 0x10000) { out.push_back((char)(0xE0 | (cp >> 12))); out.push_back((char)(0x80 | ((cp >> 6) & 0x3F))); out.push_back((char)(0x80 | (cp & 0x3F))); }
        else { out.push_back((char)(0xF0 | (cp >> 18))); out.push_back((char)(0x80 | ((cp >> 12) & 0x3F))); out.push_back((char)(0x80 | ((cp >> 6) & 0x3F))); out.push_back((char)(0x80 | (cp & 0x3F))); }
    }
    env->ReleaseStringChars(js, u);
    return out;
}

jstring fromUtf8(JNIEnv* env, const std::string& s) {
    std::vector<jchar> u;
    u.reserve(s.size());
    size_t i = 0, n = s.size();
    while (i < n) {
        uint8_t c = (uint8_t)s[i];
        uint32_t cp; size_t len;
        if (c < 0x80) { cp = c; len = 1; }
        else if ((c & 0xE0) == 0xC0 && i + 1 < n) { cp = ((c & 0x1F) << 6) | (s[i + 1] & 0x3F); len = 2; }
        else if ((c & 0xF0) == 0xE0 && i + 2 < n) { cp = ((c & 0x0F) << 12) | ((s[i + 1] & 0x3F) << 6) | (s[i + 2] & 0x3F); len = 3; }
        else if ((c & 0xF8) == 0xF0 && i + 3 < n) { cp = ((c & 0x07) << 18) | ((s[i + 1] & 0x3F) << 12) | ((s[i + 2] & 0x3F) << 6) | (s[i + 3] & 0x3F); len = 4; }
        else { cp = 0xFFFD; len = 1; }
        i += len;
        if (cp >= 0x10000) { cp -= 0x10000; u.push_back((jchar)(0xD800 + (cp >> 10))); u.push_back((jchar)(0xDC00 + (cp & 0x3FF))); }
        else u.push_back((jchar)cp);
    }
    return env->NewString(u.data(), (jsize)u.size());
}

fv::Bytes toBytes(JNIEnv* env, jbyteArray a) {
    fv::Bytes out;
    if (!a) return out;
    jsize n = env->GetArrayLength(a);
    out.resize((size_t)n);
    if (n) env->GetByteArrayRegion(a, 0, n, reinterpret_cast<jbyte*>(out.data()));
    return out;
}

jbyteArray fromBytes(JNIEnv* env, const uint8_t* p, size_t n) {
    jbyteArray a = env->NewByteArray((jsize)n);
    if (a && n) env->SetByteArrayRegion(a, 0, (jsize)n, reinterpret_cast<const jbyte*>(p));
    return a;
}

bool clearException(JNIEnv* env) {
    if (!env->ExceptionCheck()) return false;
    env->ExceptionClear();
    return true;
}

std::string wireEntry(const fv::DirEntry& e) {
    // Same shape as DirEntryWire.encode(): kind|size|mtimeSeconds|name   (kind: F file, D folder, L symlink --
    // an L entry only ever comes out of nativeListSymlinks, never out of nativeListDirectory)
    return std::string(e.isSymlink ? "L|" : e.isDir ? "D|" : "F|") + std::to_string(e.isDir ? 0 : e.size) + "|" +
           std::to_string(e.mtimeMs / 1000) + "|" + e.name;
}

bool parseWire(const std::string& raw, fv::DirEntry& e) {
    size_t a = raw.find('|');
    if (a == std::string::npos) return false;
    size_t b = raw.find('|', a + 1);
    if (b == std::string::npos) return false;
    size_t c = raw.find('|', b + 1);
    if (c == std::string::npos) return false;
    e.isDir = raw.compare(0, a, "D") == 0;
    e.isSymlink = raw.compare(0, a, "L") == 0;
    e.size = std::strtoll(raw.substr(a + 1, b - a - 1).c_str(), nullptr, 10);
    e.mtimeMs = std::strtoll(raw.substr(b + 1, c - b - 1).c_str(), nullptr, 10) * 1000;
    e.name = raw.substr(c + 1);
    return true;
}

// -------------------------------------------------- core hooks (NFC, log) --

jclass g_normalizerClass = nullptr;
jclass g_normalizerFormClass = nullptr;
jmethodID g_normalizeMethod = nullptr;
jobject g_formNfc = nullptr;

std::string nfcViaJava(const std::string& s) {
    JNIEnv* env = threadEnv();
    if (!env || !g_normalizeMethod) return s;
    jstring in = fromUtf8(env, s);
    jstring out = (jstring)env->CallStaticObjectMethod(g_normalizerClass, g_normalizeMethod, in, g_formNfc);
    if (clearException(env) || !out) { env->DeleteLocalRef(in); return s; }
    std::string r = toUtf8(env, out);
    env->DeleteLocalRef(in);
    env->DeleteLocalRef(out);
    return r;
}

void logToAndroid(fv::LogLevel lvl, const char* tag, const std::string& msg) {
    int prio = lvl == fv::LogLevel::Error ? ANDROID_LOG_ERROR : lvl == fv::LogLevel::Warn ? ANDROID_LOG_WARN
             : lvl == fv::LogLevel::Info ? ANDROID_LOG_INFO : ANDROID_LOG_DEBUG;
    __android_log_print(prio, tag, "%s", msg.c_str());
}

// ----------------------------------------------------- Kotlin-backed storage --

class JniStorage final : public fv::Storage {
public:
    JniStorage(JNIEnv* env, jobject cb) {
        obj_ = env->NewGlobalRef(cb);
        jclass c = env->GetObjectClass(cb);
        auto m = [&](const char* name, const char* sig) {
            jmethodID id = env->GetMethodID(c, name, sig);
            if (!id) { env->ExceptionClear(); __android_log_print(ANDROID_LOG_ERROR, TAG, "missing callback %s%s", name, sig); }
            return id;
        };
        list_ = m("list", "(Ljava/lang/String;)[Ljava/lang/String;");
        stat_ = m("stat", "(Ljava/lang/String;)Ljava/lang/String;");
        mkdir_ = m("mkdir", "(Ljava/lang/String;)Z");
        createFile_ = m("createFile", "(Ljava/lang/String;)Z");
        rename_ = m("rename", "(Ljava/lang/String;Ljava/lang/String;)Z");
        remove_ = m("remove", "(Ljava/lang/String;)Z");
        setMtime_ = m("setMtime", "(Ljava/lang/String;J)Z");
        readWhole_ = m("readWhole", "(Ljava/lang/String;)[B");
        writeWhole_ = m("writeWhole", "(Ljava/lang/String;[B)Z");
        writeAtomic_ = m("writeWholeAtomic", "(Ljava/lang/String;[B)Z");
        writeBlock_ = m("writeBlock", "(Ljava/lang/String;[B)Z");
        ensure_ = m("ensureContentReady", "(Ljava/lang/String;)V");
        openRead_ = m("openRead", "(Ljava/lang/String;Ljava/lang/String;)I");
        openWrite_ = m("openWrite", "(Ljava/lang/String;Z)I");
        pending_ = m("markWritePending", "(Ljava/lang/String;)V");
        publish_ = m("publishWrite", "(Ljava/lang/String;Z)Z");
        invalidate_ = m("invalidate", "(Ljava/lang/String;)V");
        invalidateAll_ = m("invalidateAll", "()V");
        space_ = m("spaceInfo", "()[J");
        close_ = m("close", "()V");
        env->DeleteLocalRef(c);
    }
    ~JniStorage() override {
        JNIEnv* env = threadEnv();
        if (env && obj_) env->DeleteGlobalRef(obj_);
    }

    bool list(const std::string& dir, std::vector<fv::DirEntry>& out) override {
        JNIEnv* env = threadEnv(); if (!env) return false;
        jstring jd = fromUtf8(env, dir);
        jobjectArray arr = (jobjectArray)env->CallObjectMethod(obj_, list_, jd);
        env->DeleteLocalRef(jd);
        if (clearException(env) || !arr) return false;
        out.clear();
        jsize n = env->GetArrayLength(arr);
        for (jsize i = 0; i < n; i++) {
            jstring s = (jstring)env->GetObjectArrayElement(arr, i);
            fv::DirEntry e;
            if (s && parseWire(toUtf8(env, s), e)) out.push_back(std::move(e));
            if (s) env->DeleteLocalRef(s);
        }
        env->DeleteLocalRef(arr);
        return true;
    }
    bool stat(const std::string& path, fv::DirEntry& out) override {
        JNIEnv* env = threadEnv(); if (!env) return false;
        jstring jp = fromUtf8(env, path);
        jstring r = (jstring)env->CallObjectMethod(obj_, stat_, jp);
        env->DeleteLocalRef(jp);
        if (clearException(env) || !r) return false;
        bool ok = parseWire(toUtf8(env, r), out);
        env->DeleteLocalRef(r);
        if (ok) out.name = fv::nameOf(path);
        return ok;
    }
    bool mkdir(const std::string& p) override { return call1(mkdir_, p); }
    bool createFile(const std::string& p) override { return call1(createFile_, p); }
    bool remove(const std::string& p) override { return call1(remove_, p); }
    bool rename(const std::string& a, const std::string& b) override {
        JNIEnv* env = threadEnv(); if (!env) return false;
        jstring ja = fromUtf8(env, a), jb = fromUtf8(env, b);
        jboolean r = env->CallBooleanMethod(obj_, rename_, ja, jb);
        env->DeleteLocalRef(ja); env->DeleteLocalRef(jb);
        return !clearException(env) && r;
    }
    bool setMtime(const std::string& p, int64_t sec) override {
        JNIEnv* env = threadEnv(); if (!env) return false;
        jstring jp = fromUtf8(env, p);
        jboolean r = env->CallBooleanMethod(obj_, setMtime_, jp, (jlong)sec);
        env->DeleteLocalRef(jp);
        return !clearException(env) && r;
    }
    bool readWhole(const std::string& p, fv::Bytes& out) override {
        JNIEnv* env = threadEnv(); if (!env) return false;
        jstring jp = fromUtf8(env, p);
        jbyteArray a = (jbyteArray)env->CallObjectMethod(obj_, readWhole_, jp);
        env->DeleteLocalRef(jp);
        if (clearException(env) || !a) return false;
        out = toBytes(env, a);
        env->DeleteLocalRef(a);
        return true;
    }
    bool writeWhole(const std::string& p, const uint8_t* d, size_t n) override { return callData(writeWhole_, p, d, n); }
    bool writeWholeAtomic(const std::string& p, const uint8_t* d, size_t n) override { return callData(writeAtomic_, p, d, n); }
    bool writeBlock(const std::string& p, const uint8_t* d, size_t n) override { return callData(writeBlock_, p, d, n); }
    void ensureContentReady(const std::string& p) override {
        JNIEnv* env = threadEnv(); if (!env) return;
        jstring jp = fromUtf8(env, p);
        env->CallVoidMethod(obj_, ensure_, jp);
        env->DeleteLocalRef(jp);
        clearException(env);
    }
    fv::FdFile openRead(const std::string& p, const std::string& hint) override {
        JNIEnv* env = threadEnv(); if (!env) return fv::FdFile();
        jstring jp = fromUtf8(env, p), jh = fromUtf8(env, hint);
        jint fd = env->CallIntMethod(obj_, openRead_, jp, jh);
        env->DeleteLocalRef(jp); env->DeleteLocalRef(jh);
        if (clearException(env) || fd < 0) return fv::FdFile();
        return fv::FdFile(fd);   // detached by Kotlin: ours to close
    }
    fv::FdFile openWrite(const std::string& p, bool truncate) override {
        JNIEnv* env = threadEnv(); if (!env) return fv::FdFile();
        jstring jp = fromUtf8(env, p);
        jint fd = env->CallIntMethod(obj_, openWrite_, jp, (jboolean)truncate);
        env->DeleteLocalRef(jp);
        if (clearException(env) || fd < 0) return fv::FdFile();
        return fv::FdFile(fd);
    }
    void markWritePending(const std::string& p) override {
        JNIEnv* env = threadEnv(); if (!env) return;
        jstring jp = fromUtf8(env, p);
        env->CallVoidMethod(obj_, pending_, jp);
        env->DeleteLocalRef(jp);
        clearException(env);
    }
    bool publishWrite(const std::string& p, bool defer) override {
        JNIEnv* env = threadEnv(); if (!env) return false;
        jstring jp = fromUtf8(env, p);
        jboolean r = env->CallBooleanMethod(obj_, publish_, jp, (jboolean)defer);
        env->DeleteLocalRef(jp);
        return !clearException(env) && r;
    }
    void invalidate(const std::string& p) override {
        JNIEnv* env = threadEnv(); if (!env) return;
        jstring jp = fromUtf8(env, p);
        env->CallVoidMethod(obj_, invalidate_, jp);
        env->DeleteLocalRef(jp);
        clearException(env);
    }
    void invalidateAll() override {
        JNIEnv* env = threadEnv(); if (!env) return;
        env->CallVoidMethod(obj_, invalidateAll_);
        clearException(env);
    }
    bool spaceInfo(int64_t& total, int64_t& free) override {
        JNIEnv* env = threadEnv(); if (!env) return false;
        jlongArray a = (jlongArray)env->CallObjectMethod(obj_, space_);
        if (clearException(env) || !a) return false;
        jlong v[2] = {0, 0};
        if (env->GetArrayLength(a) >= 2) env->GetLongArrayRegion(a, 0, 2, v);
        env->DeleteLocalRef(a);
        total = v[0]; free = v[1];
        return true;
    }
    void close() override {
        JNIEnv* env = threadEnv(); if (!env) return;
        env->CallVoidMethod(obj_, close_);
        clearException(env);
    }

private:
    bool call1(jmethodID m, const std::string& p) {
        JNIEnv* env = threadEnv(); if (!env) return false;
        jstring jp = fromUtf8(env, p);
        jboolean r = env->CallBooleanMethod(obj_, m, jp);
        env->DeleteLocalRef(jp);
        return !clearException(env) && r;
    }
    bool callData(jmethodID m, const std::string& p, const uint8_t* d, size_t n) {
        JNIEnv* env = threadEnv(); if (!env) return false;
        jstring jp = fromUtf8(env, p);
        jbyteArray a = fromBytes(env, d, n);
        jboolean r = a ? env->CallBooleanMethod(obj_, m, jp, a) : JNI_FALSE;
        env->DeleteLocalRef(jp);
        if (a) env->DeleteLocalRef(a);
        return !clearException(env) && r;
    }
    jobject obj_ = nullptr;
    jmethodID list_{}, stat_{}, mkdir_{}, createFile_{}, rename_{}, remove_{}, setMtime_{}, readWhole_{}, writeWhole_{},
        writeAtomic_{}, writeBlock_{}, ensure_{}, openRead_{}, openWrite_{}, pending_{}, publish_{}, invalidate_{},
        invalidateAll_{}, space_{}, close_{};
};

// -------------------------------------------- Java streams / progress glue --

class JniByteSource final : public fv::ByteSource {
public:
    JniByteSource(JNIEnv* env, jobject in) {
        in_ = env->NewGlobalRef(in);
        jclass c = env->FindClass("java/io/InputStream");
        read_ = env->GetMethodID(c, "read", "([BII)I");
        env->DeleteLocalRef(c);
        jbyteArray b = env->NewByteArray(kBuf);
        buf_ = (jbyteArray)env->NewGlobalRef(b);
        env->DeleteLocalRef(b);
    }
    ~JniByteSource() override {
        JNIEnv* env = threadEnv();
        if (env) { env->DeleteGlobalRef(in_); env->DeleteGlobalRef(buf_); }
    }
    int64_t read(uint8_t* out, size_t n) override {
        JNIEnv* env = threadEnv();
        if (!env) return -1;
        jint want = (jint)std::min<size_t>(n, kBuf);
        jint r = env->CallIntMethod(in_, read_, buf_, 0, want);
        if (clearException(env)) return -1;
        if (r < 0) return 0;   // EOF
        if (r > 0) env->GetByteArrayRegion(buf_, 0, r, reinterpret_cast<jbyte*>(out));
        return r;
    }
private:
    static constexpr jint kBuf = 1 << 20;
    jobject in_ = nullptr;
    jbyteArray buf_ = nullptr;
    jmethodID read_{};
};

// Maps core progress onto the app's existing copy/export bridges, with the
// same accounting the Kotlin engine used: a transfer that touches the data
// twice (read+write) reports half per pass unless it is single-pass.
class BridgeProgress final : public fv::Progress {
public:
    BridgeProgress(int opId, bool singlePass) : opId_(opId), single_(singlePass) {}
    void onWriteBack(uint64_t bytes) override {
        if (opId_ > 0) reportCopyProgress(opId_, single_ ? bytes : bytes / 2);
    }
    void onExtract(uint64_t bytes) override {
        if (opId_ <= 0) return;
        if (isExportTracking(opId_)) reportExportChunkProgress(opId_, bytes);
        else reportCopyProgress(opId_, single_ ? bytes : bytes / 2);
    }
    bool cancelled() override {
        return opId_ > 0 && (isCopyCancelled(opId_) || isExportCancelled(opId_));
    }
private:
    int opId_;
    bool single_;
};

// ------------------------------------------------------------- registry --

struct Holder { std::unique_ptr<fv::Vault> vault; };
std::mutex g_regMu;
std::unordered_map<jlong, std::shared_ptr<Holder>> g_registry;
std::atomic<jlong> g_nextHandle{1};

std::shared_ptr<Holder> lookup(jlong h) {
    std::lock_guard<std::mutex> g(g_regMu);
    auto it = g_registry.find(h);
    return it == g_registry.end() ? nullptr : it->second;
}

std::shared_ptr<fv::Storage> makeStorage(JNIEnv* env, jstring rawRoot, jobject cb) {
    if (rawRoot) return std::make_shared<fv::PosixStorage>(toUtf8(env, rawRoot));
    if (cb) return std::make_shared<JniStorage>(env, cb);
    return nullptr;
}

fv::HostEnv makeEnv(JNIEnv* env, jstring localState, jstring tempDir) {
    fv::HostEnv e;
    e.cryfsLocalStateDir = toUtf8(env, localState);
    e.tempDir = toUtf8(env, tempDir);
    return e;
}

void setOut(JNIEnv* env, jobjectArray out, jsize idx, jobject v) {
    if (out && env->GetArrayLength(out) > idx) env->SetObjectArrayElement(out, idx, v);
}

struct PwGuard {
    fv::Bytes b;
    ~PwGuard() { fv::secureZero(b.data(), b.size()); }
};

#define FV_JNI(ret, name) extern "C" JNIEXPORT ret JNICALL Java_com_aeidolon_vaultexplorer_foldervault_NativeFolderVault_##name

}  // namespace

// ================================================================ exports ==

FV_JNI(void, nativeInit)(JNIEnv* env, jclass) {
    static std::once_flag once;
    std::call_once(once, [&] {
        fv::setLogger(logToAndroid);
        jclass n = env->FindClass("java/text/Normalizer");
        jclass f = env->FindClass("java/text/Normalizer$Form");
        if (n && f) {
            g_normalizerClass = (jclass)env->NewGlobalRef(n);
            g_normalizerFormClass = (jclass)env->NewGlobalRef(f);
            g_normalizeMethod = env->GetStaticMethodID(n, "normalize",
                "(Ljava/lang/CharSequence;Ljava/text/Normalizer$Form;)Ljava/lang/String;");
            jfieldID nfc = env->GetStaticFieldID(f, "NFC", "Ljava/text/Normalizer$Form;");
            jobject nv = nfc ? env->GetStaticObjectField(f, nfc) : nullptr;
            if (nv) g_formNfc = env->NewGlobalRef(nv);
            if (g_normalizeMethod && g_formNfc) fv::setNfcNormalizer(nfcViaJava);
        }
        clearException(env);
    });
}

// format: 0 gocryptfs, 1 cryptomator, 2 cryfs.  Returns a handle (> 0), or
// 0 = invalid vault, -1 = wrong password; out[0] = message, out[1] = CryFS
// derived key bytes.
FV_JNI(jlong, nativeOpen)(JNIEnv* env, jclass, jint format, jstring rawRoot, jobject bootstrap, jobject sessionProvider,
                          jbyteArray password, jboolean readOnly, jstring localState, jstring tempDir,
                          jbyteArray combinedKey, jobjectArray out) {
    PwGuard pw{toBytes(env, password)};
    PwGuard ck{toBytes(env, combinedKey)};
    auto st = makeStorage(env, rawRoot, bootstrap);
    if (!st) { setOut(env, out, 0, fromUtf8(env, "No storage available")); return 0; }
    fv::HostEnv henv = makeEnv(env, localState, tempDir);

    fv::StorageFactory factory;
    jobject provider = sessionProvider ? env->NewGlobalRef(sessionProvider) : nullptr;
    if (provider) {
        factory = [provider]() -> std::shared_ptr<fv::Storage> {
            JNIEnv* e = threadEnv();
            if (!e) return nullptr;
            jclass c = e->GetObjectClass(provider);
            jmethodID m = e->GetMethodID(c, "buildSessionStorage", "()Lcom/aeidolon/vaultexplorer/foldervault/FolderVaultStorage;");
            e->DeleteLocalRef(c);
            if (!m) { clearException(e); throw fv::Error(fv::Err::Io, "storage provider is missing buildSessionStorage"); }
            jobject s = e->CallObjectMethod(provider, m);
            if (e->ExceptionCheck()) {
                jthrowable t = e->ExceptionOccurred();
                e->ExceptionClear();
                std::string msg = "Could not set up vault storage";
                jclass tc = e->GetObjectClass(t);
                jmethodID gm = e->GetMethodID(tc, "getMessage", "()Ljava/lang/String;");
                if (gm) { jstring jm = (jstring)e->CallObjectMethod(t, gm); if (jm) { msg = toUtf8(e, jm); e->DeleteLocalRef(jm); } }
                clearException(e);
                e->DeleteLocalRef(tc); e->DeleteLocalRef(t);
                throw fv::Error(fv::Err::Io, msg);
            }
            if (!s) return nullptr;
            auto js = std::make_shared<JniStorage>(e, s);
            e->DeleteLocalRef(s);
            return js;
        };
    }

    fv::OpenResult r;
    switch (format) {
        case 0: r = fv::openGocryptfs(st, pw.b.data(), pw.b.size(), readOnly, henv, factory); break;
        case 1: r = fv::openCryptomator(st, pw.b.data(), pw.b.size(), readOnly, henv, factory); break;
        default:
            r = ck.b.empty() ? fv::openCryfs(st, pw.b.data(), pw.b.size(), readOnly, henv, factory)
                             : fv::openCryfsWithCombinedKey(st, ck.b.data(), ck.b.size(), readOnly, henv, factory);
            break;
    }
    if (provider) env->DeleteGlobalRef(provider);
    if (r.status != fv::OpenStatus::Ok || !r.vault) {
        setOut(env, out, 0, fromUtf8(env, r.message));
        return r.status == fv::OpenStatus::WrongPassword ? -1 : 0;
    }
    if (!r.derivedKey.empty()) setOut(env, out, 1, fromBytes(env, r.derivedKey.data(), r.derivedKey.size()));
    auto h = std::make_shared<Holder>();
    h->vault = std::move(r.vault);
    jlong id = g_nextHandle.fetch_add(1);
    std::lock_guard<std::mutex> g(g_regMu);
    g_registry[id] = std::move(h);
    return id;
}

// options: gocryptfs [cipher 0..2, plaintextNames 0/1, deterministicNames 0/1, longNameMax 0|62..255]
// (the last two are optional, older callers pass two); cryfs [blocksize, 0]; cipherName for cryfs.
// Returns fv::OpenStatus as int (0 Ok, 1 WrongPassword, 2 InvalidVault); out[0] = message.
FV_JNI(jint, nativeCreate)(JNIEnv* env, jclass, jint format, jstring rawRoot, jobject storageCb, jbyteArray password,
                           jintArray options, jstring cipherName, jstring localState, jstring tempDir,
                           jbyteArray userEntropy, jobjectArray out) {
    ScopedJniUserEntropy entropyScope(env, userEntropy);
    PwGuard pw{toBytes(env, password)};
    auto st = makeStorage(env, rawRoot, storageCb);
    if (!st) { setOut(env, out, 0, fromUtf8(env, "No storage available")); return 2; }
    jint opt[4] = {0, 0, 0, 0};
    if (options) {
        jsize n = env->GetArrayLength(options);
        if (n >= 2) env->GetIntArrayRegion(options, 0, n < 4 ? n : 4, opt);
    }
    fv::PlainResult r;
    if (format == 0) {
        fv::GocryptfsCreateOptions o;
        o.cipher = opt[0] == 1 ? fv::GocryptfsCipher::XChaCha20Poly1305 : opt[0] == 2 ? fv::GocryptfsCipher::AesSiv : fv::GocryptfsCipher::Aes256Gcm;
        o.plaintextNames = opt[1] != 0;
        o.deterministicNames = opt[2] != 0;
        o.longNameMax = opt[3];
        r = fv::createGocryptfs(*st, pw.b.data(), pw.b.size(), o);
    } else if (format == 1) {
        r = fv::createCryptomator(*st, pw.b.data(), pw.b.size());
    } else {
        fv::CryfsCreateOptions o;
        std::string cn = toUtf8(env, cipherName);
        if (!cn.empty()) o.cipher = cn;
        if (opt[0] > 0) o.blocksizeBytes = opt[0];
        r = fv::createCryfs(*st, pw.b.data(), pw.b.size(), o, makeEnv(env, localState, tempDir));
    }
    st->close();
    if (r.status != fv::OpenStatus::Ok) setOut(env, out, 0, fromUtf8(env, r.message));
    return (jint)r.status == 0 ? 0 : (r.status == fv::OpenStatus::WrongPassword ? 1 : 2);
}

FV_JNI(jint, nativeChangePassword)(JNIEnv* env, jclass, jint format, jstring rawRoot, jobject storageCb,
                                   jbyteArray oldPw, jbyteArray newPw, jobjectArray out) {
    PwGuard o{toBytes(env, oldPw)}, n{toBytes(env, newPw)};
    auto st = makeStorage(env, rawRoot, storageCb);
    if (!st) { setOut(env, out, 0, fromUtf8(env, "No storage available")); return 2; }
    fv::PlainResult r;
    if (format == 0) r = fv::changeGocryptfsPassword(*st, o.b.data(), o.b.size(), n.b.data(), n.b.size());
    else if (format == 1) r = fv::changeCryptomatorPassword(*st, o.b.data(), o.b.size(), n.b.data(), n.b.size());
    else r = fv::changeCryfsPassword(*st, o.b.data(), o.b.size(), n.b.data(), n.b.size());
    st->close();
    if (r.status != fv::OpenStatus::Ok) setOut(env, out, 0, fromUtf8(env, r.message));
    return r.status == fv::OpenStatus::Ok ? 0 : (r.status == fv::OpenStatus::WrongPassword ? 1 : 2);
}

// Cryptomator format 7 -> 8 (one way). Same result codes as nativeChangePassword: 0 ok, 1 wrong password, 2 other
// failure (message in out[0]).
FV_JNI(jint, nativeMigrateCryptomator)(JNIEnv* env, jclass, jstring rawRoot, jobject storageCb, jbyteArray pw,
                                       jobjectArray out) {
    PwGuard p{toBytes(env, pw)};
    auto st = makeStorage(env, rawRoot, storageCb);
    if (!st) { setOut(env, out, 0, fromUtf8(env, "No storage available")); return 2; }
    fv::PlainResult r = fv::migrateCryptomator7To8(*st, p.b.data(), p.b.size());
    st->close();
    if (r.status != fv::OpenStatus::Ok) setOut(env, out, 0, fromUtf8(env, r.message));
    return r.status == fv::OpenStatus::Ok ? 0 : (r.status == fv::OpenStatus::WrongPassword ? 1 : 2);
}

FV_JNI(void, nativeClose)(JNIEnv*, jclass, jlong h) {
    std::shared_ptr<Holder> holder;
    {
        std::lock_guard<std::mutex> g(g_regMu);
        auto it = g_registry.find(h);
        if (it == g_registry.end()) return;
        holder = std::move(it->second);
        g_registry.erase(it);
    }
    holder->vault->close();   // waits for in-flight calls, wipes keys
}

FV_JNI(jobjectArray, nativeListDirectory)(JNIEnv* env, jclass, jlong h, jstring path) {
    auto v = lookup(h);
    if (!v) return nullptr;
    std::vector<fv::DirEntry> es;
    if (!v->vault->listDirectory(toUtf8(env, path), es)) return nullptr;
    jclass sc = env->FindClass("java/lang/String");
    jobjectArray arr = env->NewObjectArray((jsize)es.size(), sc, nullptr);
    for (size_t i = 0; i < es.size(); i++) {
        jstring s = fromUtf8(env, wireEntry(es[i]));
        env->SetObjectArrayElement(arr, (jsize)i, s);
        env->DeleteLocalRef(s);
    }
    env->DeleteLocalRef(sc);
    return arr;
}

// Symlinks live outside nativeListDirectory on purpose (see Vault::listSymlinks): only callers that know how to
// show one ask for them. Same wire shape as the directory listing, kind "L", size = target length in bytes.
FV_JNI(jobjectArray, nativeListSymlinks)(JNIEnv* env, jclass, jlong h, jstring path) {
    auto v = lookup(h);
    if (!v) return nullptr;
    std::vector<fv::DirEntry> es;
    if (!v->vault->listSymlinks(toUtf8(env, path), es)) return nullptr;
    jclass sc = env->FindClass("java/lang/String");
    jobjectArray arr = env->NewObjectArray((jsize)es.size(), sc, nullptr);
    for (size_t i = 0; i < es.size(); i++) {
        jstring s = fromUtf8(env, wireEntry(es[i]));
        env->SetObjectArrayElement(arr, (jsize)i, s);
        env->DeleteLocalRef(s);
    }
    env->DeleteLocalRef(sc);
    return arr;
}

FV_JNI(jstring, nativeReadSymlink)(JNIEnv* env, jclass, jlong h, jstring path) {
    auto v = lookup(h);
    if (!v) return nullptr;
    auto t = v->vault->readSymlink(toUtf8(env, path));
    return t ? fromUtf8(env, *t) : nullptr;
}

FV_JNI(jboolean, nativeCreateSymlink)(JNIEnv* env, jclass, jlong h, jstring path, jstring target) {
    auto v = lookup(h);
    return v && v->vault->createSymlink(toUtf8(env, path), toUtf8(env, target));
}

FV_JNI(jint, nativeHiddenEntryCount)(JNIEnv* env, jclass, jlong h, jstring path) {
    auto v = lookup(h);
    return v ? (jint)v->vault->hiddenEntryCount(toUtf8(env, path)) : -1;
}

#define FV_BOOL1(name, call) \
    FV_JNI(jboolean, name)(JNIEnv* env, jclass, jlong h, jstring a) { \
        auto v = lookup(h); return v && v->vault->call(toUtf8(env, a)); }
FV_BOOL1(nativeCreateDirectory, createDirectory)
FV_BOOL1(nativeDeleteFile, deleteFile)
FV_BOOL1(nativeFinishWrite, finishWrite)

FV_JNI(jboolean, nativeRenameFile)(JNIEnv* env, jclass, jlong h, jstring a, jstring b) {
    auto v = lookup(h);
    return v && v->vault->renameFile(toUtf8(env, a), toUtf8(env, b));
}
FV_JNI(jboolean, nativeSetLastModified)(JNIEnv* env, jclass, jlong h, jstring p, jlong sec) {
    auto v = lookup(h);
    return v && v->vault->setLastModifiedTime(toUtf8(env, p), sec);
}
FV_JNI(jlong, nativeGetFileSize)(JNIEnv* env, jclass, jlong h, jstring p) {
    auto v = lookup(h);
    return v ? v->vault->getFileSize(toUtf8(env, p)) : -1;
}
FV_JNI(jlong, nativeGetFolderSize)(JNIEnv* env, jclass, jlong h, jstring p) {
    auto v = lookup(h);
    return v ? v->vault->getFolderSize(toUtf8(env, p)) : 0;
}
FV_JNI(jbyteArray, nativeReadFileChunk)(JNIEnv* env, jclass, jlong h, jstring p, jlong off, jint len) {
    auto v = lookup(h);
    if (!v) return nullptr;
    auto r = v->vault->readFileChunk(toUtf8(env, p), off, len);
    if (!r) return nullptr;
    return fromBytes(env, r->data(), r->size());
}
FV_JNI(jboolean, nativeWriteFileChunk)(JNIEnv* env, jclass, jlong h, jstring p, jlong off, jbyteArray data) {
    auto v = lookup(h);
    if (!v) return JNI_FALSE;
    fv::Bytes b = toBytes(env, data);
    bool ok = v->vault->writeFileChunk(toUtf8(env, p), off, b.data(), b.size());
    fv::secureZero(b.data(), b.size());
    return ok;
}
FV_JNI(jboolean, nativeWriteBackFile)(JNIEnv* env, jclass, jlong h, jstring p, jstring src, jint opId, jboolean single) {
    auto v = lookup(h);
    if (!v) return JNI_FALSE;
    BridgeProgress prog(opId, single);
    return v->vault->writeBackFile(toUtf8(env, p), toUtf8(env, src), &prog);
}
FV_JNI(jboolean, nativeImportStream)(JNIEnv* env, jclass, jlong h, jstring p, jobject in) {
    auto v = lookup(h);
    if (!v) return JNI_FALSE;
    JniByteSource src(env, in);
    return v->vault->importStream(toUtf8(env, p), src, nullptr);
}
FV_JNI(jboolean, nativeExtractFile)(JNIEnv* env, jclass, jlong h, jstring p, jstring dest, jint opId, jboolean single) {
    auto v = lookup(h);
    if (!v) return JNI_FALSE;
    BridgeProgress prog(opId, single);
    return v->vault->extractFile(toUtf8(env, p), toUtf8(env, dest), &prog);
}

FV_JNI(void, nativeBeginBatchWrite)(JNIEnv*, jclass, jlong h) { if (auto v = lookup(h)) v->vault->beginBatchWrite(); }
FV_JNI(void, nativeEndBatchWrite)(JNIEnv*, jclass, jlong h) { if (auto v = lookup(h)) v->vault->endBatchWrite(); }
FV_JNI(void, nativeBeginBatchDelete)(JNIEnv*, jclass, jlong h) { if (auto v = lookup(h)) v->vault->beginBatchDelete(); }
FV_JNI(void, nativeEndBatchDelete)(JNIEnv*, jclass, jlong h) { if (auto v = lookup(h)) v->vault->endBatchDelete(); }
FV_JNI(void, nativeInvalidateCache)(JNIEnv* env, jclass, jlong h, jstring p) {
    if (auto v = lookup(h)) v->vault->invalidateCache(toUtf8(env, p));
}

FV_JNI(jlongArray, nativeSpaceInfo)(JNIEnv* env, jclass, jlong h) {
    auto v = lookup(h);
    int64_t total = 0, free = 0;
    if (!v || !v->vault->spaceInfo(total, free)) return nullptr;
    jlongArray a = env->NewLongArray(2);
    jlong x[2] = {total, free};
    env->SetLongArrayRegion(a, 0, 2, x);
    return a;
}

// Flat array of triples: key, kind ("s" | "i" | "b"), value.
FV_JNI(jobjectArray, nativeInfo)(JNIEnv* env, jclass, jlong h) {
    auto v = lookup(h);
    if (!v) return nullptr;
    auto items = v->vault->info();
    jclass sc = env->FindClass("java/lang/String");
    jobjectArray arr = env->NewObjectArray((jsize)items.size() * 3, sc, nullptr);
    jsize i = 0;
    for (auto& it : items) {
        const char* kind = it.kind == fv::InfoItem::Kind::Int ? "i" : it.kind == fv::InfoItem::Kind::Bool ? "b" : "s";
        jstring k = fromUtf8(env, it.key), kd = fromUtf8(env, kind), val = fromUtf8(env, it.value);
        env->SetObjectArrayElement(arr, i++, k);
        env->SetObjectArrayElement(arr, i++, kd);
        env->SetObjectArrayElement(arr, i++, val);
        env->DeleteLocalRef(k); env->DeleteLocalRef(kd); env->DeleteLocalRef(val);
    }
    env->DeleteLocalRef(sc);
    return arr;
}

// Key export for the Kotlin check & repair tooling: String[] of
// "f:<name>:<base64>" and "s:<name>:<value>" entries.
FV_JNI(jobjectArray, nativeExportKeys)(JNIEnv* env, jclass, jlong h) {
    auto v = lookup(h);
    if (!v) return nullptr;
    fv::KeyExport k = v->vault->exportKeys();
    jclass sc = env->FindClass("java/lang/String");
    jobjectArray arr = env->NewObjectArray((jsize)(k.fields.size() + k.strings.size()), sc, nullptr);
    jsize i = 0;
    for (auto& f : k.fields) {
        std::string line = "f:" + f.first + ":" + fv::base64Encode(f.second.data(), f.second.size(), false, true);
        jstring s = fromUtf8(env, line);
        env->SetObjectArrayElement(arr, i++, s);
        env->DeleteLocalRef(s);
        std::string tmp; tmp.swap(line); fv::secureZero(tmp.data(), tmp.size());
    }
    for (auto& s2 : k.strings) {
        jstring s = fromUtf8(env, "s:" + s2.first + ":" + s2.second);
        env->SetObjectArrayElement(arr, i++, s);
        env->DeleteLocalRef(s);
    }
    for (auto& f : k.fields) fv::secureZero(f.second.data(), f.second.size());
    env->DeleteLocalRef(sc);
    return arr;
}
