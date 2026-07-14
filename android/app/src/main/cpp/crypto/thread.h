#ifndef ARGON2_THREAD_H
#define ARGON2_THREAD_H

#if !defined(ARGON2_NO_THREADS)

#if defined(_WIN32)
#include <process.h>
typedef unsigned(__stdcall *argon2_thread_func_t)(void *);
typedef uintptr_t argon2_thread_handle_t;
#else
#include <pthread.h>
typedef void *(*argon2_thread_func_t)(void *);
typedef pthread_t argon2_thread_handle_t;
#endif

/* Creates a thread */
int argon2_thread_create(argon2_thread_handle_t *handle,
                         argon2_thread_func_t func, void *args);

/* Waits for a thread to terminate */
int argon2_thread_join(argon2_thread_handle_t handle);

/* Terminates a thread */
void argon2_thread_exit(void);

#endif /* ARGON2_NO_THREADS */
#endif