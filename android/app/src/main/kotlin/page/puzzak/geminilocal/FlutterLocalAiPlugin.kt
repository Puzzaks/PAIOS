package page.puzzak.geminilocal

import android.content.Context
import android.util.Log
import com.google.mlkit.genai.common.DownloadStatus
import com.google.mlkit.genai.common.FeatureStatus
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
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onCompletion
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.transform
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import android.content.Intent
import android.net.Uri

class FlutterLocalAiPlugin : FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler {
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var downloadChannel : EventChannel
    private var generativeModel: GenerativeModel? = null
    private var instructions: String? = null
    private val coroutineScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private lateinit var context: Context

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext

        methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_local_ai")
        methodChannel.setMethodCallHandler(this)

        downloadChannel = EventChannel(flutterPluginBinding.binaryMessenger, "download_channel")

        eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "flutter_local_ai_events")
        eventChannel.setStreamHandler(this)

        downloadChannel.setStreamHandler(
            object : EventChannel.StreamHandler {
                private var downloadScope: CoroutineScope? = null
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    if (events == null) return

                    downloadScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
                    downloadScope?.launch {
                        initAiCoreFlow()
                            .catch { e -> events.error("FlowError", e.message, null) }
                            .collect { statusString ->
                                events.success(statusString)
                            }
                    }
                }
                override fun onCancel(arguments: Any?) {
                    downloadScope?.cancel()
                    downloadScope = null
                }
            }
        )
    }

    private fun initAiCoreFlow(): Flow<String> = flow {
        try {
            if (generativeModel == null) {
                generativeModel = com.google.mlkit.genai.prompt.Generation.getClient()
            }
            val status = generativeModel!!.checkStatus()
            when (status) {
                FeatureStatus.AVAILABLE -> emit("Available=Available=0")
                FeatureStatus.UNAVAILABLE -> emit("Error=AICore=Unavailable")
                FeatureStatus.DOWNLOADING,
                FeatureStatus.DOWNLOADABLE -> {
                    emit("Download=downloading_model=0")

                    generativeModel!!.download().collect { downloadStatus ->
                        when (downloadStatus) {
                            is DownloadStatus.DownloadStarted ->   emit("Download=downloading_model=0")
                            is DownloadStatus.DownloadProgress ->  emit("Download=downloading_model=${downloadStatus.totalBytesDownloaded}")
                            is DownloadStatus.DownloadCompleted -> emit("Available=Download=0")
                            is DownloadStatus.DownloadFailed ->    emit("Error=Download=${downloadStatus.e.message}")
                            else ->                                emit("Error=Download=Unknown")
                        }
                    }
                }
                else -> emit("Error=Unknown=$status")
            }
        } catch (e: Exception) {
            emit("Error=Unknown=${e.message}")
        }
    }.flowOn(Dispatchers.IO)

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getModelInfo" -> {
                coroutineScope.launch {
                    try {
                        val info = getModelInfo()
                        result.success(info)
                    } catch (e: Exception) {
                        result.error("GET_MODEL_INFO_ERROR", e.message, null)
                    }
                }
            }
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

    private suspend fun getModelInfo(): Map<String, String> = withContext(Dispatchers.IO) {
        try {
            if (generativeModel == null) {
                generativeModel = com.google.mlkit.genai.prompt.Generation.getClient()
            }

            val status = generativeModel!!.checkStatus()
            val statusString = when (status) {
                FeatureStatus.AVAILABLE -> "Available"
                FeatureStatus.UNAVAILABLE -> "Unavailable"
                FeatureStatus.DOWNLOADING -> "Downloading"
                FeatureStatus.DOWNLOADABLE -> "Downloadable"
                else -> "Unknown"
            }
            var modelVersion = "Unknown"
            if (status == FeatureStatus.AVAILABLE) {
                try {
                    modelVersion = generativeModel!!.getBaseModelName() ?: "Unknown"
                } catch (e: Exception) {
                    // Could fail if model is not ready, etc.
                    Log.w("FlutterLocalAi", "Could not get base model name: ${e.message}")
                }
            }

            mapOf(
                "status" to statusString,
                "version" to modelVersion
            )
        } catch (e: Exception) {
            android.util.Log.e("FlutterLocalAi", "getModelInfo error: ${e.javaClass.simpleName} - ${e.message}", e)
            mapOf(
                "status" to "Error",
                "version" to (e.message ?: "Unknown error")
            )
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
                    events.success(mapOf("status" to "Done", "response" to null, "error" to null, "reason" to null))
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
        val reason = payload["reason"] as? String
        if (prompt == null) {
            events.error("INVALID_ARG", "Prompt is required for streaming", null)
            return
        }
        val configMap = payload["config"] as? Map<String, Any>
        var lastFinishReason: String? = "UNKNOWN"
        coroutineScope.launch {
            try {
                withContext(Dispatchers.Main) {
                    events.success(mapOf("status" to "Loading", "response" to null, "error" to null))
                }

                generateTextStream(prompt, configMap)
                    .onEach { chunkMap ->
                        val reasonFromChunk = chunkMap["reason"] as? String
                        if (reasonFromChunk != null && reasonFromChunk != "null") {
                            lastFinishReason = reasonFromChunk
                        }
                        withContext(Dispatchers.Main) {
                            events.success(mapOf("status" to "Streaming", "response" to chunkMap, "error" to null))
                        }
                    }
                    .onCompletion {
                        withContext(Dispatchers.Main) {
                            events.success(mapOf("status" to "Done", "response" to null, "error" to null, "reason" to lastFinishReason))
                            events.endOfStream()
                        }
                    }
                    .catch { e ->
                        withContext(Dispatchers.Main) {
                            events.success(mapOf("status" to "Error", "response" to null, "error" to e.message))
                            events.endOfStream()
                        }
                    }
                    .launchIn(this)

            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    events.success(mapOf("status" to "Error", "response" to null, "error" to e.message))
                    events.endOfStream()
                }
            }
        }
    }

    override fun onCancel(arguments: Any?) {

    }

    private suspend fun initAiCore(): String = withContext(Dispatchers.IO) {
        try {
            if (generativeModel == null) {
                generativeModel = com.google.mlkit.genai.prompt.Generation.getClient()
            }
            val status = generativeModel!!.checkStatus()
            when (status) {
                FeatureStatus.AVAILABLE -> "Available=Available=0"
                FeatureStatus.UNAVAILABLE -> "Error=AICore=Unavailable"
                FeatureStatus.DOWNLOADING -> "Download=In Progress=0"
                FeatureStatus.DOWNLOADABLE -> {
                    var downloadMessage = "Download=In Progress=0"
                    generativeModel!!.download().collect {
                        status -> when (status) {
                            is DownloadStatus.DownloadStarted ->   downloadMessage = "Download=In Progress=0"
                            is DownloadStatus.DownloadProgress ->  downloadMessage = "Download=In Progress=${status.totalBytesDownloaded}"
                            is DownloadStatus.DownloadCompleted -> downloadMessage = "Available=Download=0"
                            is DownloadStatus.DownloadFailed ->    downloadMessage = "Error=Download=${status.e.message}"
                            else ->                                downloadMessage = "Error=Download=Unknown"
                        }
                    }
                    downloadMessage
                }
                else -> "Error=Unknown=$status"
            }
        } catch (e: Exception) {
            "Error=Unknown=${e.message}"
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
        val candidateCountValue = configMap?.get("candidates")?.let { (it as Number).toInt() }
        val maxOutputTokensValue = configMap?.get("maxTokens")?.let { (it as Number).toInt() }
        val temperatureValue = configMap?.get("temperature")?.let { (it as Number).toDouble()?.toFloat() }
        val request = generateContentRequest(TextPart(fullPrompt)) {
            maxOutputTokens = maxOutputTokensValue
            temperature = temperatureValue
            candidateCount = candidateCountValue
        }
        var fullResponse = ""
        val startTime = System.currentTimeMillis()

        return generativeModel!!.generateContentStream(request)
            .transform { chunk ->
                val newChunkText = chunk.candidates.firstOrNull()?.text ?: ""
                val finishReason = chunk.candidates.firstOrNull()?.finishReason.toString()
                fullResponse += newChunkText
                val generationTime = System.currentTimeMillis() - startTime
                val tokenCount = fullResponse.split(" ").filter { it.isNotEmpty() }.size
                emit(mapOf(
                    "text" to fullResponse,
                    "chunk" to newChunkText,
                    "generationTimeMs" to generationTime,
                    "tokenCount" to tokenCount,
                    "reason" to finishReason
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

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        downloadChannel.setStreamHandler(null)
        dispose()
    }
}