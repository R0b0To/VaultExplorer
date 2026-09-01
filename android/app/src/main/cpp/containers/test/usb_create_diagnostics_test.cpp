// Host-side test, no Android toolchain required:
//   g++ -std=c++17 usb_create_diagnostics_test.cpp -o usb_create_diagnostics_test
#include "../usb_create_diagnostics.h"
#include <cassert>
#include <cstdio>
#include <string>

int main() {
    // Ok() always reports success with phase kComplete, regardless of
    // whatever the caller had accumulated in a scratch UsbCreateResult
    // beforehand -- callers rely on this to just do
    // `return success ? UsbCreateResult::Ok() : result;`.
    {
        UsbCreateResult r = UsbCreateResult::Ok();
        assert(r.success);
        assert(r.phase == UsbCreatePhase::kComplete);
        assert(r.errorCode.empty());
        assert(r.errorMessage.empty());
    }

    // Fail() captures every field passed to it, and success is always false.
    {
        UsbCreateResult r = UsbCreateResult::Fail(UsbCreatePhase::kFillData, "USB_FILL_WRITE_FAILED",
                                                   "disk full", /*offsetBytes=*/4096, /*sector=*/8,
                                                   /*sectorCount=*/16);
        assert(!r.success);
        assert(r.phase == UsbCreatePhase::kFillData);
        assert(r.errorCode == "USB_FILL_WRITE_FAILED");
        assert(r.errorMessage == "disk full");
        assert(r.offsetBytes == 4096);
        assert(r.sector == 8);
        assert(r.sectorCount == 16);
    }

    // Fail()'s trailing diagnostic fields are optional -- a validation
    // failure with no meaningful sector/offset (e.g. USB_EMPTY_PASSWORD)
    // must still construct cleanly at their zero defaults.
    {
        UsbCreateResult r = UsbCreateResult::Fail(UsbCreatePhase::kValidate, "USB_EMPTY_PASSWORD", "empty");
        assert(!r.success);
        assert(r.offsetBytes == 0);
        assert(r.sector == 0);
        assert(r.sectorCount == 0);
    }

    // usbCreatePhaseName covers every enum value with a distinct, non-empty
    // name -- every UsbCreateResult surfaced to Kotlin includes this string,
    // so a phase silently falling through to "UNKNOWN" would be a real
    // diagnostics regression, not just a cosmetic one.
    {
        const UsbCreatePhase allPhases[] = {
            UsbCreatePhase::kValidate,        UsbCreatePhase::kOpen,
            UsbCreatePhase::kWriteMbr,        UsbCreatePhase::kPrepareHeader,
            UsbCreatePhase::kWritePrimaryHeader, UsbCreatePhase::kWriteBackupHeader,
            UsbCreatePhase::kFillData,        UsbCreatePhase::kFormatFilesystem,
            UsbCreatePhase::kComplete,
        };
        std::string seen[9];
        size_t n = 0;
        for (UsbCreatePhase p : allPhases) {
            std::string name = usbCreatePhaseName(p);
            assert(!name.empty());
            assert(name != "UNKNOWN");
            for (size_t i = 0; i < n; ++i) assert(seen[i] != name);  // all distinct
            seen[n++] = name;
        }
    }

    printf("usb_create_diagnostics_test: all assertions passed\n");
    return 0;
}
