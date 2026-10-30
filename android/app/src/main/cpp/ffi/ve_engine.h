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

#define VE_ABI_VERSION 3 /* bump whenever a function/struct is added or changed; the Dart side checks it */

/* ---- result codes ------------------------------------------------------- */
#define VE_OK 0
#define VE_ERR_FAILED 1        /* wrong password / bad format / I/O error / not found */
#define VE_ERR_CANCELLED 2     /* unlock cancelled via ve_request_cancel_unlock */
#define VE_ERR_NOT_UNLOCKED 3  /* vol_id has no active session */
#define VE_ERR_READ_ONLY 4     /* write attempted on a read-only mount */
#define VE_ERR_INVALID_ARG 5
#define VE_ERR_EXCEPTION 6     /* a C++ exception was caught at the boundary */
#define VE_ERR_MOUNT_FAILED 7  /* decrypted OK but the filesystem could not be mounted */

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

/* ---- filesystem operations on an unlocked slot ---------------------------
 * Paths are UTF-8, '/'-separated, relative to the volume root ("/" or ""). */

/* Directory listing, packed as: u32 count, then count x (u32 len, len bytes),
 * all little-endian. Each entry is the engine's directory-entry wire string. */
VE_API int32_t ve_list_directory(int32_t vol_id, const char* path, ve_buffer* out);

/* Sizes: >= 0 on success, < 0 on error (-VE_ERR_*). Missing path reads as 0. */
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

#ifdef __cplusplus
}
#endif

#endif /* VE_ENGINE_H */
