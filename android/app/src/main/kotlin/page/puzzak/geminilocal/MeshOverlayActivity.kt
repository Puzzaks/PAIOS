package page.puzzak.geminilocal

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextUtils
import android.text.style.BackgroundColorSpan
import android.text.style.ForegroundColorSpan
import android.text.style.RelativeSizeSpan
import android.text.style.StyleSpan
import android.text.style.TypefaceSpan
import android.util.Base64
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.annotation.Keep
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.google.mlkit.genai.prompt.GenerateContentResponse
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.ImagePart
import com.google.mlkit.genai.prompt.TextPart
import com.google.mlkit.genai.prompt.generateContentRequest
import java.io.File
import java.lang.ref.WeakReference
import java.util.Locale
import kotlin.math.abs
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.cancel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.onCompletion
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONArray
import org.json.JSONObject

/**
 * Unified Translucent Bottom Status Pill & Material 3 Expressive Half-Screen Assistant Sheet.
 *
 * Supports two operating modes:
 * - **Mode A (Headless / One-Shot RPC Mode)**: Appears momentarily as a non-focusable pill
 *   when external apps request background Gemini Nano text/vision inference, satisfies
 *   AICore's foreground window check, returns the JSON-RPC response, and finishes automatically.
 * - **Mode B (Interactive Material 3 Expressive Assistant Sheet)**: Activated via
 *   `Intent.ACTION_ASSIST`, `Intent.ACTION_VOICE_COMMAND`, or `interactive_bubble = true`.
 *   Renders a full-width Material 3 Expressive dark-teal assistant bottom sheet with drag-to-close /
 *   drag-to-expand handle, outside-tap dismissal, native vector icons, chat bubbles with live
 *   markdown rendering, multimodal vision preview, localized strings from `assets/translations/`,
 *   and automatic Mesh + Assist context discovery.
 */
@Keep
class MeshOverlayActivity : Activity() {

    companion object {
        private const val TAG = "MeshOverlayActivity"
        private const val REQUEST_CODE_BUBBLE_IMAGE = 0x4249
        private const val MAX_DOWNSAMPLE_DIMENSION = 768
        private const val ASSIST_CACHE_TTL_MS = 1500L
        private const val MAX_EXTERNAL_TOOL_SCHEMA_CHARS = 3500
        private const val MESH_TOOL_QUERY_TIMEOUT_MS = 1500L

        // =========================================================================
        // GEOMETRY & LAYOUT CONSTANTS (COLORS DERIVED DYNAMICALLY VIA THEMEPALETTE)
        // =========================================================================
        /** Sheet corner radius in dp */
        const val CARD_CORNER_RADIUS_DP = 28

        /** Sheet border stroke width in dp */
        const val CARD_BORDER_WIDTH_DP = 1

        /** Sheet elevation in dp */
        const val CARD_ELEVATION_DP = 14

        /** Title text size in sp */
        const val TITLE_TEXT_SIZE_SP = 18f

        /** Subtitle text size in sp */
        const val SUBTITLE_TEXT_SIZE_SP = 12f

        /** Horizontal progress bar height in dp */
        const val PROGRESS_BAR_HEIGHT_DP = 3

        /** Outer horizontal margin from screen edges in dp */
        const val OUTER_PADDING_HORIZONTAL_DP = 8

        /** Outer bottom margin from navigation bar in dp */
        const val OUTER_PADDING_BOTTOM_DP = 12

        /** Inner card horizontal padding in dp */
        const val CARD_PADDING_HORIZONTAL_DP = 16

        /** Inner card vertical padding in dp */
        const val CARD_PADDING_VERTICAL_DP = 14

        @Volatile
        private var lastGreetingPhrase: String? = null
        // =========================================================================

        @Keep
        @JvmField
        @Volatile
        var pendingCallback: ((String) -> Unit)? = null

        @Keep
        @JvmStatic
        fun setCallback(cb: ((String) -> Unit)?) {
            pendingCallback = cb
        }

        @Volatile
        private var activeInstanceRef: WeakReference<MeshOverlayActivity>? = null

        @Volatile
        var latestAssistBitmap: Bitmap? = null

        @Volatile
        var latestAssistScreenText: String? = null

        @Volatile
        var latestAssistCallerPkg: String? = null

        @Volatile
        var latestAssistTimestampMs: Long = 0L

        @Volatile
        private var cachedEnDict: JSONObject? = null

        @Volatile
        private var cachedLangCode: String? = null

        @Volatile
        private var cachedActiveDict: JSONObject? = null

        @Volatile
        private var cachedSupportedLangs: Set<String>? = null

        private fun getSupportedLanguages(context: Context): Set<String> {
            cachedSupportedLangs?.let { return it }
            val loaded = LinkedHashSet<String>()
            try {
                val langsText = context.assets.open("flutter_assets/assets/translations/languages.json")
                    .bufferedReader()
                    .use { it.readText() }
                val arr = JSONArray(langsText)
                for (i in 0 until arr.length()) {
                    val id = arr.optJSONObject(i)?.optString("id", "")?.trim()?.lowercase(Locale.ROOT)
                    if (!id.isNullOrEmpty()) {
                        loaded.add(id)
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to load languages.json: ${e.message}")
            }
            if (loaded.isEmpty()) {
                loaded.add("en")
            }
            cachedSupportedLangs = loaded
            return loaded
        }

        private fun resolveSupportedLang(context: Context): String {
            val rawLang = Locale.getDefault().language.lowercase(Locale.ROOT)
            val supported = getSupportedLanguages(context)
            return if (supported.contains(rawLang)) rawLang else "en"
        }

        @Keep
        @JvmStatic
        fun preloadTranslationsAsync(context: android.content.Context) {
            if (cachedEnDict != null && cachedActiveDict != null) return
            Thread {
                try {
                    val enText = context.assets.open("flutter_assets/assets/translations/en.json")
                        .bufferedReader()
                        .use { it.readText() }
                    val enJson = JSONObject(enText)
                    cachedEnDict = enJson

                    val supportedLang = resolveSupportedLang(context)
                    if (supportedLang == "en") {
                        cachedLangCode = "en"
                        cachedActiveDict = enJson
                    } else {
                        val langText = context.assets.open("flutter_assets/assets/translations/$supportedLang.json")
                            .bufferedReader()
                            .use { it.readText() }
                        cachedLangCode = supportedLang
                        cachedActiveDict = JSONObject(langText)
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "preloadTranslationsAsync warning: ${e.message}")
                }
            }.start()
        }

        @Keep
        @JvmStatic
        fun updateSystemAssistScreenshot(bitmap: Bitmap) {
            latestAssistBitmap = bitmap
            latestAssistTimestampMs = System.currentTimeMillis()
            val active = activeInstanceRef?.get()
            active?.runOnUiThread {
                active.onSystemAssistScreenshotAvailable(bitmap)
            }
        }

        @Keep
        @JvmStatic
        fun updateSystemAssistContext(callerPkg: String, screenText: String) {
            latestAssistCallerPkg = callerPkg
            latestAssistScreenText = screenText
            latestAssistTimestampMs = System.currentTimeMillis()
            val active = activeInstanceRef?.get()
            active?.runOnUiThread {
                active.onSystemAssistContextAvailable(callerPkg, screenText)
            }
        }

        @Keep
        @JvmStatic
        fun clearAssistCache() {
            latestAssistBitmap = null
            latestAssistScreenText = null
            latestAssistCallerPkg = null
            latestAssistTimestampMs = 0L
        }
    }

    private val activityScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private var activeStreamJob: Job? = null
    private var callbackFired = false
    private var callId: Any = "overlay-${System.currentTimeMillis()}"
    private var isInteractiveMode = false
    private var isLaunchingImagePicker = false
    private var isDismissing = false
    private var isSheetExpanded = false
    private var activeSheetAnimator: android.animation.ValueAnimator? = null
    private var lastLaunchTimestampMs = 0L

    // Localization maps loaded from flutter_assets/assets/translations/<lang>.json
    private var activeDict: JSONObject = JSONObject()
    private var fallbackEnDict: JSONObject = JSONObject()

    // Cached dynamic Mesh app alias -> packageName and packageName -> authority maps
    @Volatile
    private var discoveredAppAliases: Map<String, String> = emptyMap()
    @Volatile
    private var discoveredAuthorities: Map<String, String> = emptyMap()

    // Interactive state & views
    private var currentBitmap: Bitmap? = null
    private val attachedBitmaps = mutableListOf<Bitmap>()
    private var activeSessionBitmap: Bitmap? = null
    private var screenContextBitmap: Bitmap? = null
    private var downsampleSetting: Boolean = true
    private val maxImagesAllowed: Int
        get() = if (downsampleSetting) 5 else 3
    private var rawCallerPackage: String = ""
    private var callerName: String = ""
    private var contextData: String = ""
    private var conversationHistoryPrompt: String = ""
    private var visualContextMemory: String = ""
    private var lastResponseText: String = ""
    private val sessionMessages = mutableListOf<JSONObject>()

    data class ThemePalette(
        val cardBg: Int,
        val surfaceContainer: Int,
        val aiBubbleBg: Int,
        val aiBubbleBorder: Int,
        val userBubbleBg: Int,
        val userBubbleText: Int,
        val chipBg: Int,
        val cardBorder: Int,
        val sheetBorder: Int,
        val accent: Int,
        val onAccent: Int,
        val subtitle: Int,
        val bodyText: Int,
        val dragHandle: Int
    )

    private lateinit var palette: ThemePalette

    /**
     * Flutter's shared_preferences_android persists integer values as java.lang.Long in XML.
     * Calling prefs.getInt() directly throws ClassCastException: java.lang.Long cannot be cast to java.lang.Integer.
     * This helper gracefully attempts getInt, catches ClassCastException, and falls back to getLong().toInt().
     */
    private fun getSafeColorPref(prefs: SharedPreferences, key: String): Int {
        return try {
            prefs.getInt(key, 0)
        } catch (_: ClassCastException) {
            try {
                prefs.getLong(key, 0L).toInt()
            } catch (_: Exception) {
                0
            }
        } catch (_: Exception) {
            0
        }
    }

    private fun resolveDownsampleSetting(): Boolean {
        return try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            if (prefs.contains("flutter.downsampleImages")) {
                prefs.getBoolean("flutter.downsampleImages", true)
            } else if (prefs.contains("downsampleImages")) {
                prefs.getBoolean("downsampleImages", true)
            } else {
                val defPrefs = getSharedPreferences("${packageName}_preferences", Context.MODE_PRIVATE)
                defPrefs.getBoolean("downsampleImages", true)
            }
        } catch (_: Exception) {
            true
        }
    }

    private fun resolveThemePalette(): ThemePalette {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val cachedPrimary = getSafeColorPref(prefs, "flutter.theme_color_primary")
        val cachedSurface = getSafeColorPref(prefs, "flutter.theme_color_surface")
        val cachedBg = getSafeColorPref(prefs, "flutter.theme_color_background")
        val cachedOnSurface = getSafeColorPref(prefs, "flutter.theme_color_on_surface")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                val sysSurface = resources.getColor(android.R.color.system_neutral1_900, theme)
                val sysSurfaceContainer = resources.getColor(android.R.color.system_neutral1_800, theme)
                val sysAccent = resources.getColor(android.R.color.system_accent1_200, theme)
                val sysPrimaryContainer = resources.getColor(android.R.color.system_accent1_700, theme)
                val sysOnPrimaryContainer = resources.getColor(android.R.color.system_accent1_100, theme)
                val sysBody = resources.getColor(android.R.color.system_neutral1_100, theme)
                val sysSubtitle = resources.getColor(android.R.color.system_neutral2_200, theme)
                val sysOutline = resources.getColor(android.R.color.system_neutral2_400, theme)
                val sysOutlineVariant = resources.getColor(android.R.color.system_neutral2_700, theme)

                val effectiveCardBg = if (cachedSurface != 0) cachedSurface else sysSurface
                val effectiveAccent = if (cachedPrimary != 0) cachedPrimary else sysAccent

                return ThemePalette(
                    cardBg = effectiveCardBg,
                    surfaceContainer = sysSurfaceContainer,
                    aiBubbleBg = sysSurfaceContainer,
                    aiBubbleBorder = sysOutlineVariant,
                    userBubbleBg = sysPrimaryContainer,
                    userBubbleText = sysOnPrimaryContainer,
                    chipBg = sysSurfaceContainer,
                    cardBorder = sysOutlineVariant,
                    sheetBorder = sysOutlineVariant,
                    accent = effectiveAccent,
                    onAccent = Color.BLACK,
                    subtitle = sysSubtitle,
                    bodyText = if (cachedOnSurface != 0) cachedOnSurface else sysBody,
                    dragHandle = sysOutline
                )
            } catch (e: Exception) {
                Log.w(TAG, "Monet system dynamic color lookup failed: ${e.message}")
            }
        }

        // Fallback to Flutter cached or dark teal palette
        val cardBg = if (cachedSurface != 0) cachedSurface else Color.parseColor("#0E1715")
        val surfaceContainer = Color.parseColor("#14221E")
        val accent = if (cachedPrimary != 0) cachedPrimary else Color.parseColor("#80CBC4")
        val userBubbleBg = Color.parseColor("#004F47")
        val userBubbleText = Color.parseColor("#A7FFEB")
        val body = if (cachedOnSurface != 0) cachedOnSurface else Color.parseColor("#E2F1EE")
        val subtitle = Color.parseColor("#A7C4BE")
        val border = Color.parseColor("#1F332E")
        val chipBorder = Color.parseColor("#263E38")
        val dragHandle = Color.parseColor("#5C7872")

