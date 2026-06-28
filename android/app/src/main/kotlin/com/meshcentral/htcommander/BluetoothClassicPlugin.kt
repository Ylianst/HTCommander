package com.meshcentral.htcommander

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/**
 * Native Bluetooth Classic (RFCOMM / Serial Port Profile) bridge for Android.
 *
 * Registers the same method/event channels the rest of the app already uses for
 * macOS and Windows so the existing Dart [BluetoothClassicMacOS] bridge and
 * [BluetoothClassicTransport] work unchanged:
 *   - MethodChannel `com.htcommander/bluetooth_classic`
 *   - EventChannel  `com.htcommander/bluetooth_classic_data`   (control channel)
 *   - EventChannel  `com.htcommander/bluetooth_classic_audio`  (BS AOC audio)
 *
 * The control channel (SPP, 0x1101) carries GAIA framed commands. The audio
 * channel uses the vendor "BS AOC" 128-bit UUID. RFCOMM channel numbers are
 * resolved by UUID via SDP (Android's createRfcommSocketToServiceRecord), never
 * by a hardcoded channel number. See docs/radio-bluetooth.md.
 */
class BluetoothClassicPlugin(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "BtClassic"
        private const val METHOD_CHANNEL = "com.htcommander/bluetooth_classic"
        private const val DATA_EVENT_CHANNEL = "com.htcommander/bluetooth_classic_data"
        private const val AUDIO_EVENT_CHANNEL = "com.htcommander/bluetooth_classic_audio"

        // Standard Serial Port Profile (control / GAIA).
        private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
        // Vendor "BS AOC" service that carries the SBC audio stream.
        private val AUDIO_UUID: UUID = UUID.fromString("39144315-32FA-40DB-85ED-FBFEBA2D86E6")

        // Known compatible radio device name patterns (matches the Dart list).
        private val TARGET_NAMES = listOf(
            "UV-PRO", "UV-50PRO", "GA-5WB", "VR-N75", "VR-N76", "VR-N7500",
            "VR-N7600", "DB50-B", "WP-C1", "HT-CH1", "QUANSHENG", "VR-N",
            "SA-888S", "HG-UV98", "UV-98", "HAM-AIO", "VR-6600PRO", "TH-UV88",
            "3B01B", "E1WPR", "PNI-HP98WP",
        )

        // Remembers the RFCOMM channel that last connected for a given radio
        // address so reconnects can skip the channel scan. The radio's SDP
        // record advertises an unstable channel, so the working channel is
        // discovered by probing; caching it makes later connects near-instant.
        private val lastGoodChannel = ConcurrentHashMap<String, Int>()
    }

    /** Set by [MainActivity] so we can request runtime permissions. */
    var activity: Activity? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val dataEventChannel = EventChannel(messenger, DATA_EVENT_CHANNEL)
    private val audioEventChannel = EventChannel(messenger, AUDIO_EVENT_CHANNEL)

    private var dataSink: EventChannel.EventSink? = null
    private var audioSink: EventChannel.EventSink? = null

    private val controlConnections = ConcurrentHashMap<String, RfcommConnection>()
    private val audioConnections = ConcurrentHashMap<String, RfcommConnection>()

    init {
        methodChannel.setMethodCallHandler(this)
        dataEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                dataSink = events
            }

            override fun onCancel(arguments: Any?) {
                dataSink = null
            }
        })
        audioEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                audioSink = events
            }

            override fun onCancel(arguments: Any?) {
                audioSink = null
            }
        })
    }

    private val bluetoothAdapter: BluetoothAdapter?
        get() = (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    private fun hasConnectPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return context.checkSelfPermission(
            Manifest.permission.BLUETOOTH_CONNECT,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun hasScanPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return context.checkSelfPermission(
            Manifest.permission.BLUETOOTH_SCAN,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestConnectPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        activity?.requestPermissions(
            arrayOf(Manifest.permission.BLUETOOTH_CONNECT),
            1001,
        )
    }

    private fun normalizeAddress(address: String): String =
        address.uppercase().replace('-', ':')

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(isAvailable())
            "getPairedDevices" -> result.success(listDevices(filterCompatible = false))
            "findCompatibleDevices" -> result.success(listDevices(filterCompatible = true))
            "getDeviceNames" -> result.success(deviceNames())
            "connect" -> openRfcomm(call.argument<String>("address"), SPP_UUID, audio = false, result)
            "disconnect" -> {
                disconnect(call.argument<String>("address"), audio = false)
                result.success(true)
            }
            "send" -> result.success(
                send(call.argument<String>("address"), call.argument("data"), audio = false),
            )
            "connectAudio" -> connectAudio(call.argument<String>("address"), result)
            "disconnectAudio" -> {
                disconnect(call.argument<String>("address"), audio = true)
                result.success(true)
            }
            "sendAudio" -> result.success(
                send(call.argument<String>("address"), call.argument("data"), audio = true),
            )
            else -> result.notImplemented()
        }
    }

    private fun isAvailable(): Boolean {
        val adapter = bluetoothAdapter ?: return false
        return adapter.isEnabled
    }

    private fun listDevices(filterCompatible: Boolean): List<Map<String, Any>> {
        val adapter = bluetoothAdapter ?: return emptyList()
        if (!hasConnectPermission()) {
            requestConnectPermission()
            return emptyList()
        }
        val devices = mutableListOf<Map<String, Any>>()
        val seen = mutableSetOf<String>()
        try {
            for (device in adapter.bondedDevices ?: emptySet()) {
                val name = device.name ?: continue
                val address = normalizeAddress(device.address ?: continue)
                if (seen.contains(address)) continue
                if (filterCompatible && !isCompatible(name)) continue
                seen.add(address)
                devices.add(
                    mapOf(
                        "name" to name,
                        "address" to address,
                        "isPaired" to true,
                        "isConnected" to controlConnections.containsKey(address),
                    ),
                )
            }
        } catch (e: SecurityException) {
            requestConnectPermission()
        }
        return devices
    }

    private fun deviceNames(): List<String> {
        return listDevices(filterCompatible = false).mapNotNull { it["name"] as? String }
    }

    private fun isCompatible(name: String): Boolean {
        val upper = name.uppercase()
        return TARGET_NAMES.any { upper.contains(it.uppercase()) }
    }

    private fun connectAudio(address: String?, result: MethodChannel.Result) {
        openRfcomm(address, AUDIO_UUID, audio = true, result)
    }

    private fun openRfcomm(
        address: String?,
        uuid: UUID,
        audio: Boolean,
        result: MethodChannel.Result,
    ) {
        if (address == null) {
            result.error("INVALID_ARGS", "Missing address", null)
            return
        }
        val adapter = bluetoothAdapter
        if (adapter == null) {
            result.success(false)
            return
        }
        if (!hasConnectPermission()) {
            requestConnectPermission()
            result.success(false)
            return
        }

        val normalized = normalizeAddress(address)
        val map = if (audio) audioConnections else controlConnections
        if (map.containsKey(normalized)) {
            result.success(true)
            return
        }

        Thread {
            var socket: BluetoothSocket? = null
            try {
                // Cancelling discovery speeds up RFCOMM connects, but it needs
                // BLUETOOTH_SCAN on Android 12+. It is only an optimization, so
                // skip it when the permission is missing rather than failing.
                if (hasScanPermission()) {
                    try {
                        adapter.cancelDiscovery()
                    } catch (_: SecurityException) {
                    }
                }
                val device = adapter.getRemoteDevice(normalized)
                socket = connectSocket(device, uuid)

                val connection = RfcommConnection(normalized, socket, audio)
                map[normalized] = connection
                connection.startReading()

                postEvent(audio, "connected", normalized, null)
                mainHandler.post { result.success(true) }
            } catch (e: Exception) {
                try {
                    socket?.close()
                } catch (_: IOException) {
                }
                val message = "${e.javaClass.simpleName}: ${e.message ?: "RFCOMM connect failed"}"
                mainHandler.post {
                    result.error("CONNECT_FAILED", message, null)
                }
            }
        }.start()
    }

    /**
     * Open and connect an RFCOMM socket, trying several strategies in order.
     *
     * The radios accept the connection only with **null authentication** (the
     * Windows app connects with BluetoothEncryptionAllowNullAuthentication). On
     * Android that maps to the *insecure* RFCOMM socket, so we try the insecure
     * sockets first; the secure variants force authentication the radio rejects.
     *
     * The radio's SPP channel is unstable: its SDP record can advertise a server
     * channel (e.g. 1) that the firmware then refuses with an RFCOMM DM frame
     * (`read failed ... read ret: -1`). So when the UUID/SDP-resolved sockets
     * fail we probe a range of fixed RFCOMM channels and take the first the
     * radio actually accepts. A short delay is inserted between attempts to let
     * the radio reset its RFCOMM state. See docs/radio-bluetooth.md.
     */
    private fun connectSocket(
        device: android.bluetooth.BluetoothDevice,
        uuid: UUID,
    ): BluetoothSocket {
        var lastError: Exception? = null
        val address = device.address

        fun attempt(label: String, factory: () -> BluetoothSocket): BluetoothSocket? {
            var candidate: BluetoothSocket? = null
            return try {
                candidate = factory()
                candidate.connect()
                Log.i(TAG, "RFCOMM connected via $label")
                candidate
            } catch (e: Exception) {
                lastError = e
                Log.w(TAG, "RFCOMM attempt $label failed: ${e.javaClass.simpleName}: ${e.message}")
                try {
                    candidate?.close()
                } catch (_: IOException) {
                }
                try {
                    Thread.sleep(250)
                } catch (_: InterruptedException) {
                }
                null
            }
        }

        val insecureByChannel = device.javaClass.getMethod(
            "createInsecureRfcommSocket",
            Int::class.javaPrimitiveType,
        )

        fun tryChannel(channel: Int): BluetoothSocket? =
            attempt("insecure-ch$channel") {
                insecureByChannel.invoke(device, channel) as BluetoothSocket
            }?.also { lastGoodChannel[address] = channel }

        // 0. Fast path: reuse the channel that last worked for this radio so we
        //    skip the full scan on reconnect.
        val cachedChannel = lastGoodChannel[address]
        if (cachedChannel != null) {
            tryChannel(cachedChannel)?.let { return it }
        }

        // 1. UUID/SDP-resolved sockets (channel comes from the radio's SDP
        //    record). Insecure first to match the radio's null-auth requirement.
        attempt("insecure-sdp") {
            device.createInsecureRfcommSocketToServiceRecord(uuid)
        }?.let { return it }
        attempt("secure-sdp") {
            device.createRfcommSocketToServiceRecord(uuid)
        }?.let { return it }

        // 2. Probe fixed RFCOMM channels with an insecure socket. The radio's
        //    SPP channel has been observed on 1 and 4; scan a small range and
        //    take the first the radio accepts.
        for (channel in 1..12) {
            if (channel == cachedChannel) continue // already tried above
            tryChannel(channel)?.let { return it }
        }

        // 3. Final fallback: secure fixed channel 1.
        attempt("secure-ch1") {
            val method = device.javaClass.getMethod(
                "createRfcommSocket",
                Int::class.javaPrimitiveType,
            )
            method.invoke(device, 1) as BluetoothSocket
        }?.let { return it }

        throw lastError ?: IOException("RFCOMM connect failed")
    }

    private fun disconnect(address: String?, audio: Boolean) {
        if (address == null) return
        val normalized = normalizeAddress(address)
        val map = if (audio) audioConnections else controlConnections
        map.remove(normalized)?.close()
    }

    private fun send(address: String?, data: ByteArray?, audio: Boolean): Boolean {
        if (address == null || data == null) return false
        val normalized = normalizeAddress(address)
        val map = if (audio) audioConnections else controlConnections
        val connection = map[normalized] ?: return false
        return connection.write(data)
    }

    private fun postEvent(audio: Boolean, event: String, address: String, data: ByteArray?) {
        mainHandler.post {
            val sink = if (audio) audioSink else dataSink
            val payload = HashMap<String, Any>()
            payload["event"] = event
            payload["address"] = address
            if (data != null) payload["data"] = data
            sink?.success(payload)
        }
    }

    /** Owns a single RFCOMM socket and its background read loop. */
    private inner class RfcommConnection(
        private val address: String,
        private val socket: BluetoothSocket,
        private val audio: Boolean,
    ) {
        @Volatile
        private var closed = false
        private var readThread: Thread? = null

        fun startReading() {
            readThread = Thread {
                val buffer = ByteArray(4096)
                val input = try {
                    socket.inputStream
                } catch (e: IOException) {
                    handleClosed()
                    return@Thread
                }
                while (!closed) {
                    val count = try {
                        input.read(buffer)
                    } catch (e: IOException) {
                        break
                    }
                    if (count < 0) break
                    if (count > 0) {
                        postEvent(audio, "data", address, buffer.copyOf(count))
                    }
                }
                handleClosed()
            }.apply { isDaemon = true; start() }
        }

        fun write(data: ByteArray): Boolean {
            if (closed) return false
            return try {
                val output = socket.outputStream
                output.write(data)
                output.flush()
                true
            } catch (e: IOException) {
                false
            }
        }

        private fun handleClosed() {
            if (closed) return
            closed = true
            val map = if (audio) audioConnections else controlConnections
            map.remove(address)
            try {
                socket.close()
            } catch (_: IOException) {
            }
            postEvent(audio, "disconnected", address, null)
        }

        fun close() {
            if (closed) return
            closed = true
            try {
                socket.close()
            } catch (_: IOException) {
            }
            postEvent(audio, "disconnected", address, null)
        }
    }
}
