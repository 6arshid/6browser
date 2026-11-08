package com.sixarshid.sixbrowser

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.plugin.common.MethodChannel

/**
 * Voice commands with the phone's speech recognizer (Google's on most
 * phones). Progress goes to Dart on the "6browser/voice" channel: "level"
 * (0..1), "partial" and "result" (text), "endOfSpeech", and "error" (a code).
 */
class VoiceInput(private val activity: Activity, private val channel: MethodChannel) {
    private var session: Session? = null

    /** Starts listening in [language] (a BCP 47 tag; null for the phone's). */
    fun start(language: String?): String? {
        if (!SpeechRecognizer.isRecognitionAvailable(activity)) return "unavailable"
        cancel()
        val recognizer = SpeechRecognizer.createSpeechRecognizer(activity)
        val current = Session(recognizer)
        session = current
        recognizer.setRecognitionListener(current)
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_WEB_SEARCH)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, activity.packageName)
            if (language != null) {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, language)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, language)
            }
        }
        recognizer.startListening(intent)
        return null
    }

    /** Stops listening; the result for what was said follows. */
    fun stop() {
        session?.recognizer?.stopListening()
    }

    fun cancel() {
        session?.release(cancel = true)
        session = null
    }

    private inner class Session(val recognizer: SpeechRecognizer) : RecognitionListener {
        private val active get() = session === this

        fun release(cancel: Boolean = false) {
            if (cancel) recognizer.cancel()
            // Not from inside the recognizer's own callback.
            Handler(Looper.getMainLooper()).post { recognizer.destroy() }
        }

        private fun finish(method: String, argument: Any?) {
            if (!active) return
            session = null
            release()
            channel.invokeMethod(method, argument)
        }

        override fun onRmsChanged(rmsdB: Float) {
            if (active) channel.invokeMethod("level", ((rmsdB + 2f) / 12f).coerceIn(0f, 1f).toDouble())
        }

        override fun onPartialResults(partialResults: Bundle?) {
            val text = partialResults
                ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                ?.firstOrNull()
            if (active && !text.isNullOrBlank()) channel.invokeMethod("partial", text)
        }

        override fun onEndOfSpeech() {
            if (active) channel.invokeMethod("endOfSpeech", null)
        }

        override fun onResults(results: Bundle?) = finish(
            "result",
            results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull() ?: "",
        )

        override fun onError(error: Int) = finish(
            "error",
            when (error) {
                SpeechRecognizer.ERROR_NO_MATCH -> "no_match"
                SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "no_speech"
                SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "permission"
                SpeechRecognizer.ERROR_NETWORK,
                SpeechRecognizer.ERROR_NETWORK_TIMEOUT,
                SpeechRecognizer.ERROR_SERVER,
                ERROR_SERVER_DISCONNECTED -> "network"
                SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "busy"
                ERROR_LANGUAGE_NOT_SUPPORTED, ERROR_LANGUAGE_UNAVAILABLE -> "language"
                else -> "error"
            },
        )

        override fun onReadyForSpeech(params: Bundle?) {}
        override fun onBeginningOfSpeech() {}
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEvent(eventType: Int, params: Bundle?) {}
    }

    private companion object {
        // SpeechRecognizer constants added in API 31 (the app supports older).
        const val ERROR_SERVER_DISCONNECTED = 11
        const val ERROR_LANGUAGE_NOT_SUPPORTED = 12
        const val ERROR_LANGUAGE_UNAVAILABLE = 13
    }
}
