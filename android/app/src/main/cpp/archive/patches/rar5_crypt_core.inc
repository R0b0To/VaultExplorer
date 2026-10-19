/* ======================================================================
 * RAR5 AES-256-CBC support (header + data encryption).
 *
 * Injected into libarchive's archive_read_support_format_rar5.c by
 * apply_patch_once.cmake. This file is the *core* half: key derivation,
 * header decryption, the decrypted-data stream and cleanup. The parser half
 * (HEAD_CRYPT / EX_CRYPT) lives in rar5_crypt_parse.inc.
 *
 * Design rules (these are what the earlier version got wrong):
 *
 *  1. The decrypted views are *scoped*:
 *       in_hdr  - only while one encrypted header block is being parsed.
 *       in_data - only while the payload of ONE file is being read.
 *     Both are cleared at every point where the reader moves on (next header,
 *     skip, new file context), so consume()/read_ahead() never leak a stale
 *     virtual view into raw-stream skipping.
 *
 *  2. The raw archive position of an encrypted payload is owned by
 *     `crypt.raw_remaining`. Whatever happened to the file (fully read,
 *     partially read by a probe, skipped, failed) r5c_end_data() consumes the
 *     leftover raw bytes, so the next header is always read at the right
 *     offset.
 *
 *  3. AES-CBC pads the packed data to 16 bytes and the padded size is what the
 *     header declares. Output completeness is decided by unpacked_size /
 *     the decoder, never by "bytes_remaining == 0".
 *
 *  4. "Tweaked" checksums (HMAC'd with the derived hash key) are converted
 *     before they are compared.
 * ====================================================================== */
#ifdef HAVE_LIBCRYPTO

#define R5C_MAX_KDF_LG   24
#define R5C_MAX_HDR      (2 * 1024 * 1024)
#define R5C_CHUNK        (64 * 1024)
#define R5C_TAIL         32          /* zero bytes kept after decrypted data */

enum {
	R5C_UNLOCK_OK = 0,
	R5C_UNLOCK_NO_PASSPHRASE = 1,
	R5C_UNLOCK_WRONG = 2,
	R5C_UNLOCK_ERROR = 3
};

static void r5c_cleanse(void* p, size_t n) {
	if(p != NULL && n > 0)
		OPENSSL_cleanse(p, n);
}

/*
 * RAR5 key schedule. One PBKDF2-HMAC-SHA256 chain (salt || 00000001) is
 * evaluated for 2^lg + 32 iterations and the running XOR is sampled:
 *   after 2^lg      iterations -> AES-256 key
 *   after 2^lg + 16 iterations -> hash key (checksum MAC)
 *   after 2^lg + 32 iterations -> password check value (folded to 8 bytes)
 */
static int r5c_derive(const char* pass, const uint8_t salt[16], unsigned lg,
    uint8_t key[32], uint8_t hash_key[32], uint8_t check8[8])
{
	uint8_t u[32], t[32], acc[32], sbuf[20];
	unsigned int ulen = 0;
	const uint64_t n = (uint64_t)1 << lg;
	const uint64_t total = n + 32;
	const size_t plen = strlen(pass);
	uint64_t i;
	int k, ok = 0;

	memcpy(sbuf, salt, 16);
	sbuf[16] = 0; sbuf[17] = 0; sbuf[18] = 0; sbuf[19] = 1;

	if(!HMAC(EVP_sha256(), pass, plen, sbuf, sizeof(sbuf), u, &ulen) ||
	    ulen != 32)
		goto done;
	memcpy(acc, u, 32);
	if(n == 1)
		memcpy(key, acc, 32);

	for(i = 1; i < total; i++) {
		if(!HMAC(EVP_sha256(), pass, plen, u, 32, t, &ulen) || ulen != 32)
			goto done;
		memcpy(u, t, 32);
		for(k = 0; k < 32; k++)
			acc[k] ^= u[k];
		if(i + 1 == n)
			memcpy(key, acc, 32);
		else if(i + 1 == n + 16)
			memcpy(hash_key, acc, 32);
	}

	memset(check8, 0, 8);
	for(k = 0; k < 32; k++)
		check8[k & 7] ^= acc[k];
	ok = 1;

done:
	r5c_cleanse(u, sizeof(u));
	r5c_cleanse(t, sizeof(t));
	r5c_cleanse(acc, sizeof(acc));
	return ok;
}

