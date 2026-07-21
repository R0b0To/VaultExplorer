/* -*- coding: utf-8 -*- */
/* -*- mode: c -*- */
/*
 * Dislocker -- enables to read/write on BitLocker encrypted partitions under
 * Linux
 *
 * virtual_io.h -- VaultExplorer addition, not upstream.
 *
 * Lets a caller of the library hand dislocker a volume that has no real
 * filesystem path -- e.g. one only reachable through this app's USB
 * sector-transport JNI calls -- instead of the real path dis_open() would
 * otherwise require.
 *
 * The callback shape deliberately mirrors libbfio's (lseek-style:
 * read/write operate on an internally-tracked position, no explicit
 * offset parameter) since that's the same shape this codebase's existing
 * libbde/libbfio bridge (bitlocker_backend.cpp's BdeIoContext) already
 * uses. Porting that bridge to this API is meant to be close to a
 * find-and-replace.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 */
#ifndef DIS_VIRTUAL_IO_H
#define DIS_VIRTUAL_IO_H

#include <stdint.h>
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif


/**
 * Callback set for a virtual (non-path-backed) BitLocker volume source.
 * All five are lseek(2)/read(2)/write(2)-shaped: position is tracked
 * internally by the implementation behind user_data, not passed in.
 *
 * - read/write: return the number of bytes transferred, or -1 on error
 *   (errno need not be set -- dislocker only checks for a negative/short
 *   result, same as it already does for real pread()/pwrite()).
 * - seek: return the resulting absolute position, or (off_t)-1 on error.
 * - close: optional (may be NULL). Called exactly once, when dislocker
 *   tears the volume down (dis_close() on this fd). Does NOT imply
 *   freeing user_data -- the registrant still owns that lifetime.
 */
typedef struct {
	ssize_t (*read)(void* user_data, uint8_t* buffer, size_t size);
	ssize_t (*write)(void* user_data, const uint8_t* buffer, size_t size);
	off_t   (*seek)(void* user_data, off_t offset, int whence);
	int     (*close)(void* user_data); /* may be NULL */
	void*   user_data;
} dis_virtual_io_t;


/**
 * Registers a virtual I/O backend and returns a fake fd to pass as
 * DIS_OPT_VOLUME_PATH is normally used for -- see virtual_io.h's header
 * comment and dis_virtual_io_fake_path(). The struct pointed to by `io`
 * is copied; the caller does not need to keep it alive past this call
 * (user_data itself is a pointer the caller DOES still own).
 *
 * Returns a negative fake-fd handle on success, or 0 if every slot
 * (DIS_VIRTUAL_FD_SLOTS) is already in use.
 */
int dis_virtual_io_register(const dis_virtual_io_t* io);

/**
 * Frees the slot for reuse. Does NOT call the close callback (dis_close()
 * on the fake fd already does that as part of normal teardown) -- this
 * is for the case a caller needs to abandon a slot it registered but
 * never handed to dis_initialize() (e.g. detection probe failed before
 * dis_initialize() was even called).
 */
void dis_virtual_io_unregister(int fake_fd);

/** True if `fd` is a fake fd previously returned by _register(), not a real OS fd. */
int dis_virtual_io_is_virtual(int fd);


/*
 * ---------------------------------------------------------------------
 * Dispatch functions below this line are for common.c/inouts/sectors.c
 * only (patched call sites route here instead of the real syscall once
 * dis_virtual_io_is_virtual(fd) is true). Not meant to be called
 * directly by library users -- go through dis_setopt(DIS_OPT_...) /
 * dis_read() / dis_write() / dis_lseek() / dis_close() as normal, they
 * already do this check internally.
 * ---------------------------------------------------------------------
 */
ssize_t dis_virtual_io_read(int fake_fd, void* buf, size_t count);
ssize_t dis_virtual_io_write(int fake_fd, const void* buf, size_t count);
off_t   dis_virtual_io_lseek(int fake_fd, off_t offset, int whence);
int     dis_virtual_io_close(int fake_fd);

/* pread(2)/pwrite(2)-shaped: atomic seek-then-transfer, for
 * inouts/sectors.c's hot path (which never mixes lseek+read/write for
 * the real-fd case either -- it always uses pread/pwrite directly). */
ssize_t dis_virtual_io_pread(int fake_fd, void* buf, size_t count, off_t offset);
ssize_t dis_virtual_io_pwrite(int fake_fd, const void* buf, size_t count, off_t offset);


#ifdef __cplusplus
}
#endif

#endif /* DIS_VIRTUAL_IO_H */
