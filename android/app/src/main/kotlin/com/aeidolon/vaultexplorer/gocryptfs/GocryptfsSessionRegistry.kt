package com.aeidolon.vaultexplorer.gocryptfs

import java.util.concurrent.ConcurrentHashMap

object GocryptfsSessionRegistry {
    private val sessions = ConcurrentHashMap<Int, GocryptfsSession>()
    fun put(volId: Int, session: GocryptfsSession) { sessions[volId] = session }
    fun get(volId: Int): GocryptfsSession? = sessions[volId]
    fun remove(volId: Int) { sessions.remove(volId)?.close() }
    fun isGocryptfs(volId: Int): Boolean = sessions.containsKey(volId)
}