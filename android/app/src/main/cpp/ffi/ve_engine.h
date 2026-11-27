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

#define VE_ABI_VERSION 16 /* bump whenever a function/struct is added or changed; the Dart side checks it */

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
/* Raw block devices (ve_unlock_device): */
#define VE_ERR_DEVICE_NOT_FOUND 11   /* no such disk / partition (unplugged, renumbered) */
#define VE_ERR_DEVICE_PERMISSION 12  /* the OS refused: needs root / the disk group / an elevated process */
#define VE_ERR_DEVICE_BUSY 13        /* a write open was refused because the OS has it (or a partition) mounted */
#define VE_ERR_DEVICE_OPEN 14        /* anything else: not a disk or image, already open in another slot, I/O error */
#define VE_ERR_TOO_LARGE 15          /* refused by a size guard (e.g. ve_image_thumbnail: the picture is too big to decode) */
#define VE_ERR_NO_MEMORY 16          /* ran out of memory (ve_image_thumbnail) */

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

/* ---- raw block devices (desktop, ABI 14) ---------------------------------------- */
/* Whole disks and partitions that hold a BitLocker, VeraCrypt or LUKS volume, opened straight from the OS
 * (Linux /dev/sdX, /dev/nvme0n1, /dev/disk/by-id/...; Windows \\.\PhysicalDriveN). A regular file is accepted
 * too (a raw disk image). The engine scans the MBR/GPT partitions for LUKS and BitLocker, then tries VeraCrypt
 * at the start of the device and of every partition (with the hidden-volume header), exactly as it does for a USB
 * mass-storage device on Android. Needs permission to open the device (root / disk group, or an elevated
 * process on Windows). 4Kn disks work for whole-device volumes; partition scanning assumes 512-byte sectors. */

/* UTF-8 JSON array, one object per disk the OS lists:
 *   {"path","name","bus","sizeBytes","sectorSize","removable","readable","writable","inUse","system","formats":[..]}
 * "path" is what ve_unlock_device takes (a stable /dev/disk/by-id path on Linux when there is one). "formats" lists
 * "bitlocker" / "luks" signatures found at the start of a partition (readable disks only; VeraCrypt is invisible
 * until it is unlocked). Free with ve_buffer_free. Empty array where the platform cannot enumerate. */
VE_API int32_t ve_list_block_devices(ve_buffer* out_json);

typedef struct ve_unlock_device_params {
    int32_t struct_size;            /* sizeof(ve_unlock_device_params) */
    const char* device_path;        /* UTF-8; the "path" of ve_list_block_devices, or a disk image */
    int32_t vol_id;                 /* slot to unlock into */
    const uint8_t* password;        /* UTF-8 bytes, may be NULL when keyfiles are used */
    int32_t password_len;
    int32_t pim;                    /* 0 = default */
    int32_t cipher_id;              /* 255 = auto-detect */
    int32_t hash_id;                /* 255 = auto-detect */
    const uint8_t* preserved_key;   /* optional cached derived key material */
    int32_t preserved_key_len;
    const int32_t* keyfile_fds;     /* owned by the engine */
    int32_t keyfile_count;
    int32_t read_only;              /* 0 opens the device read-write (exclusive on Linux) */
    int64_t partition_offset_hint;  /* start sector (512-byte units) of the partition to try first, -1 = scan */
    /* Hidden-volume protection (VeraCrypt): all NULL/0 to disable. */
    const uint8_t* hidden_password;
    int32_t hidden_password_len;
    int32_t hidden_pim;
    int32_t hidden_cipher_id;
    int32_t hidden_hash_id;
    const int32_t* hidden_keyfile_fds;
    int32_t hidden_keyfile_count;
    int32_t* os_error_out;          /* optional: errno / GetLastError() of a failed open */
} ve_unlock_device_params;

/* Opens the device, unlocks it into slot vol_id and mounts its file system. VE_OK on success; VE_ERR_FAILED when
 * no volume on it opened with these credentials; VE_ERR_DEVICE_* when the device itself could not be opened;
 * VE_ERR_MOUNT_FAILED / VE_ERR_CANCELLED as ve_unlock. Lock it with ve_lock, which also closes the device. */
