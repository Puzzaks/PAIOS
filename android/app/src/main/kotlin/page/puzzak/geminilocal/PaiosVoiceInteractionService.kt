package page.puzzak.geminilocal

import android.app.ActivityOptions
import android.app.assist.AssistContent
import android.app.assist.AssistStructure
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.service.voice.VoiceInteractionService
import android.service.voice.VoiceInteractionSession
import android.service.voice.VoiceInteractionSessionService
import android.speech.RecognitionService
import android.speech.SpeechRecognizer
import android.util.Log
import androidx.annotation.Keep
import java.lang.ref.WeakReference

/**
 * Android System Digital Assistant VoiceInteractionService for PAIOS.
 *
 * Enables PAIOS to be bound by Android's `VoiceInteractionManagerService` as the active
 * system Digital Assistant (Power button long-press / corner swipe) and receive live screen
 * hierarchy (`AssistStructure`) and screen captures (`onHandleScreenshot`).
 */
@Keep
class PaiosVoiceInteractionService : VoiceInteractionService() {
    override fun onReady() {
        super.onReady()
        Log.d("PaiosAssistService", "[VOICE INTERACTION SERVICE READY] PAIOS bound as active system assistant")
        MeshOverlayActivity.preloadTranslationsAsync(applicationContext)
    }
}

/**
 * Required companion `RecognitionService` for `VoiceInteractionServiceInfo` validation in AOSP.
 * Without a valid `android:recognitionService` in `res/xml/interaction_service.xml`, Android's
 * `VoiceInteractionManagerService` rejects the `VoiceInteractionService` with
 * `Bad voice interaction service: No recognitionService specified`.
 */
@Keep
class PaiosRecognitionService : RecognitionService() {
    override fun onStartListening(intent: Intent?, listener: Callback?) {
        try {
            listener?.error(SpeechRecognizer.ERROR_CLIENT)
        } catch (_: Exception) {}
    }

    override fun onCancel(listener: Callback?) {}

    override fun onStopListening(listener: Callback?) {}
}

@Keep
class PaiosVoiceInteractionSessionService : VoiceInteractionSessionService() {
    override fun onNewSession(args: Bundle?): VoiceInteractionSession {
        return PaiosVoiceInteractionSession(this)
    }
}

@Keep
class PaiosVoiceInteractionSession(context: Context) : VoiceInteractionSession(context) {

    companion object {
        private const val TAG = "PaiosAssistSession"

        private val GENERIC_CHROME = setOf(
            "back",
            "up",
            "navigate up",
            "navigate back",
            "more options",
            "more",
            "share",
            "home",
            "menu",
            "close",
            "search",
            "clear",
            "clear query",
            "voice search",
            "cancel",
            "done",
            "ok",
            "refresh",
            "overflow menu",
            "settings"
        )

        private val CONTENT_ID_KEYWORDS = listOf(
            "title",
            "body",
            "summary",
            "content",
            "desc",
            "message",
            "query",
            "article",
            "comment",
            "post",
            "text",
            "headline",
            "caption",
            "subtitle"
        )

        @Volatile
        private var activeSessionRef: WeakReference<PaiosVoiceInteractionSession>? = null

        @Keep
        @JvmStatic
        fun dismissActiveSession() {
            val session = activeSessionRef?.get() ?: return
            try {
                session.hide()
            } catch (_: Exception) {}
        }
    }

    override fun onCreate() {
        super.onCreate()
        activeSessionRef = WeakReference(this)
        MeshOverlayActivity.preloadTranslationsAsync(context.applicationContext)
    }

    override fun onPrepareShow(args: Bundle?, showFlags: Int) {
        super.onPrepareShow(args, showFlags)
        // Disable the default system voice layer UI since we render MeshOverlayActivity directly
        setUiEnabled(false)
    }

    override fun onShow(args: Bundle?, showFlags: Int) {
        super.onShow(args, showFlags)
        activeSessionRef = WeakReference(this)
        MeshOverlayActivity.clearAssistCache()

        val overlayIntent = Intent(context, MeshOverlayActivity::class.java).apply {
            component = ComponentName(context, MeshOverlayActivity::class.java)
            action = Intent.ACTION_ASSIST
            addCategory(Intent.CATEGORY_DEFAULT)
            addCategory(Intent.CATEGORY_VOICE)
            setPackage(context.packageName)
            putExtra("interactive_bubble", true)
            putExtra("from_voice_session", true)
            if (args != null) {
                putExtras(args)
            }
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                    Intent.FLAG_ACTIVITY_NO_ANIMATION
            )
        }

