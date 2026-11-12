#pragma once
// Ordering policy for locking a volume, with the I/O supplied by the caller so it
// can be tested on the host (session/test/lock_policy_test.cpp).
//
// A lock has two ways to lose data it already acknowledged to the filesystem: tear
// the filesystem down while the device would still have refused the flush, and --
// worse -- reset the volume (which clears the USB write cache) after a flush that
// failed. The policy:
//   * normal lock: flush FIRST, while everything is still mounted; if the device
//     refuses, change nothing and report failure (the vault stays usable).
//   * then tear down; if that final flush fails, report failure WITHOUT resetting, so
//     the pending bytes survive and a retry only has to flush again. The filesystem is
//     then unmounted but the session stays open and usable: ensureMounted() remounts it
//     on the next operation (see unmountVolume in io/virtual_block_device.h).
//   * force (removed device, or the user chose "lock anyway"): always tear down and
//     reset, discarding whatever could not be written; `discarded` says so.
namespace lockpolicy {

//   flush()    -> bool : make buffered data durable; false = the device refused
//   teardown() -> bool : unmount the filesystem and flush again; false = that flush failed
//   reset()            : drop all volume state, INCLUDING any pending write cache
// `flushable` is false for backing stores with no separate flush step to try first.
// Returns true when the volume ended up locked (reset() ran).
template <typename FlushFn, typename TeardownFn, typename ResetFn>
bool lockVolume(bool flushable, bool force, FlushFn&& flush, TeardownFn&& teardown, ResetFn&& reset,
                bool* discarded = nullptr) {
    if (discarded) *discarded = false;
    if (!force && flushable && !flush()) return false;
    const bool durable = teardown();
    if (!durable && !force) return false;
    if (discarded) *discarded = !durable;
    reset();
    return true;
}

}  // namespace lockpolicy
