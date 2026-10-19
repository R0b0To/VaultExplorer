/* ======================================================================
 * RAR5 encryption records: archive encryption header (HEAD_CRYPT) and the
 * per-file encryption extra record (EX_CRYPT). Injected after consume().
 * See rar5_crypt_core.inc for the design notes.
 * ====================================================================== */
#ifdef HAVE_LIBCRYPTO

/* Bounded RAR5 vint reader for records that were copied out of a header. */
static int r5c_vint(const uint8_t* p, size_t len, size_t* pos, uint64_t* out)
{
	uint64_t v = 0;
	unsigned shift = 0;

	while(*pos < len && shift < 64) {
		uint8_t b = p[(*pos)++];
		v |= ((uint64_t)(b & 0x7F)) << shift;
		if((b & 0x80) == 0) {
			*out = v;
			return 1;
		}
		shift += 7;
	}
	return 0;
}

/*
 * HEAD_CRYPT body: version(vint) flags(vint) kdf_lg(1) salt(16)
 * [check value(12) if flags & 1]. `remaining` is the number of body bytes
 * still unread. All later headers are encrypted with the derived key.
 */
static int r5c_parse_head_crypt(struct archive_read* a, struct rar5* rar5,
    size_t remaining)
{
	struct rar5_crypt* c = &rar5->crypt;
	const uint8_t* p;
	uint8_t rec[64], key[32], hk[32];
	const uint8_t* check = NULL;
	uint8_t salt[16];
	uint64_t ver = 0, flags = 0;
	size_t pos = 0, need;
	unsigned lg;
	int r;

	if(remaining == 0 || remaining > sizeof(rec)) {
		archive_set_error(&a->archive, ARCHIVE_ERRNO_FILE_FORMAT,
		    "Malformed RAR5 crypt header");
		return ARCHIVE_FATAL;
	}
	if(!read_ahead(a, remaining, &p))
		return ARCHIVE_EOF;
	memcpy(rec, p, remaining);

	if(!r5c_vint(rec, remaining, &pos, &ver) ||
	    !r5c_vint(rec, remaining, &pos, &flags)) {
		archive_set_error(&a->archive, ARCHIVE_ERRNO_FILE_FORMAT,
		    "Malformed RAR5 crypt header");
		return ARCHIVE_FATAL;
	}
	if(ver != 0) {
		archive_set_error(&a->archive, ARCHIVE_ERRNO_FILE_FORMAT,
		    "Unsupported RAR5 crypt version");
		return ARCHIVE_FATAL;
	}
	need = 1 + 16 + ((flags & 1) ? 12 : 0);
	if(remaining - pos < need) {
		archive_set_error(&a->archive, ARCHIVE_ERRNO_FILE_FORMAT,
		    "Malformed RAR5 crypt header");
		return ARCHIVE_FATAL;
	}
	lg = rec[pos++];
	memcpy(salt, rec + pos, 16);
	pos += 16;
	if(flags & 1)
		check = rec + pos;
	if(lg > R5C_MAX_KDF_LG) {
		archive_set_error(&a->archive, ARCHIVE_ERRNO_FILE_FORMAT,
		    "Unsupported RAR5 key derivation setting");
		return ARCHIVE_FATAL;
	}

	r = r5c_unlock(a, rar5, salt, lg, check, key, hk);
	if(r == R5C_UNLOCK_NO_PASSPHRASE) {
		archive_set_error(&a->archive, ARCHIVE_ERRNO_MISC,
		    "Passphrase required for encrypted RAR5 headers");
		return ARCHIVE_FATAL;
	}
	if(r == R5C_UNLOCK_WRONG) {
		archive_set_error(&a->archive, ARCHIVE_ERRNO_MISC,
		    "Incorrect passphrase for encrypted RAR5 headers");
		return ARCHIVE_FATAL;
	}
	if(r != R5C_UNLOCK_OK) {
		archive_set_error(&a->archive, ARCHIVE_ERRNO_MISC,
		    "RAR5 key derivation failed");
		return ARCHIVE_FATAL;
	}

	memcpy(c->hdr_key, key, 32);
	c->headers_encrypted = 1;
	r5c_cleanse(key, sizeof(key));
	r5c_cleanse(hk, sizeof(hk));
	return ARCHIVE_OK;
}

