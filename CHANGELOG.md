## Update 1.5.10 ([1.5.10] - 2026-11-13)
#### Improvements & Cleanups
- **Mesh Proposals, Alerts Icon & Resource Links (`assets/data/mesh_proposals.json`, `assets/additional_resources.json`, `lib/pages/settings/extensions.dart`, `lib/pages/intro.dart`)**:
  - Verified `page.puzzak.alerts` (`"alert"`) proposal entry in `mesh_proposals.json` and mapped `'alert'` to `Icons.notifications_active_rounded` in both `ExtensionsSettingsPage._resolveIcon` and `IntroPage._iconForMeshProposal`.
  - Fixed stale `Puzzaks/geminilocal` GitHub URLs and `id=page.puzzak.geminilocal` Play Store package ID across `additional_resources.json` and `intro.dart` to point to `Puzzaks/PAIOS` and `page.puzzak.paios`.
- **Dynamic App Metadata, Self-Package Resolution & Localization (`lib/pages/settings.dart`, `lib/pages/settings/extensions.dart`, `lib/pages/intro.dart`, `assets/translations/**`)**:
  - Replaced hardcoded `'page.puzzak.paios'` comparisons and store fallback URLs with `AIEngine.canonicalExtensionId('paios')`.
  - Updated `SettingsBentoHeader` in `settings.dart` to read `M3x.appName`, `M3x.appDescription`, and `M3x.versionDisplay` directly without stale hardcoded fallbacks, delegated `_showChangelogDialog` to `SettingsBentoHeader.showChangelogDialog`, and replaced the `"1.5.0"` diagnostic report fallback in `intro.dart` with `M3x.appVersion`.
  - Replaced hardcoded English UI labels in `extensions.dart` (`"Active"`, `"Disabled"`, `"No individual tool schemas exposed by this app."`, `"Live"`, `'tool'`/`'tools'`, and IPC footer) with localized `engine.dict.value(...)` keys across `en.json`, `uk.json`, `de.json`, `tr.json`, and `zh.json`.

## Update 1.5.9 ([1.5.9] - 2026-11-13)
#### Bugfixes & Hardening
- **Tool Synthesis Prompting & Clean Plain-Text Fallback (`lib/engine.dart`)**:
  - Removed parrot-prone `"The tool '...' returned: [TOOL RESULT: ...]"` and `"You MUST answer..."` framing from `_triggerToolSynthesis` and `chatData` system history entries so Gemini Nano synthesizes natural prose instead of echoing internal tool wrappers.
  - Added `_looksLikeUnformattedToolEcho` guard to retry once with `includeTools: false` on empty/echoed tool output and upgraded `_buildIncompleteToolFallback()` to format human-readable key-value summaries instead of raw JSON or `[TOOL RESULT: ...]` strings.
- **Recoverable Parameter Errors vs. Infrastructure Failures (`lib/engine.dart`)**:
  - Added `_isInfrastructureToolError` and `_extractSoftToolError` to distinguish transport/IPC outages (`is not running`, `timed out`, `HEADLESS_OVERLAY_REQUIRED`, etc.) from recoverable parameter errors (e.g. `StatusPage 'statuspage-1' not found`).
  - Infrastructure errors immediately disable tools (`includeTools: false`), withhold entity lists, and guard against hallucinated `"no incidents"` responses (`_looksLikeHallucinatedNormalOnError`).
  - First-turn recoverable parameter errors (`_recoverableErrorRetries == 0 && _toolTurnCount < 3`) allow 1 self-correction turn with `includeTools: true` and an explicit retry hint before stopping tools on a 2nd failure.

## Update 1.5.8 ([1.5.8] - 2026-11-13)
#### Bugfixes & Hardening
- **Native Streaming Lifecycle & Cancellation (`FlutterLocalAiPlugin.kt`, `lib/parts/gemini.dart`)**:
  - Tracked and cancelled `activeStreamJob` in `onCancel` and on subsequent stream starts, with `CancellationException` rethrown cleanly instead of being wrapped as an error.
  - Ordered `.catch` before `.onCompletion { cause -> ... }` and gated `Done` emission on `cause == null && !streamFailed` so cancelled or failed streams never emit spurious `Done` events.
  - Propagated `reason` cleanly onto `AiEvent` (filtering `"null"` and `"UNKNOWN"` placeholders) and initialized `lastFinishReason = null`.
- **Resilient Tool Parsing, Continuation & Tool-Free Synthesis (`lib/engine.dart`, `lib/parts/prompt.dart`, `lib/services/local_ai_provider.dart`)**:
  - Replaced regex `_extractToolCallJson` with shared balanced-brace `M3xToolCallParser` (`m3x_mesh`) handling nested JSON objects, unclosed markdown fences, escaped underscores (`\_`), trailing commas, unescaped string newlines, and single-quoted payloads.
  - Fixed continuation join boundaries (`_resolveJoin`, `Prompt.generateContinuation`) for cut-off JSON/code blocks and added `M3xToolCallParser.looksLikeIncompleteToolCall` detection so broken JSON tool drafts either continue cleanly or fall back without leaking into chat history.
  - Fixed `_triggerToolSynthesis` and `continueGenerating` so duplicate tool calls, tool-turn caps (`>= 6`), or infrastructure/IPC errors force a `includeTools = false` final prose turn instead of committing unexecuted JSON tool requests or hallucinating "no incidents" on tool errors.
  - Eliminated cross-stream `onDone` race conditions across `generateStream`, `continueGenerating`, and `_triggerToolSynthesis` via `_streamGenerationId`, `receivedTerminalEvent`, and `_activeToolHandling`.
  - Fixed invalid single-quoted tool call schema examples across `prompt.dart`, `local_ai_provider.dart`, and `MeshOverlayActivity.kt`.
  - Wired `meshClient.startListening()` in `AIEngine._registerLocalTools()`.
- **Overlay Streaming & Tool Parser Hardening (`MeshOverlayActivity.kt`)**:
  - Replaced greedy/non-greedy regex `extractToolCallJson` with balanced-brace scanner + tolerances and `looksLikeIncompleteToolCall`.
  - Gated `.onCompletion` on `cause == null && !streamFailed` in both overlay conversation and synthesis streams, hiding the progress indicator on error and preventing broken/errored drafts from polluting `sessionMessages`.
  - Added `[TOOL ERROR — DATA UNAVAILABLE]` banner when overlay mesh calls fail so Gemini Nano never fabricates normal status on IPC errors.

