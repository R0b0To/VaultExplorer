package com.aeidolon.vaultexplorer

data class ContainerSession(
    val uri: String,
    val password: String,
    val pim: Int,
    val volId: Int,
    var cachedFilesList: List<String>,
    val displayName: String? = null
)

object VeraCryptSession {
    private const val MAX_VOLUMES = 16

    // One lock per volume slot (0 to MAX_VOLUMES-1)
    val locks = Array(MAX_VOLUMES) { Any() }

    val activeSessions = mutableMapOf<Int, ContainerSession>()

    fun isUnlocked(volId: Int): Boolean {
        return activeSessions.containsKey(volId)
    }

    fun hasAnyActiveSessions(): Boolean {
        return activeSessions.isNotEmpty()
    }

    fun getFreeVolumeId(): Int? {
        for (i in 0 until MAX_VOLUMES) {
            if (!activeSessions.containsKey(i)) return i
        }
        return null
    }

    fun getSessionByUri(uri: String): ContainerSession? {
        return activeSessions.values.find { it.uri == uri }
    }

    fun getVolumeIdByUri(uri: String): Int? {
        return activeSessions.entries.find { it.value.uri == uri }?.key
    }

    fun getVolumeIdByDocId(docId: String): Int? {
        return docId.substringBefore("_").toIntOrNull()
    }

    fun removeSession(volId: Int) {
        activeSessions.remove(volId)
    }
}