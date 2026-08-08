// Internal-only, same-app AIDL hop from VaultExplorer's main process to its
// own ":syncbridge" process (see docs/architecture.md §8). This is NOT
// part of the public com.aeidolon.vaultexplorer.syncapi contract shared
// with VaultSync Bridge — it never crosses an app boundary, carries no
// stability guarantee outside this repo, and is not versioned by
// vaultsync-syncapi.
//
// oneway for the same reason IVaultSyncCallback (syncapi) is: a
// ContainerEngine write hook (docs/architecture.md ADR-029) must never
// block on this process hop, or on the :syncbridge process being slow,
// killed, or (overwhelmingly the common case) never started at all.
package com.aeidolon.vaultexplorer.syncbridge.internal;

oneway interface ILedgerWriter {
    void recordChange(String rootUri, String relativePath, String changeType, long sizeBytes, long detectedAtEpochMs);
}
