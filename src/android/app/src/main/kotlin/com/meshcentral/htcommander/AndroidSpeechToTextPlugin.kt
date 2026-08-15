package com.meshcentral.htcommander

import android.content.Context
import android.content.Intent
import android.media.AudioFormat
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
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

/**
 * Feeds raw PCM into Android's on-device [SpeechRecognizer] without bundling any
 * model in the APK.
 *
 * Android 13 (API 33) added [RecognizerIntent.EXTRA_AUDIO_SOURCE], which lets a
 * caller hand the recognizer an already-open audio source (a
 * [ParcelFileDescriptor]) instead of having it open the microphone. This plugin
 * creates a pipe, passes the read end to the recognizer, and writes the radio
 * PCM delivered from Dart into the write end. Combined with
 * `EXTRA_SEGMENTED_SESSION = EXTRA_AUDIO_SOURCE`, the recognition session ends
 * only when the write end is closed, so the app controls segment boundaries.
 *
 * Channel contract (mirrors [AndroidSpeechToTextEngine] on the Dart side):
 *   - MethodChannel `com.htcommander/android_speech_to_text`
 *       initialize {localeId} -> Bool   (false if unsupported/unavailable)
 *       startSegment                     (opens a new recognition session)
 *       appendAudio {data, sampleRate}   (16-bit LE mono PCM at 16 kHz)
 *       completeSegment                  (closes audio -> forces final result)
 *       resetSegment                     (cancels without emitting a result)
 *       dispose
 *   - EventChannel `com.htcommander/android_speech_to_text_events`
 *       {event: "result", text, isFinal}
 *       {event: "processing", active}
 *       {event: "error", code}
 *
 * The recognizer's audio source is fixed at 16 kHz mono 16-bit PCM (the
 * `EXTRA_AUDIO_SOURCE_*` defaults); the Dart side resamples before sending.
 */
