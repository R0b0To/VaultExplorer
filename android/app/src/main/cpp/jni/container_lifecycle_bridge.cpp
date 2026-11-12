// JNI bridge: container lifecycle -- creating new VeraCrypt/LUKS containers
// (file-backed and USB-backed, plain and hidden-volume variants) and
// changing an existing container's password. See crypto_bridge.cpp's header
// comment for why splitting vaultexplorer.cpp this way doesn't require any
// Kotlin/Dart changes.

#include <jni.h>
#include <cstring>
#include <vector>

#include "container_create.h"
#include "crypto/keyfile_mixing.h"

#include "jni_bridge_common.h"

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_createContainerNative(
        JNIEnv* env, jobject,
        jint fd, jstring password, jint pim, jlong sizeBytes, jstring fileSystem,
        jint containerFormat, jint cipherId, jint hashId, jintArray keyfileFds,
        jboolean quickFormat, jbyteArray userEntropy) {
    JNI_TRY
    ScopedJniUserEntropy entropyScope(env, userEntropy);

    std::vector<int> kfFds = extractKeyfileFds(env, keyfileFds);
    const char* nativePass = vcGetPasswordUtf8(env, password);
    const char* nativeFS   = env->GetStringUTFChars(fileSystem, nullptr);

    bool success;
    if (containerFormat == 1 || containerFormat == 2) {
        // 1 = LUKS1, 2 = LUKS2 — see ContainerFormat (container_format.h).
        success = createLuksContainer(fd, nativePass, pim, static_cast<int64_t>(sizeBytes),
                                      nativeFS, containerFormat, cipherId, hashId,
                                      kfFds.empty() ? nullptr : kfFds.data(),
                                      static_cast<int>(kfFds.size()),
                                      quickFormat);
    } else {
        success = createContainer(fd, nativePass, pim, static_cast<int64_t>(sizeBytes),
                                  nativeFS, cipherId, hashId,
                                  kfFds.empty() ? nullptr : kfFds.data(),
                                  static_cast<int>(kfFds.size()),
                                  quickFormat);
    }

    vcReleasePasswordUtf8(nativePass);
    env->ReleaseStringUTFChars(fileSystem, nativeFS);

    return success ? JNI_TRUE : JNI_FALSE;

    JNI_CATCH_RETURN(JNI_FALSE)
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_createContainerWithHiddenNative(
        JNIEnv* env, jobject,
        jint fd, jstring outerPassword, jstring hiddenPassword,
        jint outerPim, jint hiddenPim, jlong sizeBytes, jstring outerFileSystem, jstring hiddenFileSystem,
        jlong hiddenSizeBytes,
        jint outerCipherId, jint outerHashId,
        jint hiddenCipherId, jint hiddenHashId,
        jintArray outerKeyfileFds, jintArray hiddenKeyfileFds,
        jboolean quickFormat, jbyteArray userEntropy) {
    JNI_TRY
    ScopedJniUserEntropy entropyScope(env, userEntropy);

    std::vector<int> outerKfFds = extractKeyfileFds(env, outerKeyfileFds);
    std::vector<int> hiddenKfFds = extractKeyfileFds(env, hiddenKeyfileFds);
    
    const char* nativeOuterPass = vcGetPasswordUtf8(env, outerPassword);
    const char* nativeHiddenPass = vcGetPasswordUtf8(env, hiddenPassword);
    const char* nativeOuterFS   = env->GetStringUTFChars(outerFileSystem, nullptr);
    const char* nativeHiddenFS   = env->GetStringUTFChars(hiddenFileSystem, nullptr);

    bool success = createContainerWithHidden(fd, nativeOuterPass, nativeHiddenPass, outerPim, hiddenPim, static_cast<int64_t>(sizeBytes),
                                             nativeOuterFS, nativeHiddenFS, static_cast<int64_t>(hiddenSizeBytes),
                                             outerCipherId, outerHashId,
                                             hiddenCipherId, hiddenHashId,
                                             outerKfFds.empty() ? nullptr : outerKfFds.data(), static_cast<int>(outerKfFds.size()),
                                             hiddenKfFds.empty() ? nullptr : hiddenKfFds.data(), static_cast<int>(hiddenKfFds.size()),
                                             quickFormat);

    vcReleasePasswordUtf8(nativeOuterPass);
    vcReleasePasswordUtf8(nativeHiddenPass);
    env->ReleaseStringUTFChars(outerFileSystem, nativeOuterFS);
    env->ReleaseStringUTFChars(hiddenFileSystem, nativeHiddenFS);

    return success ? JNI_TRUE : JNI_FALSE;

    JNI_CATCH_RETURN(JNI_FALSE)
}

#include "partition_writer.h"

// Builds a Map<String, Any?> from a UsbCreateResult, following the same
// HashMap-construction pattern as getVaultInfo (filesystem_bridge.cpp).
// Used by both createUsbContainerNative and createUsbContainerWithHiddenNative
// below -- kept `static` in this file rather than in jni_bridge_common.h per
// that header's own stated policy (shared across files goes there; shared
// within one file stays local).
//
// Keys: "success" (Boolean), "phase" (String), "errorCode" (String, only
// when !success), "errorMessage" (String, only when !success),
// "offsetBytes"/"sector" (Long, only when !success), "sectorCount" (Integer,
// only when !success). NativeEngine.createUsbContainerNative's doc comment
// documents this shape for the Kotlin side.
static jobject buildUsbCreateResultMap(JNIEnv* env, const UsbCreateResult& r) {
    jclass mapClass = env->FindClass("java/util/HashMap");
    jmethodID mapInit = env->GetMethodID(mapClass, "<init>", "()V");
    jmethodID mapPut = env->GetMethodID(mapClass, "put",
        "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");
    jobject result = env->NewObject(mapClass, mapInit);

    jclass boolClass = env->FindClass("java/lang/Boolean");
    jmethodID boolInit = env->GetMethodID(boolClass, "<init>", "(Z)V");
    jclass longClass = env->FindClass("java/lang/Long");
    jmethodID longInit = env->GetMethodID(longClass, "<init>", "(J)V");
    jclass intClass = env->FindClass("java/lang/Integer");
    jmethodID intInit = env->GetMethodID(intClass, "<init>", "(I)V");

    auto putBool = [&](const char* key, bool value) {
        jstring k = env->NewStringUTF(key);
        jobject boxed = env->NewObject(boolClass, boolInit, static_cast<jboolean>(value));
        env->CallObjectMethod(result, mapPut, k, boxed);
        env->DeleteLocalRef(k);
        env->DeleteLocalRef(boxed);
    };
    auto putLong = [&](const char* key, int64_t value) {
        jstring k = env->NewStringUTF(key);
        jobject boxed = env->NewObject(longClass, longInit, static_cast<jlong>(value));
        env->CallObjectMethod(result, mapPut, k, boxed);
        env->DeleteLocalRef(k);
        env->DeleteLocalRef(boxed);
    };
    auto putInt = [&](const char* key, int value) {
        jstring k = env->NewStringUTF(key);
        jobject boxed = env->NewObject(intClass, intInit, static_cast<jint>(value));
        env->CallObjectMethod(result, mapPut, k, boxed);
        env->DeleteLocalRef(k);
        env->DeleteLocalRef(boxed);
    };
    auto putString = [&](const char* key, const std::string& value) {
        jstring k = env->NewStringUTF(key);
        jstring v = env->NewStringUTF(value.c_str());
        env->CallObjectMethod(result, mapPut, k, v);
        env->DeleteLocalRef(k);
        env->DeleteLocalRef(v);
    };

    putBool("success", r.success);
    putString("phase", usbCreatePhaseName(r.phase));
    if (!r.success) {
        putString("errorCode", r.errorCode);
        putString("errorMessage", r.errorMessage);
        putLong("offsetBytes", static_cast<int64_t>(r.offsetBytes));
        putLong("sector", static_cast<int64_t>(r.sector));
        putInt("sectorCount", static_cast<int>(r.sectorCount));
    }
    return result;
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_createUsbContainerNative(
        JNIEnv* env, jobject,
        jint volId, jstring partitionScheme, jstring password, jint pim, jlong sizeBytes, jstring fileSystem,
        jint containerFormat, jint cipherId, jint hashId, jintArray keyfileFds, jboolean quickFormat,
        jlong deviceSectorCount, jstring operationId, jbyteArray userEntropy, jint deviceSectorSize) {
    JNI_TRY
    ScopedJniUserEntropy entropyScope(env, userEntropy);

    if (volId < 0 || volId >= MAX_VOLUMES) {
        return buildUsbCreateResultMap(env, UsbCreateResult::Fail(
            UsbCreatePhase::kValidate, "USB_INVALID_VOLUME_ID", "Invalid internal volume id"));
    }

    std::vector<int> kfFds = extractKeyfileFds(env, keyfileFds);
    const char* nativePass = vcGetPasswordUtf8(env, password);
    const char* nativeFS   = env->GetStringUTFChars(fileSystem, nullptr);
    const char* nativeOpId = operationId ? env->GetStringUTFChars(operationId, nullptr) : nullptr;

    static constexpr uint64_t kUsbPartitionStartSector = 2048;   // 1 MiB, in the 512-byte units the native layer addresses
    // A drive with larger logical sectors (4Kn: 4096) counts them in its partition table, and the volume must be
    // a whole number of them: like desktop, the header and the file system use that sector size.
    const uint32_t sectorSize = (deviceSectorSize >= 512 && deviceSectorSize <= 4096 && deviceSectorSize % 512 == 0)
                                    ? static_cast<uint32_t>(deviceSectorSize) : 512u;
    int64_t usbSizeBytes = static_cast<int64_t>(sizeBytes);
    if (sectorSize > 512) usbSizeBytes -= usbSizeBytes % 4096;
    const uint64_t mbrStartSector = kUsbPartitionStartSector * 512 / sectorSize;
    const uint64_t numSectors = static_cast<uint64_t>(usbSizeBytes) / sectorSize;

    LOGI("[%s] createUsbContainerNative: volId=%d sizeBytes=%lld fs=%s format=%d numSectors=%llu deviceSectorCount=%lld",
         nativeOpId ? nativeOpId : "-", volId, (long long)sizeBytes, nativeFS, containerFormat,
         (unsigned long long)numSectors, (long long)deviceSectorCount);

    UsbCreateResult mbrResult = writeMbrPartitionTable(volId, mbrStartSector, numSectors,
                                                        static_cast<uint64_t>(deviceSectorCount));
    LOGI("[%s] createUsbContainerNative: writeMbrPartitionTable success=%d errorCode=%s",
         nativeOpId ? nativeOpId : "-", mbrResult.success ? 1 : 0, mbrResult.errorCode.c_str());

    UsbCreateResult createResult;
    if (mbrResult.success) {
        createResult = (containerFormat == 1 || containerFormat == 2)
            ? createUsbLuksContainer(volId, kUsbPartitionStartSector, nativePass, pim,
                                     usbSizeBytes, nativeFS,
                                     containerFormat, cipherId, hashId,
                                     kfFds.empty() ? nullptr : kfFds.data(), static_cast<int>(kfFds.size()), quickFormat,
                                     nativeOpId)
            : createUsbContainer(volId, kUsbPartitionStartSector, nativePass, pim,
                                 usbSizeBytes, nativeFS,
                                 cipherId, hashId,
                                 kfFds.empty() ? nullptr : kfFds.data(), static_cast<int>(kfFds.size()), quickFormat,
                                 nativeOpId, sectorSize);
    } else {
        closeUnusedKeyfileFds(kfFds.empty() ? nullptr : kfFds.data(), static_cast<int>(kfFds.size()));
        createResult = mbrResult;
    }

    LOGI("[%s] createUsbContainerNative: EXIT success=%d phase=%s",
         nativeOpId ? nativeOpId : "-", createResult.success ? 1 : 0, usbCreatePhaseName(createResult.phase));
    vcReleasePasswordUtf8(nativePass);
    env->ReleaseStringUTFChars(fileSystem, nativeFS);
    if (operationId && nativeOpId) env->ReleaseStringUTFChars(operationId, nativeOpId);
    return buildUsbCreateResultMap(env, createResult);

    JNI_CATCH_RETURN(nullptr)
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_createUsbContainerWithHiddenNative(
        JNIEnv* env, jobject,
        jint volId, jstring partitionScheme,
        jstring outerPassword, jstring hiddenPassword,
        jint outerPim, jint hiddenPim, jlong sizeBytes,
        jstring outerFileSystem, jstring hiddenFileSystem, jlong hiddenSizeBytes,
        jint outerCipherId, jint outerHashId, jint hiddenCipherId, jint hiddenHashId,
        jintArray outerKeyfileFds, jintArray hiddenKeyfileFds, jboolean quickFormat,
        jlong deviceSectorCount, jstring operationId, jbyteArray userEntropy, jint deviceSectorSize) {
    JNI_TRY
    ScopedJniUserEntropy entropyScope(env, userEntropy);

    if (volId < 0 || volId >= MAX_VOLUMES) {
        return buildUsbCreateResultMap(env, UsbCreateResult::Fail(
            UsbCreatePhase::kValidate, "USB_INVALID_VOLUME_ID", "Invalid internal volume id"));
    }

    std::vector<int> outerKfFds = extractKeyfileFds(env, outerKeyfileFds);
    std::vector<int> hiddenKfFds = extractKeyfileFds(env, hiddenKeyfileFds);
    
    const char* nativeOuterPass = vcGetPasswordUtf8(env, outerPassword);
    const char* nativeHiddenPass = vcGetPasswordUtf8(env, hiddenPassword);
    const char* nativeOuterFS   = env->GetStringUTFChars(outerFileSystem, nullptr);
    const char* nativeHiddenFS   = env->GetStringUTFChars(hiddenFileSystem, nullptr);
    const char* nativeOpId = operationId ? env->GetStringUTFChars(operationId, nullptr) : nullptr;

    static constexpr uint64_t kUsbPartitionStartSector = 2048;   // 1 MiB, in the 512-byte units the native layer addresses
    // A drive with larger logical sectors (4Kn: 4096) counts them in its partition table, and the volume must be
    // a whole number of them: like desktop, the header and the file system use that sector size.
    const uint32_t sectorSize = (deviceSectorSize >= 512 && deviceSectorSize <= 4096 && deviceSectorSize % 512 == 0)
                                    ? static_cast<uint32_t>(deviceSectorSize) : 512u;
    int64_t usbSizeBytes = static_cast<int64_t>(sizeBytes);
    if (sectorSize > 512) usbSizeBytes -= usbSizeBytes % 4096;
    const uint64_t mbrStartSector = kUsbPartitionStartSector * 512 / sectorSize;
    const uint64_t numSectors = static_cast<uint64_t>(usbSizeBytes) / sectorSize;

    UsbCreateResult mbrResult = writeMbrPartitionTable(volId, mbrStartSector, numSectors,
                                                        static_cast<uint64_t>(deviceSectorCount));

    UsbCreateResult createResult;
    if (mbrResult.success) {
        createResult = createUsbContainerWithHidden(
            volId, kUsbPartitionStartSector,
            nativeOuterPass, nativeHiddenPass, outerPim, hiddenPim, usbSizeBytes,
            nativeOuterFS, nativeHiddenFS, static_cast<int64_t>(hiddenSizeBytes),
            outerCipherId, outerHashId, hiddenCipherId, hiddenHashId,
            outerKfFds.empty() ? nullptr : outerKfFds.data(), static_cast<int>(outerKfFds.size()),
            hiddenKfFds.empty() ? nullptr : hiddenKfFds.data(), static_cast<int>(hiddenKfFds.size()),
            quickFormat, nativeOpId, sectorSize
        );
    } else {
        closeUnusedKeyfileFds(outerKfFds.empty() ? nullptr : outerKfFds.data(), static_cast<int>(outerKfFds.size()));
        closeUnusedKeyfileFds(hiddenKfFds.empty() ? nullptr : hiddenKfFds.data(), static_cast<int>(hiddenKfFds.size()));
        createResult = mbrResult;
    }

    vcReleasePasswordUtf8(nativeOuterPass);
    vcReleasePasswordUtf8(nativeHiddenPass);
    env->ReleaseStringUTFChars(outerFileSystem, nativeOuterFS);
    env->ReleaseStringUTFChars(hiddenFileSystem, nativeHiddenFS);
    if (operationId && nativeOpId) env->ReleaseStringUTFChars(operationId, nativeOpId);
    return buildUsbCreateResultMap(env, createResult);

    JNI_CATCH_RETURN(nullptr)
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_changeContainerPasswordNative(
        JNIEnv* env, jobject,
        jint fd, jstring oldPassword, jstring newPassword,
        jint oldPim, jint newPim,
        jint cipherId, jint hashId, jintArray oldKeyfileFds, jintArray newKeyfileFds,
        jint newHashId) {
    JNI_TRY


    std::vector<int> oldKfFds = extractKeyfileFds(env, oldKeyfileFds);
    std::vector<int> newKfFds = extractKeyfileFds(env, newKeyfileFds);
    
    const char* nativeOldPass = vcGetPasswordUtf8(env, oldPassword);
    const char* nativeNewPass = vcGetPasswordUtf8(env, newPassword);

    bool success = changeContainerPassword(fd, nativeOldPass, nativeNewPass, oldPim, newPim,
                                           cipherId, hashId,
                                           oldKfFds.empty() ? nullptr : oldKfFds.data(), static_cast<int>(oldKfFds.size()),
                                           newKfFds.empty() ? nullptr : newKfFds.data(), static_cast<int>(newKfFds.size()),
                                           newHashId);

    vcReleasePasswordUtf8(nativeOldPass);
    vcReleasePasswordUtf8(nativeNewPass);

    return success ? JNI_TRUE : JNI_FALSE;

    JNI_CATCH_RETURN(JNI_FALSE)
}

// Returns changeLuksContainerPassword()'s tri-state int directly (0 =
// success, 1 = wrong old password/keyfile, 2 = any other error) rather
// than collapsing to a jboolean like changeContainerPasswordNative above
// — LUKS's Kotlin caller needs to tell "wrong password" apart from "I/O
// or format error" to report AUTH_FAIL vs INVALID_VAULT, matching the
// folder-vault (Cryptomator/gocryptfs/CryFS) change-password handlers.
extern "C" JNIEXPORT jint JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_changeLuksContainerPasswordNative(
        JNIEnv* env, jobject,
        jint fd, jstring oldPassword, jstring newPassword,
        jintArray oldKeyfileFds, jintArray newKeyfileFds) {
    JNI_TRY

    std::vector<int> oldKfFds = extractKeyfileFds(env, oldKeyfileFds);
    std::vector<int> newKfFds = extractKeyfileFds(env, newKeyfileFds);

    const char* nativeOldPass = vcGetPasswordUtf8(env, oldPassword);
    const char* nativeNewPass = vcGetPasswordUtf8(env, newPassword);

    int result = changeLuksContainerPassword(fd, nativeOldPass, nativeNewPass,
                                             oldKfFds.empty() ? nullptr : oldKfFds.data(), static_cast<int>(oldKfFds.size()),
                                             newKfFds.empty() ? nullptr : newKfFds.data(), static_cast<int>(newKfFds.size()));

    vcReleasePasswordUtf8(nativeOldPass);
    vcReleasePasswordUtf8(nativeNewPass);

    return result;

    JNI_CATCH_RETURN(2)
}

// File-system code for the result arrays below, from the label fsGetFilesystemLabel reports.
static jint fsKindCode(const FsGrowReport& report) {
    static const char* const kNames[] = {"", "FAT12", "FAT16", "FAT32", "exFAT", "NTFS", "ext2", "ext3", "ext4"};
    for (jint i = 1; i < 9; i++) if (std::strcmp(report.fsLabel, kNames[i]) == 0) return i;
    return 0;
}

// Packs {container outcome, file-system step, file-system kind}. Container outcome: 0 = ok, 1 = wrong
// password/keyfile, 2 = not expandable (hidden-volume header / not a plain full-size standard volume),
// 3 = requested size not larger, 4 = I/O error, 5 = unreadable keyfile. File-system step: -1 = not run,
// otherwise an FsGrowStatus (filesystems/fs_grow.h). Kind: 0 unknown, 1 FAT12, 2 FAT16, 3 FAT32, 4 exFAT,
// 5 NTFS, 6 ext2, 7 ext3, 8 ext4.
static jintArray packExpandResult(JNIEnv* env, ExpandOutcome outcome, const FsGrowReport& report) {
    jint packed[3] = {static_cast<jint>(outcome), report.attempted ? static_cast<jint>(report.status) : -1,
                      fsKindCode(report)};
    jintArray result = env->NewIntArray(3);
    if (result != nullptr) env->SetIntArrayRegion(result, 0, 3, packed);
    return result;
}

extern "C" JNIEXPORT jintArray JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_expandVeraCryptContainerNative(
        JNIEnv* env, jobject,
        jint fd, jstring password, jint pim, jint cipherId, jint hashId, jintArray keyfileFds,
        jlong newSizeBytes, jboolean initFreeSpace, jboolean growFileSystem) {
    JNI_TRY

    std::vector<int> kfFds = extractKeyfileFds(env, keyfileFds);
    const char* nativePass = vcGetPasswordUtf8(env, password);
    FsGrowReport report;
    const ExpandOutcome outcome = expandVeraCryptContainer(
        fd, nativePass != nullptr ? nativePass : "", pim, cipherId, hashId,
        kfFds.empty() ? nullptr : kfFds.data(), static_cast<int>(kfFds.size()),
        static_cast<int64_t>(newSizeBytes), initFreeSpace == JNI_TRUE, growFileSystem == JNI_TRUE, &report);
    vcReleasePasswordUtf8(nativePass);
    return packExpandResult(env, outcome, report);

    JNI_CATCH_RETURN(nullptr)
}

// Grows only the file system of a standard volume that was expanded earlier. Same result array as above.
extern "C" JNIEXPORT jintArray JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_growVeraCryptFileSystemNative(
        JNIEnv* env, jobject,
        jint fd, jstring password, jint pim, jint cipherId, jint hashId, jintArray keyfileFds) {
    JNI_TRY

    std::vector<int> kfFds = extractKeyfileFds(env, keyfileFds);
    const char* nativePass = vcGetPasswordUtf8(env, password);
    FsGrowReport report;
    const ExpandOutcome outcome = growVeraCryptFileSystem(
        fd, nativePass != nullptr ? nativePass : "", pim, cipherId, hashId,
        kfFds.empty() ? nullptr : kfFds.data(), static_cast<int>(kfFds.size()), &report);
    vcReleasePasswordUtf8(nativePass);
    return packExpandResult(env, outcome, report);

    JNI_CATCH_RETURN(nullptr)
}

// Result: [outcome, fsKind, clusterSize, maxHiddenBytes]; outcome 0 = ok, 1 wrong password, 2 unsupported file system,
// 4 I/O error, 5 unreadable keyfile, 6 not a plain full-size standard volume.
extern "C" JNIEXPORT jlongArray JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_analyzeHiddenVolumeHostNative(
        JNIEnv* env, jobject,
        jint fd, jstring password, jint pim, jint cipherId, jint hashId, jintArray keyfileFds) {
    JNI_TRY

    std::vector<int> kfFds = extractKeyfileFds(env, keyfileFds);
    const char* nativePass = vcGetPasswordUtf8(env, password);
    HiddenHostAnalysis analysis;
    const HiddenHostOutcome outcome = analyzeHiddenVolumeHost(
        fd, nativePass != nullptr ? nativePass : "", pim, cipherId, hashId,
        kfFds.empty() ? nullptr : kfFds.data(), static_cast<int>(kfFds.size()), &analysis);
    vcReleasePasswordUtf8(nativePass);
    jlong values[4] = {static_cast<jlong>(outcome), static_cast<jlong>(analysis.fsKind),
                       static_cast<jlong>(analysis.clusterSize), static_cast<jlong>(analysis.maxHiddenBytes)};
    jlongArray result = env->NewLongArray(4);
    if (result != nullptr) env->SetLongArrayRegion(result, 0, 4, values);
    return result;

    JNI_CATCH_RETURN(nullptr)
}

// 0 = created, 1 wrong outer password, 2 unsupported file system, 3 no room / size too large, 4 I/O error,
// 5 unreadable keyfile, 6 invalid (not a plain full-size standard volume, hidden password too long or equal to the outer one).
extern "C" JNIEXPORT jint JNICALL
Java_com_aeidolon_vaultexplorer_NativeEngine_createHiddenVolumeInExistingNative(
        JNIEnv* env, jobject,
        jint fd, jstring outerPassword, jint outerPim, jint outerCipherId, jint outerHashId, jintArray outerKeyfileFds,
        jstring hiddenPassword, jint hiddenPim, jstring hiddenFileSystem, jlong hiddenSizeBytes,
        jint hiddenCipherId, jint hiddenHashId, jintArray hiddenKeyfileFds, jboolean quickFormat,
        jbyteArray userEntropy) {
    JNI_TRY
    ScopedJniUserEntropy entropyScope(env, userEntropy);

    std::vector<int> outerKfFds = extractKeyfileFds(env, outerKeyfileFds);
    std::vector<int> hiddenKfFds = extractKeyfileFds(env, hiddenKeyfileFds);
    const char* nativeOuterPass = vcGetPasswordUtf8(env, outerPassword);
    const char* nativeHiddenPass = vcGetPasswordUtf8(env, hiddenPassword);
    const char* nativeHiddenFS = env->GetStringUTFChars(hiddenFileSystem, nullptr);
    const HiddenHostOutcome outcome = createHiddenVolumeInExisting(
        fd, nativeOuterPass != nullptr ? nativeOuterPass : "", outerPim, outerCipherId, outerHashId,
        outerKfFds.empty() ? nullptr : outerKfFds.data(), static_cast<int>(outerKfFds.size()),
        nativeHiddenPass != nullptr ? nativeHiddenPass : "", hiddenPim,
        nativeHiddenFS, static_cast<int64_t>(hiddenSizeBytes), hiddenCipherId, hiddenHashId,
        hiddenKfFds.empty() ? nullptr : hiddenKfFds.data(), static_cast<int>(hiddenKfFds.size()),
        quickFormat == JNI_TRUE);
    env->ReleaseStringUTFChars(hiddenFileSystem, nativeHiddenFS);
    vcReleasePasswordUtf8(nativeOuterPass);
    vcReleasePasswordUtf8(nativeHiddenPass);
    return static_cast<jint>(outcome);

    JNI_CATCH_RETURN(static_cast<jint>(HiddenHostOutcome::kIoError))
}
