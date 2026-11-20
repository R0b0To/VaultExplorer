#pragma once

// Result of growing the file system inside an unlocked volume so that it fills the volume
// (filesystems/fs_ops.h: fsGrowToFit). The numeric values cross the JNI boundary
// (NativeEngine.expandVeraCryptContainerNative / growVeraCryptFileSystemNative) and are
// mirrored in VeraCryptToolsHandlers.kt -- keep them in sync.
enum class FsGrowStatus : int {
    kGrown = 0,         // the file system now fills the volume
    kAlreadyFills = 1,  // nothing to do: no unallocated space beyond the file system
    kUnsupported = 2,   // this file system cannot be grown in place (FAT, exFAT) or isn't recognised
    kNeedsCheck = 3,    // the file system is marked dirty/in error: check & repair it first
    kBusy = 4,          // files are still open on the volume
    kFailed = 5,        // I/O error or the file system refused the new size
};