VE_API int32_t ve_unlock_device(const ve_unlock_device_params* params);
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

/* Check & Repair for folder vaults (foldervault/fv_check.h). format: VE_FV_*; root: the vault folder. password
 * (UTF-8, may be NULL/0 for a structure-only check; a repair needs credentials) or session_vol >= 0, the slot of
 * the same vault unlocked in this process -- its keys are used instead of the password and never leave the process.
 * op_id > 0 streams the step log as VE_EVENT_REPAIR_LOG. Returns VE_OK with a record (little-endian, a string is
 * u32 length + UTF-8):
 *     u32 outcome     0 ok, 1 wrong password, 2 not a vault / refused
 *     string message  why, when outcome != 0
 *   check, outcome 0:   u32 files scanned, u32 deep scan (0/1), issues
 *   repair, outcome 0:  u32 fixed, u32 recovered (moved to /LOST+FOUND), u32 removed, issues (what is still wrong)
 *   issues:             u32 count, then count x { u32 severity (0 info, 1 warning, 2 critical), string path,
 *                       string message }
 * Free the buffer with ve_buffer_free. */
VE_API int32_t ve_fv_check(int32_t format, const char* root, const uint8_t* password, int32_t password_len,
                           int32_t session_vol, const char* local_state_dir, const char* temp_dir, int32_t op_id,
                           ve_buffer* out);
VE_API int32_t ve_fv_repair(int32_t format, const char* root, const uint8_t* password, int32_t password_len,
                            int32_t session_vol, const char* local_state_dir, const char* temp_dir, int32_t op_id,
                            ve_buffer* out);
/* The file that holds a folder vault's key material (gocryptfs.conf, masterkey.cryptomator, cryfs.config), UTF-8
 * without a terminator. */
VE_API int32_t ve_fv_config_file_name(int32_t format, ve_buffer* out);
/* Password-free structural check of a config file's bytes: VE_OK when it parses as a genuine config of that
 * format, VE_ERR_FAILED with the reason in *reason when it does not. */
VE_API int32_t ve_fv_validate_config(int32_t format, const uint8_t* bytes, int32_t len, ve_buffer* reason);

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

/* ---- Check & Repair, header backup (unmounted container files and mounted volumes) -------------
 * Every fd is a descriptor from ve_open_file and is CLOSED by the call on every path (ownership transfers, like
 * the keyfile fds of ve_unlock). op_id > 0 streams the step-by-step log as VE_EVENT_REPAIR_LOG; <= 0 skips it.
 * Every call returns VE_OK when it ran and filled its outputs, VE_ERR_INVALID_ARG for bad arguments. */

/* code_out: RepairDiagnosisCode (0 healthy, 1 header corrupted, 2 file system dirty). format_out: ContainerFormat
 * (0 VeraCrypt, 1 LUKS1, 2 LUKS2, 3 BitLocker, 4 plain) or -1 when the file is not recognised. */
VE_API int32_t ve_repair_diagnose_file(int32_t fd, int32_t op_id, int32_t* code_out, int32_t* format_out);
/* LUKS2: restore the primary header from the checksum-verified secondary copy. VE_OK restored, VE_ERR_FAILED not. */
VE_API int32_t ve_repair_restore_luks2(int32_t fd, int32_t op_id);
/* VeraCrypt/TrueCrypt: restore the primary header from the backup header that verifies against the password.
 * cipher_id / hash_id 255 auto-detect. result_out: 0 success, 1 wrong password, 2 already healthy, 3 I/O error. */
VE_API int32_t ve_repair_restore_veracrypt(int32_t fd, const uint8_t* password, int32_t password_len, int32_t pim,
                                           int32_t cipher_id, int32_t hash_id, int32_t op_id, int32_t* result_out);
