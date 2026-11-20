## Update 1.8.9 ([1.8.9] - 2026-11-20)
#### Changes
- **ML Kit GenAI `1.0.0-beta5` Integration (`FlutterLocalAiPlugin.kt`, `PaiosModelHelper.kt`, `MeshOverlayActivity.kt`, `lib/engine.dart`, `assets/docs/genai.md.txt`)**: Integrated `model.warmup()`, `PromptPrefix` caching, native multi-image `Content` `ImagePart`s replacing vertical canvas stitching, `countTokens`/`getTokenLimit`, `FunctionCall` streaming capture, `topK`/`seed` sampling parameters, non-deprecated `getAvailableFeatures()`, and fixed `GenAiException.ErrorCode` `BUSY (9)` vs `AICORE_INCOMPATIBLE (-101)` classification (updating the `genai.md.txt` Error Taxonomy table to match verified `beta5` bytecode constants).
- **Lifecycle Sync & Voice Extension Roadmap (`lib/engine.dart`, `assets/data/mesh_proposals.json`, `ROADMAP.md`)**: Added `AppLifecycleState.resumed` sync for dismissed Assistant Overlay chats and updated `mesh_proposals.json` and `ROADMAP.md` for the upcoming standalone **PAIOS Voice (`TinyASR` + TTS)** Companion M3x Extension (`android.speech.RecognitionService` + `TextToSpeech` + offline Live Voice loop).
#### Fixes
- **Simplified Chinese (`zh-Hans`) Asset & PR `#36` Localization Parity (`pubspec.yaml`, `assets/translations/*`, `assets/prompts/*`, `assets/additional_resources.json`, `lib/pages/*`, `MeshOverlayActivity.kt`)**: Registered `assets/translations/zh-Hans.json` in `pubspec.yaml` and completed PR `#36` localization across built-in prompts, resources, extension modules, UI pages, and System Assistant Overlay tool/thought labels.
- **Kotlin Lifecycle, SAF I/O & Bitmap Memory Fixes (`FlutterLocalAiPlugin.kt`, `MainActivity.kt`, `FileAccessPlugin.kt`, `MeshOverlayActivity.kt`)**: Fixed `FlutterLocalAiPlugin.dispose()` coroutine scope cancellation, `MainActivity` headless handler Activity leak, `FileAccessPlugin` main-thread SAF I/O, and unrecycled/unscaled bitmap allocations.
- **Token-Budgeted Sliding Window, Cutoff Trimming & Performance (`lib/engine.dart`, `lib/pages/chats.dart`)**: Added token-budgeted sliding window context management and unpunctuated multi-sentence cutoff trimming (`"...for enhanced reasoning"`) in `AIEngine`, and eliminated the per-token 500ms streaming delay, per-turn background `syncRemoteDocs()` HTTP calls, and background `ChatsPage` full-history JSON re-parsing.

