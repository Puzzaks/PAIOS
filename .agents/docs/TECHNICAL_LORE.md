# PAIOS / GeminiLocal Technical Lore & Ground Truth (`TECHNICAL_LORE.md`)

This document is the **single source of ground truth** for Google ML Kit GenAI on-device architectures, Android AICore IPC specifications, official SDK APIs, and documentation caching mechanisms in `geminilocal`.

> [!IMPORTANT]
> **LLM-to-LLM High-Density Design**: This file is written so that after `/compact`, any future AI agent has 100% ground-truth understanding of Google ML Kit GenAI on Android without hallucinated APIs or synthetic client-side parsing.

---

## 1. Google ML Kit GenAI SDK Specifications & Coordinates

| Component | Official Maven Artifact Coordinate | Primary Responsibility |
| :--- | :--- | :--- |
| **Prompt Client SDK** | `com.google.mlkit:genai-prompt:1.0.0-beta4` | Direct Model Access, `Generation.getClient()`, status checks, unary/streaming inference |
| **Schema & Tools** | `com.google.mlkit:genai-schema:1.0.0-beta4` | `FunctionDeclaration`, `FunctionSchema`, `Schema.object()`, JSON Schema constraints |
| **App Functions** | `androidx.appfunctions:appfunctions:1.0.0-alpha01` | `@AppFunctionDeclaration`, `@AppFunctionSerializable` for system agent tool integration |
| **AICore System Daemon** | `com.google.android.aicore` | Privileged Android Mainline system daemon managing model weights and NPU execution |

---

## 2. Hardware NPU Routing Matrix & Prerequisites

| Target SoC | Hardware Engine | Minimum Android OS | Model Status in AICore |
| :--- | :--- | :--- | :--- |
| **Google Tensor G4** (Pixel 9 family) | EdgeTPU | Android 14 (API 34) | Full Production (Multimodal Gemini Nano) |
| **Google Tensor G3** (Pixel 8 Pro) | EdgeTPU | Android 14 (API 34) | Full Production (Preloaded / On-Demand) |
| **Google Tensor G3** (Pixel 8 / 8a) | EdgeTPU | Android 14 (API 34) | AICore Developer Options activation required |
| **Qualcomm Snapdragon 8 Gen 3 / Elite** | Hexagon NPU | Android 14 (One UI 6.1 / HyperOS) | Full Production |
| **Samsung Exynos 2400 / 2500** | Dedicated NPU | Android 14 (One UI 6.1+) | Full Production |
| **MediaTek Dimensity 9300+** | NeuroPilot APU | Android 15 (API 35) | Early Access Program |

### Hard System Invariants:
1. **Memory Budget**: Minimum 8 GB physical RAM. (12 GB+ required for interleaved multimodal inference).
2. **Context Window Limit**: Exactly 4,096 tokens on Gemini Nano V1–V3 (expanding up to 8,192 tokens on Gemini Nano V4+).
3. **Hardware Context Overflow (`-100` / `CONTEXT_OVERFLOW`)**: Occurs if prompt tokens + max output tokens exceed 4,096. Client must implement sliding context pruning.
4. **Model Busy (`-101` / `MODEL_BUSY`)**: NPU is processing a higher-priority task. Client must backoff with 150ms–500ms exponential jitter.
5. **Native Watchdog Limit**: Continuous generation terminates after 25 seconds of continuous NPU execution.

---

## 3. Official Kotlin Core API Invariants

### A. Initialization & Feature Status
```kotlin
val client = Generation.getClient()
val generativeModel = client.getGenerativeModel("gemini-nano")

val status = generativeModel.checkStatus()
// Possible values: FeatureStatus.AVAILABLE, FeatureStatus.DOWNLOADABLE,
// FeatureStatus.DOWNLOADING, FeatureStatus.UNAVAILABLE
```