/*
 * Find the passphrase that unlocks (salt, lg). When the record carries a
 * password check value (check12 != NULL) every candidate is verified against
 * it; without one the first candidate is used and a wrong password only shows
 * up later as garbage / a checksum error. Results are cached per (salt, lg)
 * because every file of an archive normally shares one salt.
 */
static int r5c_unlock(struct archive_read* a, struct rar5* rar5,
    const uint8_t salt[16], unsigned lg, const uint8_t* check12,
    uint8_t key[32], uint8_t hash_key[32])
{
	struct rar5_crypt* c = &rar5->crypt;
	const char* pass;
	int tried = 0;
	uint8_t k[32], hk[32], ck[8], d[32];

	if(c->cache_valid && c->cache_lg == lg &&
	    memcmp(c->cache_salt, salt, 16) == 0 &&
	    (check12 == NULL || memcmp(c->cache_check, check12, 8) == 0)) {
		memcpy(key, c->cache_key, 32);
		memcpy(hash_key, c->cache_hash_key, 32);
		return R5C_UNLOCK_OK;
	}

	__archive_read_reset_passphrase(a);
	while((pass = __archive_read_next_passphrase(a)) != NULL) {
		tried++;
		if(!r5c_derive(pass, salt, lg, k, hk, ck)) {
			r5c_cleanse(k, sizeof(k));
			r5c_cleanse(hk, sizeof(hk));
			return R5C_UNLOCK_ERROR;
		}
		if(check12 != NULL) {
			SHA256(ck, 8, d);
			if(memcmp(ck, check12, 8) != 0 ||
			    memcmp(d, check12 + 8, 4) != 0)
				continue;
		}
		c->cache_valid = 1;
		c->cache_lg = (uint8_t)lg;
		memcpy(c->cache_salt, salt, 16);
		memcpy(c->cache_key, k, 32);
		memcpy(c->cache_hash_key, hk, 32);
		memcpy(c->cache_check, ck, 8);
		memcpy(key, k, 32);
		memcpy(hash_key, hk, 32);
		r5c_cleanse(k, sizeof(k));
		r5c_cleanse(hk, sizeof(hk));
		return R5C_UNLOCK_OK;
	}

	r5c_cleanse(k, sizeof(k));
	r5c_cleanse(hk, sizeof(hk));
	return tried ? R5C_UNLOCK_WRONG : R5C_UNLOCK_NO_PASSPHRASE;
}

/* ---- encrypted header blocks ---------------------------------------- */

/*
 * Every header of a header-encrypted archive is stored as
 *   IV(16) || AES-256-CBC(header padded with zeros to a multiple of 16)
 * The decrypted block has the normal layout CRC32 | size(vint) | body, so the
 * regular parser runs on it unchanged through the virtual view.
 */