## Update 1.8.8 ([1.8.8] - 2026-11-16)
#### Changes
- **Bare-Minimum Default System Prompt & Runtime PAIOS Self-Knowledge (`system_default.md`, `doc_service.dart`, `internal_tools_service.dart`, `InternalToolsHelper.kt`, `devices.md.txt`, `genai.md.txt`)**: Slimmed `system_default.md` to a 2-sentence baseline (always refreshed from bundled assets in `PromptRepository.initFromHive` and `MeshOverlayActivity.resolveActivePersonaContent`) and expanded `query_aicore_documentation` (plus aliases `about_paios`, `paios_info`, `get_paios_info`) with comprehensive offline PAIOS self-knowledge sections (`PAIOS Overview, Identity & Privacy`, `Model Variants & Thinking Mode`, `System Assistant Overlay & inspect_screen`, `Extensions & M3x Mesh`) so `"who are you?"` and `"tell me about yourself"` queries retrieve detailed, accurate context on demand without bloating every turn's system prompt.
- **Simplified Chinese (`zh-Hans`) Localization & Script-Aware Auto-Detection (`assets/translations.json`, `translator.dart`, `MeshOverlayActivity.kt`, PR `#36`)**: Added full Simplified Chinese (`zh-Hans`) translation alongside Traditional Chinese (`zh`) and implemented script/region-aware Chinese locale resolution (`Hans` / `CN` / `SG` / `MY` -> `zh-Hans`, `Hant` / `TW` / `HK` / `MO` -> `zh`) across the main app and Assistant Overlay.
- **AICore `ErrorCode 606` (`FEATURE_NOT_FOUND`) OEM Provisioning Diagnostics (`engine.dart`, `intro.dart`, `model.dart`, Issues `#37`, `#35`)**: Added `isAiCoreFeatureNotFoundError` detection and a dedicated troubleshooting diagnostic card in Setup (`IntroPage`) and Model Settings explaining OEM AICore feature table provisioning restrictions when AICore is installed and updated on Android 14+.
- **Android 13+ Monochrome Adaptive Launcher Icon & Release Keystore Fallback (`ic_launcher.xml`, `android/app/build.gradle.kts`, Issue `#10`, PR `#39`)**: Restored the `<monochrome android:drawable="@drawable/ic_launcher_monochrome" />` layer for Android 13+ themed icons and guarded `signingConfigs.release` with `hasReleaseKeystore` so contributor and CI release builds without `key.properties` fall back cleanly to debug signing.
#### Fixes
- **Earlier-Sentence Loop Deduplication & Final-Round `trimTrailingIncompleteSentence` (Dart + Kotlin)**: Added `>= 24`-char earlier-sentence/clause repetition stripping and loop termination in `stitchContinuation` / `detectAndTrimStutterLoop` / `stitchOverlayContinuation` / `hasContinuationStutter` (preventing multi-round continuations from restarting earlier sentences), raised `maxNullReasonContinuations` to `3`, and added `trimTrailingIncompleteSentence` at all final commit paths in `AIEngine` and `MeshOverlayActivity` so responses with at least one complete sentence cleanly trim any dangling post-continuation tail fragment (`"The wind is blowing at"`, `"illustrates how an"`).
- **Prompt Export/Import, Storage Sanitization & UI Polish (`file_access.dart`, `prompts.dart`, `resource_repository.dart`, `chats.dart`, `chat_settings.dart`, `translations.json`)**: Fixed UTF-8 `.md` prompt export encoding (`utf8.encode`), preserved Unicode CJK/Cyrillic characters in SAF prompt filenames (`nameToFilename`), triggered immediate prompt folder import after SAF directory selection (`pickPromptsFolder`), sanitized legacy `https://puzzak.page/PAIOS` resource URLs in `ResourceRepository`, guarded `ChatsPage` token counter against null message text, fixed `ChatSettingsPage` previous title dropdown selection, and added missing archived-chat/overlay localization keys across all 6 locales.
- **Verification**: Added `translation_parity_and_refs_test.dart`, `storage_and_migration_test.dart`, and `InternalToolsHelperTest.kt`, and expanded `geminilocal` Dart tests (`test/hardening_184_test.dart`: `33` tests), Kotlin unit tests (`PaiosModelHelperTest.kt`: `35` tests), and `m3x_dict`/`m3x_core`/`m3x_ui` unit test suites.

## Update 1.8.7 ([1.8.7] - 2026-11-16)
#### Fixes
- **Truncated `inspect_screen` Repair & Fallback Continuation (`PaiosModelHelper.kt`, `MeshOverlayActivity.kt`, `InternalToolsHelper.kt`)**: Added string/brace-aware truncated tool JSON closure repair (recovering `109`-char `inspect_screen` drafts missing `"}}`), raised `MAX_TOOL_JSON_CONTINUATIONS` to `2` with open-string continuation cues and `args: {}` preference, gave `runToolFreeFallbackAttempt` an auto-continue loop (fixing `"and do not"` cutoffs) + stripped `"PAIOS:"` transcript prefix echoes, and preserved screen TTL across aborted/unparseable attempts.
- **Nano v4 Native `<ctrl42>call:...` Function Calling (`m3x_mesh 1.1.5+26111601`, `FlutterLocalAiPlugin.kt`, `MeshOverlayActivity.kt`, `lib/engine.dart`)**: Parsed Gemma/Nano v4 `<ctrl\d+>call:tool{unquoted_key: "val"}<ctrl\d+>` tokens (and `app:tool` prefixes), scrubbed raw control tags from `thought` bubbles (`stripControlToolTags`), promoted thought-trapped tool calls to tool execution when `text` is empty, and bounded empty-stream `errorRetry` retries (`maxEmptyStreamRetries = 1`).
- **Synthesis Preposition, `-ing` Participle & Negation `STOP` Rescue (Dart + Kotlin)**: Lifted the synthesis exclusion on `STOP` mid-clause rescue (`"The forecast for"`), added trailing transitive `-ing` participle cutoff rules (`"and ensuring"`) and short-preposition/negation rules (`"and do not"`).
- **Verification**: Expanded `m3x_mesh` (`50` tests), `geminilocal` Dart (`test/hardening_184_test.dart`: `27` tests), and Kotlin (`PaiosModelHelperTest.kt`: `32` tests).

