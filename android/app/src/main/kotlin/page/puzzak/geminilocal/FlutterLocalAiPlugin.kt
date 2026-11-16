package page.puzzak.geminilocal

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.provider.Settings
import android.util.Base64
import android.util.Log
import com.google.mlkit.genai.common.DownloadStatus
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.common.StreamingCallback
import com.google.mlkit.genai.prompt.GenerateContentResponse
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
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger
import kotlin.coroutines.coroutineContext
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
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
        private const val AICORE_PACKAGE = "com.google.android.aicore"
        private const val AICORE_SETTINGS_ACTIVITY = "com.google.android.apps.aicore.app.settings.AiCoreSettingsActivity"
        private const val ACTION_IA_SETTINGS = "com.android.settings.action.IA_SETTINGS"
        private const val ACTION_LEGACY_AICORE_SETTINGS = "com.google.android.aicore.action.SETTINGS"
        private const val AICORE_DEV_TILE_KEY =
            "dashboard_tile_pref_com.google.android.apps.aicore.app.settings.AiCoreSettingsActivity"

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
    private var requestedReleaseStage: String? = null
    private var requestedPreference: String? = null
    private var requestedEnableThinking: Boolean? = null
    private var lastObservedPrefStage: String? = null
    private var lastObservedPrefPreference: String? = null
    private var lastObservedPrefThinking: Boolean? = null
    private var activeResolvedClient: PaiosModelHelper.ResolvedModelClient? = null
    private val clientLock = Any()
    private val activeGenerationCount = AtomicInteger(0)
    private var instructions: String? = null
    private val coroutineScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private var activeStreamJob: Job? = null
    private val variantDownloadJobs = ConcurrentHashMap<String, Job>()
    private val variantDownloadOutcomes = ConcurrentHashMap<String, VariantDownloadOutcome>()
    private val downloadJobsLock = Any()
    @Volatile
    private var downloadEventSink: EventChannel.EventSink? = null
    private lateinit var context: Context
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPickImageResult: Result? = null

    private data class VariantDownloadOutcome(
        val downloadedBytes: Long = 0L,
        val bytesToDownload: Long = 0L,
        val error: String? = null
    )

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
                    downloadEventSink = events

                    val triggerInit = (arguments as? Map<*, *>)?.get("triggerInit") as? Boolean ?: true
                    if (!triggerInit) return

                    downloadScope?.cancel()
                    downloadScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
                    downloadScope?.launch {
                        initAiCoreFlow()
                            .catch { e -> events.error("FlowError", e.message, null) }
                            .collect { statusEvent ->
                                events.success(statusEvent)
                            }
                    }
                }
                override fun onCancel(arguments: Any?) {
                    downloadEventSink = null
                    downloadScope?.cancel()
                    downloadScope = null
                }
            }
        )
    }

    private fun resolveRequestedStage(explicitStage: String? = null): String {
        val prefStage = if (::context.isInitialized) {
            PaiosModelHelper.getModelReleaseStage(context)
        } else {
            PaiosModelHelper.STAGE_STABLE
        }
        if (explicitStage != null) {
            val normalized = PaiosModelHelper.normalizeReleaseStage(explicitStage)
            requestedReleaseStage = normalized
            lastObservedPrefStage = prefStage
            return normalized
        }
        if (requestedReleaseStage == null || lastObservedPrefStage != prefStage) {
            lastObservedPrefStage = prefStage
            requestedReleaseStage = prefStage
        }
        return requestedReleaseStage ?: prefStage
    }

    private fun resolveRequestedPreference(explicitPreference: String? = null): String {
        val prefPreference = if (::context.isInitialized) {
            PaiosModelHelper.getModelPreference(context)
        } else {
            PaiosModelHelper.PREF_FULL
        }
        if (explicitPreference != null) {
            val normalized = PaiosModelHelper.normalizePreference(explicitPreference)
            requestedPreference = normalized
            lastObservedPrefPreference = prefPreference
            return normalized
        }
        if (requestedPreference == null || lastObservedPrefPreference != prefPreference) {
            lastObservedPrefPreference = prefPreference
            requestedPreference = prefPreference
        }
        return requestedPreference ?: prefPreference
    }

    private fun resolveRequestedEnableThinking(explicitThinking: Boolean? = null): Boolean {
        val prefThinking = if (::context.isInitialized) {
            PaiosModelHelper.getEnableThinking(context, defaultValue = false)
        } else {
            false
        }
        if (explicitThinking != null) {
            requestedEnableThinking = explicitThinking
            lastObservedPrefThinking = prefThinking
            return explicitThinking
        }
        if (requestedEnableThinking == null || lastObservedPrefThinking != prefThinking) {
            lastObservedPrefThinking = prefThinking
            requestedEnableThinking = prefThinking
        }
        return requestedEnableThinking ?: prefThinking
    }

    private fun replaceActiveClient(newClient: PaiosModelHelper.ResolvedModelClient) {
        val oldModel = synchronized(clientLock) {
            val previous = activeResolvedClient?.model
            activeResolvedClient = newClient
            if (previous !== newClient.model && activeGenerationCount.get() <= 0) previous else null
        }
        if (oldModel != null) {
            runCatching { oldModel.close() }
        }
    }

    private suspend fun ensureClient(
        stage: String,
        preference: String,
        allowDownloadable: Boolean,
        forceRefresh: Boolean = false
    ): PaiosModelHelper.ResolvedModelClient {
        val existing = synchronized(clientLock) { activeResolvedClient }
        if (!forceRefresh &&
            existing != null &&
            existing.requestedStage == stage &&
            existing.requestedPreference == preference &&
            existing.statusCode == FeatureStatus.AVAILABLE
        ) {
            return existing
        }
        val resolved = PaiosModelHelper.resolveClient(
            requestedStage = stage,
            requestedPreference = preference,
            allowDownloadable = allowDownloadable
        )
        replaceActiveClient(resolved)
        return resolved
    }

    private fun variantKey(stage: String, preference: String): String =
        "${PaiosModelHelper.normalizeReleaseStage(stage)}:${PaiosModelHelper.normalizePreference(preference)}"

    private fun peekRequestedStage(explicitStage: String? = null): String {
        if (explicitStage != null) {
            return PaiosModelHelper.normalizeReleaseStage(explicitStage)
        }
        val prefStage = if (::context.isInitialized) {
            PaiosModelHelper.getModelReleaseStage(context)
        } else {
            PaiosModelHelper.STAGE_STABLE
        }
        return requestedReleaseStage ?: prefStage
    }

    private fun peekRequestedPreference(explicitPreference: String? = null): String {
        if (explicitPreference != null) {
            return PaiosModelHelper.normalizePreference(explicitPreference)
        }
        val prefPreference = if (::context.isInitialized) {
            PaiosModelHelper.getModelPreference(context)
        } else {
            PaiosModelHelper.PREF_FULL
        }
        return requestedPreference ?: prefPreference
    }

    private suspend fun emitDownloadEvent(event: Any) {
        val sink = downloadEventSink ?: return
        withContext(Dispatchers.Main) {
            runCatching { sink.success(event) }
        }
    }

    private fun startOrGetVariantDownloadJob(
        stage: String,
        preference: String
    ): Pair<Job, Boolean> {
        val normStage = PaiosModelHelper.normalizeReleaseStage(stage)
        val normPref = PaiosModelHelper.normalizePreference(preference)
        val key = variantKey(normStage, normPref)

        synchronized(downloadJobsLock) {
            val existing = variantDownloadJobs[key]
            if (existing != null && existing.isActive) {
                return existing to false
            }

            variantDownloadOutcomes.remove(key)
            val job = coroutineScope.launch(Dispatchers.IO) {
                val currentJob = coroutineContext[Job]
                val model = PaiosModelHelper.buildClient(normStage, normPref)
                var knownTotalBytes = 0L
                var lastDownloadedBytes = 0L
                var downloadError: String? = null

                try {
                    val statusCode = runCatching { model.checkStatus() }
                        .getOrDefault(FeatureStatus.UNAVAILABLE)
                    when (statusCode) {
                        FeatureStatus.AVAILABLE -> {
                            emitDownloadEvent(
                                mapOf(
                                    "status" to "completed",
                                    "variantKey" to key,
                                    "releaseStage" to normStage,
                                    "preference" to normPref,
                                    "bytes" to 0L,
                                    "bytesToDownload" to 0L
                                )
                            )
                            variantDownloadOutcomes[key] = VariantDownloadOutcome()
                            return@launch
                        }
                        FeatureStatus.UNAVAILABLE -> {
                            val msg = "Model variant $key is unavailable"
                            downloadError = msg
                            emitDownloadEvent(
                                mapOf(
                                    "status" to "failed",
                                    "variantKey" to key,
                                    "releaseStage" to normStage,
                                    "preference" to normPref,
                                    "error" to msg
                                )
                            )
                            variantDownloadOutcomes[key] = VariantDownloadOutcome(error = msg)
                            return@launch
                        }
                    }

                    model.download().collect { downloadStatus ->
                        when (downloadStatus) {
                            is DownloadStatus.DownloadStarted -> {
                                knownTotalBytes = runCatching { downloadStatus.bytesToDownload }
                                    .getOrDefault(0L)
                                    .coerceAtLeast(0L)
                                emitDownloadEvent(
                                    mapOf(
                                        "status" to "started",
                                        "variantKey" to key,
                                        "releaseStage" to normStage,
                                        "preference" to normPref,
                                        "bytes" to 0L,
                                        "bytesToDownload" to knownTotalBytes
                                    )
                                )
                            }
                            is DownloadStatus.DownloadProgress -> {
                                lastDownloadedBytes = downloadStatus.totalBytesDownloaded.coerceAtLeast(0L)
                                emitDownloadEvent(
                                    mapOf(
                                        "status" to "downloading",
                                        "variantKey" to key,
                                        "releaseStage" to normStage,
                                        "preference" to normPref,
                                        "bytes" to lastDownloadedBytes,
                                        "bytesToDownload" to knownTotalBytes
                                    )
                                )
                            }
                            is DownloadStatus.DownloadCompleted -> {
                                val completedBytes = if (knownTotalBytes > 0L) knownTotalBytes else lastDownloadedBytes
                                emitDownloadEvent(
                                    mapOf(
                                        "status" to "completed",
                                        "variantKey" to key,
                                        "releaseStage" to normStage,
                                        "preference" to normPref,
                                        "bytes" to completedBytes,
                                        "bytesToDownload" to knownTotalBytes
                                    )
                                )
                            }
                            is DownloadStatus.DownloadFailed -> {
                                val msg = downloadStatus.e.message ?: "Download failed"
                                downloadError = msg
                                emitDownloadEvent(
                                    mapOf(
                                        "status" to "failed",
                                        "variantKey" to key,
                                        "releaseStage" to normStage,
                                        "preference" to normPref,
                                        "error" to msg
                                    )
                                )
                            }
                        }
                    }
                    val finalBytes = if (lastDownloadedBytes > 0L) lastDownloadedBytes else knownTotalBytes
                    variantDownloadOutcomes[key] = VariantDownloadOutcome(
                        downloadedBytes = finalBytes,
                        bytesToDownload = knownTotalBytes,
                        error = downloadError
                    )
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    val msg = e.message ?: "Download failed"
                    downloadError = msg
                    variantDownloadOutcomes[key] = VariantDownloadOutcome(
                        downloadedBytes = lastDownloadedBytes,
                        bytesToDownload = knownTotalBytes,
                        error = msg
                    )
                    emitDownloadEvent(
                        mapOf(
                            "status" to "failed",
                            "variantKey" to key,
                            "releaseStage" to normStage,
                            "preference" to normPref,
                            "error" to msg
                        )
                    )
                } finally {
                    runCatching { model.close() }
                    if (currentJob != null) {
                        variantDownloadJobs.remove(key, currentJob)
                    } else {
                        variantDownloadJobs.remove(key)
                    }
                }
            }
            variantDownloadJobs[key] = job
            return job to true
        }
    }

    private fun initAiCoreFlow(): Flow<Any> = flow {
        try {
            val resolved = ensureClient(
                stage = resolveRequestedStage(),
                preference = resolveRequestedPreference(),
                allowDownloadable = true,
                forceRefresh = true
            )
            val activeStage = resolved.activeStage
            val activePref = resolved.activePreference
            val key = variantKey(activeStage, activePref)
            when (resolved.statusCode) {
                FeatureStatus.AVAILABLE -> emit("Available=Available=0")
                FeatureStatus.UNAVAILABLE -> emit("Error=AICore=Unavailable")
                FeatureStatus.DOWNLOADING,
                FeatureStatus.DOWNLOADABLE -> {
                    emit("Download=downloading_model=0")
                    var knownTotalBytes = 0L
                    var lastDownloadedBytes = 0L

                    resolved.model.download().collect { downloadStatus ->
                        when (downloadStatus) {
                            is DownloadStatus.DownloadStarted -> {
                                knownTotalBytes = runCatching { downloadStatus.bytesToDownload }
                                    .getOrDefault(0L)
                                    .coerceAtLeast(0L)
                                emit(
                                    mapOf(
                                        "status" to "started",
                                        "variantKey" to key,
                                        "releaseStage" to activeStage,
                                        "preference" to activePref,
                                        "bytes" to 0L,
                                        "bytesToDownload" to knownTotalBytes
                                    )
                                )
                                emit("Download=downloading_model=0")
                            }
                            is DownloadStatus.DownloadProgress -> {
                                lastDownloadedBytes = downloadStatus.totalBytesDownloaded.coerceAtLeast(0L)
                                emit(
                                    mapOf(
                                        "status" to "downloading",
                                        "variantKey" to key,
                                        "releaseStage" to activeStage,
                                        "preference" to activePref,
                                        "bytes" to lastDownloadedBytes,
                                        "bytesToDownload" to knownTotalBytes
                                    )
                                )
                                emit("Download=downloading_model=$lastDownloadedBytes")
                            }
                            is DownloadStatus.DownloadCompleted -> {
                                val completedBytes = if (knownTotalBytes > 0L) knownTotalBytes else lastDownloadedBytes
                                emit(
                                    mapOf(
                                        "status" to "completed",
                                        "variantKey" to key,
                                        "releaseStage" to activeStage,
                                        "preference" to activePref,
                                        "bytes" to completedBytes,
                                        "bytesToDownload" to knownTotalBytes
                                    )
                                )
                                emit("Available=Download=0")
                            }
                            is DownloadStatus.DownloadFailed -> {
                                val msg = downloadStatus.e.message ?: "Download failed"
                                emit(
                                    mapOf(
                                        "status" to "failed",
                                        "variantKey" to key,
                                        "releaseStage" to activeStage,
                                        "preference" to activePref,
                                        "error" to msg
                                    )
                                )
                                emit("Error=Download=$msg")
                            }
                        }
                    }
                }
                else -> emit("Error=Unknown=${resolved.statusCode}")
            }
        } catch (e: Exception) {
            emit("Error=Unknown=${e.message}")
        }
    }.flowOn(Dispatchers.IO)

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getModelInfo" -> {
                val argStage = call.argument<String>("releaseStage")
                val argPref = call.argument<String>("preference")
                val argThinking = call.argument<Boolean>("enableThinking")
                coroutineScope.launch {
                    try {
                        val stage = resolveRequestedStage(argStage)
                        val pref = resolveRequestedPreference(argPref)
                        resolveRequestedEnableThinking(argThinking)
                        val info = getModelInfo(stage, pref)
                        result.success(info)
                    } catch (e: Exception) {
                        result.error("GET_MODEL_INFO_ERROR", e.message, null)
                    }
                }
            }
            "initAiCore" -> {
                if (call.hasArgument("instructions")) {
                    instructions = call.argument("instructions")
                }
                val argStage = call.argument<String>("releaseStage")
                val argPref = call.argument<String>("preference")
                val argThinking = call.argument<Boolean>("enableThinking")
                coroutineScope.launch {
                    try {
                        val stage = resolveRequestedStage(argStage)
                        val pref = resolveRequestedPreference(argPref)
                        resolveRequestedEnableThinking(argThinking)
                        val resolved = withContext(Dispatchers.IO) {
                            ensureClient(stage, pref, allowDownloadable = true, forceRefresh = true)
                        }
                        result.success(buildFullModelStatusMap(resolved, logContext = "initAiCore"))
                    } catch (e: Exception) {
                        result.error("INIT_ERROR", e.message, null)
                    }
                }
            }
            "init" -> {
                instructions = call.argument("instructions")
                val argStage = call.argument<String>("releaseStage")
                val argPref = call.argument<String>("preference")
                val argThinking = call.argument<Boolean>("enableThinking")
                coroutineScope.launch {
                    try {
                        val stage = resolveRequestedStage(argStage)
                        val pref = resolveRequestedPreference(argPref)
                        resolveRequestedEnableThinking(argThinking)
                        val available = initAiCore(stage, pref)
                        result.success(available)
                    } catch (e: Exception) {
                        result.error("INIT_ERROR", e.message, null)
                    }
                }
            }
            "switchModelConfig" -> {
                if (activeGenerationCount.get() > 0) {
                    result.error("BUSY", "Cannot switch model while generation is active", null)
                    return
                }
                val argStage = call.argument<String>("releaseStage")
                val argPref = call.argument<String>("preference")
                val argThinking = call.argument<Boolean>("enableThinking")
                coroutineScope.launch {
                    if (activeGenerationCount.get() > 0) {
                        result.error("BUSY", "Cannot switch model while generation is active", null)
                        return@launch
                    }
                    try {
                        val stage = resolveRequestedStage(argStage)
                        val pref = resolveRequestedPreference(argPref)
                        resolveRequestedEnableThinking(argThinking)
                        val resolved = withContext(Dispatchers.IO) {
                            ensureClient(stage, pref, allowDownloadable = true, forceRefresh = true)
                        }
                        result.success(buildFullModelStatusMap(resolved, logContext = "switchModelConfig"))
                    } catch (e: Exception) {
                        result.error("SWITCH_MODEL_CONFIG_ERROR", e.message, null)
                    }
                }
            }
            "downloadModel" -> {
                val argStage = call.argument<String>("releaseStage")
                val argPref = call.argument<String>("preference")
                coroutineScope.launch {
                    try {
                        val stage = peekRequestedStage(argStage)
                        val pref = peekRequestedPreference(argPref)
                        val info = downloadModel(stage, pref)
                        result.success(info)
                    } catch (e: Exception) {
                        result.error("DOWNLOAD_MODEL_ERROR", e.message, null)
                    }
                }
            }
            "downloadVariant" -> {
                val stage = peekRequestedStage(call.argument<String>("releaseStage"))
                val pref = peekRequestedPreference(call.argument<String>("preference"))
                val key = variantKey(stage, pref)
                val (_, startedNow) = startOrGetVariantDownloadJob(stage, pref)
                result.success(
                    mapOf(
                        "started" to startedNow,
                        "alreadyDownloading" to !startedNow,
                        "variantKey" to key,
                        "releaseStage" to stage,
                        "preference" to pref
                    )
                )
            }
            "cancelVariantDownload" -> {
                val explicitKey = call.argument<String>("variantKey")?.trim()?.takeIf { it.isNotEmpty() }
                val stage = peekRequestedStage(call.argument<String>("releaseStage"))
                val pref = peekRequestedPreference(call.argument<String>("preference"))
                val key = explicitKey ?: variantKey(stage, pref)
                val job = variantDownloadJobs.remove(key)
                val wasActive = job?.isActive == true
                job?.cancel()
                result.success(
                    mapOf(
                        "cancelled" to wasActive,
                        "variantKey" to key
                    )
                )
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
            "generateInternalInference" -> {
                val prompt = call.argument<String>("prompt")
                if (prompt.isNullOrBlank()) {
                    result.error("INVALID_ARG", "Prompt is required", null)
                    return
                }
                val oneShotInstructions = call.argument<String>("instructions")
                val imageBytes = call.argument<ByteArray>("imageBytes")
                val rawMaxTokens = call.argument<Number>("maxTokens")?.toInt() ?: 192
                val clampedMaxTokens = rawMaxTokens.coerceIn(1, 256)
                val temperatureValue = call.argument<Number>("temperature")?.toFloat() ?: 0.2f

                coroutineScope.launch {
                    try {
                        val output = generateInternalInferenceAsync(
                            prompt = prompt,
                            oneShotInstructions = oneShotInstructions,
                            imageBytes = imageBytes,
                            maxTokens = clampedMaxTokens,
                            temperature = temperatureValue
                        )
                        result.success(output)
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        result.error(
                            "INTERNAL_INFERENCE_ERROR",
                            e.message ?: "Internal inference failed",
                            null
                        )
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

    private fun buildDirectAiCoreSettingsIntent(): Intent =
        Intent(ACTION_IA_SETTINGS).apply {
            component = ComponentName(AICORE_PACKAGE, AICORE_SETTINGS_ACTIVITY)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

    private fun buildModelStatusMap(
        resolved: PaiosModelHelper.ResolvedModelClient,
        comboStatuses: PaiosModelHelper.ComboStatuses? = null,
        extraFields: Map<String, Any?> = emptyMap()
    ): Map<String, Any?> {
        var aicoreInstalled = false
        var aicoreVersion = "Unknown"
        var isBeta = resolved.activeStage == PaiosModelHelper.STAGE_PREVIEW || resolved.capabilities.isNanoV4
        try {
            if (::context.isInitialized) {
                val packageInfo = context.packageManager.getPackageInfo(AICORE_PACKAGE, 0)
                aicoreInstalled = true
                aicoreVersion = packageInfo.versionName ?: "Unknown"
                val lowerVersion = aicoreVersion.lowercase()
                val lowerModelVersion = resolved.capabilities.baseModelName.lowercase()
                val hasSettingsActivity =
                    buildDirectAiCoreSettingsIntent().resolveActivity(context.packageManager) != null ||
                        Intent(ACTION_LEGACY_AICORE_SETTINGS).resolveActivity(context.packageManager) != null
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
        } catch (_: PackageManager.NameNotFoundException) {
            aicoreInstalled = false
            aicoreVersion = "Not Installed"
        } catch (e: Exception) {
            Log.w("FlutterLocalAi", "Error inspecting AICore package: ${e.message}")
        }

        val exposedBaseModelName: String? = resolved.capabilities.baseModelName
            .trim()
            .takeIf { it.isNotEmpty() && !it.equals("Unknown", ignoreCase = true) }

        val stableFastAvailable = comboStatuses?.stableFastAvailable ?: false
        val previewAvailable = comboStatuses?.previewAvailable ?: false
        val previewFastAvailable = comboStatuses?.previewFastAvailable ?: false
        val previewFullAvailable = comboStatuses?.previewFullAvailable ?: false
        val fastAvailable = comboStatuses?.isFastAvailableFor(resolved.activeStage) ?: false
        val variantStatuses = comboStatuses ?: PaiosModelHelper.ComboStatuses(
            stableFullStatus = if (resolved.activeStage == PaiosModelHelper.STAGE_STABLE && resolved.activePreference == PaiosModelHelper.PREF_FULL) resolved.statusCode else FeatureStatus.UNAVAILABLE,
            stableFastStatus = if (resolved.activeStage == PaiosModelHelper.STAGE_STABLE && resolved.activePreference == PaiosModelHelper.PREF_FAST) resolved.statusCode else FeatureStatus.UNAVAILABLE,
            previewFullStatus = if (resolved.activeStage == PaiosModelHelper.STAGE_PREVIEW && resolved.activePreference == PaiosModelHelper.PREF_FULL) resolved.statusCode else FeatureStatus.UNAVAILABLE,
            previewFastStatus = if (resolved.activeStage == PaiosModelHelper.STAGE_PREVIEW && resolved.activePreference == PaiosModelHelper.PREF_FAST) resolved.statusCode else FeatureStatus.UNAVAILABLE
        )
        val variantInfoList = variantStatuses.toVariantList(
            activeStage = resolved.activeStage,
            activePreference = resolved.activePreference,
            activeBaseModelName = exposedBaseModelName
        )
        val modelVariants = variantInfoList.map { it.toMap() }
        val hasAnySupportedModel = variantStatuses.hasAnySupportedModel
        val hasAnyAvailableModel = variantStatuses.hasAnyAvailableModel

        val map = mutableMapOf<String, Any?>(
            "available" to (resolved.statusCode == FeatureStatus.AVAILABLE),
            "status" to PaiosModelHelper.statusCodeToString(resolved.statusCode),
            "statusCode" to resolved.statusCode,
            "version" to exposedBaseModelName,
            "baseModelName" to exposedBaseModelName,
            "isBeta" to isBeta,
            "releaseStage" to resolved.activeStage,
            "preference" to resolved.activePreference,
            "requestedReleaseStage" to resolved.requestedStage,
            "requestedPreference" to resolved.requestedPreference,
            "fellBackToStable" to resolved.fellBackToStable,
            "stableFastAvailable" to stableFastAvailable,
            "previewAvailable" to previewAvailable,
            "previewFastAvailable" to previewFastAvailable,
            "previewFullAvailable" to previewFullAvailable,
            "fastAvailable" to fastAvailable,
            "hasAnySupportedModel" to hasAnySupportedModel,
            "hasAnyAvailableModel" to hasAnyAvailableModel,
            "modelVariants" to modelVariants,
            "isSystemPromptAvailable" to resolved.capabilities.isSystemPromptAvailable,
            "isThinkingModeAvailable" to resolved.capabilities.isThinkingModeAvailable,
            "isCachingAvailable" to resolved.capabilities.isCachingAvailable,
            "isNanoV4" to resolved.capabilities.isNanoV4,
            "tokenLimit" to resolved.capabilities.tokenLimit,
            "availableFeatures" to resolved.capabilities.availableFeatures,
            "aicoreInstalled" to aicoreInstalled,
            "aicoreVersion" to aicoreVersion,
            "deviceModel" to "${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}",
            "osVersion" to "Android ${android.os.Build.VERSION.RELEASE} (API ${android.os.Build.VERSION.SDK_INT})"
        )
        map.putAll(extraFields)
        return map
    }

    private suspend fun buildFullModelStatusMap(
        resolved: PaiosModelHelper.ResolvedModelClient,
        extraFields: Map<String, Any?> = emptyMap(),
        logContext: String? = null
    ): Map<String, Any?> = withContext(Dispatchers.IO) {
        val combos = PaiosModelHelper.probeAllComboStatuses(resolved)
        if (logContext != null) {
            Log.i(
                "FlutterLocalAi",
                "$logContext: activeStage=${resolved.activeStage}, activePreference=${resolved.activePreference}, " +
                    "requested=${resolved.requestedStage}/${resolved.requestedPreference}, " +
                    "fellBackToStable=${resolved.fellBackToStable}, " +
                    "statusCode=${resolved.statusCode} (${PaiosModelHelper.statusCodeToString(resolved.statusCode)}), " +
                    "baseModelName=${resolved.capabilities.baseModelName}, " +
                    "isThinkingModeAvailable=${resolved.capabilities.isThinkingModeAvailable}, " +
                    "isSystemPromptAvailable=${resolved.capabilities.isSystemPromptAvailable}, " +
                    "combos=[stableFull=${combos.stableFullStatus}, stableFast=${combos.stableFastStatus}, " +
                    "previewFull=${combos.previewFullStatus}, previewFast=${combos.previewFastStatus}]"
            )
        }
        buildModelStatusMap(resolved, combos, extraFields)
    }

    private suspend fun getModelInfo(
        stage: String = resolveRequestedStage(),
        preference: String = resolveRequestedPreference()
    ): Map<String, Any?> = withContext(Dispatchers.IO) {
        try {
            val resolved = ensureClient(
                stage = stage,
                preference = preference,
                allowDownloadable = true,
                forceRefresh = true
            )
            buildFullModelStatusMap(resolved, logContext = "getModelInfo")
        } catch (e: Exception) {
            Log.e("FlutterLocalAi", "getModelInfo error: ${e.javaClass.simpleName} - ${e.message}", e)
            mapOf(
                "available" to false,
                "status" to "unavailable",
                "statusCode" to FeatureStatus.UNAVAILABLE,
                "version" to null,
                "baseModelName" to null,
                "isBeta" to false,
                "releaseStage" to stage,
                "preference" to preference,
                "requestedReleaseStage" to stage,
                "requestedPreference" to preference,
                "fellBackToStable" to false,
                "stableFastAvailable" to false,
                "previewAvailable" to false,
                "previewFastAvailable" to false,
                "previewFullAvailable" to false,
                "fastAvailable" to false,
                "hasAnySupportedModel" to false,
                "hasAnyAvailableModel" to false,
                "modelVariants" to PaiosModelHelper.ComboStatuses(
                    stableFullStatus = FeatureStatus.UNAVAILABLE,
                    stableFastStatus = FeatureStatus.UNAVAILABLE,
                    previewFullStatus = FeatureStatus.UNAVAILABLE,
                    previewFastStatus = FeatureStatus.UNAVAILABLE
                ).toVariantList().map { it.toMap() },
                "isSystemPromptAvailable" to false,
                "isThinkingModeAvailable" to false,
                "isCachingAvailable" to false,
                "isNanoV4" to false,
                "tokenLimit" to 0,
                "aicoreInstalled" to false,
                "aicoreVersion" to "Unknown",
                "deviceModel" to "${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}",
                "osVersion" to "Android ${android.os.Build.VERSION.RELEASE} (API ${android.os.Build.VERSION.SDK_INT})"
            )
        }
    }

    private suspend fun downloadModel(
        stage: String,
        preference: String
    ): Map<String, Any?> = withContext(Dispatchers.IO) {
        val normStage = PaiosModelHelper.normalizeReleaseStage(stage)
        val normPref = PaiosModelHelper.normalizePreference(preference)
        val key = variantKey(normStage, normPref)
        val currentActive = synchronized(clientLock) { activeResolvedClient }
        val matchesActive = currentActive == null ||
            (currentActive.activeStage == normStage && currentActive.activePreference == normPref)

        if (currentActive != null &&
            matchesActive &&
            currentActive.statusCode == FeatureStatus.AVAILABLE
        ) {
            return@withContext buildFullModelStatusMap(currentActive, logContext = "downloadModel")
        }

        val (job, _) = startOrGetVariantDownloadJob(normStage, normPref)
        job.join()

        val outcome = variantDownloadOutcomes[key] ?: VariantDownloadOutcome()
        val extras = mutableMapOf<String, Any?>(
            "downloadedBytes" to outcome.downloadedBytes,
            "bytesToDownload" to outcome.bytesToDownload,
            "variantKey" to key
        )
        outcome.error?.let { extras["downloadError"] = it }

        val activeAfter = synchronized(clientLock) { activeResolvedClient }
        val shouldRefreshActive = activeAfter == null ||
            (activeAfter.activeStage == normStage && activeAfter.activePreference == normPref)

        if (shouldRefreshActive) {
            val refreshed = ensureClient(
                stage = normStage,
                preference = normPref,
                allowDownloadable = true,
                forceRefresh = true
            )
            return@withContext buildFullModelStatusMap(refreshed, extras, logContext = "downloadModel")
        }

        buildFullModelStatusMap(activeAfter, extras, logContext = "downloadModel")
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        if (events == null) return

        val args = arguments as? Map<*, *>
        val method = args?.get("method") as? String
        val payload = args?.get("payload") as? Map<*, *>

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

    private fun handleGenerateText(payload: Map<*, *>, events: EventChannel.EventSink) {
        val prompt = payload["prompt"] as? String
        if (prompt == null) {
            events.error("INVALID_ARG", "Prompt is required", null)
            return
        }
        val configMap = payload["config"] as? Map<*, *>
        val imageBytes = payload["imageBytes"] as? ByteArray
        val imagePath = payload["imagePath"] as? String
        val imageBase64 = payload["imageBase64"] as? String
        val downsample = (payload["downsample"] as? Boolean) ?: true
        val stage = resolveRequestedStage(
            (payload["releaseStage"] as? String) ?: (configMap?.get("releaseStage") as? String)
        )
        val preference = resolveRequestedPreference(
            (payload["preference"] as? String) ?: (configMap?.get("preference") as? String)
        )
        val enableThinking = resolveRequestedEnableThinking(
            (payload["enableThinking"] as? Boolean) ?: (configMap?.get("enableThinking") as? Boolean)
        )
        val callInstructions = (payload["instructions"] as? String) ?: instructions

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
                    downsample = downsample,
                    releaseStage = stage,
                    preference = preference,
                    enableThinking = enableThinking,
                    overrideInstructions = callInstructions
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

    private fun handleGenerateTextStream(payload: Map<*, *>, events: EventChannel.EventSink) {
        val prompt = payload["prompt"] as? String
        if (prompt == null) {
            events.error("INVALID_ARG", "Prompt is required for streaming", null)
            return
        }
        val configMap = payload["config"] as? Map<*, *>
        val imageBytes = payload["imageBytes"] as? ByteArray
        val imagePath = payload["imagePath"] as? String
        val imageBase64 = payload["imageBase64"] as? String
        val downsample = (payload["downsample"] as? Boolean) ?: true
        val stage = resolveRequestedStage(
            (payload["releaseStage"] as? String) ?: (configMap?.get("releaseStage") as? String)
        )
        val preference = resolveRequestedPreference(
            (payload["preference"] as? String) ?: (configMap?.get("preference") as? String)
        )
        val enableThinking = resolveRequestedEnableThinking(
            (payload["enableThinking"] as? Boolean) ?: (configMap?.get("enableThinking") as? Boolean)
        )
        val callInstructions = (payload["instructions"] as? String) ?: instructions

        activeStreamJob?.cancel()
        var lastFinishReason: String? = null
        var finalDoneResponse: Map<String, Any>? = null
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

                generateTextStreamFlow(
                    prompt = prompt,
                    configMap = configMap,
                    bitmap = bitmap,
                    releaseStage = stage,
                    preference = preference,
                    enableThinking = enableThinking,
                    overrideInstructions = callInstructions
                )
                    .onEach { chunkMap ->
                        val reasonFromChunk = chunkMap["reason"] as? String
                        if (!reasonFromChunk.isNullOrBlank() &&
                            reasonFromChunk != "null" &&
                            reasonFromChunk != "UNKNOWN"
                        ) {
                            lastFinishReason = reasonFromChunk
                        }
                        if (chunkMap["status"] == "done") {
                            finalDoneResponse = chunkMap
                        } else {
                            withContext(Dispatchers.Main) {
                                if (isActive) {
                                    events.success(mapOf("status" to "Streaming", "response" to chunkMap, "error" to null))
                                }
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
                                        "response" to finalDoneResponse,
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

    private suspend fun initAiCore(
        stage: String = resolveRequestedStage(),
        preference: String = resolveRequestedPreference()
    ): String = withContext(Dispatchers.IO) {
        try {
            val resolved = ensureClient(
                stage = stage,
                preference = preference,
                allowDownloadable = true,
                forceRefresh = true
            )
            when (resolved.statusCode) {
                FeatureStatus.AVAILABLE -> "Available=Available=0"
                FeatureStatus.UNAVAILABLE -> "Error=AICore=Unavailable"
                FeatureStatus.DOWNLOADING -> "Download=In Progress=0"
                FeatureStatus.DOWNLOADABLE -> {
                    var downloadMessage = "Download=In Progress=0"
                    resolved.model.download().collect { downloadStatus ->
                        when (downloadStatus) {
                            is DownloadStatus.DownloadStarted ->   downloadMessage = "Download=In Progress=0"
                            is DownloadStatus.DownloadProgress ->  downloadMessage = "Download=In Progress=${downloadStatus.totalBytesDownloaded}"
                            is DownloadStatus.DownloadCompleted -> downloadMessage = "Available=Download=0"
                            is DownloadStatus.DownloadFailed ->    downloadMessage = "Error=Download=${downloadStatus.e.message}"
                        }
                    }
                    downloadMessage
                }
                else -> "Error=Unknown=${resolved.statusCode}"
            }
        } catch (e: Exception) {
            "Error=Unknown=${e.message}"
        }
    }

    private suspend fun generateTextAsync(
        prompt: String,
        configMap: Map<*, *>?,
        imageBytes: ByteArray? = null,
        imagePath: String? = null,
        imageBase64: String? = null,
        downsample: Boolean = true,
        releaseStage: String = resolveRequestedStage(),
        preference: String = resolveRequestedPreference(),
        enableThinking: Boolean = resolveRequestedEnableThinking(),
        overrideInstructions: String? = instructions
    ): Map<String, Any> = withContext(Dispatchers.IO) {
        activeGenerationCount.incrementAndGet()
        try {
            val resolved = ensureClient(
                stage = releaseStage,
                preference = preference,
                allowDownloadable = false
            )
            val maxOutputTokensValue = (configMap?.get("maxTokens") as? Number)?.toInt()
            val temperatureValue = (configMap?.get("temperature") as? Number)?.toFloat()
            val candidateCountValue = (configMap?.get("candidates") as? Number)?.toInt()
            val bitmap = prepareBitmap(imageBytes, imagePath, imageBase64, downsample)

            val request = PaiosModelHelper.buildRequest(
                prompt = prompt,
                instructions = overrideInstructions,
                image = bitmap,
                maxTokens = maxOutputTokensValue,
                temperature = temperatureValue,
                enableThinking = enableThinking,
                useNativeSystemInstruction = resolved.capabilities.isSystemPromptAvailable,
                useThinkingCapability = resolved.capabilities.isThinkingModeAvailable,
                candidateCount = candidateCountValue
            )
            val startTime = System.currentTimeMillis()
            val response: GenerateContentResponse = resolved.model.generateContent(request)
            val generationTime = System.currentTimeMillis() - startTime
            val generatedText = response.candidates.firstOrNull()?.text ?: ""
            val thoughtText = response.thoughtProcess.joinToString("") { it.text }
            val finishReason = response.candidates.firstOrNull()?.finishReason?.toString()
            val tokenCount = generatedText.split(" ").filter { it.isNotEmpty() }.size
            val resultMap = mutableMapOf<String, Any>(
                "text" to generatedText,
                "generationTimeMs" to generationTime,
                "tokenCount" to tokenCount
            )
            if (thoughtText.isNotEmpty()) {
                resultMap["thought"] = thoughtText
            }
            if (!finishReason.isNullOrBlank() && finishReason != "null") {
                resultMap["reason"] = finishReason
            }
            resultMap
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.e("FlutterLocalAi", "generateText error: ${e.javaClass.simpleName} - ${e.message}", e)
            val errorMessage = e.message ?: ""
            val errorCode = extractErrorCode(errorMessage)
            if (errorCode == -101) {
                throw Exception("AICore is not installed or version is too low (Error -101). Please install or update Google AICore from the Play Store: https://play.google.com/store/apps/details?id=com.google.android.aicore")
            }
            throw Exception("Error generating text: ${e.message}")
        } finally {
            activeGenerationCount.decrementAndGet()
        }
    }

    private suspend fun generateInternalInferenceAsync(
        prompt: String,
        oneShotInstructions: String?,
        imageBytes: ByteArray?,
        maxTokens: Int,
        temperature: Float
    ): String = withContext(Dispatchers.IO) {
        val resolved = ensureClient(
            stage = resolveRequestedStage(),
            preference = resolveRequestedPreference(),
            allowDownloadable = false
        )
        val bitmap = if (imageBytes != null && imageBytes.isNotEmpty()) {
            prepareBitmap(imageBytes, null, null, true)
        } else {
            null
        }
        val cleanInstructions = oneShotInstructions?.takeIf { it.isNotBlank() }
        val clampedTokens = maxTokens.coerceIn(1, 256)

        val request = PaiosModelHelper.buildRequest(
            prompt = prompt,
            instructions = cleanInstructions,
            image = bitmap,
            maxTokens = clampedTokens,
            temperature = temperature,
            enableThinking = false,
            useNativeSystemInstruction = resolved.capabilities.isSystemPromptAvailable,
            useThinkingCapability = false,
            candidateCount = 1
        )

        val retryDelaysMs = longArrayOf(200L, 450L, 800L)
        var lastException: Exception? = null
        for (attempt in 0..retryDelaysMs.size) {
            try {
                val response: GenerateContentResponse = resolved.model.generateContent(request)
                return@withContext response.candidates.firstOrNull()?.text ?: ""
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                lastException = e
                if (PaiosModelHelper.isBusyException(e) && attempt < retryDelaysMs.size) {
                    val waitMs = retryDelaysMs[attempt]
                    Log.w(
                        "FlutterLocalAi",
                        "generateInternalInference busy (-101), retry ${attempt + 1}/${retryDelaysMs.size} after ${waitMs}ms: ${e.message}"
                    )
                    delay(waitMs)
                } else {
                    break
                }
            }
        }

        val finalError = lastException ?: Exception("Unknown internal inference error")
        Log.e(
            "FlutterLocalAi",
            "generateInternalInference failed: ${finalError.javaClass.simpleName} - ${finalError.message}",
            finalError
        )
        throw Exception("Internal inference error: ${finalError.message}", finalError)
    }

    private fun generateTextStreamFlow(
        prompt: String,
        configMap: Map<*, *>?,
        bitmap: Bitmap? = null,
        releaseStage: String = resolveRequestedStage(),
        preference: String = resolveRequestedPreference(),
        enableThinking: Boolean = resolveRequestedEnableThinking(),
        overrideInstructions: String? = instructions
    ): Flow<Map<String, Any>> {
        val candidateCountValue = (configMap?.get("candidates") as? Number)?.toInt()
        val maxOutputTokensValue = (configMap?.get("maxTokens") as? Number)?.toInt()
        val temperatureValue = (configMap?.get("temperature") as? Number)?.toFloat()
        val startTime = System.currentTimeMillis()

        return flow {
            activeGenerationCount.incrementAndGet()
            try {
                val resolved = ensureClient(
                    stage = releaseStage,
                    preference = preference,
                    allowDownloadable = false
                )
                val useThinking = enableThinking && resolved.capabilities.isThinkingModeAvailable
                val request = PaiosModelHelper.buildRequest(
                    prompt = prompt,
                    instructions = overrideInstructions,
                    image = bitmap,
                    maxTokens = maxOutputTokensValue,
                    temperature = temperatureValue,
                    enableThinking = useThinking,
                    useNativeSystemInstruction = resolved.capabilities.isSystemPromptAvailable,
                    useThinkingCapability = resolved.capabilities.isThinkingModeAvailable,
                    candidateCount = candidateCountValue
                )

                if (useThinking) {
                    callbackFlow {
                        val job = launch(Dispatchers.IO) {
                            val lock = Any()
                            val textBuffer = StringBuilder()
                            val thoughtBuffer = StringBuilder()
                            try {
                                val finalResponse = resolved.model.generateContent(
                                    request,
                                    object : StreamingCallback {
                                        override fun onNewThought(thought: String) {
                                            if (thought.isEmpty()) return
                                            val cumulativeText: String
                                            val cumulativeThought: String
                                            synchronized(lock) {
                                                thoughtBuffer.append(thought)
                                                cumulativeText = textBuffer.toString()
                                                cumulativeThought = thoughtBuffer.toString()
                                            }
                                            val generationTime = System.currentTimeMillis() - startTime
                                            val tokenCount = cumulativeText.split(" ").count { it.isNotEmpty() }
                                            trySend(
                                                mapOf(
                                                    "status" to "streaming",
                                                    "text" to cumulativeText,
                                                    "chunk" to "",
                                                    "thought" to cumulativeThought,
                                                    "thoughtChunk" to thought,
                                                    "generationTimeMs" to generationTime,
                                                    "tokenCount" to tokenCount
                                                )
                                            )
                                        }

                                        override fun onNewText(text: String) {
                                            if (text.isEmpty()) return
                                            val cumulativeText: String
                                            val cumulativeThought: String
                                            synchronized(lock) {
                                                textBuffer.append(text)
                                                cumulativeText = textBuffer.toString()
                                                cumulativeThought = thoughtBuffer.toString()
                                            }
                                            val generationTime = System.currentTimeMillis() - startTime
                                            val tokenCount = cumulativeText.split(" ").count { it.isNotEmpty() }
                                            trySend(
                                                mapOf(
                                                    "status" to "streaming",
                                                    "text" to cumulativeText,
                                                    "chunk" to text,
                                                    "thought" to cumulativeThought,
                                                    "generationTimeMs" to generationTime,
                                                    "tokenCount" to tokenCount
                                                )
                                            )
                                        }
                                    }
                                )
                                val finalText = synchronized(lock) { textBuffer.toString() }
                                    .ifEmpty { finalResponse.candidates.firstOrNull()?.text ?: "" }
                                val finalThought = synchronized(lock) { thoughtBuffer.toString() }
                                    .ifEmpty { finalResponse.thoughtProcess.joinToString("") { it.text } }
                                val finishReason = PaiosModelHelper.normalizeFinishReason(
                                    finalResponse.candidates.firstOrNull()?.finishReason
                                )
                                val generationTime = System.currentTimeMillis() - startTime
                                val tokenCount = finalText.split(" ").count { it.isNotEmpty() }
                                val doneMap = mutableMapOf<String, Any>(
                                    "status" to "done",
                                    "text" to finalText,
                                    "thought" to finalThought,
                                    "generationTimeMs" to generationTime,
                                    "tokenCount" to tokenCount
                                )
                                if (finishReason != null) {
                                    doneMap["reason"] = finishReason
                                }
                                trySend(doneMap)
                                close()
                            } catch (e: CancellationException) {
                                throw e
                            } catch (e: Exception) {
                                close(e)
                            }
                        }
                        awaitClose { job.cancel() }
                    }.collect { emit(it) }
                } else {
                    var fullResponse = ""
                    var lastFinishReason: String? = null
                    resolved.model.generateContentStream(request)
                        .transform { chunk ->
                            val candidate = chunk.candidates.firstOrNull()
                            val newChunkText = candidate?.text ?: ""
                            val chunkReason = PaiosModelHelper.normalizeFinishReason(candidate?.finishReason)
                            if (chunkReason != null) {
                                lastFinishReason = chunkReason
                            }
                            fullResponse += newChunkText
                            val generationTime = System.currentTimeMillis() - startTime
                            val tokenCount = fullResponse.split(" ").filter { it.isNotEmpty() }.size
                            val chunkMap = mutableMapOf<String, Any>(
                                "status" to "streaming",
                                "text" to fullResponse,
                                "chunk" to newChunkText,
                                "generationTimeMs" to generationTime,
                                "tokenCount" to tokenCount
                            )
                            val activeReason = lastFinishReason
                            if (activeReason != null) {
                                chunkMap["reason"] = activeReason
                            }
                            emit(chunkMap)
                        }
                        .collect { emit(it) }

                    val generationTime = System.currentTimeMillis() - startTime
                    val tokenCount = fullResponse.split(" ").filter { it.isNotEmpty() }.size
                    val doneMap = mutableMapOf<String, Any>(
                        "status" to "done",
                        "text" to fullResponse,
                        "generationTimeMs" to generationTime,
                        "tokenCount" to tokenCount
                    )
                    val finalReason = lastFinishReason
                    if (finalReason != null) {
                        doneMap["reason"] = finalReason
                    }
                    emit(doneMap)
                }
            } finally {
                activeGenerationCount.decrementAndGet()
            }
        }.catch { e ->
            if (e is CancellationException) throw e
            Log.e("FlutterLocalAi", "generateTextStream error: ${e.javaClass.simpleName} - ${e.message}", e)
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
            val devSettingsIntent = Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS).apply {
                putExtra(":settings:fragment_args_key", AICORE_DEV_TILE_KEY)
                putExtra(
                    ":settings:show_fragment_args",
                    Bundle().apply {
                        putString(":settings:fragment_args_key", AICORE_DEV_TILE_KEY)
                    }
                )
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(devSettingsIntent)
            return
        } catch (e: Exception) {
            Log.w("FlutterLocalAi", "Could not start Developer Options: ${e.message}")
        }

        try {
            val appDetailsIntent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", AICORE_PACKAGE, null)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(appDetailsIntent)
        } catch (e: Exception) {
            throw Exception("Could not open AICore settings or fallback settings: ${e.message}")
        }
    }

    private fun dispose() {
        variantDownloadJobs.values.forEach { it.cancel() }
        variantDownloadJobs.clear()
        variantDownloadOutcomes.clear()
        downloadEventSink = null
        coroutineScope.cancel()
        val oldModel = synchronized(clientLock) {
            val prev = activeResolvedClient?.model
            activeResolvedClient = null
            prev
        }
        if (oldModel != null) {
            runCatching { oldModel.close() }
        }
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
