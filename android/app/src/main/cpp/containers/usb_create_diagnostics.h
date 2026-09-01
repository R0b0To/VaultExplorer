#pragma once

#include <cstdint>
#include <string>

// Structured diagnostics for a single USB container-creation attempt
// (createUsbContainer / createUsbLuksContainer / createUsbContainerWithHidden
// in container_create_usb.cpp, plus writeMbrPartitionTable in
// partition_writer.cpp). Replaces a bare `bool` return so a failure deep in
// a multi-minute operation (open a 64GB drive, write a VeraCrypt/LUKS
// header, zero-fill, format a filesystem) can be reported as "which phase,
// which error, where" instead of a single undifferentiated `false` that the
// Kotlin/Flutter layers then have no way to explain to the user.
//
// This struct is additive, not a control-flow change: every call site that
// used to do `if (!step()) { LOGI(...); break; }` now also fills in a
// UsbCreateResult at that same break point, using the same information the
// LOGI call already had. No cryptographic or filesystem logic is touched
// by this file or by threading it through.
enum class UsbCreatePhase {
    kValidate = 0,        // argument/bounds validation, before any I/O
    kOpen = 1,             // opening/preparing the backing USB device
    kWriteMbr = 2,          // writing the MBR partition table
    kPrepareHeader = 3,      // building the VeraCrypt/LUKS header in memory
    kWritePrimaryHeader = 4, // writing the primary (or only) header
    kWriteBackupHeader = 5,  // writing the VeraCrypt backup header
    kFillData = 6,           // zero-filling / random-filling the data area
    kFormatFilesystem = 7,   // running the FAT/ext/NTFS/exFAT formatter
    kComplete = 8,           // fully succeeded
};

inline const char* usbCreatePhaseName(UsbCreatePhase phase) {
    switch (phase) {
        case UsbCreatePhase::kValidate: return "VALIDATE";
        case UsbCreatePhase::kOpen: return "OPEN";
        case UsbCreatePhase::kWriteMbr: return "WRITE_MBR";
        case UsbCreatePhase::kPrepareHeader: return "PREPARE_HEADER";
        case UsbCreatePhase::kWritePrimaryHeader: return "WRITE_PRIMARY_HEADER";
        case UsbCreatePhase::kWriteBackupHeader: return "WRITE_BACKUP_HEADER";
        case UsbCreatePhase::kFillData: return "FILL_DATA";
        case UsbCreatePhase::kFormatFilesystem: return "FORMAT_FILESYSTEM";
        case UsbCreatePhase::kComplete: return "COMPLETE";
    }
    return "UNKNOWN";
}

struct UsbCreateResult {
    bool success = false;
    UsbCreatePhase phase = UsbCreatePhase::kValidate;
    std::string errorCode;     // stable taxonomy, e.g. "USB_MBR_FAILED" -- surfaced to Flutter as-is
    std::string errorMessage;  // short, human-readable, never a raw data buffer or a secret
    uint64_t offsetBytes = 0;  // byte offset into the device where the failure occurred, if applicable
    uint64_t sector = 0;       // sector number, if applicable
    uint32_t sectorCount = 0;  // sector count of the failing operation, if applicable

    static UsbCreateResult Ok() {
        UsbCreateResult r;
        r.success = true;
        r.phase = UsbCreatePhase::kComplete;
        return r;
    }

    static UsbCreateResult Fail(UsbCreatePhase phase, const char* code, const std::string& message,
                                 uint64_t offsetBytes = 0, uint64_t sector = 0, uint32_t sectorCount = 0) {
        UsbCreateResult r;
        r.success = false;
        r.phase = phase;
        r.errorCode = code;
        r.errorMessage = message;
        r.offsetBytes = offsetBytes;
        r.sector = sector;
        r.sectorCount = sectorCount;
        return r;
    }
};
