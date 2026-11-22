/*
 * VaultExplorer engine -- C ABI for desktop hosts (Linux / Windows; macOS later).
 *
 * This is the desktop counterpart of the Android JNI surface (NativeEngine.kt).
 * It exposes the same engine (session/, io/, containers/, filesystems/) through
 * plain C so a Flutter desktop app can drive it with dart:ffi -- no JVM, no
 * platform channel, no Kotlin.
 *
 * Conventions
 *   * All strings are UTF-8, NUL-terminated.
 *   * Every function is thread-safe and BLOCKING (key derivation, big copies...).
 *     Call from a worker isolate/thread, never from the UI thread.
 *   * Return codes: 0 (VE_OK) on success, positive VE_ERR_* otherwise. Functions
 *     that return a size/handle say so and use <0 / 0 for failure.
 *   * A "volume slot" (vol_id, 0 .. ve_max_volumes()-1) addresses an unlocked
 *     container, exactly like the Android volId. Dart never needs to know which
 *     on-disk format backs a slot.
 *   * File descriptors passed to ve_unlock / ve_create_container (and keyfile
 *     fds) are OWNED by the engine from that point: it closes them exactly once,
 *     on success or failure -- same contract as prepareSession() on Android.
 *     Descriptors from ve_open_file are plain C-runtime descriptors.
 *   * Output buffers (ve_buffer) are allocated by the engine and must be released
 *     with ve_buffer_free(), which wipes them first (they can hold plaintext).
 */
#ifndef VE_ENGINE_H
#define VE_ENGINE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#  define VE_API __declspec(dllexport)
#else
#  define VE_API __attribute__((visibility("default")))
#endif

#define VE_ABI_VERSION 10 /* bump whenever a function/struct is added or changed; the Dart side checks it */

/* ---- result codes ------------------------------------------------------- */
#define VE_OK 0
#define VE_ERR_FAILED 1        /* wrong password / bad format / I/O error / not found */
#define VE_ERR_CANCELLED 2     /* unlock cancelled via ve_request_cancel_unlock */
#define VE_ERR_NOT_UNLOCKED 3  /* vol_id has no active session */
#define VE_ERR_READ_ONLY 4     /* write attempted on a read-only mount */
#define VE_ERR_INVALID_ARG 5
#define VE_ERR_EXCEPTION 6     /* a C++ exception was caught at the boundary */
#define VE_ERR_MOUNT_FAILED 7  /* decrypted OK but the filesystem could not be mounted */
#define VE_ERR_AUTH_FAILED 8   /* the supplied OLD password / keyfile did not verify (LUKS password change) */
#define VE_ERR_UNSUPPORTED 9   /* the operation does not exist for this kind of slot / on this platform */
#define VE_ERR_BUSY 10         /* refused because the resource is in use (e.g. unmount with open files) */

/* ---- library info / logging -------------------------------------------- */
VE_API int32_t ve_abi_version(void);
VE_API int32_t ve_max_volumes(void);

/* Engine logging is OFF by default (log lines can name volumes and paths).
 * With a sink set, lines go to it; otherwise to stderr when enabled. */
VE_API void ve_set_log_enabled(int32_t enabled);
VE_API void ve_set_log_callback(void (*cb)(int32_t prio, const char* tag, const char* message));

/* ---- buffers ------------------------------------------------------------ */
typedef struct ve_buffer {
    uint8_t* data;
    size_t len;
} ve_buffer;

VE_API void ve_buffer_free(ve_buffer* buf); /* wipes, frees, zeroes the struct */

/* ---- host files --------------------------------------------------------- */
/* Opens an EXISTING host file (binary mode, UTF-8 path) and returns a descriptor, or -1. */
VE_API int32_t ve_open_file(const char* path_utf8, int32_t writable);
/* Creates (or truncates) a host file for read/write, owner-only permissions, and returns a
 * descriptor, or -1. Use it to make the file a new container is written into. */
VE_API int32_t ve_create_file(const char* path_utf8);
VE_API void ve_close_fd(int32_t fd);

/* ---- format probing (does NOT take ownership of fd) --------------------- */
/* Returns a static string: "veracrypt" | "luks1" | "luks2" | "bitlocker" |
 * "plain" | "unknown". Cheap and read-only. */
VE_API const char* ve_probe_format(int32_t fd);

