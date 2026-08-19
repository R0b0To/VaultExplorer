#ifndef VAULTEXPLORER_CRYPTO_UTF16LE_PASSWORD_H
#define VAULTEXPLORER_CRYPTO_UTF16LE_PASSWORD_H

#include <stddef.h>
#include <stdint.h>

/*
 * Shared UTF-8 -> UTF-16LE conversion for password material.
 *
 * This used to be two separate hand-rolled implementations:
 *   - dislocker/encoding.c's toutf16() (BitLocker password prep)
 *   - crypto/single_file_crypto.cpp's utf8ToUtf16Le() (the AES Crypt
 *     compatible KDF used by the single-file encrypt/decrypt tool)
 * They drifted: toutf16() got a security fix (bounds-checked continuation
 * bytes, after an OOB read on a truncated multi-byte sequence) that
 * utf8ToUtf16Le() never received. Consolidating so a future fix only has
 * to happen once. See crypto/test/utf16le_password_test.cpp for the
 * regression cases this exists to protect.
 *
 * IMPORTANT -- input is JNI "modified UTF-8", not strict UTF-8:
 * Both call sites' password bytes ultimately come from
 * env->GetStringUTFChars(), which per the JNI spec returns "modified
 * UTF-8" (JNI spec 4.6.4.1): the NUL character is encoded as two bytes,
 * and any supplementary-plane character (e.g. an emoji) is pre-split into
 * a UTF-16 surrogate pair, with each surrogate half separately encoded as
 * its own *3-byte* sequence (CESU-8) -- never as one real 4-byte UTF-8
 * sequence.
 *
 * This function deliberately does NOT special-case or reject encoded
 * surrogates. It decodes each 3-byte sequence as an independent
 * code point below 0x10000 and writes it straight through as one raw
 * UTF-16 code unit, no questions asked. That is exactly what makes
 * astral/emoji passwords round-trip correctly: the two surrogate halves
 * land in the output in the same order, forming a valid UTF-16 surrogate
 * pair, purely as a side effect of nobody trying to recombine or validate
 * them. If you "harden" this into a strict RFC 3629 UTF-8 decoder that
 * rejects encoded surrogates, you will silently break every password
 * containing an emoji or other supplementary-plane character. The
 * 4-byte-lead-byte branch below exists only for hypothetical callers
 * that feed it real UTF-8 instead of modified UTF-8 -- it is never
 * exercised by JNI password input, since modified UTF-8 never emits a
 * true 4-byte sequence.
 */

/* Worst-case output size in bytes for a given input length: every input
 * byte could be a lone ASCII byte, each producing one 2-byte UTF-16 code
 * unit, so the bound is in_len * 2. Callers should size `out` with this
 * before calling utf16le_from_utf8(). */
static inline size_t utf16le_password_max_output_size(size_t in_len) {
    return in_len * 2;
}

/*
 * Converts `in_len` bytes of (modified) UTF-8 at `in` to UTF-16LE, writing
 * at most `out_cap` bytes to `out` (2 bytes per output code unit; never a
 * partial code unit). Returns the number of bytes actually written
 * (always even, 0..out_cap).
 *
 * `in` need not be NUL-terminated -- exactly `in_len` bytes are read.
 * Every continuation-byte access is bounds-checked against `in_len`, so a
 * truncated multi-byte sequence at the end of the buffer is never read
 * past. A lead byte that doesn't start a recognized UTF-8 sequence is
 * skipped (advance 1, keep going); a multi-byte sequence whose
 * continuation byte(s) don't have the required 10xxxxxx pattern is
 * dropped as a whole (advance past it, keep going) rather than silently
 * decoded from garbage bits. Neither case is treated as fatal: the
 * function always returns whatever it could recover rather than failing
 * outright, matching the behavior both original call sites relied on.
 *
 * Returns 0 if `in` or `out` is null.
 */
static inline size_t utf16le_from_utf8(const uint8_t *in, size_t in_len, uint8_t *out, size_t out_cap) {
    if (!in || !out) return 0;

    size_t i = 0;
    size_t written = 0;

    while (i < in_len) {
        const uint8_t lead = in[i];
        uint32_t codepoint;
        size_t extra; /* additional continuation bytes required */

        if ((lead & 0x80) == 0) {
            codepoint = lead;
            extra = 0;
        } else if ((lead & 0xE0) == 0xC0) {
            codepoint = lead & 0x1F;
            extra = 1;
        } else if ((lead & 0xF0) == 0xE0) {
            codepoint = lead & 0x0F;
            extra = 2;
        } else if ((lead & 0xF8) == 0xF0) {
            codepoint = lead & 0x07;
            extra = 3;
        } else {
            i += 1; /* invalid lead byte, just skip it */
            continue;
        }

        if (i + 1 + extra > in_len) {
            /* Truncated multi-byte sequence at the end of the buffer --
             * stop instead of reading past it. */
            break;
        }

        int valid = 1;
        for (size_t k = 1; k <= extra; k++) {
            const uint8_t cont = in[i + k];
            if ((cont & 0xC0) != 0x80) { valid = 0; break; }
            codepoint = (codepoint << 6) | (cont & 0x3F);
        }
        i += 1 + extra;
        if (!valid) continue; /* malformed continuation byte(s), skip the sequence */

        if (codepoint < 0x10000) {
            if (written + 2 > out_cap) break;
            out[written++] = (uint8_t)(codepoint & 0xFF);
            out[written++] = (uint8_t)((codepoint >> 8) & 0xFF);
        } else {
            if (written + 4 > out_cap) break;
            const uint32_t c = codepoint - 0x10000;
            const uint16_t high = (uint16_t)(0xD800 | (c >> 10));
            const uint16_t low  = (uint16_t)(0xDC00 | (c & 0x3FF));
            out[written++] = (uint8_t)(high & 0xFF);
            out[written++] = (uint8_t)((high >> 8) & 0xFF);
            out[written++] = (uint8_t)(low & 0xFF);
            out[written++] = (uint8_t)((low >> 8) & 0xFF);
        }
    }

    return written;
}

#endif /* VAULTEXPLORER_CRYPTO_UTF16LE_PASSWORD_H */
