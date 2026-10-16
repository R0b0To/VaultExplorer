// JNI glue for the document scanner (docscan/). Kept deliberately thin: all
// logic lives in docscan/ so it can be unit-tested on the host.
//
// Two Kotlin owners:
//   VaultCameraSession  - live edge detection on preview (Y plane) frames
//   DocumentScanNative  - capture-time detection, warp, filters and PDF output
//
// Pixel buffers cross the boundary as direct ByteBuffers (RGBA_8888, as written
// by Bitmap.copyPixelsToBuffer) so no copies are made; nothing is written to disk.
#include <jni.h>

#include <vector>

#include "docscan/doc_pdf.h"
#include "docscan/doc_scan.h"

namespace {

// Result layout shared with Kotlin: [x0,y0, x1,y1, x2,y2, x3,y3, score], with
// corners clockwise from the top-left and coordinates normalised to 0..1.
jfloatArray packDetection(JNIEnv* env, const docscan::Quad& q, float score) {
    const jfloat out[9] = {q.p[0].x, q.p[0].y, q.p[1].x, q.p[1].y, q.p[2].x,
                           q.p[2].y, q.p[3].x, q.p[3].y, score};
    jfloatArray arr = env->NewFloatArray(9);
    if (!arr) return nullptr;
    env->SetFloatArrayRegion(arr, 0, 9, out);
    return arr;
}

bool readQuad(JNIEnv* env, jfloatArray quad8, docscan::Quad* out) {
    if (!quad8 || env->GetArrayLength(quad8) < 8) return false;
    jfloat v[8];
    env->GetFloatArrayRegion(quad8, 0, 8, v);
    for (int i = 0; i < 4; ++i) {
        out->p[i].x = v[2 * i];
        out->p[i].y = v[2 * i + 1];
    }
    return true;
}

// Returns the buffer address if it is a direct buffer with at least `bytes`.
uint8_t* directBuffer(JNIEnv* env, jobject buf, jlong bytes) {
    if (!buf) return nullptr;
    void* p = env->GetDirectBufferAddress(buf);
    if (!p || env->GetDirectBufferCapacity(buf) < bytes) return nullptr;
    return static_cast<uint8_t*>(p);
}

}  // namespace

// Live preview: detect on the Y plane of a raw sensor frame, then rotate the
// result clockwise by rotationDegrees so it is in the upright (natural) frame.
extern "C" JNIEXPORT jfloatArray JNICALL
Java_com_aeidolon_vaultexplorer_camera_VaultCameraSession_nativeDetectDocument(
    JNIEnv* env, jobject /* this */, jbyteArray yPlaneBytes, jint width, jint height, jint rowStride,
    jint rotationDegrees) {
    if (!yPlaneBytes) return nullptr;
    jbyte* buffer = env->GetByteArrayElements(yPlaneBytes, nullptr);
    if (!buffer) return nullptr;
    jfloatArray result = nullptr;
    try {
        const docscan::Detection d =
            docscan::detectFromGray(reinterpret_cast<const uint8_t*>(buffer), width, height, rowStride);
        env->ReleaseByteArrayElements(yPlaneBytes, buffer, JNI_ABORT);
        buffer = nullptr;
        if (d.found) {
            docscan::PointF pts[4];
            for (int i = 0; i < 4; ++i) pts[i] = docscan::rotateNormalized(d.quad.p[i], rotationDegrees);
            result = packDetection(env, docscan::orderCorners(pts), d.score);
        }
    } catch (...) {
        if (buffer) env->ReleaseByteArrayElements(yPlaneBytes, buffer, JNI_ABORT);
        return nullptr;
    }
    return result;
}

// Capture time: detect on an RGBA image held in a direct buffer.
extern "C" JNIEXPORT jfloatArray JNICALL
Java_com_aeidolon_vaultexplorer_camera_DocumentScanNative_nativeDetectRgba(
    JNIEnv* env, jobject /* this */, jobject rgbaBuffer, jint width, jint height) {
    if (width < 16 || height < 16) return nullptr;
    const uint8_t* px = directBuffer(env, rgbaBuffer, static_cast<jlong>(width) * height * 4);
    if (!px) return nullptr;
    try {
        const docscan::Detection d = docscan::detectFromRgba(px, width, height, width * 4);
        if (!d.found) return nullptr;
        return packDetection(env, d.quad, d.score);
    } catch (...) {
        return nullptr;
    }
}