/* ---- session lifecycle -------------------------------------------------- */
typedef struct ve_unlock_params {
    int32_t struct_size;            /* sizeof(ve_unlock_params), for forward compat */
    int32_t fd;                     /* owned by the engine from here on */
    const uint8_t* password;        /* UTF-8 bytes, may be NULL when keyfiles are used */
    int32_t password_len;
    int32_t pim;                    /* 0 = default */
    int32_t vol_id;                 /* slot to unlock into */
    int32_t cipher_id;              /* 255 = auto-detect */
    int32_t hash_id;                /* 255 = auto-detect */
    const uint8_t* preserved_key;   /* optional cached derived key material */
    int32_t preserved_key_len;
    const int32_t* keyfile_fds;     /* owned by the engine */
    int32_t keyfile_count;
    int32_t read_only;
    /* Hidden-volume protection (VeraCrypt): all NULL/0 to disable. */
    const uint8_t* hidden_password;
    int32_t hidden_password_len;
    int32_t hidden_pim;
    int32_t hidden_cipher_id;
    int32_t hidden_hash_id;
    const int32_t* hidden_keyfile_fds;
    int32_t hidden_keyfile_count;
} ve_unlock_params;

/* Unlocks fd into slot vol_id and mounts its filesystem. VE_OK on success. */
VE_API int32_t ve_unlock(const ve_unlock_params* params);
/* Asks an in-flight ve_unlock on vol_id to stop; it then returns VE_ERR_CANCELLED. */
VE_API void ve_request_cancel_unlock(int32_t vol_id);
/* Closes open streams, unmounts, and wipes the slot's key material. */
VE_API void ve_lock(int32_t vol_id);
VE_API int32_t ve_get_container_format(int32_t vol_id); /* ContainerFormat enum, <0 if invalid */
/* Which cipher / hash the unlock settled on (same ids ve_unlock accepts; 255 = unknown/n.a.). <0 if invalid slot. */
VE_API int32_t ve_get_matched_cipher_id(int32_t vol_id);
VE_API int32_t ve_get_matched_hash_id(int32_t vol_id);

/* ---- container creation ------------------------------------------------- */
typedef struct ve_create_params {
    int32_t struct_size;
    int32_t fd;                     /* owned by the engine (closed before return) */
    const uint8_t* password;
    int32_t password_len;           /* NUL-free UTF-8 */
    int32_t pim;
    int64_t size_bytes;
    const char* file_system;        /* "fat" | "exfat" | "ntfs" | "ext2" | "ext3" | "ext4" */
    int32_t container_format;       /* 0 = VeraCrypt, 1 = LUKS1, 2 = LUKS2 */
    int32_t cipher_id;              /* 255 = auto (VeraCrypt) */
    int32_t hash_id;                /* 255 = auto (VeraCrypt) */
    const int32_t* keyfile_fds;     /* owned by the engine */
    int32_t keyfile_count;
    int32_t quick_format;
    const uint8_t* user_entropy;    /* optional, mixed on top of the OS RNG */
    int32_t user_entropy_len;
} ve_create_params;

VE_API int32_t ve_create_container(const ve_create_params* params);

/* VeraCrypt container with an embedded hidden volume. cipher/hash ids apply to BOTH volumes. */
typedef struct ve_create_hidden_params {
    int32_t struct_size;
    int32_t fd;                      /* owned by the engine (closed before return) */
    const uint8_t* outer_password;
    int32_t outer_password_len;
    const uint8_t* hidden_password;
    int32_t hidden_password_len;
    int32_t outer_pim;
    int32_t hidden_pim;
    int64_t size_bytes;
    const char* outer_file_system;
    const char* hidden_file_system;
    int64_t hidden_size_bytes;
    int32_t outer_cipher_id;
    int32_t outer_hash_id;
    int32_t hidden_cipher_id;
    int32_t hidden_hash_id;
    const int32_t* outer_keyfile_fds;  /* owned by the engine */
    int32_t outer_keyfile_count;
    const int32_t* hidden_keyfile_fds; /* owned by the engine */
    int32_t hidden_keyfile_count;
    int32_t quick_format;
    const uint8_t* user_entropy;
    int32_t user_entropy_len;
} ve_create_hidden_params;

VE_API int32_t ve_create_container_with_hidden(const ve_create_hidden_params* params);

