package com.meshcentral.htcommander

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CopyOnWriteArraySet

/**
 * In-process bridge between the Flutter engine and the Android Auto car UI.
 *
 * The car surface ([RadioCarAppService] and its screens) runs in the same
 * process as [MainActivity] but on a separate lifecycle, so it cannot talk to
 * the Dart isolate directly. This singleton holds the latest car-safe state
 * pushed from Dart over the `com.htcommander/android_auto` [MethodChannel] and
 * lets the car screens both read that state and request a channel change.
 *
 * Data flow:
 *   - Dart -> native: `updateState` refreshes the mirrored radio state
 *     ([regionName], [vfoA]/[vfoB], [scan], [dualWatch], [regions], [channels]
 *     and [messages]); registered [listeners] are then notified to invalidate.
 *   - native -> Dart: [requestChannel], [requestRegion], [requestScan] and
 *     [requestDualWatch] invoke the matching setters back on Dart.
 */
object AndroidAutoBridge : MethodChannel.MethodCallHandler {
    private const val CHANNEL = "com.htcommander/android_auto"

    private val mainHandler = Handler(Looper.getMainLooper())
    private var methodChannel: MethodChannel? = null

    @Volatile
    private var carConnected: Boolean = false

    data class CarChannel(val id: Int, val name: String, val frequency: String)
    data class CarRadio(val id: String, val name: String)
    data class CarRegion(val index: Int, val name: String)
    data class CarVfo(val channelId: Int, val name: String, val frequency: String) {
        val title: String
            get() = name.ifBlank { frequency.ifBlank { "—" } }

        val subtitle: String
            get() = if (name.isNotBlank()) {
                frequency
            } else if (channelId >= 0) {
                "Channel ${channelId + 1}"
            } else {
                ""
            }
    }
    data class CarMessage(
        val kind: String,
        val from: String,
        val text: String,
        val time: Long,
    )

    @Volatile
    var connected: Boolean = false
        private set

    @Volatile
    var powerOn: Boolean = true
        private set

    @Volatile
    var scanningRadios: Boolean = false
        private set

    @Volatile
    var connectingRadioId: String = ""
        private set

    @Volatile
    var radioConnectionErrorId: String = ""
        private set

    @Volatile
    var availableRadios: List<CarRadio> = emptyList()
        private set

    @Volatile
    var radioName: String = ""
        private set

    @Volatile
    var regionName: String = ""
        private set

    @Volatile
    var regionIndex: Int = -1
        private set

    @Volatile
    var regions: List<CarRegion> = emptyList()
        private set

    @Volatile
    var vfoA: CarVfo = CarVfo(-1, "", "")
        private set

    @Volatile
    var vfoB: CarVfo = CarVfo(-1, "", "")
        private set

    @Volatile
    var scan: Boolean = false
        private set

    @Volatile
    var dualWatch: Boolean = false
        private set

    @Volatile
    var channels: List<CarChannel> = emptyList()
        private set

    @Volatile
    var messages: List<CarMessage> = emptyList()
        private set

    private val listeners = CopyOnWriteArraySet<() -> Unit>()

    /** Binds the method channel to the active Flutter engine's messenger. */
    fun attach(messenger: BinaryMessenger) {
        val channel = MethodChannel(messenger, CHANNEL)
        channel.setMethodCallHandler(this)
        methodChannel = channel
        // Pull the current snapshot in case Dart pushed state before a car
        // screen (and therefore this channel) existed.
        mainHandler.post {
            methodChannel?.invokeMethod("carConnected", carConnected)
            methodChannel?.invokeMethod("getState", null, object : MethodChannel.Result {
                override fun success(result: Any?) {
                    @Suppress("UNCHECKED_CAST")
                    (result as? Map<String, Any?>)?.let { applyState(it) }
                }

                override fun error(code: String, message: String?, details: Any?) {}
                override fun notImplemented() {}
            })
        }
    }

    fun addListener(listener: () -> Unit) {
        listeners.add(listener)
    }

    fun removeListener(listener: () -> Unit) {
        listeners.remove(listener)
    }

    /** Requests that the preferred radio switch VFO [vfo] ("A" or "B") to
     *  [channelId]. */
    fun requestChannel(channelId: Int, vfo: String) {
        mainHandler.post {
            methodChannel?.invokeMethod(
                "setChannel",
                mapOf("channelId" to channelId, "vfo" to vfo),
            )
        }
    }

