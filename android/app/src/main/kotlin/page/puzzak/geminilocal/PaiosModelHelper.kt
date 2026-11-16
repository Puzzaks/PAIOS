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
import org.json.JSONArray
import org.json.JSONObject

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
    const val MAX_TOOL_JSON_CONTINUATIONS = 2
    const val MAX_OVERLAY_ACCUMULATED_CHARS = 12000
    const val MAX_CONTINUATION_TAIL_CHARS = 450
    const val MAX_CONTINUATION_OVERLAP_CHARS = 240
    const val MID_WORD_BACKOFF_MAX_CHARS = 28
    const val SCREEN_CONTEXT_TTL_TURNS = 3
    const val MAX_STOP_CUTOFF_RETRIES = 1
    const val MAX_STOP_CUTOFF_RESCUE_CHARS = 1800
    private const val MIN_EARLIER_LOOP_REPEAT_CHARS = 24
    private const val MIN_COMPLETE_PREFIX_FOR_TRIM_CHARS = 25

    private val CONTINUATION_DUPLICATE_FENCE_REGEX = Regex("""^```[a-zA-Z0-9]*\r?\n?""")
    private val SENTENCE_BOUNDARY_AFTER_PUNCT_REGEX = Regex("""[.!?。！？]["”’'\)\]\*_]*\s+""")
    private val SENTENCE_END_BEFORE_WHITESPACE_REGEX = Regex("""[.!?。！？]["”’'\)\]\*_]*(?=\s+\S)""")
    private val LIST_NUMBER_BEFORE_PERIOD_REGEX = Regex("""(?:^|\n)\s*\d+\.$""")
    private val LEADING_CONTINUATION_ELLIPSIS_REGEX = Regex("""^(?:\s*(?:…+|\.{2,}|\.(?:\s+\.){1,}))+\s*""")
    private val TRAILING_CONTINUATION_ELLIPSIS_REGEX = Regex("""(?:\s*(?:…+|\.{2,}|\.(?:\s+\.){1,}))+\s*$""")
    private val CONTRACTION_TRAILING_APOSTROPHE_REGEX = Regex("""[A-Za-z0-9]['’]$""")
    private val TERMINAL_PUNCTUATION_REGEX = Regex("""[.!?…"\x27”’`\)\]。！？]+$""")
    private val TRAILING_MARKDOWN_WITH_TERMINAL_REGEX = Regex("""[.!?…"\x27”’`\)\]。！？][*_]+$""")
    private val OPEN_MID_CLAUSE_TAIL_REGEX = Regex("""[,;:\-—(\[\{]$""")
    private val WHITESPACE_SPLIT_REGEX = Regex("""\s+""")
    private val MARKDOWN_JSON_BLOCK_REGEX = Regex("""```(?:json)?\s*([\s\S]*?)\s*(?:```|$)""", RegexOption.IGNORE_CASE)
    private val JSON_FENCE_OPEN_BRACE_REGEX = Regex("""```json\s*\{""", RegexOption.IGNORE_CASE)
    private val TOOL_DRAFT_HINT_REGEX = Regex(
        """(?:["']action["']\s*:\s*["']tool(?:\\?_)?call["']|["'](?:tool|method)["']\s*:|\{\s*["'](?:action|tool|method)["'])""",
        RegexOption.IGNORE_CASE
    )
    private val NAME_DRAFT_KEY_REGEX = Regex("""["']name["']\s*:""", RegexOption.IGNORE_CASE)
    private val TOOL_ARGS_OR_APP_HINT_REGEX = Regex(
        """["'](?:args|arguments|parameters|params|app)["']\s*:|["']name["']\s*:\s*["']?[a-z][a-z0-9]*(?:_[a-z0-9]+)+""",
        RegexOption.IGNORE_CASE
    )
    private val TOOL_KEY_PRESENT_REGEX = Regex("""["'](?:tool|name|method|action)["']\s*:""", RegexOption.IGNORE_CASE)
    private val TOOL_SECONDARY_KEY_PRESENT_REGEX = Regex(
        """["'](?:args|arguments|parameters|params|app|description)["']\s*:""",
        RegexOption.IGNORE_CASE
    )
    private val EMPTY_OBJECT_FALLBACK_KEYS = setOf("args", "arguments", "parameters", "params")
    private val CONTROL_TOOL_CALL_OPEN_REGEX = Regex(
        """<ctrl\d+>call:([a-zA-Z0-9_.:-]+)\s*\{"""
    )
    private val CONTROL_TOOL_STRIP_FULL_REGEX = Regex(
        """<ctrl\d+>call:[a-zA-Z0-9_.:-]+\s*\{[\s\S]*?\}(?:<ctrl\d+>)?"""
    )
    private val CONTROL_TOOL_STRIP_TAIL_REGEX = Regex("""<ctrl\d+>call:[\s\S]*$""")
    private val CONTROL_TAG_REGEX = Regex("""<ctrl\d+>""")
    private val LEADING_PAIOS_PREFIX_REGEX = Regex("""^\s*PAIOS:\s*""", RegexOption.IGNORE_CASE)
    private val JSON_DRAFT_TOOL_START_REGEX = Regex(
        """^\{\s*["'](?:tool|name|method|action)["']\s*:""",
        RegexOption.IGNORE_CASE
    )
    private val JSON_DRAFT_PROSE_BEFORE_TOOL_REGEX = Regex(
        """^[\s\S]{1,120}?(\{\s*["'](?:tool|name|method|action)["']\s*:)""",
        RegexOption.IGNORE_CASE
    )
    private val CLOSED_TOOL_VALUE_REGEX = Regex(
        """["'](?:tool|name|method)["']\s*:\s*["'][^"']+["']""",
        RegexOption.IGNORE_CASE
    )
    private val REQUIRED_TOOL_ARGS = mapOf(
        "wikipedia_summary" to listOf("query"),
        "wikipedia_details" to listOf("query", "question"),
        "duckduckgo_search" to listOf("query"),
        "query_aicore_documentation" to listOf("query"),
        "weather_forecast" to listOf("location")
    )

    private val DANGLING_TAIL_WORDS = setOf(
        "to", "and", "or", "but", "of", "the", "a", "an", "with", "for",
        "in", "on", "at", "by", "from", "into", "about", "as", "that",
        "which", "who", "your", "its", "their", "this", "these", "those",
        "my", "our", "is", "are", "was", "were", "can", "will", "would",
        "should", "could", "may", "might"
    )

    private val STRICT_TRAILING_DETERMINERS = setOf(
        "the", "a", "an", "your", "its", "their", "my", "our"
    )

    private val SHORT_DANGLING_PREPOSITIONS_CONJUNCTIONS = setOf(
        "for", "to", "with", "of", "in", "on", "at", "by", "from", "into",
        "and", "or", "but"
    )

    private val TRANSITIVE_TRAILING_PARTICIPLES = setOf(
        "ensuring", "including", "providing", "creating", "making",
        "requiring", "involving", "preventing", "maintaining", "developing",
        "building", "allowing", "enabling", "using"
    )

    private val PARTICIPLE_PRECEDING_TRIGGERS = setOf(
        "and", "or", "while", "by", "for", "of", "without", "to"
    )

    private val NON_PARTICIPLE_ING_WORDS = setOf(
        "thing", "something", "anything", "nothing", "everything",
        "morning", "evening", "spring", "string", "ceiling",
        "feeling", "meaning", "meeting", "during"
    )

    private val NEGATION_AUXILIARIES = setOf(
        "do", "does", "did", "will", "would", "can", "could", "should",
        "may", "might", "must", "is", "are", "was", "were", "have", "has", "had"
    )

    private val PRE_MODIFIER_TRIGGERS = setOf(
        "a", "an", "the", "of", "with", "for", "in", "on", "at", "by",
        "from", "into", "about", "as", "to", "your", "its", "their",
        "my", "our", "this", "these", "those"
    )

    private val EXPLICIT_MODIFIER_ADJECTIVES = setOf(
        "new", "old", "major", "minor", "main", "key", "own", "same",
        "other", "next", "global", "local", "digital", "personal",
        "general", "special", "complex", "modern", "future", "human",
        "rapid", "deep", "wide", "broad", "strong", "high", "low",
        "long", "short", "large", "small", "full", "real", "certain",
        "severe", "extreme", "likely", "common", "single", "double",
        "multiple", "entire", "whole", "several", "many", "various",
        "further", "more", "less", "such"
    )

    private val MODIFIER_NOUN_EXCLUSIONS = setOf(
        "student", "parent", "client", "patient", "agent", "event",
        "moment", "content", "comment", "percent", "library", "factory",
        "history", "memory", "story", "theory", "category", "territory",
        "hundred", "united"
    )

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

    data class ScreenContextTurnState(
        val available: Boolean,
        val nextTurnsRemaining: Int,
        val shouldExpire: Boolean
    )

    fun consumeScreenContextTurn(
        turnsRemaining: Int,
        hasContent: Boolean
    ): ScreenContextTurnState {
        if (turnsRemaining <= 0 || !hasContent) {
            return ScreenContextTurnState(
                available = false,
                nextTurnsRemaining = 0,
                shouldExpire = true
            )
        }
        val next = (turnsRemaining - 1).coerceAtLeast(0)
        return ScreenContextTurnState(
            available = true,
            nextTurnsRemaining = next,
            shouldExpire = next == 0
        )
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

    private fun isLikelyTrailingModifier(word: String): Boolean {
        if (word.length < 3) return false
        if (EXPLICIT_MODIFIER_ADJECTIVES.contains(word)) return true
        if (word.endsWith("ment") || MODIFIER_NOUN_EXCLUSIONS.contains(word)) return false
        return (word.length >= 5 && word.endsWith("ed") && !word.endsWith("eed")) ||
            word.endsWith("tial") ||
            word.endsWith("cial") ||
            word.endsWith("ical") ||
            word.endsWith("ant") ||
            word.endsWith("ent") ||
            word.endsWith("ous") ||
            word.endsWith("ive") ||
            word.endsWith("ful") ||
            word.endsWith("less") ||
            word.endsWith("ary") ||
            word.endsWith("ory") ||
            (word.length >= 7 && (word.endsWith("able") || word.endsWith("ible")))
    }

    fun isTruncationHeuristic(text: String): Boolean {
        val trimmed = text.trimEnd()
        if (trimmed.isEmpty()) return false
        if (OPEN_MID_CLAUSE_TAIL_REGEX.containsMatchIn(trimmed)) return true
        if (CONTRACTION_TRAILING_APOSTROPHE_REGEX.containsMatchIn(trimmed)) return true
        if (TRAILING_MARKDOWN_WITH_TERMINAL_REGEX.containsMatchIn(trimmed)) return false
        if (TERMINAL_PUNCTUATION_REGEX.containsMatchIn(trimmed)) return false

        val tokens = trimmed.split(WHITESPACE_SPLIT_REGEX).filter { it.isNotEmpty() }
        if (tokens.isEmpty()) return false
        val lastWord = tokens.last().trim { !it.isLetterOrDigit() }.lowercase(Locale.ROOT)
        if (lastWord.isEmpty()) return false

        val prevWord = if (tokens.size >= 2) {
            tokens[tokens.size - 2].trim { !it.isLetterOrDigit() }.lowercase(Locale.ROOT)
        } else {
            ""
        }

        if (TRANSITIVE_TRAILING_PARTICIPLES.contains(lastWord)) {
            return true
        }
        if (tokens.size >= 2 &&
            lastWord.length >= 5 &&
            lastWord.endsWith("ing") &&
            !NON_PARTICIPLE_ING_WORDS.contains(lastWord) &&
            PARTICIPLE_PRECEDING_TRIGGERS.contains(prevWord)
        ) {
            return true
        }
        if (tokens.size >= 2 && lastWord == "not" && NEGATION_AUXILIARIES.contains(prevWord)) {
            return true
        }

        if (tokens.size <= 3) {
            return STRICT_TRAILING_DETERMINERS.contains(lastWord) ||
                (tokens.size >= 2 && SHORT_DANGLING_PREPOSITIONS_CONJUNCTIONS.contains(lastWord))
        }
        if (DANGLING_TAIL_WORDS.contains(lastWord)) {
            return true
        }
        return PRE_MODIFIER_TRIGGERS.contains(prevWord) && isLikelyTrailingModifier(lastWord)
    }

    private fun isMeaningfulClauseForStutter(candidate: String): Boolean {
        val trimmed = candidate.trim()
        if (candidate.length < 12 || trimmed.length < 10) return false
        var alnumCount = 0
        val distinctChars = HashSet<Char>()
        for (ch in trimmed) {
            if (ch.isLetterOrDigit()) {
                alnumCount++
            }
            if (!ch.isWhitespace()) {
                distinctChars.add(ch.lowercaseChar())
            }
        }
        return alnumCount >= 6 && distinctChars.size >= 4
    }

    private fun findTrailingEarlierSentenceRepeatCutIndex(text: String): Int {
        val trimmed = text.trimEnd()
        if (trimmed.length < MIN_EARLIER_LOOP_REPEAT_CHARS * 2) return -1
        for (match in SENTENCE_BOUNDARY_AFTER_PUNCT_REGEX.findAll(trimmed)) {
            val clauseStart = match.range.last + 1
            if (clauseStart >= trimmed.length) continue
            val prefixWithSpace = trimmed.substring(0, clauseStart)
            val sentenceEndIdx = prefixWithSpace.trimEnd().length
            if (sentenceEndIdx < MIN_EARLIER_LOOP_REPEAT_CHARS) continue

            val trailingClause = trimmed.substring(clauseStart).trim()
            if (trailingClause.length < MIN_EARLIER_LOOP_REPEAT_CHARS) continue
            val minSeed = trailingClause.substring(0, MIN_EARLIER_LOOP_REPEAT_CHARS)
            if (!isMeaningfulClauseForStutter(minSeed)) continue

            var seedIdx = prefixWithSpace.indexOf(minSeed, ignoreCase = true)
            while (seedIdx >= 0) {
                val atBoundary = seedIdx == 0 || !prefixWithSpace[seedIdx - 1].isLetterOrDigit()
                if (atBoundary) {
                    return sentenceEndIdx
                }
                seedIdx = prefixWithSpace.indexOf(minSeed, seedIdx + 1, ignoreCase = true)
            }
        }
        return -1
    }

    private fun stripEarlierRepeatedPrefix(base: String, next: String): String {
        val trimmedNext = next.trimStart()
        if (trimmedNext.length < MIN_EARLIER_LOOP_REPEAT_CHARS ||
            base.length < MIN_EARLIER_LOOP_REPEAT_CHARS
        ) {
            return next
        }
        val seed = trimmedNext.substring(0, MIN_EARLIER_LOOP_REPEAT_CHARS)
        if (!isMeaningfulClauseForStutter(seed)) return next

        var bestMatchLen = 0
        var searchIdx = base.indexOf(seed, ignoreCase = true)
        while (searchIdx >= 0) {
            val atBoundary = searchIdx == 0 || !base[searchIdx - 1].isLetterOrDigit()
            if (atBoundary) {
                var len = MIN_EARLIER_LOOP_REPEAT_CHARS
                while (searchIdx + len < base.length &&
                    len < trimmedNext.length &&
                    base[searchIdx + len].equals(trimmedNext[len], ignoreCase = true)
                ) {
                    len++
                }
                if (len < trimmedNext.length &&
                    trimmedNext[len - 1].isLetterOrDigit() &&
                    trimmedNext[len].isLetterOrDigit()
                ) {
                    while (len > MIN_EARLIER_LOOP_REPEAT_CHARS && trimmedNext[len - 1].isLetterOrDigit()) {
                        len--
                    }
                }
                if (len > bestMatchLen) {
                    bestMatchLen = len
                }
            }
            searchIdx = base.indexOf(seed, searchIdx + 1, ignoreCase = true)
        }

        if (bestMatchLen < MIN_EARLIER_LOOP_REPEAT_CHARS) return next
        val matchedPrefix = trimmedNext.substring(0, bestMatchLen).trimEnd()
        val remainder = trimmedNext.substring(bestMatchLen).trimStart()
        if (remainder.isEmpty()) {
            return ""
        }
        val baseTrimmedEnd = base.trimEnd()
        val baseEndsAtSentence = TERMINAL_PUNCTUATION_REGEX.containsMatchIn(baseTrimmedEnd) ||
            TRAILING_MARKDOWN_WITH_TERMINAL_REGEX.containsMatchIn(baseTrimmedEnd)
        val matchedEndsAtSentence = TERMINAL_PUNCTUATION_REGEX.containsMatchIn(matchedPrefix) ||
            TRAILING_MARKDOWN_WITH_TERMINAL_REGEX.containsMatchIn(matchedPrefix)
        return if (!baseEndsAtSentence || matchedEndsAtSentence) {
            remainder
        } else {
            next
        }
    }

    fun trimTrailingIncompleteSentence(text: String): String {
        val trimmed = text.trimEnd()
        if (trimmed.isBlank()) return text
        if (Regex("```").findAll(trimmed).count() % 2 == 1) return text
        if (looksLikeIncompleteToolCall(trimmed)) return text

        val repeatedCutIdx = findTrailingEarlierSentenceRepeatCutIndex(trimmed)
        if (repeatedCutIdx >= MIN_COMPLETE_PREFIX_FOR_TRIM_CHARS) {
            val deduped = trimmed.substring(0, repeatedCutIdx).trimEnd()
            if (deduped.length >= MIN_COMPLETE_PREFIX_FOR_TRIM_CHARS && !isTruncationHeuristic(deduped)) {
                return deduped
            }
        }

        if (!isTruncationHeuristic(trimmed)) return text

        val matches = SENTENCE_END_BEFORE_WHITESPACE_REGEX.findAll(trimmed).toList()
        for (idx in matches.indices.reversed()) {
            val match = matches[idx]
            val candidatePrefix = trimmed.substring(0, match.range.last + 1).trimEnd()
            if (candidatePrefix.length < MIN_COMPLETE_PREFIX_FOR_TRIM_CHARS) continue
            if (LIST_NUMBER_BEFORE_PERIOD_REGEX.containsMatchIn(candidatePrefix)) continue
            if (!isTruncationHeuristic(candidatePrefix)) {
                return candidatePrefix
            }
        }
        return text
    }

    fun hasContinuationStutter(text: String): Boolean {
        val normalizedTail = text.trim().replace(MULTI_SPACE_REGEX, " ")
        if (normalizedTail.length < 36) return false
        if (findTrailingEarlierSentenceRepeatCutIndex(normalizedTail) > 0) {
            return true
        }
        val tail = if (normalizedTail.length > 600) {
            normalizedTail.substring(normalizedTail.length - 600)
        } else {
            normalizedTail
        }
        val tailWithSpace = "$tail "
        val n = tail.length
        val maxPatternLen = minOf(160, tailWithSpace.length / 3)
        for (len in 12..maxPatternLen) {
            val maxStart = tailWithSpace.length - len * 3
            for (start in maxStart downTo 0) {
                if (tailWithSpace[start] != tailWithSpace[start + len] ||
                    tailWithSpace[start] != tailWithSpace[start + len * 2]
                ) {
                    continue
                }
                if (!tailWithSpace.regionMatches(start, tailWithSpace, start + len, len)) continue
                if (!tailWithSpace.regionMatches(start, tailWithSpace, start + len * 2, len)) continue
                val candidate = tailWithSpace.substring(start, start + len)
                if (isMeaningfulClauseForStutter(candidate)) {
                    return true
                }
            }
            val maxPunctStart = n - len * 2 - 12
            for (start in maxPunctStart downTo 0) {
                if (!tail.regionMatches(start, tail, start + len, len)) continue
                val candidate = tail.substring(start, start + len)
                val trimmedEnd = candidate.trimEnd(',', '.', ';', ':', ' ')
                if (trimmedEnd.length >= 12 &&
                    start + len * 2 + trimmedEnd.length <= n &&
                    tail.regionMatches(start, tail, start + len * 2, trimmedEnd.length) &&
                    isMeaningfulClauseForStutter(trimmedEnd)
                ) {
                    return true
                }
            }
        }
        return false
    }

    fun shouldContinuePartialResponse(
        finishReason: String?,
        partialText: String,
        continuationCount: Int,
        lastRoundAddedChars: Int,
        isNanoV4: Boolean,
        maxContinuations: Int = MAX_OVERLAY_CONTINUATIONS,
        maxAccumulatedChars: Int = MAX_OVERLAY_ACCUMULATED_CHARS,
        nullReasonRetryCount: Int = 0,
        stopCutoffRetryCount: Int = 0,
        isToolDraft: Boolean = false
    ): Boolean {
        if (continuationCount >= maxContinuations) return false
        if (partialText.isBlank()) return false
        if (partialText.length >= maxAccumulatedChars) return false
        if (continuationCount > 0 && lastRoundAddedChars <= 0) return false
        if (hasContinuationStutter(partialText)) return false

        val normalized = normalizeFinishReason(finishReason)?.uppercase(Locale.ROOT)
        if (isToolDraft) {
            if (continuationCount >= MAX_TOOL_JSON_CONTINUATIONS) return false
            if (normalized == null) return true
            if (normalized == "0" || normalized == "STOP") return false
            return normalized == "1" ||
                normalized == "-100" ||
                normalized == "MAX_TOKENS" ||
                normalized == "LIMIT" ||
                normalized == "OTHER" ||
                normalized.contains("MAX_TOKENS") ||
                normalized.contains("LIMIT")
        }

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
                return !isNanoV4 &&
                    stopCutoffRetryCount < MAX_STOP_CUTOFF_RETRIES &&
                    partialText.length < MAX_STOP_CUTOFF_RESCUE_CHARS &&
                    isTruncationHeuristic(partialText)
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

    fun stripLeadingAssistantLabel(text: String): String {
        if (text.isEmpty()) return text
        return text.replaceFirst(LEADING_PAIOS_PREFIX_REGEX, "")
    }

    fun stripControlToolTags(text: String): String {
        if (text.isEmpty() || !text.contains("<ctrl", ignoreCase = true)) return text
        var cleaned = text.replace(CONTROL_TOOL_STRIP_FULL_REGEX, "")
        cleaned = cleaned.replace(CONTROL_TOOL_STRIP_TAIL_REGEX, "")
        cleaned = cleaned.replace(CONTROL_TAG_REGEX, "")
        return cleaned.trim()
    }

    private fun hasUnclosedJsonString(text: String): Boolean {
        var inDoubleQuote = false
        var escaped = false
        for (ch in text) {
            if (escaped) {
                escaped = false
            } else if (inDoubleQuote) {
                if (ch == '\\') {
                    escaped = true
                } else if (ch == '"') {
                    inDoubleQuote = false
                }
            } else if (ch == '"') {
                inDoubleQuote = true
            }
        }
        return inDoubleQuote
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
        val boundedTail = boundTailAtBoundary(partialText, maxTailChars)
        if (isJsonDraft) {
            val openString = hasUnclosedJsonString(boundedTail)
            val sysBlock = buildString {
                append("## [CONTINUATION]\n")
                append("Partial JSON tail:\n")
                append(boundedTail)
                if (openString) {
                    append("\nComplete ONLY the remaining JSON characters from the exact end (close the open string quote and braces). Do not restart or add markdown.")
                } else {
                    append("\nComplete ONLY the remaining JSON characters from the exact end to close the JSON object. Do not restart or add markdown.")
                }
            }
            return ContinuationPrompt(instructions = sysBlock, userPrompt = "Continue.")
        }

        val boundedPersona = personaAnchor?.let { boundHeadAtBoundary(it, 240) }.orEmpty()
        val boundedQuestion = boundHeadAtBoundary(originalQuestion, maxQuestionChars)
        val trailingWordToken = if (boundedTail.isNotEmpty() && boundedTail.last().isLetterOrDigit()) {
            var start = boundedTail.length
            while (start > 0 && !boundedTail[start - 1].isWhitespace()) {
                start--
            }
            boundedTail.substring(start).takeIf { it.isNotEmpty() && it.length <= MID_WORD_BACKOFF_MAX_CHARS }
        } else {
            null
        }
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
            if (trailingWordToken != null) {
                append(" If '$trailingWordToken' was cut mid-word, complete or rewrite it cleanly without spaces.")
            }
            append(" Do NOT prepend an ellipsis (...) or repeat words. Complete the answer concisely without starting new unrelated topics.")
        }
        return ContinuationPrompt(instructions = sysBlock, userPrompt = "Continue.")
    }

    private fun countUnclosedJsonBraces(text: String): Int {
        var depth = 0
        var quote: Char? = null
        var escaped = false
        for (ch in text) {
            if (escaped) {
                escaped = false
                continue
            }
            if (quote != null) {
                if (ch == '\\') {
                    escaped = true
                } else if (ch == quote) {
                    quote = null
                }
                continue
            }
            when (ch) {
                '"', '\'' -> quote = ch
                '{' -> depth++
                '}' -> if (depth > 0) depth--
            }
        }
        return depth
    }

    private fun findSuffixPrefixOverlap(
        base: String,
        next: String,
        allowSingleClosingOverlap: Boolean = false
    ): Int {
        val maxOverlap = minOf(MAX_CONTINUATION_OVERLAP_CHARS, base.length, next.length)
        for (len in maxOverlap downTo 2) {
            val ignoreCase = len >= 8
            if (base.regionMatches(base.length - len, next, 0, len, ignoreCase = ignoreCase)) {
                val boundaryBefore = base.length == len || !base[base.length - len - 1].isLetterOrDigit()
                val boundaryAfterNext = next.length == len || !next[len].isLetterOrDigit()
                val validMatch = when {
                    len >= 8 -> true
                    len >= 3 -> boundaryBefore
                    else -> boundaryBefore && boundaryAfterNext
                }
                if (validMatch) {
                    return len
                }
            }
        }
        if (allowSingleClosingOverlap && base.isNotEmpty() && next.isNotEmpty()) {
            if (base.last() == '"' && next.first() == '"' && !base.endsWith("\\\"")) {
                return 1
            }
            if (base.last() == '}' && next.first() == '}') {
                var leadingCloses = 0
                while (leadingCloses < next.length && next[leadingCloses] == '}') {
                    leadingCloses++
                }
                val unclosed = countUnclosedJsonBraces(base)
                if (unclosed == 0 || leadingCloses > unclosed) {
                    return 1
                }
            }
        }
        return 0
    }

    fun stitchOverlayContinuation(existing: String, incoming: String): String {
        if (incoming.isEmpty()) return existing
        if (existing.isEmpty()) return incoming

        var next = stripLeadingContinuationEllipsis(incoming)
        if (next.isEmpty()) return existing

        val trimmedExistingLeft = existing.trimStart()
        val isJsonDraft = looksLikeIncompleteToolCall(existing) ||
            trimmedExistingLeft.startsWith("{") ||
            trimmedExistingLeft.startsWith("```json", ignoreCase = true) ||
            (TOOL_KEY_PRESENT_REGEX.containsMatchIn(trimmedExistingLeft) &&
                TOOL_SECONDARY_KEY_PRESENT_REGEX.containsMatchIn(trimmedExistingLeft))

        if (isJsonDraft) {
            next = stripLeadingAssistantLabel(next)
            next = next.replaceFirst(CONTINUATION_DUPLICATE_FENCE_REGEX, "")
            val proseBeforeTool = JSON_DRAFT_PROSE_BEFORE_TOOL_REGEX.find(next)
            if (proseBeforeTool != null) {
                val braceIdx = proseBeforeTool.groups[1]?.range?.first ?: -1
                if (braceIdx > 0) {
                    next = next.substring(braceIdx)
                }
            }
            if (next.isEmpty()) return existing
        }

        val base = if (isJsonDraft) {
            existing
        } else {
            existing.replaceFirst(TRAILING_CONTINUATION_ELLIPSIS_REGEX, "")
        }
        if (base.isEmpty()) return next

        val openCodeFence = Regex("```").findAll(base).count() % 2 == 1
        if (openCodeFence) {
            next = next.replaceFirst(CONTINUATION_DUPLICATE_FENCE_REGEX, "")
            if (next.isEmpty()) return existing
        }

        var stitchedBase = base
        if (isJsonDraft) {
            val trimmedNextStart = next.trimStart()
            if (JSON_DRAFT_TOOL_START_REGEX.containsMatchIn(trimmedNextStart)) {
                val restartOverlap = findSuffixPrefixOverlap(
                    stitchedBase,
                    trimmedNextStart,
                    allowSingleClosingOverlap = true
                )
                if (restartOverlap > 0) {
                    val remainder = trimmedNextStart.substring(restartOverlap)
                    return if (remainder.isEmpty()) existing else stitchedBase + remainder
                }
                if (extractToolCallJson(trimmedNextStart, allowTruncatedRepair = false) != null ||
                    trimmedNextStart.length > stitchedBase.length
                ) {
                    return trimmedNextStart
                }
            }
        }

        // Trim exact suffix-prefix overlap (up to 240 chars) if the model echoed the tail
        var overlapLen = findSuffixPrefixOverlap(
            stitchedBase,
            next,
            allowSingleClosingOverlap = isJsonDraft
        )
        if (overlapLen == 0 && stitchedBase.last().isWhitespace()) {
            val trimmedBase = stitchedBase.trimEnd()
            if (trimmedBase.isNotEmpty()) {
                val trimmedOverlap = findSuffixPrefixOverlap(
                    trimmedBase,
                    next,
                    allowSingleClosingOverlap = isJsonDraft
                )
                if (trimmedOverlap > 0) {
                    stitchedBase = trimmedBase
                    overlapLen = trimmedOverlap
                }
            }
        }
        if (overlapLen > 0) {
            next = next.substring(overlapLen)
        }
        var strippedEllipsisAfterOverlap = false
        if (!isJsonDraft && overlapLen > 0) {
            val afterEllipsis = stripLeadingContinuationEllipsis(next)
            if (afterEllipsis != next) {
                next = afterEllipsis
                strippedEllipsisAfterOverlap = true
            }
        }
        if (!isJsonDraft && overlapLen == 0 && !openCodeFence) {
            val baseTrimmedEnd = stitchedBase.trimEnd()
            val baseEndsAtSentence = TERMINAL_PUNCTUATION_REGEX.containsMatchIn(baseTrimmedEnd) ||
                TRAILING_MARKDOWN_WITH_TERMINAL_REGEX.containsMatchIn(baseTrimmedEnd)
            if (baseEndsAtSentence) {
                val afterEarlierPrefix = stripEarlierRepeatedPrefix(stitchedBase, next)
                if (afterEarlierPrefix.isEmpty()) {
                    return baseTrimmedEnd
                }
                next = afterEarlierPrefix
            }
        }
        if (next.isEmpty()) return existing

        if (isJsonDraft) {
            return stitchedBase + next
        }

        if (overlapLen > 0 && !strippedEllipsisAfterOverlap) {
            val joinedOverlap = stitchedBase + next
            if (!openCodeFence) {
                val cutIdx = findTrailingEarlierSentenceRepeatCutIndex(joinedOverlap)
                if (cutIdx > 0) {
                    return joinedOverlap.substring(0, cutIdx).trimEnd()
                }
            }
            return joinedOverlap
        }

        val lastChar = stitchedBase.last()
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
            if (endsWithSpace || startsWithSpace) "" else "\n"
        } else if (endsWithSpace || startsWithSpace || endsWithJoiningPunct || startsWithPunctuation) {
            ""
        } else {
            " "
        }

        val stitchedResult = stitchedBase + separator + next
        if (!openCodeFence) {
            val cutIdx = findTrailingEarlierSentenceRepeatCutIndex(stitchedResult)
            if (cutIdx > 0) {
                return stitchedResult.substring(0, cutIdx).trimEnd()
            }
        }
        return stitchedResult
    }

    data class ParsedToolCall(
        val tool: String,
        val app: String,
        val description: String,
        val args: Map<String, Any?>,
        val raw: Map<String, Any?>
    ) {
        fun toJsonObject(): JSONObject = mapToJsonObject(raw)
    }

    fun looksLikeIncompleteToolCall(text: String): Boolean {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return false
        if (extractToolCallJson(trimmed, allowTruncatedRepair = false) != null) return false

        if (CONTROL_TOOL_CALL_OPEN_REGEX.containsMatchIn(trimmed)) {
            return true
        }

        for (match in JSON_FENCE_OPEN_BRACE_REGEX.findAll(text)) {
            val braceStart = text.indexOf('{', match.range.first)
            if (braceStart != -1 && findMatchingBrace(text, braceStart) == -1) {
                return true
            }
        }
        if (trimmed.startsWith("```json", ignoreCase = true) && !trimmed.contains("```", ignoreCase = false).let {
                trimmed.indexOf("```", startIndex = 3) != -1
            } && !trimmed.contains('{')
        ) {
            return true
        }

        val firstNonWs = text.indexOfFirst { !it.isWhitespace() }
        var i = 0
        while (i < text.length) {
            if (text[i] != '{') {
                i++
                continue
            }
            val end = findMatchingBrace(text, i)
            if (end != -1) {
                i = end + 1
                continue
            }
            val tail = text.substring(i)
            if (i == firstNonWs && tail.trim() == "{") {
                return true
            }
            if (TOOL_DRAFT_HINT_REGEX.containsMatchIn(tail)) {
                return true
            }
            if (NAME_DRAFT_KEY_REGEX.containsMatchIn(tail) &&
                TOOL_ARGS_OR_APP_HINT_REGEX.containsMatchIn(tail)
            ) {
                return true
            }
            i++
        }
        return false
    }

    fun extractToolCallJson(text: String, allowTruncatedRepair: Boolean = true): ParsedToolCall? {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return null

        for (match in MARKDOWN_JSON_BLOCK_REGEX.findAll(trimmed)) {
            val block = match.groupValues[1].trim()
            val parsed = scanBalancedToolObjects(block)
            if (parsed != null) return parsed
        }
        val balanced = scanBalancedToolObjects(trimmed)
        if (balanced != null) return balanced

        val controlCall = parseControlToolCalls(trimmed, allowTruncatedRepair)
        if (controlCall != null) return controlCall

        if (allowTruncatedRepair) {
            return repairTruncatedToolJson(trimmed)
        }
        return null
    }

    private fun parseControlToolCalls(source: String, allowTruncatedRepair: Boolean): ParsedToolCall? {
        if (!source.contains("<ctrl", ignoreCase = true)) return null
        for (match in CONTROL_TOOL_CALL_OPEN_REGEX.findAll(source)) {
            val rawTarget = match.groupValues[1].trim()
            if (rawTarget.isEmpty()) continue
            val braceStart = match.range.last
            val braceEnd = findMatchingBrace(source, braceStart)
            val isRepaired: Boolean
            val candidateArgs = if (braceEnd != -1) {
                isRepaired = false
                source.substring(braceStart, braceEnd + 1)
            } else if (allowTruncatedRepair) {
                isRepaired = true
                val rawTail = source.substring(braceStart)
                val nextCtrl = CONTROL_TAG_REGEX.find(rawTail)?.range?.first ?: rawTail.length
                closeTruncatedJsonObject(rawTail.substring(0, nextCtrl)) ?: continue
            } else {
                continue
            }

            val argsMap = parseJsonLikeObject(candidateArgs) ?: continue
            val (resolvedApp, resolvedTool) = if (rawTarget.contains(':')) {
                val parts = rawTarget.split(':', limit = 2)
                parts[0].trim().ifEmpty { "paios" } to parts[1].trim()
            } else {
                "paios" to rawTarget
            }
            if (resolvedTool.isEmpty()) continue

            val rawMap = LinkedHashMap<String, Any?>().apply {
                put("tool", resolvedTool)
                put("app", resolvedApp)
                put("args", argsMap)
            }
            val parsed = normalizeToolCall(rawMap)
            if (!isRepaired || hasSatisfiedRequiredArgs(parsed)) {
                return parsed
            }
        }
        return null
    }

    fun repairTruncatedToolJson(text: String): ParsedToolCall? {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return null

        for (match in MARKDOWN_JSON_BLOCK_REGEX.findAll(trimmed)) {
            val block = match.groupValues[1].trim()
            val repaired = scanAndRepairTruncatedToolObjects(block)
            if (repaired != null) return repaired
        }
        return scanAndRepairTruncatedToolObjects(trimmed)
    }

    private fun scanAndRepairTruncatedToolObjects(source: String): ParsedToolCall? {
        var i = 0
        while (i < source.length) {
            if (source[i] != '{') {
                i++
                continue
            }
            val end = findMatchingBrace(source, i)
            if (end != -1) {
                i = end + 1
                continue
            }
            val tail = source.substring(i)
            if (CLOSED_TOOL_VALUE_REGEX.containsMatchIn(tail)) {
                val closedJson = closeTruncatedJsonObject(tail)
                if (closedJson != null) {
                    val parsed = tryParseToolObject(closedJson)
                    if (parsed != null && hasSatisfiedRequiredArgs(parsed)) {
                        return parsed
                    }
                }
            }
            i++
        }
        return null
    }

    private fun closeTruncatedJsonObject(raw: String): String? {
        if (!raw.startsWith("{")) return null
        val stack = ArrayList<Char>()
        var quote: Char? = null
        var escaped = false

        for (ch in raw) {
            if (escaped) {
                escaped = false
                continue
            }
            if (quote != null) {
                if (ch == '\\') {
                    escaped = true
                } else if (ch == quote) {
                    quote = null
                }
                continue
            }
            when (ch) {
                '"', '\'' -> quote = ch
                '{' -> stack.add('{')
                '[' -> stack.add('[')
                '}' -> {
                    if (stack.lastOrNull() == '{') {
                        stack.removeAt(stack.lastIndex)
                    } else {
                        return null
                    }
                }
                ']' -> {
                    if (stack.lastOrNull() == '[') {
                        stack.removeAt(stack.lastIndex)
                    } else {
                        return null
                    }
                }
            }
        }
        if (stack.isEmpty()) return raw

        val sb = StringBuilder(raw.length + stack.size + 4)
        sb.append(raw)
        if (escaped && sb.isNotEmpty() && sb[sb.length - 1] == '\\') {
            sb.setLength(sb.length - 1)
        }
        if (quote != null) {
            sb.append(quote)
        }

        while (sb.isNotEmpty() && sb[sb.length - 1].isWhitespace()) {
            sb.setLength(sb.length - 1)
        }
        while (sb.isNotEmpty()) {
            val last = sb[sb.length - 1]
            if (last == ',') {
                sb.setLength(sb.length - 1)
                while (sb.isNotEmpty() && sb[sb.length - 1].isWhitespace()) {
                    sb.setLength(sb.length - 1)
                }
                continue
            }
            if (last == ':') {
                val prefixBeforeColon = sb.substring(0, sb.length - 1).trimEnd()
                val endsWithEmptyObjKey = EMPTY_OBJECT_FALLBACK_KEYS.any { key ->
                    prefixBeforeColon.endsWith("\"$key\"") || prefixBeforeColon.endsWith("'$key'")
                }
                if (endsWithEmptyObjKey) {
                    sb.append("{}")
                } else {
                    sb.setLength(sb.length - 1)
                    while (sb.isNotEmpty() && sb[sb.length - 1].isWhitespace()) {
                        sb.setLength(sb.length - 1)
                    }
                }
                break
            }
            break
        }

        for (idx in stack.lastIndex downTo 0) {
            sb.append(if (stack[idx] == '[') ']' else '}')
        }
        return sb.toString()
    }

    private fun hasSatisfiedRequiredArgs(parsed: ParsedToolCall): Boolean {
        val toolKey = parsed.tool.trim().lowercase(Locale.ROOT)
        if (toolKey.isEmpty()) return false
        val required = REQUIRED_TOOL_ARGS[toolKey] ?: return true
        return required.all { reqKey ->
            val value = parsed.args[reqKey] ?: return@all false
            when (value) {
                is String -> value.trim().isNotEmpty()
                else -> true
            }
        }
    }

    private fun parseJsonLikeObject(candidate: String): Map<String, Any?>? {
        val attempts = listOf(
            candidate,
            sanitizeJsonLikeString(candidate, convertSingleQuotes = false),
            sanitizeJsonLikeString(candidate, convertSingleQuotes = true)
        )
        for (attempt in attempts) {
            val parsedMap = runCatching { SimpleJsonParser(attempt).parseObjectRoot() }.getOrNull()
            if (parsedMap != null) return parsedMap
        }
        return null
    }

    fun scanBalancedToolObjects(source: String): ParsedToolCall? {
        var i = 0
        while (i < source.length) {
            if (source[i] != '{') {
                i++
                continue
            }
            val end = findMatchingBrace(source, i)
            if (end == -1) {
                i++
                continue
            }
            val candidate = source.substring(i, end + 1)
            val parsed = tryParseToolObject(candidate)
            if (parsed != null) return parsed
            i = end + 1
        }
        return null
    }

    fun findMatchingBrace(source: String, start: Int): Int {
        var depth = 0
        var quote: Char? = null
        var escaped = false
        for (i in start until source.length) {
            val ch = source[i]
            if (escaped) {
                escaped = false
                continue
            }
            if (quote != null) {
                if (ch == '\\') {
                    escaped = true
                } else if (ch == quote) {
                    quote = null
                }
                continue
            }
            when (ch) {
                '"', '\'' -> quote = ch
                '{' -> depth++
                '}' -> {
                    depth--
                    if (depth == 0) return i
                }
            }
        }
        return -1
    }

    fun tryParseToolObject(candidate: String): ParsedToolCall? {
        val attempts = listOf(
            candidate,
            sanitizeJsonLikeString(candidate, convertSingleQuotes = false),
            sanitizeJsonLikeString(candidate, convertSingleQuotes = true)
        )
        for (attempt in attempts) {
            val parsedMap = runCatching { SimpleJsonParser(attempt).parseObjectRoot() }.getOrNull()
                ?: continue
            if (isToolCallObject(parsedMap)) {
                return normalizeToolCall(parsedMap)
            }
        }
        return null
    }

    fun isToolCallObject(obj: Map<String, Any?>): Boolean {
        val action = (obj["action"] as? String)?.trim()?.lowercase(Locale.ROOT)
        if (action == "tool_call" || action == "tool\\_call") return true

        val tool = (obj["tool"] as? String)?.trim()
        if (!tool.isNullOrEmpty()) return true

        val hasContainerOrMeta = obj.containsKey("args") ||
            obj.containsKey("arguments") ||
            obj.containsKey("parameters") ||
            obj.containsKey("params") ||
            obj.containsKey("app")

        val method = (obj["method"] as? String)?.trim()
        if (!method.isNullOrEmpty() && (hasContainerOrMeta || obj.containsKey("description"))) {
            return true
        }

        val name = (obj["name"] as? String)?.trim()
        if (!name.isNullOrEmpty() && hasContainerOrMeta) {
            return true
        }

        return false
    }

    private fun normalizeToolCall(rawMap: Map<String, Any?>): ParsedToolCall {
        val normalized = LinkedHashMap(rawMap)
        val resolvedTool = listOf("tool", "name", "method")
            .firstNotNullOfOrNull { key ->
                (normalized[key] as? String)?.trim()?.takeIf { it.isNotEmpty() }
            } ?: ""
        if (resolvedTool.isNotEmpty() &&
            (normalized["tool"] as? String)?.trim().isNullOrEmpty()
        ) {
            normalized["tool"] = resolvedTool
        }

        val resolvedApp = (normalized["app"] as? String)?.trim()?.takeIf { it.isNotEmpty() } ?: "paios"
        val resolvedDesc = (normalized["description"] as? String)?.trim() ?: ""

        @Suppress("UNCHECKED_CAST")
        val resolvedArgs: Map<String, Any?> = listOf("args", "arguments", "parameters", "params")
            .firstNotNullOfOrNull { key ->
                normalized[key] as? Map<String, Any?>
            } ?: emptyMap()

        if (normalized["args"] !is Map<*, *> &&
            listOf("arguments", "parameters", "params").any { normalized[it] is Map<*, *> }
        ) {
            normalized["args"] = resolvedArgs
        }

        return ParsedToolCall(
            tool = resolvedTool,
            app = resolvedApp,
            description = resolvedDesc,
            args = resolvedArgs,
            raw = normalized
        )
    }

    fun sanitizeJsonLikeString(raw: String, convertSingleQuotes: Boolean = false): String {
        val normalizedEscapes = raw.replace("\\_", "_")
        val quotedKeys = quoteUnquotedObjectKeys(normalizedEscapes)
        val escaped = escapeControlCharsAndQuotes(quotedKeys, convertSingleQuotes)
        val withValues = repairMissingPropertyValues(escaped)
        val withoutTrailingCommas = stripTrailingCommasOutsideStrings(withValues)
        return stripDanglingObjectKeys(withoutTrailingCommas)
    }

    private fun quoteUnquotedObjectKeys(raw: String): String {
        val out = StringBuilder(raw.length + 16)
        val containerStack = ArrayList<Char>()
        var quote: Char? = null
        var escaped = false
        var expectingKey = false
        var i = 0

        while (i < raw.length) {
            val ch = raw[i]
            if (quote != null) {
                out.append(ch)
                if (escaped) {
                    escaped = false
                } else if (ch == '\\') {
                    escaped = true
                } else if (ch == quote) {
                    quote = null
                    expectingKey = false
                }
                i++
                continue
            }
            if (ch == '"' || ch == '\'') {
                quote = ch
                out.append(ch)
                i++
                continue
            }
            if (ch == '{') {
                containerStack.add('{')
                expectingKey = true
                out.append(ch)
                i++
                continue
            }
            if (ch == '[') {
                containerStack.add('[')
                expectingKey = false
                out.append(ch)
                i++
                continue
            }
            if (ch == '}' || ch == ']') {
                if (containerStack.isNotEmpty()) {
                    containerStack.removeAt(containerStack.lastIndex)
                }
                expectingKey = false
                out.append(ch)
                i++
                continue
            }
            if (ch == ',') {
                expectingKey = containerStack.lastOrNull() == '{'
                out.append(ch)
                i++
                continue
            }
            if (expectingKey && (ch.isLetter() || ch == '_')) {
                var j = i + 1
                while (j < raw.length && (raw[j].isLetterOrDigit() || raw[j] == '_')) {
                    j++
                }
                var k = j
                while (k < raw.length && raw[k].isWhitespace()) {
                    k++
                }
                if (k < raw.length && raw[k] == ':') {
                    out.append('"').append(raw, i, j).append('"')
                    expectingKey = false
                    i = j
                    continue
                }
            }
            if (!ch.isWhitespace()) {
                expectingKey = false
            }
            out.append(ch)
            i++
        }
        return out.toString()
    }

    private fun escapeControlCharsAndQuotes(raw: String, convertSingleQuotes: Boolean): String {
        val out = StringBuilder(raw.length)
        var quote: Char? = null
        var i = 0
        while (i < raw.length) {
            val ch = raw[i]
            if (quote != null) {
                if (ch == '\\' && i + 1 < raw.length) {
                    val next = raw[i + 1]
                    if (convertSingleQuotes && quote == '\'' && next == '\'') {
                        out.append('\'')
                        i += 2
                        continue
                    }
                    out.append(ch).append(next)
                    i += 2
                    continue
                }
                if (ch == '\r') {
                    if (i + 1 < raw.length && raw[i + 1] == '\n') {
                        i++
                    }
                    out.append("\\n")
                    i++
                    continue
                }
                if (ch == '\n') {
                    out.append("\\n")
                    i++
                    continue
                }
                if (ch == '\t') {
                    out.append("\\t")
                    i++
                    continue
                }
                if (ch == quote) {
                    if (quote == '\'' && convertSingleQuotes && i + 1 < raw.length) {
                        val next = raw[i + 1]
                        if (next.isLetterOrDigit() || next == ' ') {
                            out.append('\'')
                            i++
                            continue
                        }
                    }
                    out.append(if (convertSingleQuotes) '"' else ch)
                    quote = null
                    i++
                    continue
                }
                if (convertSingleQuotes && quote == '\'' && ch == '"') {
                    out.append("\\\"")
                    i++
                    continue
                }
                out.append(ch)
                i++
                continue
            }
            if (ch == '"' || (convertSingleQuotes && ch == '\'')) {
                quote = ch
                out.append(if (convertSingleQuotes) '"' else ch)
                i++
                continue
            }
            out.append(ch)
            i++
        }
        return out.toString()
    }

    private fun repairMissingPropertyValues(input: String): String {
        val out = StringBuilder(input.length)
        var quote: Char? = null
        var escaped = false
        var currentStringStart = -1
        var lastKey: String? = null

        for (i in input.indices) {
            val ch = input[i]
            if (quote != null) {
                out.append(ch)
                if (escaped) {
                    escaped = false
                } else if (ch == '\\') {
                    escaped = true
                } else if (ch == quote) {
                    if (currentStringStart >= 0) {
                        lastKey = input.substring(currentStringStart + 1, i)
                        currentStringStart = -1
                    }
                    quote = null
                }
                continue
            }
            if (ch == '"' || ch == '\'') {
                quote = ch
                currentStringStart = i
                out.append(ch)
                continue
            }
            if (ch == ':') {
                out.append(ch)
                var j = i + 1
                while (j < input.length && input[j].isWhitespace()) {
                    j++
                }
                if (j < input.length && (input[j] == ',' || input[j] == '}' || input[j] == ']')) {
                    val fallback = if (lastKey != null && EMPTY_OBJECT_FALLBACK_KEYS.contains(lastKey)) {
                        "{}"
                    } else {
                        "null"
                    }
                    out.append(fallback)
                }
                lastKey = null
                continue
            }
            if (!ch.isWhitespace()) {
                lastKey = null
            }
            out.append(ch)
        }
        return out.toString()
    }

    private fun stripTrailingCommasOutsideStrings(input: String): String {
        val out = StringBuilder(input.length)
        var quote: Char? = null
        var escaped = false

        for (i in input.indices) {
            val ch = input[i]
            if (quote != null) {
                out.append(ch)
                if (escaped) {
                    escaped = false
                } else if (ch == '\\') {
                    escaped = true
                } else if (ch == quote) {
                    quote = null
                }
                continue
            }
            if (ch == '"' || ch == '\'') {
                quote = ch
                out.append(ch)
                continue
            }
            if (ch == ',') {
                var j = i + 1
                while (j < input.length && input[j].isWhitespace()) {
                    j++
                }
                if (j < input.length && (input[j] == '}' || input[j] == ']')) {
                    continue
                }
            }
            out.append(ch)
        }
        return out.toString()
    }

    private fun stripDanglingObjectKeys(input: String): String {
        val out = StringBuilder(input.length)
        val containerStack = ArrayList<Char>()
        var lastSignificant = '\u0000'
        var quote: Char? = null
        var escaped = false
        var i = 0

        while (i < input.length) {
            val ch = input[i]
            if (quote != null) {
                out.append(ch)
                if (escaped) {
                    escaped = false
                } else if (ch == '\\') {
                    escaped = true
                } else if (ch == quote) {
                    quote = null
                    lastSignificant = 's'
                }
                i++
                continue
            }

            if (ch == ',') {
                if (containerStack.lastOrNull() == '{') {
                    val afterDangling = findDanglingObjectKeyEnd(input, i + 1)
                    if (afterDangling != null) {
                        i = afterDangling
                        continue
                    }
                }
                lastSignificant = ','
                out.append(ch)
                i++
                continue
            }

            if (ch == '"' || ch == '\'') {
                if (containerStack.lastOrNull() == '{' && lastSignificant == '{') {
                    val afterDangling = findDanglingObjectKeyEnd(input, i)
                    if (afterDangling != null) {
                        i = afterDangling
                        continue
                    }
                }
                quote = ch
                out.append(ch)
                i++
                continue
            }

            if (ch == '{' || ch == '[') {
                containerStack.add(ch)
                lastSignificant = ch
                out.append(ch)
                i++
                continue
            }

            if (ch == '}' || ch == ']') {
                if (containerStack.isNotEmpty()) {
                    containerStack.removeAt(containerStack.lastIndex)
                }
                lastSignificant = ch
                out.append(ch)
                i++
                continue
            }

            if (!ch.isWhitespace()) {
                lastSignificant = ch
            }
            out.append(ch)
            i++
        }
        return out.toString()
    }

    private fun findDanglingObjectKeyEnd(input: String, startIndex: Int): Int? {
        var j = startIndex
        while (j < input.length && input[j].isWhitespace()) {
            j++
        }
        if (j >= input.length) return null
        val quote = input[j]
        if (quote != '"' && quote != '\'') return null

        j++
        var escaped = false
        while (j < input.length) {
            val ch = input[j]
            if (escaped) {
                escaped = false
            } else if (ch == '\\') {
                escaped = true
            } else if (ch == quote) {
                break
            }
            j++
        }
        if (j >= input.length || input[j] != quote) return null

        j++
        while (j < input.length && input[j].isWhitespace()) {
            j++
        }
        return if (j < input.length && input[j] == '}') j else null
    }

    private fun toJsonValue(value: Any?): Any = when (value) {
        null -> JSONObject.NULL
        is Map<*, *> -> {
            val obj = JSONObject()
            for ((k, v) in value) {
                if (k != null) {
                    obj.put(k.toString(), toJsonValue(v))
                }
            }
            obj
        }
        is List<*> -> {
            val arr = JSONArray()
            for (item in value) {
                arr.put(toJsonValue(item))
            }
            arr
        }
        else -> value
    }

    fun mapToJsonObject(map: Map<String, Any?>): JSONObject {
        val obj = JSONObject()
        for ((k, v) in map) {
            obj.put(k, toJsonValue(v))
        }
        return obj
    }

    private class SimpleJsonParser(private val input: String) {
        private var pos = 0

        fun parseObjectRoot(): Map<String, Any?>? {
            skipWhitespace()
            if (pos >= input.length || input[pos] != '{') return null
            val obj = parseObject() ?: return null
            skipWhitespace()
            if (pos != input.length) return null
            return obj
        }

        private fun parseValue(): Any? {
            skipWhitespace()
            if (pos >= input.length) throw IllegalArgumentException("Unexpected end of JSON")
            return when (val ch = input[pos]) {
                '{' -> parseObject() ?: throw IllegalArgumentException("Invalid object")
                '[' -> parseArray()
                '"' -> parseString()
                't' -> parseLiteral("true", true)
                'f' -> parseLiteral("false", false)
                'n' -> parseLiteral("null", null)
                '-', in '0'..'9' -> parseNumber()
                else -> throw IllegalArgumentException("Unexpected char '$ch' at $pos")
            }
        }

        private fun parseObject(): Map<String, Any?>? {
            if (pos >= input.length || input[pos] != '{') return null
            pos++
            skipWhitespace()
            val result = LinkedHashMap<String, Any?>()
            if (pos < input.length && input[pos] == '}') {
                pos++
                return result
            }
            while (true) {
                skipWhitespace()
                if (pos >= input.length || input[pos] != '"') {
                    throw IllegalArgumentException("Expected object key at $pos")
                }
                val key = parseString()
                skipWhitespace()
                if (pos >= input.length || input[pos] != ':') {
                    throw IllegalArgumentException("Expected ':' after key at $pos")
                }
                pos++
                val value = parseValue()
                result[key] = value
                skipWhitespace()
                if (pos >= input.length) throw IllegalArgumentException("Unterminated object")
                when (input[pos]) {
                    ',' -> pos++
                    '}' -> {
                        pos++
                        return result
                    }
                    else -> throw IllegalArgumentException("Expected ',' or '}' at $pos")
                }
            }
        }

        private fun parseArray(): List<Any?> {
            pos++
            skipWhitespace()
            val result = ArrayList<Any?>()
            if (pos < input.length && input[pos] == ']') {
                pos++
                return result
            }
            while (true) {
                result.add(parseValue())
                skipWhitespace()
                if (pos >= input.length) throw IllegalArgumentException("Unterminated array")
                when (input[pos]) {
                    ',' -> pos++
                    ']' -> {
                        pos++
                        return result
                    }
                    else -> throw IllegalArgumentException("Expected ',' or ']' at $pos")
                }
            }
        }

        private fun parseString(): String {
            pos++
            val sb = StringBuilder()
            while (pos < input.length) {
                val ch = input[pos++]
                if (ch == '"') return sb.toString()
                if (ch == '\\') {
                    if (pos >= input.length) throw IllegalArgumentException("Unterminated escape")
                    when (val esc = input[pos++]) {
                        '"' -> sb.append('"')
                        '\\' -> sb.append('\\')
                        '/' -> sb.append('/')
                        'b' -> sb.append('\b')
                        'f' -> sb.append('\u000C')
                        'n' -> sb.append('\n')
                        'r' -> sb.append('\r')
                        't' -> sb.append('\t')
                        'u' -> {
                            if (pos + 4 > input.length) throw IllegalArgumentException("Invalid unicode escape")
                            val hex = input.substring(pos, pos + 4)
                            sb.append(hex.toInt(16).toChar())
                            pos += 4
                        }
                        else -> sb.append(esc)
                    }
                } else {
                    if (ch.code < 0x20) throw IllegalArgumentException("Unescaped control char in string")
                    sb.append(ch)
                }
            }
            throw IllegalArgumentException("Unterminated string")
        }

        private fun parseLiteral(literal: String, value: Any?): Any? {
            if (!input.startsWith(literal, pos)) {
                throw IllegalArgumentException("Expected '$literal' at $pos")
            }
            pos += literal.length
            return value
        }

        private fun parseNumber(): Number {
            val start = pos
            if (input[pos] == '-') pos++
            if (pos >= input.length || !input[pos].isDigit()) {
                throw IllegalArgumentException("Invalid number at $start")
            }
            if (input[pos] == '0') {
                pos++
            } else {
                while (pos < input.length && input[pos].isDigit()) pos++
            }
            var isFloat = false
            if (pos < input.length && input[pos] == '.') {
                isFloat = true
                pos++
                if (pos >= input.length || !input[pos].isDigit()) {
                    throw IllegalArgumentException("Invalid fraction at $pos")
                }
                while (pos < input.length && input[pos].isDigit()) pos++
            }
            if (pos < input.length && (input[pos] == 'e' || input[pos] == 'E')) {
                isFloat = true
                pos++
                if (pos < input.length && (input[pos] == '+' || input[pos] == '-')) pos++
                if (pos >= input.length || !input[pos].isDigit()) {
                    throw IllegalArgumentException("Invalid exponent at $pos")
                }
                while (pos < input.length && input[pos].isDigit()) pos++
            }
            val raw = input.substring(start, pos)
            return if (isFloat) {
                raw.toDouble()
            } else {
                raw.toLongOrNull()?.let { l ->
                    if (l in Int.MIN_VALUE..Int.MAX_VALUE) l.toInt() else l
                } ?: raw.toDouble()
            }
        }

        private fun skipWhitespace() {
            while (pos < input.length && input[pos].isWhitespace()) {
                pos++
            }
        }
    }
}
