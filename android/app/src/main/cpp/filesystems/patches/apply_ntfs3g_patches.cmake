# android/app/src/main/cpp/filesystems/patches/apply_ntfs3g_patches.cmake
#
# Applies ntfs-3g-lookup-by-mbsname.patch to the fetched ntfs-3g tree.
# Run with the ntfs-3g source directory as the working directory:
#
#   cmake -DPATCH_FILE=<path to .patch> -P apply_ntfs3g_patches.cmake
#
# Why the patch exists: ntfs_inode_lookup_by_mbsname() passes a NULL
# "cached_name" to ntfs_mbstoucs() on a case sensitive volume when the volume
# has no lookup cache, which is exactly how ntfs_device_mount() leaves it (the
# FUSE driver's ntfs_mount() creates the caches; this app deliberately does
# not). open_reparse_index() uses that function to find $Extend/$Reparse, so
# without the patch every reparse-point operation fails with EINVAL:
# ntfs_create_symlink() returns NULL, and ntfs_delete() silently leaves a stale
# $Reparse index entry behind. See the patch for the one-line change.
#
# Idempotent: if the patch is already applied (an existing .cxx build tree
# re-configuring), it does nothing. Fails configure loudly if the patch neither
# applies nor is already applied (e.g. after an ntfs-3g version bump).

if(NOT PATCH_FILE OR NOT EXISTS "${PATCH_FILE}")
    message(FATAL_ERROR "apply_ntfs3g_patches: PATCH_FILE '${PATCH_FILE}' not found")
endif()

find_program(GIT_EXECUTABLE git REQUIRED)

# Already applied? A reverse apply that checks out means the patched text is there.
execute_process(
    COMMAND "${GIT_EXECUTABLE}" apply --check --reverse --whitespace=nowarn "${PATCH_FILE}"
    RESULT_VARIABLE already_applied
    OUTPUT_QUIET ERROR_QUIET)
if(already_applied EQUAL 0)
    message(STATUS "ntfs-3g patch already applied: ${PATCH_FILE}")
    return()
endif()

# Not (fully) applied. Start from the stock sources so that an edited patch
# re-applies cleanly onto a tree an older version of it already touched.
# Best effort: this only works in a git work tree, which FetchContent provides.
execute_process(
    COMMAND "${GIT_EXECUTABLE}" checkout -- libntfs-3g
    OUTPUT_QUIET ERROR_QUIET)

execute_process(
    COMMAND "${GIT_EXECUTABLE}" apply --whitespace=nowarn "${PATCH_FILE}"
    RESULT_VARIABLE apply_result
    ERROR_VARIABLE apply_error)
if(NOT apply_result EQUAL 0)
    message(FATAL_ERROR "Patch does not apply to the fetched ntfs-3g sources: ${PATCH_FILE}\n${apply_error}")
endif()
message(STATUS "Applied ntfs-3g patch: ${PATCH_FILE}")