## Update 1.8.6 ([1.8.6] - 2026-11-16)
#### Changes
- **`m3x_chat` `ChatThoughtsBlock` Smart Auto-Scroll (`0.2.3+26111602`)**: Added `ScrollController` auto-follow in expanded `ChatThoughtsBlock` while streaming chunks append, pausing cleanly whenever the user scrolls up manually (`24dp` threshold).
#### Fixes
- **Overlay Tool JSON & `inspect_screen` Reliability (Kotlin)**: Moved tool JSON parsing/repair (`extractToolCallJson`, `looksLikeIncompleteToolCall`, `sanitizeJsonLikeString` with missing-value and dangling-key repair + `"name"`/`"method"` and `"parameters"`/`"args"`/`"arguments"` normalization) into `PaiosModelHelper`; compacted `InternalToolsHelper.getInspectScreenPromptSpec()` & internal tool specs; removed mandatory `"description"` bloat from `getMeshToolSchemaPrompt`; removed the `incompleteTool` continuation loop bypass (`MAX_TOOL_JSON_CONTINUATIONS = 1`, never continuing tool drafts on `STOP`); omitted persona/question bloat from `isJsonDraft` continuation prompts; and added automatic tool-free fallback retry in `MeshOverlayActivity` before emitting `"Unable to parse completed tool request"`.
- **Disabled Extension Filtering & Synthesis Contraction Rescue (`engine.dart`, `prompt.dart`, `InternalToolsHelper.kt`)**: Synchronized `toolRegistry` (`_syncInternalToolRegistrations`) on init and `setExtensionEnabled` so disabled internal modules (e.g. `paios.wikipedia`) are excluded from `M3xMesh` tool discovery, `IntroPage`, and `Prompt.generate` guidance; gated Kotlin `executeDuckDuckGoSearch`'s `wikipedia_summary` hint on `MODULE_WIKIPEDIA`; and allowed 1 bounded `STOP` rescue even during synthesis for hard mid-token contraction/open-delimiter cutoffs (`"Right now, I can'"`).
- **Onboarding State Clarity & Composer Draft Isolation (`intro.dart`, `chat.dart`, `chats.dart`, `engine.dart`)**: Distinguished **Ready**, **Downloading**, **Downloadable**, and **Checking** states cleanly on `IntroPage` Slide A-4 across all 5 locales (`en`, `uk`, `zh`, `de`, `tr`), fixed `handleDownloadStatus('Available=Available=0')` missing-version ready detection, and added `AIEngine.startNewChat()` + exit cleanup so cancelled drafts do not leak across new chats.
- **Verification**: Expanded Kotlin (`PaiosModelHelperTest.kt`: 28 tests), Dart (`hardening_184_test.dart`, `intro_test.dart`), and `m3x_chat` widget tests (`13` tests).

## Update 1.8.5 ([1.8.5] - 2026-11-16)
#### Changes
- **On-Demand Assistant Screen Context Tool (`inspect_screen`)**: Replaced passive force-attached screenshots and `[BACKGROUND SCREEN CONTEXT]` system bloat in the Assistant Overlay with a lazy `inspect_screen` (`app: "paios"`) tool held for a `3`-turn TTL (`SCREEN_CONTEXT_TTL_TURNS = 3`) and silently dropped/recycled if irrelevant, preventing unrelated prompts (e.g. general questions while on the home screen) from misinterpreting the current screen image while still enabling VLM + `AssistStructure` inspection whenever asked about the screen.
#### Fixes
- **Mid-Clause `STOP` Cutoff Rescue & Prompt Coherence (Dart + Kotlin)**: Added preposition/determiner + trailing modifier mid-phrase detection (`isLikelyMidClauseCutoff` / `isTruncationHeuristic` catching cutoffs like `"with advanced"`), bounded 1-shot `STOP` / `"0"` rescue (`maxStopCutoffContinuations = 1` / `MAX_STOP_CUTOFF_RETRIES = 1`), and aligned `buildOverlayContinuationPrompt` to preserve trailing tokens in `Partial answer tail:` rather than deleting whole words from the prompt context.
- **Verification**: Added unit tests covering `isLikelyMidClauseCutoff` / `STOP` rescue (`test/hardening_184_test.dart`) and `inspect_screen` 3-turn TTL + Kotlin cutoff rescue (`PaiosModelHelperTest.kt`).

