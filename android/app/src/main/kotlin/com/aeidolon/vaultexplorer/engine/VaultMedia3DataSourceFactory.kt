package com.aeidolon.vaultexplorer.engine

import androidx.media3.datasource.DataSource

/**
 * Factory that creates [VaultMedia3DataSource] instances for a specific
 * (volId, filePath) pair.
 *
 * One factory is created per media item. ExoPlayer's
 * [ProgressiveMediaSource] calls [createDataSource] each time it needs a
 * new read session (initial load, after a seek, etc.), and the resulting
 * [VaultMedia3DataSource] opens its own C++ stream handle.
 */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
class VaultMedia3DataSourceFactory(
    private val volId: Int,
    private val filePath: String,
) : DataSource.Factory {

    override fun createDataSource(): DataSource = VaultMedia3DataSource(volId, filePath)
}
