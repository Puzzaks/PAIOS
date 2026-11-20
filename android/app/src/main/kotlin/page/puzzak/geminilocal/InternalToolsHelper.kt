package page.puzzak.geminilocal

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.Looper
import android.util.Log
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.URL
import java.net.URLEncoder
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

/**
 * Native Kotlin mirror of Dart's InternalToolsService.
 *
 * Provides extension metadata, FlutterSharedPreferences gating, network
 * reachability checks, prompt schema generation, and HTTP/device execution
 * for PAIOS built-in tools inside [MeshOverlayActivity].
 */
object InternalToolsHelper {
    private const val TAG = "InternalToolsHelper"
    private const val PREFS_NAME = "FlutterSharedPreferences"
    private const val USER_AGENT = "PAIOS/1.7 (https://github.com/Puzzaks/PAIOS)"
    private const val HTTP_TIMEOUT_MS = 6000

    const val MODULE_DOCS = "paios.docs"
    const val MODULE_DEVICE = "paios.device"
    const val MODULE_WIKIPEDIA = "paios.wikipedia"
    const val MODULE_SEARCH = "paios.search"
    const val MODULE_WEATHER = "paios.weather"
    const val TOOL_INSPECT_SCREEN = "inspect_screen"

    data class InternalToolSpec(
        val name: String,
        val moduleId: String,
        val description: String,
        val parametersJson: String,
        val requiresInternet: Boolean,
    )

    data class InternalModuleSpec(
        val id: String,
        val title: String,
        val defaultEnabled: Boolean,
        val requiresInternet: Boolean,
        val tools: List<InternalToolSpec>,
    )

    val INTERNAL_MODULES: List<InternalModuleSpec> = listOf(
        InternalModuleSpec(
            id = MODULE_DOCS,
            title = "AICore Docs",
            defaultEnabled = true,
            requiresInternet = false,
            tools = listOf(
                InternalToolSpec(
                    name = "query_aicore_documentation",
                    moduleId = MODULE_DOCS,
                    description = "Searches official PAIOS & Google ML Kit GenAI / AICore documentation. Call when asked 'who are you?', 'tell me about yourself', 'what is PAIOS?', or about PAIOS features, extensions, assistant overlay, Gemini Nano v3/v4, supported devices, token limits, and error codes.",
                    parametersJson = """{"type":"object","properties":{"query":{"type":"string","description":"Search topic, PAIOS feature, device model, or error code (e.g. \"PAIOS overview\", \"token limits\", \"-101\", \"Pixel 9\", \"system prompt\")"}},"required":["query"]}""",
                    requiresInternet = false,
                ),
            ),
        ),
        InternalModuleSpec(
            id = MODULE_DEVICE,
            title = "Device & Battery",
            defaultEnabled = true,
            requiresInternet = false,
            tools = listOf(
                InternalToolSpec(
                    name = "get_battery_status",
                    moduleId = MODULE_DEVICE,
                    description = "Checks device battery level, charging state, and power status. NEVER invoke this tool for questions about images, photos, screen icons, UI widgets, or visible apps.",
                    parametersJson = """{"type":"object","properties":{}}""",
                    requiresInternet = false,
                ),
            ),
        ),
        InternalModuleSpec(
            id = MODULE_WIKIPEDIA,
            title = "Wikipedia",
            defaultEnabled = false,
            requiresInternet = true,
            tools = listOf(
                InternalToolSpec(
                    name = "wikipedia_summary",
                    moduleId = MODULE_WIKIPEDIA,
                    description = "Fetches a concise Wikipedia summary for a topic, person, place, or concept.",
                    parametersJson = """{"type":"object","properties":{"query":{"type":"string","description":"Article title or topic to look up"},"lang":{"type":"string","description":"Two-letter Wikipedia language code (default \"en\")"}},"required":["query"]}""",
                    requiresInternet = true,
                ),
                InternalToolSpec(
                    name = "wikipedia_details",
                    moduleId = MODULE_WIKIPEDIA,
                    description = "Searches a Wikipedia article for sections relevant to a specific question and extracts key facts.",
                    parametersJson = """{"type":"object","properties":{"query":{"type":"string","description":"Wikipedia article title or topic"},"question":{"type":"string","description":"Specific question or detail to look for"},"lang":{"type":"string","description":"Two-letter Wikipedia language code (default \"en\")"}},"required":["query","question"]}""",
                    requiresInternet = true,
                ),
            ),
        ),
        InternalModuleSpec(
            id = MODULE_SEARCH,
            title = "Web Search (DuckDuckGo)",
            defaultEnabled = false,
            requiresInternet = true,
            tools = listOf(
                InternalToolSpec(
                    name = "duckduckgo_search",
                    moduleId = MODULE_SEARCH,
                    description = "Queries DuckDuckGo Instant Answer for quick facts, definitions, and related snippets.",
                    parametersJson = """{"type":"object","properties":{"query":{"type":"string","description":"Search query for instant answers"}},"required":["query"]}""",
                    requiresInternet = true,
                ),
            ),
        ),
        InternalModuleSpec(
            id = MODULE_WEATHER,
            title = "Weather (Open-Meteo)",
            defaultEnabled = false,
            requiresInternet = true,
            tools = listOf(
                InternalToolSpec(
                    name = "weather_forecast",
                    moduleId = MODULE_WEATHER,
                    description = "Fetches current weather conditions and a 2-day forecast for a city or location.",
                    parametersJson = """{"type":"object","properties":{"location":{"type":"string","description":"City or place name (e.g. \"Kyiv\", \"London\")"}},"required":["location"]}""",
                    requiresInternet = true,
                ),
            ),
        ),
    )

