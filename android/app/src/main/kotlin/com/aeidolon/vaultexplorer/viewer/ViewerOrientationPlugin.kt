package com.aeidolon.vaultexplorer.viewer

import android.app.Activity
import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Surface
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

private const val METHOD_CHANNEL = "com.aeidolon.vaultexplorer/viewer/orientation_method"
private const val EVENT_CHANNEL = "com.aeidolon.vaultexplorer/viewer/orientation"

/**
 * Streams the device attitude to the 360° image viewer ("look around by moving
 * the phone").
 *
 * Android's own sensor fusion does the heavy lifting: TYPE_GAME_ROTATION_VECTOR
 * (gyroscope + accelerometer, no magnetometer, so no drift and no compass
 * jitter) is preferred, with TYPE_ROTATION_VECTOR as a fallback. Each event is
 * turned into a 3x3 rotation matrix, row-major, mapping the *screen* axes
 * (x right, y up, z out of the screen) to the world axes (East, North, Up),
 * already corrected for the current display rotation so landscape works.
 *
 * The sensor is only registered while Dart is listening, i.e. while the viewer
 * is actually in gyro mode. No permission is needed at SENSOR_DELAY_GAME.
 */
class ViewerOrientationPlugin(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val sensorManager =
        activity.applicationContext.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())

    private var listener: SensorEventListener? = null
    private val deviceToWorld = FloatArray(9)
    private val screenToWorld = FloatArray(9)

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    private fun pickSensor(): Sensor? =
        sensorManager.getDefaultSensor(Sensor.TYPE_GAME_ROTATION_VECTOR)
            ?: sensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(pickSensor() != null)
            else -> result.notImplemented()
        }
    }

    @Suppress("DEPRECATION")
    private fun displayRotation(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.display?.rotation ?: Surface.ROTATION_0
        } else {
            activity.windowManager.defaultDisplay.rotation
        }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        stop()
        val sensor = pickSensor()
        if (sensor == null) {
            sink.error("unavailable", "No rotation-vector sensor on this device", null)
            return
        }
        val l = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                SensorManager.getRotationMatrixFromVector(deviceToWorld, event.values)
                val out = when (displayRotation()) {
                    Surface.ROTATION_90 -> remap(SensorManager.AXIS_Y, SensorManager.AXIS_MINUS_X)
                    Surface.ROTATION_180 -> remap(SensorManager.AXIS_MINUS_X, SensorManager.AXIS_MINUS_Y)
                    Surface.ROTATION_270 -> remap(SensorManager.AXIS_MINUS_Y, SensorManager.AXIS_X)
                    else -> deviceToWorld
                }
                sink.success(out.copyOf())
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
        }
        listener = l
        sensorManager.registerListener(l, sensor, SensorManager.SENSOR_DELAY_GAME, mainHandler)
    }

    private fun remap(axisX: Int, axisY: Int): FloatArray {
        SensorManager.remapCoordinateSystem(deviceToWorld, axisX, axisY, screenToWorld)
        return screenToWorld
    }

    override fun onCancel(arguments: Any?) = stop()

    private fun stop() {
        listener?.let { sensorManager.unregisterListener(it) }
        listener = null
    }

    fun dispose() {
        stop()
        eventChannel.setStreamHandler(null)
        methodChannel.setMethodCallHandler(null)
    }
}
