package page.puzzak.geminilocal

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.OpenableColumns
import android.provider.Settings
import android.util.Base64
import android.util.Log
import com.google.mlkit.genai.common.DownloadStatus
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.prompt.GenerateContentResponse
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.GenerativeModel
import com.google.mlkit.genai.prompt.ImagePart
import com.google.mlkit.genai.prompt.TextPart
import com.google.mlkit.genai.prompt.generateContentRequest
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import java.io.ByteArrayOutputStream
import java.io.File
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.onCompletion
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.transform
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class FlutterLocalAiPlugin(
    private var activity: Activity? = null
) : FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler, ActivityAware, PluginRegistry.ActivityResultListener {
    companion object {
        private const val REQUEST_CODE_PICK_IMAGE = 0x494D
        private const val MAX_DOWNSAMPLE_DIMENSION = 768

        @Volatile
        var pendingAssistantChatPayload: String? = null

        @Volatile
        var pendingAssistantChatUnarchived: Boolean = true

        @Volatile
        private var pluginInstanceRef: java.lang.ref.WeakReference<FlutterLocalAiPlugin>? = null

        @androidx.annotation.Keep
        @JvmStatic
        fun deliverAssistantChat(messagesJson: String, unarchived: Boolean = true) {
            val plugin = pluginInstanceRef?.get()
            if (plugin != null) {
                plugin.coroutineScope.launch(Dispatchers.Main) {
                    plugin.methodChannel.invokeMethod(
                        "onAssistantChatReceived",
                        mapOf("messages" to messagesJson, "unarchived" to unarchived)
                    )
                }
            } else {
                pendingAssistantChatPayload = messagesJson
                pendingAssistantChatUnarchived = unarchived
            }
        }
    }

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var downloadChannel: EventChannel
    private var generativeModel: GenerativeModel? = null
    private var instructions: String? = null
    private val coroutineScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private var activeStreamJob: Job? = null
    private lateinit var context: Context
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPickImageResult: Result? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        pluginInstanceRef = java.lang.ref.WeakReference(this)

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
            "openAICoreBetaProgram" -> {
                try {
                    openAICoreBetaProgram()
                    result.success(null)
                } catch (e: Exception) {
                    result.error("BETA_PROGRAM_ERROR", "Could not open AICore beta program: ${e.message}", null)
                }
            }
            "openAICoreDevSettings" -> {
                try {
                    openAICoreDevSettings()
                    result.success(null)
                } catch (e: Exception) {
                    result.error("DEV_SETTINGS_ERROR", "Could not open AICore dev settings: ${e.message}", null)
                }
            }
            "pickImage" -> {
                val act = activity
                if (act == null) {
                    result.error("NO_ACTIVITY", "Activity is not attached for picking image", null)
                    return
                }
                pendingPickImageResult?.success(null)
                pendingPickImageResult = result
                try {
                    val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                        type = "image/*"
                        addCategory(Intent.CATEGORY_OPENABLE)
                    }
                    act.startActivityForResult(intent, REQUEST_CODE_PICK_IMAGE)
                } catch (e: Exception) {
                    pendingPickImageResult = null
                    result.error("PICK_IMAGE_ERROR", "Could not launch image picker: ${e.message}", null)
                }
            }
            "getInitialAssistantChat" -> {
                val payload = pendingAssistantChatPayload
                val unarchived = pendingAssistantChatUnarchived
                pendingAssistantChatPayload = null
                if (payload != null) {
                    result.success(mapOf("messages" to payload, "unarchived" to unarchived))
                } else {
                    result.success(null)
                }
            }
            "syncActivePrompt" -> {
                val id = call.argument<String>("id")
                val content = call.argument<String>("content")
                val title = call.argument<String>("title")
                try {
                    val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    prefs.edit().apply {
                        if (id != null) putString("flutter.defaultPromptId", id)
                        if (content != null) putString("flutter.defaultPromptContent", content)
                        if (title != null) putString("flutter.defaultPromptTitle", title)
                        apply()
                    }
                    result.success(true)
                } catch (e: Exception) {
                    result.error("SYNC_ERROR", e.message, null)
                }
            }
            "dispose" -> {
                dispose()
                result.success(null)
            }
            "isDefaultAssistant" -> {
                try {
                    val setting = Settings.Secure.getString(context.contentResolver, "voice_interaction_service")
                    val isDefault = setting != null && setting.contains(context.packageName)
                    result.success(isDefault)
                } catch (e: Exception) {
                    result.success(false)
                }
            }
            "openAssistantSettings" -> {
                try {
                    val intent = Intent(Settings.ACTION_VOICE_INPUT_SETTINGS).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    try {
                        val fallback = Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        context.startActivity(fallback)
                        result.success(true)
                    } catch (e2: Exception) {
                        result.error("SETTINGS_ERROR", e2.message, null)
                    }
                }
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeActivityResultListener(this)
        activity = null
        activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activity = null
        activityBinding = null
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == REQUEST_CODE_PICK_IMAGE) {
            val pending = pendingPickImageResult
            pendingPickImageResult = null
            if (pending == null) return true

            val uri: Uri? = if (resultCode == Activity.RESULT_OK) data?.data else null
            if (uri == null) {
                pending.success(null)
                return true
            }

            coroutineScope.launch(Dispatchers.IO) {
                try {
                    val bytes = context.contentResolver.openInputStream(uri)?.use { input ->
                        val buffer = ByteArrayOutputStream()
                        val chunk = ByteArray(8192)
                        var read: Int
                        while (input.read(chunk).also { read = it } != -1) {
                            buffer.write(chunk, 0, read)
                        }
                        buffer.toByteArray()
                    }

                    var fileName = "image_${System.currentTimeMillis()}.jpg"
                    try {
                        context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                            val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                            if (nameIdx >= 0 && cursor.moveToFirst()) {
                                val resolvedName = cursor.getString(nameIdx)
                                if (!resolvedName.isNullOrBlank()) {
                                    fileName = resolvedName
                                }
                            }
                        }
                    } catch (e: Exception) {
                        Log.w("FlutterLocalAi", "Could not query display name: ${e.message}")
                    }

                    withContext(Dispatchers.Main) {
                        if (bytes != null && bytes.isNotEmpty()) {
                            pending.success(
                                mapOf(
                                    "bytes" to bytes,
                                    "name" to fileName,
                                    "uri" to uri.toString()
                                )
                            )
                        } else {
                            pending.success(null)
                        }
                    }
                } catch (e: Exception) {
                    Log.e("FlutterLocalAi", "Error reading picked image: ${e.message}", e)
                    withContext(Dispatchers.Main) {
                        pending.success(null)
                    }
                }
            }
            return true
        }
        return false
    }

    private fun prepareBitmap(
        imageBytes: ByteArray?,
        imagePath: String?,
        imageBase64: String?,
        downsample: Boolean
    ): Bitmap? {
        try {
            val rawBitmap: Bitmap = when {
                imageBytes != null && imageBytes.isNotEmpty() -> {
                    BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
                }
                !imagePath.isNullOrBlank() -> {
                    if (imagePath.startsWith("content://") || imagePath.startsWith("file://")) {
                        context.contentResolver.openInputStream(Uri.parse(imagePath))?.use {
                            BitmapFactory.decodeStream(it)
                        }
                    } else {
                        val file = File(imagePath)
                        if (file.exists()) {
                            BitmapFactory.decodeFile(file.absolutePath)
                        } else {
                            null
                        }
                    }
                }
                !imageBase64.isNullOrBlank() -> {
                    val cleanBase64 = imageBase64.substringAfter("base64,", imageBase64).trim()
                    val decoded = Base64.decode(cleanBase64, Base64.DEFAULT)
                    BitmapFactory.decodeByteArray(decoded, 0, decoded.size)
                }
                else -> null
            } ?: return null

            if (downsample && (rawBitmap.width > MAX_DOWNSAMPLE_DIMENSION || rawBitmap.height > MAX_DOWNSAMPLE_DIMENSION)) {
                val scale = MAX_DOWNSAMPLE_DIMENSION.toFloat() / maxOf(rawBitmap.width, rawBitmap.height).toFloat()
                val newW = (rawBitmap.width * scale).toInt().coerceAtLeast(1)
                val newH = (rawBitmap.height * scale).toInt().coerceAtLeast(1)
                return Bitmap.createScaledBitmap(rawBitmap, newW, newH, true)
            }
            return rawBitmap
        } catch (e: Exception) {
            Log.e("FlutterLocalAi", "Error decoding bitmap for vision inference: ${e.message}", e)
            return null
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

            var aicoreInstalled = false
            var aicoreVersion = "Unknown"
            var isBeta = false
            try {
                if (::context.isInitialized) {
                    val packageInfo = context.packageManager.getPackageInfo("com.google.android.aicore", 0)
                    aicoreInstalled = true
                    aicoreVersion = packageInfo.versionName ?: "Unknown"
                    val lowerVersion = aicoreVersion.lowercase()
                    val lowerModelVersion = modelVersion.lowercase()
                    val hasSettingsActivity = Intent("com.google.android.aicore.action.SETTINGS").resolveActivity(context.packageManager) != null
                    isBeta = isBeta ||
                            lowerVersion.contains("rc") ||
                            lowerVersion.contains("preview") ||
                            lowerVersion.contains("beta") ||
                            lowerVersion.contains("dev") ||
                            lowerVersion.contains("canary") ||
                            lowerVersion.contains("test") ||
                            lowerVersion.contains("exp") ||
                            lowerModelVersion.contains("v4") ||
                            lowerModelVersion.contains("preview") ||
                            hasSettingsActivity
                }
            } catch (e: PackageManager.NameNotFoundException) {
                aicoreInstalled = false
                aicoreVersion = "Not Installed"
                isBeta = false
            } catch (e: Exception) {
                Log.w("FlutterLocalAi", "Error inspecting AICore package: ${e.message}")
            }

            mapOf(
                "status" to statusString,
                "version" to modelVersion,
                "aicoreInstalled" to aicoreInstalled.toString(),
                "aicoreVersion" to aicoreVersion,
                "isBeta" to isBeta.toString(),
                "deviceModel" to "${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}",
                "osVersion" to "Android ${android.os.Build.VERSION.RELEASE} (API ${android.os.Build.VERSION.SDK_INT})"
            )
        } catch (e: Exception) {
            android.util.Log.e("FlutterLocalAi", "getModelInfo error: ${e.javaClass.simpleName} - ${e.message}", e)
            mapOf(
                "status" to "Error",
                "version" to (e.message ?: "Unknown error"),
                "aicoreInstalled" to "false",
                "aicoreVersion" to "Unknown",
                "isBeta" to "false",
                "deviceModel" to "${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}",
                "osVersion" to "Android ${android.os.Build.VERSION.RELEASE} (API ${android.os.Build.VERSION.SDK_INT})"
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
        val imageBytes = payload["imageBytes"] as? ByteArray
        val imagePath = payload["imagePath"] as? String
        val imageBase64 = payload["imageBase64"] as? String
        val downsample = (payload["downsample"] as? Boolean) ?: true

        activeStreamJob?.cancel()
        activeStreamJob = coroutineScope.launch {
            try {
                withContext(Dispatchers.Main) {
                    if (isActive) {
                        events.success(mapOf("status" to "Loading", "response" to null, "error" to null))
                    }
                }
                val response = generateTextAsync(
                    prompt = prompt,
                    configMap = configMap,
                    imageBytes = imageBytes,
                    imagePath = imagePath,
                    imageBase64 = imageBase64,
                    downsample = downsample
                )
                withContext(Dispatchers.Main) {
                    if (isActive) {
                        events.success(
                            mapOf(
                                "status" to "Done",
                                "response" to response,
                                "error" to null,
                                "reason" to response["reason"]
                            )
                        )
                        events.endOfStream()
                    }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    events.success(mapOf("status" to "Error", "response" to null, "error" to e.message))
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
        val imageBytes = payload["imageBytes"] as? ByteArray
        val imagePath = payload["imagePath"] as? String
        val imageBase64 = payload["imageBase64"] as? String
        val downsample = (payload["downsample"] as? Boolean) ?: true

        activeStreamJob?.cancel()
        var lastFinishReason: String? = null
        var streamFailed = false
        activeStreamJob = coroutineScope.launch {
            try {
                withContext(Dispatchers.Main) {
                    if (isActive) {
                        events.success(mapOf("status" to "Loading", "response" to null, "error" to null))
                    }
                }

                val bitmap = withContext(Dispatchers.IO) {
                    prepareBitmap(imageBytes, imagePath, imageBase64, downsample)
                }

                generateTextStreamFlow(prompt, configMap, bitmap)
                    .onEach { chunkMap ->
                        val reasonFromChunk = chunkMap["reason"] as? String
                        if (!reasonFromChunk.isNullOrBlank() &&
                            reasonFromChunk != "null" &&
                            reasonFromChunk != "UNKNOWN"
                        ) {
                            lastFinishReason = reasonFromChunk
                        }
                        withContext(Dispatchers.Main) {
                            if (isActive) {
                                events.success(mapOf("status" to "Streaming", "response" to chunkMap, "error" to null))
                            }
                        }
                    }
                    .catch { e ->
                        if (e is CancellationException) throw e
                        streamFailed = true
                        withContext(Dispatchers.Main) {
                            events.success(mapOf("status" to "Error", "response" to null, "error" to e.message))
                            events.endOfStream()
                        }
                    }
                    .onCompletion { cause ->
                        if (cause == null && !streamFailed && isActive) {
                            withContext(Dispatchers.Main) {
                                events.success(
                                    mapOf(
                                        "status" to "Done",
                                        "response" to null,
                                        "error" to null,
                                        "reason" to lastFinishReason
                                    )
                                )
                                events.endOfStream()
                            }
                        }
                    }
                    .collect { }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (!streamFailed) {
                    withContext(Dispatchers.Main) {
                        events.success(mapOf("status" to "Error", "response" to null, "error" to e.message))
                        events.endOfStream()
                    }
                }
            }
        }
    }

    override fun onCancel(arguments: Any?) {
        activeStreamJob?.cancel()
        activeStreamJob = null
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
        configMap: Map<String, Any>?,
        imageBytes: ByteArray? = null,
        imagePath: String? = null,
        imageBase64: String? = null,
        downsample: Boolean = true
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
            val bitmap = prepareBitmap(imageBytes, imagePath, imageBase64, downsample)

            val request = if (bitmap != null) {
                generateContentRequest(ImagePart(bitmap), TextPart(fullPrompt)) {
                    maxOutputTokens = maxOutputTokensValue
                    temperature = temperatureValue
                }
            } else {
                generateContentRequest(TextPart(fullPrompt)) {
                    maxOutputTokens = maxOutputTokensValue
                    temperature = temperatureValue
                }
            }
            val startTime = System.currentTimeMillis()
            val response: GenerateContentResponse = generativeModel!!.generateContent(request)
            val generationTime = System.currentTimeMillis() - startTime
            val generatedText = response.candidates.firstOrNull()?.text ?: ""
            val finishReason = response.candidates.firstOrNull()?.finishReason?.toString()
            val tokenCount = generatedText.split(" ").filter { it.isNotEmpty() }.size
            val resultMap = mutableMapOf<String, Any>(
                "text" to generatedText,
                "generationTimeMs" to generationTime,
                "tokenCount" to tokenCount
            )
            if (!finishReason.isNullOrBlank() && finishReason != "null") {
                resultMap["reason"] = finishReason
            }
            resultMap
        } catch (e: CancellationException) {
            throw e
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

    private fun generateTextStreamFlow(
        prompt: String,
        configMap: Map<String, Any>?,
        bitmap: Bitmap? = null
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
        val request = if (bitmap != null) {
            generateContentRequest(ImagePart(bitmap), TextPart(fullPrompt)) {
                maxOutputTokens = maxOutputTokensValue
                temperature = temperatureValue
                candidateCount = candidateCountValue
            }
        } else {
            generateContentRequest(TextPart(fullPrompt)) {
                maxOutputTokens = maxOutputTokensValue
                temperature = temperatureValue
                candidateCount = candidateCountValue
            }
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
                if (e is CancellationException) throw e
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

    private fun openAICoreBetaProgram() {
        if (!::context.isInitialized) {
            throw Exception("Context not initialized")
        }

        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/apps/testing/com.google.android.aicore")).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        if (intent.resolveActivity(context.packageManager) != null) {
            context.startActivity(intent)
        } else {
            try {
                context.startActivity(intent)
            } catch (e: Exception) {
                throw Exception("Could not open AICore beta program: ${e.message}")
            }
        }
    }

    private fun openAICoreDevSettings() {
        if (!::context.isInitialized) {
            throw Exception("Context not initialized")
        }

        try {
            val aiCoreSettingsIntent = Intent("com.google.android.aicore.action.SETTINGS").apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(aiCoreSettingsIntent)
            return
        } catch (e: Exception) {
            Log.w("FlutterLocalAi", "Could not start AICore settings activity directly: ${e.message}")
        }

        try {
            val devSettingsIntent = Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(devSettingsIntent)
            return
        } catch (e: Exception) {
            Log.w("FlutterLocalAi", "Could not start Developer Options: ${e.message}")
        }

        try {
            val appDetailsIntent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", "com.google.android.aicore", null)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(appDetailsIntent)
        } catch (e: Exception) {
            throw Exception("Could not open AICore settings or fallback settings: ${e.message}")
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