/* ---- password change (the container must NOT need to be unlocked) --------
 * VeraCrypt (container_format 0): re-derives the header key under the new password/PIM/keyfiles; the
 * result is only success or failure. LUKS1/LUKS2 (1/2): re-wraps the master key's active keyslot; a wrong
 * old password is reported as VE_ERR_AUTH_FAILED, distinct from I/O or header errors (VE_ERR_FAILED). */
typedef struct ve_change_password_params {
    int32_t struct_size;
    int32_t fd;                     /* opened read/write; owned by the engine */
    int32_t container_format;       /* 0 = VeraCrypt, 1 or 2 = LUKS (version is auto-detected) */
    const uint8_t* old_password;
    int32_t old_password_len;
    const uint8_t* new_password;
    int32_t new_password_len;
    int32_t old_pim;                /* VeraCrypt only */
    int32_t new_pim;                /* VeraCrypt only */
    int32_t cipher_id;              /* VeraCrypt only; 255 = auto */
    int32_t hash_id;                /* VeraCrypt only; 255 = auto */
    const int32_t* old_keyfile_fds; /* owned by the engine */
    int32_t old_keyfile_count;
    const int32_t* new_keyfile_fds; /* owned by the engine */
    int32_t new_keyfile_count;
} ve_change_password_params;

VE_API int32_t ve_change_password(const ve_change_password_params* params);

/* ---- filesystem operations on an unlocked slot ---------------------------
 * Paths are UTF-8, '/'-separated, relative to the volume root ("/" or ""). */

/* Directory listing, packed as: u32 count, then count x (u32 len, len bytes),
 * all little-endian. Each entry is the engine's directory-entry wire string. */
VE_API int32_t ve_list_directory(int32_t vol_id, const char* path, ve_buffer* out);

/* Sizes: >= 0 on success; -1 when the path does not exist (or is the wrong kind) -- the same "-1 = missing"
 * contract as fsGetFileSize; any other negative value is -VE_ERR_* (session errors such as NOT_UNLOCKED). */
VE_API int64_t ve_get_file_size(int32_t vol_id, const char* path);
VE_API int64_t ve_get_folder_size(int32_t vol_id, const char* path);

/* Reads up to length bytes (<= 64 MiB) at offset. EOF/failure -> VE_ERR_FAILED. */
VE_API int32_t ve_read_file_chunk(int32_t vol_id, const char* path, int64_t offset,
                                  int32_t length, ve_buffer* out);
/* Writes at offset (creates the file; offset 0 truncates, as on Android). <= 64 MiB. */
VE_API int32_t ve_write_file_chunk(int32_t vol_id, const char* path, int64_t offset,
                                   const uint8_t* data, size_t len);

VE_API int32_t ve_delete_file(int32_t vol_id, const char* path);
VE_API int32_t ve_create_directory(int32_t vol_id, const char* path);
VE_API int32_t ve_rename_file(int32_t vol_id, const char* old_path, const char* new_path);
VE_API int32_t ve_set_last_modified(int32_t vol_id, const char* path, int64_t epoch_seconds);

/* Whole-file transfers (progress/cancel via op_id, see ve_op_register). op_id 0 = untracked. */
VE_API int32_t ve_copy_file(int32_t src_vol, const char* src_path,
                            int32_t dst_vol, const char* dst_path, int32_t op_id);
VE_API int32_t ve_import_file(int32_t vol_id, const char* vault_path,
                              const char* host_source_path, int32_t op_id);
VE_API int32_t ve_export_file(int32_t vol_id, const char* vault_path,
                              const char* host_dest_path, int32_t op_id);

VE_API int32_t ve_get_space_info(int32_t vol_id, uint64_t* total_bytes, uint64_t* free_bytes);
/* Writes e.g. "FAT32" / "NTFS" / "ext4" into buf; returns its length, or <0. */
VE_API int32_t ve_get_filesystem_label(int32_t vol_id, char* buf, size_t cap);

/* "Vault information" for an unlocked block container (mirrors NativeEngine.getVaultInfo). Fields
 * that do not apply to the format are left at their zero value; has_* says which are meaningful. */