/* A mounted volume's file system: code_out as above (never 1); check: ok_out 1 when it is clean or was repaired. */
VE_API int32_t ve_repair_diagnose_mounted(int32_t vol_id, int32_t op_id, int32_t* code_out);
VE_API int32_t ve_repair_check_mounted(int32_t vol_id, int32_t op_id, int32_t* ok_out);
/* Header backup export. Record (little-endian): u32 result (0 ok, 1 unrecognised file, 2 unsupported format,
 * 3 header unreadable, 4 I/O error), u32 ContainerFormat (0xFFFFFFFF when not meaningful), u32 payload length,
 * payload bytes. */
VE_API int32_t ve_header_export(int32_t fd, int32_t op_id, ve_buffer* out);
/* Header restore: format is ContainerFormat (0 VeraCrypt, 1 LUKS1, 2 LUKS2). password/keyfile_fds only matter for
 * VeraCrypt (the keyfile fds are mixed into the password and closed). result_out: 0 success, 1 wrong password,
 * 2 backup invalid, 3 target smaller than the backup, 4 I/O error. */
VE_API int32_t ve_header_restore(int32_t fd, int32_t format, const uint8_t* payload, int32_t payload_len,
                                 const uint8_t* password, int32_t password_len, int32_t pim, int32_t cipher_id,
                                 int32_t hash_id, int32_t op_id, const int32_t* keyfile_fds, int32_t keyfile_count,
                                 int32_t* result_out);

/* ---- container tools: expand, grow the file system, add a hidden volume to an existing volume ---------
 * The engine side of the "Expand volume" and "Add hidden volume" tools (Android: VeraCryptToolsHandlers.kt).
 * Every fd is a descriptor from ve_open_file -- opened read/write, except for ve_hidden_analyze which only reads --
 * and is CLOSED by the call on every path (ownership transfers, like the keyfile fds of ve_unlock), so are the
 * keyfile fds. Passwords are raw UTF-8 bytes (a BitLocker credential is a password or the 48-digit recovery key).
 * Keyfiles follow each format's own rule: VeraCrypt mixes them into the password; for LUKS the first replaces it.
 * A container file that is currently unlocked in a slot of this process is refused (outcome 8).
 *
 * Every call returns VE_OK when it ran and filled its output, VE_ERR_INVALID_ARG for bad arguments (the fds are
 * closed first) or VE_ERR_EXCEPTION. What happened to the container is INSIDE the output.
 *
 * Expand and grow calls fill int32_t result_out[3]:
 *     [0] outcome  0 ok, 1 wrong password or keyfile, 2 not expandable (not a plain standard volume that fills its
 *                  file / unsupported layout), 3 new size not larger, 4 I/O error, 5 unreadable keyfile, 6 not LUKS,
 *                  7 damaged or unsupported header / metadata, 8 container in use, 9 not BitLocker, 10 the virtual
 *                  disk cannot be grown, 11 the BitLocker partition cannot be grown
 *     [1] file-system step  -1 not run, else 0 grown, 1 already fills, 2 unsupported (FAT / exFAT / unknown),
 *                  3 needs a check first, 4 busy, 5 failed
 *     [2] file-system kind  0 unknown, 1 FAT12, 2 FAT16, 3 FAT32, 4 exFAT, 5 NTFS, 6 ext2, 7 ext3, 8 ext4
 * The container expansion stands whatever the file-system step reports. new_size_bytes is rounded down to the
 * format's unit; for a BitLocker VHD/VHDX it is the new virtual disk size. cipher_id / hash_id 255 auto-detect. */
VE_API int32_t ve_expand_veracrypt(int32_t fd, const uint8_t* password, int32_t password_len, int32_t pim,
                                   int32_t cipher_id, int32_t hash_id, const int32_t* keyfile_fds,
                                   int32_t keyfile_count, int64_t new_size_bytes, int32_t init_free_space,
                                   int32_t grow_file_system, int32_t* result_out);
VE_API int32_t ve_expand_luks(int32_t fd, const uint8_t* password, int32_t password_len, const int32_t* keyfile_fds,
                              int32_t keyfile_count, int64_t new_size_bytes, int32_t init_free_space,
                              int32_t grow_file_system, int32_t* result_out);
VE_API int32_t ve_expand_bitlocker(int32_t fd, const uint8_t* password, int32_t password_len, int64_t new_size_bytes,
                                   int32_t init_free_space, int32_t grow_file_system, int32_t* result_out);