## Update 1.5.7 ([1.5.7] - 2026-11-12)
#### Features & Improvements
- **Dedicated Extensions Management Page (`lib/pages/settings/extensions.dart`, `settings.dart`)**:
  - Replaced the legacy monolithic `enable_mesh` switch in settings with a dedicated `ExtensionsSettingsPage` (`Icons.extension_rounded`).
  - Added Master Switch ("Allow all new extensions", persisted in Hive `paios_storage` under `mesh_allow_all_new`, defaulting to `false`).
  - Implemented reverse-DNS canonicalization (`canonicalExtensionId` / `canonicalAppId`) mapping short names (`ptk`, `demo`, `the2k48`, `binotool`, `ggscanus`) to package IDs, eliminating duplicate cards and permission mismatches.
  - Implemented "Connected Extensions" section dynamically discovering installed mesh applications via `meshClient.discoverInstalledTools()`, `listMeshApps()`, and native `isPackageInstalled` package queries.
  - Added per-extension toggle controls with first-party apps (`page.puzzak.*`, `com.puzzak.*`) enabled by default and third-party apps governed by master permissions.
  - Implemented rich M3 bottom sheet inspector displaying package identifier, live tools count, detailed parameter schemas, and real-time execution status.
  - Added "Works with PAIOS" section loading `mesh_proposals.json`, automatically omitting installed extensions, and offering one-tap Play Store / GitHub navigation for available proposals (including PTK server health telemetry & Demo UI playground).
- **Tool Prompt Filtering, Execution Guarding & Multi-Turn Tool Chaining (`lib/engine.dart`)**:
  - Implemented `isExtensionEnabled(pkg)` helper ensuring disabled extensions are completely excluded from prompt schemas sent to Gemini Nano.
  - Added defensive execution interceptor in `_handleToolCall` blocking rogue invocations of disabled extensions.
  - Enabled multi-turn tool chaining and pagination: replaced rigid tool inequality with signature checking (`$toolName:${jsonEncode(args)} != _lastToolCallSignature`) up to 6 turns, unlocking sequential queries (e.g. `ptk_list_incidents(page: 1)` -> `page: 2`).
  - Resolved multi-turn conversation loss by carrying `originalPrompt` and `isFollowUpTurn`, preventing blank user bubble duplicates during chained tool turns.
  - Expanded synthesis prompt directing the model to invoke secondary tools if granular data or follow-up details are needed.
- **Persistent Multi-Turn Vision Context in Overlay (`MeshOverlayActivity.kt`)**:
  - Declared `activeSessionBitmap` persisting across interactive streaming turns.
  - Resolved multi-turn vision drop-off: follow-up prompts now maintain full visual awareness of screenshots without requiring re-attachment.
  - Safely reset image session on explicit close, activity destroy, image removal, or replacement.
- **Tool Schema Negative Bounds & Hallucination Elimination (`MeshOverlayActivity.kt`, `lib/parts/prompt.dart`)**:
  - Added Rule 4 to `CRITICAL TOOL INVOCATION RULES`: strictly forbids tool invocations when answering questions about visual contents, images, photos, UI widgets, screenshots, or apps on screen.
  - Constrained `get_battery_status` schema with explicit negative bounds: "NEVER invoke this tool for questions about images, photos, screen icons, UI widgets, or visible apps."
  - Wired extension permission checks in overlay via `FlutterSharedPreferences` before executing external tool IPC.
- **Language Preservation During Tool Synthesis (`MeshOverlayActivity.kt`, `lib/engine.dart`)**:
  - Conditioned tool synthesis prompt on `shareLocale`: respects active app language if enabled, or strictly preserves the user request's original natural language (e.g., Ukrainian) to prevent flipping to English.
- **Onboarding Slide Overhaul (`lib/pages/intro.dart`, `assets/translations/**`)**:
  - Overhauled Slide A-6 with `Icons.hub_rounded`, highlighting 100% on-device private IPC, zero cloud relays, and zero tracking.
  - Featured showcase cards for PTK (server health & Statuspage incidents), Demo UI playground, and transparent user permission controls in Settings → Extensions.
  - Updated all 5 localization bundles (`en.json`, `uk.json`, `de.json`, `tr.json`, `zh.json`).

## Update 1.5.6 ([1.5.6] - 2026-11-12)
#### Features & Improvements
- **AI Message Bubble Layout & Boundary Spacing (`chat.dart`, `elements.dart`)**:
  - Resolved AI bubble boundary clipping where bubbles touched or slipped into the left screen boundary.
  - Standardized `SingleChildScrollView` gutter in `chat.dart` with `horizontal: 12.0` (M3 standard margin).
  - Configured AI message bubble cards with explicit `margin: const EdgeInsets.only(left: 4.0, right: 36.0, top: 2.0, bottom: 4.0)` across both historical and streaming chunk builders.
  - Styled AI cards with `shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))`, `color: colorScheme.surfaceContainerHigh`, and internal padding `EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0)`.
  - Updated AI message bubble max width constraint to `(width * 0.80).clamp(180.0, 560.0)` for optimal readability across varied aspect ratios.
- **Persona Steering & Tool Selection Rules (`system_default.md`, `prompt.dart`, `doc_service.dart`)**:
  - Set explicit on-device assistant identity in `system_default.md` to prevent Gemini Nano base weights from identifying as Gemma or a cloud model.
  - Updated `CRITICAL TOOL INVOCATION RULES` in `prompt.dart` (Rule 2) directing the model to never call tools for general knowledge, conceptual questions about AI models, Gemini Nano, self-identity, or casual conversation.
  - Refined `query_aicore_documentation` mesh tool description to target Google ML Kit GenAI documentation for Gemini Nano architecture, capabilities, token limits, system prompts, thinking mode, function calling, and AICore APIs.

## Update 1.5.5 ([1.5.5] - 2026-11-12)
#### Features & Improvements
- **Direct Google `.md.txt` Pure Markdown SWR Pipeline (`DocService`, `docs_manifest.json`, `assets/docs/**`)**:
  - Integrated Google Developers' native Markdown publishing engine directly by targeting official `.md.txt` endpoints across all 22 ML Kit GenAI documentation guides.
  - Eliminated complex HTML scraping, DOM entity decoding, and DevSite chrome parsing from `DocService.dart`, streamlining remote SWR synchronization into a pure Markdown pipeline with zero HTML overhead.
  - Bundled authentic, pristine Google `.md.txt` documentation files directly into `assets/docs/` for 100% offline day-0 availability.
  - Updated `assets/docs/docs_manifest.json` with canonical Google `.md.txt` `remoteUrl`s and browser-facing `officialUrl`s.
  - Streamlined `syncRemoteDocs()` and `refreshDoc(id)` with fast, non-blocking 4-second timeouts, HTML error document rejection, atomic disk caching (`docs_cache/<id>.md.txt`), and immediate UI listener updates.
