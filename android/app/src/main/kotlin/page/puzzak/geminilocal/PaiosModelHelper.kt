package page.puzzak.geminilocal

import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.util.Log
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.common.GenAiException
import com.google.mlkit.genai.prompt.Feature
import com.google.mlkit.genai.prompt.GenerateContentRequest
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.GenerativeModel
import com.google.mlkit.genai.prompt.ImagePart
import com.google.mlkit.genai.prompt.ModelPreference
import com.google.mlkit.genai.prompt.ModelReleaseStage
import com.google.mlkit.genai.prompt.SystemInstruction
import com.google.mlkit.genai.prompt.TextPart
import com.google.mlkit.genai.prompt.generateContentRequest
import com.google.mlkit.genai.prompt.generationConfig
import com.google.mlkit.genai.prompt.modelConfig
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Shared AICore / MLKit GenAI Prompt helper for PAIOS.
 *
 * Centralizes `ModelConfig` (releaseStage / preference) client construction,
 * graceful Preview -> Stable+Full fallback, capability probing, native
 * `SystemInstruction` / `TextPart` request construction, and busy-error detection.
 */
object PaiosModelHelper {
    const val STAGE_STABLE = "stable"
    const val STAGE_PREVIEW = "preview"
    const val PREF_FAST = "fast"
    const val PREF_FULL = "full"
    const val MAX_SYSTEM_INSTRUCTION_WORDS = 140
    const val MAX_OVERLAY_CONTINUATIONS = 6
    const val MAX_OVERLAY_ACCUMULATED_CHARS = 12000
    const val MAX_CONTINUATION_TAIL_CHARS = 450

    private val CONTINUATION_DUPLICATE_FENCE_REGEX = Regex("""^```[a-zA-Z0-9]*\r?\n?""")
    private val LEADING_CONTINUATION_ELLIPSIS_REGEX = Regex("""^\s*(?:\.\.\.+|…+)\s*""")
    private val CONTRACTION_TRAILING_APOSTROPHE_REGEX = Regex("""[A-Za-z0-9]['’]$""")
    private val TERMINAL_PUNCTUATION_REGEX = Regex("""[.!?…"\x27”’`\)\]。！？]+$""")
    private val TRAILING_MARKDOWN_WITH_TERMINAL_REGEX = Regex("""[.!?…"\x27”’`\)\]。！？][*_]+$""")
    private val OPEN_MID_CLAUSE_TAIL_REGEX = Regex("""[,;:\-—(\[\{]$""")
    private val WHITESPACE_SPLIT_REGEX = Regex("""\s+""")

    private const val FLUTTER_PREFS = "FlutterSharedPreferences"
    private val NANO_V4_REGEX = Regex("""(?:^|[^a-z0-9])(v4|nano[\s\-_]?4)(?:[^a-z0-9]|$)""", RegexOption.IGNORE_CASE)
    private val NANO_V3_REGEX = Regex("""(?:^|[^a-z0-9])(v3|nano[\s\-_]?3)(?:[^a-z0-9]|$)""", RegexOption.IGNORE_CASE)
    private val NANO_V2_REGEX = Regex("""(?:^|[^a-z0-9])(v2|nano[\s\-_]?2)(?:[^a-z0-9]|$)""", RegexOption.IGNORE_CASE)
    private val GENERAL_NANO_VERSION_REGEX = Regex("""v?(\d+(?:\.\d+)?)""", RegexOption.IGNORE_CASE)
    private val WORD_TOKEN_REGEX = Regex("""\S+""")
    private val POLICY_ERROR_CODE_REGEX = Regex("""(?:\[\s*|\b)(?:ErrorCode|Error)\s*[:=]?\s*4\b""", RegexOption.IGNORE_CASE)
    private val EDGE_NON_ALNUM_REGEX = Regex("""^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$""")
    private val MULTI_SPACE_REGEX = Regex("""\s+""")
    private val PURE_GREETING_PHRASES = setOf(
        "hi", "hello", "hey", "yo", "sup", "hiya", "howdy", "greetings",
        "hi there", "hello there", "hey there",
        "good morning", "good afternoon", "good evening", "good night", "morning",
        "how are you", "how are you doing", "how's it going", "hows it going",
        "what's up", "whats up",
        "thanks", "thank you", "thx", "ok", "okay", "bye", "goodbye", "see you",
        "привіт", "вітаю", "добрий день", "добрий вечір", "доброго ранку",
        "як справи", "дякую", "бувай"
    )