/* Only the file-system step, for a volume whose container was expanded earlier. Same result_out. */
VE_API int32_t ve_grow_veracrypt_fs(int32_t fd, const uint8_t* password, int32_t password_len, int32_t pim,
                                    int32_t cipher_id, int32_t hash_id, const int32_t* keyfile_fds,
                                    int32_t keyfile_count, int32_t* result_out);
VE_API int32_t ve_grow_luks_fs(int32_t fd, const uint8_t* password, int32_t password_len, const int32_t* keyfile_fds,
                               int32_t keyfile_count, int32_t* result_out);
VE_API int32_t ve_grow_bitlocker_fs(int32_t fd, const uint8_t* password, int32_t password_len, int32_t* result_out);

/* How large a hidden volume fits at the end of a standard VeraCrypt volume (read-only). Fills int64_t result_out[4]:
 *     [0] outcome  0 ok, 1 wrong password, 2 unsupported file system (needs FAT / exFAT / NTFS), 4 I/O error,
 *                  5 unreadable keyfile, 6 not a plain full-size standard volume
 *     [1] file-system kind (as above, 1..5)   [2] cluster size in bytes   [3] largest hidden volume in bytes (0 = no room) */
VE_API int32_t ve_hidden_analyze(int32_t fd, const uint8_t* password, int32_t password_len, int32_t pim,
                                 int32_t cipher_id, int32_t hash_id, const int32_t* keyfile_fds,
                                 int32_t keyfile_count, int64_t* result_out);

/* Adds a hidden volume to the existing standard volume (VeraCrypt "direct mode"): the outer volume's own header and
 * files are not touched. hidden_file_system: "FAT" | "exFAT" | "NTFS". hidden_password must differ from the outer one.
 * *outcome_out: 0 created, 1 wrong outer password, 2 unsupported outer file system, 3 no room / size too large,
 * 4 I/O error, 5 unreadable keyfile, 6 invalid (not a plain full-size standard volume, hidden password too long or
 * equal to the outer one). */
typedef struct ve_hidden_in_existing_params {
    int32_t struct_size;               /* sizeof(ve_hidden_in_existing_params) */
    int32_t fd;                        /* the standard volume's file, read/write; closed by the call */
    const uint8_t* outer_password;
    int32_t outer_password_len;
    int32_t outer_pim;
    int32_t outer_cipher_id;           /* 255 = auto-detect */
    int32_t outer_hash_id;             /* 255 = auto-detect */
    const int32_t* outer_keyfile_fds;  /* owned by the call */
    int32_t outer_keyfile_count;
    const uint8_t* hidden_password;
    int32_t hidden_password_len;
    int32_t hidden_pim;
    const char* hidden_file_system;
    int64_t hidden_size_bytes;
    int32_t hidden_cipher_id;
    int32_t hidden_hash_id;
    const int32_t* hidden_keyfile_fds; /* owned by the call */
    int32_t hidden_keyfile_count;
    int32_t quick_format;
    const uint8_t* user_entropy;       /* optional, mixed on top of the OS RNG */
    int32_t user_entropy_len;
} ve_hidden_in_existing_params;

VE_API int32_t ve_hidden_create_in_existing(const ve_hidden_in_existing_params* params, int32_t* outcome_out);

