# Applies PATCH_FILE to the current directory (the fetched source tree) unless it
# is already applied. Run as: cmake -DPATCH_FILE=<patch> -P apply_patch_once.cmake
# FetchContent runs it from the source directory.
if(NOT PATCH_FILE OR NOT EXISTS "${PATCH_FILE}")
    message(FATAL_ERROR "apply_patch_once: PATCH_FILE '${PATCH_FILE}' not found")
endif()

find_program(GIT_EXECUTABLE git REQUIRED)

function(apply_patch_once patch_file)
    if(NOT EXISTS "${patch_file}")
        message(FATAL_ERROR "apply_patch_once: patch '${patch_file}' not found")
    endif()

    # Already applied? (a re-run over a populated source directory)
    execute_process(
        COMMAND "${GIT_EXECUTABLE}" apply --unidiff-zero --reverse --check "${patch_file}"
        RESULT_VARIABLE already_applied
        OUTPUT_QUIET ERROR_QUIET)
    if(already_applied EQUAL 0)
        message(STATUS "Patch already applied: ${patch_file}")
        return()
    endif()

    execute_process(
        COMMAND "${GIT_EXECUTABLE}" apply --unidiff-zero --check "${patch_file}"
        RESULT_VARIABLE can_apply
        ERROR_VARIABLE check_error)
    if(NOT can_apply EQUAL 0)
        message(FATAL_ERROR
            "Patch does not apply to the fetched sources: ${patch_file}\n"
            "If libarchive was updated, port the patch to the new version.\n${check_error}")
    endif()

    execute_process(
        COMMAND "${GIT_EXECUTABLE}" apply --unidiff-zero "${patch_file}"
        RESULT_VARIABLE applied
        ERROR_VARIABLE apply_error)
    if(NOT applied EQUAL 0)
        message(FATAL_ERROR "Failed to apply ${patch_file}:\n${apply_error}")
    endif()
    message(STATUS "Applied patch: ${patch_file}")
endfunction()

if(PATCH_FILE_2)
    # The diagnostics patch is layered on top of the main patch. If it is
    # already applied, the main patch's reverse check can fail because the
    # diagnostics hunk changed nearby context; its presence proves both layers
    # are already installed.
    execute_process(
        COMMAND "${GIT_EXECUTABLE}" apply --unidiff-zero --reverse --check "${PATCH_FILE_2}"
        RESULT_VARIABLE diagnostics_already_applied
        OUTPUT_QUIET ERROR_QUIET)
    if(diagnostics_already_applied EQUAL 0)
        message(STATUS "Libarchive archive patches already applied")
        return()
    endif()
endif()

set(main_patch_already_present FALSE)
if(PATCH_FILE_2)
    # Some Android ABI build trees may already contain an older application
    # of this large patch. Its new 7-Zip reader and writer symbols distinguish
    # that state from a pristine upstream checkout, where the full patch must
    # be applied.
    execute_process(
        COMMAND "${GIT_EXECUTABLE}" grep -q "init_7zip_aes_decryption" --
            libarchive/archive_read_support_format_7zip.c
        RESULT_VARIABLE has_7zip_reader_patch
        OUTPUT_QUIET ERROR_QUIET)
    execute_process(
        COMMAND "${GIT_EXECUTABLE}" grep -q "SEVENZIP_ENCRYPT" --
            libarchive/archive_write_set_format_7zip.c
        RESULT_VARIABLE has_7zip_writer_patch
        OUTPUT_QUIET ERROR_QUIET)
    if(has_7zip_reader_patch EQUAL 0 AND has_7zip_writer_patch EQUAL 0)
        set(main_patch_already_present TRUE)
        message(STATUS "Main libarchive 7-Zip patch already present")
    endif()
endif()

if(NOT main_patch_already_present)
    apply_patch_once("${PATCH_FILE}")
endif()
if(PATCH_FILE_2)
    apply_patch_once("${PATCH_FILE_2}")
endif()