    data class CropRect(
        val left: Int,
        val top: Int,
        val width: Int,
        val height: Int
    )

    data class ModelCapabilities(
        val baseModelName: String,
        val availableFeatures: List<Int>,
        val isSystemPromptAvailable: Boolean,
        val isThinkingModeAvailable: Boolean,
        val isCachingAvailable: Boolean,
        val tokenLimit: Int,
        val isNanoV4: Boolean
    )

    data class ResolvedModelClient(
        val model: GenerativeModel,
        val requestedStage: String,
        val requestedPreference: String,
        val activeStage: String,
        val activePreference: String,
        val fellBackToStable: Boolean,
        val statusCode: Int,
        val capabilities: ModelCapabilities
    )

    data class ModelVariantInfo(
        val releaseStage: String,
        val preference: String,
        val statusCode: Int,
        val status: String,
        val available: Boolean,
        val baseModelName: String?,
        val isActive: Boolean
    ) {
        val isUnavailable: Boolean get() = statusCode == FeatureStatus.UNAVAILABLE

        fun toMap(): Map<String, Any?> = mapOf(
            "releaseStage" to releaseStage,
            "preference" to preference,
            "statusCode" to statusCode,
            "status" to status,
            "available" to available,
            "baseModelName" to baseModelName,
            "isActive" to isActive
        )
    }

    data class ComboStatuses(
        val stableFullStatus: Int,
        val stableFastStatus: Int,
        val previewFullStatus: Int,
        val previewFastStatus: Int,
        val stableFullBaseModelName: String? = null,
        val stableFastBaseModelName: String? = null,
        val previewFullBaseModelName: String? = null,
        val previewFastBaseModelName: String? = null
    ) {
        val stableFullAvailable: Boolean get() = stableFullStatus != FeatureStatus.UNAVAILABLE
        val stableFastAvailable: Boolean get() = stableFastStatus != FeatureStatus.UNAVAILABLE
        val previewFullAvailable: Boolean get() = previewFullStatus != FeatureStatus.UNAVAILABLE
        val previewFastAvailable: Boolean get() = previewFastStatus != FeatureStatus.UNAVAILABLE
        val previewAvailable: Boolean get() = previewFullAvailable || previewFastAvailable
        val hasAnySupportedModel: Boolean
            get() = stableFullAvailable || stableFastAvailable || previewFullAvailable || previewFastAvailable
        val hasAnyAvailableModel: Boolean
            get() = stableFullStatus == FeatureStatus.AVAILABLE ||
                stableFastStatus == FeatureStatus.AVAILABLE ||
                previewFullStatus == FeatureStatus.AVAILABLE ||
                previewFastStatus == FeatureStatus.AVAILABLE

        fun isFastAvailableFor(stage: String): Boolean =
            if (normalizeReleaseStage(stage) == STAGE_PREVIEW) previewFastAvailable else stableFastAvailable

        fun statusCodeFor(stage: String, preference: String): Int {
            val normStage = normalizeReleaseStage(stage)
            val normPref = normalizePreference(preference)
            return when {
                normStage == STAGE_STABLE && normPref == PREF_FULL -> stableFullStatus
                normStage == STAGE_STABLE && normPref == PREF_FAST -> stableFastStatus
                normStage == STAGE_PREVIEW && normPref == PREF_FULL -> previewFullStatus
                else -> previewFastStatus
            }
        }

        fun baseModelNameFor(stage: String, preference: String): String? {
            val normStage = normalizeReleaseStage(stage)
            val normPref = normalizePreference(preference)
            val raw = when {
                normStage == STAGE_STABLE && normPref == PREF_FULL -> stableFullBaseModelName
                normStage == STAGE_STABLE && normPref == PREF_FAST -> stableFastBaseModelName
                normStage == STAGE_PREVIEW && normPref == PREF_FULL -> previewFullBaseModelName
                else -> previewFastBaseModelName
            }
            return sanitizeBaseModelName(raw)
        }

        fun toVariantList(
            activeStage: String? = null,
            activePreference: String? = null,
            activeBaseModelName: String? = null
        ): List<ModelVariantInfo> {
            val normActiveStage = activeStage?.let { normalizeReleaseStage(it) }
            val normActivePref = activePreference?.let { normalizePreference(it) }
            val cleanActiveName = sanitizeBaseModelName(activeBaseModelName)
            val combos = listOf(
                STAGE_STABLE to PREF_FULL,
                STAGE_STABLE to PREF_FAST,
                STAGE_PREVIEW to PREF_FULL,
                STAGE_PREVIEW to PREF_FAST
            )
            return combos.map { (stage, pref) ->
                val isActive = normActiveStage == stage && normActivePref == pref
                val code = statusCodeFor(stage, pref)
                val name = if (isActive && cleanActiveName != null) {
                    cleanActiveName
                } else {
                    baseModelNameFor(stage, pref)
                }
                ModelVariantInfo(
                    releaseStage = stage,
                    preference = pref,
                    statusCode = code,
                    status = statusCodeToString(code),
                    available = code == FeatureStatus.AVAILABLE,
                    baseModelName = name,
                    isActive = isActive
                )
            }
        }
    }