/* ---- composite containers (ABI 13) ----------------------------------------------------------------
 * One VeraCrypt volume spread over several ordinary host files ("carriers": photos, videos, documents, ...). Each
 * carrier keeps its own content and carries its share of the encrypted volume after it, followed by a small
 * header-keyed trailer that lets the share be found again without any index. Only standard VeraCrypt volumes are
 * composite (no LUKS, BitLocker or hidden volume).
 *
 * Carriers are host PATHS (UTF-8): the engine opens them itself, a few at a time, so the number of carriers is not
 * limited by open descriptors. Keyfile descriptors (the one thing here that is a descriptor) belong to the call and
 * are closed on every path, like the keyfile fds of ve_unlock. The order the paths are given in never matters: the
 * engine sorts the carriers canonically (by a digest of each file's first bytes) in all three calls.
 *
 * Failures answer VE_ERR_FAILED and, when error_out is not NULL, put a code in it (UTF-8, no NUL; free with
 * ve_buffer_free): create -- NO_EXTENTS_DERIVED, CARRIER_CAPACITY_CHANGED, INVALID_VOLUME_ID, CARRIER_OPEN_FAILED,
 * CARRIER_CORRUPTION_GUARD, SIZE_TOO_SMALL, PASSWORD_TOO_LONG, KEYFILE_FAILED, URANDOM_READ_FAILED, KDF_FAILED,
 * FORMAT_FAILED; unlock -- NO_EXTENTS_DETECTED, INVALID_VOLUME_ID, SIZE_TOO_SMALL, HEADER_READ_FAILED,
 * KEYFILE_FAILED, INCORRECT_PASSWORD_OR_INVALID_CONTAINER, COMPOSITE_CARRIERS_INCOMPLETE (a carrier is missing),
 * CASCADE_KEY_SETUP_FAILED, FILESYSTEM_MOUNT_FAILED (with VE_ERR_MOUNT_FAILED). An unlock stopped by
 * ve_request_cancel_unlock answers VE_ERR_CANCELLED.
 */

/* Sizes a set of carriers (read-only). safety_margin_pct is the share of each carrier's size that may be added to it
 * (1..50; larger values mean "reserve this much", i.e. 100 - value is added; 0 or > 100 = 10). On VE_OK, out holds
 * (little-endian): u64 totalAllocatableBytes, u32 count, then per carrier in canonical order: u32 fileIndex,
 * u32 inputIndex (the position in carrier_paths), u32 tier (0 spec-guaranteed skippable data, 1 tolerated by common
 * readers, 2 appended after the end), u64 fileSize, u64 payloadOffset, u64 allocatableBytes, u32 formatLen + the
 * detected format ("png", "jpeg", "isobmff", "generic", "composite_carrier" for a carrier that already holds a
 * share, "archive_unsupported", ...), u32 pathLen + the path. */
VE_API int32_t ve_composite_profile(const char* const* carrier_paths, int32_t carrier_count, int32_t safety_margin_pct,
                                    ve_buffer* out);

typedef struct ve_composite_create_params {
    int32_t struct_size;            /* sizeof(ve_composite_create_params) */
    int32_t vol_id;                 /* a FREE slot: it formats the volume and is left empty (locked) on return */
    const char* const* carrier_paths;
    int32_t carrier_count;
    int64_t requested_bytes;        /* capacity wanted; 0 = everything the carriers can hold. Must equal what
                                       ve_composite_profile reported when > 0 (else CARRIER_CAPACITY_CHANGED) */
    int32_t safety_margin_pct;      /* 1..50 = growth per carrier in percent; anything else = 10 */
    const uint8_t* password;        /* UTF-8 bytes without NUL, may be NULL when keyfiles are used; a password or at
                                       least one keyfile is required (VE_ERR_INVALID_ARG otherwise) */
    int32_t password_len;
    int32_t pim;
    const char* file_system;        /* "fat" | "exfat" | "ntfs" | "ext2" | "ext3" | "ext4" */
    int32_t cipher_id;              /* 255 = default (AES) */
    int32_t hash_id;                /* 255 = default (SHA-512) */
    const int32_t* keyfile_fds;     /* owned by the call */
    int32_t keyfile_count;
    int32_t quick_format;
    const uint8_t* user_entropy;    /* optional, mixed on top of the OS RNG */
    int32_t user_entropy_len;
} ve_composite_create_params;

/* Writes the volume's shares into the carriers (growing each) and formats it. WRITES TO THE CARRIER FILES. VE_OK when
 * the volume exists; it is not left unlocked. Refused before any carrier is touched: NO_EXTENTS_DERIVED,
 * CARRIER_CAPACITY_CHANGED, SIZE_TOO_SMALL (under 300 KiB in all) and PASSWORD_TOO_LONG (over 128 bytes). A failure
 * after the carriers were written can leave them grown by the unused share, which is harmless to their content. */
