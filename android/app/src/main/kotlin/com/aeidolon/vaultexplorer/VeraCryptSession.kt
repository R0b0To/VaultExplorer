package com.aeidolon.vaultexplorer

data class ContainerSession(
    val uri: String,
    val volId: Int,
    var cachedFilesList: List<String>,
    val displayName: String? = null
)


object VeraCryptSession {
    const val MAX_VOLUMES = 4   // Must match FF_VOLUMES (ffconf.h) and MAX_VOLUMES (vaultexplorer.cpp)

    /** One fair lock per volume slot; prevents concurrent JNI calls on the same slot. */
    val locks: Array<Any> = Array(MAX_VOLUMES) { Any() }

    val activeSessions = mutableMapOf<Int, ContainerSession>()

    fun isUnlocked(volId: Int) = activeSessions.containsKey(volId)

    fun hasAnyActiveSessions() = activeSessions.isNotEmpty()

    /** Returns the lowest free slot index, or null when all [MAX_VOLUMES] slots are occupied. */
    fun getFreeVolumeId(): Int? = (0 until MAX_VOLUMES).firstOrNull { !activeSessions.containsKey(it) }

    fun getSessionByUri(uri: String): ContainerSession? = activeSessions.values.find { it.uri == uri }

    fun getVolumeIdByUri(uri: String): Int? = activeSessions.entries.find { it.value.uri == uri }?.key

    fun removeSession(volId: Int) {
        activeSessions.remove(volId)
    }
}