        var launched = false
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                val opts = ActivityOptions.makeBasic().apply {
                    setPendingIntentBackgroundActivityStartMode(
                        ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED
                    )
                }
                startAssistantActivity(overlayIntent, opts.toBundle())
            } else {
                startAssistantActivity(overlayIntent)
            }
            launched = true
            Log.d(TAG, "[SESSION ON_SHOW] Launched MeshOverlayActivity via startAssistantActivity (flags=$showFlags)")
        } catch (e: Exception) {
            Log.w(TAG, "startAssistantActivity failed, falling back to context.startActivity: ${e.message}")
        }

        if (!launched) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    val opts = ActivityOptions.makeBasic().apply {
                        setPendingIntentBackgroundActivityStartMode(
                            ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED
                        )
                    }
                    context.startActivity(overlayIntent, opts.toBundle())
                } else {
                    context.startActivity(overlayIntent)
                }
                Log.d(TAG, "[SESSION ON_SHOW] Launched MeshOverlayActivity via context.startActivity (flags=$showFlags)")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start MeshOverlayActivity from VoiceInteractionSession: ${e.message}", e)
            }
        }
    }

    override fun onDestroy() {
        if (activeSessionRef?.get() === this) {
            activeSessionRef = null
        }
        super.onDestroy()
    }

    override fun onHandleAssist(state: AssistState) {
        super.onHandleAssist(state)
        try {
            val structure = state.assistStructure
            val content = state.assistContent
            extractAndPublishAssistStructure(structure, content)
        } catch (e: Exception) {
            Log.e(TAG, "onHandleAssist error: ${e.message}", e)
        }
    }

    @Deprecated("Deprecated in Android API 29, kept for compatibility")
    override fun onHandleAssist(
        data: Bundle?,
        structure: AssistStructure?,
        content: AssistContent?
    ) {
        @Suppress("DEPRECATION")
        super.onHandleAssist(data, structure, content)
        try {
            extractAndPublishAssistStructure(structure, content)
        } catch (e: Exception) {
            Log.e(TAG, "Legacy onHandleAssist error: ${e.message}", e)
        }
    }

    override fun onHandleScreenshot(screenshot: Bitmap?) {
        super.onHandleScreenshot(screenshot)
        if (screenshot != null) {
            Log.d(TAG, "[ASSIST SCREENSHOT RECEIVED] ${screenshot.width}x${screenshot.height}")
            MeshOverlayActivity.updateSystemAssistScreenshot(screenshot)
        }
    }

    private data class CandidateItem(
        val text: String,
        val idEntry: String?,
        val isFocused: Boolean,
        val order: Int
    )

    private fun extractAndPublishAssistStructure(
        structure: AssistStructure?,
        content: AssistContent?
    ) {
        if (structure == null && content == null) return

        val callerPkg = structure?.activityComponent?.packageName
        if (callerPkg == context.packageName) {
            return
        }
        val snippets = LinkedHashSet<String>()

        // 1. Deep Link URIs and URLs from AssistContent
        content?.webUri?.toString()?.trim()?.takeIf { it.isNotBlank() }?.let {
            snippets.add("URL: $it")
        }
        content?.intent?.dataString?.trim()?.takeIf { it.isNotBlank() }?.let {
            snippets.add("DeepLink: $it")
        }
        content?.structuredData?.trim()?.takeIf { it.isNotBlank() }?.let {
            snippets.add("StructuredData: $it")
        }

        if (structure != null) {
            val windowCount = structure.windowNodeCount
            for (i in 0 until windowCount) {
                val winNode = structure.getWindowNodeAt(i)
                val title = winNode.title?.toString()?.trim()
                if (!title.isNullOrEmpty() && !title.contains("page.puzzak.paios")) {
                    snippets.add("Window: $title")
                }
                winNode.rootViewNode?.let { root ->
                    collectViewNodeText(root, snippets)
                }
            }
        }

        val combinedText = snippets.joinToString("\n").take(3500)
        if (combinedText.isNotBlank() || !callerPkg.isNullOrBlank()) {
            Log.d(
                TAG,
                "[ASSIST STRUCTURE EXTRACTED] Caller: $callerPkg | Chars: ${combinedText.length}"
            )
            MeshOverlayActivity.updateSystemAssistContext(
                callerPkg = callerPkg ?: "Screen",
                screenText = combinedText
            )
        }
    }

    private fun collectViewNodeText(
        node: AssistStructure.ViewNode,
        out: MutableSet<String>
    ) {
        val candidates = mutableListOf<CandidateItem>()
        val domains = LinkedHashSet<String>()
        val focusedItems = LinkedHashSet<String>()

        var orderCounter = 0
        traverseViewNode(
            node = node,
            depth = 0,
            candidates = candidates,
            domains = domains,
            focusedItems = focusedItems,
            orderCounter = { orderCounter++ }
        )

        // 1. Web domains (e.g. Domain: en.wikipedia.org)
        for (domain in domains) {
            out.add("Domain: $domain")
        }

        // 2. Focused view content prominently at the top
        for (focused in focusedItems) {
            out.add(focused)
        }

        // 3. Salient content prioritization (respecting remaining slots out of 80)
        val remainingSlots = (80 - out.size).coerceAtLeast(0)
        if (remainingSlots > 0) {
            val prioritized = prioritizeCandidates(candidates, remainingSlots)
            out.addAll(prioritized)
        }
    }

    private fun traverseViewNode(
        node: AssistStructure.ViewNode,
        depth: Int,
        candidates: MutableList<CandidateItem>,
        domains: MutableSet<String>,
        focusedItems: MutableSet<String>,
        orderCounter: () -> Int
    ) {
        if (depth > 50) return
        if (node.visibility != android.view.View.VISIBLE) return

        // 1. WebView Web Domain check
        try {
            node.webDomain?.trim()?.takeIf { it.isNotBlank() }?.let { domain ->
                domains.add(domain)
            }
        } catch (_: Exception) {}

        val rawText = node.text?.toString()?.trim()
        val rawHint = try {
            node.hint?.toString()?.trim()
        } catch (_: Exception) {
            null
        }
        val rawDesc = node.contentDescription?.toString()?.trim()

        // 2. Input Field Hints fallback when text is blank
        val effectiveText = if (!rawText.isNullOrBlank()) {
            rawText
        } else if (!rawHint.isNullOrBlank()) {
            rawHint
        } else {
            null
        }

        val isFocused = try {
            node.isFocused
        } catch (_: Exception) {
            false
        }

        // 3. Focused View Content: flag or prepend so user's active focus is prominent
        if (isFocused) {
            val focusContent = effectiveText ?: rawDesc
            if (!focusContent.isNullOrBlank() && focusContent.length >= 2) {
                focusedItems.add("Focused: $focusContent")
            }
        } else {
            val isAlreadyFocused = focusedItems.any { it == "Focused: $effectiveText" }
            if (!effectiveText.isNullOrBlank() && effectiveText.length >= 2 && !isAlreadyFocused) {
                candidates.add(
                    CandidateItem(
                        text = effectiveText,
                        idEntry = node.idEntry,
                        isFocused = false,
                        order = orderCounter()
                    )
                )
            }
        }

        // Also capture contentDescription if distinct from text and not already focused
        if (rawDesc != null && rawDesc.length >= 2 && rawDesc != effectiveText && !isFocused) {
            val isAlreadyFocused = focusedItems.any { it == "Focused: $rawDesc" }
            if (!isAlreadyFocused) {
                candidates.add(
                    CandidateItem(
                        text = rawDesc,
                        idEntry = node.idEntry,
                        isFocused = false,
                        order = orderCounter()
                    )
                )
            }
        }

        val count = node.childCount
        for (i in 0 until count) {
            val child = node.getChildAt(i) ?: continue
            traverseViewNode(child, depth + 1, candidates, domains, focusedItems, orderCounter)
        }
    }

    private fun scoreCandidate(item: CandidateItem): Int {
        val lower = item.text.lowercase().trim()
        if (GENERIC_CHROME.contains(lower)) {
            return if (item.isFocused) 100 else -100
        }

        var score = 0
        val id = item.idEntry?.lowercase() ?: ""
        if (CONTENT_ID_KEYWORDS.any { id.contains(it) }) {
            score += 50
        }

        val len = item.text.length
        score += when {
            len >= 120 -> 60
            len >= 60 -> 40
            len >= 25 -> 25
            len >= 10 -> 15
            len >= 5 -> 5
            len < 3 -> -20
            else -> 0
        }

        if (item.isFocused) {
            score += 300
        }

        return score
    }

    private fun prioritizeCandidates(
        candidates: List<CandidateItem>,
        maxCount: Int
    ): List<String> {
        if (candidates.isEmpty() || maxCount <= 0) return emptyList()

        val deduplicated = LinkedHashMap<String, Pair<CandidateItem, Int>>()
        for (item in candidates) {
            val score = scoreCandidate(item)
            val existing = deduplicated[item.text]
            if (existing == null || score > existing.second) {
                deduplicated[item.text] = Pair(item, score)
            }
        }

        val topItems = deduplicated.values
            .sortedByDescending { it.second }
            .take(maxCount)
            .map { it.first }

        return topItems
            .sortedBy { it.order }
            .map { it.text }
    }
}
