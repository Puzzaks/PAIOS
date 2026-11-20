# Project Roadmap
  - [ ] Planned/ indev change
  - [x] Implemented change
  - `~version` Upstream version of this change
  - `version` Downstream version of this change

---
## Phase 1 `AI Core - Basic` 13/16
 - [x] **Release** `1.0.0`
    - Text-only interface for the AI Core API (Gemini Nano / Flan T-5) implementation, Play Store and source release
 - [x] **UI and UX** `1.0.1`
    - Multi-chat application with finalized MD3 style and state control for model download
 - [x] **Basic features** `1.1.0`
    - Multichat, chat pinning, basic per-chat settings
 - [x] **Hotfixes and monitoring** `~1.1.1`, `~1.1.2`, `1.1.5`
    - Optional analytics and crash reporting, logging, issue fixes in UI and backend
 - [x] **Additional features** `~1.1.6`, `~1.1.7`
    - Per-chat personas, temperature and token limit settings, etc.
 - [x] **Generation extension** `~1.1.7`, `1.1.8`
    - Workaround for 25s response generation time that ends answers prematurely
 - [x] **AICore controls** `1.2.0`, `1.8.0`, `1.8.3`, `1.8.8`, `1.8.9`
    - Shipped Stable (`gemini-nano-v3`) & Preview/Beta (`gemini-nano-v4-full` / `fast`) switching, unified Multi-Model Manager & parallel background downloader, live capability badges, ML Kit GenAI `1.0.0-beta5` (`warmup()`, `PromptPrefix` caching, native multi-image `Content` `ImagePart`s, `countTokens`/`getTokenLimit`, `FunctionCall` streaming, `topK`/`seed`, non-deprecated `getAvailableFeatures()`), accurate `GenAiException.ErrorCode` classification (`BUSY (9)` vs `AICORE_INCOMPATIBLE (-101)` / `FEATURE_NOT_FOUND (606)`), and auto-continuation with mid-clause/contraction `STOP` cutoff rescue
 - [x] **Documentation in-app & 3-Tier SWR Multi-Page Explorer** `1.5.3`, `1.5.4`, `1.5.5`
    - In-app Google ML Kit GenAI & AICore 23-page comprehensive offline & SWR documentation hub (`DocExplorerPage`), authentic Google developer specifications (`com.google.mlkit:genai-prompt:1.0.0-beta4`), live Google DevSite HTML-to-Markdown SWR synchronization engine with fallback fetching, canonical Google developer URL routing, cross-page term-frequency search engine, and `query_aicore_documentation` on-device RAG mesh tool
 - [x] **Dual-Branch Onboarding & SWR Remote Slides** `1.5.0`
    - PTK-style Material 3 onboarding wizard with animated pill indicators, device hardware validation, SWR remote slides from GitHub, assistant setup, and troubleshooting dashboard
 - [ ] **Contributions and open-source licenses**
    - *Partial (`1.5.0`)*: Dependency & license viewer shipped in Settings; dedicated contributor attribution credits still planned
 - [x] **Change in storage and updates** `~1.1.6`, `~1.1.8`
    - Use Firebase Remote Config for delivering data updates and storage instead of GitHub, move to a real DB instead of shared prefs
    - It would look like Remote Config would not work for collaboration (prompts and translations) so only the *config* part will move there
 - [x] **GitHub issue and update browser** `1.2.0`
    - A neat dashboard of contributions and issue list from this repo, in-app
 - [x] **Master Prompt selector and editor** `~1.1.6`, `~1.1.7`, `~1.1.8`
    - Collection of different Master Prompts and ability to create own ones
 - [x] **Master Prompt fixes** `1.2.0`, `1.8.8`
    - Slimmed default system prompt (`system_default.md`) to a 2-sentence baseline refreshed from bundled assets, moving PAIOS self-knowledge to on-demand `query_aicore_documentation` RAG lookup for consistent tool/chat behavior and maximum token headroom
 - [ ] **Monetization**
    - Monetize the project to allocate more time to the project
 - [ ] **Finalization**
    - Polishing and fixing issues, supporting users and optimisations


