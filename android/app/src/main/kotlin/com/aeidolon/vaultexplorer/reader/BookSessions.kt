package com.aeidolon.vaultexplorer.reader

import java.util.UUID

/**
 * One open comic or e-book: the byte source it is read from and its parsed ZIP
 * directory. A reader screen opens a session when it appears and closes it
 * when it goes away; the EPUB WebView resolves its requests through the same
 * session, which is why this is a process-wide registry and not owned by the
 * channel handler.
 *
 * Only metadata (entry names and offsets) lives here. Page and chapter bytes
 * are read on demand and are never cached on disk.
 */
class BookSession(
    val token: String,
    val source: BookByteSource,
    val directory: ZipDirectory,
    val epub: EpubPackage?,
)

object BookSessions {
    /** Enough for a reader, a preview and a screen being torn down; bounds leaked descriptors. */
    private const val MAX_OPEN = 6

    private val sessions = LinkedHashMap<String, BookSession>()

    fun open(source: BookByteSource, directory: ZipDirectory, epub: EpubPackage?): BookSession {
        val session = BookSession(UUID.randomUUID().toString(), source, directory, epub)
        val evicted = ArrayList<BookSession>()
        synchronized(this) {
            sessions[session.token] = session
            while (sessions.size > MAX_OPEN) {
                val eldest = sessions.entries.first()
                evicted.add(eldest.value)
                sessions.remove(eldest.key)
            }
        }
        evicted.forEach { runCatching { it.source.close() } }
        return session
    }

    @Synchronized
    fun get(token: String?): BookSession? = if (token == null) null else sessions[token]

    fun close(token: String?) {
        val session = synchronized(this) { if (token == null) null else sessions.remove(token) }
        runCatching { session?.source?.close() }
    }

    fun closeAll() {
        val all = synchronized(this) {
            val copy = sessions.values.toList()
            sessions.clear()
            copy
        }
        all.forEach { runCatching { it.source.close() } }
    }
}