- **Tool Call Bubble Polish (`lib/pages/support/elements.dart`)**:
  - Completely removed the "Complete" badge chip from `ToolCallBubble` header for a sleek, distraction-free display showing only the tool icon, action title, and animated expansion chevron.
- **Authentic Google ML Kit GenAI Documentation Overhaul (`assets/docs/**`)**:
  - Replaced all 23 markdown technical documentation guides with 100% authentic Google ML Kit GenAI developer specifications (`com.google.mlkit:genai-prompt:1.0.0-beta4`), eliminating internal client regex representations.
  - **Thinking Mode & Reasoning Chains (`thinking_mode.md.txt`)**: Integrated official Kotlin API (`generateContentRequest { text(...); enableThinking = true }`) and native thought extraction via `response.thoughtProcess` and streaming candidate chunks for Gemini Nano V4+.
  - **System Instructions (`system_instructions.md.txt`)**: Implemented official `SystemInstruction("...")` API with root KV cache injection and persistent NPU steering for Gemini Nano V3+.
  - **Function Calling & Tool Declarations (`function_calling.md.txt` & `agent_tools.md.txt`)**: Documented official `@androidx.appfunctions.AppFunctionDeclaration`, `@AppFunctionSerializable`, and `com.google.mlkit:genai-schema` (`FunctionDeclaration`, `FunctionSchema`) RPC architectures.
  - **Structured Output (`structured_output.md.txt`)**: Updated to reflect official Kotlin Symbol Processing (KSP) schema generation, `@JsonClass(generateAdapter = true)`, and logits-level constrained grammar decoding.
  - **Direct Model Access & Modalities**: Updated complete hardware and client API guides (`Generation.getClient()`, `generativeModel.checkStatus()`, `FeatureStatus.AVAILABLE / DOWNLOADABLE / UNAVAILABLE`), multi-modal ViT downsampling (768px), on-device Whisper/Conformer speech recognition, real-time speech translation, neural TTS, document summarization, proofreading, rewriting, and vector embeddings.
- **Interactive SWR Remote Doc Refresh & Live Browser Links (`DocService` & `DocExplorerPage`)**:
  - Transformed the "Bundled Offline" / "Synced" badge into an interactive one-tap action chip with haptic feedback, disk cache clearance, and immediate remote fetch.
  - Added dedicated `refreshDoc(id)` method in `DocService` ensuring atomic cache eviction, remote download with fallback, and timestamped UI state updates.
  - Added context-aware "Open in Browser" action buttons in the AppBar and article footers navigating directly to the live Google developer documentation portal (`https://developers.google.com/ml-kit/genai/...`).
  - Updated `docs_manifest.json` with canonical raw endpoints and direct `officialUrl` mappings across all 23 documentation topics.
- **Chat Bubble Image Caption Alignment & Responsive Sizing (`m3x_chat`)**:
  - Fixed chat bubble image caption alignment by enforcing `CrossAxisAlignment.start`, aligning text descriptions flush with image boundaries.
  - Implemented responsive constraint checking preventing layout overflows and awkward whitespace on compact mobile screens.
- **Enriched Android "App Data" Accessibility Extraction (`FlutterLocalAiPlugin.kt` & `MainActivity.kt`)**:
  - Deepened screen context extraction to prioritize focused interactive elements, extract web domains and deep links from active browser viewports, and capture input hints and placeholder texts.
  - Formatted structured app context for seamless ingestion by Gemini Nano during screen analysis tasks.

## Update 1.5.4 ([1.5.4] - 2026-11-12)
#### Features & Improvements
- **Handlebar Drag Physics & Screen Fill in Assistant Popup Overlay (`MeshOverlayActivity.kt`)**:
  - Implemented dynamic velocity-aware handlebar dragging with anchored bottom sheet height stretching.
  - Added full-screen expansion threshold: dragging past 80% viewport height smoothly animates to 100% full-screen fill.
  - Seamlessly respects soft keyboard IME insets (`WindowInsetsCompat.Type.ime()`) and system gesture navigation exclusion zones during drag transitions.
- **Mesh Tool Execution & Synthesis Loop in Assistant Popup Overlay**:
  - Integrated on-device `m3x_mesh` tool execution loop directly within the native assistant overlay.
  - Intercepts tool call requests emitted by Gemini Nano, executes local system APIs and sibling mesh tools (e.g. `query_aicore_documentation`, `check_battery_status`), and injects `FunctionResponse` payloads back into the session context for immediate answer synthesis.
- **Elimination of Recursive Continuation Loop & Synthesis Prompt Preservation (`AIEngine.dart`)**:
  - Resolved runaway recursive continuation calls when stream responses exceed native timeout boundaries.
  - Guaranteed strict preservation of initial synthesis prompt throughout multi-turn continuations, preventing persona drift and context amnesia.
- **Tool Call Bubble UI Enhancements (`ChatBubbleList.dart` / `puzzak_ui_chat`)**:
  - Streamlined tool call visual representation: removed redundant `[✓ Complete]` badge for a clean, distraction-free bubble interface.
  - Added descriptive action summaries (e.g. "Reading documentation for 'devices'", "Checking battery status").
  - Added smooth interactive fold/unfold toggling allowing inspection of raw tool execution payloads and return values on demand.
- **Message Rendering Order Resolution**:
  - Fixed visual interleaving bug where tool bubbles rendered out-of-order; ensured user prompt consistently renders above tool call bubbles and assistant responses across all turns.
- **Chat ID "0" Persistence Race Condition Resolution (`ChatRepository.dart`)**:
  - Resolved asynchronous race condition where newly initiated assistant chats could be indexed with default ID "0" prior to database key generation.
  - Enforced atomic ID reservation before writing messages, guaranteeing instant persistence and flawless archive synchronization.
- **Settings Refinements**:
  - Dynamically hides "Set as Default Assistant" configuration card when PAIOS is already verified as the active system assistant.
  - Integrated persistent review status tracking via `in_app_review` preventing repetitive review prompts.
  - Hardened fallback mechanism directing users seamlessly to Google Play Store or web market URL if native in-app review dialog is unavailable.
- **Onboarding Refinements (`IntroPage.dart` & `IntroSlideRepository.dart`)**:
  - Refined slide layout by removing redundant action chips and decluttering visual hierarchy.
  - Added active Gemini Nano readiness verification with live NPU weight download progress indicators.
  - Implemented intelligent mesh tool filtering and curated proposal catalog displaying compatible sibling apps (PTK, 2048, BinoTool).
  - Added direct link to open-source repository and community discussion channels.
