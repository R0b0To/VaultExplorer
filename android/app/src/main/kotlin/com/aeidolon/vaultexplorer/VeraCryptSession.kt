package com.aeidolon.vaultexplorer

data class ContainerSession(
    val uri: String,
    val volId: Int,
    var cachedFilesList: List<String>,
    val displayName: String? = null,
    val documentProvider: Boolean = false,  // only expose in doc picker when true
)

object VeraCryptSession {
    const val MAX_VOLUMES = 4

    val locks: Array<Any> = Array(MAX_VOLUMES) { Any() }
    val activeSessions = mutableMapOf<Int, ContainerSession>()

    fun isUnlocked(volId: Int) = activeSessions.containsKey(volId)
    fun hasAnyActiveSessions() = activeSessions.isNotEmpty()
    fun getFreeVolumeId(): Int? = (0 until MAX_VOLUMES).firstOrNull { !activeSessions.containsKey(it) }
    fun getSessionByUri(uri: String): ContainerSession? = activeSessions.values.find { it.uri == uri }
    fun getVolumeIdByUri(uri: String): Int? = activeSessions.entries.find { it.value.uri == uri }?.key
    fun removeSession(volId: Int) { activeSessions.remove(volId) }
}