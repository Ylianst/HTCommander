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
 *   - Dart -> native: `updateState` refreshes [channels], [currentChannelId]
 *     and [messages]; registered [listeners] are then notified to invalidate.
 *   - native -> Dart: [requestChannel] invokes `setChannel` back on Dart.
 */
object AndroidAutoBridge : MethodChannel.MethodCallHandler {
    private const val CHANNEL = "com.htcommander/android_auto"

    private val mainHandler = Handler(Looper.getMainLooper())
    private var methodChannel: MethodChannel? = null

    data class CarChannel(val id: Int, val name: String)
    data class CarMessage(val from: String, val text: String, val time: Long)

    @Volatile
    var connected: Boolean = false
        private set

    @Volatile
    var radioName: String = ""
        private set

    @Volatile
    var currentChannelId: Int = -1
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

    /** Requests that the preferred radio switch VFO A to [channelId]. */
    fun requestChannel(channelId: Int) {
        mainHandler.post { methodChannel?.invokeMethod("setChannel", channelId) }
    }

    /** Notifies Dart whether a car (Android Auto) session is projecting, so it
     *  can decide whether to read incoming messages aloud. */
    fun setCarConnected(connected: Boolean) {
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
        radioName = map["radioName"] as? String ?: ""
        currentChannelId = (map["currentChannelId"] as? Number)?.toInt() ?: -1
        channels = (map["channels"] as? List<*>).orEmpty().mapNotNull { item ->
            val m = item as? Map<*, *> ?: return@mapNotNull null
            val id = (m["id"] as? Number)?.toInt() ?: return@mapNotNull null
            CarChannel(id, m["name"] as? String ?: "")
        }
        messages = (map["messages"] as? List<*>).orEmpty().mapNotNull { item ->
            val m = item as? Map<*, *> ?: return@mapNotNull null
            CarMessage(
                from = m["from"] as? String ?: "",
                text = m["text"] as? String ?: "",
                time = (m["time"] as? Number)?.toLong() ?: 0L,
            )
        }
        notifyListeners()
    }

    private fun notifyListeners() {
        mainHandler.post { listeners.forEach { it() } }
    }
}
