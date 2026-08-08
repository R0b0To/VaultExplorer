package com.aeidolon.vaultexplorer.syncbridge

import android.content.Context
import androidx.room.Dao
import androidx.room.Database
import androidx.room.Entity
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.PrimaryKey
import androidx.room.Query
import androidx.room.Room
import androidx.room.RoomDatabase

/**
 * Metadata only — never ciphertext content, never a plaintext filename
 * from inside an unlocked vault (docs/architecture.md §8, ownership rule
 * 8.1 in this document, mirroring vaultsync-bridge's ADR-S-001 from the
 * other side of the boundary). Lives entirely inside the `:syncbridge`
 * process; the main process never opens this database directly — it only
 * ever reaches it through [LedgerWriterService] (docs/architecture.md
 * ADR-029), the same way VaultSync Bridge only ever reaches it through
 * [VaultSyncBridgeService]'s AIDL surface.
 */
@Entity(tableName = "sync_vaults")
data class SyncVaultEntity(
    @PrimaryKey val vaultId: String,
    val displayName: String,
    val format: String,
    val rootKind: String,
    val rootUriOrPath: String,
    val cursor: Long,
    val createdAt: Long,
)

@Entity(tableName = "dirty_ledger", primaryKeys = ["vaultId", "seq"])
data class DirtyLedgerEntity(
    val vaultId: String,
    val seq: Long,
    val relativePath: String,
    val changeType: String,
    val sizeBytes: Long,
    val detectedAt: Long,
)

@Dao
interface SyncVaultDao {
    @Query("SELECT * FROM sync_vaults")
    suspend fun listAll(): List<SyncVaultEntity>

    @Query("SELECT * FROM sync_vaults WHERE vaultId = :vaultId")
    suspend fun get(vaultId: String): SyncVaultEntity?

    /** The lookup the main-process write hook actually needs: "is this
     *  vault (identified by the URI ContainerSessionRegistry already
     *  knows) registered for sync at all?" — a miss is the overwhelmingly
     *  common case and must stay cheap (docs/architecture.md ADR-029). */
    @Query("SELECT * FROM sync_vaults WHERE rootUriOrPath = :rootUri LIMIT 1")
    suspend fun findByRootUri(rootUri: String): SyncVaultEntity?

    @Query("SELECT COUNT(*) FROM sync_vaults")
    suspend fun count(): Int

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(vault: SyncVaultEntity)

    @Query("DELETE FROM sync_vaults WHERE vaultId = :vaultId")
    suspend fun delete(vaultId: String)

    @Query("UPDATE sync_vaults SET cursor = :cursor WHERE vaultId = :vaultId AND cursor < :cursor")
    suspend fun advanceCursor(vaultId: String, cursor: Long)
}

@Dao
interface DirtyLedgerDao {
    @Query("SELECT COALESCE(MAX(seq), 0) FROM dirty_ledger WHERE vaultId = :vaultId")
    suspend fun currentMaxSeq(vaultId: String): Long

    @Insert
    suspend fun insert(entry: DirtyLedgerEntity)

    @Query(
        "SELECT * FROM dirty_ledger WHERE vaultId = :vaultId AND seq > :sinceCursor ORDER BY seq ASC"
    )
    suspend fun changesSince(vaultId: String, sinceCursor: Long): List<DirtyLedgerEntity>

    /** Rule §8.5 (mirrors vaultsync-bridge ownership rule 5): the plugin
     *  only ever commits up to its own highest fully-clean contiguous
     *  cursor, so pruning everything at-or-below the committed cursor is
     *  always safe here — this side never has to reason about partial
     *  batches, only apply what the client already resolved. */
    @Query("DELETE FROM dirty_ledger WHERE vaultId = :vaultId AND seq <= :cursor")
    suspend fun pruneUpTo(vaultId: String, cursor: Long)

    @Query("DELETE FROM dirty_ledger WHERE vaultId = :vaultId")
    suspend fun deleteAllForVault(vaultId: String)
}

@Database(
    entities = [SyncVaultEntity::class, DirtyLedgerEntity::class],
    version = 1,
    exportSchema = true,
)
abstract class SyncLedgerDb : RoomDatabase() {
    abstract fun syncVaultDao(): SyncVaultDao
    abstract fun dirtyLedgerDao(): DirtyLedgerDao

    companion object {
        @Volatile private var instance: SyncLedgerDb? = null

        /** Lazily created — the whole point of ADR-029 is that neither
         *  this database file nor the `:syncbridge` process it lives in
         *  should exist until something actually registers a vault for
         *  sync. Call only from within the `:syncbridge` process. */
        fun get(context: Context): SyncLedgerDb =
            instance ?: synchronized(this) {
                instance ?: Room.databaseBuilder(
                    context.applicationContext,
                    SyncLedgerDb::class.java,
                    "sync_ledger.db",
                ).build().also { instance = it }
            }
    }
}