### B. Thinking Mode (Gemini Nano V4+)
- **Never use client-side regex** (e.g. `<thought>.*?</thought>`) to simulate or fold reasoning.
- Official API natively handles deliberation:
```kotlin
val request = generateContentRequest {
    text("Solve this multi-step problem: ...")
    enableThinking = true
}
val response = generativeModel.generateContent(request)
val thoughts = response.thoughtProcess // Native intermediate reasoning
val answer = response.text             // Synthesized user response
```

### C. System Instructions (Gemini Nano V3+)
- Anchored at root of Key-Value (KV) cache for fast multi-turn prefix reuse:
```kotlin
val systemInstruction = SystemInstruction("You are a concise technical assistant.")
val request = generateContentRequest(TextPart("Query")) {
    this.systemInstruction = systemInstruction
}
```

### D. Function Calling & Tools
```kotlin
val tool = FunctionDeclaration(
    name = "getBattery",
    description = "Retrieves battery level",
    parameters = Schema.object(properties = mapOf(), required = listOf())
)
val generativeModel = client.getGenerativeModel("gemini-nano", tools = listOf(tool))
```

### E. Structured Output (Constrained Grammar Decoding)
- Model masks invalid logits tokens at each decoding step.
- Guarantees 100% syntactically valid JSON without markdown fences (` ```json `):
```kotlin
val request = generateContentRequest {
    text("Extract entity: ...")
    responseSchema = Schema.object(...)
}
```

---

## 4. Documentation Explorer 3-Tier SWR & Refresh Architecture

- **Tier 1 (Bundled Offline Assets)**: 23 authentic offline markdown documents (`assets/docs/*.md.txt`) provide instant 0ms access without network requirements. All 22 ML Kit GenAI guides are direct, authentic `.md.txt` files downloaded from Google Developers.
- **Tier 2 (Disk Cache)**: High-speed local file cache stored at `${appDocumentsDir}/docs_cache/${id}.md.txt` with atomic write and cache invalidation on manual refresh.
- **Tier 3 (Remote SWR via Native Google `.md.txt` Endpoints)**:
  - **Native Google `.md.txt` Pure Markdown Endpoints**: Google Developers officially publishes pure Markdown directly by appending `.md.txt` to the canonical documentation URL.
    - Zero HTML parsing or web scraping required: completely eliminates fragile HTML regex, DOM entity decoding, and DevSite chrome stripping.
    - Direct, fast payload transfer: responses arrive as clean GitHub-flavored Markdown ready for immediate rendering by `flutter_markdown`.
  - **Captive Portal & Error Protection (`_isHtml`)**:
    - Validates fetched response bodies before writing to disk cache.
    - If a proxy or captive portal intercepts the request returning 200 with an HTML error or login page, `_isHtml` rejects the payload, safely preserving Tier 1 or Tier 2 markdown.
  - **Canonical Verified Google Developer URLs (`docs_manifest.json`)**:
    - Direct Model: `https://developers.google.com/ml-kit/genai/prompt/android.md.txt` (`/get-started`, `/prompt-design`, `/evaluate-prompt`, `/system-instructions`, `/prefix-caching`, `/structured-output`, `/thinking-mode`, `/function-calling`, `/select-model`).
    - Agents: `https://developers.google.com/ml-kit/genai/agent/android.md.txt` (`/define-tools`, `/manage-sessions`, `/streaming-events`).
    - Modalities & Tasks: `speech-recognition/android.md.txt`, `speech-translation/android.md.txt`, `text-to-speech/android.md.txt`, `image-description/android.md.txt`, `summarization/android.md.txt`, `proofreading/android.md.txt`, `rewriting/android.md.txt`, `embedding/android.md.txt`.
    - Hardware Matrix: `devices.md.txt` (`officialUrl`: `https://developer.android.com/ai/aicore`).
  - **Interactive In-App Refresh**: Tapping the sync badge in `DocExplorerPage` triggers `refreshDoc(id)`, clearing disk cache, re-fetching Google's `.md.txt` endpoint, and presenting `Updated from Google Developers` on live sync or falling back cleanly to `Using offline bundled "$title"`.