- **Translation Integrity & UTF-8 BOM Elimination**:
  - Stripped UTF-8 Byte Order Mark (`\xef\xbb\xbf`) from `assets/translations/en.json`, enforcing strict UTF-8 across all localization resources.
  - Synchronized 163 missing keys across Ukrainian (`uk.json`), German (`de.json`), Turkish (`tr.json`), and Traditional Chinese (`zh.json`), eliminating missing literal warnings (`!!!key`) across debug and release builds.
- **23-Page Comprehensive Offline & SWR Documentation Hub (`DocService` & `DocExplorerPage`)**:
  - Expanded documentation manifest (`docs_manifest.json`) to cover the full Google ML Kit GenAI technical sitemap across 23 exhaustive guides:
    1. Direct Model Access (Beta) Overview (`direct_model_overview`)
    2. Get Started with Direct Model Access (`get_started`)
    3. Prompt Design Best Practices (`prompt_design`)
    4. Evaluate Prompt Quality (`evaluate_prompt`)
    5. System Instructions & Persona Tuning (`system_instructions`)
    6. Prefix Caching Architecture & Reusability (`prefix_caching`)
    7. Generate Structured JSON Output (`structured_output`)
    8. Thinking Mode & Reasoning Chains (`thinking_mode`)
    9. Function Calling & Mesh Tools (`function_calling`)
    10. Model Selection & TPU Acceleration (`select_model`)
    11. Agentic Workflows (Preview) Overview (`agent_overview`)
    12. Defining & Registering Agent Tools (`agent_tools`)
    13. Managing Agent Sessions & State (`agent_lifecycle`)
    14. Streaming Events & UI Synchronization (`agent_streaming`)
    15. On-Device Speech Recognition (Whisper / Conformer) (`speech_recognition`)
    16. Real-Time Speech Translation (`speech_translation`)
    17. Neural Text-to-Speech (`tts_api`)
    18. Multimodal Image Description & OCR (`image_description`)
    19. Document & Conversation Summarization (`summarization`)
    20. Proofreading & Grammar Correction (`proofreading`)
    21. Text Rewriting & Style Transfer (`rewriting`)
    22. On-Device Vector Embeddings (`embeddings`)
    23. Supported Hardware & Device Eligibility Matrix (`devices`)
  - Created 23 dense offline markdown fallback assets (`assets/docs/*.md.txt`) ensuring complete 0ms offline availability, structured table of contents parsing, and full-text RAG search indexing.

## Update 1.5.3
#### Features & Improvements
- **3-Tier SWR Multi-Page Documentation Explorer (`DocService` & `DocExplorerPage`)**:
  - **Tier 1 (Bundled Offline Assets)**: Instant 0ms offline availability on day 0 via bundled `assets/docs/genai.md.txt` and `assets/docs/docs_manifest.json`.
  - **Tier 2 (Disk Caching)**: High-speed disk cache in `docs_cache/<page_id>.md.txt` with automatic filesystem persistence and instant retrieval.
  - **Tier 3 (Background SWR on Each Launch)**: Asynchronous post-launch background synchronization (`unawaited(docService.syncRemoteDocs())`) updating documentation on app startup without blocking UI or engine readiness.
  - **Resilient Network & Offline Fault Tolerance**: 4-second network timeout, silent offline fallbacks, and HTML error page rejection to protect cached Markdown integrity.
  - **Expanded 8 Google ML Kit GenAI Documentation Guides**:
    1. `Supported Devices & Hardware` (`devices`, bundled offline fallback)
    2. `AICore Developer Preview` (`aicore_preview`)
    3. `ML Kit GenAI Agent Workflows` (`agent_api`)
    4. `On-Device Neural Text-to-Speech` (`tts_api`)
    5. `Direct Model Access & Prompt API` (`direct_model`)
    6. `Structured Output & Function Calling` (`structured_output`)
    7. `Speech Recognition & Translation` (`speech_recognition`)
    8. `On-Device Summarization & Rewriting` (`summarization`)
  - **Interactive Multi-Page UI**:
    - Horizontal scrollable Material 3 category selector with dedicated icons.
    - Real-time sync badge indicator (`Bundled Offline` vs `Synced`).
    - Cross-page global search with term-frequency scoring and section relevance.
    - Section jump chips for quick Table of Contents navigation.
    - Enhanced `query_aicore_documentation` Agentic Mesh tool returning multi-page metadata.

## Update 1.5.0
#### Features & Improvements
- **Atomic Google Analytics Generation Telemetry (`ai_generation_completed`)**:
  - Replaced skewed multi-event reporting with an atomic single-event payload dispatched on every Gemini Nano inference completion or error.
  - Eliminated cardinality overflow and skewed denominators by enforcing a constant `generation_count: 1` denominator metric alongside dedicated `is_success` and `is_error` sums.
  - Telemetry schema specification:
    | Parameter | Type | GA4 Type | Description & Purpose |
    | :--- | :--- | :--- | :--- |
    | `status` | `String` | Dimension | Primary execution outcome: `"success"` or `"error"`. |
    | `is_error` | `int` | Metric (Sum) | `1` on failure, `0` on success. Allows instant error rate computation. |
    | `is_success` | `int` | Metric (Sum) | `1` on success, `0` on failure. |
    | `generation_count` | `int` | Metric (Sum) | Constant `1`. Serves as the true, unskewed denominator across all slices. |
    | `error_type` | `String` | Dimension | Root failure cause: `"none"`, `"timeout"`, `"model_busy"`, `"context_overflow"`, `"npu_unavailable"`. |
    | `error_code` | `int` | Metric | Low-level native platform or AICore return code (e.g. `-100`, `-101`). |
    | `finish_reason` | `String` | Dimension | Completion trigger: `"stop"`, `"max_tokens"`, `"timeout"`, `"error"`. |
    | `latency_ms` | `int` | Metric (Avg) | Total generation duration from dispatch to completion in milliseconds. |
    | `tokens_generated` | `int` | Metric (Sum) | Total tokens emitted during inference. |
    | `tokens_per_sec` | `double` | Metric (Avg) | Effective throughput computed as `tokens / (latencyMs / 1000.0)`. |
    | `model_version` | `String` | Dimension | Active on-device neural weight version (e.g. `"nano-v3"`, `"nano-v2"`). |
    | `prompt_id` | `String` | Dimension | Identifier of active system prompt/persona (e.g. `"system_default"`, `"concise"`). |
    | `is_multimodal` | `int` | Metric (Sum) | `1` if visual context (image) was attached, `0` for text-only inference. |