## Phase 2 `AI Core - Improved` 11/13
 - [x] **Agentism** `1.2.0`
    - Add agentic and RAG capabilities to the model with tool use loops, tool usage protocol
 - [ ] **Context expansion**
    - Find a way to allow model to use more data simultaneously, without overflowing the context window
 - [x] **Multimodality** `1.3.0`
    - Add image recognition that is supported by Gemini Nano
 - [x] **System Assistant & Multi-Turn Overlay** `1.4.0`
    - Distraction-free Material You (Monet) dynamic assistant bubble, rotating persona greetings, zero-flicker IME insets, smooth gestures, multi-turn visual context memory, and headless Mode C.
 - [x] **Assistant Session Isolation, Persona Injection & Chat Archive** `1.4.2`
    - Hotkey assist session isolation with 1500ms TTL, active persona system prompt injection, anchored bottom stretching drag handle, symmetrical "Open in Full App" header button, and complete Chat Archive & auto-archive ecosystem.
 - [x] **Dual-Branch Onboarding & Atomic Telemetry** `1.5.0`
    - Hardware-aware dual-branch onboarding (`IntroPage`), unskewed atomic Google Analytics generation telemetry (`generation_count: 1`), and Default Assistant system integration.
 - [x] **Assistant Overlay Expansion, Mesh Tool Loop & Synthesis Recovery** `1.5.4`
    - Full-screen fill drag physics, autonomous mesh tool execution and synthesis loop, bubble UX polish, Chat ID "0" persistence race resolution, and onboarding & settings refinements.
 - [x] **Modular Extensions & Built-in/Online Tools** `1.5.7`, `1.7.0`, `1.8.6`
    - Dedicated Extensions Settings (`Allow all new extensions`, per-app & per-module toggles, live schema inspector), 6-turn tool chaining, built-in offline modules (**AICore Docs**, **Device & Battery**), opt-in online modules (**Wikipedia**, **DuckDuckGo**, **Open-Meteo Weather**), and synchronized `toolRegistry` filtering.
 - [x] **Nano v4, Thinking Mode & Multi-Model Downloader** `1.8.0`, `1.8.3`
    - `Stable` (`gemini-nano-v3`) & `Preview` (`gemini-nano-v4-full` / `fast`) model switcher, live capability badges, collapsible streaming `ChatThoughtsBlock`, and decoupled parallel background downloader with speed (`B/s`–`GB/s`) & remaining-bytes progress.
 - [x] **Overlay Camera & On-Demand `inspect_screen` (3-Turn TTL)** `1.6.0`, `1.8.5`, `1.8.6`
    - Assistant overlay `Take Photo` camera capture with EXIF orientation fix, 768px fast vision downsampling + background visual memory, and lazy `inspect_screen` tool (`3`-turn TTL) replacing passive auto-attached screenshots.
 - [x] **`m3x_chat` UI, Cutoff Rescue & Cancel Hardening** `1.8.3`, `1.8.4`, `1.8.5`, `1.8.6`, `1.8.7`, `1.8.8`, `1.8.9`
    - Standardized `m3x_chat` shrink-wrap bubbles with author attribution & tap-to-reveal timestamps, auto-continuation + mid-clause/contraction `STOP` rescue, 240-char overlap + earlier-sentence loop deduplication, `trimTrailingIncompleteSentence` (including unpunctuated multi-sentence cutoff trimming), token-budgeted sliding window, stutter guard, tool JSON repair/fallback, and stream cancel lifecycle hardening.
 - [x] **Nightly CI/CD & Release Automation** `1.8.3`
    - Hardened `build_releases.ps1` (`-ApkOnly` / `-AabOnly`) and `publish_nightly.ps1` (`dev` branch push, GitHub Nightly Prereleases, Google Play Internal Testing upload).
 - [ ] **Ephemeral Context**
    - Implementing a "Short-Term Memory" buffer for heavy data (files/logs) that doesn't pollute the long-term chat history.

## Phase 3 `Model-agnosticizm` 0/4
 - [ ] **Custom models**
    - Allow users to set up and run custom models (like Gemma 2B) besides Gemini Nano for redundancy
 - [ ] **Connectivity**
    - Create a companion app that allows bigger models to run in other environment to connect the *PAIOS* to better hardware (prolly via Ollama)
    - This has to be made in a way that allows even users who are not tech-savvy to just install the model and run it
 - [ ] **Failover**
    - Auto-switch to local model if the remote connection drops.
 - [ ] **Voice Assistant & Voice Confirmation (`M3x Mesh` Companion: PAIOS Voice)**
    - Planned standalone **PAIOS Voice (`TinyASR` + TTS)** companion M3x Extension app (`android.speech.RecognitionService` + `TextToSpeech` + offline Live Voice loop over `M3xMesh`), split out as a standalone extension APK so PAIOS stays dependency-light.

## Phase 4 `PAIOS` 0/∞
 - [ ] **File System Access**
    - Read access to files on the device, in the network or online for more capabilities
 - [ ] **Scripting**
    - Allow the AI to use scripts to interact with other devices and use better tools like smart home integration
 - [ ] **Extensions "market"**
    - Create a way for users to create extensions and publish them for other users to use
 - [ ] **Voice chat**
    - Real-time, low-latency voice interaction (running locally). Possibly, ability to join chats on social media apps or act on behalf of user
 - [ ] **And much, much more**

## Phase 4.5 `Context Compacting & Local RAG` 0/2
 - [ ] **Context Compacting via On-Device Summarization API (`genai-summarization`)**
    - Integrate Android AICore On-Device Summarization API to automatically compact long conversation histories when approaching token boundaries without losing key conversational facts or user instructions.
 - [ ] **Markdown Transcript Local RAG**
    - Local in-memory retrieval-augmented generation (RAG) over exported `.md` conversation transcripts and project notes, allowing Gemini Nano to reference past chats and offline knowledge bases.

## Phase 4.6 `Google ML Kit GenAI Suite Integration` 0/3
 - [ ] **On-Device Neural Speech-to-Text (STT)**
    - Real-time on-device voice transcription allowing hands-free prompt input without external cloud API roundtrips.
 - [ ] **On-Device Neural Text-to-Speech (TTS)**
    - Expressive, low-latency spoken conversational assistant audio responses synthesized entirely on-device.
 - [ ] **Feature Support Dashboard**
    - *Partial (`1.5.0`, `1.8.0`, `1.8.3`)*: Device hardware validation & live Nano v3/v4 capability badges (`System Prompt`, `Thinking Mode`, `Prefix Caching`) shipped in Onboarding & Model Parameters; full NPU/TPU matrix dashboard across devices and Android versions still planned.

## Phase 4.7 `Cloud Model Escalation & Handoff` 0/1
 - [ ] **Google Gemini Cloud Handoff ("I know a guy...") via `ACTION_SEND` intent**
    - Seamless one-tap escalation path from local Gemini Nano to cloud-based Gemini (Pro / Ultra / Flash) via standard Android `ACTION_SEND` intent sharing.
    - Packages active conversation context, attached imagery, and failure explanation so complex multi-step reasoning can continue in cloud environments when on-device parameters are exceeded.