typedef struct ve_vault_info {
    int32_t struct_size;
    int32_t container_format;   /* ContainerFormat enum, see ve_get_container_format */
    int32_t read_only;
    int32_t hidden_volume;      /* VeraCrypt: this mount is the hidden volume */
    int64_t volume_size_bytes;
    int32_t has_cipher_hash;    /* VeraCrypt: cipher_id + hash_id valid; LUKS: cipher_id valid */
    int32_t cipher_id;
    int32_t hash_id;
    int32_t luks_version;       /* 0 when not LUKS */
    int32_t sector_size;        /* LUKS only, else 0 */
    int32_t has_file_system;
    char file_system[64];       /* e.g. "FAT32", "NTFS", "ext4" */
} ve_vault_info;

VE_API int32_t ve_get_vault_info(int32_t vol_id, ve_vault_info* out);

/* Streaming reads (media playback). handle 0 = failure. Close every handle. */
VE_API int64_t ve_open_stream(int32_t vol_id, const char* path);
VE_API int32_t ve_read_stream(int32_t vol_id, int64_t handle, int64_t offset,
                              uint8_t* dest, int32_t length); /* bytes read, or -1 */
VE_API void ve_close_stream(int32_t vol_id, int64_t handle);

/* ---- crypto primitives ------------------------------------------------------
 * The same implementations the Android bridge calls (BoringSSL / mbedTLS / the bundled Argon2 and
 * scrypt), exposed for the app's own features: password hashing for app lock and PIN, thumbnail-cache
 * encryption, authenticator-backup import, TOTP. All blocking; run them off the UI thread.
 * Fixed-size outputs are written into a caller buffer; variable-size ones come back in a ve_buffer. */
#define VE_HASH_SHA1 1
#define VE_HASH_SHA256 2
#define VE_HASH_SHA512 3

/* PBKDF2-HMAC. salt must be non-empty, iterations > 0, out_len > 0. */
VE_API int32_t ve_pbkdf2(int32_t hash, const uint8_t* password, size_t password_len,
                         const uint8_t* salt, size_t salt_len, uint32_t iterations,
                         uint8_t* out, size_t out_len);
/* One-shot HMAC; out_cap must be >= the digest size (20 / 32 / 64). *out_len receives the size. */
VE_API int32_t ve_hmac(int32_t hash, const uint8_t* key, size_t key_len,
                       const uint8_t* data, size_t data_len,
                       uint8_t* out, size_t out_cap, size_t* out_len);
VE_API int32_t ve_scrypt(const uint8_t* password, size_t password_len,
                         const uint8_t* salt, size_t salt_len,
                         uint32_t n, uint32_t r, uint32_t p, uint8_t* out, size_t out_len);
VE_API int32_t ve_argon2id(const uint8_t* password, size_t password_len,
                           const uint8_t* salt, size_t salt_len,
                           uint32_t memory_kib, uint32_t iterations, uint32_t parallelism,
                           uint8_t* out, size_t out_len);
/* AES-128/256-GCM (key_len 16 or 32, any non-empty IV). Seal output = ciphertext || 16-byte tag. */
VE_API int32_t ve_aes_gcm_seal(const uint8_t* key, size_t key_len, const uint8_t* iv, size_t iv_len,
                               const uint8_t* aad, size_t aad_len,
                               const uint8_t* plaintext, size_t plaintext_len, ve_buffer* out);
VE_API int32_t ve_aes_gcm_open(const uint8_t* key, size_t key_len, const uint8_t* iv, size_t iv_len,
                               const uint8_t* aad, size_t aad_len,
                               const uint8_t* ciphertext_and_tag, size_t len, ve_buffer* out);
/* AES-CBC decrypt with PKCS#7 padding removal (key 16/24/32 bytes, IV 16 bytes). */
VE_API int32_t ve_aes_cbc_decrypt(const uint8_t* key, size_t key_len, const uint8_t* iv, size_t iv_len,
                                  const uint8_t* ciphertext, size_t len, ve_buffer* out);
/* XChaCha20-Poly1305 open (key 32 bytes, nonce 24 bytes, input = ciphertext || 16-byte tag). */
VE_API int32_t ve_xchacha20poly1305_open(const uint8_t* key, size_t key_len,
                                         const uint8_t* nonce, size_t nonce_len,
                                         const uint8_t* aad, size_t aad_len,
                                         const uint8_t* ciphertext_and_tag, size_t len, ve_buffer* out);

