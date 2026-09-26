#include <jni.h>
#include <string>
#include "ReadBarcode.h"
#include "ImageView.h"
#include "ReaderOptions.h"

extern "C" JNIEXPORT jstring JNICALL
Java_com_aeidolon_vaultexplorer_camera_VaultCameraSession_nativeScanQrCode(
    JNIEnv* env, jobject /* this */,
    jbyteArray yPlaneBytes, jint width, jint height, jint rowStride, jint rotationDegrees) {
    
    jbyte* buffer = env->GetByteArrayElements(yPlaneBytes, nullptr);
    if (!buffer) return nullptr;

    try {
        ZXing::ImageView image(
            reinterpret_cast<const uint8_t*>(buffer),
            width,
            height,
            ZXing::ImageFormat::Lum,
            rowStride
        );

        auto options = ZXing::ReaderOptions()
            .formats(ZXing::BarcodeFormat::QRCode)
            .tryRotate(true)
            .tryHarder(false)
            .isPure(false);

        auto rotated = image.rotated(rotationDegrees);
        auto barcodes = ZXing::ReadBarcodes(rotated, options);

        env->ReleaseByteArrayElements(yPlaneBytes, buffer, JNI_ABORT);

        if (!barcodes.empty() && barcodes.front().isValid() && !barcodes.front().text().empty()) {
            return env->NewStringUTF(barcodes.front().text().c_str());
        }
    } catch (...) {
        env->ReleaseByteArrayElements(yPlaneBytes, buffer, JNI_ABORT);
    }

    return nullptr;
}