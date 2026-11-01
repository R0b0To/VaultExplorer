package com.aeidolon.vaultexplorer.securitykey

import android.app.Activity
import com.aeidolon.vaultexplorer.VeLog
import com.yubico.yubikit.android.YubiKitManager
import com.yubico.yubikit.android.transport.nfc.NfcConfiguration
import com.yubico.yubikit.android.transport.nfc.NfcNotAvailable
import com.yubico.yubikit.android.transport.usb.UsbConfiguration
import com.yubico.yubikit.core.YubiKeyConnection
import com.yubico.yubikit.core.YubiKeyDevice
import com.yubico.yubikit.core.fido.FidoConnection
import com.yubico.yubikit.core.smartcard.SmartCardConnection
import com.yubico.yubikit.core.util.Callback
import com.yubico.yubikit.core.util.Result
import com.yubico.yubikit.fido.ctap.Ctap2Session
import java.io.IOException
import java.util.concurrent.CompletableFuture
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutionException
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Waits for a FIDO2 security key to be presented over USB (plugged in) or NFC
 * (tapped), opens a [Ctap2Session] on it and runs a block of CTAP2 work.
 *
 * [run] BLOCKS the calling thread (call it from the IO executor, never the
 * UI thread) until the block succeeds, fails terminally, times out, or
 * [cancel] is called. The block runs inside the connection callback because
 * an NFC connection only lives as long as the tag stays in the field; for
 * the same reason any PIN must already be known before the key is presented.
 *
 * Failures specific to the key that was presented (it doesn't hold this
 * vault's credential, it isn't a FIDO key, the tag was pulled away) don't
 * end the wait -- the next key or tap gets a chance until the timeout, and
 * if nothing succeeds the last such failure is what gets reported.
 */
class SecurityKeyTransport(private val activity: Activity) {

    @Volatile private var pending: CompletableFuture<*>? = null
    private val cancelled = AtomicBoolean(false)

    fun cancel() {
        cancelled.set(true)
        pending?.completeExceptionally(SecurityKeyException(SecurityKeyError.CANCELLED, "Cancelled."))
    }

    fun <T> run(timeoutMs: Long = DEFAULT_TIMEOUT_MS, block: (Ctap2Session) -> T): T {
        if (cancelled.get()) throw SecurityKeyException(SecurityKeyError.CANCELLED, "Cancelled.")

        val manager = YubiKitManager(activity.applicationContext)
        val done = CompletableFuture<T>()
        val busy = AtomicBoolean(false)
        val lastKeyError = arrayOfNulls<SecurityKeyException>(1)
        pending = done

        val onDevice = Callback<YubiKeyDevice> { device ->
            handleDevice(device, done, busy, lastKeyError, block)
        }
        startDiscovery(manager, onDevice)
        try {
            return done.get(timeoutMs, TimeUnit.MILLISECONDS)
        } catch (e: TimeoutException) {
            throw lastKeyError[0] ?: SecurityKeyException(
                SecurityKeyError.TIMEOUT,
                "No security key was presented in time.",
            )
        } catch (e: ExecutionException) {
            val cause = e.cause
            throw cause as? SecurityKeyException
                ?: SecurityKeyException(SecurityKeyError.FAILED, cause?.message ?: "Security key error.", cause)
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()
            throw SecurityKeyException(SecurityKeyError.CANCELLED, "Cancelled.", e)
        } finally {
            pending = null
            stopDiscovery(manager)
        }
    }

    private fun startDiscovery(manager: YubiKitManager, listener: Callback<YubiKeyDevice>) {
        manager.startUsbDiscovery(UsbConfiguration().handlePermissions(true), listener)
        // NFC reader mode is tied to the foreground activity and is set up
        // from the UI thread; wait briefly so a failure to start is logged
        // before we settle in to wait.
        val started = CountDownLatch(1)
        activity.runOnUiThread {
            try {
                manager.startNfcDiscovery(NfcConfiguration().skipNdefCheck(true), activity, listener)
            } catch (_: NfcNotAvailable) {
                VeLog.i(TAG) { "NFC not available; waiting for a USB security key only" }
            } catch (e: Exception) {
                VeLog.w(TAG) { "Could not start NFC discovery: ${e.message}" }
            } finally {
                started.countDown()
            }
        }
        started.await(2, TimeUnit.SECONDS)
    }

    private fun stopDiscovery(manager: YubiKitManager) {
        activity.runOnUiThread {
            runCatching { manager.stopNfcDiscovery(activity) }
            runCatching { manager.stopUsbDiscovery() }
        }
    }

    private fun <T> handleDevice(
        device: YubiKeyDevice,
        done: CompletableFuture<T>,
        busy: AtomicBoolean,
        lastKeyError: Array<SecurityKeyException?>,
        block: (Ctap2Session) -> T,
    ) {
        if (done.isDone || !busy.compareAndSet(false, true)) return
        when {
            device.supportsConnection(FidoConnection::class.java) ->
                device.requestConnection(FidoConnection::class.java) { result ->
                    attempt(result, done, busy, lastKeyError, block) { conn -> Ctap2Session(conn) }
                }
            device.supportsConnection(SmartCardConnection::class.java) ->
                device.requestConnection(SmartCardConnection::class.java) { result ->
                    attempt(result, done, busy, lastKeyError, block) { conn -> Ctap2Session(conn) }
                }
            else -> busy.set(false)
        }
    }

    private fun <C : YubiKeyConnection, T> attempt(
        result: Result<C, IOException>,
        done: CompletableFuture<T>,
        busy: AtomicBoolean,
        lastKeyError: Array<SecurityKeyException?>,
        block: (Ctap2Session) -> T,
        open: (C) -> Ctap2Session,
    ) {
        var sessionOpened = false
        try {
            result.value.use { connection ->
                val session = open(connection)
                sessionOpened = true
                done.complete(block(session))
            }
        } catch (e: SecurityKeyException) {
            if (e.error.retryOnNextKey) {
                lastKeyError[0] = e
                busy.set(false)
            } else {
                done.completeExceptionally(e)
            }
        } catch (e: IOException) {
            // Key unplugged or NFC tag moved mid-operation: wait for it to be presented again.
            VeLog.i(TAG) { "Connection to the security key was interrupted: ${e.message}" }
            lastKeyError[0] = SecurityKeyException(
                SecurityKeyError.FAILED,
                "Lost contact with the security key. Keep it in place until the unlock finishes.",
                e,
            )
            busy.set(false)
        } catch (e: Exception) {
            if (!sessionOpened) {
                // Not a FIDO2 authenticator (some other NFC tag, or a key with FIDO disabled).
                lastKeyError[0] = SecurityKeyException(
                    SecurityKeyError.FAILED,
                    "That device isn't a FIDO2 security key.",
                    e,
                )
                busy.set(false)
            } else {
                done.completeExceptionally(
                    SecurityKeyException(SecurityKeyError.FAILED, e.message ?: "Security key error.", e),
                )
            }
        }
    }

    companion object {
        private const val TAG = "VaultExplorer_SecurityKey"
        const val DEFAULT_TIMEOUT_MS = 60_000L
    }
}
