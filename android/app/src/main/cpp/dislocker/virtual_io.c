/* -*- coding: utf-8 -*- */
/* -*- mode: c -*- */
/*
 * virtual_io.c -- VaultExplorer addition, not upstream. See virtual_io.h.
 */
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h> /* SEEK_SET */

#include "dislocker/virtual_io.h"

/*
 * Fake fds live in (DIS_VIRTUAL_FD_BASE - N, DIS_VIRTUAL_FD_BASE], all
 * negative, all far from the -1 "open failed" sentinel every caller in
 * this codebase already checks for, and disjoint from real fds (which
 * are always >= 0).
 */
#define DIS_VIRTUAL_FD_BASE   (-1000)
#define DIS_VIRTUAL_FD_SLOTS  16

typedef struct {
	int               in_use;
	dis_virtual_io_t  io;
	off_t             position;
	pthread_mutex_t   lock; /* guards position + the seek-then-transfer
	                          * pair below from racing itself; does NOT
	                          * make two *different* fake fds mutually
	                          * exclusive, same granularity as a real
	                          * fd's kernel-held file position would be. */
} dis_virtual_io_slot_t;

static dis_virtual_io_slot_t g_slots[DIS_VIRTUAL_FD_SLOTS];
static pthread_mutex_t g_table_lock = PTHREAD_MUTEX_INITIALIZER;
static int g_table_initialized = 0;

static void ensure_table_initialized(void)
{
	pthread_mutex_lock(&g_table_lock);
	if(!g_table_initialized)
	{
		memset(g_slots, 0, sizeof(g_slots));
		int i;
		for(i = 0; i < DIS_VIRTUAL_FD_SLOTS; ++i)
			pthread_mutex_init(&g_slots[i].lock, NULL);
		g_table_initialized = 1;
	}
	pthread_mutex_unlock(&g_table_lock);
}

static int slot_index_for_fd(int fd)
{
	if(fd > DIS_VIRTUAL_FD_BASE || fd <= DIS_VIRTUAL_FD_BASE - DIS_VIRTUAL_FD_SLOTS)
		return -1;
	return DIS_VIRTUAL_FD_BASE - fd;
}

int dis_virtual_io_is_virtual(int fd)
{
	return slot_index_for_fd(fd) >= 0;
}

int dis_virtual_io_register(const dis_virtual_io_t* io)
{
	if(!io || !io->read || !io->seek)
		return 0;

	ensure_table_initialized();

	pthread_mutex_lock(&g_table_lock);
	int i;
	for(i = 0; i < DIS_VIRTUAL_FD_SLOTS; ++i)
	{
		if(!g_slots[i].in_use)
		{
			g_slots[i].in_use   = 1;
			g_slots[i].io       = *io;
			g_slots[i].position = 0;
			pthread_mutex_unlock(&g_table_lock);
			return DIS_VIRTUAL_FD_BASE - i;
		}
	}
	pthread_mutex_unlock(&g_table_lock);
	return 0; /* every slot in use */
}

void dis_virtual_io_unregister(int fake_fd)
{
	int idx = slot_index_for_fd(fake_fd);
	if(idx < 0)
		return;

	pthread_mutex_lock(&g_table_lock);
	g_slots[idx].in_use = 0;
	memset(&g_slots[idx].io, 0, sizeof(g_slots[idx].io));
	pthread_mutex_unlock(&g_table_lock);
}

int dis_virtual_io_close(int fake_fd)
{
	int idx = slot_index_for_fd(fake_fd);
	if(idx < 0)
		return -1;

	int ret = 0;
	if(g_slots[idx].io.close)
		ret = g_slots[idx].io.close(g_slots[idx].io.user_data);

	dis_virtual_io_unregister(fake_fd);
	return ret;
}

ssize_t dis_virtual_io_read(int fake_fd, void* buf, size_t count)
{
	int idx = slot_index_for_fd(fake_fd);
	if(idx < 0)
		return -1;

	dis_virtual_io_slot_t* s = &g_slots[idx];
	pthread_mutex_lock(&s->lock);
	ssize_t n = s->io.read(s->io.user_data, (uint8_t*) buf, count);
	if(n > 0)
		s->position += n;
	pthread_mutex_unlock(&s->lock);
	return n;
}

ssize_t dis_virtual_io_write(int fake_fd, const void* buf, size_t count)
{
	int idx = slot_index_for_fd(fake_fd);
	if(idx < 0)
		return -1;

	dis_virtual_io_slot_t* s = &g_slots[idx];
	if(!s->io.write)
		return -1; /* read-only backend */

	pthread_mutex_lock(&s->lock);
	ssize_t n = s->io.write(s->io.user_data, (const uint8_t*) buf, count);
	if(n > 0)
		s->position += n;
	pthread_mutex_unlock(&s->lock);
	return n;
}

off_t dis_virtual_io_lseek(int fake_fd, off_t offset, int whence)
{
	int idx = slot_index_for_fd(fake_fd);
	if(idx < 0)
		return (off_t) -1;

	dis_virtual_io_slot_t* s = &g_slots[idx];
	pthread_mutex_lock(&s->lock);
	off_t pos = s->io.seek(s->io.user_data, offset, whence);
	if(pos != (off_t) -1)
		s->position = pos;
	pthread_mutex_unlock(&s->lock);
	return pos;
}

ssize_t dis_virtual_io_pread(int fake_fd, void* buf, size_t count, off_t offset)
{
	int idx = slot_index_for_fd(fake_fd);
	if(idx < 0)
		return -1;

	dis_virtual_io_slot_t* s = &g_slots[idx];
	pthread_mutex_lock(&s->lock);
	off_t pos = s->io.seek(s->io.user_data, offset, SEEK_SET);
	ssize_t n = -1;
	if(pos != (off_t) -1)
	{
		n = s->io.read(s->io.user_data, (uint8_t*) buf, count);
		if(n > 0)
			s->position = pos + n;
	}
	pthread_mutex_unlock(&s->lock);
	return n;
}

ssize_t dis_virtual_io_pwrite(int fake_fd, const void* buf, size_t count, off_t offset)
{
	int idx = slot_index_for_fd(fake_fd);
	if(idx < 0)
		return -1;

	dis_virtual_io_slot_t* s = &g_slots[idx];
	if(!s->io.write)
		return -1;

	pthread_mutex_lock(&s->lock);
	off_t pos = s->io.seek(s->io.user_data, offset, SEEK_SET);
	ssize_t n = -1;
	if(pos != (off_t) -1)
	{
		n = s->io.write(s->io.user_data, (const uint8_t*) buf, count);
		if(n > 0)
			s->position = pos + n;
	}
	pthread_mutex_unlock(&s->lock);
	return n;
}