class AndroidSpeechToTextPlugin(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "AndroidStt"
        private const val METHOD_CHANNEL = "com.htcommander/android_speech_to_text"
        private const val EVENT_CHANNEL = "com.htcommander/android_speech_to_text_events"
        private const val SAMPLE_RATE = 16000
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)

    /** Single background thread that owns the blocking writes into the pipe. */
    private val ioExecutor = Executors.newSingleThreadExecutor()

    private var eventSink: EventChannel.EventSink? = null
    private var recognizer: SpeechRecognizer? = null
    private var localeId: String = ""

    /** Write end of the pipe for the active segment, or null when idle. */
    private var audioOut: OutputStream? = null
    /** Read end handed to the recognizer; closed only on teardown. */
    private var audioIn: ParcelFileDescriptor? = null

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> {
                localeId = call.argument<String>("localeId") ?: ""
                result.success(initialize())
            }
            "startSegment" -> {
                startSegment()
                result.success(null)
            }
            "appendAudio" -> {
                val data = call.argument<ByteArray>("data")
                if (data != null) appendAudio(data)
                result.success(null)
            }
            "completeSegment" -> {
                completeSegment()
                result.success(null)
            }
            "resetSegment" -> {
                resetSegment()
                result.success(null)
            }
            "dispose" -> {
                dispose()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Verifies the platform can feed PCM to an on-device recognizer and creates
     * the (reused) recognizer instance. Returns false when the device is below
     * API 33 or has no on-device recognition service, so the Dart engine reports
     * itself unsupported and speech-to-text stays disabled.
     */
    private fun initialize(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return false
        if (!SpeechRecognizer.isOnDeviceRecognitionAvailable(context)) return false
        if (recognizer != null) return true
        return try {
            recognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(context).apply {
                setRecognitionListener(listener)
            }
            true
        } catch (e: Exception) {
            Log.w(TAG, "createOnDeviceSpeechRecognizer failed", e)
            false
        }
    }

    private fun startSegment() {
        val rec = recognizer ?: return
        // Discard any session still in flight before opening a new one.
        closeAudio()
        rec.cancel()

        val pipe = ParcelFileDescriptor.createPipe()
        val readSide = pipe[0]
        val writeSide = pipe[1]
        audioOut = ParcelFileDescriptor.AutoCloseOutputStream(writeSide)
        // SpeechRecognizer marshals the audio-source descriptor asynchronously
        // (after it binds to the recognition service), so this read end must
        // stay open until the segment is torn down; closing it here would race
        // the transfer. Keeping it open does not affect end-of-audio detection,
        // which depends only on the write end being closed.
        audioIn = readSide

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            if (localeId.isNotEmpty() && localeId != "auto") {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, localeId)
            }
            // Feed audio from the pipe instead of the microphone.
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, readSide)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, SAMPLE_RATE)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, 1)
            // End the session only when the audio pipe is closed.
            putExtra(
                RecognizerIntent.EXTRA_SEGMENTED_SESSION,
                RecognizerIntent.EXTRA_AUDIO_SOURCE,
            )
        }

        try {
            rec.startListening(intent)
        } catch (e: Exception) {
            Log.w(TAG, "startListening failed", e)
            closeAudio()
        }
    }

    private fun appendAudio(data: ByteArray) {
        val out = audioOut ?: return
        ioExecutor.execute {
            try {
                out.write(data)
            } catch (e: Exception) {
                // Pipe closed or broken (e.g. session already finalized).
                Log.d(TAG, "audio write failed: ${e.message}")
            }
        }
    }

    private fun completeSegment() {
        // Closing the write end signals end-of-audio; the recognizer then emits
        // its final result via onSegmentResults / onResults.
        val out = audioOut
        audioOut = null
        ioExecutor.execute {
            try {
                out?.flush()
                out?.close()
            } catch (_: Exception) {
            }
        }
    }

    private fun resetSegment() {
        closeAudio()
        mainHandler.post {
            try {
                recognizer?.cancel()
            } catch (_: Exception) {
            }
        }
    }

    private fun closeAudio() {
        val out = audioOut
        val inFd = audioIn
        audioOut = null
        audioIn = null
        ioExecutor.execute {
            try {
                out?.close()
            } catch (_: Exception) {
            }
            try {
                inFd?.close()
            } catch (_: Exception) {
            }
        }
    }

    private fun dispose() {
        closeAudio()
        mainHandler.post {
            try {
                recognizer?.destroy()
            } catch (_: Exception) {
            }
            recognizer = null
        }
        ioExecutor.shutdown()
    }

    private fun sendEvent(map: Map<String, Any?>) {
        mainHandler.post { eventSink?.success(map) }
    }

    private fun emitResults(bundle: Bundle?, isFinal: Boolean) {
        val matches = bundle?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        val text = matches?.firstOrNull() ?: return
        sendEvent(mapOf("event" to "result", "text" to text, "isFinal" to isFinal))
    }

    private val listener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {
            sendEvent(mapOf("event" to "processing", "active" to true))
        }

        override fun onBeginningOfSpeech() {}

        override fun onRmsChanged(rmsdB: Float) {}

        override fun onBufferReceived(buffer: ByteArray?) {}

        override fun onEndOfSpeech() {}

        override fun onError(error: Int) {
            sendEvent(mapOf("event" to "error", "code" to error))
            sendEvent(mapOf("event" to "processing", "active" to false))
        }

        override fun onResults(results: Bundle?) {
            emitResults(results, isFinal = true)
            sendEvent(mapOf("event" to "processing", "active" to false))
        }

        override fun onPartialResults(partialResults: Bundle?) {
            emitResults(partialResults, isFinal = false)
        }

        override fun onSegmentResults(segmentResults: Bundle) {
            emitResults(segmentResults, isFinal = true)
        }

        override fun onEndOfSegmentedSession() {
            sendEvent(mapOf("event" to "processing", "active" to false))
        }

        override fun onEvent(eventType: Int, params: Bundle?) {}
    }
}
