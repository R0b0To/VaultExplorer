# android/app/src/main/cpp/archive/patches/apply_patch_once.cmake
#
# Patches the fetched libarchive v3.8.9 tree:
#   1. applies libarchive-7zip-encryption.patch (7zAES read/write)
#   2. injects RAR5 AES-256 decryption (data AND encrypted headers /
#      file names) into libarchive/archive_read_support_format_rar5.c
#
# The RAR5 crypto code itself lives in two real C files next to this script so
# it can be read, diffed and compiled in isolation:
#   rar5_crypt_core.inc   key schedule, header/data decryption, cleanup
#   rar5_crypt_parse.inc  HEAD_CRYPT / EX_CRYPT record parsing
# This script only splices them in and hooks the existing reader functions.
# Every hook anchors on stock libarchive text and must match EXACTLY ONCE,
# otherwise configure fails loudly (e.g. after a libarchive version bump).

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
    message(FATAL_ERROR "Patch does not apply to the fetched libarchive sources: ${PATCH_FILE}\n${apply_error}")
endif()
message(STATUS "Applied patch: ${PATCH_FILE}")

# ---------------------------------------------------------------------------
# RAR5 AES support
# ---------------------------------------------------------------------------
set(RAR5_SRC "libarchive/archive_read_support_format_rar5.c")
if(NOT EXISTS "${RAR5_SRC}")
    return()
endif()

set(RAR5_CORE_INC  "${CMAKE_CURRENT_LIST_DIR}/rar5_crypt_core.inc")
set(RAR5_PARSE_INC "${CMAKE_CURRENT_LIST_DIR}/rar5_crypt_parse.inc")
foreach(_inc "${RAR5_CORE_INC}" "${RAR5_PARSE_INC}")
    if(NOT EXISTS "${_inc}")
        message(FATAL_ERROR "apply_patch_once: missing ${_inc}")
    endif()
endforeach()

file(READ "${RAR5_SRC}"       RAR5_CODE)
file(READ "${RAR5_CORE_INC}"  RAR5_CORE_CODE)
file(READ "${RAR5_PARSE_INC}" RAR5_PARSE_CODE)

# Normalize CRLF to LF so anchors match on Windows and Linux hosts.
string(REPLACE "\r\n" "\n" RAR5_CODE       "${RAR5_CODE}")
string(REPLACE "\r\n" "\n" RAR5_CORE_CODE  "${RAR5_CORE_CODE}")
string(REPLACE "\r\n" "\n" RAR5_PARSE_CODE "${RAR5_PARSE_CODE}")

# Replace `from` by `to` in RAR5_CODE; `from` must occur exactly once.
function(rar5_replace title from to)
    string(REPLACE "\r\n" "\n" _from "${from}")
    string(REPLACE "\r\n" "\n" _to   "${to}")
    string(FIND "${RAR5_CODE}" "${_from}" _pos)
    if(_pos EQUAL -1)
        message(FATAL_ERROR "apply_patch_once: [${title}] anchor not found in RAR5 source:\n${_from}")
    endif()
    string(LENGTH "${_from}" _flen)
    math(EXPR _next "${_pos} + ${_flen}")
    string(SUBSTRING "${RAR5_CODE}" 0 ${_pos} _head)
    string(SUBSTRING "${RAR5_CODE}" ${_next} -1 _tail)
    string(FIND "${_tail}" "${_from}" _pos2)
    if(NOT _pos2 EQUAL -1)
        message(FATAL_ERROR "apply_patch_once: [${title}] anchor is ambiguous in RAR5 source:\n${_from}")
    endif()
    string(CONCAT _code "${_head}" "${_to}" "${_tail}")
    set(RAR5_CODE "${_code}" PARENT_SCOPE)
endfunction()

# Replacement text may reference the two spliced files.
function(rar5_expand out text)
    string(REPLACE "@CORE@"  "${RAR5_CORE_CODE}"  _t "${text}")
    string(REPLACE "@PARSE@" "${RAR5_PARSE_CODE}" _t "${_t}")
    set(${out} "${_t}" PARENT_SCOPE)