    private val STOP_WORDS = setOf(
        "the", "and", "for", "are", "but", "not", "you", "all", "can", "had",
        "her", "was", "one", "our", "out", "has", "his", "how", "its", "may",
        "new", "now", "old", "see", "two", "way", "who", "did", "get", "let",
        "say", "she", "too", "use", "what", "when", "where", "which", "while",
        "with", "from", "that", "this", "they", "have", "were", "been", "will",
        "would", "could", "should", "about", "into", "there", "their", "them",
        "then", "than", "does",
    )

    private val IGNORED_SECTIONS = setOf(
        "references", "external links", "see also", "further reading", "notes", "bibliography",
    )

    internal val DOCS_TOOL_ALIASES = setOf(
        "query_aicore_documentation",
        "about_paios",
        "paios_info",
        "get_paios_info",
    )

    internal val DOC_QUERY_ARG_KEYS = listOf(
        "query", "topic", "q", "question", "search", "subject", "title", "term", "name",
    )

    private val PAIOS_DOC_BOOST_TERMS = setOf(
        "paios", "puzzak", "overview", "identity", "assistant", "overlay",
        "extension", "extensions", "feature", "features", "privacy", "offline",
    )

    internal fun canonicalToolName(toolName: String): String {
        val norm = toolName.trim().lowercase(Locale.ROOT)
        return if (norm in DOCS_TOOL_ALIASES) "query_aicore_documentation" else norm
    }

    internal fun normalizeDocumentationQueryString(rawQuery: String): String {
        val trimmed = rawQuery.trim()
        val normalizedLower = trimmed.lowercase(Locale.ROOT)
            .trim { !it.isLetterOrDigit() }
            .replace(Regex("\\s+"), " ")
        return if (
            trimmed.isBlank() ||
            normalizedLower == "who are you" ||
            normalizedLower == "tell me about yourself" ||
            normalizedLower == "what are you" ||
            normalizedLower == "introduce yourself"
        ) {
            "PAIOS overview features"
        } else {
            trimmed
        }
    }

    internal fun normalizeDocumentationQuery(argsMap: Map<String, Any?>): String {
        val rawQuery = DOC_QUERY_ARG_KEYS
            .asSequence()
            .map { key -> argsMap[key]?.toString()?.trim().orEmpty() }
            .firstOrNull { it.isNotEmpty() }
            .orEmpty()
        return normalizeDocumentationQueryString(rawQuery)
    }

    internal fun normalizeDocumentationQuery(argsJson: JSONObject): String {
        val rawQuery = DOC_QUERY_ARG_KEYS
            .asSequence()
            .map { key -> argsJson.optString(key, "").trim() }
            .firstOrNull { it.isNotEmpty() }
            .orEmpty()
        return normalizeDocumentationQueryString(rawQuery)
    }

    internal fun normalizeToolArgs(
        toolName: String,
        rawArgs: Map<String, Any?>,
        fallbackQuestion: String? = null,
    ): Map<String, Any?> {
        val args = LinkedHashMap<String, Any?>(rawArgs)
        fun firstNonEmpty(keys: List<String>): String {
            for (k in keys) {
                val v = args[k]?.toString()?.trim().orEmpty()
                if (v.isNotEmpty()) return v
            }
            return ""
        }

        when (canonicalToolName(toolName)) {
            "query_aicore_documentation" -> {
                val raw = firstNonEmpty(DOC_QUERY_ARG_KEYS)
                    .ifEmpty { fallbackQuestion?.trim().orEmpty() }
                args["query"] = normalizeDocumentationQueryString(raw)
            }
            "wikipedia_summary", "wikipedia_details", "duckduckgo_search" -> {
                if (args["query"]?.toString()?.trim().isNullOrEmpty()) {
                    val alias = firstNonEmpty(DOC_QUERY_ARG_KEYS)
                    if (alias.isNotEmpty()) {
                        args["query"] = alias
                    }
                }
                if (toolName.trim().equals("wikipedia_details", ignoreCase = true) &&
                    args["question"]?.toString()?.trim().isNullOrEmpty()
                ) {
                    val qAlias = firstNonEmpty(listOf("ask", "detail", "prompt"))
                        .ifEmpty { fallbackQuestion?.trim().orEmpty() }
                    if (qAlias.isNotEmpty()) {
                        args["question"] = qAlias
                    }
                }
            }
            "weather_forecast" -> {
                if (args["location"]?.toString()?.trim().isNullOrEmpty()) {
                    val locAlias = firstNonEmpty(listOf("city", "place", "query", "q"))
                    if (locAlias.isNotEmpty()) {
                        args["location"] = locAlias
                    }
                }
            }
        }
        return args
    }

    fun moduleById(moduleId: String): InternalModuleSpec? {
        val norm = moduleId.trim().lowercase(Locale.ROOT)
        return INTERNAL_MODULES.firstOrNull { it.id == norm }
    }

    fun moduleForTool(toolName: String): InternalModuleSpec? {
        val canon = canonicalToolName(toolName)
        return INTERNAL_MODULES.firstOrNull { mod -> mod.tools.any { it.name == canon } }
    }

    fun isInternalTool(toolName: String): Boolean = moduleForTool(toolName) != null