/* ---- single-file encryption (the "encrypt / decrypt a file" tool) ----------
 * Stream-encrypts a host file into another host file (.vxenc, or .aes for cipher_index 2) and back.
 * Progress is reported as VE_EVENT_SPLITJOIN_PROGRESS for op_id; to make the operation cancellable,
 * ve_op_register(op_id, ...) first and call ve_op_cancel(op_id) -- a cancelled run returns
 * VE_ERR_CANCELLED. src_fd and dest_fd are closed by the engine before returning; keyfile descriptors
 * are consumed as the keyfiles are read. The caller deletes dest on any failure. */
typedef struct ve_single_file_params {
    int32_t struct_size;
    int32_t src_fd;
    int32_t dest_fd;
    int32_t encrypt;             /* 1 = encrypt, 0 = decrypt */
    int32_t cipher_index;        /* encrypt only: the tool's cipher choice (2 = ".aes" format) */
    const uint8_t* password;
    int32_t password_len;
    const int32_t* keyfile_fds;
    int32_t keyfile_count;
    int32_t op_id;               /* 0 = not cancellable, no progress */
} ve_single_file_params;

VE_API int32_t ve_single_file_crypt(const ve_single_file_params* params);

/* ---- streaming digests (checksum tool) -----------------------------------
 * One session feeds the same bytes into several algorithms in a single pass. Algorithm ids: the
 * VE_HASH_* values above plus VE_HASH_MD5. The mask has bit (1 << id) set for each wanted algorithm. */
#define VE_HASH_MD5 4

VE_API int64_t ve_hash_begin(uint32_t algorithm_mask);  /* handle, or 0 */
VE_API int32_t ve_hash_update(int64_t handle, const uint8_t* data, size_t len);
/* Finalizes one algorithm of the session into out (raw digest bytes). */
VE_API int32_t ve_hash_finish(int64_t handle, int32_t algorithm, uint8_t* out, size_t cap, size_t* out_len);
VE_API void ve_hash_free(int64_t handle);
/* One-shot digest of a buffer. */
VE_API int32_t ve_hash_bytes(int32_t algorithm, const uint8_t* data, size_t len,
                             uint8_t* out, size_t cap, size_t* out_len);

/* ---- operations: progress events + cancellation ------------------------- */
#define VE_OP_COPY 0
#define VE_OP_IMPORT 1
#define VE_OP_EXPORT 2

/* Declare an operation id before passing it to a *_file call so the engine can
 * route its progress and honor ve_op_cancel(). Unregister when done. */
VE_API void ve_op_register(int32_t op_id, int32_t flavor);
VE_API void ve_op_cancel(int32_t op_id);
VE_API void ve_op_unregister(int32_t op_id);

#define VE_EVENT_UNLOCK_PROGRESS 1      /* vol_id; i0=attempted i1=total i2=hash i3=cipher i4=format; n0=slot */
#define VE_EVENT_SPLITJOIN_PROGRESS 2   /* op_id; n0=bytes done, n1=bytes total */
#define VE_EVENT_REPAIR_LOG 3           /* op_id; text */
#define VE_EVENT_COPY_PROGRESS 4        /* op_id; n0=bytes since last poll */
#define VE_EVENT_IMPORT_PROGRESS 5      /* op_id; n0=bytes since last poll */
#define VE_EVENT_EXPORT_PROGRESS 6      /* op_id; n0=bytes since last poll */
#define VE_EVENT_HIDDEN_VOLUME_PROTECTION 7 /* vol_id: a write hit the protected area */

typedef struct ve_event {
    int32_t kind;
    int32_t vol_id; /* -1 when not applicable */
    int32_t op_id;  /* 0 when not applicable */
    int32_t i0, i1, i2, i3, i4;
    int64_t n0, n1;
    char text[240];
} ve_event;

/* Pops one queued event into *out; returns 1 if an event was returned, 0 if empty.
 * Progress for one operation is coalesced, so polling at ~10 Hz is plenty. */
VE_API int32_t ve_poll_event(ve_event* out);
/* Optional: called (from an engine thread, no arguments) whenever the queue goes
 * non-empty, so a host can wake a poller instead of using a timer. Must be cheap
 * and must not call back into the engine. Pass NULL to clear. */
VE_API void ve_set_wake_callback(void (*cb)(void));