extern "C" JNIEXPORT jintArray JNICALL
Java_com_aeidolon_vaultexplorer_camera_DocumentScanNative_nativeOutputSize(
    JNIEnv* env, jobject /* this */, jfloatArray quad8, jint srcW, jint srcH, jint maxLongSide) {
    docscan::Quad q;
    if (!readQuad(env, quad8, &q) || srcW < 2 || srcH < 2 || maxLongSide < 1) return nullptr;
    try {
        int w = 0, h = 0;
        docscan::outputSize(q, srcW, srcH, maxLongSide, &w, &h);
        const jint out[2] = {w, h};
        jintArray arr = env->NewIntArray(2);
        if (!arr) return nullptr;
        env->SetIntArrayRegion(arr, 0, 2, out);
        return arr;
    } catch (...) {
        return nullptr;
    }
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_camera_DocumentScanNative_nativeWarp(
    JNIEnv* env, jobject /* this */, jobject srcBuffer, jint srcW, jint srcH, jfloatArray quad8,
    jobject dstBuffer, jint dstW, jint dstH) {
    docscan::Quad q;
    if (!readQuad(env, quad8, &q) || srcW < 2 || srcH < 2 || dstW < 1 || dstH < 1) return JNI_FALSE;
    const uint8_t* src = directBuffer(env, srcBuffer, static_cast<jlong>(srcW) * srcH * 4);
    uint8_t* dst = directBuffer(env, dstBuffer, static_cast<jlong>(dstW) * dstH * 4);
    if (!src || !dst) return JNI_FALSE;
    try {
        return docscan::warpQuad(src, srcW, srcH, srcW * 4, q, dst, dstW, dstH) ? JNI_TRUE : JNI_FALSE;
    } catch (...) {
        return JNI_FALSE;
    }
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aeidolon_vaultexplorer_camera_DocumentScanNative_nativeFilter(
    JNIEnv* env, jobject /* this */, jobject rgbaBuffer, jint width, jint height, jint filter) {
    if (width < 2 || height < 2 || filter < 0 || filter > 3) return JNI_FALSE;
    uint8_t* px = directBuffer(env, rgbaBuffer, static_cast<jlong>(width) * height * 4);
    if (!px) return JNI_FALSE;
    try {
        docscan::applyFilter(px, width, height, static_cast<docscan::Filter>(filter));
        return JNI_TRUE;
    } catch (...) {
        return JNI_FALSE;
    }
}

// Pages are plain JPEG byte arrays; their sizes are read from the JPEG headers.
// Returns null if any page is not an embeddable 8-bit gray/RGB JPEG.
extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_aeidolon_vaultexplorer_camera_DocumentScanNative_nativeBuildPdf(
    JNIEnv* env, jobject /* this */, jobjectArray jpegs) {
    if (!jpegs) return nullptr;
    const jsize n = env->GetArrayLength(jpegs);
    if (n <= 0) return nullptr;

    std::vector<jbyteArray> arrays(n, nullptr);
    std::vector<jbyte*> data(n, nullptr);
    std::vector<docscan::PdfPage> pages(n);
    bool ok = true;
    for (jsize i = 0; i < n && ok; ++i) {
        arrays[i] = static_cast<jbyteArray>(env->GetObjectArrayElement(jpegs, i));
        if (!arrays[i]) {
            ok = false;
            break;
        }
        data[i] = env->GetByteArrayElements(arrays[i], nullptr);
        if (!data[i]) {
            ok = false;
            break;
        }
        pages[i].jpeg = reinterpret_cast<const uint8_t*>(data[i]);
        pages[i].jpegSize = static_cast<size_t>(env->GetArrayLength(arrays[i]));
    }

    std::vector<uint8_t> pdf;
    if (ok) {
        try {
            pdf = docscan::buildPdf(pages);
        } catch (...) {
            pdf.clear();
        }
    }
    for (jsize i = 0; i < n; ++i) {
        if (arrays[i] && data[i]) env->ReleaseByteArrayElements(arrays[i], data[i], JNI_ABORT);
        if (arrays[i]) env->DeleteLocalRef(arrays[i]);
    }
    if (pdf.empty()) return nullptr;
    jbyteArray out = env->NewByteArray(static_cast<jsize>(pdf.size()));
    if (!out) return nullptr;
    env->SetByteArrayRegion(out, 0, static_cast<jsize>(pdf.size()), reinterpret_cast<const jbyte*>(pdf.data()));
    return out;
}