    /**
     * Checks whether an internal PAIOS module is enabled in FlutterSharedPreferences.
     * Defaults to true for offline modules (paios.docs, paios.device) and false for
     * online modules (paios.wikipedia, paios.search, paios.weather).
     */
    fun isInternalModuleEnabled(context: Context, moduleId: String): Boolean {
        val module = moduleById(moduleId)
        val defaultVal = module?.defaultEnabled ?: false
        return try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val flutterKey = "flutter.mesh_extension_${moduleId}_enabled"
            val directKey = "mesh_extension_${moduleId}_enabled"
            when {
                prefs.contains(flutterKey) -> prefs.getBoolean(flutterKey, defaultVal)
                prefs.contains(directKey) -> prefs.getBoolean(directKey, defaultVal)
                else -> defaultVal
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed reading pref for $moduleId: ${e.message}")
            defaultVal
        }
    }

    /**
     * Checks whether the device has active internet connectivity using ConnectivityManager
     * (with quick DNS fallback when off the main thread).
     */
    fun checkOnline(context: Context): Boolean {
        return try {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            val network = cm?.activeNetwork
            val caps = if (network != null) cm.getNetworkCapabilities(network) else null
            val hasInternet = caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true
            val isValidated = caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true
            if (hasInternet && isValidated) {
                return true
            }
            if (hasInternet && Looper.myLooper() != Looper.getMainLooper()) {
                return try {
                    val addr = InetAddress.getByName("dns.google")
                    addr.hostAddress?.isNotEmpty() == true
                } catch (_: Exception) {
                    false
                }
            }
            false
        } catch (e: Exception) {
            Log.w(TAG, "checkOnline failed: ${e.message}")
            false
        }
    }

    /**
     * Returns the on-demand schema entry for [TOOL_INSPECT_SCREEN] when active
     * passive screen context is available in the overlay.
     */
    fun getInspectScreenPromptSpec(): String = buildString {
        append("\n - $TOOL_INSPECT_SCREEN (app: \"paios\"): Inspect current screen (screenshot + UI text) when asked what is on screen, 'this page', or 'this app'.")
        append("\n   args: {} or {question?: string} (prefer {} for concise calls)")
    }