/* ---- symbolic links (any unlocked slot: ext/NTFS containers and Cryptomator vaults) ----
 * Links are kept out of ve_list_directory on purpose (they are neither files nor folders, so scanners,
 * sync and export never see them). ve_list_symlinks returns ONLY the links of a folder, in the
 * ve_list_directory wire format: "L|targetBytes|mtimeSeconds|name", or "LD|0|mtimeSeconds|name" when the
 * target is a directory. ve_read_symlink returns the raw UTF-8 target (never followed); VE_ERR_FAILED if
 * `path` is not a readable link. ve_create_symlink refuses what the filesystem/vault refuses (absolute or
 * escaping targets, unsupported filesystems): VE_ERR_FAILED, or VE_ERR_READ_ONLY. */
VE_API int32_t ve_list_symlinks(int32_t vol_id, const char* path, ve_buffer* out);
VE_API int32_t ve_read_symlink(int32_t vol_id, const char* path, ve_buffer* out);
VE_API int32_t ve_create_symlink(int32_t vol_id, const char* path, const char* target);

/* ---- folder vaults (gocryptfs / Cryptomator / CryFS) ---------------------
 * Directory-based vaults live in the platform-neutral foldervault/ core. An unlocked one takes a
 * volume slot exactly like a container does: afterwards EVERY ve_* file call above (list, read,
 * write, copy, import, export, streams, space info, lock ...) works on that slot unchanged, so the
 * caller never needs to know which family backs it. Only unlock / create / password change and the
 * few queries below are folder-vault specific.
 *
 * Not available on Windows yet (foldervault/fv_storage.cpp is POSIX-only): there every function
 * below fails with VE_ERR_FAILED and ve_fv_probe reports "no vault". ve_fv_supported() says which.
 *
 * `message` out-buffers (optional, may be NULL) receive a short UTF-8 reason on failure; free them
 * with ve_buffer_free. Passwords are raw UTF-8 bytes and are never retained. */
#define VE_FV_GOCRYPTFS 0
#define VE_FV_CRYPTOMATOR 1
#define VE_FV_CRYFS 2
/* ve_get_container_format() values for an unlocked folder-vault slot (VeraCrypt..plain are 0..4). */
#define VE_FORMAT_GOCRYPTFS 10
#define VE_FORMAT_CRYPTOMATOR 11
#define VE_FORMAT_CRYFS 12

VE_API int32_t ve_fv_supported(void); /* 1 if folder vaults are compiled in, else 0 */

/* Which folder-vault format does the directory `root` look like? Writes VE_FV_* or -1 (none) to
 * *format_out. Password-free and read-only. */
VE_API int32_t ve_fv_probe(const char* root, int32_t* format_out);

/* Opens the vault at `root` into slot `vol_id`. Returns VE_OK, VE_ERR_AUTH_FAILED (wrong password),
 * VE_ERR_FAILED (not a vault / I/O error) or VE_ERR_INVALID_ARG. `combined_key` (CryFS only,
 * may be NULL) is the derived key from an earlier unlock and replaces the password.
 * `backup_key_files` (Cryptomator, read-write unlocks only) keeps .bkup copies of masterkey.cryptomator
 * and vault.cryptomator next to the originals; the other formats ignore it.
 * `derived_key` (optional) receives the CryFS derived key so the caller can offer "remember". */
VE_API int32_t ve_fv_unlock(int32_t vol_id, int32_t format, const char* root,
                            const uint8_t* password, int32_t password_len,
                            const uint8_t* combined_key, int32_t combined_key_len,
                            int32_t read_only, int32_t backup_key_files, const char* local_state_dir,
                            const char* temp_dir, ve_buffer* message, ve_buffer* derived_key);

/* Password-free look at a Cryptomator vault folder from its files alone (nothing is decrypted or
 * written): *code_out = 0 not a (readable) vault, 7 format 7 (migratable), 8 current, -8 key file is
 * version 8+ but vault.cryptomator has not synced yet (NEVER migrate), 6 too old to migrate here. */
VE_API int32_t ve_fv_probe_cryptomator(const char* root, int32_t* code_out);

/* Creates a new vault in the (empty) directory `root`. gocryptfs: cipher 0 AES-256-GCM,
 * 1 XChaCha20-Poly1305, 2 AES-SIV; plaintext_names / deterministic_names flags; long_name_max
 * 0 or 62..255. CryFS: cipher_name (e.g. "xchacha20-poly1305", NULL = default) and block_size
 * (0 = default). Cryptomator ignores all of them. user_entropy (optional) is mixed into key
 * generation like ve_create_container. Returns VE_OK / VE_ERR_FAILED / VE_ERR_INVALID_ARG. */