- **Dual-Branch Onboarding System (`IntroPage` & `IntroSlideRepository`)**:
  - Implemented dynamic first-run onboarding branching based on device hardware support and AICore readiness:
    - **Branch A (Supported / Downloading / Ready)**:
      - **Privacy-First Architecture**: Highlights 100% on-device processing ("Your Mind, On Your Device") — prompts and visual context never leave hardware.
      - **Anonymous Diagnostics**: User-controllable toggle for crash reporting and performance metrics (`allow_anonymous_usage`).
      - **Default Digital Assistant Setup**: Integrated onboarding card with one-tap deep link to Android's `ACTION_VOICE_INPUT_SETTINGS` or deferral.
      - **Smart Model Download Card**: Live byte formatters, download speed calculator (`calcSpeed`), progress percentage, and indeterminate recovery on app relaunch.
      - **SWR GitHub Prompts**: Stale-while-revalidate background synchronization of starter system prompts from GitHub.
      - **Open Agentic Mesh**: Introductory walkthrough of cross-app agentic tool execution via `m3x_mesh`.
    - **Branch B (Unsupported / Hardware Incompatible / AICore Missing)**:
      - **Compatibility Matrix**: Diagnostic check comparing device hardware to official AICore prerequisites.
      - **Persistent Diagnostic Report**: Dedicated `Copy Diagnostic Report` action formatting device model, board, manufacturer, Android SDK API level, and AICore package presence directly to clipboard for GitHub issue filing.
      - **In-App Docs & GitHub Explorer**: Instant access to in-app documentation and GitHub discussion channels.
      - **Instant Re-Check Action**: On-demand AICore status re-probe (`checkEngine()`) without requiring app restart.

- **In-App Google GenAI Documentation Explorer (`DocExplorerPage`) & Local RAG Tool (`DocService`)**:
  - **`DocService` Local Engine**:
    - Embedded official Google ML Kit GenAI and AICore documentation (`assets/docs/genai.md.txt`) chunked into `DocSection` objects via markdown headings.
    - Fast in-memory term-frequency scoring engine with keyword boosts for critical operational terms (`-101`, `-100`, `busy`, `token`, `quota`, `pixel`, `vision`).
  - **`DocExplorerPage` UI**:
    - Material 3 documentation reader with real-time search filtering, category quick-filter chips, and full Markdown rendering.
    - Accessible directly from Intro, Settings, and Model Settings.
  - **Local RAG Agentic Mesh Tool (`query_aicore_documentation`)**:
    - Registered on `M3xToolRegistry` under app `'paios'`.
    - Enables Gemini Nano and external mesh nodes to autonomously query official documentation on supported devices, token limits, system prompt rules, error codes, and multimodal vision specs during conversational reasoning.

- **Settings Additions & App Maintenance**:
  - **Default Assistant Detection & Action Card**: Real-time system assistant verification via `isDefaultAssistant()`. Displays active confirmation or action card with one-tap link to system assistant settings.
  - **"Review PAIOS on Google Play" Action**: In-app rating flow via `in_app_review` (`InAppReview.instance.requestReview()`) with automatic fallback to `market://details?id=page.puzzak.paios` and web browser.
  - **Live Pubspec Dependency Viewer**: Real-time dependency count and inspection sheet powered by `M3x.dependencies`.

## Update 1.4.2
#### Features & Improvements
- **Assistant Session Isolation & Context Freshness**:
  - Solved cross-invocation state leak in `MeshOverlayActivity.kt` and `PaiosVoiceInteractionService.kt`. Every new session resets `conversationHistoryPrompt`, `visualContextMemory`, `contextData`, and `currentBitmap`.
  - System assist screenshot and hierarchy snippets are constrained to a strict 1500ms TTL and consumed once on first read.
  - Session closure (`closeInteractiveSession`) and activity destruction explicitly purge all cached bitmaps, package names, and snippets.
- **Active Persona System Prompt Injection**:
  - Injected active persona instruction prompt into Gemini Nano streaming inference in `MeshOverlayActivity.kt`.
  - Prepend structure: `System Instruction / Persona: $activePersonaPrompt` -> `Context` -> `Recent Conversation` -> `User Request`.
  - Added automatic dual-layer synchronization in `AIEngine.dart` writing `defaultPromptContent`, `defaultPromptId`, and `defaultPromptTitle` to `SharedPreferences` on prompt switch and engine startup. Bundled fallback loads prompt markdown directly from assets.
- **Anchored Bottom Stretching Drag Handle**:
  - Replaced translation-based lifting with anchored bottom height stretching in `MeshOverlayActivity.kt`.
  - Sheet bottom remains firmly anchored to the navigation bar or IME soft keyboard (`WindowInsetsCompat.Type.ime()`). Dragging up or down stretches `sheetCard.layoutParams.height`, with auto-dismiss threshold and smooth spring animation to compact / expanded states.
- **Symmetrical "Open in Full App" Header Action**:
  - Added top-left 32dp circular button with native Material 3 `OPEN_IN_FULL` vector icon (`M3IconType.OPEN_IN_FULL`), symmetrical to the top-right close button.
  - Serializes active session messages into `open_chat_messages` intent extra and launches `MainActivity` unarchived.
- **Complete Chat Archive & Auto-Archive Ecosystem**:
  - **Data Model & Settings**: Added `autoArchiveAssistantChats` (default `true`) in `AppConfig`, exposed as a toggle in `SettingsPage`. Added `isArchived` metadata flag in `ChatRepository` with `archiveChat` and `unarchiveChat` (moves chat to top of list by refreshing `updated` timestamp). Enforced rule: pinned chats cannot be archived.
  - **Dedicated `ArchivedChatsPage`**: Accessible directly via the top `SliverAppBar` action with active count badge. Features swipe-to-unarchive and full options sheet.
  - **In-Page Expandable Archive**: Rendered collapsible "Archived (N)" card section in `ChatsPage` below active chats.
  - **Localized**: Full string coverage across English (`en`), Ukrainian (`uk`), German (`de`), Turkish (`tr`), and Chinese (`zh`).

## Update 1.4.1
#### Fixes & Improvements
- **16 KB Page Size Alignment on Android 15/16 (`libdatastore_shared_counter.so`)**:
  - Added Gradle resolution strategy forcing `androidx.datastore:datastore-core-android:1.1.7`, `androidx.datastore:datastore-preferences-android:1.1.7`, `androidx.datastore:datastore-core:1.1.7`, and `androidx.datastore:datastore-preferences:1.1.7` across all build configurations.
  - Added explicit implementation dependencies for 16 KB aligned DataStore libraries.
  - Completely eliminates 16 KB alignment memory warnings and crashes on Android 15/16 and Google Pixel 9 Pro.