/*
 * File/service EX_CRYPT record: version(vint) flags(vint) kdf_lg(1) salt(16)
 * iv(16) [check value(12) if flags & 1]. flags & 2 = checksums are MAC'd.
 *
 * Entries are always reported as encrypted. If a passphrase unlocks the
 * record the payload becomes readable (file_enc = 1). Otherwise we fall back
 * to libarchive's stock behaviour for encrypted data (cstate.data_encrypted):
 * the entry is listed and skipped without decoding, and reading it fails with
 * a descriptive error. This keeps browsing possible without a passphrase and
 * keeps a wrong password on one file (archives may mix passwords) from
 * poisoning the whole listing.
 */
static int parse_file_extra_crypt(struct archive_read* a,
    struct archive_entry* e, struct rar5* rar5, int64_t extra_field_size,
    int64_t* extra_data_size)
{
	struct rar5_crypt* c = &rar5->crypt;
	const uint8_t* p = NULL;
	uint8_t rec[96], key[32], hk[32];
	uint64_t ver = 0, flags = 0;
	size_t len, pos = 0, need;
	unsigned lg;
	int r;

	if(extra_field_size < 0 || extra_field_size > (int64_t)sizeof(rec) ||
	    extra_field_size > *extra_data_size) {
		archive_set_error(&a->archive, ARCHIVE_ERRNO_FILE_FORMAT,
		    "Malformed RAR5 file crypt record");
		return ARCHIVE_FATAL;
	}
	len = (size_t)extra_field_size;
	if(len > 0) {
		if(!read_ahead(a, len, &p))
			return ARCHIVE_EOF;
		memcpy(rec, p, len);
		if(ARCHIVE_OK != consume(a, (int64_t)len))
			return ARCHIVE_EOF;
	}
	*extra_data_size -= (int64_t)len;

	archive_entry_set_is_data_encrypted(e, 1);
	if(c->headers_encrypted)
		archive_entry_set_is_metadata_encrypted(e, 1);
	rar5->has_encrypted_entries = 1;
	c->file_enc = 0;
	c->file_err = 0;

	if(!r5c_vint(rec, len, &pos, &ver) ||
	    !r5c_vint(rec, len, &pos, &flags))
		goto unsupported;
	need = 1 + 16 + 16 + ((flags & 1) ? 12 : 0);
	if(ver != 0 || len - pos < need)
		goto unsupported;
	lg = rec[pos++];
	if(lg > R5C_MAX_KDF_LG)
		goto unsupported;

	r = r5c_unlock(a, rar5, rec + pos, lg,
	    (flags & 1) ? rec + pos + 32 : NULL, key, hk);
	if(r == R5C_UNLOCK_OK) {
		memcpy(c->file_key, key, 32);
		memcpy(c->file_hash_key, hk, 32);
		memcpy(c->file_iv, rec + pos + 16, 16);
		c->tweaked = (flags & 2) != 0;
		c->file_enc = 1;
		c->raw_remaining = rar5->file.bytes_remaining > 0 ?
		    (uint64_t)rar5->file.bytes_remaining : 0;
		r5c_cleanse(key, sizeof(key));
		r5c_cleanse(hk, sizeof(hk));
		return ARCHIVE_OK;
	}
	if(r == R5C_UNLOCK_ERROR) {
		archive_set_error(&a->archive, ARCHIVE_ERRNO_MISC,
		    "RAR5 key derivation failed");
		return ARCHIVE_FATAL;
	}

	c->file_err = (r == R5C_UNLOCK_WRONG) ? 2 : 1;
	rar5->cstate.data_encrypted = 1;
	return ARCHIVE_OK;

unsupported:
	c->file_err = 3;
	rar5->cstate.data_encrypted = 1;
	return ARCHIVE_OK;
}

#endif /* HAVE_LIBCRYPTO */