VE_API int32_t ve_fv_create(int32_t format, const char* root, const uint8_t* password,
                            int32_t password_len, int32_t cipher, int32_t plaintext_names,
                            int32_t deterministic_names, int32_t long_name_max, int32_t block_size,
                            const char* cipher_name, const uint8_t* user_entropy,
                            int32_t user_entropy_len, const char* local_state_dir,
                            const char* temp_dir, ve_buffer* message);

/* Rewraps the key under a new password. VE_OK, VE_ERR_AUTH_FAILED (old password wrong) or VE_ERR_FAILED. */
VE_API int32_t ve_fv_change_password(int32_t format, const char* root, const uint8_t* old_password,
                                     int32_t old_len, const uint8_t* new_password, int32_t new_len,
                                     ve_buffer* message);

/* Cryptomator format 7 -> 8 (one way). Same return codes as ve_fv_change_password. */
VE_API int32_t ve_fv_migrate_cryptomator(const char* root, const uint8_t* password,
                                         int32_t password_len, ve_buffer* message);

/* Queries on an unlocked folder-vault slot (VE_ERR_NOT_UNLOCKED when vol_id is not one). */
/* Vault properties as triples: u32 count, then per item 3 x (u32 length + UTF-8 bytes):
 * key, kind ("s" string / "i" integer / "b" boolean), value. Little-endian. */
VE_API int32_t ve_fv_info(int32_t vol_id, ve_buffer* out);
/* Number of entries hidden from listings in `path` (>= 0), or a negative -VE_ERR_* code. */
VE_API int32_t ve_fv_hidden_entry_count(int32_t vol_id, const char* path);
/* Flushes pending metadata for a file that was written chunk by chunk. */
VE_API int32_t ve_fv_finish_write(int32_t vol_id, const char* path);
/* Brackets a burst of writes (kind 0) or deletes (kind 1) so the vault can defer index work. */
VE_API int32_t ve_fv_batch(int32_t vol_id, int32_t kind, int32_t begin);

/* ---- random-access writes (block containers) ------------------------------------------------------
 * ve_write_file_chunk keeps its historical meaning (a write at offset 0 REPLACES the file). The two calls
 * below are for callers that need ordinary file semantics -- the OS mount layer.
 *   ve_write_file_at     writes `len` bytes at `offset` into an EXISTING file without touching the rest.
 *                        `offset` must be <= the current size (grow with ve_truncate first).
 *   ve_truncate          sets the size of an existing file; growing zero-fills.
 *   ve_create_empty_file creates an empty file (a folder vault commits it immediately).
 * Folder-vault slots only accept chunks in order from offset 0 + ve_fv_finish_write, so the first two
 * return VE_ERR_UNSUPPORTED there (the mount layer buffers instead). */
VE_API int32_t ve_write_file_at(int32_t vol_id, const char* path, int64_t offset, const uint8_t* data, size_t len);
VE_API int32_t ve_truncate(int32_t vol_id, const char* path, int64_t size);
VE_API int32_t ve_create_empty_file(int32_t vol_id, const char* path);

/* ---- archives -----------------------------------------------------------------------------------
 * Reads zip, 7z, rar, tar.*, iso and cpio archives, including split sets (name.7z.001, name.z01 + name.zip --
 * opening any part opens the whole set). A SOURCE is a file inside an unlocked slot (src_vol >= 0, src_path is
 * the vault path) or a host file (src_vol < 0, src_path is a filesystem path). A SINK is memory, a host file or
 * folder (dest_vol < 0), or a vault file or folder (dest_vol >= 0). Nothing is staged on disk for an in-vault
 * source, folder vaults included. Passphrases are raw UTF-8, NULL or "" for none.
 *
 * Every call returns VE_OK when it ran and filled its record, VE_ERR_INVALID_ARG for bad arguments, or another
 * VE_ERR_* if it could not even allocate the answer. What happened to the archive is INSIDE the record
 * (little-endian; a string is u32 length + UTF-8 bytes):
 *     u32 status    0 ok, 1 unsupported format, 2 passphrase required, 3 wrong passphrase, 4 I/O error
 *     u32 flags     bit 0 solid archive, bit 1 7z, bit 2 the run was cancelled (status is still 0)
 *     u32 count     scan: number of entries that follow; extract_all: files extracted; extract_entry: 0
 *     string message   engine error text, empty on success
 * ve_archive_scan appends `count` entries:
 *     string path, u64 uncompressed size, u64 compressed size, i64 mtime (epoch seconds),
 *     u32 flags (bit 0 encrypted, bit 1 directory), i32 index (the value to pass to extract_entry)
 * Free every ve_buffer with ve_buffer_free. */