## Update 1.8.4 ([1.8.4] - 2026-11-16)
#### Fixes
- **Cancel & Stream Lifecycle Hardening (`AIEngine.cancelGeneration()`)**: Bumps `_streamGenerationId++` on cancel, nulls `_aiSubscription`, resets all active turn flags (`isLoading`, `isGenerating`, `isContinuing`, `_isSynthesizing`, `_activeToolHandling`, `_forcedFinalSynthesis`), clears pending turn buffers, prevents double-entry before `initEngine`, fixes `errorRetry` backoff deadlocks, and cleanly unlocks unexpected stream closures (`onDone`).
- **Continuation Overlap Deduplication, Mid-Word Recovery & Stutter Guard (Dart + Kotlin Overlay)**: Expanded `stitchContinuation` / `stitchOverlayContinuation` suffix-prefix overlap window (`240` chars, re-evaluated dynamically on cumulative streaming chunks), strips trailing/leading ellipsis seams (`...`, `..`, `. . .`, `…`), backs off mid-word cutoff tails cleanly (`splitTrailingPartialWord` / `MID_WORD_BACKOFF_MAX_CHARS = 28`) to prevent subword drops (`Eliezer Yud sky`), computes progress post-stitching, and halts runaway repetition loops (`detectAndTrimStutterLoop` / `hasContinuationStutter`).
- **Tool-Call Recovery & `InternalToolsService` Hardening**: Rescues invalid/incomplete Turn-1 tool JSON with one automatic tool-free fallback pass (`includeTools: false`), stops aborting streams solely for extra `"description"` keys, normalizes common argument aliases (`q`/`topic`/`title` -> `query`) with `wikipedia_details` -> `wikipedia_summary` fallback, prompts Nano to prefer `wikipedia_summary` for general explanations, gates `duckDuckGoSearch`'s `try wikipedia_summary` hint on module enablement, races `checkOnline()` DNS/TCP checks in parallel, and adds explicit `25s` timeout fallback around `readerAgent` in `wikipediaDetails`.
- **Verification**: Added 18 Dart unit tests (`test/hardening_184_test.dart`) and expanded `PaiosModelHelperTest.kt` Kotlin tests.

