/*
 * Glue for e2fsprogs' resize2fs engine (resize/resize2fs.c + resize/extent.c), which the
 * app builds into libext2fs to grow an ext2/3/4 file system in place
 * (extGrowToFit in ext_backend.cpp).
 *
 * resize_fs() brackets each phase with init_resource_track()/print_resource_track(). Upstream
 * defines them in resize/resource_track.c, which reads sbrk()/getrusage()/gettimeofday() to
 * print timing and memory statistics for resize2fs's debug flags. The app never enables
 * those flags, so these are the no-op equivalents: no sbrk, no stdio.
 */
#include "config.h"
#include "resize2fs.h"

void init_resource_track(struct resource_track *track, const char *desc, io_channel channel)
{
	(void) channel;
	memset(track, 0, sizeof(*track));
	track->desc = desc;
}

void print_resource_track(ext2_resize_t rfs, struct resource_track *track, io_channel channel)
{
	(void) rfs;
	(void) track;
	(void) channel;
}

/*
 * ext2fs_dup_handle() (dupfs.c) asks for the direct-I/O alignment of the MMP file descriptor.
 * Upstream defines it in lib/ext2fs/getsectsize.c, which CMakeLists.txt leaves out of libext2fs
 * (it probes real block devices). The app's volumes are never backed by an MMP descriptor, and
 * 0 is the upstream answer for "no alignment requirement / unknown".
 */
int ext2fs_get_dio_alignment(int fd)
{
	(void) fd;
	return 0;
}
