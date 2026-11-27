package com.aeidolon.vaultexplorer.viewer

import android.graphics.PointF
import android.opengl.Matrix
import android.view.Choreographer
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.VelocityTracker
import androidx.media3.exoplayer.video.spherical.SphericalGLSurfaceView
import java.lang.reflect.Array as ReflectArray
import java.lang.reflect.Field
import java.lang.reflect.Method
import java.lang.reflect.Proxy
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.asin
import kotlin.math.atan
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.hypot
import kotlin.math.sin

/**
 * Replaces Media3's touch tracker for this view. Its built-in tracker caps pitch at
 * 45 degrees, and disabling its sensor leaves the last sensor matrix in place.
 * The renderer still belongs to Media3, so video projection and camera motion
 * keep following the player as before. Touch drag and fling use the photo
 * panorama's sensitivity and decay. In gyro mode the touch tilt axis stays
 * fixed instead of following Media3's discontinuous roll near the poles.
 * Media3 1.11.1 has no public controls for these behaviors; recheck the
 * reflected members when upgrading it.
 */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class SphericalOrientationController(
    private val sphere: SphericalGLSurfaceView,
) : View.OnTouchListener {
    private val renderer: Any
    private val onScrollChange: Method
    private val onOrientationChange: Method
    private val deviceMatrixField: Field
    private val pitchMatrixField: Field
    private val yawMatrixField: Field
    private val deviceRollField: Field
    private val orientationListeners: Any
    private val rendererListenerIndex: Int
    private val stableRollListener: Any

    private var sensorEnabled = false
    private var yawDegrees = 0f
    private var pitchDegrees = 0f
    private var activePointerId = MotionEvent.INVALID_POINTER_ID
    private var previousX = 0f
    private var previousY = 0f
    private var velocityTracker: VelocityTracker? = null
    private var dragDistancePx = 0f
    private var usedMultiplePointers = false
    private val touchSlopPx = ViewConfiguration.get(sphere.context).scaledTouchSlop.toFloat()
    private val choreographer = Choreographer.getInstance()
    private var flingRunning = false
    private var lastFrameTimeNanos = 0L
    private var flingYawDegreesPerSecond = 0f
    private var flingPitchDegreesPerSecond = 0f
    private val flingFrame = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            if (!flingRunning) return
            val dt = if (lastFrameTimeNanos == 0L) {
                0f
            } else {
                ((frameTimeNanos - lastFrameTimeNanos) / 1_000_000_000f).coerceIn(0f, 0.05f)
            }
            lastFrameTimeNanos = frameTimeNanos
            if (dt > 0f) {
                yawDegrees = wrapDegrees(yawDegrees + flingYawDegreesPerSecond * dt)
                pitchDegrees = (pitchDegrees + flingPitchDegreesPerSecond * dt)
                    .coerceIn(-MAX_PITCH_DEGREES, MAX_PITCH_DEGREES)
                pushTouchRotation()
                val decay = exp(-3.5f * dt)
                flingYawDegreesPerSecond *= decay
                flingPitchDegreesPerSecond *= decay
            }
            if (abs(flingYawDegreesPerSecond) < STOP_FLING_DEGREES_PER_SECOND &&
                abs(flingPitchDegreesPerSecond) < STOP_FLING_DEGREES_PER_SECOND) {
                stopFling()
            } else {
                choreographer.postFrameCallback(this)
            }
        }
    }

    init {
        val tracker = sphere.javaClass.privateField("touchTracker").get(sphere)
        renderer = tracker.javaClass.privateField("listener").get(tracker)
        onScrollChange = renderer.javaClass.getDeclaredMethod("onScrollChange", PointF::class.java)
            .apply { isAccessible = true }
        onOrientationChange = renderer.javaClass.getDeclaredMethod(
            "onOrientationChange",
            FloatArray::class.java,
            java.lang.Float.TYPE,
        ).apply { isAccessible = true }
        deviceMatrixField = renderer.javaClass.privateField("deviceOrientationMatrix")
        pitchMatrixField = renderer.javaClass.privateField("touchPitchMatrix")
        yawMatrixField = renderer.javaClass.privateField("touchYawMatrix")
        deviceRollField = renderer.javaClass.privateField("deviceRoll")

        val orientationListener = sphere.javaClass.privateField("orientationListener").get(sphere)
        orientationListeners = orientationListener.javaClass.privateField("listeners").get(orientationListener)
        rendererListenerIndex = (0 until ReflectArray.getLength(orientationListeners))
            .firstOrNull { ReflectArray.get(orientationListeners, it) === renderer }
            ?: error("Media3 orientation renderer listener missing")
        val listenerInterface = orientationListeners.javaClass.componentType
        stableRollListener = Proxy.newProxyInstance(
            listenerInterface.classLoader,
            arrayOf(listenerInterface),
        ) { proxy, method, args ->
            when (method.name) {
                "onOrientationChange" -> {
                    // Keep Media3's full sensor matrix, but use the same local
                    // pitch axis through the nadir and zenith. Its extracted
                    // roll can flip there and otherwise pivots touch pitch.
                    onOrientationChange.invoke(renderer, args?.get(0), -PI.toFloat())
                    null
                }
                "equals" -> proxy === args?.get(0)
                "hashCode" -> System.identityHashCode(proxy)
                "toString" -> "Stable spherical orientation listener"
                else -> null
            }
        }
        ReflectArray.set(orientationListeners, rendererListenerIndex, stableRollListener)
    }

    fun setSensorEnabled(enabled: Boolean) {
        if (sensorEnabled == enabled) return
        stopFling()
        if (enabled) {
            sensorEnabled = true
            sphere.setUseSensorRotation(true)
            return
        }

        // Capture the direction in the middle of the screen before removing
        // the sensor matrix. Turning the sensor off alone leaves that matrix
        // active in Media3, which shifts the touch-only viewing range.
        val look = currentLookDirection()
        sensorEnabled = false
        sphere.setUseSensorRotation(false)
        resetSensorMatrix()
        yawDegrees = wrapDegrees(-look.x)
        pitchDegrees = -look.y.coerceIn(-MAX_PITCH_DEGREES, MAX_PITCH_DEGREES)
        pushTouchRotation()
    }

    override fun onTouch(view: View, event: MotionEvent): Boolean {
        if (event.actionMasked == MotionEvent.ACTION_DOWN) {
            velocityTracker?.recycle()
            velocityTracker = VelocityTracker.obtain()
        }
        velocityTracker?.addMovement(event)
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                stopFling()
                dragDistancePx = 0f
                usedMultiplePointers = false
                // An orientation callback already in flight can arrive just
                // after the sensor is unregistered. Clear it before panning.
                if (!sensorEnabled) {
                    resetSensorMatrix()
                    pushTouchRotation()
                }
                activePointerId = event.getPointerId(0)
                previousX = event.x
                previousY = event.y
            }
            MotionEvent.ACTION_MOVE -> {
                if (event.pointerCount != 1 || activePointerId == MotionEvent.INVALID_POINTER_ID) {
                    return true
                }
                val index = event.findPointerIndex(activePointerId)
                if (index < 0) return true
                val x = event.getX(index)
                val y = event.getY(index)
                val dx = x - previousX
                val dy = y - previousY
                dragDistancePx += hypot(dx, dy)
                val degreesPerPixel = degreesPerPixel(view)
                val touchX = dx * degreesPerPixel
                val touchY = dy * degreesPerPixel
                previousX = x
                previousY = y

                // Media3 uses the device roll to keep finger movement aligned
                // with the screen even when the phone is tilted.
                val roll = synchronized(renderer) { deviceRollField.getFloat(renderer) }
                val cr = cos(roll)
                val sr = sin(roll)
                yawDegrees = wrapDegrees(yawDegrees - (cr * touchX - sr * touchY))
                pitchDegrees = (pitchDegrees + sr * touchX + cr * touchY)
                    .coerceIn(-MAX_PITCH_DEGREES, MAX_PITCH_DEGREES)
                pushTouchRotation()
            }
            MotionEvent.ACTION_POINTER_DOWN -> {
                activePointerId = MotionEvent.INVALID_POINTER_ID
                usedMultiplePointers = true
            }
            MotionEvent.ACTION_POINTER_UP -> {
                if (event.pointerCount == 2) {
                    val remaining = if (event.actionIndex == 0) 1 else 0
                    activePointerId = event.getPointerId(remaining)
                    previousX = event.getX(remaining)
                    previousY = event.getY(remaining)
                }
            }
            MotionEvent.ACTION_UP -> {
                if (!usedMultiplePointers && dragDistancePx > touchSlopPx &&
                    activePointerId != MotionEvent.INVALID_POINTER_ID) {
                    val tracker = velocityTracker
                    if (tracker != null) {
                        tracker.computeCurrentVelocity(1000)
                        val roll = synchronized(renderer) { deviceRollField.getFloat(renderer) }
                        val cr = cos(roll)
                        val sr = sin(roll)
                        val degreesPerPixel = degreesPerPixel(view)
                        val velocityX = tracker.getXVelocity(activePointerId) * degreesPerPixel
                        val velocityY = tracker.getYVelocity(activePointerId) * degreesPerPixel
                        startFling(
                            -(cr * velocityX - sr * velocityY),
                            sr * velocityX + cr * velocityY,
                        )
                    }
                }
                activePointerId = MotionEvent.INVALID_POINTER_ID
                velocityTracker?.recycle()
                velocityTracker = null
            }
            MotionEvent.ACTION_CANCEL -> {
                activePointerId = MotionEvent.INVALID_POINTER_ID
                velocityTracker?.recycle()
                velocityTracker = null
            }
        }
        return true
    }

    fun dispose() {
        stopFling()
        sphere.setUseSensorRotation(false)
        ReflectArray.set(orientationListeners, rendererListenerIndex, renderer)
        velocityTracker?.recycle()
        velocityTracker = null
    }

    private fun degreesPerPixel(view: View): Float {
        if (view.width <= 0 || view.height <= 0) return 0f
        val aspect = view.width.toDouble() / view.height.toDouble()
        // Media3's 90-degree horizontal FOV narrows vertically in landscape.
        // Use the photo viewer's 0.65 fraction of the visible vertical FOV.
        val verticalFov = if (aspect > 1.0) Math.toDegrees(2.0 * atan(1.0 / aspect)) else 90.0
        return (verticalFov / view.height.toDouble() * PAN_SENSITIVITY.toDouble()).toFloat()
    }

    private fun startFling(yawVelocity: Float, pitchVelocity: Float) {
        if (abs(yawVelocity) < START_FLING_DEGREES_PER_SECOND &&
            abs(pitchVelocity) < START_FLING_DEGREES_PER_SECOND) return
        flingYawDegreesPerSecond = yawVelocity
        flingPitchDegreesPerSecond = pitchVelocity
        lastFrameTimeNanos = 0L
        flingRunning = true
        choreographer.postFrameCallback(flingFrame)
    }

    private fun stopFling() {
        if (flingRunning) choreographer.removeFrameCallback(flingFrame)
        flingRunning = false
        flingYawDegreesPerSecond = 0f
        flingPitchDegreesPerSecond = 0f
        lastFrameTimeNanos = 0L
    }

    private fun pushTouchRotation() {
        onScrollChange.invoke(renderer, PointF(yawDegrees, pitchDegrees))
    }

    private fun resetSensorMatrix() {
        val identity = FloatArray(16)
        Matrix.setIdentityM(identity, 0)
        // Renderer negates this roll; -PI restores its touch-only upright roll.
        onOrientationChange.invoke(renderer, identity, -PI.toFloat())
    }

    private fun currentLookDirection(): PointF {
        val (device, pitch, yaw) = synchronized(renderer) {
            Triple(
                (deviceMatrixField.get(renderer) as FloatArray).clone(),
                (pitchMatrixField.get(renderer) as FloatArray).clone(),
                (yawMatrixField.get(renderer) as FloatArray).clone(),
            )
        }
        val temp = FloatArray(16)
        val view = FloatArray(16)
        Matrix.multiplyMM(temp, 0, device, 0, yaw, 0)
        Matrix.multiplyMM(view, 0, pitch, 0, temp, 0)
        // The inverse of this rotation maps the camera's -Z ray into the world.
        val forwardX = -view[2]
        val forwardY = -view[6]
        val forwardZ = -view[10]
        return PointF(
            Math.toDegrees(atan2(forwardX.toDouble(), -forwardZ.toDouble())).toFloat(),
            Math.toDegrees(asin(forwardY.coerceIn(-1f, 1f).toDouble())).toFloat(),
        )
    }

    private fun wrapDegrees(value: Float): Float = ((value + 180f) % 360f + 360f) % 360f - 180f

    private fun Class<*>.privateField(name: String): Field =
        getDeclaredField(name).apply { isAccessible = true }

    private companion object {
        const val MAX_PITCH_DEGREES = 89.5f
        const val PAN_SENSITIVITY = 0.65f
        val START_FLING_DEGREES_PER_SECOND = Math.toDegrees(0.2).toFloat()
        val STOP_FLING_DEGREES_PER_SECOND = Math.toDegrees(0.02).toFloat()
    }
}