- **Decentralized Inter-App Mesh Discovery (`m3x_mesh`)**:
  - Replaced hardcoded queries in `AIEngine.start()` with `meshClient.discoverInstalledTools()`.
  - Automatically discovers all tools declared by installed mesh nodes (such as `demo_get_environment` and `demo_get_components` from Demo) with zero hardcoded package names and a 2-second timeout per node.

## Update 1.4.0
#### Features & Improvements
- Android Assistant & System Interaction Complete Overhaul:
  - **Assistant Opening Reliability**: Removed premature 750ms dismissal timer (`safetyHideRunnable`) in `PaiosVoiceInteractionSession.kt`; window dismissal now strictly triggers upon user dismissal or overlay finish.
  - **Rotating Persona Opening Phrases**: Integrated 5-10 vibrant localized opening greetings per persona (Default, Pirate, Concise, Creative) with non-consecutive rotation across all 5 languages (`en`, `uk`, `de`, `tr`, `zh`). Synchronized active persona with Flutter via `SharedPreferences`.
  - **Distraction-Free Minimalist UI**: Removed scrim darkening (`#00000000`), removed clutter pills ("PAIOS", "nano-v3", "Assist • Vision"), removed suggestion chips, and added generous 28dp card corner radii with clean top drag handle and subtle close button.
  - **Smooth Drag Handle & Touch Physics**: Replaced tap-to-expand glitch with continuous 1:1 translation tracking, smooth swipe-down to dismiss, and swipe-up to expand without abrupt height jumps.
  - **Keyboard Handling & Dynamic Window Insets**: Implemented `ViewCompat.setOnApplyWindowInsetsListener` adjusting for IME and navigation bars; output view flexes smoothly while keeping the input row permanently docked at bottom.
  - **Image Lifecycle & Visual Context Retention**: Replaced screen-spanning image previews with a compact chip above the input row; automatically nests thumbnails into user conversation bubbles upon send; introduced `visualContextMemory` so Gemini Nano retains visual scene context across multi-turn queries.
  - **Dynamic Theme & Material You (Monet)**: Added `ThemePalette` reading system Monet tokens (`android.R.color.system_*`) on Android 12+ and caching Flutter palette to `SharedPreferences` with zero hardcoded hex colors.
  - **Removed "Tensor TPU" Mentions**: Removed all references to "Ready on Tensor TPU" across all translations and code.
  - **Super-Minimal Non-Interactable Mode (Mode C)**: Added 1×1 invisible headless overlay mode for automated/timed background assistant tasks without UI flashes.

## Update 1.3.0
#### Changes
- On-Device Multimodal Vision & Image Attachments:
  - Added image attachment button (`Icons.add_photo_alternate_outlined`) and Material 3 image preview bar (48×48 thumbnail, filename, resolution badge, and remove action) to the Chat input bar (`lib/pages/chat.dart`).
  - Integrated native Android photo picker (`pickImage`) and multimodal streaming (`imageBytes`, `imagePath`, `imageBase64`, `downsample`) in `GeminiNano` (`lib/parts/gemini.dart`) and `AIEngine` (`lib/engine.dart`).
  - Rendered rounded Material 3 image thumbnails (`BorderRadius.circular(12)`, max height `200px`) inside conversation bubbles with tap-to-zoom full-screen `InteractiveViewer` modal (`lib/pages/support/elements.dart` and `m3x_chat`).
  - Added persistent chat image storage (`<appDataDir>/chat_images/chat_<chatId>/img_<timestamp>.jpg`) with automatic cascading file & directory deletion when a chat is deleted or cleared (`ChatRepository`).
- Configurable Vision Downsampling & Agentic Mesh Controls:
  - Added **Fast Vision Downsampling (768px)** toggle (`downsampleImages`) in AI Model Settings (`lib/pages/settings/model.dart`), allowing users to switch between fast 768px EdgeTPU prefill and full original screenshot resolution for small text/OCR.
  - Added **Inter-App Agentic Mesh** toggle (`enableMesh`) in Settings & Model Settings (`lib/pages/settings.dart`, `lib/pages/settings/model.dart`), persisted in Hive (`AppConfig`) and wired to `meshClient.enabled`.
  - Updated `query_local_ai` mesh tool to accept optional `image_base64` and `downsample` parameters for cross-app visual inference.
  - Localized all new vision and mesh settings across all 5 supported languages (`en`, `uk`, `de`, `tr`, `zh`).

## Update 1.2.14
#### Fixes
- 16 KB Page Size Alignment Fix (`libdatastore_shared_counter.so`):
  - Added Gradle resolution strategy forcing `androidx.datastore:datastore-core-android:1.1.7`, `androidx.datastore:datastore-preferences-android:1.1.7`, `androidx.datastore:datastore-core:1.1.7`, and `androidx.datastore:datastore-preferences:1.1.7` across all build configurations.
  - Added explicit implementation dependencies for 16 KB aligned DataStore libraries.
  - Eliminates the 16 KB alignment warning on Android 15/16 and Google Pixel 9 Pro.
- Decentralized Inter-App Mesh Discovery (`m3x_mesh`):
  - Replaced hardcoded queries in `AIEngine.start()` with `meshClient.discoverInstalledTools()`.
  - Automatically discovers all tools declared by installed mesh nodes (such as `demo_get_environment` and `demo_get_components` from Demo) with zero hardcoded package names and a 2-second timeout per node.

## Update 1.2.13
#### Fixes
- Floating Window & Touch/Scroll Passthrough in `MeshOverlayActivity`:
  - Defined `MeshOverlayTheme` with `android:windowIsFloating="true"`, `android:backgroundDimEnabled="false"`, and `android:windowIsTranslucent="true"`.
  - Added `FLAG_NOT_FOCUSABLE` and `FLAG_NOT_TOUCH_MODAL` to `MeshOverlayActivity` window flags.
  - Constrained DecorView to wrap content at the bottom of the screen, preventing full-screen gesture interception and focus stealing, allowing seamless background scrolling in caller apps (e.g. Demo or PTK) during active Gemini Nano inference.

## Update 1.2.12
#### Changes
- Non-Modal Touch Passthrough in `MeshOverlayActivity`:
  - Added `FLAG_NOT_TOUCH_MODAL` and `FLAG_WATCH_OUTSIDE_TOUCH` with `clearFlags(FLAG_DIM_BEHIND)`.
  - Touches outside the bottom pill now pass directly through to the underlying application without blocking or freezing user interactions.