static int r5c_decrypt_header(struct archive_read* a, struct rar5* rar5)
{
	struct rar5_crypt* c = &rar5->crypt;
	const uint8_t* p;
	uint8_t iv[16], first[16];
	uint64_t raw_sz = 0;
	size_t size_len = 0, total, padded, i;
	int outl = 0;

	c->in_hdr = 0;

	p = __archive_read_ahead(a, 32, NULL);
	if(p == NULL)
		return ARCHIVE_EOF;
	memcpy(iv, p, 16);

	if(c->hctx == NULL)
		c->hctx = EVP_CIPHER_CTX_new();
	else
		EVP_CIPHER_CTX_reset(c->hctx);
	if(c->hctx == NULL ||
	    !EVP_DecryptInit_ex(c->hctx, EVP_aes_256_cbc(), NULL,
	        c->hdr_key, iv)) {
		archive_set_error(&a->archive, ARCHIVE_ERRNO_MISC,
		    "RAR5 header cipher init failed");
		return ARCHIVE_FATAL;
	}
	EVP_CIPHER_CTX_set_padding(c->hctx, 0);

	if(!EVP_DecryptUpdate(c->hctx, first, &outl, p + 16, 16) ||
	    outl != 16) {
		archive_set_error(&a->archive, ARCHIVE_ERRNO_MISC,
		    "RAR5 header decryption failed");
		return ARCHIVE_FATAL;
	}

	/* first[0..3] = CRC32, then the header size as a vint. */
	for(i = 0; i < 10 && (4 + i) < 16; i++) {
		uint8_t b = first[4 + i];
		raw_sz |= ((uint64_t)(b & 0x7F)) << (i * 7);
		size_len = i + 1;
		if((b & 0x80) == 0)
			break;
		if(i == 9 || (4 + i) == 15) {
			size_len = 0;
			break;
		}
	}
	if(size_len == 0 || raw_sz < 2 || raw_sz > R5C_MAX_HDR) {
		archive_set_error(&a->archive, ARCHIVE_ERRNO_MISC,
		    "Incorrect RAR passphrase or damaged encrypted header");
		return ARCHIVE_FATAL;
	}

	total = 4 + size_len + (size_t)raw_sz;
	padded = (total + 15) & ~((size_t)15);

	if(c->hdr_cap < padded + R5C_TAIL) {
		uint8_t* nb = realloc(c->hdr_buf, padded + R5C_TAIL);
		if(nb == NULL) {
			archive_set_error(&a->archive, ENOMEM,
			    "Out of memory for RAR5 header");
			return ARCHIVE_FATAL;
		}
		c->hdr_buf = nb;
		c->hdr_cap = padded + R5C_TAIL;
	}
	memcpy(c->hdr_buf, first, 16);

	if(padded > 16) {
		p = __archive_read_ahead(a, 16 + padded, NULL);
		if(p == NULL)
			return ARCHIVE_EOF;
		if(!EVP_DecryptUpdate(c->hctx, c->hdr_buf + 16, &outl,
		        p + 32, (int)(padded - 16))) {
			archive_set_error(&a->archive, ARCHIVE_ERRNO_MISC,
			    "RAR5 header decryption failed");
			return ARCHIVE_FATAL;
		}
	}
	if(__archive_read_consume(a, (int64_t)(16 + padded)) !=
	    (int64_t)(16 + padded))
		return ARCHIVE_EOF;

	memset(c->hdr_buf + total, 0, c->hdr_cap - total);
	c->hdr_len = total;
	c->hdr_off = 0;
	c->in_hdr = 1;
	return ARCHIVE_OK;
}

/* ---- encrypted file payload ------------------------------------------ */

static int r5c_data_start(struct archive_read* a, struct rar5* rar5)
{
	struct rar5_crypt* c = &rar5->crypt;

	if(c->in_data)
		return ARCHIVE_OK;

	if(c->dctx == NULL)
		c->dctx = EVP_CIPHER_CTX_new();
	else
		EVP_CIPHER_CTX_reset(c->dctx);
	if(c->dctx == NULL ||
	    !EVP_DecryptInit_ex(c->dctx, EVP_aes_256_cbc(), NULL,
	        c->file_key, c->file_iv)) {
		archive_set_error(&a->archive, ARCHIVE_ERRNO_MISC,
		    "RAR5 data cipher init failed");
		return ARCHIVE_FATAL;
	}
	EVP_CIPHER_CTX_set_padding(c->dctx, 0);

	if(c->dec_buf == NULL) {
		c->dec_buf = calloc(1, R5C_CHUNK + R5C_TAIL);
		if(c->dec_buf == NULL) {
			archive_set_error(&a->archive, ENOMEM,
			    "Out of memory for RAR5 data buffer");
			return ARCHIVE_FATAL;
		}
		c->dec_cap = R5C_CHUNK + R5C_TAIL;
	}
	memset(c->dec_buf, 0, R5C_TAIL);
	c->dec_off = 0;
	c->dec_len = 0;
	c->in_data = 1;
	return ARCHIVE_OK;
}

