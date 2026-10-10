# Brings the fetched libarchive tree to "pristine upstream + PATCH_FILE".
#
#   cmake -DPATCH_FILE=<patch> -P apply_patch_once.cmake      (cwd = source dir)
#
# It is idempotent by construction: tracked files are reset to the pinned
# upstream commit first, so a clean tree, an already patched tree and a tree
# patched with an older version of the patch all end in the same state. If the
# patch stops applying (e.g. after bumping libarchive) configure fails here.
if(NOT PATCH_FILE OR NOT EXISTS "${PATCH_FILE}")
    message(FATAL_ERROR "apply_patch_once: PATCH_FILE '${PATCH_FILE}' not found")
endif()

find_program(GIT_EXECUTABLE git REQUIRED)

execute_process(
    COMMAND "${GIT_EXECUTABLE}" checkout -- libarchive
    RESULT_VARIABLE reset_result
    ERROR_VARIABLE reset_error)
if(NOT reset_result EQUAL 0)
    message(FATAL_ERROR "Could not reset the libarchive sources:\n${reset_error}")
endif()

execute_process(
    COMMAND "${GIT_EXECUTABLE}" apply --whitespace=nowarn "${PATCH_FILE}"
    RESULT_VARIABLE apply_result
    ERROR_VARIABLE apply_error)
if(NOT apply_result EQUAL 0)
    message(FATAL_ERROR
        "Patch does not apply to the fetched libarchive sources: ${PATCH_FILE}\n"
        "If libarchive was updated, port the patch to the new version.\n${apply_error}")
endif()
message(STATUS "Applied patch: ${PATCH_FILE}")