- UI Styling Constants & Theming:
  - Cleanly exposed pill styling parameters (`CARD_BG_COLOR`, `ACCENT_COLOR`, `CARD_CORNER_RADIUS_DP`, padding, typography, etc.) as dedicated constants for easy customization.

## Update 1.2.9
#### Changes
- Hardware Feature Gating:
  - Added `<uses-feature android:name="android.hardware.npu" android:required="true" />` to `AndroidManifest.xml` to explicitly require NPU hardware.

## Update 1.2.7
#### Fixes
- Android Package Installation & Hardware Feature Gating Fix:
  - Replaced invalid `<uses-library android:name="com.google.android.aicore" android:required="true" />` declaration with `<uses-feature android:name="android.hardware.npu" android:required="true" />` in `AndroidManifest.xml`.
  - Clarified that Google AICore is an Android system application service (queried via `<queries><package android:name="com.google.android.aicore" /></queries>`), not an OS-level shared library (`<uses-library>` caused Android PackageManager to fail installation with `INSTALL_FAILED_MISSING_SHARED_LIBRARY`).
  - Google Play hardware gating is now correctly enforced via `android.hardware.npu` hardware feature, restoring flawless package installation and sideloading on supported devices (such as Google Pixel 9 Pro).

## Update 1.2.6
#### Changes
- Mandatory AICore System Library Gating:
  - Configured `<uses-library android:name="com.google.android.aicore" android:required="true" />` in `AndroidManifest.xml`.
  - Google Play now automatically restricts distribution to supported hardware equipped with Google AICore, eliminating manual device catalog exclusions and skipping automated pre-launch bots on unsupported virtual devices.

## Update 1.2.5
#### Changes
- Material 3 Expressive Bento Settings Header (`SettingsBentoHeader`):
  - Added segmented 3-card Material 3 Expressive Bento header to the top of the Settings page.
  - Displays primary application brand card ('PAIOS') with dynamic subtitle derived from `M3x.appDescription`.
  - Integrates interactive Version & Build card displaying clean semantic version and build date derived from `M3x.versionDisplay`. Tapping opens a draggable changelog viewer sheet rendered via `flutter_markdown`.
  - Integrates interactive Connected Modules card displaying active ecosystem modules count (5) with one-tap inspection modal listing `m3x_ui`, `m3x_dict`, `m3x_core`, `m3x_chat`, and `m3x_mesh`.
- Central M3x Ecosystem Orchestrator (`M3x.init()`):
  - Integrated `m3x` master package orchestration into `AIEngine.start()`.
  - Auto-parses bundled `pubspec.yaml` and `CHANGELOG.md` assets for app identity, build dates, and changelog contents.

## Update 1.2.0 `OBT`
#### Changes
- Translucent Bottom Status Pill / Foreground Overlay (`MeshOverlayActivity`):
  - Implemented programmatic Material 3 bottom progress pill activity with transparent window (`@android:style/Theme.Translucent.NoTitleBar`) anchored to `Gravity.BOTTOM`.
  - Satisfies Google AICore's mandatory foreground window check when external apps (`demo`, `ptk`) call `query_local_ai` while PAIOS is closed, minimized, or in the background.
  - Runs on-device Gemini Nano inference via Google ML Kit GenAI Prompt API directly on the NPU and automatically dismisses upon returning the JSON-RPC 2.0 response.
- `m3x_mesh` Inter-App Agentic Tool Calling & AI Provider Architecture:
  - Migrated packages from legacy `puzzak_*` to modular `m3x_*` ecosystem (`m3x_ui`, `m3x_chat`, `m3x_dict`, `m3x_core`, and new `m3x_mesh`).
  - Integrated `M3xMeshClient` and `M3xToolRegistry` into `AIEngine`.
  - Implemented `GeminiLocalAiProvider` connecting on-device Gemini Nano inference to `M3xAiProvider`.
  - Registered local PAIOS tools: `query_local_ai` (Gemini Nano on-device LLM inference) and `get_ai_status`.
  - Discovered and registered sibling tools from `ptk` (`ping_host`, `calculate_subnet`) and `the2k48` (`get_high_score`).
  - Enhanced `Prompt.generate` with `### [AVAILABLE TOOLS]` schema injection and structured JSON tool-calling directives.
  - Implemented two-stage agentic tool execution with context appending and second-stage conversational natural language synthesis.
- Real Android ContentProvider IPC (`M3xMeshContentProvider`):
  - Native Android `ContentProvider` (`M3xMeshContentProvider`) registered under `content://${applicationId}.mesh` (`page.puzzak.paios.mesh`).
  - Added Android 11+ `<queries>` package and provider visibility declarations for `page.puzzak.paios`, `page.puzzak.demo`, `com.puzzak.ptk`, `com.puzzak.the2k48`, and `com.puzzak.binotool`.
  - Real-time bidirectional telemetry logging across Android Logcat (`M3xMesh`) and Dart console.
- App Status Check API:
  - Added `checkAppStatus` for fast health and readiness checks before starting inference.
- Added in-app GitHub Explorer (`GitHubService` & `GitHubExplorerPage`) with 4 interactive tabs:
  - Repository Documentation browser (README, ROADMAP, CHANGELOG, etc.) with Markdown rendering & image support
  - Live GitHub Issues explorer with search, labels, and issue comments thread bottom sheet
  - Releases explorer with release notes and asset download links
  - Project Security & Open-Source License overview
- Added native AICore Beta Track detection (`isAICoreBeta`, package version inspection via `PackageManager`):
  - Beta badge & update track indicator in AI Model Settings
  - Direct deep link to AICore System & Developer Settings (for Persistent Mode and cache management)
  - One-tap "Join AICore Beta" button directing to Google Play Beta enrollment
  - Fully localized new AICore Beta and Developer Settings keys across all 5 supported languages (en, uk, de, tr, zh)
- Applied velocity-based directional scroll motion blur (`MotionBlurContainer`) across all pages (`chats`, `chat`, `settings`, `intro`, `model`, `prompts`, `prompt_editor`, `prompt_viewer`, `resources`, `logs`, `context`)
- Replaced legacy template unit tests with comprehensive regression and widget test suite
#### Fixes
- Self-Deadlock & ANR Elimination:
  - Implemented local app short-circuit (`_isLocalApp`) in `m3x_mesh` so local tool calls execute in-memory (0ms) without invoking the native ContentProvider on its own process, completely eliminating main thread deadlocks and ANRs.