endfunction()

# 1. includes
rar5_replace("1. includes"
[=[#include "archive_entry_private.h"
#include "archive_time_private.h"

#ifdef HAVE_BLAKE2_H]=]
[=[#include "archive_entry_private.h"
#include "archive_time_private.h"

#ifdef HAVE_LIBCRYPTO
#include "archive_read_private.h"
#include "archive_openssl_evp_private.h"
#include <openssl/crypto.h>
#include <openssl/evp.h>
#include <openssl/hmac.h>
#include <openssl/sha.h>
#include <string.h>
#endif

#ifdef HAVE_BLAKE2_H]=])

# 2a. crypt state type
rar5_replace("2a. crypt state type"
[=[struct rar5 {
	int header_initialized;
]=]
[=[#ifdef HAVE_LIBCRYPTO
/* AES-256 state for encrypted RAR5 archives (see rar5_crypt_core.inc). */
struct rar5_crypt {
	/* Archive level (HEAD_CRYPT): every later header is encrypted. */
	uint8_t headers_encrypted;
	uint8_t hdr_key[32];

	/* Current file / service block (EX_CRYPT). */
	uint8_t file_enc;        /* payload encrypted AND we hold its key   */
	uint8_t file_err;        /* 1 no passphrase, 2 wrong, 3 unsupported */
	uint8_t tweaked;         /* checksums are HMAC'd with file_hash_key */
	uint8_t converted;       /* CRC already converted for comparison    */
	uint8_t file_key[32];
	uint8_t file_hash_key[32];
	uint8_t file_iv[16];

	/* Derived-key cache, keyed by (salt, kdf_lg). */
	uint8_t cache_valid;
	uint8_t cache_lg;
	uint8_t cache_salt[16];
	uint8_t cache_key[32];
	uint8_t cache_hash_key[32];
	uint8_t cache_check[8];

	EVP_CIPHER_CTX* hctx;    /* header cipher */
	EVP_CIPHER_CTX* dctx;    /* data cipher   */

	/* Decrypted header view (only valid while in_hdr). */
	uint8_t* hdr_buf;
	size_t hdr_cap;
	size_t hdr_len;
	size_t hdr_off;
	int in_hdr;

	/* Decrypted payload view (only valid while in_data). */
	uint8_t* dec_buf;
	size_t dec_cap;
	size_t dec_off;
	size_t dec_len;
	int in_data;
	uint64_t raw_remaining;  /* payload bytes still in the raw stream */
};
#endif

struct rar5 {
	int header_initialized;
]=])

# 2b. crypt member
rar5_replace("2b. crypt member"
[=[	int has_encrypted_entries;
	int headers_are_encrypted;
};]=]
[=[	int has_encrypted_entries;
	int headers_are_encrypted;
#ifdef HAVE_LIBCRYPTO
	struct rar5_crypt crypt;
#endif
};

#ifdef HAVE_LIBCRYPTO
/* Defined with the other crypto helpers; reset_file_context() comes first. */
static void r5c_reset_file(struct rar5* rar5);
#endif]=])

# 3. read_ahead/consume + crypto helpers
rar5_expand(_to [=[@CORE@static int read_ahead(struct archive_read* a, size_t how_many,
    const uint8_t** ptr)
{
	if(!ptr)
		return 0;

#ifdef HAVE_LIBCRYPTO
	{
		struct rar5* r5 = a->format ? (struct rar5*) a->format->data : NULL;
		if(r5 && (r5->crypt.in_hdr || r5->crypt.in_data))
			return r5c_ahead(a, r5, how_many, ptr);
	}
#endif

	*ptr = __archive_read_ahead(a, how_many, NULL);
	if(*ptr == NULL) {
		return 0;
	}

	return 1;
}

static int consume(struct archive_read* a, int64_t how_many) {
	int ret;

#ifdef HAVE_LIBCRYPTO
	{
		struct rar5* r5 = a->format ? (struct rar5*) a->format->data : NULL;
		if(r5 && (r5->crypt.in_hdr || r5->crypt.in_data))
			return r5c_consume(a, r5, how_many);
	}
#endif

	ret = how_many == __archive_read_consume(a, how_many)
		? ARCHIVE_OK
		: ARCHIVE_FATAL;

	return ret;
}

@PARSE@]=])
rar5_replace("3. read_ahead/consume + crypto helpers"
[=[static int read_ahead(struct archive_read* a, size_t how_many,
    const uint8_t** ptr)
{
	if(!ptr)
		return 0;

	*ptr = __archive_read_ahead(a, how_many, NULL);
	if(*ptr == NULL) {
		return 0;
	}

	return 1;
}

static int consume(struct archive_read* a, int64_t how_many) {
	int ret;

	ret = how_many == __archive_read_consume(a, how_many)
		? ARCHIVE_OK
		: ARCHIVE_FATAL;

	return ret;
}]=]
    "${_to}")

# 4a. scope the header view
rar5_replace("4a. scope the header view"
[=[static int process_base_block(struct archive_read* a,
    struct archive_entry* entry)
{
	const size_t SMALLEST_RAR5_BLOCK_SIZE = 3;

	struct rar5 *rar5 = a->format->data;]=]
[=[static int process_base_block(struct archive_read* a,
    struct archive_entry* entry)
{
	const size_t SMALLEST_RAR5_BLOCK_SIZE = 3;

	struct rar5 *rar5 = a->format->data;
#ifdef HAVE_LIBCRYPTO
	/* A header view never outlives its block. */
	rar5->crypt.in_hdr = 0;
#endif]=])

# 4b. finish previous payload, decrypt next header
rar5_replace("4b. finish previous payload, decrypt next header"
[=[	/* Skip any unprocessed data for this file. */
	ret = skip_unprocessed_bytes(a);
	if(ret != ARCHIVE_OK)
		return ret;]=]
[=[	/* Skip any unprocessed data for this file. */
	ret = skip_unprocessed_bytes(a);
	if(ret != ARCHIVE_OK)
		return ret;

#ifdef HAVE_LIBCRYPTO
	/* Whatever happened to the previous encrypted payload (read, probed,
	 * skipped), put the raw stream right behind it. */
	if(r5c_end_data(a, rar5) != ARCHIVE_OK)
		return ARCHIVE_FATAL;
	if(rar5->crypt.headers_encrypted) {
		ret = r5c_decrypt_header(a, rar5);
		if(ret != ARCHIVE_OK)
			return ret;
	}
#endif]=])

# 5. HEAD_CRYPT
rar5_replace("5. HEAD_CRYPT"
[=[		case HEAD_CRYPT:
			archive_entry_set_is_metadata_encrypted(entry, 1);
			archive_entry_set_is_data_encrypted(entry, 1);
			rar5->has_encrypted_entries = 1;
			rar5->headers_are_encrypted = 1;
			archive_set_error(&a->archive,
			    ARCHIVE_ERRNO_FILE_FORMAT,
			    "Encryption is not supported");
			return ARCHIVE_FATAL;]=]
[=[		case HEAD_CRYPT:
			archive_entry_set_is_metadata_encrypted(entry, 1);
			archive_entry_set_is_data_encrypted(entry, 1);
			rar5->has_encrypted_entries = 1;
#ifdef HAVE_LIBCRYPTO
		{
			const uint8_t* cur = NULL;
			size_t used, remaining;

			if(!read_ahead(a, 1, &cur))
				return ARCHIVE_EOF;
			used = (size_t)(cur - body_start);
			remaining = used < raw_hdr_size ? raw_hdr_size - used : 0;
			ret = r5c_parse_head_crypt(a, rar5, remaining);
			if(ret != ARCHIVE_OK)
				return ret;
			rar5_skip_remaining_block(a, body_start, raw_hdr_size);
			return ARCHIVE_RETRY;
		}
#else
			rar5->headers_are_encrypted = 1;
			archive_set_error(&a->archive,
			    ARCHIVE_ERRNO_FILE_FORMAT,
			    "Encryption is not supported");
			return ARCHIVE_FATAL;
#endif]=])

# 6. EX_CRYPT
rar5_replace("6. EX_CRYPT"
[=[			case EX_CRYPT:
				/* Mark the entry as encrypted */
				archive_entry_set_is_data_encrypted(e, 1);
				rar5->has_encrypted_entries = 1;
				rar5->cstate.data_encrypted = 1;
				/* fallthrough */
			case EX_SUBDATA:]=]
[=[			case EX_CRYPT:
#ifdef HAVE_LIBCRYPTO
				ret = parse_file_extra_crypt(a, e, rar5,
				    (int64_t)extra_field_size, &extra_data_size);
				break;
#else
				/* Mark the entry as encrypted */
				archive_entry_set_is_data_encrypted(e, 1);
				rar5->has_encrypted_entries = 1;
				rar5->cstate.data_encrypted = 1;
				/* fallthrough */
#endif
			case EX_SUBDATA:]=])

# 8a. rar5_read_data prologue
rar5_replace("8a. rar5_read_data prologue"
[=[	if (rar5->headers_are_encrypted || rar5->cstate.data_encrypted) {
		archive_set_error(&a->archive, ARCHIVE_ERRNO_FILE_FORMAT,
		    "Reading encrypted data is not currently supported");
		return ARCHIVE_FAILED;
	}]=]
[=[#ifdef HAVE_LIBCRYPTO
	rar5->crypt.in_hdr = 0;
	if(rar5->crypt.file_enc && !rar5->crypt.in_data) {
		ret = r5c_data_start(a, rar5);
		if(ret != ARCHIVE_OK)
			return ret;
	}
	if(rar5->cstate.data_encrypted && !rar5->crypt.file_enc) {
		/* Encrypted data we cannot decrypt (no/incorrect passphrase). */
		archive_set_error(&a->archive, ARCHIVE_ERRNO_MISC,
		    rar5->crypt.file_err == 2 ?
		        "Incorrect passphrase for encrypted RAR5 data" :
		    rar5->crypt.file_err == 3 ?
		        "Unsupported RAR5 crypt parameters" :
		        "Passphrase required for encrypted RAR5 data");
		return ARCHIVE_FAILED;
	}
#endif
	if (rar5->headers_are_encrypted || rar5->cstate.data_encrypted) {
		archive_set_error(&a->archive, ARCHIVE_ERRNO_FILE_FORMAT,
		    "Reading encrypted data is not currently supported");
		return ARCHIVE_FAILED;
	}]=])

# 8b. padding is not data
rar5_replace("8b. padding is not data"
[=[	if(rar5->file.bytes_remaining == 0 &&
			rar5->cstate.last_write_ptr == rar5->file.unpacked_size)
	{]=]
[=[#ifdef HAVE_LIBCRYPTO
	if(rar5->crypt.in_data &&
	    rar5->file.bytes_remaining > 0 && rar5->file.bytes_remaining < 16 &&
	    rar5->cstate.last_write_ptr == rar5->file.unpacked_size) {
		/* Everything is decoded; what is left is AES block padding. */
		rar5->file.bytes_remaining = 0;
	}
#endif
	if(rar5->file.bytes_remaining == 0 &&
			rar5->cstate.last_write_ptr == rar5->file.unpacked_size)
	{]=])

# 9a. skip: drop the header view
rar5_replace("9a. skip: drop the header view"
[=[static int rar5_read_data_skip(struct archive_read *a) {
	struct rar5 *rar5 = a->format->data;

	if(rar5->main.solid && (rar5->cstate.data_encrypted == 0)) {]=]
[=[static int rar5_read_data_skip(struct archive_read *a) {
	struct rar5 *rar5 = a->format->data;

#ifdef HAVE_LIBCRYPTO
	/* Called from process_head_service() while the header view is still
	 * set; the header is fully parsed by now. */
	rar5->crypt.in_hdr = 0;
#endif

	if(rar5->main.solid && (rar5->cstate.data_encrypted == 0)) {]=])

# 9b. skip: raw skip for encrypted payloads
rar5_replace("9b. skip: raw skip for encrypted payloads"
[=[		if(ARCHIVE_OK != consume(a, rar5->file.bytes_remaining)) {
			return ARCHIVE_FATAL;
		}

		rar5->file.bytes_remaining = 0;]=]
[=[#ifdef HAVE_LIBCRYPTO
		if(rar5->crypt.file_enc) {
			/* Encrypted payload: skip the raw bytes, never the
			 * decrypted view. */
			if(ARCHIVE_OK != r5c_end_data(a, rar5))
				return ARCHIVE_FATAL;
			return ARCHIVE_OK;
		}
#endif
		if(ARCHIVE_OK != consume(a, rar5->file.bytes_remaining)) {
			return ARCHIVE_FATAL;
		}

		rar5->file.bytes_remaining = 0;]=])

# 10. stored files: cap to unpacked size
rar5_replace("10. stored files: cap to unpacked size"
[=[	to_read = rar5_min(rar5->file.bytes_remaining, 64 * 1024);
	if(to_read == 0) {
		return ARCHIVE_EOF;
	}

	if(!read_ahead(a, to_read, &p)) {
		archive_set_error(&a->archive, ARCHIVE_ERRNO_FILE_FORMAT,
		    "I/O error when unstoring file");]=]
[=[	to_read = rar5_min(rar5->file.bytes_remaining, 64 * 1024);
#ifdef HAVE_LIBCRYPTO
	if(rar5->crypt.in_data) {
		/* AES padding follows the real data; only unpacked_size bytes
		 * belong to the file. */
		int64_t left = (int64_t)rar5->file.unpacked_size -
		    rar5->cstate.last_unstore_ptr;
		if(left <= 0) {
			rar5->file.bytes_remaining = 0;
			return ARCHIVE_EOF;
		}
		if((int64_t)to_read > left)
			to_read = (size_t)left;
	}
#endif
	if(to_read == 0) {
		return ARCHIVE_EOF;
	}

	if(!read_ahead(a, to_read, &p)) {
		archive_set_error(&a->archive, ARCHIVE_ERRNO_FILE_FORMAT,
		    "I/O error when unstoring file");]=])

# 11. reset per-file crypto state
rar5_replace("11. reset per-file crypto state"
[=[	rar5->file.redir_type = REDIR_TYPE_NONE;
	rar5->file.redir_flags = 0;

	free_filters(rar5);
}]=]
[=[	rar5->file.redir_type = REDIR_TYPE_NONE;
	rar5->file.redir_flags = 0;

	free_filters(rar5);
#ifdef HAVE_LIBCRYPTO
	r5c_reset_file(rar5);
#endif
}]=])

# 12. cleanup
rar5_replace("12. cleanup"
[=[static int rar5_cleanup(struct archive_read *a) {
	struct rar5 *rar5 = a->format->data;

	free(rar5->cstate.window_buf);]=]
[=[static int rar5_cleanup(struct archive_read *a) {
	struct rar5 *rar5 = a->format->data;

#ifdef HAVE_LIBCRYPTO
	r5c_free(rar5);
#endif

	free(rar5->cstate.window_buf);]=])

# 13a. tweaked CRC32
rar5_replace("13a. tweaked CRC32"
[=[		if(rar5->file.stored_crc32 > 0) {
			/* Check CRC32 only when the file contains a CRC32
			 * value for this file. */
]=]
[=[		if(rar5->file.stored_crc32 > 0) {
			/* Check CRC32 only when the file contains a CRC32
			 * value for this file. */
#ifdef HAVE_LIBCRYPTO
			r5c_tweak_crc(rar5);
#endif
]=])

# 13b. tweaked BLAKE2sp
rar5_replace("13b. tweaked BLAKE2sp"
[=[			(void) blake2sp_final(&rar5->file.b2state, b2_buf, 32);
]=]
[=[			(void) blake2sp_final(&rar5->file.b2state, b2_buf, 32);
#ifdef HAVE_LIBCRYPTO
			r5c_tweak_blake(rar5, b2_buf);
#endif
]=])

file(WRITE "${RAR5_SRC}" "${RAR5_CODE}")
message(STATUS "Injected RAR5 AES-256 decryption into ${RAR5_SRC}")
