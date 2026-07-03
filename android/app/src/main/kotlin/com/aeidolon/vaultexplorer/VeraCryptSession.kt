package com.aeidolon.vaultexplorer

data class ContainerSession(
    val uri: String,
    val volId: Int,
    var cachedFilesList: List<String>,
    var displayName: String? = null,
    var documentProvider: Boolean = false,
    val isUsbSource: Boolean = false,
)

object VeraCryptSession {

    val MAX_VOLUMES: Int by lazy { VeraCryptEngine.getMaxVolumesNative() }

    val locks: Array<Any> by lazy { Array(MAX_VOLUMES) { Any() } }
    val activeSessions = mutableMapOf<Int, ContainerSession>()

    fun isUnlocked(volId: Int) = activeSessions.containsKey(volId)
    fun hasAnyActiveSessions() = activeSessions.isNotEmpty()
    fun getFreeVolumeId(): Int? = (0 until MAX_VOLUMES).firstOrNull { !activeSessions.containsKey(it) }
    fun getSessionByUri(uri: String): ContainerSession? = activeSessions.values.find { it.uri == uri }
    fun getVolumeIdByUri(uri: String): Int? = activeSessions.entries.find { it.value.uri == uri }?.key
    fun removeSession(volId: Int) { activeSessions.remove(volId) }
}