## Update 1.8.3 ([1.8.3] - 2026-11-16)
#### Changes
- Integrated the standardized `m3x_chat` message schema across the in-app chat (`ChatMessage`, `ChatMessageBubble` with `showAvatar: false`, inline collapsible `ChatThoughtsBlock`, and `ChatAnimatedSkeleton` for initial waiting and auto-continuation that transitions smoothly out as text arrives).
- Added assistant author attribution (`"Gemini Nano vX"` / `"You"`) and live per-chunk timestamp metadata persisted to `ChatRepository` and revealed on bubble tap.
- Added native `modelVariants` enumeration (`ComboStatuses` / `probeAllComboStatuses` in `FlutterLocalAiPlugin.kt` & `PaiosModelHelper.kt`) alongside a unified Language-style list Model Selector dialog (`showModelSelectorDialog`) accessible from both the `"nano-v3"`/`"nano-v4"` main header chip and Model Settings.
- Added decoupled multi-model background downloading (`FlutterLocalAiPlugin.variantDownloadJobs` independent of `activeResolvedClient`, reporting real `DownloadStarted.bytesToDownload` totals) with `AIEngine.downloadVariant` and `PaiosVariantDownloadState` live progress, speed (`B/s`–`GB/s`), and remaining-bytes UI in both the Model Selector dialog and Model Settings.
- Added a single-stable-model onboarding gate in `IntroPage` (`hasAnySupportedModel` / `hasAnyAvailableModel`), keeping supported devices with 0 downloaded models on Branch A until a default stable model finishes downloading.
- CI/CD: hardened `build_releases.ps1` (`-ApkOnly`, `-AabOnly`, fail-fast exits) and added `publish_nightly.ps1` (`dev` branch commit/push, GitHub Prerelease, Play Store Internal Testing `internal` upload with <=500-char notes).
#### Fixes
- Fixed Gemini Nano v3 premature truncation in both `ChatPage` and Assistant Overlay (`FlutterLocalAiPlugin.kt` emitting terminal `"done"` + `finishReason` from `generateContentStream`, tail-only `Prompt.generateContinuation` preserving v3 output headroom, and multi-round auto-continuation + compact v3 context budgets in `MeshOverlayActivity` / `PaiosModelHelper`).
- Eliminated continuation `...` / `…` seam artifacts (`AIEngine.stripLeadingEllipsis`, `Prompt.generateContinuation` anti-ellipsis directive, and `PaiosModelHelper.stitchOverlayContinuation`), capped normal prose auto-continuation (`maxProseContinuations = 3`, soft/hard stops at `1600`/`2400` chars, while keeping `maxContinuations = 10` inside open code blocks), and aborted malformed/empty-argument tool JSON continuation loops (`_isMalformedToolJsonDraft`).
- Fixed double User bubbles and duplicate synthesis AI bubbles during tool-call turns (`AIEngine` clearing `lastPrompt` / `streamingUserMessageTime` on tool commit and resetting `responseText` + `streamingMessageTime` via `_commitSynthesisMessage`), and localized tool fallback messages (`tool_fallback_infra_error`, `tool_fallback_partial_error`, `tool_fallback_invalid_request`).
- Fixed collapsed `ChatThoughtsBlock` (`m3x_chat v0.2.2+26111601`) and `ToolCallBubble(embeddedInBubble: true)` failing to shrink-wrap tightly, and removed double card nesting around embedded tool call bubbles.
- Fixed tapping Open/Expand on Assistant Overlay returning to `SettingsPage` instead of opening the Assistant chat (`appNavigatorKey` popping pushed routes via `popUntil` and pushing `ChatPage` for live and cold-start unarchived chats, plus preventing duplicate `pending_assistant_chats` writes).
- Fixed nested thought-block scroll leaking velocity blur to parent `ChatPage` (`m3x_ui` `depth != 0` guard + `ChatThoughtsBlock` isolated `MotionBlurContainer`).
- Fixed short user/AI chat bubbles failing to shrink-wrap (`ChatMessageBubble` `SizeTransition(fixedCrossAxisSizeFactor: 1.0)` + `MarkdownBody(fitContent: true, shrinkWrap: true)`).
- Fixed static `selectorModelVariants` list ordering, radio indicators, internal model IDs (`internalModelName`, e.g. `gemini-nano-v3`, `gemini-nano-v4-fast`), inverted `FeatureStatus` `'1'`/`'2'` in `ModelSettings`, and active-inference model-switching lock (`FlutterLocalAiPlugin.activeGenerationCount` + `AIEngine.isLoading` guard).
- Hardened `Dictionary` (`translator.dart`) against mojibaked remote/cached translations (auto-repairing CP1251/Latin-1 artifacts and preventing poisoned GitHub/Hive strings like `"Continuing responseвЂ¦"` from overwriting clean bundled strings) and switched remaining repository/doc HTTP decodes to `utf8.decode(response.bodyBytes)`.
- Added unit and widget regression tests in `test/bugfix_v3_translator_test.dart`, `test/viewport_scroll_test.dart`, and `PaiosModelHelperTest.kt`.

## Update 1.8.2 ([1.8.2] - 2026-11-15)
#### Fixes
- Added `isAiCoreKnownUnavailable` / `isAiCoreAvailable` checks on `AIEngine` handling lowercase `"unavailable"`, `available: false`, `statusCode: 0`, and `modelDownloadLog` AICore errors.
- Stopped `lateProgressCheck()` and `lateNetCheck()` from endlessly looping and re-triggering `checkEngine()` every 15 seconds on unsupported devices (including Play Console Pre-Launch Report emulators).
- Suppressed duplicate `"Gemini Nano is unavailable"` toasts during first-launch onboarding, limited post-onboarding unavailable toasts to once per session, and wrapped `Fluttertoast.showToast` calls so headless tests never throw `MissingPluginException`.
- Added fail-fast unavailable handling in `generateStream()` and `initEngine()` so chat generation cleanly reports `isError = true` and a clear status without spinning or crashing.
- Fixed Play Pre-Launch & Broken Functionality (`26111304`) startup/responsiveness hangs: made `AppConfig.initFromHive()` remote config fetching non-blocking, added explicit timeouts to Firebase/plugin startup calls (`main.dart`, `AnalyticsService`, `AIEngine.start()`), and capped recursive `1-DOWNLOAD_ERROR` retries (`maxDownloadErrorRetries = 2`).
- Fixed responsive layout and narrow-viewport (`320x480` / `360x640`) scroll issues in `elements.dart` (removed `physicalSize` / hardcoded pixel offsets and added `Expanded`, `Flexible`, and `IntrinsicHeight`) and `chat.dart` (bounded status banner with `ConstrainedBox` and scrollable banner content so the chatlog never gets squished).
- Fixed Assistant Overlay (`MeshOverlayActivity`, `PaiosVoiceInteractionService`, `PaiosModelHelper`) `[ErrorCode 4]` (`REQUEST_PROCESSING_ERROR`) failures: stripped status bar, navigation bar, and display cutout insets from passive OS screenshots, filtered `com.android.systemui` from `AssistStructure`, prevented passive screenshots from latching across turns in `activeSessionBitmap`, kept user `TextPart` clean by moving history/context out, aligned `enableThinking`/`maxTokens` with `ChatPage`, and added automatic multi-tier `[POLICY FALLBACK RETRY]` recovery.
- Added regression test coverage: `test/viewport_scroll_test.dart` (10 narrow-viewport tests), `PaiosModelHelperTest.kt` (8 JVM unit tests), and startup timeout / retry cap tests in `test/unsupported_device_test.dart`.