    private fun flutterPrefs(context: Context): SharedPreferences =
        context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)

    fun normalizeReleaseStage(raw: String?): String {
        return when (raw?.trim()?.lowercase(Locale.ROOT)) {
            STAGE_PREVIEW -> STAGE_PREVIEW
            else -> STAGE_STABLE
        }
    }

    fun normalizePreference(raw: String?): String {
        return when (raw?.trim()?.lowercase(Locale.ROOT)) {
            PREF_FAST -> PREF_FAST
            else -> PREF_FULL
        }
    }

    fun hasModelReleaseStagePref(context: Context): Boolean = runCatching {
        val prefs = flutterPrefs(context)
        prefs.contains("flutter.modelReleaseStage") || prefs.contains("modelReleaseStage")
    }.getOrDefault(false)

    fun getModelReleaseStage(context: Context): String = runCatching {
        val prefs = flutterPrefs(context)
        val raw = prefs.getString("flutter.modelReleaseStage", null)
            ?: prefs.getString("modelReleaseStage", null)
        normalizeReleaseStage(raw)
    }.getOrDefault(STAGE_STABLE)

    fun hasModelPreferencePref(context: Context): Boolean = runCatching {
        val prefs = flutterPrefs(context)
        prefs.contains("flutter.modelPreference") || prefs.contains("modelPreference")
    }.getOrDefault(false)

    fun getModelPreference(context: Context): String = runCatching {
        val prefs = flutterPrefs(context)
        val raw = prefs.getString("flutter.modelPreference", null)
            ?: prefs.getString("modelPreference", null)
        normalizePreference(raw)
    }.getOrDefault(PREF_FULL)

    fun hasEnableThinkingPref(context: Context): Boolean = runCatching {
        val prefs = flutterPrefs(context)
        prefs.contains("flutter.enableThinking") || prefs.contains("enableThinking")
    }.getOrDefault(false)

    fun getEnableThinking(context: Context, defaultValue: Boolean = false): Boolean = runCatching {
        val prefs = flutterPrefs(context)
        when {
            prefs.contains("flutter.enableThinking") -> prefs.getBoolean("flutter.enableThinking", defaultValue)
            prefs.contains("enableThinking") -> prefs.getBoolean("enableThinking", defaultValue)
            else -> defaultValue
        }
    }.getOrDefault(defaultValue)

    fun statusCodeToString(statusCode: Int): String = when (statusCode) {
        FeatureStatus.AVAILABLE -> "available"
        FeatureStatus.DOWNLOADABLE -> "downloadable"
        FeatureStatus.DOWNLOADING -> "downloading"
        else -> "unavailable"
    }

    fun sanitizeBaseModelName(raw: String?): String? {
        val trimmed = raw?.trim() ?: return null
        if (trimmed.isEmpty() ||
            trimmed.equals("Unknown", ignoreCase = true) ||
            trimmed.equals("null", ignoreCase = true)
        ) {
            return null
        }
        return trimmed
    }

    fun formatNanoAuthor(
        baseModelName: String?,
        isNanoV4: Boolean = false
    ): String {
        if (isNanoV4) return "Gemini Nano v4"
        val clean = sanitizeBaseModelName(baseModelName) ?: return "Gemini Nano"
        if (NANO_V4_REGEX.containsMatchIn(clean)) return "Gemini Nano v4"
        if (NANO_V3_REGEX.containsMatchIn(clean)) return "Gemini Nano v3"
        if (NANO_V2_REGEX.containsMatchIn(clean)) return "Gemini Nano v2"
        val match = GENERAL_NANO_VERSION_REGEX.find(clean)
        if (match != null) {
            val ver = match.groupValues[1]
            if (ver.isNotEmpty()) return "Gemini Nano v$ver"
        }
        return "Gemini Nano"
    }

    fun buildClient(releaseStage: String, preference: String): GenerativeModel {
        val normStage = normalizeReleaseStage(releaseStage)
        val normPref = normalizePreference(preference)
        val stageValue = if (normStage == STAGE_PREVIEW) {
            ModelReleaseStage.PREVIEW
        } else {
            ModelReleaseStage.STABLE
        }
        val prefValue = if (normPref == PREF_FAST) {
            ModelPreference.FAST
        } else {
            ModelPreference.FULL
        }
        val config = generationConfig {
            modelConfig = modelConfig {
                this.releaseStage = stageValue
                this.preference = prefValue
            }
        }
        return Generation.getClient(config)
    }

    @Suppress("DEPRECATION")
    suspend fun probeCapabilities(model: GenerativeModel, statusCode: Int): ModelCapabilities {
        if (statusCode != FeatureStatus.AVAILABLE) {
            return ModelCapabilities(
                baseModelName = "Unknown",
                availableFeatures = emptyList(),
                isSystemPromptAvailable = false,
                isThinkingModeAvailable = false,
                isCachingAvailable = false,
                tokenLimit = 0,
                isNanoV4 = false
            )
        }
        val rawBaseModelName = runCatching { model.getBaseModelName() }
            .onFailure { e ->
                Log.w("FlutterLocalAi", "getBaseModelName() failed: ${e.javaClass.simpleName} - ${e.message}")
            }
            .getOrNull()
            ?.trim()
        val baseModelName = rawBaseModelName?.takeIf { it.isNotEmpty() } ?: "Unknown"
        val availableFeatures = runCatching { model.getAvailableFeatures() }
            .getOrDefault(emptyList())
        val isSystemPromptAvailable = runCatching { model.isSystemPromptAvailable() }
            .getOrDefault(availableFeatures.contains(Feature.SYSTEM_PROMPT))
        val isThinkingModeAvailable = runCatching { model.isThinkingModeAvailable() }
            .getOrDefault(availableFeatures.contains(Feature.THINKING_MODE))
        val isCachingAvailable = runCatching { model.isCachingFeatureAvailable() }
            .getOrDefault(availableFeatures.contains(Feature.PREFIX_CACHING))
        val tokenLimit = runCatching { model.getTokenLimit() }
            .getOrDefault(0)
        val isNanoV4 = isThinkingModeAvailable ||
            availableFeatures.contains(Feature.THINKING_MODE) ||
            baseModelName.contains("v4", ignoreCase = true) ||
            baseModelName.contains("nano 4", ignoreCase = true) ||
            baseModelName.contains("nano-4", ignoreCase = true)

        return ModelCapabilities(
            baseModelName = baseModelName,
            availableFeatures = availableFeatures,
            isSystemPromptAvailable = isSystemPromptAvailable,
            isThinkingModeAvailable = isThinkingModeAvailable,
            isCachingAvailable = isCachingAvailable,
            tokenLimit = tokenLimit,
            isNanoV4 = isNanoV4
        )
    }

    private data class ComboProbeResult(
        val statusCode: Int,
        val baseModelName: String? = null
    )

    @Suppress("DEPRECATION")
    private suspend fun probeComboDetails(
        releaseStage: String,
        preference: String,
        activeResolved: ResolvedModelClient? = null
    ): ComboProbeResult = withContext(Dispatchers.IO) {
        val normStage = normalizeReleaseStage(releaseStage)
        val normPref = normalizePreference(preference)
        if (activeResolved != null &&
            activeResolved.activeStage == normStage &&
            activeResolved.activePreference == normPref
        ) {
            val cachedName = sanitizeBaseModelName(activeResolved.capabilities.baseModelName)
            val resolvedName = cachedName ?: if (
                activeResolved.statusCode == FeatureStatus.DOWNLOADABLE ||
                activeResolved.statusCode == FeatureStatus.DOWNLOADING
            ) {
                runCatching { sanitizeBaseModelName(activeResolved.model.getBaseModelName()) }
                    .getOrNull()
            } else {
                null
            }
            return@withContext ComboProbeResult(
                statusCode = activeResolved.statusCode,
                baseModelName = resolvedName
            )
        }
        val tempModel = buildClient(normStage, normPref)
        try {
            val code = runCatching { tempModel.checkStatus() }
                .getOrDefault(FeatureStatus.UNAVAILABLE)
            val baseName = if (code == FeatureStatus.AVAILABLE ||
                code == FeatureStatus.DOWNLOADABLE ||
                code == FeatureStatus.DOWNLOADING
            ) {
                runCatching { sanitizeBaseModelName(tempModel.getBaseModelName()) }
                    .getOrNull()
            } else {
                null
            }
            ComboProbeResult(statusCode = code, baseModelName = baseName)
        } finally {
            runCatching { tempModel.close() }
        }
    }

    suspend fun probeComboStatus(releaseStage: String, preference: String): Int =
        probeComboDetails(releaseStage, preference).statusCode

    suspend fun probeAllComboStatuses(
        activeResolved: ResolvedModelClient? = null
    ): ComboStatuses = withContext(Dispatchers.IO) {
        val stableFull = probeComboDetails(STAGE_STABLE, PREF_FULL, activeResolved)
        val stableFast = probeComboDetails(STAGE_STABLE, PREF_FAST, activeResolved)
        val previewFull = probeComboDetails(STAGE_PREVIEW, PREF_FULL, activeResolved)
        val previewFast = probeComboDetails(STAGE_PREVIEW, PREF_FAST, activeResolved)
        ComboStatuses(
            stableFullStatus = stableFull.statusCode,
            stableFastStatus = stableFast.statusCode,
            previewFullStatus = previewFull.statusCode,
            previewFastStatus = previewFast.statusCode,
            stableFullBaseModelName = stableFull.baseModelName,
            stableFastBaseModelName = stableFast.baseModelName,
            previewFullBaseModelName = previewFull.baseModelName,
            previewFastBaseModelName = previewFast.baseModelName
        )
    }

    suspend fun resolveClient(
        requestedStage: String,
        requestedPreference: String,
        allowDownloadable: Boolean = true
    ): ResolvedModelClient = withContext(Dispatchers.IO) {
        val normRequestedStage = normalizeReleaseStage(requestedStage)
        val normRequestedPref = normalizePreference(requestedPreference)

        var activeStage = normRequestedStage
        var activePref = normRequestedPref
        var fellBackToStable = false

        var model = buildClient(activeStage, activePref)
        var statusCode = runCatching { model.checkStatus() }
            .getOrDefault(FeatureStatus.UNAVAILABLE)

        val isNonDefaultCombo = normRequestedStage != STAGE_STABLE || normRequestedPref != PREF_FULL
        val shouldFallback = isNonDefaultCombo && (
            statusCode == FeatureStatus.UNAVAILABLE ||
                (!allowDownloadable && statusCode != FeatureStatus.AVAILABLE)
        )

        if (shouldFallback) {
            val originalStatus = statusCode
            runCatching { model.close() }
            activeStage = STAGE_STABLE
            activePref = PREF_FULL
            fellBackToStable = true
            model = buildClient(activeStage, activePref)
            statusCode = runCatching { model.checkStatus() }
                .getOrDefault(FeatureStatus.UNAVAILABLE)
            Log.i(
                "FlutterLocalAi",
                "resolveClient fallback: $normRequestedStage/$normRequestedPref (status=$originalStatus) -> " +
                    "$activeStage/$activePref (status=$statusCode)"
            )
        }

        val capabilities = probeCapabilities(model, statusCode)

        ResolvedModelClient(
            model = model,
            requestedStage = normRequestedStage,
            requestedPreference = normRequestedPref,
            activeStage = activeStage,
            activePreference = activePref,
            fellBackToStable = fellBackToStable,
            statusCode = statusCode,
            capabilities = capabilities
        )
    }

    fun buildRequest(
        prompt: String,
        instructions: String? = null,
        image: Bitmap? = null,
        maxTokens: Int? = null,
        temperature: Float? = null,
        enableThinking: Boolean = false,
        useNativeSystemInstruction: Boolean = false,
        useThinkingCapability: Boolean = enableThinking,
        candidateCount: Int? = null
    ): GenerateContentRequest {
        val cleanInstructions = instructions?.trim()?.takeIf { it.isNotEmpty() }
        val sysInstruction = if (useNativeSystemInstruction) cleanInstructions else null
        val effectivePrompt = if (sysInstruction == null && cleanInstructions != null) {
            "$cleanInstructions\n\n$prompt"
        } else {
            prompt
        }
        val shouldThink = enableThinking && useThinkingCapability

        val configure: GenerateContentRequest.Builder.() -> Unit = {
            if (maxTokens != null && maxTokens > 0) {
                maxOutputTokens = maxTokens
            }
            if (temperature != null) {
                this.temperature = temperature
            }
            if (candidateCount != null && candidateCount > 0) {
                this.candidateCount = candidateCount
            }
            if (shouldThink) {
                this.enableThinking = true
            }
        }

        return when {
            sysInstruction != null && image != null ->
                generateContentRequest(
                    SystemInstruction(sysInstruction),
                    ImagePart(image),
                    TextPart(effectivePrompt),
                    configure
                )
            sysInstruction != null ->
                generateContentRequest(
                    SystemInstruction(sysInstruction),
                    TextPart(effectivePrompt),
                    configure
                )
            image != null ->
                generateContentRequest(
                    ImagePart(image),
                    TextPart(effectivePrompt),
                    configure
                )
            else ->
                generateContentRequest(
                    TextPart(effectivePrompt),
                    configure
                )
        }
    }

    fun isBusyException(e: Throwable): Boolean {
        var current: Throwable? = e
        while (current != null) {
            if (current is GenAiException && current.errorCode == GenAiException.ErrorCode.BUSY) {
                return true
            }
            val message = current.message ?: ""
            if (message.contains("-101") || message.contains("BUSY", ignoreCase = true)) {
                return true
            }
            current = current.cause
        }
        return false
    }

    fun isPolicyCheckException(e: Throwable): Boolean {
        var current: Throwable? = e
        while (current != null) {
            if (current is GenAiException &&
                current.errorCode == GenAiException.ErrorCode.REQUEST_PROCESSING_ERROR
            ) {
                return true
            }
            val message = current.message ?: ""
            if (message.contains("policy check", ignoreCase = true) ||
                message.contains("REQUEST_PROCESSING_ERROR", ignoreCase = true) ||
                POLICY_ERROR_CODE_REGEX.containsMatchIn(message)
            ) {
                return true
            }
            current = current.cause
        }
        return false
    }

    fun trimSystemInstructionToWordLimit(
        instructions: String?,
        maxWords: Int = MAX_SYSTEM_INSTRUCTION_WORDS
    ): String? {
        val trimmed = instructions?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        if (maxWords <= 0) return null
        val matches = WORD_TOKEN_REGEX.findAll(trimmed).take(maxWords + 1).toList()
        if (matches.size <= maxWords) return trimmed
        return trimmed.substring(0, matches[maxWords - 1].range.last + 1).trimEnd()
    }

    fun isPureGreetingOrSmallTalk(prompt: String): Boolean {
        val normalized = prompt
            .trim()
            .lowercase(Locale.ROOT)
            .replace(EDGE_NON_ALNUM_REGEX, "")
            .replace(MULTI_SPACE_REGEX, " ")
            .trim()
        return normalized.isNotEmpty() && PURE_GREETING_PHRASES.contains(normalized)
    }

    fun computeInsetCropRect(
        bitmapWidth: Int,
        bitmapHeight: Int,
        insetLeft: Int,
        insetTop: Int,
        insetRight: Int,
        insetBottom: Int,
        boundsWidth: Int = bitmapWidth,
        boundsHeight: Int = bitmapHeight,
        minRemainingPx: Int = 64
    ): CropRect? {
        if (bitmapWidth <= 0 || bitmapHeight <= 0) return null
        val scaleX = if (boundsWidth > 0) bitmapWidth.toFloat() / boundsWidth.toFloat() else 1f
        val scaleY = if (boundsHeight > 0) bitmapHeight.toFloat() / boundsHeight.toFloat() else 1f
        val left = (insetLeft * scaleX).toInt().coerceIn(0, bitmapWidth)
        val top = (insetTop * scaleY).toInt().coerceIn(0, bitmapHeight)
        val right = (insetRight * scaleX).toInt().coerceIn(0, bitmapWidth)
        val bottom = (insetBottom * scaleY).toInt().coerceIn(0, bitmapHeight)
        if (left == 0 && top == 0 && right == 0 && bottom == 0) return null
        val cropW = bitmapWidth - left - right
        val cropH = bitmapHeight - top - bottom
        if (cropW < minRemainingPx || cropH < minRemainingPx) return null
        return CropRect(left = left, top = top, width = cropW, height = cropH)
    }

    data class ContinuationPrompt(
        val instructions: String?,
        val userPrompt: String
    )

    fun normalizeFinishReason(raw: Any?): String? {
        val trimmed = raw?.toString()?.trim() ?: return null
        if (trimmed.isEmpty()) return null
        val upper = trimmed.uppercase(Locale.ROOT)
        if (upper == "NULL" || upper == "UNKNOWN" || upper == "FINISH_REASON_UNSPECIFIED") {
            return null
        }
        return trimmed
    }

    fun isTruncationHeuristic(text: String): Boolean {
        val trimmed = text.trimEnd()
        if (trimmed.isEmpty()) return false
        if (OPEN_MID_CLAUSE_TAIL_REGEX.containsMatchIn(trimmed)) return true
        if (CONTRACTION_TRAILING_APOSTROPHE_REGEX.containsMatchIn(trimmed)) return true
        if (TRAILING_MARKDOWN_WITH_TERMINAL_REGEX.containsMatchIn(trimmed)) return false
        if (TERMINAL_PUNCTUATION_REGEX.containsMatchIn(trimmed)) return false
        val wordCount = trimmed.split(WHITESPACE_SPLIT_REGEX).count { it.isNotEmpty() }
        return wordCount >= 3
    }

    fun shouldContinuePartialResponse(
        finishReason: String?,
        partialText: String,
        continuationCount: Int,
        lastRoundAddedChars: Int,
        isNanoV4: Boolean,
        maxContinuations: Int = MAX_OVERLAY_CONTINUATIONS,
        maxAccumulatedChars: Int = MAX_OVERLAY_ACCUMULATED_CHARS,
        nullReasonRetryCount: Int = 0
    ): Boolean {
        if (continuationCount >= maxContinuations) return false
        if (partialText.isBlank()) return false
        if (partialText.length >= maxAccumulatedChars) return false
        if (continuationCount > 0 && lastRoundAddedChars <= 0) return false

        val normalized = normalizeFinishReason(finishReason)?.uppercase(Locale.ROOT)
        if (normalized != null) {
            if (normalized == "1" ||
                normalized == "-100" ||
                normalized == "MAX_TOKENS" ||
                normalized == "LIMIT" ||
                normalized == "OTHER" ||
                normalized.contains("MAX_TOKENS") ||
                normalized.contains("LIMIT")
            ) {
                return true
            }
            if (normalized == "0" || normalized == "STOP") {
                return false
            }
        }

        if (!isNanoV4 && normalized == null && nullReasonRetryCount < 2) {
            return isTruncationHeuristic(partialText)
        }
        return false
    }

    fun boundTailAtBoundary(text: String, maxChars: Int = MAX_CONTINUATION_TAIL_CHARS): String {
        if (maxChars <= 0) return ""
        if (text.length <= maxChars) return text
        val sliceStart = text.length - maxChars
        val tail = text.substring(sliceStart)
        val searchLimit = (tail.length / 3).coerceAtMost(96)
        for (i in 0 until searchLimit) {
            val ch = tail[i]
            if (ch == '\n' || ch == ' ' || ch == '\t') {
                var nextIdx = i + 1
                while (nextIdx < tail.length && (tail[nextIdx] == ' ' || tail[nextIdx] == '\t')) {
                    nextIdx++
                }
                if (nextIdx < tail.length) {
                    return tail.substring(nextIdx)
                }
            }
        }
        return tail
    }

    private fun boundHeadAtBoundary(text: String, maxChars: Int): String {
        val trimmed = text.trim()
        if (maxChars <= 0 || trimmed.isEmpty()) return ""
        if (trimmed.length <= maxChars) return trimmed
        val cut = trimmed.substring(0, maxChars)
        val lastSpace = cut.lastIndexOfAny(charArrayOf(' ', '\n', '\t'))
        val clean = if (lastSpace >= (maxChars * 0.6).toInt()) {
            cut.substring(0, lastSpace).trimEnd()
        } else {
            cut.trimEnd()
        }
        return clean
    }

    fun stripLeadingContinuationEllipsis(text: String): String {
        if (text.isEmpty()) return text
        return text.replaceFirst(LEADING_CONTINUATION_ELLIPSIS_REGEX, "")
    }

    fun buildOverlayContinuationPrompt(
        originalQuestion: String,
        partialText: String,
        personaAnchor: String? = null,
        languageCode: String? = null,
        maxTailChars: Int = MAX_CONTINUATION_TAIL_CHARS,
        isJsonDraft: Boolean = false,
        maxQuestionChars: Int = 220
    ): ContinuationPrompt {
        val boundedPersona = personaAnchor?.let { boundHeadAtBoundary(it, 240) }.orEmpty()
        val boundedQuestion = boundHeadAtBoundary(originalQuestion, maxQuestionChars)
        val boundedTail = boundTailAtBoundary(partialText, maxTailChars)
        val trimmedLang = languageCode?.trim().orEmpty()

        val sysBlock = buildString {
            append("## [CONTINUATION]\n")
            if (boundedPersona.isNotEmpty()) {
                append("Persona: $boundedPersona\n")
            }
            if (trimmedLang.isNotEmpty()) {
                append("Language: $trimmedLang.\n")
            }
            if (boundedQuestion.isNotEmpty()) {
                append("Question: \"$boundedQuestion\"\n")
            }
            append("Partial answer tail:\n")
            append(boundedTail)
            append("\nContinue seamlessly from the exact end without repeating.")
            if (isJsonDraft) {
                append(" Output ONLY the remaining valid JSON characters to complete the tool call.")
            } else {
                append(" Do NOT prepend an ellipsis (...) or repeat words. Complete the answer concisely without starting new unrelated topics.")
            }
        }
        return ContinuationPrompt(instructions = sysBlock, userPrompt = "Continue.")
    }

    fun stitchOverlayContinuation(existing: String, incoming: String): String {
        if (incoming.isEmpty()) return existing
        if (existing.isEmpty()) return incoming

        var next = stripLeadingContinuationEllipsis(incoming)
        if (next.isEmpty()) return existing

        val openCodeFence = Regex("```").findAll(existing).count() % 2 == 1
        if (openCodeFence) {
            next = next.replaceFirst(CONTINUATION_DUPLICATE_FENCE_REGEX, "")
            if (next.isEmpty()) return existing
        }

        // Trim exact suffix-prefix overlap (>= 8 chars) if the model echoed the tail
        val maxOverlap = minOf(64, existing.length, next.length)
        for (len in maxOverlap downTo 8) {
            if (existing.regionMatches(existing.length - len, next, 0, len)) {
                val boundaryBefore = existing.length == len || existing[existing.length - len - 1].isWhitespace()
                if (boundaryBefore || len >= 14) {
                    next = next.substring(len)
                    break
                }
            }
        }
        if (next.isEmpty()) return existing

        val trimmedExistingLeft = existing.trimStart()
        val isJsonDraft = trimmedExistingLeft.startsWith("{") ||
            trimmedExistingLeft.startsWith("```json") ||
            (trimmedExistingLeft.contains("\"tool\"") && trimmedExistingLeft.contains("\"args\""))
        if (isJsonDraft) {
            return existing + next
        }

        val lastChar = existing.last()
        val firstChar = next.first()
        val endsWithSpace = lastChar.isWhitespace()
        val startsWithSpace = firstChar.isWhitespace()
        val endsWithJoiningPunct = lastChar == '\'' || lastChar == '’' ||
            lastChar == '(' || lastChar == '[' || lastChar == '{' ||
            lastChar == '"' || lastChar == '“' || lastChar == '-' ||
            lastChar == '—' || lastChar == '/'
        val startsWithPunctuation = firstChar == ',' || firstChar == '.' ||
            firstChar == '!' || firstChar == '?' || firstChar == ';' ||
            firstChar == ':' || firstChar == ')' || firstChar == ']' ||
            firstChar == '}' || firstChar == '\'' || firstChar == '’' ||
            firstChar == '"' || firstChar == '”' || firstChar == '%'

        val separator = if (openCodeFence) {
            if (endsWithSpace) "" else "\n"
        } else if (endsWithSpace || startsWithSpace || endsWithJoiningPunct || startsWithPunctuation) {
            ""
        } else {
            " "
        }

        return existing + separator + next
    }
}