/*
 * Make sure at least `want` decrypted bytes are available at
 * dec_buf + dec_off. Returns 1 on success, 0 if the encrypted payload has
 * fewer bytes left (or on I/O / cipher errors). Raw bytes are consumed from
 * the archive as they are decrypted and accounted in raw_remaining.
 */
static int r5c_fill(struct archive_read* a, struct rar5* rar5, size_t want)
{
	struct rar5_crypt* c = &rar5->crypt;
	size_t avail = c->dec_len - c->dec_off;

	while(avail < want) {
		const void* raw;
		ssize_t got = 0;
		uint64_t blocks = c->raw_remaining & ~(uint64_t)15;
		size_t need, take;
		int outl = 0;

		if(blocks == 0)
			break;

		if(c->dec_off > 0) {
			memmove(c->dec_buf, c->dec_buf + c->dec_off, avail);
			c->dec_off = 0;
			c->dec_len = avail;
		}

		need = ((want - avail) + 15) & ~((size_t)15);
		if(need < R5C_CHUNK)
			need = R5C_CHUNK;
		if((uint64_t)need > blocks)
			need = (size_t)blocks;

		if(c->dec_cap < c->dec_len + need + R5C_TAIL) {
			size_t ncap = c->dec_len + need + R5C_TAIL;
			uint8_t* nb = realloc(c->dec_buf, ncap);
			if(nb == NULL) {
				archive_set_error(&a->archive, ENOMEM,
				    "Out of memory for RAR5 data buffer");
				return 0;
			}
			c->dec_buf = nb;
			c->dec_cap = ncap;
		}

		raw = __archive_read_ahead(a, 16, &got);
		if(raw == NULL || got < 16)
			return 0;

		take = (size_t)got < need ? (size_t)got : need;
		if(take > ((size_t)1 << 30))
			take = (size_t)1 << 30;
		take &= ~((size_t)15);

		if(!EVP_DecryptUpdate(c->dctx, c->dec_buf + c->dec_len,
		        &outl, (const uint8_t*)raw, (int)take) ||
		    (size_t)outl != take) {
			archive_set_error(&a->archive, ARCHIVE_ERRNO_MISC,
			    "RAR5 data decryption failed");
			return 0;
		}
		if(__archive_read_consume(a, (int64_t)take) != (int64_t)take)
			return 0;

		c->raw_remaining -= take;
		c->dec_len += take;
		avail += take;
	}

	memset(c->dec_buf + c->dec_len, 0, R5C_TAIL);
	return avail >= want;
}

/*
 * Leave the payload of the current file: consume whatever raw bytes of it are
 * still in the archive stream and drop the decrypted view. Safe to call any
 * number of times.
 */
static int r5c_end_data(struct archive_read* a, struct rar5* rar5)
{
	struct rar5_crypt* c = &rar5->crypt;
	int ret = ARCHIVE_OK;

	if(c->raw_remaining > 0) {
		int64_t n = (int64_t)c->raw_remaining;
		c->raw_remaining = 0;
		if(__archive_read_consume(a, n) != n) {
			archive_set_error(&a->archive, ARCHIVE_ERRNO_FILE_FORMAT,
			    "Truncated RAR5 archive");
			ret = ARCHIVE_FATAL;
		}
	}
	c->in_data = 0;
	c->dec_off = 0;
	c->dec_len = 0;
	if(c->file_enc)
		rar5->file.bytes_remaining = 0;
	return ret;
}

static void r5c_reset_file(struct rar5* rar5)
{
	struct rar5_crypt* c = &rar5->crypt;

	/* NOTE: deliberately leaves in_hdr/hdr_* alone: this runs while the
	 * header of the new file is being parsed through the virtual view. */
	c->in_data = 0;
	c->dec_off = 0;
	c->dec_len = 0;
	c->file_enc = 0;
	c->file_err = 0;
	c->tweaked = 0;
	c->converted = 0;
	c->raw_remaining = 0;
}