- Strict Negative Tool Scoping & Hallucination Suppression:
  - Filtered out self-hosted AI tools (`query_local_ai`, `get_ai_status`) from Gemini Nano's system instructions.
  - Added explicit negative constraints prohibiting tool calls for greetings ("hi", "how are you"), pleasantries, or general knowledge, preventing random tool calling.
- Simulation Fallback Elimination:
  - Disabled simulation mode on native Android so PAIOS only discovers and registers real, physically installed sibling tools.
- Startup Splash Timeout Safeguard:
  - Added a 2-second timeout on sibling discovery in `AIEngine.start()` so PAIOS never hangs on the splash screen if sibling apps are missing or uninstalled.
- Real-time Generation Deduplication:
  - Fixed real-time deduplication during active generation and auto-continuation (eliminated duplicate bubbles while streaming).
- Historical Message Duplicate Suppression:
  - Fixed historical duplicate message suppression in `elements.dart` `text.chatlog`.
- Header Filter Logic:
  - Fixed "Other chats" / "Pinned chats" header filter logic in `chats.dart`.
- Intro Theme Styling:
  - Removed nested `MaterialApp` and legacy grey theme styling in `IntroPage`, restoring full Material 3 dynamic color support.
- Null-Safe Links:
  - Fixed null-unsafe link launching in Markdown conversation bubbles.
- System Locale Fallback:
  - Fixed system language fallback to `"en"` when device locale is not bundled in `languages.json`.
- Analyzer Cleanliness:
  - Resolved all analyzer warnings across `engine.dart`, `intro.dart`, `settings.dart`, and `logs.dart`.

## Update 1.1.8 `OBT`
#### Changes
- Reworked and optimized settings and other parts
- Updated prompt manager
- Prompt exports in .md
- Prompt imports in .md
#### Fixes
- Fixed issue with chats not being saved
- Fixed issue with resource names not being translated
- Fixed issue with prompts not being downloaded from GH
#### Known Issues
 - Autocoplete still may behave weirdly, still testing it
 - Chat from "Testing prompt" still mau count towards total chat counter

## Update 1.1.7 `OBT`
#### Changes
- Auto-continue on long responses
- Per-chat temperature
- Reworked and optimized settings 
#### Known Issues
 - Chats may not save
 - Prompts are not loaded from GitHub
 - Chat from "Testing prompt" counts towards total chat counter
 - Autocoplete is in testing and may not behave correctly:
   - It may prompt model to continue when it's answer is finished (especially if the answer took exactly 25 seconds to complete)
   - It may NOT prompt model to continue even if it was cut-off

## Update 1.1.6 `OBT`
#### Changes
- Prompt manager
- Prompt editor
- Per-chat prompts
- System and user prompts are replacing master and user prompts, now you are in control!
- DB storage instead of shared preferences
- Early implementation of remote configs from Firebase

## Update 1.1.5 `OBT`
#### Fixes
 - Fixed Google Analytics misreporting
 - Added Google Crashalitics
 - Fixed app getting stuck in offline mode
 - Fixed downloading logs
#### Changes
 - Added logs to the intro screen for debugging (Sorry, Basim)
#### Contributions
 - [@mikropsoft](https://github.com/mikropsoft) added Turkish translation
 - [@NewNiklas](https://github.com/NewNiklas) added German translation

## Update 1.1.3 `OBT`
#### Fixes
 - Fixed analytics preventing app from starting in offline mode
#### Contributions
 - [@abc0922001](https://github.com/abc0922001) added Chinese translation

## Update 1.1.2 `OBT`
#### Changes
 - Added optional analytics for debugging and crash reporting
 - Added internal logs for the app

## Update 1.1.1 `OBT`
#### Changes
 - Chat list now shows status of generation in the correct chat
 - You now can jump only to the chat that is being generated now
 - New chat card is at the top of the list
 - "AI Title" function now describes the whole chat, not the first message only
 - Some code refactoring
#### Fixes
 - Fixed that "Pinned" category would appear even if there are none
 - Fixed that "Other chats" category was not shown when there are pinned chats
 - Fixed the issue with messages appearing in wrong chats
 - Fixed the issue where messages were not in order
#### Miscellaneous
 - Changed color variables throughout the app (you shouldn't notice any changes visually, it was internal)

## Update 1.1.0 `OBT`
#### Changes
 - Multichats!
   - You can now have more than one chat and switch between them.
   - You can now pin chats to the top of the list.
   - You can now rename chats yourself or get a title from Gemini Nano.
 - Updated Settings
   - Adding per-chat settings, some options were moved from settings to per-chat ones.
 - Refactoring and optimisation
   - Rewrited dart-side of the generator,
   - Removed obsolete files,
   - Optimized file structure.
 - Bug fixes
   - (some of them were fixed just by changing the structure)
 - Master Prompt changes
 - Ability to go instruction-less
   - When toggled, model will only receive minimal instructions with chat history.
   - This WILL produce weird and incorrect responses, with lots of hallucinations.
   - Use at your own risk!
 - Auto-retry now works better and in more situations 
#### Fixes
 - Fixed some unwanted prompting behavior in the master prompt
#### Known Issues
 - Rapidly switching between chats (especially when the AI is still generating) may cause messages to not save.
 - Exiting the chat into the chat menu when generating may cause some temporary lagging.
 - Closing the app before response generates may cause loss of the last generated text.
 - Closing the chat before the name of the chat changes will likely make chat history empty.
 - Typing curses or slurs may soft-lock the app if the auto-retry is enabled
   - This happens because model hits an internal censorship and reports an error;
   - When encountering error while generating, with auto-retry, app sends the same input back, getting the same error;
   - This feedback loop will not end untill the app is restarted, and it also consumes huge amount of battery life.

  
## Update 1.0.1 `OBT`
#### Changes
 - New Intro page
 - Model download status display
 - Updated Settings
 - Code optimisation
 - Bug fixes
 - Master Prompt changes
#### Fixes
 - Fixed the issue with app skipping the initialization when model is unavailable
 - Fixed issue with app not requesting model download
 - Fixed issue with translations not being loaded from repository
#### Known Issues
 - The AI is unstable so it can:
   - Ignore requests
   - Generate erroneous information
   - Mix historical events with current time
   - Hallucinate
   - Ignore instructions
   - Mix requests and responses in chat log


 ## Update 1.0.0 `OBT`
#### Changes
 - Initial Release


---
> Template for later updates
```Markdown
## Update 1.0.0 `OBT`
#### Changes
#### Fixes
#### Known Issues
#### Miscellaneous
```