VE_API int32_t ve_composite_create(const ve_composite_create_params* params, ve_buffer* error_out);

typedef struct ve_composite_unlock_params {
    int32_t struct_size;            /* sizeof(ve_composite_unlock_params) */
    int32_t vol_id;                 /* slot to unlock into */
    const char* const* carrier_paths;
    int32_t carrier_count;
    const uint8_t* password;        /* UTF-8 bytes, may be NULL when keyfiles are used */
    int32_t password_len;
    int32_t pim;
    int32_t cipher_id;              /* 255 = auto-detect */
    int32_t hash_id;                /* 255 = auto-detect */
    const int32_t* keyfile_fds;     /* owned by the call */
    int32_t keyfile_count;
    int32_t read_only;
} ve_composite_unlock_params;

/* Finds every carrier's share, checks that none is missing, unlocks the volume into vol_id and mounts its file
 * system. After VE_OK the slot behaves exactly like one unlocked by ve_unlock (ve_lock, ve_list_directory, ... and
 * ve_get_container_format / ve_get_matched_*_id). */
VE_API int32_t ve_composite_unlock(const ve_composite_unlock_params* params, ve_buffer* error_out);

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

/* Creates an archive (format = ArchiveFormat: 0 zip, 1 7z, 2 tar, 3 tar.gz, 4 tar.bz2, 5 tar.xz, 6 tar.zst,
 * 7 tar.lzma, 8 iso, 9 cpio). `count` sources, each a path (src_paths[i]: a vault path when src_vol >= 0,
 * otherwise a host path) stored under entry_names[i]; a name ending in '/' (or a host folder) is a folder entry.
 * modified_secs may be NULL; a value <= 0 takes the host file's own modification time. The archive goes to
 * dest_path: a host file (dest_vol < 0, replaced if it exists) or a vault file (dest_vol >= 0).
 * split_size > 0 (zip and 7z only, 64 KiB .. 4 GiB - 2) writes parts instead -- 7z: <dest>.001, .002, ...;
 * zip: <dest without .zip>.z01, .z02, ..., and the last part <dest without .zip>.zip -- and never replaces a file.
 * compression_level -1 is the library default, 0 store, 1..9; compression_method 0 is the format's own codec
 * (1 Deflate, 2 LZMA, 3 LZMA2). The 7z and ISO writers assemble the archive in a temporary file: temp_dir (NULL to
 * leave the process setting alone) is where it goes ($TMPDIR, or TMP/TEMP on Windows), and it should be private.
 * Progress is VE_EVENT_SPLITJOIN_PROGRESS in SOURCE bytes (n0 done, n1 total); ve_op_cancel(op_id) stops the run.
 * A failed or cancelled run removes what it wrote. The record's count is the number of files written (1, or the
 * number of parts); bit 2 of its flags is set when the run was cancelled. */
VE_API int32_t ve_archive_create(int32_t src_vol, const char* const* src_paths, const char* const* entry_names,
                                 const int64_t* modified_secs, int32_t count, int32_t dest_vol,
                                 const char* dest_path, int32_t format, const char* passphrase,
                                 int32_t encrypt_filenames, int32_t compression_level,
                                 int32_t compression_method, uint64_t split_size, const char* temp_dir,
                                 int32_t op_id, ve_buffer* out);