        return ThemePalette(
            cardBg = cardBg,
            surfaceContainer = surfaceContainer,
            aiBubbleBg = surfaceContainer,
            aiBubbleBorder = border,
            userBubbleBg = userBubbleBg,
            userBubbleText = userBubbleText,
            chipBg = Color.parseColor("#182825"),
            cardBorder = chipBorder,
            sheetBorder = border,
            accent = accent,
            onAccent = Color.parseColor("#003731"),
            subtitle = subtitle,
            bodyText = body,
            dragHandle = dragHandle
        )
    }

    private var sheetCardView: LinearLayout? = null
    private var callerBadgeView: TextView? = null
    private var imagePreviewContainer: HorizontalScrollView? = null
    private var imagePreviewItemsRow: LinearLayout? = null
    private var imagePreviewView: ImageView? = null
    private var imagePreviewLabel: TextView? = null
    private var outputScrollView: ScrollView? = null
    private var messagesContainer: LinearLayout? = null
    private var emptyStateCard: LinearLayout? = null
    private var sheetProgressBar: ProgressBar? = null
    private var promptInput: EditText? = null
    private var currentScrollMaxHeightPx: Int = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
        activeInstanceRef = WeakReference(this)
        palette = resolveThemePalette()
        loadTranslations()
        handleIncomingIntent(intent)
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        activeInstanceRef = WeakReference(this)
        palette = resolveThemePalette()
        loadTranslations()
        if (intent != null) {
            setIntent(intent)
            handleIncomingIntent(intent)
        }
    }

    /**
     * Loads localized strings from bundled Flutter assets (`flutter_assets/assets/translations/<lang>.json`)
     * with English fallback (`en.json`) and static in-memory caching so subsequent launches take 0ms.
     */
    private fun loadTranslations() {
        val supportedLang = resolveSupportedLang(this)

        val existingEn = cachedEnDict
        val existingActive = cachedActiveDict
        if (existingEn != null && existingActive != null && cachedLangCode == supportedLang) {
            fallbackEnDict = existingEn
            activeDict = existingActive
            return
        }

        try {
            val enJson = existingEn ?: JSONObject(
                assets.open("flutter_assets/assets/translations/en.json")
                    .bufferedReader()
                    .use { it.readText() }
            ).also { cachedEnDict = it }
            fallbackEnDict = enJson
        } catch (e: Exception) {
            Log.w(TAG, "Failed to load fallback en.json: ${e.message}")
        }

        if (supportedLang == "en") {
            activeDict = fallbackEnDict
            cachedLangCode = "en"
            cachedActiveDict = fallbackEnDict
            return
        }

        try {
            val langText = assets.open("flutter_assets/assets/translations/$supportedLang.json")
                .bufferedReader()
                .use { it.readText() }
            activeDict = JSONObject(langText)
            cachedLangCode = supportedLang
            cachedActiveDict = activeDict
        } catch (e: Exception) {
            Log.w(TAG, "Failed to load $supportedLang.json, using en.json: ${e.message}")
            activeDict = fallbackEnDict
        }
    }

    private fun tr(key: String): String {
        val localized = activeDict.optString(key, "")
        if (localized.isNotEmpty()) return localized
        return fallbackEnDict.optString(key, key)
    }

    override fun onResume() {
        super.onResume()
        isLaunchingImagePicker = false
    }

    override fun onStop() {
        super.onStop()
        val elapsedSinceLaunch = System.currentTimeMillis() - lastLaunchTimestampMs
        if (isInteractiveMode &&
            !isLaunchingImagePicker &&
            !isChangingConfigurations &&
            !isFinishing &&
            elapsedSinceLaunch > 600L
        ) {
            Log.d(TAG, "[LIFECYCLE] onStop -> closing interactive overlay")
            closeInteractiveSession()
        }
    }

    override fun onTouchEvent(event: MotionEvent?): Boolean {
        if (isInteractiveMode && event?.action == MotionEvent.ACTION_OUTSIDE) {
            dismissSheetAnimated()
            return true
        }
        return super.onTouchEvent(event)
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private fun formatShortCaller(rawCaller: String): String {
        val defaultAssist = tr("assistant_context_default")
        val cleaned = rawCaller
            .removePrefix("System Assist (")
            .removeSuffix(")")
            .substringAfterLast('.')
            .trim()
        return when {
            cleaned.isEmpty() || cleaned.equals("external_app", ignoreCase = true) -> defaultAssist
            cleaned.equals("System Assist", ignoreCase = true) -> defaultAssist
            cleaned.equals("Assist", ignoreCase = true) -> defaultAssist
            cleaned.equals("nexuslauncher", ignoreCase = true) -> defaultAssist
            else -> cleaned.replaceFirstChar { it.uppercase() }
        }
    }

    private fun handleIncomingIntent(launchIntent: Intent) {
        activeStreamJob?.cancel()
        isDismissing = false
        lastLaunchTimestampMs = System.currentTimeMillis()

        // Reset isolated session context on every hotkey / assist invocation
        conversationHistoryPrompt = ""
        visualContextMemory = ""
        contextData = ""
        currentBitmap = null
        attachedBitmaps.clear()
        activeSessionBitmap = null
        screenContextBitmap = null
        lastResponseText = ""
        sessionMessages.clear()

        val action = launchIntent.action
        val isAssistAction = action == Intent.ACTION_ASSIST || action == Intent.ACTION_VOICE_COMMAND
        var interactiveExtra = launchIntent.getBooleanExtra("interactive_bubble", false)

        val assistPkg = launchIntent.getStringExtra("android.intent.extra.ASSIST_PACKAGE")
        val rawCaller = launchIntent.getStringExtra("caller")
            ?: (if (isAssistAction && !assistPkg.isNullOrBlank()) assistPkg else "")
        rawCallerPackage = rawCaller
        callerName = formatShortCaller(rawCaller)

        val payload = launchIntent.getStringExtra("payload") ?: "{}"
        var methodName = ""
        var promptText = launchIntent.getStringExtra("prompt")
            ?: launchIntent.getStringExtra(Intent.EXTRA_TEXT)
            ?: ""
        contextData = launchIntent.getStringExtra("context_data") ?: ""
        var imageBase64 = launchIntent.getStringExtra("image_base64")
        var imageUri = launchIntent.getStringExtra("image_uri")
        downsampleSetting = if (launchIntent.hasExtra("downsample")) {
            launchIntent.getBooleanExtra("downsample", true)
        } else {
            resolveDownsampleSetting()
        }
        var targetJsonObj: JSONObject? = null

        // Parse JSON-RPC payload if provided
        try {
            val json = JSONObject(payload)
            if (json.has("id")) {
                callId = json.get("id")
            }
            methodName = json.optString("method", json.optString("name", json.optString("tool", "")))

            val paramsObj = json.opt("params") ?: json.opt("arguments") ?: json.opt("args")
            targetJsonObj = when (paramsObj) {
                is JSONObject -> paramsObj
                is String -> try {
                    JSONObject(paramsObj)
                } catch (_: Exception) {
                    if (promptText.isEmpty()) promptText = paramsObj
                    null
                }
                else -> json
            }

            val targetJson = targetJsonObj
            if (targetJson != null) {
                if (promptText.isEmpty()) {
                    promptText = targetJson.optString("prompt", "")
                }
                if (contextData.isEmpty()) {
                    contextData = targetJson.optString("context_data", "")
                }
                if (imageBase64.isNullOrBlank() && targetJson.has("image_base64")) {
                    imageBase64 = targetJson.optString("image_base64", "")
                }
                if (imageUri.isNullOrBlank() && targetJson.has("image_uri")) {
                    imageUri = targetJson.optString("image_uri", "")
                }
                if (targetJson.has("downsample")) {
                    downsampleSetting = targetJson.optBoolean("downsample", downsampleSetting)
                }
                if (targetJson.has("interactive_bubble")) {
                    interactiveExtra = interactiveExtra || targetJson.optBoolean("interactive_bubble", false)
                }
            }

            if (promptText.isEmpty() && json.has("prompt")) {
                promptText = json.optString("prompt", "")
            }
        } catch (e: Exception) {
            Log.w(TAG, "Error parsing payload JSON: ${e.message}")
        }

        val isSilentMode = launchIntent.getBooleanExtra("silent", false) ||
            launchIntent.getBooleanExtra("headless_silent", false) ||
            (targetJsonObj != null && (targetJsonObj.optBoolean("silent", false) || targetJsonObj.optBoolean("headless_silent", false)))

        isInteractiveMode = !isSilentMode && (isAssistAction || interactiveExtra || methodName == "open_assistant_bubble")
        Log.d(
            TAG,
            "[OVERLAY LAUNCHED] Caller: $callerName | Interactive: $isInteractiveMode | Silent: $isSilentMode | Method: $methodName"
        )

        if (isSilentMode) {
            setupSilentHeadlessMode(
                methodName = methodName,
                promptText = promptText,
                imageBase64 = imageBase64,
                imageUri = imageUri,
                downsample = downsampleSetting
            )
        } else if (isInteractiveMode) {
            setupInteractiveBubbleSheet(
                initialPrompt = promptText,
                initialImageBase64 = imageBase64,
                initialImageUri = imageUri
            )
        } else {
            setupHeadlessOneShotPill(
                methodName = methodName,
                promptText = promptText,
                imageBase64 = imageBase64,
                imageUri = imageUri,
                downsample = downsampleSetting
            )
        }
    }

    /**
     * Called when `PaiosVoiceInteractionSession` receives a system screenshot from the OS.
     * Scales and converts the bitmap on `Dispatchers.IO` so the UI thread never drops frames.
     */
    fun onSystemAssistScreenshotAvailable(bitmap: Bitmap) {
        if (!isInteractiveMode) return
        downsampleSetting = resolveDownsampleSetting()
        activityScope.launch {
            val processed = withContext(Dispatchers.IO) {
                try {
                    val softBmp = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                        bitmap.config == Bitmap.Config.HARDWARE
                    ) {
                        bitmap.copy(Bitmap.Config.ARGB_8888, false) ?: bitmap
                    } else {
                        bitmap
                    }
                    if (downsampleSetting &&
                        (softBmp.width > MAX_DOWNSAMPLE_DIMENSION || softBmp.height > MAX_DOWNSAMPLE_DIMENSION)
                    ) {
                        val scale = MAX_DOWNSAMPLE_DIMENSION.toFloat() / maxOf(softBmp.width, softBmp.height).toFloat()
                        Bitmap.createScaledBitmap(
                            softBmp,
                            (softBmp.width * scale).toInt().coerceAtLeast(1),
                            (softBmp.height * scale).toInt().coerceAtLeast(1),
                            true
                        )
                    } else {
                        softBmp
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Error scaling assist screenshot: ${e.message}")
                    bitmap
                }
            }
            withContext(Dispatchers.Main) {
                attachScreenContext(processed)
            }
        }
    }

    /**
     * Called when `PaiosVoiceInteractionSession` extracts text from the foreground screen's `AssistStructure`.
     */
    fun onSystemAssistContextAvailable(callerPkg: String, screenText: String) {
        if (!isInteractiveMode) return
        val defaultAssist = tr("assistant_context_default")
        if (callerPkg.isNotBlank() && callerPkg != "Screen") {
            if (rawCallerPackage.isBlank()) {
                rawCallerPackage = callerPkg
                discoverLiveMeshContext(callerPkg)
            }
            if (callerName == defaultAssist) {
                callerName = formatShortCaller(callerPkg)
            }
        }
        if (screenText.isNotBlank() && !contextData.contains(screenText.take(60))) {
            contextData = if (contextData.isBlank()) {
                "Screen Content ($callerName):\n$screenText"
            } else {
                "$contextData\n\nScreen Content ($callerName):\n$screenText"
            }
        }
        updateContextBadgeUI()
    }

    private fun updateContextBadgeUI() {
        val hasImage = attachedBitmaps.isNotEmpty() || currentBitmap != null
        val hasContext = contextData.isNotBlank()
        val visionStr = tr("assistant_context_vision")
        val contextStr = tr("assistant_context_data")
        val label = when {
            hasImage && hasContext -> "$callerName • $visionStr + $contextStr"
            hasImage -> "$callerName • $visionStr"
            hasContext -> "$callerName • $contextStr"
            else -> callerName
        }
        callerBadgeView?.text = label
    }

    /**
     * Queries the active foreground Puzzak Mesh node (if the user invoked the Assistant while
     * inside a Mesh-enabled app) on `Dispatchers.IO` to enrich the assistant bubble with live
     * environment/telemetry context without cold-spawning unrelated background apps.
     */
    private fun discoverLiveMeshContext(targetPkg: String = rawCallerPackage) {
        val candidatePkg = targetPkg.trim()
        if (candidatePkg.isEmpty() ||
            candidatePkg == packageName ||
            candidatePkg.contains("launcher", ignoreCase = true) ||
            candidatePkg == "com.android.settings" ||
            candidatePkg == "com.android.systemui"
        ) {
            return
        }
        activityScope.launch(Dispatchers.IO) {
            try {
                val pm = packageManager
                val authority = "$candidatePkg.mesh"
                if (pm.resolveContentProvider(authority, 0) == null) {
                    return@launch
                }

                val collectedSnippets = mutableListOf<String>()
                var primaryMeshApp: String? = null

                try {
                    val uri = Uri.parse("content://$authority")
                    val toolsBundle = contentResolver.call(uri, "query_tools", null, null)
                    val toolsJsonStr = toolsBundle?.getString("response") ?: return@launch
                    val toolsArr = JSONArray(toolsJsonStr)
                    for (i in 0 until toolsArr.length()) {
                        val toolObj = toolsArr.optJSONObject(i) ?: continue
                        val toolName = toolObj.optString("name", "")
                        val isAutoContext = toolObj.optBoolean("autoContext", false)
                        val isContextTool = isAutoContext ||
                            toolName.contains("get_environment") ||
                            toolName.contains("get_status") ||
                            toolName.contains("get_state") ||
                            toolName.contains("get_components")
                        if (isContextTool) {
                            val callPayload = JSONObject().apply {
                                put("jsonrpc", "2.0")
                                put("id", "assist-ctx-$toolName")
                                put("method", toolName)
                                put("params", JSONObject())
                            }.toString()
                            val extras = Bundle().apply { putString("payload", callPayload) }
                            val resBundle = contentResolver.call(uri, "call_tool", callPayload, extras)
                            val resStr = resBundle?.getString("response")
                            if (!resStr.isNullOrBlank() && !resStr.contains("HEADLESS_OVERLAY_REQUIRED")) {
                                val parsed = JSONObject(resStr)
                                val resultNode = parsed.opt("result")
                                if (resultNode != null) {
                                    val appShort = authority.removeSuffix(".mesh").substringAfterLast('.')
                                    if (primaryMeshApp == null) {
                                        primaryMeshApp = appShort.replaceFirstChar { it.uppercase() }
                                    }
                                    collectedSnippets.add("[$toolName]: $resultNode")
                                }
                            }
                        }
                    }
                } catch (e: Exception) {
                    Log.d(TAG, "Mesh context probe skipped for $authority: ${e.message}")
                }

                if (collectedSnippets.isNotEmpty()) {
                    val meshSummary = collectedSnippets.joinToString("\n").take(2500)
                    withContext(Dispatchers.Main) {
                        val defaultAssist = tr("assistant_context_default")
                        if (callerName == defaultAssist && primaryMeshApp != null) {
                            callerName = primaryMeshApp!!
                        }
                        if (!contextData.contains(meshSummary.take(40))) {
                            contextData = if (contextData.isBlank()) {
                                "Live Mesh Telemetry:\n$meshSummary"
                            } else {
                                "$contextData\n\nLive Mesh Telemetry:\n$meshSummary"
                            }
                        }
                        updateContextBadgeUI()
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "discoverLiveMeshContext error: ${e.message}")
            }
        }
    }

    /**
     * Decodes a Bitmap from [imageUriStr] or [imageBase64] and optionally downsamples
     * so the longest edge is at most [MAX_DOWNSAMPLE_DIMENSION] (768px).
     */
    private fun decodeVisualBitmap(
        imageBase64: String?,
        imageUriStr: String?,
        downsample: Boolean
    ): Bitmap? {
        try {
            val rawBitmap: Bitmap = when {
                !imageUriStr.isNullOrBlank() -> {
                    if (imageUriStr.startsWith("content://") || imageUriStr.startsWith("file://")) {
                        contentResolver.openInputStream(Uri.parse(imageUriStr))?.use {
                            BitmapFactory.decodeStream(it)
                        }
                    } else {
                        val file = File(imageUriStr)
                        if (file.exists()) {
                            BitmapFactory.decodeFile(file.absolutePath)
                        } else {
                            null
                        }
                    }
                }
                !imageBase64.isNullOrBlank() -> {
                    val clean = imageBase64.substringAfter("base64,", imageBase64).trim()
                    val bytes = Base64.decode(clean, Base64.DEFAULT)
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
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
            Log.e(TAG, "Failed to decode visual context bitmap: ${e.message}", e)
            return null
        }
    }

    // =========================================================================
    // MODE C: SUPER-MINIMAL SILENT HEADLESS MODE FOR BACKGROUND / TIMED TASKS
    // =========================================================================
    private fun setupSilentHeadlessMode(
        methodName: String,
        promptText: String,
        imageBase64: String?,
        imageUri: String?,
        downsample: Boolean
    ) {
        window.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
        window.clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
        window.addFlags(
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
        )
        setFinishOnTouchOutside(false)

        val invisibleView = View(this).apply {
            layoutParams = ViewGroup.LayoutParams(1, 1)
            visibility = View.INVISIBLE
        }
        setContentView(invisibleView)
        window?.setLayout(1, 1)
        window?.setGravity(Gravity.TOP or Gravity.START)

        activityScope.launch(Dispatchers.IO) {
            try {
                if (methodName == "query_local_ai" || (methodName.isEmpty() && promptText.isNotEmpty())) {
                    val bitmap = decodeVisualBitmap(imageBase64, imageUri, downsample)
                    val effectivePrompt = if (contextData.isNotBlank()) {
                        "$promptText\n\nContext:\n$contextData"
                    } else {
                        promptText
                    }
                    val generativeModel = Generation.getClient()
                    val request = if (bitmap != null) {
                        generateContentRequest(ImagePart(bitmap), TextPart(effectivePrompt)) {}
                    } else {
                        generateContentRequest(TextPart(effectivePrompt)) {}
                    }
                    val response: GenerateContentResponse = generativeModel.generateContent(request)
                    val text = response.candidates.firstOrNull()?.text ?: ""

                    val resultObj = JSONObject().apply {
                        put("status", "success")
                        put("prompt", promptText)
                        put("response", text)
                        put("vision", bitmap != null)
                        put("silent", true)
                        put("engine", "Gemini Nano (Mesh Silent Overlay)")
                    }
                    val responseJson = JSONObject().apply {
                        put("jsonrpc", "2.0")
                        put("id", callId)
                        put("result", resultObj)
                    }.toString()

                    sendResult(responseJson)
                } else {
                    val errorObj = JSONObject().apply {
                        put("code", -32601)
                        put("message", "Method '$methodName' not supported in MeshOverlayActivity")
                    }
                    val responseJson = JSONObject().apply {
                        put("jsonrpc", "2.0")
                        put("id", callId)
                        put("error", errorObj)
                    }.toString()

                    sendResult(responseJson)
                }
            } catch (e: Exception) {
                Log.e(TAG, "[SILENT INFERENCE ERROR] ${e.message}", e)
                val errorObj = JSONObject().apply {
                    put("code", -32603)
                    put("message", "Gemini Nano inference failed: ${e.message ?: "Unknown error"}")
                }
                val responseJson = JSONObject().apply {
                    put("jsonrpc", "2.0")
                    put("id", callId)
                    put("error", errorObj)
                }.toString()

                sendResult(responseJson)
            } finally {
                withContext(Dispatchers.Main) {
                    finishAndRemoveTask()
                }
            }
        }
    }

    // =========================================================================
    // MODE A: HEADLESS / ONE-SHOT RPC PILL
    // =========================================================================
    private fun setupHeadlessOneShotPill(
        methodName: String,
        promptText: String,
        imageBase64: String?,
        imageUri: String?,
        downsample: Boolean
    ) {
        val screenWidth = resources.displayMetrics.widthPixels
        val targetCardWidth = (screenWidth - dp(OUTER_PADDING_HORIZONTAL_DP * 2)).coerceAtLeast(dp(280))

        window.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
        window.clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
        window.addFlags(
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
        )
        setFinishOnTouchOutside(false)

        val rootLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            minimumWidth = screenWidth
            setPadding(
                dp(OUTER_PADDING_HORIZONTAL_DP),
                0,
                dp(OUTER_PADDING_HORIZONTAL_DP),
                dp(OUTER_PADDING_BOTTOM_DP)
            )
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }

        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            minimumWidth = targetCardWidth
            setPadding(
                dp(CARD_PADDING_HORIZONTAL_DP),
                dp(CARD_PADDING_VERTICAL_DP),
                dp(CARD_PADDING_HORIZONTAL_DP),
                dp(CARD_PADDING_VERTICAL_DP)
            )
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(CARD_CORNER_RADIUS_DP).toFloat()
                setColor(palette.cardBg)
                setStroke(dp(CARD_BORDER_WIDTH_DP), palette.sheetBorder)
            }
            elevation = dp(CARD_ELEVATION_DP).toFloat()
            layoutParams = LinearLayout.LayoutParams(
                targetCardWidth,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = Gravity.CENTER_HORIZONTAL
            }
        }

        val headerRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }

        val sparkleIcon = ImageView(this).apply {
            setImageDrawable(
                M3VectorDrawable(
                    M3IconType.SPARKLE,
                    palette.accent,
                    dp(18)
                )
            )
            layoutParams = LinearLayout.LayoutParams(dp(18), dp(18)).apply {
                rightMargin = dp(8)
            }
        }
        headerRow.addView(sparkleIcon)

        val titleView = TextView(this).apply {
            text = tr("assistant_headless_title")
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            setTextColor(palette.bodyText)
            isSingleLine = true
            ellipsize = TextUtils.TruncateAt.END
        }
        headerRow.addView(titleView)
        card.addView(headerRow)

        val statusView = TextView(this).apply {
            text = tr("assistant_status_processing")
            setTextSize(TypedValue.COMPLEX_UNIT_SP, SUBTITLE_TEXT_SIZE_SP)
            setTextColor(palette.subtitle)
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                topMargin = dp(4)
            }
        }
        card.addView(statusView)

        val progressBar = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            isIndeterminate = true
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(PROGRESS_BAR_HEIGHT_DP)
            ).apply {
                topMargin = dp(10)
            }
            indeterminateDrawable?.setTint(palette.accent)
        }
        card.addView(progressBar)

        rootLayout.addView(card)
        setContentView(rootLayout)

        window?.setLayout(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT
        )
        window?.setGravity(Gravity.BOTTOM)

        activityScope.launch(Dispatchers.IO) {
            try {
                if (methodName == "query_local_ai" || (methodName.isEmpty() && promptText.isNotEmpty())) {
                    val bitmap = decodeVisualBitmap(imageBase64, imageUri, downsample)
                    val effectivePrompt = if (contextData.isNotBlank()) {
                        "$promptText\n\nContext:\n$contextData"
                    } else {
                        promptText
                    }
                    Log.d(
                        TAG,
                        "[INFERENCE START] Prompt length: ${effectivePrompt.length} | Vision: ${bitmap != null}"
                    )
                    val generativeModel = Generation.getClient()
                    val request = if (bitmap != null) {
                        generateContentRequest(ImagePart(bitmap), TextPart(effectivePrompt)) {}
                    } else {
                        generateContentRequest(TextPart(effectivePrompt)) {}
                    }
                    val response: GenerateContentResponse = generativeModel.generateContent(request)
                    val text = response.candidates.firstOrNull()?.text ?: ""
                    Log.d(TAG, "[INFERENCE COMPLETE] Generated ${text.length} chars")

                    val resultObj = JSONObject().apply {
                        put("status", "success")
                        put("prompt", promptText)
                        put("response", text)
                        put("vision", bitmap != null)
                        put("engine", "Gemini Nano (Mesh Overlay)")
                    }
                    val responseJson = JSONObject().apply {
                        put("jsonrpc", "2.0")
                        put("id", callId)
                        put("result", resultObj)
                    }.toString()

                    sendResult(responseJson)
                } else {
                    Log.w(TAG, "[UNSUPPORTED METHOD] $methodName")
                    val errorObj = JSONObject().apply {
                        put("code", -32601)
                        put("message", "Method '$methodName' not supported in MeshOverlayActivity")
                    }
                    val responseJson = JSONObject().apply {
                        put("jsonrpc", "2.0")
                        put("id", callId)
                        put("error", errorObj)
                    }.toString()

                    sendResult(responseJson)
                }
            } catch (e: Exception) {
                Log.e(TAG, "[INFERENCE ERROR] ${e.message}", e)
                val errorObj = JSONObject().apply {
                    put("code", -32603)
                    put("message", "Gemini Nano inference failed: ${e.message ?: "Unknown error"}")
                }
                val responseJson = JSONObject().apply {
                    put("jsonrpc", "2.0")
                    put("id", callId)
                    put("error", errorObj)
                }.toString()

                sendResult(responseJson)
            } finally {
                withContext(Dispatchers.Main) {
                    finishAndRemoveTask()
                }
            }
        }
    }

    private fun resolveActivePersona(): String {
        val fromIntent = intent?.getStringExtra("persona") ?: intent?.getStringExtra("prompt_id")
        if (!fromIntent.isNullOrBlank()) return fromIntent.lowercase(Locale.ROOT)

        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val prefPersona = prefs.getString("flutter.defaultPromptId", null)
            if (!prefPersona.isNullOrBlank()) return prefPersona.lowercase(Locale.ROOT)
        } catch (_: Exception) {}

        return "system_default"
    }

    private fun resolveActivePersonaContent(): String {
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val prefContent = prefs.getString("flutter.defaultPromptContent", null)
            if (!prefContent.isNullOrBlank()) {
                return prefContent.trim()
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to read defaultPromptContent from prefs: ${e.message}")
        }

        val personaId = resolveActivePersona()
        try {
            val assetPath = "flutter_assets/assets/prompts/$personaId.md"
            val content = assets.open(assetPath).bufferedReader().use { it.readText() }.trim()
            if (content.isNotBlank()) {
                return content
            }
        } catch (_: Exception) {}

        return ""
    }

    private fun getPersonaGreeting(persona: String, lang: String): String {
        val isUk = lang == "uk"
        val isDe = lang == "de"
        val isTr = lang == "tr"
        val isZh = lang == "zh"

        val phrases = when {
            persona.contains("pirate") -> {
                if (isUk) {
                    listOf(
                        "Агов, капітане! Який курс прокладаємо сьогодні?",
                        "Грім і блискавка! Які скарби чи пригоди нас чекають?",
                        "Йо-хо-хо! Готовий до здобичі нових знань, друже?",
                        "Свистати всіх нагору! Який твій наказ, капітане?",
                        "Агов! Компас налаштований, куди тримаємо курс?",
                        "Слухаю уважно, морський вовче! Що маємо розвідати?",
                        "Які таємниці семи морів розгадаємо сьогодні?"
                    )
                } else if (isDe) {
                    listOf(
                        "Ahoi, Kapitän! Welchen Kurs setzen wir heute?",
                        "Beim Klabautermann! Welche Schätze oder Abenteuer warten auf uns?",
                        "Aye! Bereit, neues Wissen zu erbeuten, Kumpel?",
                        "Alle Mann an Deck! Was ist dein Befehl, Kapitän?",
                        "Ahoi! Der Kompass steht bereit – wohin segeln wir?"
                    )
                } else {
                    listOf(
                        "Ahoy, captain! What course are we chartin' today?",
                        "Shiver me timbers! What treasures or troubles await?",
                        "Aye! Ready to plunder some knowledge, matey?",
                        "Ahoy! The compass is set—what's yer command?",
                        "All hands on deck! What wisdom do ye seek from the deep?",
                        "Avast ye! Speak yer mind, or walk the plank!",
                        "Ahoy, scallywag! Need a hand with yer next adventure?"
                    )
                }
            }
            persona.contains("terminal") || persona.contains("code") || persona.contains("concise") || persona.contains("old") -> {
                if (isUk) {
                    listOf(
                        "Термінал готовий. Очікую введення.",
                        "Система онлайн. Який запит?",
                        "Готовий. Вкажіть завдання.",
                        "Демон PAIOS активний. Очікую команди.",
                        "Готовий до виконання інструкцій.",
                        "Потік введення відкритий. Що оптимізуємо?",
                        "На зв'язку. Введіть директиву."
                    )
                } else if (isDe) {
                    listOf(
                        "Terminal bereit. Warte auf Eingabe.",
                        "System online. Was ist die Anfrage?",
                        "Bereit. Ziel angeben.",
                        "PAIOS Daemon aktiv. Warte auf Befehle.",
                        "Eingabekanal offen. Wie kann ich helfen?"
                    )
                } else {
                    listOf(
                        "Terminal ready. Awaiting input.",
                        "System online. What is the query?",
                        "Ready. State the objective.",
                        "PAIOS daemon active. Listening on stdin.",
                        "Ready for task execution.",
                        "Prompt required. Standing by.",
                        "Input stream open. How can I optimize your workflow?"
                    )
                }
            }
            persona.contains("creative") || persona.contains("writer") -> {
                if (isUk) {
                    listOf(
                        "Іскра натхнення напоготові! Що творимо сьогодні?",
                        "Створимо щось дивовижне разом. Яка ідея?",
                        "Чисте полотно чекає. Який задум розкриємо?",
                        "Готовий до брейншторму! Діліться будь-якою думкою.",
                        "Натхнення заряджено. Що досліджуємо?",
                        "Кожна чудова історія починається з ідеї. Яка у вас?"
                    )
                } else {
                    listOf(
                        "Spark of creativity ready! What are we imagining today?",
                        "Let's create something brilliant together. What's the idea?",
                        "A blank canvas awaits. What story or concept shall we explore?",
                        "Ready to brainstorm! Throw any thought my way.",
                        "Inspired and ready. What world are we building?",
                        "Every great journey starts with an idea. What's yours?"
                    )
                }
            }
            else -> {
                if (isUk) {
                    listOf(
                        "Готовий допомогти! Над чим працюємо?",
                        "Чим можу допомогти просто зараз?",
                        "PAIOS напоготові. Що у вас на думці?",
                        "До ваших послуг! Що потрібно зробити?",
                        "Слухаю вас! Запитуйте або покажіть екран.",
                        "Привіт! Я на зв'язку, готовий до дій.",
                        "Яке завдання вирішуємо сьогодні?"
                    )
                } else if (isDe) {
                    listOf(
                        "Bereit zu helfen! Woran arbeiten wir?",
                        "Wie kann ich dir jetzt helfen?",
                        "PAIOS steht bereit. Was liegt an?",
                        "Zu deinen Diensten! Was brauchst du?",
                        "Ich höre zu! Frag mich etwas oder zeige deinen Bildschirm.",
                        "Hallo! Ich bin einsatzbereit."
                    )
                } else if (isTr) {
                    listOf(
                        "Yardım etmeye hazırım! Bugün ne üzerinde çalışıyoruz?",
                        "Şu anda size nasıl yardımcı olabilirim?",
                        "PAIOS hazır. Aklınızda ne var?",
                        "Hizmetinizdeyim! Ne yapmamı istersiniz?",
                        "Dinliyorum! Bana bir şey sorun veya ekranınızı paylaşın."
                    )
                } else if (isZh) {
                    listOf(
                        "随时待命！今天我们要处理什么？",
                        "现在有什么我可以帮您的吗？",
                        "PAIOS 已准备就绪。有什么想法？",
                        "为您服务！需要做些什么？",
                        "我正在倾听！随时提问或分享屏幕。"
                    )
                } else {
                    listOf(
                        "Ready to assist! What are we working on?",
                        "How can I help you right now?",
                        "PAIOS is ready. What's on your mind?",
                        "At your service! What do you need?",
                        "I'm listening! Ask me anything or share your screen.",
                        "Hey there! Ready whenever you are.",
                        "What can I solve for you today?"
                    )
                }
            }
        }
        val available = if (phrases.size > 1 && lastGreetingPhrase != null) {
            phrases.filter { it != lastGreetingPhrase }
        } else {
            phrases
        }
        val chosen = available.random()
        lastGreetingPhrase = chosen
        return chosen
    }

    // =========================================================================
    // MODE B: MATERIAL 3 EXPRESSIVE INTERACTIVE ASSISTANT SHEET
    // =========================================================================
    @Suppress("DEPRECATION", "ClickableViewAccessibility")
    private fun setupInteractiveBubbleSheet(
        initialPrompt: String,
        initialImageBase64: String?,
        initialImageUri: String?
    ) {
        val screenWidth = resources.displayMetrics.widthPixels
        val screenHeight = resources.displayMetrics.heightPixels
        val targetCardWidth = (screenWidth - dp(OUTER_PADDING_HORIZONTAL_DP * 2)).coerceAtLeast(dp(300))
        val compactScrollHeightPx = dp(260)
        val expandedScrollHeightPx = (screenHeight * 0.60f).toInt().coerceAtLeast(dp(380))
        currentScrollMaxHeightPx = compactScrollHeightPx
        isSheetExpanded = false
        downsampleSetting = if (intent.hasExtra("downsample")) {
            intent.getBooleanExtra("downsample", true)
        } else {
            resolveDownsampleSetting()
        }

        window.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
        window.clearFlags(
            WindowManager.LayoutParams.FLAG_DIM_BEHIND or
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
        )
        window.addFlags(WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH)
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
        }
        setFinishOnTouchOutside(true)

        // Full-screen transparent container so tapping anywhere above the sheet closes it
        val rootContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            minimumWidth = screenWidth
            minimumHeight = screenHeight
            background = ColorDrawable(Color.TRANSPARENT)
            setPadding(
                dp(OUTER_PADDING_HORIZONTAL_DP),
                dp(48),
                dp(OUTER_PADDING_HORIZONTAL_DP),
                dp(OUTER_PADDING_BOTTOM_DP)
            )
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            isClickable = true
            setOnClickListener {
                dismissSheetAnimated()
            }
        }

        ViewCompat.setOnApplyWindowInsetsListener(rootContainer) { _, insets ->
            val imeBottom = insets.getInsets(WindowInsetsCompat.Type.ime()).bottom
            val sysInsets = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            val bottomInset = maxOf(imeBottom, sysInsets.bottom)
            val topInset = sysInsets.top

            rootContainer.setPadding(
                dp(OUTER_PADDING_HORIZONTAL_DP),
                topInset + dp(8),
                dp(OUTER_PADDING_HORIZONTAL_DP),
                bottomInset + dp(OUTER_PADDING_BOTTOM_DP)
            )
            insets
        }

        val sheetCard = object : LinearLayout(this) {
            override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
                val availableH = MeasureSpec.getSize(heightMeasureSpec)
                val maxAllowedCardH = (availableH * 0.98f).toInt()
                val maxCompactH = (availableH * 0.60f).toInt().coerceIn(dp(240), dp(400))

                val scroll = outputScrollView
                val scrollLp = scroll?.layoutParams as? LayoutParams

                // Maintain consistent weight layout params so measurement does not shift child container by 70px
                if (scrollLp != null && (scrollLp.weight != 1f || scrollLp.height != 0)) {
                    scrollLp.weight = 1f
                    scrollLp.height = 0
                }

                if (layoutParams.height == ViewGroup.LayoutParams.WRAP_CONTENT) {
                    // 1. Measure non-scroll children to find their total vertical space
                    val childWidth = (MeasureSpec.getSize(widthMeasureSpec) - paddingLeft - paddingRight).coerceAtLeast(dp(200))
                    val childWidthSpec = MeasureSpec.makeMeasureSpec(childWidth, MeasureSpec.EXACTLY)
                    var fixedViewsH = paddingTop + paddingBottom
                    for (i in 0 until childCount) {
                        val child = getChildAt(i)
                        if (child === scroll || child.visibility == View.GONE) continue
                        val lp = child.layoutParams as? LayoutParams
                        val topM = lp?.topMargin ?: 0
                        val bottomM = lp?.bottomMargin ?: 0
                        child.measure(
                            childWidthSpec,
                            MeasureSpec.makeMeasureSpec(availableH, MeasureSpec.AT_MOST)
                        )
                        fixedViewsH += child.measuredHeight + topM + bottomM
                    }

                    // 2. Measure scroll's inner content (msgList) to know its natural wrap height
                    val msgList = messagesContainer
                    val msgListH = if (msgList != null) {
                        msgList.measure(
                            childWidthSpec,
                            MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
                        )
                        msgList.measuredHeight
                    } else {
                        dp(60)
                    }

                    val scrollMargins = (scrollLp as? ViewGroup.MarginLayoutParams)?.let {
                        it.topMargin + it.bottomMargin
                    } ?: dp(12)

                    val naturalScrollH = msgListH + scrollMargins
                    val maxScrollH = (maxCompactH - fixedViewsH).coerceAtLeast(dp(60))
                    val finalScrollH = naturalScrollH.coerceAtMost(maxScrollH)

                    val targetCardH = (fixedViewsH + finalScrollH).coerceAtMost(maxAllowedCardH)
                    val exactSpec = MeasureSpec.makeMeasureSpec(targetCardH, MeasureSpec.EXACTLY)
                    super.onMeasure(widthMeasureSpec, exactSpec)
                } else {
                    val targetH = layoutParams.height.coerceAtMost(maxAllowedCardH)
                    val exactSpec = MeasureSpec.makeMeasureSpec(targetH, MeasureSpec.EXACTLY)
                    super.onMeasure(widthMeasureSpec, exactSpec)
                }
            }
        }.apply {
            orientation = LinearLayout.VERTICAL
            minimumWidth = targetCardWidth
            isClickable = true // Consume touches inside sheet so they don't trigger rootContainer dismiss
            setPadding(
                dp(CARD_PADDING_HORIZONTAL_DP),
                dp(6),
                dp(CARD_PADDING_HORIZONTAL_DP),
                dp(CARD_PADDING_VERTICAL_DP)
            )
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(CARD_CORNER_RADIUS_DP).toFloat()
                setColor(palette.cardBg)
                setStroke(dp(CARD_BORDER_WIDTH_DP), palette.sheetBorder)
            }
            elevation = dp(CARD_ELEVATION_DP).toFloat()
            layoutParams = LinearLayout.LayoutParams(
                targetCardWidth,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = Gravity.CENTER_HORIZONTAL
            }
        }
        sheetCardView = sheetCard

        // 1. Symmetrical Top Bar: Clean Centered Drag Handle + Subtle Circular Close Button (✕)
        val topBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            isClickable = true
            setPadding(dp(4), dp(2), dp(4), dp(4))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }

        val openInFullBtn = ImageView(this).apply {
            scaleType = ImageView.ScaleType.CENTER
            contentDescription = tr("open_in_app")
            setImageDrawable(
                M3VectorDrawable(
                    M3IconType.OPEN_IN_FULL,
                    palette.subtitle,
                    dp(14)
                )
            )
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(palette.chipBg)
                setStroke(dp(1), palette.cardBorder)
            }
            layoutParams = LinearLayout.LayoutParams(dp(32), dp(32))
            setOnClickListener {
                it.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
                openInFullApp()
            }
        }
        topBar.addView(openInFullBtn)

        val dragCenterContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            isClickable = false
            layoutParams = LinearLayout.LayoutParams(0, dp(32), 1f)
        }

        val dragHandlePill = View(this).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(2).toFloat()
                setColor(palette.dragHandle)
            }
            layoutParams = LinearLayout.LayoutParams(dp(36), dp(4))
        }
        dragCenterContainer.addView(dragHandlePill)
        topBar.addView(dragCenterContainer)

        val closeBtn = ImageView(this).apply {
            scaleType = ImageView.ScaleType.CENTER
            contentDescription = tr("close")
            setImageDrawable(
                M3VectorDrawable(
                    M3IconType.CLOSE,
                    palette.subtitle,
                    dp(13)
                )
            )
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(palette.chipBg)
                setStroke(dp(1), palette.cardBorder)
            }
            layoutParams = LinearLayout.LayoutParams(dp(32), dp(32))
            setOnClickListener {
                dismissSheetAnimated()
            }
        }
        topBar.addView(closeBtn)
        sheetCard.addView(topBar)

        // Anchored bottom stretching drag handle: keeps bottom edge anchored to screen / IME keyboard
        var touchDownRawY = 0f
        var initialSheetHeight = 0
        var startExpandedState = false
        var draggingSheet = false

        val dragTouchListener = View.OnTouchListener { _, ev ->
            if (isDismissing) return@OnTouchListener true
            val availableH = (rootContainer.height - rootContainer.paddingBottom - rootContainer.paddingTop).coerceAtLeast(dp(300))
            val maxAllowedH = (availableH * 0.98f).toInt()

            when (ev.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    activeSheetAnimator?.cancel()
                    touchDownRawY = ev.rawY
                    initialSheetHeight = if (sheetCard.height > 0) sheetCard.height else calculateCompactTargetHeight()
                    startExpandedState = isSheetExpanded
                    draggingSheet = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val rawTouchH = (rootContainer.height - ev.rawY - rootContainer.paddingBottom).toInt()
                    val deltaY = ev.rawY - touchDownRawY
                    if (abs(deltaY) > dp(8)) {
                        draggingSheet = true
                    }
                    val rawTouchHDown = (rootContainer.height - touchDownRawY - rootContainer.paddingBottom).toInt()
                    val touchOffsetFromTop = initialSheetHeight - rawTouchHDown
                    val targetH = rawTouchH + touchOffsetFromTop

                    // Quick dismiss on deliberate pull down during move
                    if (!startExpandedState && deltaY > dp(90)) {
                        dismissSheetAnimated()
                        return@OnTouchListener true
                    }
                    if (startExpandedState && targetH < dp(140)) {
                        dismissSheetAnimated()
                        return@OnTouchListener true
                    }

                    // Rubber-band resistance when pulling down past minimum
                    val minDragH = if (startExpandedState) {
                        dp(180)
                    } else {
                        (initialSheetHeight - dp(80)).coerceAtLeast(dp(120))
                    }
                    sheetCard.layoutParams.height = targetH.coerceIn(minDragH, maxAllowedH)
                    sheetCard.requestLayout()
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    val totalDeltaY = ev.rawY - touchDownRawY
                    val currentH = sheetCard.height.coerceAtLeast(dp(100))
                    val targetCompactH = calculateCompactTargetHeight()

                    // 1. A tap on the handlebar or top bar NEVER dismisses; toggles expansion smoothly
                    if (!draggingSheet || abs(totalDeltaY) <= dp(8)) {
                        sheetCard.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
                        val targetExpanded = !isSheetExpanded
                        if (targetExpanded) {
                            animateSheetHeight(sheetCard, currentH, maxAllowedH) {
                                toggleSheetExpanded(true, compactScrollHeightPx, expandedScrollHeightPx)
                            }
                        } else {
                            animateSheetHeight(sheetCard, currentH, targetCompactH) {
                                sheetCard.layoutParams.height = ViewGroup.LayoutParams.WRAP_CONTENT
                                sheetCard.requestLayout()
                                toggleSheetExpanded(false, compactScrollHeightPx, expandedScrollHeightPx)
                            }
                        }
                        return@OnTouchListener true
                    }

                    // 2. Deliberate downward drag to dismiss
                    if (!startExpandedState) {
                        if (totalDeltaY > dp(70)) {
                            dismissSheetAnimated()
                            return@OnTouchListener true
                        } else if (totalDeltaY > 0) {
                            // User pulled down slightly but not enough to dismiss: bounce back to compact
                            animateSheetHeight(sheetCard, currentH, targetCompactH) {
                                sheetCard.layoutParams.height = ViewGroup.LayoutParams.WRAP_CONTENT
                                sheetCard.requestLayout()
                                toggleSheetExpanded(false, compactScrollHeightPx, expandedScrollHeightPx)
                            }
                            return@OnTouchListener true
                        }
                    } else {
                        if (currentH < targetCompactH - dp(40) || totalDeltaY > (initialSheetHeight - dp(120))) {
                            dismissSheetAnimated()
                            return@OnTouchListener true
                        }
                    }

                    // 3. Settle to expanded or compact based on midpoint threshold
                    val midpoint = (targetCompactH + maxAllowedH) / 2
                    if (currentH > midpoint) {
                        animateSheetHeight(sheetCard, currentH, maxAllowedH) {
                            toggleSheetExpanded(true, compactScrollHeightPx, expandedScrollHeightPx)
                        }
                    } else {
                        animateSheetHeight(sheetCard, currentH, targetCompactH) {
                            sheetCard.layoutParams.height = ViewGroup.LayoutParams.WRAP_CONTENT
                            sheetCard.requestLayout()
                            toggleSheetExpanded(false, compactScrollHeightPx, expandedScrollHeightPx)
                        }
                    }
                    true
                }
                else -> false
            }
        }
        topBar.setOnTouchListener(dragTouchListener)

        // 2. Streaming Progress Indicator
        val progress = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            isIndeterminate = true
            visibility = View.GONE
            indeterminateDrawable?.setTint(palette.accent)
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(3)
            ).apply {
                topMargin = dp(4)
            }
        }
        sheetProgressBar = progress
        sheetCard.addView(progress)

        // 3. Scrollable Chat Bubble List (Clean ScrollView with isFillViewport = true)
        val scroll = ScrollView(this).apply {
            isFillViewport = true
            isVerticalScrollBarEnabled = true
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f
            ).apply {
                topMargin = dp(6)
                bottomMargin = dp(6)
            }
        }

        val msgList = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }

        // Persona Opening Greeting Bubble (0ms instant personality, localized)
        val welcomeCard = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(14), dp(12), dp(14), dp(12))
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(18).toFloat()
                setColor(palette.aiBubbleBg)
                setStroke(dp(1), palette.aiBubbleBorder)
            }
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }

        val welcomeIcon = ImageView(this).apply {
            setImageDrawable(
                M3VectorDrawable(
                    M3IconType.SPARKLE,
                    palette.accent,
                    dp(18)
                )
            )
            layoutParams = LinearLayout.LayoutParams(dp(18), dp(18)).apply {
                rightMargin = dp(10)
            }
        }
        welcomeCard.addView(welcomeIcon)

        val persona = resolveActivePersona()
        val activeLang = cachedLangCode ?: Locale.getDefault().language.lowercase(Locale.ROOT)
        val initialGreeting = getPersonaGreeting(persona, activeLang)

        val welcomeText = TextView(this).apply {
            text = initialGreeting
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13.5f)
            setTextColor(palette.bodyText)
            setLineSpacing(0f, 1.2f)
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        }
        welcomeCard.addView(welcomeText)

        emptyStateCard = welcomeCard
        msgList.addView(welcomeCard)
        scroll.addView(msgList)

        outputScrollView = scroll
        messagesContainer = msgList
        sheetCard.addView(scroll)

        // System Assist Screenshot Settings tip chip (shows when "Use screenshot" is disabled in OS settings)
        val screenshotEnabled = try {
            Settings.Secure.getInt(contentResolver, "assist_screenshot_enabled", 1) == 1
        } catch (_: Exception) {
            true
        }
        if (!screenshotEnabled) {
            val tipChip = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(12), dp(6), dp(12), dp(6))
                background = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = dp(14).toFloat()
                    setColor(palette.surfaceContainer)
                    setStroke(dp(1), palette.cardBorder)
                }
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
                ).apply {
                    topMargin = dp(4)
                    bottomMargin = dp(4)
                }
                isClickable = true
                setOnClickListener {
                    it.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
                    try {
                        startActivity(Intent(Settings.ACTION_VOICE_INPUT_SETTINGS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        })
                    } catch (e: Exception) {
                        try {
                            startActivity(Intent(Settings.ACTION_SETTINGS).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            })
                        } catch (_: Exception) {}
                    }
                }
            }

            val tipIcon = ImageView(this).apply {
                setImageDrawable(
                    M3VectorDrawable(
                        M3IconType.SPARKLE,
                        palette.accent,
                        dp(14)
                    )
                )
                layoutParams = LinearLayout.LayoutParams(dp(14), dp(14)).apply {
                    rightMargin = dp(8)
                }
            }
            tipChip.addView(tipIcon)

            val tipText = TextView(this).apply {
                text = "Enable 'Use screenshot' in Assistant Settings to analyze screen"
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 11.5f)
                typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
                setTextColor(palette.subtitle)
                isSingleLine = true
                ellipsize = TextUtils.TruncateAt.END
                layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
            }
            tipChip.addView(tipText)

            sheetCard.addView(tipChip)
        }

        // 4. Pending Image Attachment Preview Row (Horizontal scroll of attachments above input bar)
        val previewScroll = HorizontalScrollView(this).apply {
            visibility = View.GONE
            overScrollMode = View.OVER_SCROLL_NEVER
            isHorizontalScrollBarEnabled = false
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                topMargin = dp(4)
                bottomMargin = dp(4)
            }
        }

        val previewItemsLayout = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }
        previewScroll.addView(previewItemsLayout)

        imagePreviewContainer = previewScroll
        imagePreviewItemsRow = previewItemsLayout
        sheetCard.addView(previewScroll)

        // 5. Material 3 Bottom Input Bar: Fixed at the bottom of the sheet
        val inputRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                topMargin = dp(4)
            }
        }

        val cameraBtn = ImageView(this).apply {
            scaleType = ImageView.ScaleType.CENTER
            contentDescription = tr("attach_image")
            setImageDrawable(
                M3VectorDrawable(
                    M3IconType.ADD_PHOTO,
                    palette.accent,
                    dp(20)
                )
            )
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(palette.chipBg)
                setStroke(dp(1), palette.cardBorder)
            }
            layoutParams = LinearLayout.LayoutParams(dp(44), dp(44))
            setOnClickListener {
                it.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
                if (attachedBitmaps.size >= maxImagesAllowed) {
                    it.performHapticFeedback(HapticFeedbackConstants.REJECT)
                    Toast.makeText(this@MeshOverlayActivity, tr("max_images_reached"), Toast.LENGTH_SHORT).show()
                    return@setOnClickListener
                }
                try {
                    isLaunchingImagePicker = true
                    val pickIntent = Intent(Intent.ACTION_GET_CONTENT).apply {
                        type = "image/*"
                        addCategory(Intent.CATEGORY_OPENABLE)
                        putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                    }
                    startActivityForResult(pickIntent, REQUEST_CODE_BUBBLE_IMAGE)
                } catch (e: Exception) {
                    isLaunchingImagePicker = false
                    Log.e(TAG, "Failed to launch gallery picker from bubble: ${e.message}", e)
                }
            }
        }
        inputRow.addView(cameraBtn)

        val edit = EditText(this).apply {
            hint = tr("assistant_hint")
            setHintTextColor(palette.subtitle)
            setTextColor(palette.bodyText)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14.5f)
            maxLines = 3
            minimumHeight = dp(44)
            setPadding(dp(18), dp(10), dp(18), dp(10))
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(22).toFloat()
                setColor(palette.surfaceContainer)
                setStroke(dp(1), palette.cardBorder)
            }
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply {
                leftMargin = dp(8)
                rightMargin = dp(8)
            }
        }
        promptInput = edit
        inputRow.addView(edit)

        val sendBtn = ImageView(this).apply {
            scaleType = ImageView.ScaleType.CENTER
            setImageDrawable(
                M3VectorDrawable(
                    M3IconType.SEND,
                    palette.onAccent,
                    dp(19)
                )
            )
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(palette.accent)
            }
            layoutParams = LinearLayout.LayoutParams(dp(44), dp(44))
            setOnClickListener {
                it.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                val userText = edit.text?.toString()?.trim() ?: ""
                if (userText.isNotEmpty()) {
                    edit.setText("")
                    startInteractiveStreaming(userText)
                }
            }
        }
        inputRow.addView(sendBtn)

        sheetCard.addView(inputRow)
        rootContainer.addView(sheetCard)
        setContentView(rootContainer)

        // Ensure full window layout
        window?.setLayout(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT
        )
        window?.setGravity(Gravity.BOTTOM)

        // Subtle entrance slide-up animation
        sheetCard.translationY = dp(40).toFloat()
        sheetCard.alpha = 0f
        sheetCard.animate()
            .translationY(0f)
            .alpha(1f)
            .setDuration(200)
            .start()

        // Check for cached System Assist data (1500ms TTL, consumed once)
        val now = System.currentTimeMillis()
        if (now - latestAssistTimestampMs <= ASSIST_CACHE_TTL_MS) {
            latestAssistBitmap?.let { bmp ->
                onSystemAssistScreenshotAvailable(bmp)
                latestAssistBitmap = null
            }
            val cachedText = latestAssistScreenText
            val cachedPkg = latestAssistCallerPkg
            if (!cachedText.isNullOrBlank()) {
                onSystemAssistContextAvailable(cachedPkg ?: "", cachedText)
                latestAssistScreenText = null
            }
        } else {
            latestAssistBitmap = null
            latestAssistScreenText = null
            latestAssistCallerPkg = null
        }

        // Probe live Mesh sibling nodes
        discoverLiveMeshContext()

        activityScope.launch {
            if (!initialImageBase64.isNullOrBlank() || !initialImageUri.isNullOrBlank()) {
                val bmp = withContext(Dispatchers.IO) {
                    decodeVisualBitmap(initialImageBase64, initialImageUri, downsampleSetting)
                }
                if (bmp != null) {
                    withContext(Dispatchers.Main) {
                        attachGalleryBitmap(bmp)
                    }
                }
            }

            if (initialPrompt.isNotBlank()) {
                startInteractiveStreaming(initialPrompt)
            }
        }
    }

    private fun toggleSheetExpanded(
        expand: Boolean,
        compactHeightPx: Int = 0,
        expandedHeightPx: Int = 0
    ) {
        if (isSheetExpanded != expand) {
            sheetCardView?.performHapticFeedback(HapticFeedbackConstants.GESTURE_END)
        }
        isSheetExpanded = expand
        currentScrollMaxHeightPx = if (expand) expandedHeightPx else compactHeightPx
        if (!expand && sheetCardView?.layoutParams?.height != ViewGroup.LayoutParams.WRAP_CONTENT) {
            sheetCardView?.layoutParams?.height = ViewGroup.LayoutParams.WRAP_CONTENT
            sheetCardView?.requestLayout()
        }
        outputScrollView?.post { outputScrollView?.fullScroll(View.FOCUS_DOWN) }
    }

    private fun calculateCompactTargetHeight(): Int {
        val card = sheetCardView ?: return dp(220)
        val parent = card.parent as? ViewGroup
        val availableH = if (parent != null) {
            (parent.height - parent.paddingBottom - parent.paddingTop).coerceAtLeast(dp(300))
        } else {
            resources.displayMetrics.heightPixels
        }
        val maxCompactH = (availableH * 0.60f).toInt().coerceIn(dp(240), dp(400))

        val cardW = if (card.width > 0) card.width else (resources.displayMetrics.widthPixels - dp(OUTER_PADDING_HORIZONTAL_DP * 2))
        val childWidth = (cardW - card.paddingLeft - card.paddingRight).coerceAtLeast(dp(200))
        val childWidthSpec = View.MeasureSpec.makeMeasureSpec(childWidth, View.MeasureSpec.EXACTLY)

        var fixedViewsH = card.paddingTop + card.paddingBottom
        for (i in 0 until card.childCount) {
            val child = card.getChildAt(i)
            if (child === outputScrollView || child.visibility == View.GONE) continue
            val lp = child.layoutParams as? ViewGroup.MarginLayoutParams
            val topM = lp?.topMargin ?: 0
            val bottomM = lp?.bottomMargin ?: 0
            child.measure(childWidthSpec, View.MeasureSpec.makeMeasureSpec(availableH, View.MeasureSpec.AT_MOST))
            fixedViewsH += child.measuredHeight + topM + bottomM
        }

        val msgList = messagesContainer
        val msgListH = if (msgList != null) {
            msgList.measure(childWidthSpec, View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
            msgList.measuredHeight
        } else {
            dp(60)
        }

        val scrollMargins = (outputScrollView?.layoutParams as? ViewGroup.MarginLayoutParams)?.let {
            it.topMargin + it.bottomMargin
        } ?: dp(12)

        val naturalScrollH = msgListH + scrollMargins
        val maxScrollH = (maxCompactH - fixedViewsH).coerceAtLeast(dp(60))
        val finalScrollH = naturalScrollH.coerceAtMost(maxScrollH)

        return (fixedViewsH + finalScrollH).coerceIn(dp(180), maxCompactH)
    }

    private fun animateSheetHeight(view: View, fromH: Int, toH: Int, onEnd: (() -> Unit)? = null) {
        activeSheetAnimator?.cancel()
        val anim = android.animation.ValueAnimator.ofInt(fromH, toH).apply {
            duration = 180L
            interpolator = android.view.animation.DecelerateInterpolator()
            addUpdateListener { va ->
                view.layoutParams.height = va.animatedValue as Int
                view.requestLayout()
            }
            addListener(object : android.animation.AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: android.animation.Animator) {
                    activeSheetAnimator = null
                    onEnd?.invoke()
                }
                override fun onAnimationCancel(animation: android.animation.Animator) {
                    activeSheetAnimator = null
                }
            })
        }
        activeSheetAnimator = anim
        anim.start()
    }

    private fun openInFullApp() {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            action = Intent.ACTION_VIEW
            putExtra("from_assistant_overlay", true)
            putExtra("open_chat_unarchived", true)
            if (sessionMessages.isNotEmpty()) {
                val jsonArr = JSONArray()
                for (msg in sessionMessages) {
                    jsonArr.put(msg)
                }
                putExtra("open_chat_messages", jsonArr.toString())
            }
        }
        startActivity(launchIntent)
        dismissSheetAnimated()
    }

    private fun dismissSheetAnimated() {
        if (isDismissing) return
        isDismissing = true
        (sheetCardView ?: window?.decorView)?.performHapticFeedback(HapticFeedbackConstants.REJECT)
        val card = sheetCardView
        if (card != null) {
            card.animate()
                .translationY(card.height.toFloat().coerceAtLeast(dp(220).toFloat()))
                .alpha(0f)
                .setDuration(160)
                .withEndAction {
                    closeInteractiveSession()
                }
                .start()
        } else {
            closeInteractiveSession()
        }
    }

    private fun attachScreenContext(bitmap: Bitmap) {
        val existingScreenBmp = screenContextBitmap
        if (existingScreenBmp != null) {
            attachedBitmaps.remove(existingScreenBmp)
            screenContextBitmap = null
        }
        if (attachedBitmaps.size >= maxImagesAllowed) {
            (sheetCardView ?: window?.decorView)?.performHapticFeedback(HapticFeedbackConstants.REJECT)
            Toast.makeText(this, tr("max_images_reached"), Toast.LENGTH_SHORT).show()
            return
        }
        activeSessionBitmap = null
        screenContextBitmap = bitmap
        currentBitmap = bitmap
        attachedBitmaps.add(0, bitmap)
        renderAttachedImagesPreview()
    }

    private fun attachGalleryBitmap(bitmap: Bitmap) {
        if (attachedBitmaps.size >= maxImagesAllowed) {
            (sheetCardView ?: window?.decorView)?.performHapticFeedback(HapticFeedbackConstants.REJECT)
            Toast.makeText(this, tr("max_images_reached"), Toast.LENGTH_SHORT).show()
            return
        }
        activeSessionBitmap = null
        currentBitmap = bitmap
        attachedBitmaps.add(bitmap)
        renderAttachedImagesPreview()
    }

    private fun attachBitmapToPreview(
        bitmap: Bitmap,
        sourceLabel: String? = null,
        isScreenContext: Boolean = false
    ) {
        if (isScreenContext) {
            attachScreenContext(bitmap)
        } else {
            attachGalleryBitmap(bitmap)
        }
    }

    private fun renderAttachedImagesPreview() {
        val container = imagePreviewContainer ?: return
        val itemsRow = imagePreviewItemsRow ?: return

        itemsRow.removeAllViews()

        if (attachedBitmaps.isEmpty()) {
            container.visibility = View.GONE
            updateContextBadgeUI()
            return
        }

        container.visibility = View.VISIBLE

        for (bitmap in attachedBitmaps.toList()) {
            if (bitmap === screenContextBitmap) {
                // Screen context chip: [✦] Screen context added [✕]
                val chip = LinearLayout(this).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                    setPadding(dp(10), dp(6), dp(8), dp(6))
                    background = GradientDrawable().apply {
                        shape = GradientDrawable.RECTANGLE
                        cornerRadius = dp(14).toFloat()
                        setColor(palette.surfaceContainer)
                        setStroke(dp(1), palette.cardBorder)
                    }
                    layoutParams = LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT
                    ).apply {
                        rightMargin = dp(8)
                    }
                }

                val icon = ImageView(this).apply {
                    setImageDrawable(
                        M3VectorDrawable(
                            M3IconType.SPARKLE,
                            palette.accent,
                            dp(15)
                        )
                    )
                    layoutParams = LinearLayout.LayoutParams(dp(15), dp(15)).apply {
                        rightMargin = dp(6)
                    }
                }
                chip.addView(icon)

                val label = TextView(this).apply {
                    text = tr("screen_context_added")
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                    typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
                    setTextColor(palette.bodyText)
                    layoutParams = LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT
                    ).apply {
                        rightMargin = dp(8)
                    }
                }
                chip.addView(label)

                val removeBtn = ImageView(this).apply {
                    scaleType = ImageView.ScaleType.CENTER
                    contentDescription = tr("remove_image")
                    setImageDrawable(
                        M3VectorDrawable(
                            M3IconType.CLOSE,
                            palette.subtitle,
                            dp(10)
                        )
                    )
                    background = GradientDrawable().apply {
                        shape = GradientDrawable.OVAL
                        setColor(palette.chipBg)
                    }
                    layoutParams = LinearLayout.LayoutParams(dp(22), dp(22))
                    setOnClickListener {
                        it.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
                        attachedBitmaps.remove(bitmap)
                        if (currentBitmap === bitmap) {
                            currentBitmap = attachedBitmaps.firstOrNull()
                        }
                        if (attachedBitmaps.isEmpty()) {
                            activeSessionBitmap = null
                        }
                        screenContextBitmap = null
                        renderAttachedImagesPreview()
                    }
                }
                chip.addView(removeBtn)

                itemsRow.addView(chip)
            } else {
                // Gallery image item: FrameLayout with 40x40dp thumbnail + subtle close badge
                val frame = FrameLayout(this).apply {
                    layoutParams = LinearLayout.LayoutParams(dp(44), dp(44)).apply {
                        rightMargin = dp(8)
                    }
                }

                val thumb = ImageView(this).apply {
                    scaleType = ImageView.ScaleType.CENTER_CROP
                    clipToOutline = true
                    background = GradientDrawable().apply {
                        shape = GradientDrawable.RECTANGLE
                        cornerRadius = dp(10).toFloat()
                        setColor(palette.chipBg)
                    }
                    setImageBitmap(bitmap)
                    layoutParams = FrameLayout.LayoutParams(dp(40), dp(40)).apply {
                        gravity = Gravity.BOTTOM or Gravity.START
                    }
                }
                frame.addView(thumb)

                val removeBadge = ImageView(this).apply {
                    scaleType = ImageView.ScaleType.CENTER
                    contentDescription = tr("remove_image")
                    setImageDrawable(
                        M3VectorDrawable(
                            M3IconType.CLOSE,
                            palette.bodyText,
                            dp(9)
                        )
                    )
                    background = GradientDrawable().apply {
                        shape = GradientDrawable.OVAL
                        setColor(palette.surfaceContainer)
                        setStroke(dp(1), palette.cardBorder)
                    }
                    layoutParams = FrameLayout.LayoutParams(dp(18), dp(18)).apply {
                        gravity = Gravity.TOP or Gravity.END
                    }
                    setOnClickListener {
                        it.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
                        attachedBitmaps.remove(bitmap)
                        if (currentBitmap === bitmap) {
                            currentBitmap = attachedBitmaps.firstOrNull()
                        }
                        if (attachedBitmaps.isEmpty()) {
                            activeSessionBitmap = null
                        }
                        renderAttachedImagesPreview()
                    }
                }
                frame.addView(removeBadge)

                itemsRow.addView(frame)
            }
        }

        updateContextBadgeUI()
    }

    /**
     * Appends a right-aligned Material 3 user bubble to [messagesContainer] (no "You:" label).
     * If [images] / [image] are present, places rounded thumbnail previews directly inside the bubble!
     */
    private fun addUserMessageBubble(
        text: String,
        images: List<Bitmap> = emptyList(),
        image: Bitmap? = null
    ) {
        val container = messagesContainer ?: return
        emptyStateCard?.visibility = View.GONE

        val screenWidth = resources.displayMetrics.widthPixels
        val maxBubbleWidth = (screenWidth * 0.78f).toInt()

        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.END
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                topMargin = dp(8)
            }
        }

        val bubbleCol = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.START
            setPadding(dp(12), dp(8), dp(12), dp(8))
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                val r = dp(18).toFloat()
                val tail = dp(4).toFloat()
                cornerRadii = floatArrayOf(r, r, r, r, tail, tail, r, r)
                setColor(palette.userBubbleBg)
            }
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }

        val allImages = if (images.isNotEmpty()) images else listOfNotNull(image)
        if (allImages.isNotEmpty()) {
            if (allImages.size == 1) {
                val imgView = ImageView(this).apply {
                    scaleType = ImageView.ScaleType.CENTER_CROP
                    clipToOutline = true
                    background = GradientDrawable().apply {
                        shape = GradientDrawable.RECTANGLE
                        cornerRadius = dp(10).toFloat()
                    }
                    setImageBitmap(allImages.first())
                    layoutParams = LinearLayout.LayoutParams(
                        if (text.isNotBlank()) ViewGroup.LayoutParams.MATCH_PARENT else dp(180),
                        dp(130)
                    ).apply {
                        if (text.isNotBlank()) {
                            bottomMargin = dp(8)
                        }
                    }
                }
                bubbleCol.addView(imgView)
            } else {
                val imgRow = HorizontalScrollView(this).apply {
                    overScrollMode = View.OVER_SCROLL_NEVER
                    isHorizontalScrollBarEnabled = false
                    layoutParams = LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT
                    ).apply {
                        if (text.isNotBlank()) {
                            bottomMargin = dp(8)
                        }
                    }
                }
                val imgList = LinearLayout(this).apply {
                    orientation = LinearLayout.HORIZONTAL
                }
                for (bmp in allImages) {
                    val iv = ImageView(this).apply {
                        scaleType = ImageView.ScaleType.CENTER_CROP
                        clipToOutline = true
                        background = GradientDrawable().apply {
                            shape = GradientDrawable.RECTANGLE
                            cornerRadius = dp(8).toFloat()
                        }
                        setImageBitmap(bmp)
                        layoutParams = LinearLayout.LayoutParams(dp(72), dp(72)).apply {
                            rightMargin = dp(6)
                        }
                    }
                    imgList.addView(iv)
                }
                imgRow.addView(imgList)
                bubbleCol.addView(imgRow)
            }
        }

        if (text.isNotBlank()) {
            val bubbleText = TextView(this).apply {
                this.text = text
                maxWidth = maxBubbleWidth
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                setTextColor(palette.userBubbleText)
                setLineSpacing(0f, 1.2f)
                setTextIsSelectable(true)
            }
            bubbleCol.addView(bubbleText)
        }

        row.addView(bubbleCol)
        container.addView(row)
        outputScrollView?.post { outputScrollView?.fullScroll(View.FOCUS_DOWN) }
    }

    /**
     * Appends a left-aligned Material 3 AI response bubble to [messagesContainer] (no "PAIOS:" label)
     * and returns its [TextView] so streaming tokens can update it with live markdown spans.
     */
    private fun addAiMessageBubble(initialStatus: String): TextView {
        val container = messagesContainer ?: return TextView(this)
        emptyStateCard?.visibility = View.GONE

        val screenWidth = resources.displayMetrics.widthPixels
        val maxBubbleWidth = (screenWidth * 0.88f).toInt()

        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.START
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                topMargin = dp(8)
            }
        }

        val bubble = TextView(this).apply {
            text = formatMarkdownToSpannable(initialStatus)
            maxWidth = maxBubbleWidth
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            setTextColor(palette.bodyText)
            setLineSpacing(0f, 1.25f)
            setTextIsSelectable(true)
            setPadding(dp(14), dp(9), dp(14), dp(9))
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                val r = dp(18).toFloat()
                val tail = dp(4).toFloat()
                cornerRadii = floatArrayOf(r, r, r, r, r, r, tail, tail)
                setColor(palette.aiBubbleBg)
                setStroke(dp(1), palette.aiBubbleBorder)
            }
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }

        row.addView(bubble)
        container.addView(row)
        outputScrollView?.post { outputScrollView?.fullScroll(View.FOCUS_DOWN) }
        return bubble
    }

    /**
     * Converts Markdown (`**bold**`, `*italic*`, `` `code` ``, `# headings`, and `* ` / `- ` bullets)
     * into native Android [SpannableStringBuilder] styling with zero raw `**` asterisks.
     */
    private fun formatMarkdownToSpannable(raw: String): CharSequence {
        val trimmed = raw.trimEnd()
        if (trimmed.isEmpty()) return ""

        // 1. Normalize line-level bullets and headings
        val normalizedLines = trimmed.lines().map { line ->
            val trimmedStart = line.trimStart()
            when {
                trimmedStart.startsWith("### ") -> "**" + trimmedStart.removePrefix("### ").trim() + "**"
                trimmedStart.startsWith("## ") -> "**" + trimmedStart.removePrefix("## ").trim() + "**"
                trimmedStart.startsWith("# ") -> "**" + trimmedStart.removePrefix("# ").trim() + "**"
                trimmedStart.startsWith("* ") -> "  • " + trimmedStart.removePrefix("* ")
                trimmedStart.startsWith("- ") -> "  • " + trimmedStart.removePrefix("- ")
                else -> line
            }
        }.joinToString("\n")

        val builder = SpannableStringBuilder()
        var i = 0
        val n = normalizedLines.length

        while (i < n) {
            // Bold: **text**
            if (i + 1 < n && normalizedLines[i] == '*' && normalizedLines[i + 1] == '*') {
                val closeIdx = normalizedLines.indexOf("**", i + 2)
                if (closeIdx != -1) {
                    val content = normalizedLines.substring(i + 2, closeIdx)
                    val start = builder.length
                    builder.append(content)
                    builder.setSpan(
                        StyleSpan(Typeface.BOLD),
                        start,
                        builder.length,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                    )
                    builder.setSpan(
                        ForegroundColorSpan(Color.WHITE),
                        start,
                        builder.length,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                    )
                    i = closeIdx + 2
                    continue
                }
            }

            // Inline code: `code`
            if (normalizedLines[i] == '`') {
                val closeIdx = normalizedLines.indexOf('`', i + 1)
                if (closeIdx != -1 && closeIdx > i + 1) {
                    val content = normalizedLines.substring(i + 1, closeIdx)
                    val start = builder.length
                    builder.append("\u00A0$content\u00A0")
                    builder.setSpan(
                        TypefaceSpan("monospace"),
                        start,
                        builder.length,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                    )
                    builder.setSpan(
                        BackgroundColorSpan(palette.chipBg),
                        start,
                        builder.length,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                    )
                    builder.setSpan(
                        ForegroundColorSpan(palette.accent),
                        start,
                        builder.length,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                    )
                    builder.setSpan(
                        RelativeSizeSpan(0.92f),
                        start,
                        builder.length,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                    )
                    i = closeIdx + 1
                    continue
                }
            }

            // Italic: *text* (single asterisk not followed by space)
            if (normalizedLines[i] == '*' && i + 1 < n && normalizedLines[i + 1] != ' ' && normalizedLines[i + 1] != '*') {
                val closeIdx = normalizedLines.indexOf('*', i + 1)
                if (closeIdx != -1 && closeIdx > i + 1 && !normalizedLines.substring(i + 1, closeIdx).contains('\n')) {
                    val content = normalizedLines.substring(i + 1, closeIdx)
                    val start = builder.length
                    builder.append(content)
                    builder.setSpan(
                        StyleSpan(Typeface.ITALIC),
                        start,
                        builder.length,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                    )
                    i = closeIdx + 1
                    continue
                }
            }

            builder.append(normalizedLines[i])
            i++
        }

        return builder
    }

    private fun compositeBitmaps(bitmaps: List<Bitmap>): Bitmap {
        if (bitmaps.size == 1) return bitmaps[0]

        val targetWidth = bitmaps.maxOf { it.width }
        val totalHeight = bitmaps.sumOf { (it.height * (targetWidth.toFloat() / it.width)).toInt() }
        val composite = Bitmap.createBitmap(targetWidth, totalHeight.coerceAtLeast(1), Bitmap.Config.ARGB_8888)
        val canvas = Canvas(composite)
        var currentY = 0f

        for (bmp in bitmaps) {
            val scale = targetWidth.toFloat() / bmp.width
            val drawHeight = bmp.height * scale
            val destRect = RectF(0f, currentY, targetWidth.toFloat(), currentY + drawHeight)
            canvas.drawBitmap(bmp, null, destRect, null)
            currentY += drawHeight
        }

        if (downsampleSetting && (composite.width > MAX_DOWNSAMPLE_DIMENSION || composite.height > MAX_DOWNSAMPLE_DIMENSION)) {
            val scale = MAX_DOWNSAMPLE_DIMENSION.toFloat() / maxOf(composite.width, composite.height).toFloat()
            return Bitmap.createScaledBitmap(
                composite,
                (composite.width * scale).toInt().coerceAtLeast(1),
                (composite.height * scale).toInt().coerceAtLeast(1),
                true
            )
        }
        return composite
    }

    private fun startInteractiveStreaming(userPrompt: String) {
        activeStreamJob?.cancel()

        val bitmapsSnapshot = attachedBitmaps.toList()
        addUserMessageBubble(userPrompt, images = bitmapsSnapshot)
        currentBitmap = null
        attachedBitmaps.clear()
        screenContextBitmap = null
        renderAttachedImagesPreview()

        // Record user message in session message list
        val userMsg = JSONObject().apply {
            put("user", "User")
            put("message", userPrompt)
            put("time", System.currentTimeMillis().toString())
        }
        sessionMessages.add(userMsg)

        val aiBubbleView = addAiMessageBubble(tr("assistant_thinking"))
        sheetProgressBar?.visibility = View.VISIBLE

        val contextDataSnapshot = contextData
        val callerNameSnapshot = callerName
        val visualMemorySnapshot = visualContextMemory
        val historySnapshot = conversationHistoryPrompt

        activeStreamJob = activityScope.launch(Dispatchers.IO) {
            val personaSystemPrompt = resolveActivePersonaContent()
            val meshToolsPrompt = getMeshToolSchemaPrompt()

            val fullPrompt = buildString {
                if (personaSystemPrompt.isNotBlank()) {
                    append("System Instruction / Persona:\n")
                    append(personaSystemPrompt)
                    append("\n\n")
                }
                append(meshToolsPrompt)
                append("\n\n")

                if (contextDataSnapshot.isNotBlank()) {
                    append("Application & Screen Context ($callerNameSnapshot):\n")
                    append(contextDataSnapshot)
                    append("\n\n")
                }
                if (visualMemorySnapshot.isNotBlank()) {
                    append("Visual Context Memory (from previously analyzed image / screen):\n")
                    append(visualMemorySnapshot)
                    append("\n\n")
                }
                if (historySnapshot.isNotBlank()) {
                    append("Recent Conversation:\n")
                    append(historySnapshot.takeLast(1600))
                    append("\n\n")
                }
                append("User Request: ")
                append(userPrompt)
            }

            var streamedText = ""
            var handledToolCall = false
            var streamFailed = false
            try {
                val generativeModel = Generation.getClient()
                val request = if (bitmapsSnapshot.isNotEmpty()) {
                    val combinedBmp = compositeBitmaps(bitmapsSnapshot)
                    activeSessionBitmap = combinedBmp
                    generateContentRequest(ImagePart(combinedBmp), TextPart(fullPrompt)) {}
                } else if (activeSessionBitmap != null) {
                    generateContentRequest(ImagePart(activeSessionBitmap!!), TextPart(fullPrompt)) {}
                } else {
                    generateContentRequest(TextPart(fullPrompt)) {}
                }

                generativeModel.generateContentStream(request)
                    .onEach { chunk ->
                        val piece = chunk.candidates.firstOrNull()?.text ?: ""
                        streamedText += piece
                        val toolCall = extractToolCallJson(streamedText)
                        val isToolCallPending = looksLikeIncompleteToolCall(streamedText)
                        if (toolCall != null || isToolCallPending) {
                            handledToolCall = true
                        }
                        withContext(Dispatchers.Main) {
                            if (handledToolCall) {
                                val desc = formatToolChipLabel(toolCall, streamedText)
                                applyToolChipStyle(aiBubbleView, desc)
                            } else {
                                val formatted = formatMarkdownToSpannable(streamedText)
                                aiBubbleView.text = formatted
                            }
                            outputScrollView?.post { outputScrollView?.fullScroll(View.FOCUS_DOWN) }
                        }
                    }
                    .catch { e ->
                        if (e is kotlinx.coroutines.CancellationException) throw e
                        streamFailed = true
                        Log.e(TAG, "[STREAM ERROR] ${e.message}", e)
                        withContext(Dispatchers.Main) {
                            sheetProgressBar?.visibility = View.GONE
                            val errText = if (streamedText.isEmpty()) {
                                "${e.message}"
                            } else {
                                "$streamedText\n\n*${e.message}*"
                            }
                            aiBubbleView.text = formatMarkdownToSpannable(errText)
                        }
                    }
                    .onCompletion { cause ->
                        if (cause != null || streamFailed) {
                            withContext(Dispatchers.Main) {
                                sheetProgressBar?.visibility = View.GONE
                            }
                            return@onCompletion
                        }

                        val finalToolCall = extractToolCallJson(streamedText)
                        if (finalToolCall != null) {
                            val tool = finalToolCall.optString("tool", "")
                            val app = finalToolCall.optString("app", "paios")
                            val args = finalToolCall.optJSONObject("arguments") ?: JSONObject()
                            val desc = formatToolChipLabel(finalToolCall, streamedText)

                            val toolCallMsg = JSONObject().apply {
                                put("user", "Gemini")
                                put("message", streamedText)
                                put("time", System.currentTimeMillis().toString())
                            }
                            sessionMessages.add(toolCallMsg)

                            launchToolSynthesis(
                                userPrompt = userPrompt,
                                toolBubble = aiBubbleView,
                                toolName = tool,
                                appName = app,
                                description = desc,
                                arguments = args,
                                personaSystemPrompt = personaSystemPrompt
                            )
                            return@onCompletion
                        }

                        if (handledToolCall || looksLikeIncompleteToolCall(streamedText)) {
                            Log.w(TAG, "[STREAM INCOMPLETE TOOL] Discarding unparseable tool call draft")
                            withContext(Dispatchers.Main) {
                                sheetProgressBar?.visibility = View.GONE
                                aiBubbleView.text = formatMarkdownToSpannable("Unable to parse completed tool request. Please try again.")
                            }
                            return@onCompletion
                        }

                        withContext(Dispatchers.Main) {
                            sheetProgressBar?.visibility = View.GONE
                            if (streamedText.isNotEmpty()) {
                                conversationHistoryPrompt += "\nUser: $userPrompt\nPAIOS: $streamedText\n"
                                lastResponseText = streamedText
                                if (bitmapsSnapshot.isNotEmpty() || activeSessionBitmap != null) {
                                    visualContextMemory = streamedText.take(1200)
                                }
                                val aiMsg = JSONObject().apply {
                                    put("user", "Gemini")
                                    put("message", streamedText)
                                    put("time", System.currentTimeMillis().toString())
                                }
                                sessionMessages.add(aiMsg)
                            }
                        }
                    }
                    .collect {}
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.e(TAG, "[STREAM INIT ERROR] ${e.message}", e)
                withContext(Dispatchers.Main) {
                    sheetProgressBar?.visibility = View.GONE
                    aiBubbleView.text = formatMarkdownToSpannable("${e.message}")
                }
            }
        }
    }

    private fun applyToolChipStyle(view: TextView, description: String) {
        view.text = formatMarkdownToSpannable("🔧  *$description*")
        view.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
        view.setTextColor(palette.subtitle)
        view.background = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(12).toFloat()
            setColor(palette.chipBg)
            setStroke(dp(1), palette.cardBorder)
        }
        view.setPadding(dp(12), dp(6), dp(12), dp(6))
    }

    private fun launchToolSynthesis(
        userPrompt: String,
        toolBubble: TextView,
        toolName: String,
        appName: String,
        description: String,
        arguments: JSONObject,
        personaSystemPrompt: String
    ) {
        activityScope.launch(Dispatchers.IO) {
            withContext(Dispatchers.Main) {
                applyToolChipStyle(toolBubble, description)
                sheetProgressBar?.visibility = View.VISIBLE
            }

            // 1. Execute tool call via ContentProvider or local handler
            val resultPayload = executeMeshToolCall(toolName, appName, arguments)
            val isToolError = try {
                val parsed = JSONObject(resultPayload)
                parsed.has("error") && !parsed.has("statuspage") && !parsed.has("incidents") && !parsed.has("statuspages")
            } catch (_: Exception) {
                false
            }

            val toolResultBanner = if (isToolError) {
                "[TOOL ERROR — DATA UNAVAILABLE] Calling '$toolName' on '$appName' FAILED: $resultPayload. Inform the user of this failure and NEVER invent data or claim everything is normal."
            } else {
                "[TOOL RESULT: $resultPayload]"
            }

            val sysMsg = JSONObject().apply {
                put("user", "System")
                put("message", toolResultBanner)
                put("time", System.currentTimeMillis().toString())
            }
            sessionMessages.add(sysMsg)

            // 2. Add synthesis AI bubble below tool chip
            val synthesisBubble = withContext(Dispatchers.Main) {
                addAiMessageBubble(tr("assistant_thinking"))
            }

            // 3. Build natural language synthesis prompt
            val isShareLocale = isShareLocaleEnabled()
            val synthesisPrompt = buildString {
                if (personaSystemPrompt.isNotBlank()) {
                    append("System Instruction / Persona:\n$personaSystemPrompt\n\n")
                }
                append("The tool '$toolName' from application '$appName' was executed and returned:\n")
                append("$toolResultBanner\n\n")

                if (isShareLocale) {
                    val appLang = activeDict.optString("current_language", "en")
                    append("CRITICAL LANGUAGE INSTRUCTION: You MUST respond in the current app language ($appLang). Do not switch to English.\n\n")
                } else {
                    append("CRITICAL LANGUAGE INSTRUCTION: You MUST respond in the EXACT SAME LANGUAGE as the user's request: \"$userPrompt\" (e.g. if the user asked in Ukrainian, you MUST answer in Ukrainian; do not switch to English).\n\n")
                }

                if (isToolError) {
                    append("The tool failed. Explain clearly that live data could not be retrieved due to this error. NEVER claim there are no incidents or invent data.")
                } else {
                    append("Please provide a clear, helpful, and natural language answer to the user's request: \"$userPrompt\" using the tool result above.")
                }
            }

            var synthText = ""
            var synthFailed = false
            try {
                val generativeModel = Generation.getClient()
                val request = generateContentRequest(TextPart(synthesisPrompt)) {}
                generativeModel.generateContentStream(request)
                    .onEach { chunk ->
                        val piece = chunk.candidates.firstOrNull()?.text ?: ""
                        synthText += piece
                        val formatted = formatMarkdownToSpannable(synthText)
                        withContext(Dispatchers.Main) {
                            synthesisBubble.text = formatted
                            outputScrollView?.post { outputScrollView?.fullScroll(View.FOCUS_DOWN) }
                        }
                    }
                    .catch { e ->
                        if (e is kotlinx.coroutines.CancellationException) throw e
                        synthFailed = true
                        Log.e(TAG, "[SYNTHESIS STREAM ERROR] ${e.message}", e)
                        withContext(Dispatchers.Main) {
                            sheetProgressBar?.visibility = View.GONE
                            val errText = if (synthText.isEmpty()) "${e.message}" else "$synthText\n\n*${e.message}*"
                            synthesisBubble.text = formatMarkdownToSpannable(errText)
                        }
                    }
                    .onCompletion { cause ->
                        withContext(Dispatchers.Main) {
                            sheetProgressBar?.visibility = View.GONE
                            if (cause == null && !synthFailed && synthText.isNotEmpty()) {
                                conversationHistoryPrompt += "\nUser: $userPrompt\nPAIOS: $synthText\n"
                                lastResponseText = synthText
                                val aiMsg = JSONObject().apply {
                                    put("user", "Gemini")
                                    put("message", synthText)
                                    put("time", System.currentTimeMillis().toString())
                                }
                                sessionMessages.add(aiMsg)
                            }
                        }
                    }
                    .collect {}
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.e(TAG, "[SYNTHESIS INIT ERROR] ${e.message}", e)
                withContext(Dispatchers.Main) {
                    sheetProgressBar?.visibility = View.GONE
                    synthesisBubble.text = formatMarkdownToSpannable("${e.message}")
                }
            }
        }
    }

    private fun formatToolChipLabel(toolCall: JSONObject?, streamedText: String): String {
        val explicitDesc = toolCall?.optString("description")?.trim().orEmpty()
        if (explicitDesc.isNotEmpty()) return explicitDesc

        val toolName = toolCall?.optString("tool")?.trim().orEmpty()
        return when {
            toolName.contains("doc") || (toolName.isEmpty() && streamedText.contains("doc")) -> {
                val query = toolCall?.optJSONObject("arguments")?.optString("query")?.trim().orEmpty()
                when {
                    query.isNotEmpty() -> tr("tool_reading_docs").replace("%s", query)
                    toolName.isNotEmpty() -> tr("tool_using").replace("%s", toolName)
                    else -> tr("tool_reading_docs").replace(" '%s'", "").replace("'%s'", "").replace("%s", "").trim()
                }
            }
            toolName.contains("battery") || (toolName.isEmpty() && streamedText.contains("battery")) -> {
                tr("tool_checking_battery")
            }
            toolName.isNotEmpty() -> {
                tr("tool_using").replace("%s", toolName)
            }
            else -> tr("assistant_status_processing")
        }
    }

    private fun discoverMeshProviders(): LinkedHashMap<String, String> {
        val providers = LinkedHashMap<String, String>()
        val pm = packageManager

        try {
            val meshIntent = Intent("com.puzzak.m3x.mesh.ACTION_MESH_NODE")
            val resolveInfos = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.queryIntentContentProviders(
                    meshIntent,
                    PackageManager.ResolveInfoFlags.of(0)
                )
            } else {
                @Suppress("DEPRECATION")
                pm.queryIntentContentProviders(meshIntent, 0)
            }
            for (info in resolveInfos) {
                val providerInfo = info.providerInfo ?: continue
                val pkg = providerInfo.packageName ?: continue
                val auth = providerInfo.authority?.takeIf { it.isNotBlank() } ?: "$pkg.mesh"
                providers.putIfAbsent(pkg, auth)
            }
        } catch (e: Exception) {
            Log.w(TAG, "queryIntentContentProviders failed: ${e.message}")
        }

        try {
            val installedProviders = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.queryContentProviders(
                    null,
                    0,
                    PackageManager.ComponentInfoFlags.of(PackageManager.GET_META_DATA.toLong())
                )
            } else {
                @Suppress("DEPRECATION")
                pm.queryContentProviders(null, 0, PackageManager.GET_META_DATA)
            }
            for (p in installedProviders) {
                val auth = p.authority ?: continue
                val pkg = p.packageName ?: continue
                if (auth.endsWith(".mesh")) {
                    providers.putIfAbsent(pkg, auth)
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "queryContentProviders failed: ${e.message}")
        }

        return providers
    }

    private suspend fun fetchExternalMeshToolEntries(): List<String> = withContext(Dispatchers.IO) {
        val providers = discoverMeshProviders()
        val aliasMap = HashMap<String, String>()
        val authorityMap = HashMap<String, String>()
        val selfLower = packageName.lowercase(Locale.ROOT)

        val candidates = providers.entries.filter { (pkg, _) ->
            val pkgLower = pkg.lowercase(Locale.ROOT)
            val isSelf = pkgLower == selfLower ||
                pkgLower == "page.puzzak.paios" ||
                pkgLower == "com.puzzak.geminilocal"
            !isSelf && isExtensionEnabledInPrefs(pkg)
        }

        val perAppResults = coroutineScope {
            candidates.map { (pkg, authority) ->
                async(Dispatchers.IO) {
                    withTimeoutOrNull(MESH_TOOL_QUERY_TIMEOUT_MS) {
                        val entries = mutableListOf<String>()
                        val localAliases = HashMap<String, String>()
                        try {
                            val uri = Uri.parse("content://$authority")
                            val toolsBundle = contentResolver.call(uri, "query_tools", null, null)
                            val toolsJsonStr = toolsBundle?.getString("response")
                            if (!toolsJsonStr.isNullOrBlank()) {
                                val arr = JSONArray(toolsJsonStr)
                                val shortPkg = pkg.substringAfterLast('.').lowercase(Locale.ROOT)
                                if (shortPkg.isNotEmpty()) {
                                    localAliases[shortPkg] = pkg
                                }
                                for (i in 0 until arr.length()) {
                                    val toolObj = arr.optJSONObject(i) ?: continue
                                    val name = toolObj.optString("name", "").trim()
                                    if (name.isEmpty() ||
                                        name == "query_aicore_documentation" ||
                                        name == "get_battery_status" ||
                                        name == "query_local_ai" ||
                                        name == "get_ai_status"
                                    ) {
                                        continue
                                    }
                                    val declaredApp = toolObj.optString("app", "").trim()
                                    if (declaredApp.isNotEmpty() && !declaredApp.contains('.')) {
                                        localAliases[declaredApp.lowercase(Locale.ROOT)] = pkg
                                    }
                                    val rawDesc = toolObj.optString("description", "")
                                        .trim()
                                        .replace(Regex("\\s+"), " ")
                                    val desc = if (rawDesc.length > 220) {
                                        rawDesc.take(217) + "..."
                                    } else {
                                        rawDesc
                                    }
                                    val paramsObj = toolObj.optJSONObject("parameters")
                                        ?: JSONObject().apply {
                                            put("type", "object")
                                            put("properties", JSONObject())
                                        }
                                    entries.add(
                                        "\n - $name (app: \"$pkg\"): $desc\n   arguments schema: $paramsObj"
                                    )
                                }
                            }
                        } catch (e: Exception) {
                            Log.d(TAG, "query_tools skipped for $pkg ($authority): ${e.message}")
                        }
                        Triple(pkg, authority, Pair(localAliases, entries))
                    }
                }
            }.awaitAll()
        }

        val collected = mutableListOf<String>()
        var charBudgetUsed = 0
        for (res in perAppResults) {
            if (res == null) continue
            val (pkg, authority, payload) = res
            authorityMap[pkg] = authority
            aliasMap.putAll(payload.first)
            for (entry in payload.second) {
                if (charBudgetUsed + entry.length > MAX_EXTERNAL_TOOL_SCHEMA_CHARS) {
                    Log.w(TAG, "External mesh tool schema budget ($MAX_EXTERNAL_TOOL_SCHEMA_CHARS chars) reached; truncating remaining schemas.")
                    break
                }
                collected.add(entry)
                charBudgetUsed += entry.length
            }
        }

        discoveredAppAliases = aliasMap
        discoveredAuthorities = authorityMap
        collected
    }

    private suspend fun getMeshToolSchemaPrompt(): String {
        val externalEntries = try {
            fetchExternalMeshToolEntries()
        } catch (e: Exception) {
            Log.w(TAG, "Failed to discover external mesh tools: ${e.message}")
            emptyList()
        }

        return buildString {
            append(
                """
### [AVAILABLE TOOLS]
You have access to external agentic tools provided by connected applications in the M3x mesh.

CRITICAL TOOL INVOCATION RULES:
1. ONLY invoke a tool when the user's latest message explicitly asks for information, status, or an action that REQUIRES that specific tool.
2. NEVER invoke a tool for general greetings (e.g. "hi", "hello", "how are you"), pleasantries, casual conversation, self-descriptions, or questions that do not require external live data. For these, respond naturally in conversation without calling any tool.
3. NEVER guess or invoke a tool speculatively. If unsure, respond conversationally.
4. NEVER invoke a tool when the user is asking about visual contents, images, photos, UI widgets, screenshots, or apps visible on the screen, or when no tool exists for the requested data. There is NO tool for reading screen apps or images; inspect the attached image directly or answer honestly that no such tool exists.

When a tool is genuinely required by the user's explicit request, respond ONLY with a valid JSON tool call block using double quotes:
```json
{"action": "tool_call", "app": "<app>", "tool": "<tool>", "description": "Checking live data", "arguments": {}}
```
Do not add any text before or after the JSON block.

Available tool schemas:
 - query_aicore_documentation (app: "paios"): Searches official Google ML Kit GenAI and AICore documentation for supported devices, token limits, system prompt guidelines, error codes (-101, -100, BUSY, BACKGROUND_USE_BLOCKED), and multimodal vision specs.
   arguments schema: {"type":"object","properties":{"query":{"type":"string","description":"Search topic, device model, or error code (e.g. \"token limits\", \"-101\", \"Pixel 9\", \"system prompt\", \"vision downsample\")"}},"required":["query"]}
 - get_battery_status (app: "paios"): Checks device battery level, charging state, and power status. NEVER invoke this tool for questions about images, photos, screen icons, UI widgets, or visible apps.
   arguments schema: {"type":"object","properties":{}}
""".trimIndent()
            )
            for (entry in externalEntries) {
                append(entry)
            }
        }
    }

    private fun looksLikeIncompleteToolCall(text: String): Boolean {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return false
        if (extractToolCallJson(trimmed) != null) return false
        val stripped = trimmed.replace(Regex("""^```(?:json)?\s*""", RegexOption.IGNORE_CASE), "")
        if (!stripped.startsWith("{")) return false
        return stripped.contains("\"action\"") ||
            stripped.contains("\"tool_call\"") ||
            stripped.contains("\"tool\"") ||
            stripped.contains("'action'") ||
            stripped.contains("'tool'")
    }

    private fun extractToolCallJson(text: String): JSONObject? {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return null

        val mdRegex = Regex("""```(?:json)?\s*([\s\S]*?)\s*(?:```|$)""", RegexOption.IGNORE_CASE)
        for (match in mdRegex.findAll(trimmed)) {
            val block = match.groupValues[1].trim()
            val parsed = scanBalancedToolObjects(block)
            if (parsed != null) return parsed
        }
        return scanBalancedToolObjects(trimmed)
    }

    private fun scanBalancedToolObjects(source: String): JSONObject? {
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
            val obj = tryParseToolObject(candidate)
            if (obj != null) return obj
            i = end + 1
        }
        return null
    }

    private fun findMatchingBrace(source: String, start: Int): Int {
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

    private fun tryParseToolObject(candidate: String): JSONObject? {
        val attempts = listOf(
            candidate,
            sanitizeJsonLikeString(candidate, convertSingleQuotes = false),
            sanitizeJsonLikeString(candidate, convertSingleQuotes = true)
        )
        for (attempt in attempts) {
            try {
                val obj = JSONObject(attempt)
                if (isToolCallObject(obj)) return obj
            } catch (_: Exception) {}
        }
        return null
    }

    private fun isToolCallObject(obj: JSONObject): Boolean {
        if (obj.optString("action") == "tool_call") return true
        val tool = obj.opt("tool")?.toString()?.trim()
        if (tool.isNullOrEmpty()) return false
        return obj.has("arguments") || obj.has("params") || obj.has("app") || obj.has("description")
    }

    private fun sanitizeJsonLikeString(raw: String, convertSingleQuotes: Boolean): String {
        val out = StringBuilder(raw.length)
        var quote: Char? = null
        var i = 0
        while (i < raw.length) {
            val ch = raw[i]
            if (quote != null) {
                if (ch == '\\' && i + 1 < raw.length) {
                    val next = raw[i + 1]
                    if (next == '_') {
                        out.append('_')
                        i += 2
                        continue
                    }
                    out.append(ch).append(next)
                    i += 2
                    continue
                }
                if (ch == '\n' || ch == '\r') {
                    out.append("\\n")
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
        // Strip trailing commas before } or ]
        return out.toString().replace(Regex(""",(\s*[}\]])"""), "$1")
    }

    private fun isShareLocaleEnabled(): Boolean {
        return try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            if (prefs.contains("flutter.shareLocale")) {
                prefs.getBoolean("flutter.shareLocale", false)
            } else if (prefs.contains("shareLocale")) {
                prefs.getBoolean("shareLocale", false)
            } else {
                false
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun canonicalAppId(app: String): String {
        val trimmed = app.trim()
        val lower = trimmed.lowercase(Locale.ROOT)
        val selfPkg = packageName
        if (lower == "paios" ||
            lower == "geminilocal" ||
            lower == selfPkg.lowercase(Locale.ROOT) ||
            lower == "page.puzzak.paios" ||
            lower == "com.puzzak.geminilocal" ||
            lower == "com.puzzak.paios"
        ) {
            return selfPkg
        }
        if (trimmed.contains('.')) {
            return trimmed
        }
        discoveredAppAliases[lower]?.let { return it }

        try {
            val providers = discoverMeshProviders()
            for (pkg in providers.keys) {
                if (pkg.equals(trimmed, ignoreCase = true) ||
                    pkg.substringAfterLast('.').equals(trimmed, ignoreCase = true)
                ) {
                    return pkg
                }
            }
            if (android.os.Looper.myLooper() != android.os.Looper.getMainLooper()) {
                for ((pkg, authority) in providers) {
                    if (pkg == selfPkg) continue
                    try {
                        val toolsBundle = contentResolver.call(Uri.parse("content://$authority"), "query_tools", null, null)
                        val toolsJson = toolsBundle?.getString("response") ?: continue
                        val arr = JSONArray(toolsJson)
                        for (i in 0 until arr.length()) {
                            val toolObj = arr.optJSONObject(i) ?: continue
                            val declaredApp = toolObj.optString("app", "").trim()
                            if (declaredApp.equals(trimmed, ignoreCase = true)) {
                                return pkg
                            }
                        }
                    } catch (_: Exception) {}
                }
            }
        } catch (_: Exception) {}
        return trimmed
    }

    private fun isExtensionEnabledInPrefs(appPackage: String): Boolean {
        val canon = canonicalAppId(appPackage)
        if (canon == packageName || canon == "page.puzzak.paios") return true
        return try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val specificKeyFlutter = "flutter.mesh_extension_${canon}_enabled"
            val specificKeyDirect = "mesh_extension_${canon}_enabled"
            val rawKeyFlutter = "flutter.mesh_extension_${appPackage}_enabled"
            if (prefs.contains(specificKeyFlutter)) {
                prefs.getBoolean(specificKeyFlutter, true)
            } else if (prefs.contains(specificKeyDirect)) {
                prefs.getBoolean(specificKeyDirect, true)
            } else if (prefs.contains(rawKeyFlutter)) {
                prefs.getBoolean(rawKeyFlutter, true)
            } else {
                val allowAllKeyFlutter = "flutter.mesh_allow_all_new"
                val allowAllKeyDirect = "mesh_allow_all_new"
                val allowAllNew = if (prefs.contains(allowAllKeyFlutter)) {
                    prefs.getBoolean(allowAllKeyFlutter, false)
                } else if (prefs.contains(allowAllKeyDirect)) {
                    prefs.getBoolean(allowAllKeyDirect, false)
                } else {
                    false
                }
                if (canon.startsWith("page.puzzak.") || canon.startsWith("com.puzzak.")) {
                    true
                } else {
                    allowAllNew
                }
            }
        } catch (_: Exception) {
            true
        }
    }

    private suspend fun executeMeshToolCall(tool: String, app: String, arguments: JSONObject): String {
        val rawApp = if (app.isNotBlank()) app else "paios"
        val canonApp = canonicalAppId(rawApp)
        if (canonApp != packageName && canonApp != "page.puzzak.paios") {
            if (!isExtensionEnabledInPrefs(canonApp)) {
                Log.w(TAG, "Extension '$canonApp' is disabled in PAIOS settings.")
                return JSONObject().apply {
                    put("status", "error")
                    put("message", "Extension '$canonApp' is disabled in PAIOS settings.")
                }.toString()
            }
        }
        val authority = discoveredAuthorities[canonApp] ?: "$canonApp.mesh"

        try {
            val uri = Uri.parse("content://$authority")
            val callPayload = JSONObject().apply {
                put("jsonrpc", "2.0")
                put("id", "call-${System.currentTimeMillis()}")
                put("method", tool)
                put("params", arguments)
            }.toString()
            val extras = Bundle().apply {
                putString("payload", callPayload)
                putString("call", callPayload)
            }
            val resBundle = contentResolver.call(uri, "call_tool", callPayload, extras)
            val resStr = resBundle?.getString("response")
            if (!resStr.isNullOrBlank() && !resStr.contains("HEADLESS_OVERLAY_REQUIRED")) {
                val parsed = JSONObject(resStr)
                val resultNode = parsed.opt("result")
                if (resultNode != null) {
                    return resultNode.toString()
                }
                val errorNode = parsed.optJSONObject("error")
                if (errorNode != null) {
                    return JSONObject().apply {
                        put("error", errorNode.optString("message", errorNode.toString()))
                    }.toString()
                }
            }
        } catch (e: Exception) {
            Log.d(TAG, "ContentProvider call_tool failed for $authority: ${e.message}")
        }

        return executeBuiltInTool(tool, arguments)
    }

    private fun executeBuiltInTool(tool: String, arguments: JSONObject): String {
        return when (tool) {
            "query_aicore_documentation" -> {
                val query = arguments.optString("query", "").trim()
                queryDocumentation(query)
            }
            "get_battery_status" -> {
                getBatteryStatusJson()
            }
            else -> {
                JSONObject().apply {
                    put("status", "error")
                    put("message", "Tool '$tool' not supported in offline fallback")
                }.toString()
            }
        }
    }

    private fun queryDocumentation(query: String): String {
        return try {
            val docText = assets.open("docs/genai.md.txt").bufferedReader().use { it.readText() }
            val qTerms = query.lowercase(Locale.ROOT).split(Regex("\\s+")).filter { it.length > 2 }

            val sections = docText.split(Regex("(?=## )"))
            var bestSection = ""
            var bestScore = 0

            for (sec in sections) {
                val secLower = sec.lowercase(Locale.ROOT)
                val lines = sec.lines()
                val title = lines.firstOrNull { it.startsWith("##") } ?: ""
                val titleLower = title.lowercase(Locale.ROOT)

                var score = 0
                for (term in qTerms) {
                    if (titleLower.contains(term)) score += 10
                    if (secLower.contains(term)) score += 2
                }
                if (score > bestScore) {
                    bestScore = score
                    bestSection = sec
                }
            }

            val content = if (bestScore > 0 && bestSection.isNotBlank()) {
                bestSection.trim().take(1800)
            } else {
                docText.take(1500)
            }

            JSONObject().apply {
                put("found", true)
                put("query", query)
                put("content", content)
            }.toString()
        } catch (e: Exception) {
            Log.e(TAG, "queryDocumentation error: ${e.message}", e)
            JSONObject().apply {
                put("found", false)
                put("error", e.message)
            }.toString()
        }
    }

    private fun getBatteryStatusJson(): String {
        return try {
            val bm = getSystemService(Context.BATTERY_SERVICE) as? android.os.BatteryManager
            val level = bm?.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1
            val isCharging = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val status = bm?.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_STATUS) ?: -1
                status == android.os.BatteryManager.BATTERY_STATUS_CHARGING ||
                    status == android.os.BatteryManager.BATTERY_STATUS_FULL
            } else false
            JSONObject().apply {
                put("battery_level", "$level%")
                put("is_charging", isCharging)
                put("status", if (isCharging) "Charging" else "Discharging")
            }.toString()
        } catch (e: Exception) {
            JSONObject().apply {
                put("error", e.message)
            }.toString()
        }
    }

    private fun closeInteractiveSession() {
        PaiosVoiceInteractionSession.dismissActiveSession()

        // Auto-archive assistant session to SharedPreferences if messages were exchanged
        if (sessionMessages.isNotEmpty()) {
            try {
                val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val autoArchive = prefs.getBoolean("flutter.autoArchiveAssistantChats", true)
                val existingPendingStr = prefs.getString("flutter.pending_assistant_chats", null)
                val pendingArr = if (!existingPendingStr.isNullOrBlank()) {
                    JSONArray(existingPendingStr)
                } else {
                    JSONArray()
                }
                val sessionItem = JSONObject().apply {
                    put("messages", JSONArray(sessionMessages))
                    put("unarchived", !autoArchive)
                    put("timestamp", System.currentTimeMillis())
                }
                pendingArr.put(sessionItem)
                prefs.edit().putString("flutter.pending_assistant_chats", pendingArr.toString()).apply()
            } catch (e: Exception) {
                Log.w(TAG, "Error saving pending assistant session: ${e.message}")
            }
        }

        // Explicitly clear all assist state on session close
        latestAssistBitmap = null
        latestAssistScreenText = null
        latestAssistCallerPkg = null
        currentBitmap = null
        attachedBitmaps.clear()
        activeSessionBitmap = null
        screenContextBitmap = null
        conversationHistoryPrompt = ""
        visualContextMemory = ""
        contextData = ""
        sessionMessages.clear()

        val resultObj = JSONObject().apply {
            put("status", "success")
            put("interactive", true)
            put("response", lastResponseText)
            put("engine", "Gemini Nano (PAIOS Assistant Bubble)")
        }
        val responseJson = JSONObject().apply {
            put("jsonrpc", "2.0")
            put("id", callId)
            put("result", resultObj)
        }.toString()
        sendResult(responseJson)
        finishAndRemoveTask()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        isLaunchingImagePicker = false
        if (requestCode == REQUEST_CODE_BUBBLE_IMAGE && resultCode == RESULT_OK) {
            val clipData = data?.clipData
            val singleUri = data?.data
            val urisToProcess = mutableListOf<Uri>()
            if (clipData != null) {
                for (i in 0 until clipData.itemCount) {
                    urisToProcess.add(clipData.getItemAt(i).uri)
                }
            } else if (singleUri != null) {
                urisToProcess.add(singleUri)
            }

            if (urisToProcess.isNotEmpty()) {
                activityScope.launch {
                    for (uri in urisToProcess) {
                        if (attachedBitmaps.size >= maxImagesAllowed) {
                            withContext(Dispatchers.Main) {
                                (sheetCardView ?: window?.decorView)?.performHapticFeedback(HapticFeedbackConstants.REJECT)
                                Toast.makeText(this@MeshOverlayActivity, tr("max_images_reached"), Toast.LENGTH_SHORT).show()
                            }
                            break
                        }
                        val bmp = withContext(Dispatchers.IO) {
                            decodeVisualBitmap(null, uri.toString(), downsampleSetting)
                        }
                        if (bmp != null) {
                            withContext(Dispatchers.Main) {
                                attachGalleryBitmap(bmp)
                            }
                        }
                    }
                }
            }
        }
    }

    private fun sendResult(json: String) {
        synchronized(this) {
            if (!callbackFired) {
                callbackFired = true
                try {
                    val resultIntent = Intent().apply {
                        putExtra("response", json)
                    }
                    setResult(RESULT_OK, resultIntent)
                    Log.d(TAG, "[ACTIVITY RESULT SET] response length: ${json.length}")
                } catch (e: Exception) {
                    Log.e(TAG, "Error setting activity result: ${e.message}", e)
                }
                val cb = pendingCallback
                pendingCallback = null
                cb?.invoke(json)
            }
        }
    }

    override fun finish() {
        if (!callbackFired && isInteractiveMode) {
            val resultObj = JSONObject().apply {
                put("status", "closed")
                put("interactive", true)
                put("response", lastResponseText)
            }
            val responseJson = JSONObject().apply {
                put("jsonrpc", "2.0")
                put("id", callId)
                put("result", resultObj)
            }.toString()
            sendResult(responseJson)
        }
        super.finishAndRemoveTask()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            overrideActivityTransition(Activity.OVERRIDE_TRANSITION_CLOSE, 0, 0)
        } else {
            @Suppress("DEPRECATION")
            overridePendingTransition(0, 0)
        }
    }

    override fun finishAndRemoveTask() {
        finish()
    }

    override fun onDestroy() {
        activeSheetAnimator?.cancel()
        activeSheetAnimator = null
        activeStreamJob?.cancel()
        activityScope.cancel()
        if (activeInstanceRef?.get() === this) {
            activeInstanceRef = null
        }
        latestAssistBitmap = null
        latestAssistScreenText = null
        latestAssistCallerPkg = null
        currentBitmap = null
        attachedBitmaps.clear()
        activeSessionBitmap = null
        screenContextBitmap = null
        super.onDestroy()
        if (!callbackFired) {
            if (isInteractiveMode) {
                val resultObj = JSONObject().apply {
                    put("status", "closed")
                    put("interactive", true)
                    put("response", lastResponseText)
                }
                val responseJson = JSONObject().apply {
                    put("jsonrpc", "2.0")
                    put("id", callId)
                    put("result", resultObj)
                }.toString()
                sendResult(responseJson)
            } else {
                val errorObj = JSONObject().apply {
                    put("code", -32603)
                    put("message", "Mesh overlay activity destroyed before completing inference.")
                }
                val responseJson = JSONObject().apply {
                    put("jsonrpc", "2.0")
                    put("id", callId)
                    put("error", errorObj)
                }.toString()
                sendResult(responseJson)
            }
        }
    }

    // =========================================================================
    // CUSTOM MATERIAL 3 VECTOR ICON DRAWABLES (ZERO EMOJIS)
    // =========================================================================
    private enum class M3IconType {
        SPARKLE,
        CLOSE,
        OPEN_IN_FULL,
        SUMMARIZE,
        SEARCH,
        INSIGHT,
        EXTRACT,
        ADD_PHOTO,
        SEND
    }

    private class M3VectorDrawable(
        private val type: M3IconType,
        private val tintColor: Int,
        private val sizePx: Int
    ) : Drawable() {

        private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = tintColor
            style = Paint.Style.STROKE
            strokeWidth = (sizePx * 0.105f).coerceAtLeast(2f)
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }

        private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = tintColor
            style = Paint.Style.FILL
        }

        override fun getIntrinsicWidth(): Int = sizePx
        override fun getIntrinsicHeight(): Int = sizePx

        override fun draw(canvas: Canvas) {
            val b = bounds
            if (b.isEmpty) return
            val w = b.width().toFloat()
            val h = b.height().toFloat()
            val cx = b.exactCenterX()
            val cy = b.exactCenterY()
            val r = minOf(w, h) * 0.44f

            when (type) {
                M3IconType.SPARKLE -> {
                    val path = Path().apply {
                        moveTo(cx, cy - r)
                        quadTo(cx, cy, cx + r, cy)
                        quadTo(cx, cy, cx, cy + r)
                        quadTo(cx, cy, cx - r, cy)
                        quadTo(cx, cy, cx, cy - r)
                        close()
                    }
                    canvas.drawPath(path, fillPaint)
                }

                M3IconType.CLOSE -> {
                    val d = r * 0.72f
                    canvas.drawLine(cx - d, cy - d, cx + d, cy + d, strokePaint)
                    canvas.drawLine(cx + d, cy - d, cx - d, cy + d, strokePaint)
                }

                M3IconType.OPEN_IN_FULL -> {
                    val d = r * 0.70f
                    val boxLeft = cx - d
                    val boxBottom = cy + d
                    val boxTop = cy - d * 0.15f
                    val boxRight = cx + d * 0.15f
                    val boxPath = Path().apply {
                        moveTo(boxLeft, boxTop)
                        lineTo(boxLeft, boxBottom)
                        lineTo(boxRight, boxBottom)
                    }
                    canvas.drawPath(boxPath, strokePaint)

                    val ax = cx + d
                    val ay = cy - d
                    val startX = cx - d * 0.20f
                    val startY = cy + d * 0.20f
                    canvas.drawLine(startX, startY, ax, ay, strokePaint)
                    val headSize = d * 0.48f
                    canvas.drawLine(ax - headSize, ay, ax, ay, strokePaint)
                    canvas.drawLine(ax, ay + headSize, ax, ay, strokePaint)
                }

                M3IconType.SUMMARIZE -> {
                    val left = cx - r * 0.85f
                    val rightFull = cx + r * 0.45f
                    val rightShort = cx + r * 0.80f
                    canvas.drawLine(left, cy - r * 0.45f, rightFull, cy - r * 0.45f, strokePaint)
                    canvas.drawLine(left, cy + r * 0.05f, rightShort, cy + r * 0.05f, strokePaint)
                    canvas.drawLine(left, cy + r * 0.55f, cx + r * 0.25f, cy + r * 0.55f, strokePaint)
                    val sx = cx + r * 0.68f
                    val sy = cy - r * 0.52f
                    val sr = r * 0.32f
                    val sp = Path().apply {
                        moveTo(sx, sy - sr)
                        quadTo(sx, sy, sx + sr, sy)
                        quadTo(sx, sy, sx, sy + sr)
                        quadTo(sx, sy, sx - sr, sy)
                        quadTo(sx, sy, sx, sy - sr)
                        close()
                    }
                    canvas.drawPath(sp, fillPaint)
                }

                M3IconType.SEARCH -> {
                    val cr = r * 0.58f
                    val scx = cx - r * 0.15f
                    val scy = cy - r * 0.15f
                    canvas.drawCircle(scx, scy, cr, strokePaint)
                    canvas.drawLine(
                        scx + cr * 0.72f,
                        scy + cr * 0.72f,
                        cx + r * 0.78f,
                        cy + r * 0.78f,
                        strokePaint
                    )
                }

                M3IconType.INSIGHT -> {
                    val br = r * 0.54f
                    val by = cy - r * 0.22f
                    canvas.drawCircle(cx, by, br, strokePaint)
                    canvas.drawLine(cx - br * 0.45f, cy + r * 0.52f, cx + br * 0.45f, cy + r * 0.52f, strokePaint)
                    canvas.drawLine(cx - br * 0.28f, cy + r * 0.82f, cx + br * 0.28f, cy + r * 0.82f, strokePaint)
                }

                M3IconType.EXTRACT -> {
                    val rect = RectF(cx - r * 0.72f, cy - r * 0.85f, cx + r * 0.72f, cy + r * 0.85f)
                    canvas.drawRoundRect(rect, r * 0.22f, r * 0.22f, strokePaint)
                    canvas.drawLine(cx - r * 0.38f, cy - r * 0.30f, cx + r * 0.38f, cy - r * 0.30f, strokePaint)
                    canvas.drawLine(cx - r * 0.38f, cy + r * 0.08f, cx + r * 0.38f, cy + r * 0.08f, strokePaint)
                    canvas.drawLine(cx - r * 0.38f, cy + r * 0.45f, cx + r * 0.12f, cy + r * 0.45f, strokePaint)
                }

                M3IconType.ADD_PHOTO -> {
                    val rect = RectF(cx - r * 0.82f, cy - r * 0.72f, cx + r * 0.82f, cy + r * 0.78f)
                    canvas.drawRoundRect(rect, r * 0.25f, r * 0.25f, strokePaint)
                    canvas.drawCircle(cx - r * 0.34f, cy - r * 0.24f, r * 0.15f, fillPaint)
                    val mtn = Path().apply {
                        moveTo(cx - r * 0.62f, cy + r * 0.52f)
                        lineTo(cx - r * 0.15f, cy + r * 0.02f)
                        lineTo(cx + r * 0.18f, cy + r * 0.34f)
                        lineTo(cx + r * 0.42f, cy + r * 0.10f)
                        lineTo(cx + r * 0.65f, cy + r * 0.52f)
                    }
                    canvas.drawPath(mtn, strokePaint)
                }

                M3IconType.SEND -> {
                    val path = Path().apply {
                        moveTo(cx - r * 0.78f, cy - r * 0.72f)
                        lineTo(cx + r * 0.85f, cy)
                        lineTo(cx - r * 0.78f, cy + r * 0.72f)
                        lineTo(cx - r * 0.42f, cy)
                        close()
                    }
                    canvas.drawPath(path, fillPaint)
                }
            }
        }

        override fun setAlpha(alpha: Int) {
            strokePaint.alpha = alpha
            fillPaint.alpha = alpha
        }

        override fun setColorFilter(colorFilter: ColorFilter?) {
            strokePaint.colorFilter = colorFilter
            fillPaint.colorFilter = colorFilter
        }

        @Deprecated("Deprecated in Java")
        override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
    }
}
