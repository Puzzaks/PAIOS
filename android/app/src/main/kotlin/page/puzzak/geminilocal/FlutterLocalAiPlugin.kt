package page.puzzak.geminilocal

import android.content.Context
// NEW IMPORTS for model status and logging
import android.util.Log
import com.google.mlkit.genai.common.DownloadStatus
import com.google.mlkit.genai.common.FeatureStatus
// END NEW IMPORTS
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.GenerateContentResponse
import com.google.mlkit.genai.prompt.GenerativeModel
import com.google.mlkit.genai.prompt.TextPart
import com.google.mlkit.genai.prompt.generateContentRequest
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onCompletion
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.transform
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
// ADD these imports for opening the Play Store
import android.content.Intent
import android.net.Uri

/** FlutterLocalAiPlugin */
class FlutterLocalAiPlugin : FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler {
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var generativeModel: GenerativeModel? = null
    private var instructions: String? = null
    private val coroutineScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private lateinit var context: Context

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext

        methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_local_ai")
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "flutter_local_ai_events")
        eventChannel.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "init" -> {
                instructions = call.argument("instructions")
                coroutineScope.launch {
                    try {
                        val available = initAiCore()
                        result.success(available)
                    } catch (e: Exception) {
                        result.error("INIT_ERROR", e.message, null)
                    }
                }
            }
            "openAICorePlayStore" -> {
                try {
                    openPlayStore()
                    result.success(null)
                } catch (e: Exception) {
                    result.error("PLAY_STORE_ERROR", "Could not open Play Store: ${e.message}", null)
                }
            }
            "dispose" -> {
                dispose()
                result.success(null)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        if (events == null) return

        val args = arguments as? Map<String, Any>
        val method = args?.get("method") as? String
        val payload = args?.get("payload") as? Map<String, Any>

        if (method == null || payload == null) {
            events.error("INVALID_ARGS", "Missing 'method' or 'payload' in EventChannel arguments", null)
            return
        }

        when (method) {
            "generateText" -> handleGenerateText(payload, events)
            "generateTextStream" -> handleGenerateTextStream(payload, events)
            else -> events.error("UNKNOWN_METHOD", "Unknown method '$method' for EventChannel", null)
        }
    }

    private fun handleGenerateText(payload: Map<String, Any>, events: EventChannel.EventSink) {
        val prompt = payload["prompt"] as? String
        if (prompt == null) {
            events.error("INVALID_ARG", "Prompt is required", null)
            return
        }
        val configMap = payload["config"] as? Map<String, Any>

        coroutineScope.launch {
            try {
                withContext(Dispatchers.Main) {
                    events.success(mapOf("status" to "Loading", "response" to null, "error" to null))
                }
                val response = generateTextAsync(prompt, configMap)
                withContext(Dispatchers.Main) {
                    events.success(mapOf("status" to "Done", "response" to response, "error" to null))
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    events.success(mapOf("status" to "Error", "response" to null, "error" to e.message))
                }
            } finally {
                withContext(Dispatchers.Main) {
                    events.endOfStream()
                }
            }
        }
    }

    private fun handleGenerateTextStream(payload: Map<String, Any>, events: EventChannel.EventSink) {
        val prompt = payload["prompt"] as? String
        if (prompt == null) {
            events.error("INVALID_ARG", "Prompt is required for streaming", null)
            return
        }
        val configMap = payload["config"] as? Map<String, Any>

        coroutineScope.launch {
            try {
                withContext(Dispatchers.Main) {
                    events.success(mapOf("status" to "Loading", "response" to null, "error" to null))
                }

                generateTextStream(prompt, configMap)
                    .onEach { chunkMap ->
                        withContext(Dispatchers.Main) {
                            events.success(mapOf("status" to "Streaming", "response" to chunkMap, "error" to null))
                        }
                    }
                    .onCompletion {
                        withContext(Dispatchers.Main) {
                            events.success(mapOf("status" to "Done", "response" to null, "error" to null))
                            events.endOfStream()
                        }
                    }
                    .catch { e ->
                        withContext(Dispatchers.Main) {
                            events.success(mapOf("status" to "Error", "response" to null, "error" to e.message))
                            events.endOfStream()
                        }
                    }
                    .launchIn(this) // Start collecting the flow in the coroutine scope

            } catch (e: Exception) {
                // Catch setup errors before the flow starts
                withContext(Dispatchers.Main) {
                    events.success(mapOf("status" to "Error", "response" to null, "error" to e.message))
                    events.endOfStream()
                }
            }
        }
    } // <-- *** THIS WAS THE MISSING BRACE ***

    override fun onCancel(arguments: Any?) {
        // Not strictly needed to implement, but good practice
    }

    private suspend fun initAiCore(): String = withContext(Dispatchers.IO) {
        try {
            if (generativeModel == null) {
                generativeModel = com.google.mlkit.genai.prompt.Generation.getClient()
            }

            val status = generativeModel!!.checkStatus()
            when (status) {
                FeatureStatus.AVAILABLE -> {
                    "Available"
                }
                FeatureStatus.UNAVAILABLE -> {
                    "Error: Model unavailable on this device."
                }
                FeatureStatus.DOWNLOADING -> {
                    "Model is already downloading. Please wait."
                }
                FeatureStatus.DOWNLOADABLE -> {
                    Log.d("FlutterLocalAi", "Model is DOWNLOADABLE. Starting download...")
                    var downloadMessage = "Download started..."

                    generativeModel!!.download().collect { status ->
                        when (status) {
                            is DownloadStatus.DownloadStarted ->
                                Log.d("FlutterLocalAi", "starting download for Gemini Nano")
                            is DownloadStatus.DownloadProgress ->
                                Log.d("FlutterLocalAi", "Nano ${status.totalBytesDownloaded} bytes downloaded")
                            DownloadStatus.DownloadCompleted -> {
                                Log.d("FlutterLocalAi", "Gemini Nano download complete")
                                downloadMessage = "Model download complete"
                            }
                            is DownloadStatus.DownloadFailed -> {
                                Log.e("FlutterLocalAi", "Nano download failed ${status.e.message}")
                                throw Exception("Model download failed: ${status.e.message}")
                            }
                        }
                    }
                    downloadMessage
                }
                else -> "Unknown model status: $status"
            }
        } catch (e: Exception) {
            android.util.Log.e("FlutterLocalAi", "initAiCore error: ${e.javaClass.simpleName} - ${e.message}", e)
            "Error: ${e.message}"
        }
    }

    private suspend fun generateTextAsync(
        prompt: String,
        configMap: Map<String, Any>?
    ): Map<String, Any> = withContext(Dispatchers.IO) {
        try {
            if (generativeModel == null) {
                generativeModel = com.google.mlkit.genai.prompt.Generation.getClient()
            }
            val fullPrompt = if (instructions != null) {
                "${instructions}\n\n$prompt"
            } else {
                prompt
            }
            val maxOutputTokensValue = configMap?.get("maxTokens")?.let { (it as Number).toInt() }
            val temperatureValue = configMap?.get("temperature")?.let { (it as Number).toDouble()?.toFloat() }
            val request = generateContentRequest(TextPart(fullPrompt)) {
                maxOutputTokens = maxOutputTokensValue
                temperature = temperatureValue
            }
            val startTime = System.currentTimeMillis()
            val response: GenerateContentResponse = generativeModel!!.generateContent(request)
            val generationTime = System.currentTimeMillis() - startTime
            val generatedText = response.candidates.firstOrNull()?.text ?: ""
            val tokenCount = generatedText.split(" ").size
            mapOf(
                "text" to generatedText,
                "generationTimeMs" to generationTime,
                "tokenCount" to (tokenCount ?: generatedText.split(" ").size)
            )
        } catch (e: Exception) {
            android.util.Log.e("FlutterLocalAi", "generateText error: ${e.javaClass.simpleName} - ${e.message}", e)
            val errorMessage = e.message ?: ""
            val errorCode = extractErrorCode(errorMessage)
            if (errorCode == -101) {
                throw Exception("AICore is not installed or version is too low (Error -101). Please install or update Google AICore from the Play Store: https://play.google.com/store/apps/details?id=com.google.android.aicore")
            }
            throw Exception("Error generating text: ${e.message}")
        }
    }

    private fun generateTextStream(
        prompt: String,
        configMap: Map<String, Any>?
    ): Flow<Map<String, Any>> {
        if (generativeModel == null) {
            generativeModel = com.google.mlkit.genai.prompt.Generation.getClient()
        }
        val fullPrompt = if (instructions != null) {
            "${instructions}\n\n$prompt"
        } else {
            prompt
        }
        val maxOutputTokensValue = configMap?.get("maxTokens")?.let { (it as Number).toInt() }
        val temperatureValue = configMap?.get("temperature")?.let { (it as Number).toDouble()?.toFloat() }
        val request = generateContentRequest(TextPart(fullPrompt)) {
            maxOutputTokens = maxOutputTokensValue
            temperature = temperatureValue
        }
        var fullResponse = ""
        val startTime = System.currentTimeMillis()

        return generativeModel!!.generateContentStream(request)
            .transform { chunk ->
                val newChunkText = chunk.candidates.firstOrNull()?.text ?: ""
                fullResponse += newChunkText
                val generationTime = System.currentTimeMillis() - startTime
                val tokenCount = fullResponse.split(" ").filter { it.isNotEmpty() }.size
                emit(mapOf(
                    "text" to fullResponse,
                    "chunk" to newChunkText,
                    "generationTimeMs" to generationTime,
                    "tokenCount" to tokenCount
                ))
            }
            .catch { e ->
                android.util.Log.e("FlutterLocalAi", "generateTextStream error: ${e.javaClass.simpleName} - ${e.message}", e)
                val errorMessage = e.message ?: ""
                val errorCode = extractErrorCode(errorMessage)
                val exception = if (errorCode == -101) {
                    Exception("AICore is not installed or version is too low (Error -101). Please install or update Google AICore from the Play Store: https://play.google.com/store/apps/details?id=com.google.android.aicore")
                } else {
                    Exception("Error generating text stream: ${e.message}")
                }
                throw exception
            }
    }

    private fun openPlayStore() {
        if (!::context.isInitialized) {
            throw Exception("Context not initialized")
        }

        val intent = Intent(Intent.ACTION_VIEW).apply {
            data = Uri.parse("https://play.google.com/store/apps/details?id=com.google.android.aicore")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        if (intent.resolveActivity(context.packageManager) != null) {
            context.startActivity(intent)
        } else {
            throw Exception("No app found to handle Play Store URL")
        }
    }

    private fun dispose() {
        coroutineScope.cancel()
        generativeModel = null
        instructions = null
    }

    private fun extractErrorCode(errorMessage: String): Int {
        val regex = "Error (-?\\d+)".toRegex()
        val match = regex.find(errorMessage)
        return match?.groups?.get(1)?.value?.toInt() ?: 0
    }

    // THIS WAS THE MISSING FUNCTION
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        dispose()
    }
}