    private fun formatCompactToolArgs(parametersJson: String): String {
        val obj = runCatching { JSONObject(parametersJson) }.getOrNull() ?: return "{}"
        val props = obj.optJSONObject("properties") ?: return "{}"
        if (props.length() == 0) return "{}"

        val requiredKeys = HashSet<String>()
        val reqArr = obj.optJSONArray("required")
        if (reqArr != null) {
            for (i in 0 until reqArr.length()) {
                val key = reqArr.optString(i, "").trim()
                if (key.isNotEmpty()) requiredKeys.add(key)
            }
        }

        val parts = mutableListOf<String>()
        val keys = props.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            val propObj = props.optJSONObject(key)
            val baseType = propObj?.optString("type", "")?.trim()?.takeIf { it.isNotEmpty() } ?: "any"
            val enumArr = propObj?.optJSONArray("enum")
            val typeSpec = if (enumArr != null && enumArr.length() > 0) {
                val enums = (0 until enumArr.length())
                    .mapNotNull { idx -> enumArr.opt(idx)?.toString()?.trim()?.takeIf { it.isNotEmpty() } }
                if (enums.isNotEmpty()) "$baseType(${enums.joinToString("|")})" else baseType
            } else {
                baseType
            }
            val suffix = if (requiredKeys.contains(key)) "" else "?"
            parts.add("$key$suffix: $typeSpec")
        }
        return "{${parts.joinToString(", ")}}"
    }

    /**
     * Returns formatted schema lines for all enabled internal PAIOS tools
     * for inclusion in the assistant's [AVAILABLE TOOLS] prompt block.
     */
    fun getMeshToolPromptSpecs(
        context: Context,
        includeInspectScreen: Boolean = false
    ): String {
        return buildString {
            if (includeInspectScreen) {
                append(getInspectScreenPromptSpec())
            }
            for (module in INTERNAL_MODULES) {
                if (!isInternalModuleEnabled(context, module.id)) continue
                for (tool in module.tools) {
                    append("\n - ${tool.name} (app: \"paios\"): ${tool.description}")
                    append("\n   args: ${formatCompactToolArgs(tool.parametersJson)}")
                }
            }
        }
    }

    /**
     * Executes an internal PAIOS tool (offline or online) and returns a compact JSON string.
     */
    suspend fun executeInternalTool(
        context: Context,
        toolName: String,
        argsJson: JSONObject,
        readerCallback: (suspend (text: String, question: String) -> String)? = null,
    ): String {
        val normTool = toolName.trim().lowercase(Locale.ROOT)
        val module = moduleForTool(normTool)
        if (module != null && !isInternalModuleEnabled(context, module.id)) {
            return JSONObject().apply {
                put("status", "error")
                put("error", "extension_disabled")
                put("message", "Extension '${module.title}' (${module.id}) is disabled in PAIOS settings.")
            }.toString()
        }

        return when (canonicalToolName(normTool)) {
            "query_aicore_documentation" -> {
                val query = normalizeDocumentationQuery(argsJson)
                withContext(Dispatchers.IO) { queryDocumentation(context, query) }
            }
            "get_battery_status" -> {
                getBatteryStatusJson(context)
            }
            "wikipedia_summary" -> withContext(Dispatchers.IO) {
                if (!checkOnline(context)) return@withContext offlineErrorJson()
                val query = DOC_QUERY_ARG_KEYS.asSequence()
                    .map { k -> argsJson.optString(k, "").trim() }
                    .firstOrNull { it.isNotEmpty() }
                    .orEmpty()
                val lang = argsJson.optString("lang", "en").ifBlank { "en" }
                executeWikipediaSummary(query, lang)
            }
            "wikipedia_details" -> withContext(Dispatchers.IO) {
                if (!checkOnline(context)) return@withContext offlineErrorJson()
                val query = DOC_QUERY_ARG_KEYS.asSequence()
                    .map { k -> argsJson.optString(k, "").trim() }
                    .firstOrNull { it.isNotEmpty() }
                    .orEmpty()
                val question = sequenceOf("question", "ask", "detail", "prompt")
                    .map { k -> argsJson.optString(k, "").trim() }
                    .firstOrNull { it.isNotEmpty() }
                    .orEmpty()
                val lang = argsJson.optString("lang", "en").ifBlank { "en" }
                executeWikipediaDetails(query, question, lang, readerCallback)
            }
            "duckduckgo_search" -> withContext(Dispatchers.IO) {
                if (!checkOnline(context)) return@withContext offlineErrorJson()
                val query = DOC_QUERY_ARG_KEYS.asSequence()
                    .map { k -> argsJson.optString(k, "").trim() }
                    .firstOrNull { it.isNotEmpty() }
                    .orEmpty()
                executeDuckDuckGoSearch(context, query)
            }
            "weather_forecast" -> withContext(Dispatchers.IO) {
                if (!checkOnline(context)) return@withContext offlineErrorJson()
                val location = sequenceOf("location", "city", "place", "query", "q")
                    .map { k -> argsJson.optString(k, "").trim() }
                    .firstOrNull { it.isNotEmpty() }
                    .orEmpty()
                executeWeatherForecast(location)
            }
            else -> JSONObject().apply {
                put("status", "error")
                put("message", "Tool '$normTool' is not supported as an internal PAIOS tool.")
            }.toString()
        }
    }

    private fun offlineErrorJson(): String = JSONObject().apply {
        put("error", "device_offline")
        put("message", "Device is offline; cannot use online search tools right now.")
    }.toString()

    private fun invalidArgsJson(message: String): String = JSONObject().apply {
        put("found", false)
        put("error", "invalid_arguments")
        put("message", message)
    }.toString()

    private fun sanitizeLang(lang: String): String {
        val cleaned = lang.trim().lowercase(Locale.ROOT)
        return if (Regex("""^[a-z]{2,3}(-[a-z0-9]{2,8})?$""").matches(cleaned)) cleaned else "en"
    }

    private fun encodeUrlParam(value: String): String =
        URLEncoder.encode(value, "UTF-8").replace("+", "%20")

    private fun truncateText(text: String, maxChars: Int): String {
        val trimmed = text.trim()
        if (trimmed.length <= maxChars) return trimmed
        if (maxChars <= 3) return trimmed.take(maxChars)
        return trimmed.take(maxChars - 3).trimEnd() + "..."
    }

    private fun httpGet(urlString: String): Pair<Int, String> {
        var conn: HttpURLConnection? = null
        return try {
            val url = URL(urlString)
            conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = HTTP_TIMEOUT_MS
                readTimeout = HTTP_TIMEOUT_MS
                instanceFollowRedirects = true
                setRequestProperty("User-Agent", USER_AGENT)
                setRequestProperty("Accept", "application/json")
            }
            val code = conn.responseCode
            val stream = if (code in 200..299) conn.inputStream else conn.errorStream
            val body = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() } ?: ""
            Pair(code, body)
        } finally {
            conn?.disconnect()
        }
    }

    private fun searchBestWikipediaTitle(query: String, safeLang: String): String? {
        val url = "https://$safeLang.wikipedia.org/w/rest.php/v1/search/title?q=${encodeUrlParam(query)}&limit=3"
        val (code, body) = httpGet(url)
        if (code != 200 || body.isBlank()) return null
        val json = JSONObject(body)
        val pages = json.optJSONArray("pages") ?: return null
        if (pages.length() == 0) return null

        val queryLower = query.lowercase(Locale.ROOT)
        var fallback: String? = null
        for (i in 0 until pages.length()) {
            val item = pages.optJSONObject(i) ?: continue
            val title = item.optString("title", "").trim()
            val key = item.optString("key", "").trim()
            val candidate = if (key.isNotEmpty()) key else title
            if (candidate.isEmpty()) continue
            if (fallback == null) fallback = candidate
            if (title.lowercase(Locale.ROOT) == queryLower || key.lowercase(Locale.ROOT) == queryLower) {
                return candidate
            }
        }
        return fallback
    }

    private fun executeWikipediaSummary(query: String, lang: String): String {
        if (query.isEmpty()) return invalidArgsJson("Query must not be empty.")
        val safeLang = sanitizeLang(lang)
        return try {
            val bestKey = searchBestWikipediaTitle(query, safeLang)
                ?: return JSONObject().apply {
                    put("found", false)
                    put("query", query)
                    put("message", "No Wikipedia article found for \"$query\".")
                }.toString()

            val summaryUrl = "https://$safeLang.wikipedia.org/api/rest_v1/page/summary/${encodeUrlParam(bestKey)}"
            val (code, body) = httpGet(summaryUrl)
            if (code == 404) {
                return JSONObject().apply {
                    put("found", false)
                    put("query", query)
                    put("message", "Wikipedia summary not found for \"$bestKey\".")
                }.toString()
            }
            if (code != 200) {
                return JSONObject().apply {
                    put("found", false)
                    put("error", "http_$code")
                    put("message", "Wikipedia summary request failed with status $code.")
                }.toString()
            }

            val obj = JSONObject(body)
            val title = obj.optString("title", bestKey).trim()
            val description = obj.optString("description", "").trim()
            val extract = obj.optString("extract", "").trim()
            if (extract.isEmpty()) {
                return JSONObject().apply {
                    put("found", false)
                    put("title", title)
                    put("message", "No summary text available for \"$title\".")
                }.toString()
            }

            val contentUrls = obj.optJSONObject("content_urls")
            val pageUrl = contentUrls?.optJSONObject("desktop")?.optString("page", "")
                ?.takeIf { it.isNotBlank() }
                ?: contentUrls?.optJSONObject("mobile")?.optString("page", "")
                    ?.takeIf { it.isNotBlank() }
                ?: "https://$safeLang.wikipedia.org/wiki/${encodeUrlParam(bestKey)}"

            JSONObject().apply {
                put("found", true)
                put("title", title)
                if (description.isNotEmpty()) put("description", description)
                put("extract", truncateText(extract, 800))
                put("url", pageUrl)
            }.toString()
        } catch (e: Exception) {
            Log.w(TAG, "wikipediaSummary failed: ${e.message}")
            JSONObject().apply {
                put("found", false)
                put("error", "request_failed")
                put("message", "Wikipedia lookup failed: ${e.message}")
            }.toString()
        }
    }

    private suspend fun executeWikipediaDetails(
        query: String,
        question: String,
        lang: String,
        readerCallback: (suspend (text: String, question: String) -> String)?,
    ): String {
        if (query.isEmpty() || question.isEmpty()) {
            return invalidArgsJson("Both query and question must not be empty.")
        }
        val safeLang = sanitizeLang(lang)
        return try {
            val bestKey = searchBestWikipediaTitle(query, safeLang)
                ?: return JSONObject().apply {
                    put("found", false)
                    put("query", query)
                    put("message", "No Wikipedia article found for \"$query\".")
                }.toString()

            val apiUrl = "https://$safeLang.wikipedia.org/w/api.php?action=query&prop=extracts&explaintext=1&titles=${encodeUrlParam(bestKey)}&format=json&redirects=1"
            val (code, body) = httpGet(apiUrl)
            if (code != 200) {
                return JSONObject().apply {
                    put("found", false)
                    put("error", "http_$code")
                    put("message", "Wikipedia details request failed with status $code.")
                }.toString()
            }

            val root = JSONObject(body)
            val pagesObj = root.optJSONObject("query")?.optJSONObject("pages")
            if (pagesObj == null || pagesObj.length() == 0) {
                return JSONObject().apply {
                    put("found", false)
                    put("query", query)
                    put("message", "No detailed Wikipedia content found for \"$query\".")
                }.toString()
            }

            var pageObj: JSONObject? = null
            val keys = pagesObj.keys()
            while (keys.hasNext()) {
                val k = keys.next()
                if (k == "-1") continue
                val candidate = pagesObj.optJSONObject(k)
                if (candidate != null && !candidate.has("missing")) {
                    pageObj = candidate
                    break
                }
            }

            val extract = pageObj?.optString("extract", "")?.trim() ?: ""
            val resolvedTitle = pageObj?.optString("title", bestKey)?.trim()?.ifEmpty { bestKey } ?: bestKey
            if (extract.isEmpty()) {
                return JSONObject().apply {
                    put("found", false)
                    put("title", resolvedTitle)
                    put("message", "No plaintext extract available for \"$resolvedTitle\".")
                }.toString()
            }

            val rankedText = rankWikipediaSections(extract, question, query, maxChars = 2200)
            val pageUrl = "https://$safeLang.wikipedia.org/wiki/${encodeUrlParam(resolvedTitle.replace(' ', '_'))}"

            var condensedText: String? = null
            if (readerCallback != null && rankedText.length > 500) {
                try {
                    val output = readerCallback(rankedText, question).trim()
                    if (output.isNotEmpty()) {
                        condensedText = truncateText(output, 1200)
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "readerCallback failed, falling back to ranked excerpt: ${e.message}")
                }
            }

            JSONObject().apply {
                put("found", true)
                put("title", resolvedTitle)
                put("question", question)
                put("condensed", condensedText != null)
                put("details", condensedText ?: truncateText(rankedText, 1200))
                put("url", pageUrl)
            }.toString()
        } catch (e: Exception) {
            Log.w(TAG, "wikipediaDetails failed: ${e.message}")
            JSONObject().apply {
                put("found", false)
                put("error", "request_failed")
                put("message", "Wikipedia details lookup failed: ${e.message}")
            }.toString()
        }
    }

    private data class ScoredChunk(val order: Int, val score: Int, val text: String)

    fun rankWikipediaSections(
        fullText: String,
        question: String,
        query: String,
        maxChars: Int = 2200,
    ): String {
        val normalized = fullText.trim()
        if (normalized.isEmpty()) return ""

        val keywords = "$question $query"
            .lowercase(Locale.ROOT)
            .split(Regex("""[^\p{L}\p{N}]+"""))
            .filter { it.length > 2 && !STOP_WORDS.contains(it) }
            .distinct()
        val questionPhrase = question.trim().lowercase(Locale.ROOT)

        val headingRegex = Regex("""^={2,}\s*(.+?)\s*={2,}$""", RegexOption.MULTILINE)
        val matches = headingRegex.findAll(normalized).toList()

        val rawSections = mutableListOf<Pair<String, String>>()
        if (matches.isEmpty()) {
            rawSections.add("" to normalized)
        } else {
            if (matches.first().range.first > 0) {
                val lead = normalized.substring(0, matches.first().range.first).trim()
                if (lead.isNotEmpty()) rawSections.add("Overview" to lead)
            }
            for (i in matches.indices) {
                val m = matches[i]
                val heading = m.groupValues[1].trim()
                val start = m.range.last + 1
                val end = if (i + 1 < matches.size) matches[i + 1].range.first else normalized.length
                val body = normalized.substring(start, end).trim()
                if (body.isNotEmpty() && !IGNORED_SECTIONS.contains(heading.lowercase(Locale.ROOT))) {
                    rawSections.add(heading to body)
                }
            }
        }

        val chunks = mutableListOf<ScoredChunk>()
        var order = 0
        for ((heading, body) in rawSections) {
            val paragraphs = body.split(Regex("""\n\s*\n+"""))
            for (para in paragraphs) {
                val trimmed = para.trim()
                if (trimmed.isEmpty()) continue
                val headingLower = heading.lowercase(Locale.ROOT)
                val textLower = trimmed.lowercase(Locale.ROOT)
                var score = if (heading == "Overview") 1 else 0
                if (questionPhrase.length > 4 && textLower.contains(questionPhrase)) {
                    score += 8
                }
                for (kw in keywords) {
                    if (headingLower.contains(kw)) score += 5
                    if (textLower.contains(kw)) score += 2
                }
                val formatted = if (heading.isNotEmpty()) "## $heading\n$trimmed" else trimmed
                chunks.add(ScoredChunk(order++, score, formatted))
            }
        }

        if (chunks.isEmpty()) return truncateText(normalized, maxChars)

        val sorted = chunks.sortedWith(compareByDescending<ScoredChunk> { it.score }.thenBy { it.order })
        val selected = mutableListOf<ScoredChunk>()
        var totalLen = 0
        for (chunk in sorted) {
            if (selected.isNotEmpty() && chunk.score == 0) continue
            val sepLen = if (selected.isEmpty()) 0 else 2
            if (totalLen + sepLen + chunk.text.length <= maxChars) {
                selected.add(chunk)
                totalLen += sepLen + chunk.text.length
            } else if (selected.isEmpty()) {
                selected.add(chunk.copy(text = truncateText(chunk.text, maxChars)))
                break
            }
        }

        if (selected.isEmpty()) return truncateText(normalized, maxChars)
        return selected.sortedBy { it.order }.joinToString("\n\n") { it.text }
    }

    private fun executeDuckDuckGoSearch(context: Context, query: String): String {
        if (query.isEmpty()) return invalidArgsJson("Query must not be empty.")
        return try {
            val url = "https://api.duckduckgo.com/?q=${encodeUrlParam(query)}&format=json&no_html=1&skip_disambig=1"
            val (code, body) = httpGet(url)
            if (code != 200) {
                return JSONObject().apply {
                    put("found", false)
                    put("error", "http_$code")
                    put("message", "DuckDuckGo search failed with status $code.")
                }.toString()
            }

            val obj = JSONObject(body)
            val heading = obj.optString("Heading", "").trim()
            val abstractText = obj.optString("AbstractText", "").trim()
            val answer = obj.optString("Answer", "").trim()
            val definition = obj.optString("Definition", "").trim()
            val abstractUrl = obj.optString("AbstractURL", "").trim()

            val related = mutableListOf<String>()
            fun collectRelated(arr: JSONArray?) {
                if (arr == null || related.size >= 3) return
                for (i in 0 until arr.length()) {
                    if (related.size >= 3) break
                    val item = arr.optJSONObject(i) ?: continue
                    val text = item.optString("Text", "").trim()
                    if (text.isNotEmpty()) {
                        related.add(truncateText(text, 180))
                    } else {
                        collectRelated(item.optJSONArray("Topics"))
                    }
                }
            }
            collectRelated(obj.optJSONArray("RelatedTopics"))

            if (abstractText.isEmpty() && answer.isEmpty() && definition.isEmpty() && related.isEmpty()) {
                val hintMsg = if (isInternalModuleEnabled(context, MODULE_WIKIPEDIA)) {
                    "No instant answer found; try wikipedia_summary or rephrase query."
                } else {
                    "No instant answer found; try rephrasing the query."
                }
                return JSONObject().apply {
                    put("found", false)
                    put("query", query)
                    put("message", hintMsg)
                }.toString()
            }

            var currentAbstract = if (abstractText.isNotEmpty()) truncateText(abstractText, 420) else ""
            var includeUrl = abstractUrl.isNotEmpty()
            val trimmedRelated = related.toMutableList()

            fun buildPayload(): JSONObject = JSONObject().apply {
                put("found", true)
                if (heading.isNotEmpty()) put("heading", truncateText(heading, 100))
                if (answer.isNotEmpty()) put("answer", truncateText(answer, 220))
                if (currentAbstract.isNotEmpty()) put("abstract", currentAbstract)
                if (definition.isNotEmpty()) put("definition", truncateText(definition, 220))
                if (includeUrl) put("url", truncateText(abstractUrl, 160))
                if (trimmedRelated.isNotEmpty()) put("related", JSONArray(trimmedRelated))
            }

            var out = buildPayload()
            while (out.toString().length > 900) {
                if (trimmedRelated.isNotEmpty()) {
                    trimmedRelated.removeAt(trimmedRelated.lastIndex)
                } else if (currentAbstract.length > 120) {
                    currentAbstract = truncateText(currentAbstract, currentAbstract.length - 80)
                } else if (includeUrl) {
                    includeUrl = false
                } else {
                    break
                }
                out = buildPayload()
            }
            out.toString()
        } catch (e: Exception) {
            Log.w(TAG, "duckDuckGoSearch failed: ${e.message}")
            JSONObject().apply {
                put("found", false)
                put("error", "request_failed")
                put("message", "DuckDuckGo search failed: ${e.message}")
            }.toString()
        }
    }

    fun describeWmoWeatherCode(code: Int?): String {
        return when (code) {
            0 -> "Clear"
            1 -> "Mainly clear"
            2 -> "Partly cloudy"
            3 -> "Cloudy"
            45, 48 -> "Fog"
            51, 53, 55 -> "Drizzle"
            56, 57 -> "Freezing drizzle"
            61, 63, 65 -> "Rain"
            66, 67 -> "Freezing rain"
            71, 73, 75, 77 -> "Snow"
            80, 81, 82 -> "Rain showers"
            85, 86 -> "Snow showers"
            95 -> "Thunderstorm"
            96, 99 -> "Thunderstorm with hail"
            else -> "Unknown"
        }
    }

    private fun executeWeatherForecast(location: String): String {
        if (location.isEmpty()) return invalidArgsJson("Location must not be empty.")
        return try {
            val geoUrl = "https://geocoding-api.open-meteo.com/v1/search?name=${encodeUrlParam(location)}&count=1&language=en&format=json"
            val (geoCode, geoBody) = httpGet(geoUrl)
            if (geoCode != 200) {
                return JSONObject().apply {
                    put("found", false)
                    put("error", "http_$geoCode")
                    put("message", "Open-Meteo geocoding failed with status $geoCode.")
                }.toString()
            }

            val geoJson = JSONObject(geoBody)
            val results = geoJson.optJSONArray("results")
            if (results == null || results.length() == 0) {
                return JSONObject().apply {
                    put("found", false)
                    put("location", location)
                    put("message", "Location \"$location\" not found.")
                }.toString()
            }

            val place = results.getJSONObject(0)
            if (!place.has("latitude") || !place.has("longitude")) {
                return JSONObject().apply {
                    put("found", false)
                    put("location", location)
                    put("message", "Missing coordinates for \"$location\".")
                }.toString()
            }

            val lat = place.getDouble("latitude")
            val lon = place.getDouble("longitude")
            val forecastUrl = "https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,apparent_temperature,weather_code,wind_speed_10m,relative_humidity_2m&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max&forecast_days=2&timezone=auto"
            val (fcCode, fcBody) = httpGet(forecastUrl)
            if (fcCode != 200) {
                return JSONObject().apply {
                    put("found", false)
                    put("error", "http_$fcCode")
                    put("message", "Open-Meteo forecast failed with status $fcCode.")
                }.toString()
            }

            val fcJson = JSONObject(fcBody)
            val current = fcJson.optJSONObject("current") ?: JSONObject()
            val weatherCode = if (current.has("weather_code")) current.optInt("weather_code") else null

            val daily = fcJson.optJSONObject("daily")
            val dates = daily?.optJSONArray("time")
            val maxTemps = daily?.optJSONArray("temperature_2m_max")
            val minTemps = daily?.optJSONArray("temperature_2m_min")
            val precipProbs = daily?.optJSONArray("precipitation_probability_max")

            val dailyArray = JSONArray()
            if (dates != null) {
                val count = minOf(dates.length(), 2)
                for (i in 0 until count) {
                    val dayObj = JSONObject().apply {
                        put("date", dates.optString(i, ""))
                        if (maxTemps != null && i < maxTemps.length()) put("temp_max_c", maxTemps.opt(i))
                        if (minTemps != null && i < minTemps.length()) put("temp_min_c", minTemps.opt(i))
                        if (precipProbs != null && i < precipProbs.length()) {
                            put("precipitation_probability_percent", precipProbs.opt(i))
                        }
                    }
                    dailyArray.put(dayObj)
                }
            }

            val locObj = JSONObject().apply {
                put("name", place.optString("name", location))
                val region = place.optString("admin1", "")
                if (region.isNotEmpty()) put("region", region)
                val country = place.optString("country", "")
                if (country.isNotEmpty()) put("country", country)
            }

            val currentObj = JSONObject().apply {
                if (current.has("temperature_2m")) put("temperature_c", current.opt("temperature_2m"))
                if (current.has("apparent_temperature")) put("apparent_temperature_c", current.opt("apparent_temperature"))
                put("condition", describeWmoWeatherCode(weatherCode))
                if (weatherCode != null) put("weather_code", weatherCode)
                if (current.has("wind_speed_10m")) put("wind_speed_kmh", current.opt("wind_speed_10m"))
                if (current.has("relative_humidity_2m")) put("humidity_percent", current.opt("relative_humidity_2m"))
            }

            JSONObject().apply {
                put("found", true)
                put("location", locObj)
                put("current", currentObj)
                if (dailyArray.length() > 0) put("daily", dailyArray)
            }.toString()
        } catch (e: Exception) {
            Log.w(TAG, "weatherForecast failed: ${e.message}")
            JSONObject().apply {
                put("found", false)
                put("error", "request_failed")
                put("message", "Weather lookup failed: ${e.message}")
            }.toString()
        }
    }

    internal data class DocSearchMatch(
        val found: Boolean,
        val query: String,
        val sectionTitle: String,
        val content: String,
        val score: Int,
    )

    internal fun rankDocumentationSections(docText: String, query: String): DocSearchMatch {
        val normalizedQuery = normalizeDocumentationQueryString(query)
        val queryLower = normalizedQuery.lowercase(Locale.ROOT)
        val rawLower = query.trim().lowercase(Locale.ROOT)
        val isSelfIdentity = rawLower.isBlank() ||
            rawLower.contains("who are you") ||
            rawLower.contains("tell me about yourself") ||
            rawLower.contains("about yourself") ||
            rawLower.contains("what are you") ||
            rawLower.contains("introduce yourself") ||
            rawLower.contains("what is paios") ||
            rawLower.contains("about paios") ||
            queryLower == "paios overview features"

        val expandedQuery = if (isSelfIdentity) {
            "$normalizedQuery paios overview identity features"
        } else {
            normalizedQuery
        }
        val qTerms = expandedQuery
            .lowercase(Locale.ROOT)
            .split(Regex("[\\s,;:!?\"'()\\[\\]{}/]+"))
            .map { it.trim('.', '*', '_') }
            .filter { it.length >= 2 && it !in STOP_WORDS }
            .distinct()

        val sections = docText.split(Regex("(?=## )"))
        var bestSection = ""
        var bestTitle = ""
        var bestScore = 0

        for (sec in sections) {
            val secLower = sec.lowercase(Locale.ROOT)
            val lines = sec.lines()
            val title = lines.firstOrNull { it.startsWith("##") }
                ?: lines.firstOrNull { it.startsWith("#") }
                ?: ""
            val cleanTitle = title.trimStart('#', ' ').trim()
            val titleLower = cleanTitle.lowercase(Locale.ROOT)

            var score = 0
            if (isSelfIdentity) {
                if (titleLower.contains("paios overview")) {
                    score += 80
                } else if (titleLower.contains("paios")) {
                    score += 30
                }
            }
            for (term in qTerms) {
                val isBoosted = term in PAIOS_DOC_BOOST_TERMS
                if (titleLower.contains(term)) score += if (isBoosted) 16 else 10
                if (secLower.contains(term)) score += if (isBoosted) 5 else 2
            }
            if (score > bestScore) {
                bestScore = score
                bestSection = sec
                bestTitle = cleanTitle
            }
        }

        val content = if (bestScore > 0 && bestSection.isNotBlank()) {
            bestSection.trim().take(1800)
        } else {
            docText.trim().take(1500)
        }

        return DocSearchMatch(
            found = content.isNotBlank(),
            query = normalizedQuery,
            sectionTitle = bestTitle,
            content = content,
            score = bestScore,
        )
    }

    private fun queryDocumentation(context: Context, query: String): String {
        return try {
            val docText = try {
                context.assets.open("flutter_assets/assets/docs/genai.md.txt")
                    .bufferedReader().use { it.readText() }
            } catch (_: Exception) {
                context.assets.open("docs/genai.md.txt")
                    .bufferedReader().use { it.readText() }
            }
            val match = rankDocumentationSections(docText, query)
            JSONObject().apply {
                put("found", match.found)
                put("query", match.query)
                if (match.sectionTitle.isNotEmpty()) put("title", match.sectionTitle)
                put("content", match.content)
            }.toString()
        } catch (e: Exception) {
            Log.e(TAG, "queryDocumentation error: ${e.message}", e)
            JSONObject().apply {
                put("found", false)
                put("error", e.message)
            }.toString()
        }
    }

    data class BatteryStatusSnapshot(
        val level: Int,
        val charging: Boolean,
        val status: String,
    )

    fun readBatteryStatusSnapshot(context: Context): BatteryStatusSnapshot {
        val bm = context.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
        val intent = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        var level = bm?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1
        if (level < 0 && intent != null) {
            val rawLevel = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
            if (rawLevel >= 0 && scale > 0) {
                level = (rawLevel * 100) / scale
            }
        }
        val statusInt = intent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
            ?: if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                bm?.getIntProperty(BatteryManager.BATTERY_PROPERTY_STATUS) ?: -1
            } else {
                -1
            }
        val isCharging = statusInt == BatteryManager.BATTERY_STATUS_CHARGING ||
            statusInt == BatteryManager.BATTERY_STATUS_FULL
        val statusLabel = when (statusInt) {
            BatteryManager.BATTERY_STATUS_CHARGING -> "Charging"
            BatteryManager.BATTERY_STATUS_FULL -> "Full"
            BatteryManager.BATTERY_STATUS_NOT_CHARGING -> "Not charging"
            BatteryManager.BATTERY_STATUS_DISCHARGING -> "Discharging"
            else -> if (isCharging) "Charging" else "Discharging"
        }
        return BatteryStatusSnapshot(
            level = level,
            charging = isCharging,
            status = statusLabel,
        )
    }

    private fun getBatteryStatusJson(context: Context): String {
        return try {
            val snapshot = readBatteryStatusSnapshot(context)
            JSONObject().apply {
                put("battery_level", "${snapshot.level}%")
                put("is_charging", snapshot.charging)
                put("status", snapshot.status)
            }.toString()
        } catch (e: Exception) {
            JSONObject().apply {
                put("error", e.message)
            }.toString()
        }
    }
}
