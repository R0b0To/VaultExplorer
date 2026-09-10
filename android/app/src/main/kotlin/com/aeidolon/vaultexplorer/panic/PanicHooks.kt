package com.aeidolon.vaultexplorer.panic

import android.content.Context

/**
 * Extension seam for Phase 4 (Platform Channel Bridge & C++ Integration):
 * lets the Dart/C++ side register cleanup that must run at specific points
 * in a panic wipe, without this `panic` package needing to know Flutter or
 * JNI exist -- matching this plan's "Headless-Safe Native Orchestration"
 * principle (native code drives the wipe unconditionally; Dart is notified
 * on a best-effort basis if it happens to be around).
 *
 * Every method is a no-op by default, so [PanicManager] works correctly
 * standalone before Phase 4 ever registers a real implementation.
 *
 * All methods run synchronously on whatever thread called
 * [PanicManager.execute] (see that function's threading contract).
 * [PanicManager] wraps every call to a hook in `runCatching`, so a
 * throwing hook can't abort the wipe -- but a *slow* hook still delays
 * every step after it, including, for a Tier 3 wipe, the eventual
 * process-death sequence. Implementations should do the minimum needed
 * (queueing/zeroing already-held buffers) rather than anything that
 * itself blocks on I/O.
 */
interface PanicHooks {
    /** Called once, before [PanicManager] unmounts any container --
     *  Phase 4's implementation can read state here that unmounting is
     *  about to invalidate. */
    fun onBeforeSessionPurge(context: Context) {}

    /** Called once every container has been unmounted (Tier 1 and above).
     *  Phase 4's real implementation zeroes C++ session-key/buffer-pool
     *  memory and any Dart-managed decrypted buffers here, and (per
     *  Phase 4's "Downward Panic Notification") notifies Dart over the
     *  MethodChannel if the Flutter engine is currently attached. */
    fun onAfterSessionPurge(context: Context) {}

    /** Called once the Keystore and every registered credential store
     *  have been purged (Tier 2 and above). Phase 4 uses this to tell
     *  Dart a credential purge happened, so any in-memory Dart state
     *  mirroring those credentials (cached biometric-unlock flags, etc.)
     *  gets cleared too, not just its native backing store. */
    fun onAfterCredentialPurge(context: Context) {}

    /** Called once, immediately before [PanicManager] dispatches the
     *  uninstall intent and kills the process (Tier 3 only) -- the final
     *  point at which the process is guaranteed to still exist. */
    fun onBeforeProcessDeath(context: Context) {}
}