    /** Requests that the preferred radio switch to region [index]. */
    fun requestRegion(index: Int) {
        mainHandler.post { methodChannel?.invokeMethod("setRegion", index) }
    }

    /** Requests that the preferred radio enable or disable channel scan. */
    fun requestScan(on: Boolean) {
        mainHandler.post { methodChannel?.invokeMethod("setScan", on) }
    }

    /** Requests that the preferred radio enable or disable dual-watch. */
    fun requestDualWatch(on: Boolean) {
        mainHandler.post { methodChannel?.invokeMethod("setDualWatch", on) }
    }

    /** Requests a fresh enumeration of paired compatible radios. */
    fun requestRadioRefresh() {
        mainHandler.post { methodChannel?.invokeMethod("refreshRadios", null) }
    }

    /** Requests a connection to the paired radio identified by [id]. */
    fun requestRadioConnection(id: String) {
        mainHandler.post {
            methodChannel?.invokeMethod("connectRadio", mapOf("id" to id))
        }
    }

    /** Requests the connected radio power on ([on] true) or off ([on] false). */
    fun requestRadioPower(on: Boolean) {
        mainHandler.post { methodChannel?.invokeMethod("setRadioPower", on) }
    }

    /** Requests disconnecting from the currently connected radio. */
    fun requestDisconnect() {
        mainHandler.post { methodChannel?.invokeMethod("disconnectRadio", null) }
    }

    /** Notifies Dart whether a car (Android Auto) session is projecting, so it
     *  can decide whether to read incoming messages aloud. */
    fun setCarConnected(connected: Boolean) {
        carConnected = connected
        mainHandler.post { methodChannel?.invokeMethod("carConnected", connected) }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "updateState" -> {
                @Suppress("UNCHECKED_CAST")
                val map = call.arguments as? Map<String, Any?> ?: emptyMap()
                applyState(map)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun applyState(map: Map<String, Any?>) {
        connected = map["connected"] as? Boolean ?: false
        powerOn = map["powerOn"] as? Boolean ?: true
        scanningRadios = map["scanningRadios"] as? Boolean ?: false
        connectingRadioId = map["connectingRadioId"] as? String ?: ""
        radioConnectionErrorId = map["radioConnectionErrorId"] as? String ?: ""
        availableRadios = (map["availableRadios"] as? List<*>).orEmpty().mapNotNull { item ->
            val m = item as? Map<*, *> ?: return@mapNotNull null
            val id = m["id"] as? String ?: return@mapNotNull null
            CarRadio(id, m["name"] as? String ?: "")
        }
        radioName = map["radioName"] as? String ?: ""
        regionName = map["regionName"] as? String ?: ""
        regionIndex = (map["regionIndex"] as? Number)?.toInt() ?: -1
        scan = map["scan"] as? Boolean ?: false
        dualWatch = map["dualWatch"] as? Boolean ?: false
        vfoA = parseVfo(map["vfoA"])
        vfoB = parseVfo(map["vfoB"])
        regions = (map["regions"] as? List<*>).orEmpty().mapNotNull { item ->
            val m = item as? Map<*, *> ?: return@mapNotNull null
            val index = (m["index"] as? Number)?.toInt() ?: return@mapNotNull null
            CarRegion(index, m["name"] as? String ?: "")
        }
        channels = (map["channels"] as? List<*>).orEmpty().mapNotNull { item ->
            val m = item as? Map<*, *> ?: return@mapNotNull null
            val id = (m["id"] as? Number)?.toInt() ?: return@mapNotNull null
            CarChannel(id, m["name"] as? String ?: "", m["frequency"] as? String ?: "")
        }
        messages = (map["messages"] as? List<*>).orEmpty().mapNotNull { item ->
            val m = item as? Map<*, *> ?: return@mapNotNull null
            CarMessage(
                kind = m["kind"] as? String ?: "",
                from = m["from"] as? String ?: "",
                text = m["text"] as? String ?: "",
                time = (m["time"] as? Number)?.toLong() ?: 0L,
            )
        }
        notifyListeners()
    }

    private fun parseVfo(value: Any?): CarVfo {
        val m = value as? Map<*, *> ?: return CarVfo(-1, "", "")
        return CarVfo(
            channelId = (m["channelId"] as? Number)?.toInt() ?: -1,
            name = m["name"] as? String ?: "",
            frequency = m["frequency"] as? String ?: "",
        )
    }

    private fun notifyListeners() {
        mainHandler.post { listeners.forEach { it() } }
    }
}