static void r5c_free(struct rar5* rar5)
{
	struct rar5_crypt* c = &rar5->crypt;

	if(c->hctx != NULL) { EVP_CIPHER_CTX_free(c->hctx); c->hctx = NULL; }
	if(c->dctx != NULL) { EVP_CIPHER_CTX_free(c->dctx); c->dctx = NULL; }
	r5c_cleanse(c->hdr_buf, c->hdr_cap);
	free(c->hdr_buf);
	c->hdr_buf = NULL;
	c->hdr_cap = 0;
	r5c_cleanse(c->dec_buf, c->dec_cap);
	free(c->dec_buf);
	c->dec_buf = NULL;
	c->dec_cap = 0;
	/* Wipes hdr_key, file_key, file_hash_key and the derived-key cache. */
	r5c_cleanse(c, sizeof(*c));
}

/* ---- virtual read_ahead()/consume() views ---------------------------- */

static int r5c_ahead(struct archive_read* a, struct rar5* rar5,
    size_t how_many, const uint8_t** ptr)
{
	struct rar5_crypt* c = &rar5->crypt;
	size_t avail;

	if(c->in_hdr) {
		/* The buffer ends in zero bytes, so varint readers may look a
		 * little past the header exactly like with a real stream. */
		if(c->hdr_off > c->hdr_len ||
		    how_many > c->hdr_cap - c->hdr_off)
			return 0;
		*ptr = c->hdr_buf + c->hdr_off;
		return 1;
	}

	(void) r5c_fill(a, rar5, how_many);
	avail = c->dec_len - c->dec_off;
	if(avail < how_many) {
		/* The decoder asks for up to 4 bytes beyond the end of its
		 * block. In a plain archive those belong to the next header;
		 * here the encrypted payload simply ends, so supply zeros -
		 * but only at the genuine end of the payload. */
		if(c->raw_remaining >= 16 || how_many - avail > 16)
			return 0;
	}
	*ptr = c->dec_buf + c->dec_off;
	return 1;
}

static int r5c_consume(struct archive_read* a, struct rar5* rar5,
    int64_t how_many)
{
	struct rar5_crypt* c = &rar5->crypt;

	if(how_many < 0)
		return ARCHIVE_FATAL;

	if(c->in_hdr) {
		size_t room = c->hdr_len - c->hdr_off;
		c->hdr_off += ((uint64_t)how_many > room) ? room :
		    (size_t)how_many;
		return ARCHIVE_OK;
	}

	while(how_many > 0) {
		size_t avail = c->dec_len - c->dec_off;
		size_t take;

		if(avail == 0) {
			if(!r5c_fill(a, rar5, 1))
				return ARCHIVE_FATAL;
			avail = c->dec_len - c->dec_off;
		}
		take = ((uint64_t)how_many > avail) ? avail : (size_t)how_many;
		c->dec_off += take;
		how_many -= (int64_t)take;
	}
	return ARCHIVE_OK;
}

/* ---- checksum conversion for "tweaked" (MAC'd) hashes ---------------- */

static void r5c_tweak_crc(struct rar5* rar5)
{
	struct rar5_crypt* c = &rar5->crypt;
	uint8_t raw[4], d[32];
	unsigned int dl = 0;
	uint32_t v = 0, crc;
	int i;

	if(!c->file_enc || !c->tweaked || c->converted)
		return;
	crc = rar5->file.calculated_crc32;
	raw[0] = (uint8_t)crc; raw[1] = (uint8_t)(crc >> 8);
	raw[2] = (uint8_t)(crc >> 16); raw[3] = (uint8_t)(crc >> 24);
	if(HMAC(EVP_sha256(), c->file_hash_key, 32, raw, 4, d, &dl) != NULL) {
		for(i = 0; i < 32; i++)
			v ^= (uint32_t)d[i] << ((i & 3) * 8);
		rar5->file.calculated_crc32 = v;
	}
	c->converted = 1;
}

static void r5c_tweak_blake(struct rar5* rar5, uint8_t b2[32])
{
	struct rar5_crypt* c = &rar5->crypt;
	uint8_t d[32];
	unsigned int dl = 0;

	if(!c->file_enc || !c->tweaked)
		return;
	if(HMAC(EVP_sha256(), c->file_hash_key, 32, b2, 32, d, &dl) != NULL)
		memcpy(b2, d, 32);
}

#endif /* HAVE_LIBCRYPTO */

