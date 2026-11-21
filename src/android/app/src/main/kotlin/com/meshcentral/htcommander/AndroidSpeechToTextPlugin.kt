package com.meshcentral.htcommander

import android.content.Context
import android.content.Intent
import android.media.AudioFormat
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.OutputStream
import java.util.concurrent.Executors

/** On-device PCM recognition. Each transmission owns its recognizer and
 * listener so a delayed final can never be relabelled as another transmission. */
class AndroidSpeechToTextPlugin(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    companion object {
        private const val TAG = "AndroidStt"
        private const val RATE = 16000
        private const val MAX_QUEUED_BYTES = RATE * 2 * 10
    }

    private class Session(
        val id: Int,
        val recognizer: SpeechRecognizer,
        val input: ParcelFileDescriptor,
        var output: OutputStream?,
    ) {
        var text = ""
        var partial = ""
        var closing = false
        var closedAt = 0L
    }

    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private val sessions = mutableMapOf<Int, Session>()
    private var activeId: Int? = null
    private var sink: EventChannel.EventSink? = null
    private var localeId = ""
    private var queuedBytes = 0
    private var overloaded = false
    private var lastDiagnostics = 0L

    init {
        MethodChannel(messenger, "com.htcommander/android_speech_to_text")
            .setMethodCallHandler(this)
        EventChannel(messenger, "com.htcommander/android_speech_to_text_events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    sink = events
                }
                override fun onCancel(arguments: Any?) { sink = null }
            })
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "isSupported" -> result.success(isSupported())
                "initialize" -> {
                    localeId = call.argument<String>("localeId") ?: ""
                    result.success(isSupported())
                }
                "startSegment" -> {
                    start(call.argument<Int>("segmentId")!!,
                        call.argument<List<String>>("hotwords") ?: emptyList())
                    result.success(null)
                }
                "appendAudio" -> {
                    append(call.argument<Int>("segmentId")!!,
                        call.argument<ByteArray>("data")!!)
                    result.success(null)
                }
                "completeSegment" -> {
                    complete(call.argument<Int>("segmentId")!!)
                    result.success(null)
                }
                "resetSegment" -> {
                    sessions[call.argument<Int>("segmentId")]?.let { release(it) }
                    result.success(null)
                }
                "dispose" -> {
                    sessions.values.toList().forEach { release(it) }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            Log.e(TAG, "${call.method} failed", e)
            result.error("SPEECH_ERROR", e.message, null)
        }
    }

    private fun isSupported() =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            SpeechRecognizer.isOnDeviceRecognitionAvailable(context)

    private fun event(values: Map<String, Any?>) {
        sink?.success(values)
    }

    private fun diagnostics(id: Int, decodeMs: Long = 0, force: Boolean = false) {
        val now = SystemClock.elapsedRealtime()
        if (!force && queuedBytes != 0 && now - lastDiagnostics < 250) return
        lastDiagnostics = now
        event(mapOf("event" to "diagnostics", "segmentId" to id,
            "queuedAudioMs" to queuedBytes * 1000 / (RATE * 2),
            "decodeMs" to decodeMs, "overloaded" to overloaded))
    }

    private fun result(session: Session, final: Boolean) {
        val text = listOf(session.text, session.partial).filter { it.isNotEmpty() }.joinToString(" ")
        event(mapOf("event" to "result", "segmentId" to session.id,
            "text" to text, "isFinal" to final))
    }

    private fun fail(session: Session, code: String) {
        Log.e(TAG, "segment ${session.id}: $code")
        event(mapOf("event" to "error", "segmentId" to session.id,
            "code" to code, "overloaded" to overloaded))
        release(session)
    }

    private fun start(id: Int, hotwords: List<String>) {
        check(isSupported()) { "On-device PCM recognition is unavailable" }
        activeId?.let { old -> sessions[old]?.let { complete(old) } }
        val pipe = ParcelFileDescriptor.createPipe()
        val rec = SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
        val session = Session(id, rec, pipe[0], ParcelFileDescriptor.AutoCloseOutputStream(pipe[1]))
        sessions[id] = session
        activeId = id
        rec.setRecognitionListener(listener(session))
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            if (localeId.isNotEmpty() && localeId != "auto") {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, localeId)
            }
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, session.input)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, RATE)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, 1)
            putExtra(RecognizerIntent.EXTRA_SEGMENTED_SESSION, RecognizerIntent.EXTRA_AUDIO_SOURCE)
            putExtra(RecognizerIntent.EXTRA_BIASING_STRINGS, ArrayList(hotwords))
        }
        try {
            rec.startListening(intent)
        } catch (e: Exception) {
            fail(session, "startListening: ${e.message}")
        }
    }

    private fun append(id: Int, data: ByteArray) {
        val session = sessions[id] ?: return
        if (session.closing) return
        val output = session.output ?: return
        if (queuedBytes + data.size > MAX_QUEUED_BYTES) {
            overloaded = true
            fail(session, "More than 10 seconds of audio queued; transmission interrupted")
            diagnostics(id, force = true)
            return
        }
        queuedBytes += data.size
        diagnostics(id)
        val timeout = Runnable {
            if (sessions[id] === session) {
                overloaded = true
                fail(session, "Audio pipe stalled")
                diagnostics(id, force = true)
            }
        }
        main.postDelayed(timeout, session, 10000)
        io.execute {
            var failure: Exception? = null
            try { output.write(data) } catch (e: Exception) { failure = e }
            main.post {
                main.removeCallbacks(timeout)
                queuedBytes -= data.size
                val wasOverloaded = overloaded
                if (queuedBytes <= MAX_QUEUED_BYTES / 2) overloaded = false
                failure?.let { e ->
                    if (sessions[id] === session) fail(session, "audio write: ${e.message}")
                }
                diagnostics(id, force = queuedBytes == 0 || wasOverloaded != overloaded)
            }
        }
    }

    private fun complete(id: Int) {
        val session = sessions[id] ?: return
        if (session.closing) return
        session.closing = true
        session.closedAt = SystemClock.elapsedRealtime()
        if (activeId == id) activeId = null
        val output = session.output
        io.execute {
            try {
                output?.close()
            } catch (e: Exception) {
                main.post {
                    if (sessions[id] === session) fail(session, "audio close: ${e.message}")
                }
            } finally {
                main.post { session.output = null }
            }
        }
        main.postDelayed(Runnable {
            if (sessions[id] === session) fail(session, "Final result timed out")
        }, session, 10000)
    }

    private fun release(session: Session) {
        if (sessions.remove(session.id) !== session) return
        main.removeCallbacksAndMessages(session)
        if (activeId == session.id) activeId = null
        session.recognizer.cancel()
        session.recognizer.destroy()
        session.input.close()
        val output = session.output
        session.output = null
        // Close directly to unblock a writer; queuing close behind a blocked
        // write would prevent every subsequent transmission from progressing.
        try { output?.close() } catch (e: Exception) {
            Log.w(TAG, "Closing cancelled audio pipe", e)
        }
    }

    private fun listener(session: Session) = object : RecognitionListener {
        private fun valid() = sessions[session.id] === session
        private fun first(bundle: Bundle?) =
            bundle?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull() ?: ""
        override fun onReadyForSpeech(params: Bundle?) {
            if (valid()) event(mapOf("event" to "processing", "active" to true))
        }
        override fun onBeginningOfSpeech() {}
        override fun onRmsChanged(rmsdB: Float) {}
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() {}
        override fun onEvent(eventType: Int, params: Bundle?) {}
        override fun onError(error: Int) {
            if (valid()) fail(session, "Recognizer error $error")
        }
        override fun onPartialResults(partialResults: Bundle?) {
            if (!valid()) return
            session.partial = first(partialResults)
            result(session, false)
        }
        override fun onSegmentResults(segmentResults: Bundle) {
            if (!valid()) return
            session.text = listOf(session.text, first(segmentResults))
                .filter { it.isNotEmpty() }.joinToString(" ")
            session.partial = ""
            result(session, false)
        }
        override fun onResults(results: Bundle?) {
            if (!valid()) return
            session.partial = first(results)
            finish()
        }
        override fun onEndOfSegmentedSession() {
            if (valid()) finish()
        }
        private fun finish() {
            result(session, true)
            diagnostics(session.id, if (session.closedAt == 0L) 0
                else SystemClock.elapsedRealtime() - session.closedAt, force = true)
            release(session)
            event(mapOf("event" to "processing", "active" to sessions.isNotEmpty()))
        }
    }
}