/* ---- image thumbnails (ABI 15) -----------------------------------------------------------------------
 * Decodes a JPEG, PNG or WebP and answers a small picture that fits target_size x target_size (never enlarged),
 * in ONE blocking call: the source is read through a read-ahead buffer (never loaded whole, except WebP), a JPEG
 * is shrunk inside its DCT (1/2, 1/4, 1/8), a PNG is box-filtered row by row, and the result is a JPEG of the given
 * quality (1..100) -- or a PNG when some pixel is really not opaque. EXIF orientation is applied, so the size
 * reported is the picture as a viewer shows it. preserve_alpha is accepted for parity with Android and does not
 * change the outcome. Thread-safe; run it in a worker isolate.
 *   ve_image_thumbnail       a file inside an unlocked slot (container or folder vault)
 *   ve_image_thumbnail_file  a file on the host (UTF-8 path)
 *   ve_image_thumbnail_mem   a picture already in memory (e.g. a video frame)
 * max_source_bytes > 0 refuses a larger file (VE_ERR_TOO_LARGE); <= 0 takes the 256 MiB default.
 * `info` receives VE_IMAGE_INFO_COUNT int32 values:
 *   [0] 1 = PNG, 0 = JPEG   [1] source width   [2] source height   [3] thumbnail width   [4] thumbnail height
 *   [5] 1 = some pixel is not opaque   [6] 1 = the thumbnail looks blank (flat / black / white / low contrast)
 * Results: VE_OK; VE_ERR_UNSUPPORTED (not one of the three formats, an animated WebP, a CMYK JPEG: the caller should
 * use another decoder); VE_ERR_TOO_LARGE; VE_ERR_NO_MEMORY; VE_ERR_NOT_UNLOCKED / VE_ERR_INVALID_ARG; otherwise
 * VE_ERR_FAILED (missing, unreadable or corrupt). *out is empty on every failure. */
#define VE_IMAGE_INFO_COUNT 8
VE_API int32_t ve_image_thumbnail(int32_t vol_id, const char* path, int32_t target_size, int32_t quality,
                                  int32_t preserve_alpha, int64_t max_source_bytes, ve_buffer* out, int32_t* info);
VE_API int32_t ve_image_thumbnail_file(const char* host_path_utf8, int32_t target_size, int32_t quality,
                                       int32_t preserve_alpha, int64_t max_source_bytes, ve_buffer* out, int32_t* info);
VE_API int32_t ve_image_thumbnail_mem(const uint8_t* data, size_t len, int32_t target_size, int32_t quality,
                                      int32_t preserve_alpha, ve_buffer* out, int32_t* info);

/* ---- video thumbnails (ABI 16) ---------------------------------------------------------------------
 * One picture of a video, decoded by the engine itself (FFmpeg: software, no player, no loopback server) in ONE
 * blocking call: the container header is read through a read-ahead buffer, a single keyframe is decoded and scaled to
 * fit target_size x target_size (rotation and pixel aspect applied), and the answer is a JPEG of the given quality.
 * The result layout and result codes are those of the image calls above; info[7] is the duration in milliseconds
 * (0 when the container does not say), and info[1]/[2] are the picture as shown (what an aspect ratio wants).
 *   strategy        0 = the start; 1 = the picture at frame_position; 2 = the start, and when that looks blank
 *                   (black leader, fade-in, slate) the first not-blank picture at frame_position, 25% or 45%
 *   frame_position  fraction of the duration, clamped to 0.05 .. 0.90
 *   explicit_time_us >= 0: exactly that point (0 = the start), strategy ignored, nothing retried
 *   timeout_ms      for the whole call (retries included); <= 0 takes 20000
 * VE_ERR_UNSUPPORTED means this build cannot open or decode it (an unknown container, a codec that is not compiled
 * in, or an engine built without FFmpeg): the caller should use another route. VE_ERR_FAILED: a video it understands
 * but no picture could be made (corrupt, no video stream, timed out, unreadable). Thread-safe; run it in a worker.
 *   ve_video_thumbnail       a file inside an unlocked slot
 *   ve_video_thumbnail_file  a file on the host (UTF-8 path)
 *   ve_video_thumbnails_available  1 when this engine was built with FFmpeg, else 0 */
VE_API int32_t ve_video_thumbnail(int32_t vol_id, const char* path, int32_t target_size, int32_t quality,
                                  int32_t strategy, double frame_position, int64_t explicit_time_us,
                                  int32_t timeout_ms, ve_buffer* out, int32_t* info);
VE_API int32_t ve_video_thumbnail_file(const char* host_path_utf8, int32_t target_size, int32_t quality,
                                       int32_t strategy, double frame_position, int64_t explicit_time_us,
                                       int32_t timeout_ms, ve_buffer* out, int32_t* info);
VE_API int32_t ve_video_thumbnails_available(void);

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