VE_API int32_t ve_archive_scan(int32_t src_vol, const char* src_path, const char* passphrase, ve_buffer* out);

/* One entry. With dest_path NULL the bytes come back in *data_out; otherwise they are streamed into that host
 * file (dest_vol < 0) or vault file (dest_vol >= 0) and *data_out may be NULL. A failed run removes the partial
 * destination. */
VE_API int32_t ve_archive_extract_entry(int32_t src_vol, const char* src_path, int32_t target_index,
                                        const char* passphrase, int32_t dest_vol, const char* dest_path,
                                        ve_buffer* data_out, ve_buffer* result_out);

/* Everything (or only the entries under sub_path, NULL/"" for all) into the folder dest_dir, created as needed.
 * op_id > 0: progress is reported as VE_EVENT_SPLITJOIN_PROGRESS with n0 = files extracted so far (n1 = 0, the
 * total is unknown), and ve_op_cancel(op_id) stops the run after the current file. */
VE_API int32_t ve_archive_extract_all(int32_t src_vol, const char* src_path, const char* passphrase,
                                      const char* sub_path, int32_t dest_vol, const char* dest_dir,
                                      int32_t op_id, ve_buffer* out);

/* ---- OS mounts (Linux: FUSE 3; Windows: WinFsp, not built yet) -------------------------------------
 * Exposes an unlocked slot as a real folder / drive so any application and the file manager can use it --
 * the desktop equivalent of the Android DocumentsProvider. Works for every format behind a slot.
 *   ve_mount_supported  1 if mounting can work on this machine; else 0 and a short human-readable reason
 *                       in reason_buf (e.g. "libfuse3 / fusermount3 not found").
 *   ve_mount            mount_point must be an existing, empty directory owned by the caller (or absent,
 *                       in which case it is created). *out_mount_id receives the mount's id.
 *   ve_unmount          unmounts and commits pending writes. force=0 returns VE_ERR_BUSY if files are open;
 *                       force=1 detaches regardless. Also reaps a mount that already ended on its own.
 *   ve_list_mounts      u32 count, then per mount u32 length + UTF-8 "<id>|<vol>|<state>|<mount point>"
 *                       with state "active" or "ended" (someone unmounted it from outside).
 *   ve_set_mount_callback  event 1 = mount `mount_id` ended without ve_unmount (external eject / crash of the
 *                       FUSE side). Called from a native thread: forward it to Dart with NativeCallable.listener.
 * ve_lock() unmounts every mount of the slot first, so key material is never wiped under a live mount. */
typedef struct ve_mount_options {
    int32_t struct_size;        /* sizeof(ve_mount_options) */
    int32_t read_only;          /* mount read-only even if the slot is writable */
    int32_t allow_other;        /* let other users reach it (Linux: needs user_allow_other in /etc/fuse.conf) */
    int32_t max_buffer_mb;      /* per open file, folder vaults: in-memory cap for in-place edits; 0 = 256 */
    const char* volume_name;    /* shown by the file manager; NULL = "VaultExplorer" */
    const char* sub_path;       /* vault folder to expose, e.g. "/Documents"; NULL or "/" = whole vault */
} ve_mount_options;

VE_API int32_t ve_mount_supported(char* reason_buf, size_t reason_cap);
VE_API int32_t ve_mount(int32_t vol_id, const char* mount_point_utf8, const ve_mount_options* opts,
                        int64_t* out_mount_id);
VE_API int32_t ve_unmount(int64_t mount_id, int32_t force);
VE_API int32_t ve_list_mounts(ve_buffer* out);
VE_API void ve_set_mount_callback(void (*cb)(int64_t mount_id, int32_t event));
/* Human-readable reason for the most recent failed ve_mount / ve_unmount (e.g. "mount point is not empty").
 * Returns the message length; copies at most cap-1 bytes + NUL into buf. */
VE_API int32_t ve_mount_last_error(char* buf, size_t cap);

#ifdef __cplusplus
}
#endif

#endif /* VE_ENGINE_H */