## Update 1.8.1 ([1.8.1] - 2026-11-15)
#### Fixes
- Fixed UTF-8/Windows-1251 mojibake characters in English translations and GitHub Explorer metadata labels.
- Shortened the `Preview` channel segment label to prevent ellipsis truncation across all 5 languages, localized `Downloadable`/`Downloading` version status fallbacks, and disabled unavailable `Fast`/`Full` segments per channel with explanatory notes and clean config syncing.
- Updated tool prompt instructions (`"args": {}` for parameterless tools), fixed `Prompt.generateContinuation` JSON draft detection (`"tool"` + `"args"`), hid plain-fenced streaming tool drafts (` ```\n{...`), corrected `Candidate.FinishReason` constants (`STOP=0`, `MAX_TOKENS=1`, `OTHER=-100`), and hid the `"Continuing response…"` chip as soon as continuation streaming produces thoughts or text.
- Converted internal/Wikipedia tool payloads into clean human-readable notes before synthesis and added anti-echo Markdown instructions so raw JSON keys like `found`, `title`, `description`, `extract`, and `url` are never echoed verbatim.

## Update 1.8.0 ([1.8.0] - 2026-11-15)
#### Changes
- Added AICore Model Config Switcher in Model Parameters (`Stable` vs `Preview (Nano v4 Beta)` release channel and `Full` vs `Fast` preference), live capability badges, fallback notices, and one-tap preview model download.
- Added Thinking Mode support with persisted toggle on Nano v2/v3 (auto-enabled and locked on when Gemini Nano v4 is active) and per-turn `thoughtProcess` persistence in chat history.
- Added collapsible Material 3 "Thought process" / "Thinking..." bubbles above assistant replies for both live thought streaming and completed turns across all 5 languages.

## Update 1.7.0 ([1.7.0] - 2026-11-15)
#### Changes
- Added modular built-in extensions: offline PAIOS documentation and battery status tools, plus opt-in online Wikipedia, DuckDuckGo search, and Open-Meteo weather forecast tools (online modules are off by default for privacy and fail gracefully when offline).
- Added a "PAIOS Built-in Extensions" section in Extensions Settings with per-module toggles, tool schema inspection, and "Online" badges, translated across all 5 languages.
- Added background post-turn visual memory caching so attached images are summarized automatically after the first reply.
- Streamlined system prompt resetting and removed legacy prompt assets.

## Update 1.6.2 ([1.6.2] - 2026-11-15)
#### Changes
- Tool call cards in both the main chat and assistant overlay now appear immediately as soon as a tool response starts streaming, showing a localized "Selecting a tool..." label and concise 2–4 word titles.
- Updated assistant overlay prompting so casual greetings get a warm reply without triggering unnecessary tools.
#### Fixes
- Fixed an AICore crash caused by requesting more than the 256-token output limit.

## Update 1.6.1 ([1.6.1] - 2026-11-15)
#### Changes
- Assistant overlay now uses the configured max-token budget and skips redundant background screenshots when opened directly inside PAIOS.
- Shortened external extension tool descriptions so enabled tools fit comfortably inside Gemini Nano's context window.
#### Fixes
- Prevented empty streaming chunks from wiping the "Thinking..." indicator in the assistant overlay, and added an automatic retry (plus clear fallback message) when a response comes back blank.

## Update 1.6.0 ([1.6.0] - 2026-11-14)
#### Changes
- Added a Take Photo camera button next to Gallery in the assistant overlay, with automatic EXIF orientation correction and temporary file cleanup.
- Streamlined the empty assistant overlay by removing the opening greeting card, tip banner, and visible screen-context chip while keeping screen context available when enabled in Android Assist settings.
- Improved vision isolation in the overlay so attaching a photo clears background screen context and prior visual memory, preventing earlier turns from bleeding into new photos.
- Brought assistant overlay prompts in line with the in-app chat (time/language context, persona placeholders, temperature setting, and respecting the Extensions toggle).

## Update 1.5.10 ([1.5.10] - 2026-11-13)
#### Changes
- Replaced remaining hardcoded app names, version fallbacks, and English-only strings in Extensions, Settings, and Onboarding with dynamic metadata and full 5-language localization.
#### Fixes
- Fixed stale GitHub and Play Store links pointing to the old `geminilocal` repository/package, and added the missing Alerts icon in extension proposals.

## Update 1.5.9 ([1.5.9] - 2026-11-13)
#### Fixes
- Improved tool result synthesis so Gemini Nano writes natural replies instead of echoing internal `[TOOL RESULT]` wrappers, with an automatic retry or clean summary fallback if output is empty or raw.
- Separated temporary tool parameter mistakes (allowing one self-correction retry) from unreachable/offline extension errors (disabling tools immediately and preventing hallucinated "everything looks normal" answers).

## Update 1.5.8 ([1.5.8] - 2026-11-13)
#### Fixes
- Fixed native stream cancellation and completion ordering so cancelled or failed generations never emit spurious completion events.
- Hardened JSON tool-call parsing and auto-continuation across both in-app chat and the assistant overlay, preventing broken JSON drafts from leaking into chat history.
- Eliminated cross-stream race conditions and tool-turn loops, and added an explicit unavailable-data notice when overlay extension calls fail.

## Update 1.5.7 ([1.5.7] - 2026-11-12)
#### Changes
- Added a dedicated Extensions Settings page with a master "Allow all new extensions" switch, per-app toggles, live tool schema inspection, and a "Works with PAIOS" discovery list.
- Enabled multi-turn tool chaining and pagination (up to 6 turns) while blocking disabled extensions from prompts and execution.
- Preserved attached/screenshot vision context across follow-up turns in the assistant overlay, and preserved the user's language during tool synthesis.
- Redesigned the onboarding mesh slide around private on-device IPC, sibling app cards, and permission controls across all 5 languages.
#### Fixes
- Added strict rules preventing tools like battery status from being called on visual or screenshot questions.

## Update 1.5.6 ([1.5.6] - 2026-11-12)
#### Changes
- Steered the default persona and tool rules so Gemini Nano identifies properly as the on-device assistant and avoids calling tools for general knowledge or casual conversation.
- Refined the documentation search tool description to target official ML Kit GenAI and AICore specs.
#### Fixes
- Fixed AI message bubble margins, rounded corners, and responsive max-width constraints so bubbles no longer clip against the left edge of the screen.

## Update 1.5.5 ([1.5.5] - 2026-11-12)
#### Changes
- Switched documentation syncing from HTML scraping to official Google `.md.txt` Markdown guides across all 23 ML Kit GenAI & AICore topics, with bundled offline copies, one-tap manual refresh, and "Open in Browser" links.
- Simplified tool call bubbles by removing the redundant "Complete" badge.
- Enriched Android screen context extraction to capture focused controls, browser domains/links, and input hints for better on-screen assistance.
#### Fixes
- Fixed image caption alignment and compact-screen sizing inside chat bubbles.

## Update 1.5.4 ([1.5.4] - 2026-11-12)
#### Changes
- Added velocity-aware drag physics to the assistant overlay handle (expanding to full screen past 80% height while respecting the keyboard and system bars).
- Added on-device extension tool execution directly inside the assistant overlay.
- Expanded the offline and synced documentation hub to 23 ML Kit GenAI guides, and polished tool call bubbles with readable summaries and expandable payloads.
- Refined Settings (hiding "Set as Default Assistant" when already active, improving Play Store review prompts) and Onboarding (live model download status and filtered sibling app proposals).
#### Fixes
- Fixed runaway recursive auto-continuation loops and preserved the synthesis prompt across continued turns.
- Fixed message ordering around tool bubbles and a race condition that could save new chats under ID `0`.
- Stripped a stray UTF-8 BOM from English translations and filled in 163 missing keys across Ukrainian, German, Turkish, and Chinese.

## Update 1.5.3
#### Changes
- Upgraded the in-app documentation explorer to a 3-tier cache (bundled offline assets, disk cache, and non-blocking background refresh) covering 8 ML Kit GenAI guides.
- Added category selector tabs, sync status badges, section jump chips, and cross-page search, plus multi-page results in the documentation tool.

## Update 1.5.0
#### Changes
- Redesigned generation analytics into a single atomic completion event (`ai_generation_completed`) for accurate success rates, error breakdowns, latency, and token throughput.
- Added dual-branch onboarding: supported devices get privacy, diagnostics, default assistant setup, live model download progress, GitHub prompt sync, and mesh intro slides; unsupported devices get a compatibility check, copyable diagnostic report, and instant re-check.
- Added the in-app Google GenAI Documentation Explorer and local `query_aicore_documentation` assistant tool.
- Added Default Assistant status/setup, Google Play in-app review prompt, and a dependency viewer in Settings.

## Update 1.4.2
#### Changes
- Added full chat archiving: archive/unarchive chats (except pinned chats), an expandable "Archived" section in the chat list, a dedicated Archived Chats page, and an auto-archive toggle for assistant overlay sessions.
- Added a symmetrical "Open in Full App" button in the assistant overlay to continue the conversation in the main app.
- Anchored the assistant overlay drag handle to the keyboard and navigation bar so dragging stretches the sheet smoothly, and injected the active persona prompt into overlay replies.
#### Fixes
- Fixed cross-session leaks in the assistant overlay so screenshots, snippets, and visual memory are strictly reset per session with a short freshness timeout.

## Update 1.4.1
#### Changes
- Switched inter-app extension discovery to query all installed compatible apps dynamically without hardcoded package names.
#### Fixes
- Updated Android DataStore dependencies to fix 16 KB memory page-size alignment warnings and crashes on Android 15/16 devices like Pixel 9 Pro.

## Update 1.4.0
#### Changes
- Overhauled the Android assistant overlay: removed background dimming and clutter pills, added 28dp rounded corners, smooth 1:1 drag-to-expand/dismiss physics, and proper keyboard/navigation inset handling.
- Added rotating localized persona greetings across all 5 languages, Material You (Monet) dynamic colors, compact image attachment chips with multi-turn visual memory, and a 1x1 headless mode for background tasks.
- Removed outdated "Tensor TPU" references across code and translations.
#### Fixes
- Removed a 750ms timer that could prematurely dismiss the assistant overlay before user interaction.

## Update 1.3.0
#### Changes
- Added on-device multimodal image attachments to chat: photo picker button, preview bar, rounded image thumbnails inside message bubbles, tap-to-zoom viewer, and persistent local image storage that cleans up on chat deletion.
- Added a Fast Vision Downsampling (768px) toggle and an Inter-App Agentic Mesh toggle in Settings (localized in all 5 languages), and extended `query_local_ai` to accept image inputs.

## Update 1.2.14
#### Changes
- Replaced hardcoded app queries with dynamic discovery of installed mesh tools.
#### Fixes
- Added 16 KB page-size alignment fix for Android DataStore on Android 15/16 and Pixel 9 Pro.

## Update 1.2.13
#### Fixes
- Configured the assistant overlay as a non-focusable, non-modal floating window so background apps can keep scrolling smoothly during AI inference.

## Update 1.2.12
#### Changes
- Exposed pill styling constants for easier theming.
#### Fixes
- Enabled touch passthrough outside the floating status pill so underlying apps stay interactive.

## Update 1.2.9
#### Changes
- Added `<uses-feature android:name="android.hardware.npu" android:required="true" />` to require NPU hardware in the Android manifest.

## Update 1.2.7
#### Fixes
- Replaced the invalid AICore `<uses-library>` manifest tag with `<uses-feature android:name="android.hardware.npu" android:required="true" />`, fixing `INSTALL_FAILED_MISSING_SHARED_LIBRARY` installation failures on supported devices.

## Update 1.2.6
#### Changes
- Added a manifest `<uses-library>` declaration for Google AICore to restrict distribution to supported devices.

## Update 1.2.5
#### Changes
- Added the 3-card Material 3 Expressive Bento header to Settings (brand card, interactive version/changelog sheet, and connected modules inspector).
- Integrated `M3x.init()` to automatically read app identity, build date, and changelog content from bundled assets.

## Update 1.2.0 `OBT`
#### Changes
- Added inter-app agentic tool calling via `m3x_mesh` and Android `ContentProvider` IPC, enabling PAIOS to run local AI tools and discover tools from sibling apps (like PTK and 2048).
- Added the translucent bottom status pill overlay so background AI requests from other apps satisfy Google AICore's foreground requirement.
- Added an in-app GitHub Explorer (docs, issues, releases, and license info), AICore Beta track detection with quick access to Developer Settings, and directional scroll motion blur across pages.
- Replaced template tests with regression and widget tests.
#### Fixes
- Fixed self-deadlocks/ANRs on local tool calls, startup hangs when sibling apps are missing, and unprompted tool calling on casual greetings.
- Fixed duplicate streaming/history bubbles, chat list header filters, Intro page Material 3 theming, unsafe Markdown links, non-English locale fallback, and analyzer warnings.

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
