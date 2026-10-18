# android/app/src/main/cpp/archive/patches/apply_patch_once.cmake

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

# Inject clean-room RAR5 AES decryption directly into libarchive
set(RAR5_SRC "libarchive/archive_read_support_format_rar5.c")
if(EXISTS "${RAR5_SRC}")
    file(READ "${RAR5_SRC}" RAR5_CODE)

    # Normalize CRLF to LF so replacements match consistently on Windows and Linux
    string(REPLACE "\r\n" "\n" RAR5_CODE "${RAR5_CODE}")

    macro(rar5_replace from to)
        set(_from "${from}")
        set(_to "${to}")
        string(REPLACE "\r\n" "\n" _from "${_from}")
        string(REPLACE "\r\n" "\n" _to "${_to}")
        string(FIND "${RAR5_CODE}" "${_from}" _pos)
        if(_pos EQUAL -1)
            message(FATAL_ERROR "apply_patch_once: Replacement target not found in RAR5 source:\n${_from}")
        endif()
        string(REPLACE "${_from}" "${_to}" RAR5_CODE "${RAR5_CODE}")
    endmacro()

    # 1. Add OpenSSL headers, private read header, and android log
    rar5_replace(
[=[#include "archive_entry_private.h"
#include "archive_time_private.h"

#ifdef HAVE_BLAKE2_H]=]
[=[#include "archive_entry_private.h"
#include "archive_time_private.h"

#ifdef HAVE_LIBCRYPTO
#include "archive_read_private.h"
#include "archive_openssl_evp_private.h"
#include <openssl/evp.h>
#include <string.h>
#include <android/log.h>
#define RLOG(...) __android_log_print(ANDROID_LOG_ERROR, "RAR5_DEBUG", __VA_ARGS__)
#endif

#ifdef HAVE_BLAKE2_H]=]
    )

    # 2. Add crypt state structure to struct rar5
    rar5_replace(
[=[	/*
	 * Custom field to denote that this archive contains encrypted entries
	 */
	int has_encrypted_entries;
	int headers_are_encrypted;
};]=]
[=[	/*
	 * Custom field to denote that this archive contains encrypted entries
	 */
	int has_encrypted_entries;
	int headers_are_encrypted;
#ifdef HAVE_LIBCRYPTO
	struct {
		uint8_t enabled;
		uint8_t headers_encrypted;
		uint8_t kdf_count;
		uint8_t salt[16];
		uint8_t iv[16];
		uint8_t aes_key[32];
		uint8_t key_ready;
		char* passphrase;
		EVP_CIPHER_CTX* ctx;
		uint8_t* header_buf;
		size_t header_buf_size;
		size_t header_buf_offset;
		int in_header_buf;
		uint8_t* dec_buf;
		size_t dec_buf_size;
		size_t dec_buf_offset;
		size_t dec_buf_len;
		int in_data_stream;
		size_t raw_bytes_remaining;
	} crypt;
#endif
};]=]
    )

    # 3. Intercept read_ahead and consume for streaming decryption
    rar5_replace(
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
[=[static int read_ahead(struct archive_read* a, size_t how_many,
    const uint8_t** ptr)
{
	if(!ptr)
		return 0;

#ifdef HAVE_LIBCRYPTO
	struct rar5* rar5 = a->format ? (struct rar5*) a->format->data : NULL;
	if(rar5 && rar5->crypt.in_header_buf) {
		if(rar5->crypt.header_buf_offset >= rar5->crypt.header_buf_size) return 0;
		*ptr = rar5->crypt.header_buf + rar5->crypt.header_buf_offset;
		return 1;
	}

	if(rar5 && rar5->crypt.in_data_stream) {
		while((rar5->crypt.dec_buf_len - rar5->crypt.dec_buf_offset) < how_many) {
			size_t avail = rar5->crypt.dec_buf_len - rar5->crypt.dec_buf_offset;
			if(avail > 0 && rar5->crypt.dec_buf_offset > 0) {
				memmove(rar5->crypt.dec_buf,
					rar5->crypt.dec_buf + rar5->crypt.dec_buf_offset,
					avail);
			}
			rar5->crypt.dec_buf_offset = 0;
			rar5->crypt.dec_buf_len = avail;

			size_t needed = how_many - avail;
			size_t to_decrypt = (needed + 15) & ~((size_t)15);
			if(to_decrypt < 64 * 1024) to_decrypt = 64 * 1024;
			if(to_decrypt > rar5->crypt.raw_bytes_remaining) {
				to_decrypt = rar5->crypt.raw_bytes_remaining;
			}
			if(to_decrypt == 0) {
				break;
			}

			size_t req_cap = avail + to_decrypt + 32;
			if(rar5->crypt.dec_buf_size < req_cap) {
				uint8_t* nb = realloc(rar5->crypt.dec_buf, req_cap);
				if(!nb) return 0;
				rar5->crypt.dec_buf = nb;
				rar5->crypt.dec_buf_size = req_cap;
			}

			ssize_t raw_avail = 0;
			const void* cptr = __archive_read_ahead(a, 16, &raw_avail);
			if(!cptr || raw_avail < 16) {
				break;
			}

			size_t can_take = (size_t)raw_avail;
			if(can_take > to_decrypt) can_take = to_decrypt;
			can_take &= ~((size_t)15);
			if(can_take == 0) {
				break;
			}

			int outl = 0;
			if(EVP_DecryptUpdate(rar5->crypt.ctx,
				rar5->crypt.dec_buf + avail,
				&outl,
				cptr,
				(int)can_take) != 1) {
				RLOG("EVP_DecryptUpdate failed");
				return 0;
			}

			RLOG("read_ahead (crypt): can_take=%zu outl=%d raw_rem=%zu", can_take, outl, rar5->crypt.raw_bytes_remaining);
			RLOG("read_ahead (crypt): cptr=[%02x %02x %02x %02x] dec=[%02x %02x %02x %02x]",
				((const uint8_t*)cptr)[0], ((const uint8_t*)cptr)[1], ((const uint8_t*)cptr)[2], ((const uint8_t*)cptr)[3],
				(rar5->crypt.dec_buf + avail)[0], (rar5->crypt.dec_buf + avail)[1],
				(rar5->crypt.dec_buf + avail)[2], (rar5->crypt.dec_buf + avail)[3]);

			__archive_read_consume(a, (int64_t)can_take);
			rar5->crypt.raw_bytes_remaining -= can_take;
			rar5->crypt.dec_buf_len += (size_t)outl;
			memset(rar5->crypt.dec_buf + rar5->crypt.dec_buf_len, 0, 16);
		}

		if(rar5->crypt.dec_buf_len - rar5->crypt.dec_buf_offset < how_many) {
			return 0;
		}

		*ptr = rar5->crypt.dec_buf + rar5->crypt.dec_buf_offset;
		return 1;
	}
#endif

	*ptr = __archive_read_ahead(a, how_many, NULL);
	if(*ptr == NULL) {
		return 0;
	}

	return 1;
}

static int consume(struct archive_read* a, int64_t how_many) {
#ifdef HAVE_LIBCRYPTO
	struct rar5* rar5 = a->format ? (struct rar5*) a->format->data : NULL;
	if(rar5 && rar5->crypt.in_header_buf) {
		rar5->crypt.header_buf_offset += (size_t)how_many;
		return ARCHIVE_OK;
	}

	if(rar5 && rar5->crypt.in_data_stream) {
		rar5->crypt.dec_buf_offset += (size_t)how_many;
		RLOG("consume (crypt): how_many=%lld, offset=%zu, len=%zu",
			(long long)how_many, rar5->crypt.dec_buf_offset, rar5->crypt.dec_buf_len);
		return ARCHIVE_OK;
	}
#endif
	int ret;

	ret = how_many == __archive_read_consume(a, how_many)
		? ARCHIVE_OK
		: ARCHIVE_FATAL;

	return ret;
}]=]
    )

    # 4. Helper to get and cache the passphrase with queue rewinding
    rar5_replace(
[=[static int process_base_block(struct archive_read* a,
    struct archive_entry* entry)
{]=]
[=[#ifdef HAVE_LIBCRYPTO
static const char* rar5_get_passphrase(struct archive_read* a, struct rar5* rar5) {
	if (rar5->crypt.passphrase != NULL) {
		return rar5->crypt.passphrase;
	}
	__archive_read_reset_passphrase(a);
	const char* pass = __archive_read_next_passphrase(a);
	if (pass != NULL) {
		rar5->crypt.passphrase = malloc(strlen(pass) + 1);
		if (rar5->crypt.passphrase != NULL) {
			strcpy(rar5->crypt.passphrase, pass);
		}
	}
	return pass;
}
#endif

static int process_base_block(struct archive_read* a,
    struct archive_entry* entry)
{]=]
    )

    # 5. Reset virtual buffer flag at start of process_base_block
    rar5_replace(
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
	if (rar5) rar5->crypt.in_header_buf = 0;
#endif]=]
    )

    # 6. Decrypt header block before processing in process_base_block
    rar5_replace(
[=[	/* Skip any unprocessed data for this file. */
	ret = skip_unprocessed_bytes(a);
	if(ret != ARCHIVE_OK)
		return ret;]=]
[=[	/* Skip any unprocessed data for this file. */
	ret = skip_unprocessed_bytes(a);
	if(ret != ARCHIVE_OK)
		return ret;

#ifdef HAVE_LIBCRYPTO
	if(rar5->crypt.headers_encrypted) {
		rar5->crypt.in_header_buf = 0;

		const void* p_iv = __archive_read_ahead(a, 16, NULL);
		if(!p_iv) return ARCHIVE_EOF;
		uint8_t iv[16];
		memcpy(iv, p_iv, 16);
		__archive_read_consume(a, 16);

		const void* p_c16 = __archive_read_ahead(a, 16, NULL);
		if(!p_c16) return ARCHIVE_EOF;
		uint8_t first16[16];
		EVP_CIPHER_CTX_reset(rar5->crypt.ctx);
		EVP_DecryptInit_ex(rar5->crypt.ctx, EVP_aes_256_cbc(), NULL, rar5->crypt.aes_key, iv);
		EVP_CIPHER_CTX_set_padding(rar5->crypt.ctx, 0);
		int outl = 0;
		EVP_DecryptUpdate(rar5->crypt.ctx, first16, &outl, (const uint8_t*)p_c16, 16);

		uint64_t raw_sz = 0;
		size_t size_len = 0;
		for(size_t i = 0; i < 10 && (4 + i) < 16; ++i) {
			uint8_t b = first16[4 + i];
			raw_sz |= ((uint64_t)(b & 0x7F)) << (i * 7);
			size_len = i + 1;
			if((b & 0x80) == 0) break;
		}
		size_t total_hdr = 4 + size_len + (size_t)raw_sz;
		size_t padded_hdr = (total_hdr + 15) & ~((size_t)15);

		RLOG("decrypt header: raw_sz=%llu, sz_len=%zu, total_hdr=%zu, padded_hdr=%zu",
			(unsigned long long)raw_sz, size_len, total_hdr, padded_hdr);

		if(total_hdr > (2 * 1024 * 1024) || padded_hdr > (2 * 1024 * 1024)) {
			archive_set_error(&a->archive, ARCHIVE_ERRNO_MISC,
			    "Incorrect RAR passphrase or damaged encrypted header");
			return ARCHIVE_FATAL;
		}

		if(rar5->crypt.header_buf_size < padded_hdr + 32) {
			free(rar5->crypt.header_buf);
			rar5->crypt.header_buf = malloc(padded_hdr + 32);
			rar5->crypt.header_buf_size = padded_hdr + 32;
		}
		memset(rar5->crypt.header_buf, 0, padded_hdr + 32);

		const void* p_all_cipher = __archive_read_ahead(a, padded_hdr, NULL);
		if(!p_all_cipher) return ARCHIVE_EOF;
		EVP_CIPHER_CTX_reset(rar5->crypt.ctx);
		EVP_DecryptInit_ex(rar5->crypt.ctx, EVP_aes_256_cbc(), NULL, rar5->crypt.aes_key, iv);
		EVP_CIPHER_CTX_set_padding(rar5->crypt.ctx, 0);
		EVP_DecryptUpdate(rar5->crypt.ctx, rar5->crypt.header_buf, &outl, (const uint8_t*)p_all_cipher, (int)padded_hdr);
		__archive_read_consume(a, (int64_t)padded_hdr);

		rar5->crypt.header_buf_size = total_hdr;
		rar5->crypt.header_buf_offset = 0;
		rar5->crypt.in_header_buf = 1;
	}
#endif]=]
    )

    # 7. Handle HEAD_CRYPT (Encrypted file names)
    rar5_replace(
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
#ifdef HAVE_LIBCRYPTO
		{
			uint64_t crypt_version = 0, crypt_flags = 0;
			uint64_t vsz = 0;
			if(!read_var(a, &crypt_version, &vsz)) return ARCHIVE_EOF;
			consume(a, (int64_t)vsz);
			if(!read_var(a, &crypt_flags, &vsz)) return ARCHIVE_EOF;
			consume(a, (int64_t)vsz);
			const uint8_t* p_kdf = NULL;
			if(!read_ahead(a, 1, &p_kdf)) return ARCHIVE_EOF;
			rar5->crypt.kdf_count = p_kdf[0];
			consume(a, 1);
			const uint8_t* p_salt = NULL;
			if(!read_ahead(a, 16, &p_salt)) return ARCHIVE_EOF;
			memcpy(rar5->crypt.salt, p_salt, 16);
			consume(a, 16);
			if(crypt_flags & 1) { consume(a, 12); }
			const char* pass = rar5_get_passphrase(a, rar5);
			if(!pass) {
				archive_set_error(&a->archive, ARCHIVE_ERRNO_MISC, "Passphrase required");
				return ARCHIVE_FATAL;
			}
			if(rar5->crypt.kdf_count > 24) {
				archive_set_error(&a->archive, ARCHIVE_ERRNO_MISC, "Unsupported KDF");
				return ARCHIVE_FATAL;
			}
			int iterations = 1 << rar5->crypt.kdf_count;
			if(!PKCS5_PBKDF2_HMAC(pass, strlen(pass), rar5->crypt.salt, 16, iterations, EVP_sha256(), 32, rar5->crypt.aes_key)) {
				archive_set_error(&a->archive, ARCHIVE_ERRNO_MISC, "PBKDF2 failed");
				return ARCHIVE_FATAL;
			}
			if(rar5->crypt.ctx == NULL) rar5->crypt.ctx = EVP_CIPHER_CTX_new();
			rar5->crypt.headers_encrypted = 1;
			rar5->crypt.enabled = 1;
			rar5->crypt.key_ready = 1;
			return ARCHIVE_RETRY;
		}
#else
			archive_entry_set_is_metadata_encrypted(entry, 1);
			archive_entry_set_is_data_encrypted(entry, 1);
			rar5->has_encrypted_entries = 1;
			rar5->headers_are_encrypted = 1;
			archive_set_error(&a->archive,
			    ARCHIVE_ERRNO_FILE_FORMAT,
			    "Encryption is not supported");
			return ARCHIVE_FATAL;
#endif]=]
    )

    # 8. Helper parse_file_extra_crypt before process_head_file_extra
    rar5_replace(
[=[		archive_entry_set_gid(e, (la_int64_t)id);
	}
	return ARCHIVE_OK;
}

static int process_head_file_extra(struct archive_read* a,]=]
[=[		archive_entry_set_gid(e, (la_int64_t)id);
	}
	return ARCHIVE_OK;
}

#ifdef HAVE_LIBCRYPTO
static int parse_file_extra_crypt(struct archive_read* a,
    struct archive_entry* e, struct rar5 *rar5, int64_t extra_field_size,
    int64_t* extra_data_size)
{
	uint64_t crypt_version = 0, crypt_flags = 0;
	uint64_t var_size = 0;
	int64_t field_consumed = 0;
	const uint8_t* p = NULL;

	archive_entry_set_is_data_encrypted(e, 1);
	rar5->has_encrypted_entries = 1;
	rar5->cstate.data_encrypted = 1;

	if(!read_var(a, &crypt_version, &var_size))
		return ARCHIVE_EOF;
	field_consumed += (int64_t)var_size;
	if(ARCHIVE_OK != consume(a, var_size))
		return ARCHIVE_EOF;

	if(!read_var(a, &crypt_flags, &var_size))
		return ARCHIVE_EOF;
	field_consumed += (int64_t)var_size;
	if(ARCHIVE_OK != consume(a, var_size))
		return ARCHIVE_EOF;

	if(!read_ahead(a, 1, &p))
		return ARCHIVE_EOF;
	rar5->crypt.kdf_count = p[0];
	field_consumed += 1;
	if(ARCHIVE_OK != consume(a, 1))
		return ARCHIVE_EOF;

	if(!read_ahead(a, 16, &p))
		return ARCHIVE_EOF;
	memcpy(rar5->crypt.salt, p, 16);
	field_consumed += 16;
	if(ARCHIVE_OK != consume(a, 16))
		return ARCHIVE_EOF;

	if(!read_ahead(a, 16, &p))
		return ARCHIVE_EOF;
	memcpy(rar5->crypt.iv, p, 16);
	field_consumed += 16;
	if(ARCHIVE_OK != consume(a, 16))
		return ARCHIVE_EOF;

	if(crypt_flags & 1) {
		if(!read_ahead(a, 12, &p))
			return ARCHIVE_EOF;
		field_consumed += 12;
		if(ARCHIVE_OK != consume(a, 12))
			return ARCHIVE_EOF;
	}

	*extra_data_size -= field_consumed;

	if(extra_field_size > field_consumed) {
		int64_t rem = extra_field_size - field_consumed;
		*extra_data_size -= rem;
		if(ARCHIVE_OK != consume(a, rem))
			return ARCHIVE_EOF;
	}

	rar5->crypt.enabled = 1;
	return ARCHIVE_OK;
}
#endif

static int process_head_file_extra(struct archive_read* a,]=]
    )

    # 9. EX_CRYPT handler in process_head_file_extra (with break, no fallthrough)
    rar5_replace(
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
case EX_SUBDATA:]=]
    )

    # 10. Track raw encrypted byte count for this file
    rar5_replace(
[=[		rar5->file.bytes_remaining = data_size;
	} else {
		rar5->file.bytes_remaining = 0;
	}]=]
[=[		rar5->file.bytes_remaining = data_size;
#ifdef HAVE_LIBCRYPTO
		rar5->crypt.raw_bytes_remaining = (data_size + 15) & ~((size_t)15);
#endif
	} else {
		rar5->file.bytes_remaining = 0;
#ifdef HAVE_LIBCRYPTO
		rar5->crypt.raw_bytes_remaining = 0;
#endif
	}]=]
    )

    # 11. Wrap file_entry_sanity_checks to allow directory records in encrypted archives
    rar5_replace(
[=[static int file_entry_sanity_checks(struct archive_read* a,]=]
[=[static int file_entry_sanity_checks_orig(struct archive_read* a,
    size_t block_flags, uint8_t is_dir, uint64_t unpacked_size,
    size_t packed_size);

static int file_entry_sanity_checks(struct archive_read* a,
    size_t block_flags, uint8_t is_dir, uint64_t unpacked_size,
    size_t packed_size)
{
	if(is_dir) return ARCHIVE_OK;
	return file_entry_sanity_checks_orig(a, block_flags, is_dir, unpacked_size, packed_size);
}

static int file_entry_sanity_checks_orig(struct archive_read* a,]=]
    )

    # 12. Wrap parse_block_header to recognize AES zero-padding at EOF
    rar5_replace(
[=[static int parse_block_header(struct archive_read* a, const uint8_t* p,]=]
[=[static int parse_block_header_orig(struct archive_read* a, const uint8_t* p,
    ssize_t* block_size, struct compressed_block_header* hdr);

static int parse_block_header(struct archive_read* a, const uint8_t* p,
    ssize_t* block_size, struct compressed_block_header* hdr)
{
	if(p && p[0] == 0 && p[1] == 0 && p[2] == 0 && p[3] == 0) {
		return ARCHIVE_EOF;
	}
	int ret = parse_block_header_orig(a, p, block_size, hdr);
	if(ret != ARCHIVE_OK && hdr && hdr->block_cksum == 0 && *block_size == 0) {
		return ARCHIVE_EOF;
	}
	return ret;
}

static int parse_block_header_orig(struct archive_read* a, const uint8_t* p,]=]
    )

    # 13. Key derivation and cipher init in rar5_read_data
    rar5_replace(
[=[static int rar5_read_data(struct archive_read *a, const void **buff,
    size_t *size, int64_t *offset) {
	struct rar5 *rar5 = a->format->data;
	int ret;

	if (size)
		*size = 0;

	if (rar5->has_encrypted_entries == ARCHIVE_READ_FORMAT_ENCRYPTION_DONT_KNOW) {
		rar5->has_encrypted_entries = 0;
	}

	if (rar5->headers_are_encrypted || rar5->cstate.data_encrypted) {
		archive_set_error(&a->archive, ARCHIVE_ERRNO_FILE_FORMAT,
		    "Reading encrypted data is not currently supported");
		return ARCHIVE_FAILED;
	}]=]
[=[#ifdef HAVE_LIBCRYPTO
static int rar5_init_cipher(struct archive_read* a, struct rar5* rar5) {
	if (!rar5->crypt.enabled || rar5->crypt.key_ready) return ARCHIVE_OK;
	const char* pass = rar5_get_passphrase(a, rar5);
	if (!pass) {
		archive_set_error(&a->archive, ARCHIVE_ERRNO_MISC, "Passphrase required");
		return ARCHIVE_FAILED;
	}
	if (rar5->crypt.kdf_count > 24) {
		archive_set_error(&a->archive, ARCHIVE_ERRNO_MISC, "Unsupported KDF");
		return ARCHIVE_FATAL;
	}
	int iterations = 1 << rar5->crypt.kdf_count;
	if (!PKCS5_PBKDF2_HMAC(pass, strlen(pass), rar5->crypt.salt, 16, iterations, EVP_sha256(), 32, rar5->crypt.aes_key)) {
		archive_set_error(&a->archive, ARCHIVE_ERRNO_MISC, "PBKDF2 failed");
		return ARCHIVE_FATAL;
	}
	if (rar5->crypt.ctx == NULL) {
		rar5->crypt.ctx = EVP_CIPHER_CTX_new();
	} else {
		EVP_CIPHER_CTX_reset(rar5->crypt.ctx);
	}
	if (!EVP_DecryptInit_ex(rar5->crypt.ctx, EVP_aes_256_cbc(), NULL, rar5->crypt.aes_key, rar5->crypt.iv)) {
		archive_set_error(&a->archive, ARCHIVE_ERRNO_MISC, "AES init failed");
		return ARCHIVE_FATAL;
	}
	EVP_CIPHER_CTX_set_padding(rar5->crypt.ctx, 0);
	rar5->crypt.key_ready = 1;
	return ARCHIVE_OK;
}
#endif

static int rar5_read_data(struct archive_read *a, const void **buff,
    size_t *size, int64_t *offset) {
	struct rar5 *rar5 = a->format->data;
	int ret;

	if (size)
		*size = 0;

	if (rar5->has_encrypted_entries == ARCHIVE_READ_FORMAT_ENCRYPTION_DONT_KNOW) {
		rar5->has_encrypted_entries = 0;
	}

#ifdef HAVE_LIBCRYPTO
	if (rar5->crypt.enabled) {
		rar5->crypt.in_header_buf = 0;
		int retCiph = rar5_init_cipher(a, rar5);
		if (retCiph != ARCHIVE_OK) return retCiph;
		rar5->cstate.data_encrypted = 0;
		rar5->headers_are_encrypted = 0;
		rar5->crypt.in_data_stream = 1;
	} else
#endif
	if (rar5->headers_are_encrypted || rar5->cstate.data_encrypted) {
		archive_set_error(&a->archive, ARCHIVE_ERRNO_FILE_FORMAT,
		    "Reading encrypted data is not currently supported");
		return ARCHIVE_FAILED;
	}]=]
    )

    # 14. Reset cipher context and in_data_stream in reset_file_context
    rar5_replace(
[=[static void reset_file_context(struct rar5 *rar5) {
	memset(&rar5->file, 0, sizeof(rar5->file));
	blake2sp_init(&rar5->file.b2state, 32);

	if(rar5->main.solid) {
		rar5->cstate.solid_offset += rar5->cstate.write_ptr;
	} else {
		rar5->cstate.solid_offset = 0;
	}

	rar5->cstate.write_ptr = 0;
	rar5->cstate.last_write_ptr = 0;
	rar5->cstate.last_unstore_ptr = 0;

	rar5->file.redir_type = REDIR_TYPE_NONE;
	rar5->file.redir_flags = 0;

	free_filters(rar5);
}]=]
[=[static void reset_file_context(struct rar5 *rar5) {
	memset(&rar5->file, 0, sizeof(rar5->file));
	blake2sp_init(&rar5->file.b2state, 32);

	if(rar5->main.solid) {
		rar5->cstate.solid_offset += rar5->cstate.write_ptr;
	} else {
		rar5->cstate.solid_offset = 0;
	}

	rar5->cstate.write_ptr = 0;
	rar5->cstate.last_write_ptr = 0;
	rar5->cstate.last_unstore_ptr = 0;

	rar5->file.redir_type = REDIR_TYPE_NONE;
	rar5->file.redir_flags = 0;

	free_filters(rar5);
#ifdef HAVE_LIBCRYPTO
	rar5->crypt.in_data_stream = 0;
	rar5->crypt.dec_buf_offset = 0;
	rar5->crypt.dec_buf_len = 0;
	rar5->crypt.in_header_buf = 0;
	if(!rar5->main.solid) {
		if(!rar5->crypt.headers_encrypted) {
			rar5->crypt.enabled = 0;
		}
		rar5->crypt.key_ready = 0;
	}
#endif
}]=]
    )

    # 15. Free crypto buffers on archive cleanup
    rar5_replace(
[=[static int rar5_cleanup(struct archive_read *a) {
	struct rar5 *rar5 = a->format->data;

	free(rar5->cstate.window_buf);]=]
[=[static int rar5_cleanup(struct archive_read *a) {
	struct rar5 *rar5 = a->format->data;

#ifdef HAVE_LIBCRYPTO
	if(rar5 && rar5->crypt.ctx) { EVP_CIPHER_CTX_free(rar5->crypt.ctx); rar5->crypt.ctx = NULL; }
	if(rar5 && rar5->crypt.passphrase) {
		memset(rar5->crypt.passphrase, 0, strlen(rar5->crypt.passphrase));
		free(rar5->crypt.passphrase);
		rar5->crypt.passphrase = NULL;
	}
	if(rar5) { free(rar5->crypt.header_buf); rar5->crypt.header_buf = NULL; }
	if(rar5) { free(rar5->crypt.dec_buf); rar5->crypt.dec_buf = NULL; }
#endif

	free(rar5->cstate.window_buf);]=]
    )

    file(WRITE "${RAR5_SRC}" "${RAR5_CODE}")
    message(STATUS "Injected RAR5 full AES decryption into ${RAR5_SRC}")
endif()