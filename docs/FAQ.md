# Frequently Asked Questions (FAQ)

Everything you need to know about **PAIOS** (Personal AI Operating System): Assistant Mode, screen context, on-device privacy, M3x Mesh cross-app tools, camera/image attachments, and known limits. For an overview and downloads, see the [README](../README.md).

## Table of Contents

- [Assistant Mode and Screen Context](#assistant-mode-and-screen-context)
  - [1. How does Assistant Mode screen context work?](#1-how-does-assistant-mode-screen-context-work)
  - [2. How does PAIOS decide when to ignore screen context?](#2-how-does-paios-decide-when-to-ignore-screen-context)
  - [3. How do I turn off screen context?](#3-how-do-i-turn-off-screen-context)
- [Privacy and On-Device Gemini Nano](#privacy-and-on-device-gemini-nano)
  - [4. Does PAIOS send any data to external servers?](#4-does-paios-send-any-data-to-external-servers)
  - [5. Why does PAIOS refuse system or network commands (like `ping`) and external web access?](#5-why-does-paios-refuse-system-or-network-commands-like-ping-and-external-web-access)
  - [6. Where are my chats and settings stored?](#6-where-are-my-chats-and-settings-stored)
- [Mesh Tools and Cross-App Integration](#mesh-tools-and-cross-app-integration)
  - [7. What is M3x Mesh and how do Extensions work?](#7-what-is-m3x-mesh-and-how-do-extensions-work)
  - [8. How do I enable, disable, or inspect connected extensions?](#8-how-do-i-enable-disable-or-inspect-connected-extensions)
- [Camera and Image Attachments](#camera-and-image-attachments)
  - [9. How do Camera and Gallery attachments work in the Assistant overlay?](#9-how-do-camera-and-gallery-attachments-work-in-the-assistant-overlay)
  - [10. Why does attaching a photo replace the background screen capture?](#10-why-does-attaching-a-photo-replace-the-background-screen-capture)
  - [11. Does the Assistant overlay remember my attached photo on follow-up questions?](#11-does-the-assistant-overlay-remember-my-attached-photo-on-follow-up-questions)
- [Troubleshooting and Known Limits](#troubleshooting-and-known-limits)
  - [12. Why does PAIOS say my device or AI Core is unsupported?](#12-why-does-paios-say-my-device-or-ai-core-is-unsupported)
  - [13. Why are answers short, cut off, or less detailed than cloud LLMs?](#13-why-are-answers-short-cut-off-or-less-detailed-than-cloud-llms)
  - [14. Why do older versions (below 1.1.2) fail to work or update?](#14-why-do-older-versions-below-112-fail-to-work-or-update)
  - [15. Where can I report a bug or request a feature?](#15-where-can-i-report-a-bug-or-request-a-feature)
- [More Resources](#more-resources)

---

## Assistant Mode and Screen Context

### 1. How does Assistant Mode screen context work?
When PAIOS is set as Android's **Default digital assistant app**, summoning the Assistant overlay allows Android to automatically provide passive screen context from what is behind the sheet:
- **Screen capture (`Use screenshot`)**: A snapshot of the visible screen (gated on Android's `assist_screenshot_enabled` setting).
- **On-screen text (`AssistStructure`)**: Structured text extracted from the foreground app's UI hierarchy (gated on Android's `assist_structure_enabled` setting).

PAIOS picks this up automatically and silently whenever those Android Assist toggles are enabled—without cluttering the overlay with preview chips or *"Enable screenshot"* tooltips. When you open the Assistant overlay directly inside PAIOS itself, passive screen capture is skipped automatically unless you attach an image. Everything stays **100% on-device** and is processed locally by Gemini Nano via Google AI Core.

### 2. How does PAIOS decide when to ignore screen context?
Passive screen captures and foreground app telemetry are **not** treated as your main question. PAIOS explicitly frames them as **optional background context** (`[OPTIONAL BACKGROUND SCREEN & APP CONTEXT — USE ONLY IF USER ASKS]`).

- **Used** only when you explicitly ask about what is visible on your screen or inside the open app (e.g., *"Summarize this page"* or *"What does this error mean?"*).
- **Ignored** for unrelated prompts—including general knowledge questions, **M3x Mesh** tool queries (such as Alerts, Battery, or PTK StatusPages), unsupported commands, or questions about a photo you attached—so whatever was open behind the overlay won't hijack your answer.

### 3. How do I turn off screen context?
If you prefer zero passive screen capture or text reading while still using the Assistant overlay:

1. Open Android **Settings**.
2. Go to **Apps** -> **Default apps** -> **Digital assistant app**.
3. Open the assistant settings (tap the **gear icon** or **Digital assistant app**, depending on your device) and toggle off **Use screenshot** and/or **Use text from screen** (`AssistStructure`).

Once disabled, Android stops sending screen captures and UI text to PAIOS. You can still attach images manually anytime using the **Gallery** or **Camera** buttons in the overlay.

---

## Privacy and On-Device Gemini Nano

### 4. Does PAIOS send any data to external servers?
No prompt text, screenshot, camera photo, or conversation history is sent to cloud AI servers. Inference runs locally on your device through **Google AI Core** (`Gemini Nano`).

The only optional network activity in PAIOS is strictly non-conversational:
- Fetching updated app translations or remote documentation/onboarding slides (with bundled offline fallbacks).
- Optional anonymous analytics/crash reporting if enabled.

### 5. Why does PAIOS refuse system or network commands (like `ping`) and external web access?
PAIOS is built around a **100% offline, on-device privacy architecture**:
- **No internet access**: Gemini Nano runs locally on your phone via Google AI Core and cannot browse the web, fetch live URLs, or reach external servers.
- **No shell or OS command execution**: PAIOS cannot run terminal/network utilities like `ping` or access arbitrary system internals.
- **Actions via M3x Mesh tools only**: Live actions and device/app integrations only run through explicit **M3x Mesh** tools exposed by compatible apps (managed in `Settings` -> `Extensions`).

When a request requires an unsupported OS command, external network access, or a tool that isn't installed, PAIOS refuses honestly rather than fabricating output.

### 6. Where are my chats and settings stored?
Conversations, personas, and preferences are stored locally on your device (via Hive and Android `SharedPreferences` under `page.puzzak.paios`). Because local storage relies on standard Android app sandboxing, keep your device secured (see the [Security Policy](../SECURITY.md) for details and vulnerability reporting).

---

## Mesh Tools and Cross-App Integration

### 7. What is M3x Mesh and how do Extensions work?
**M3x Mesh** is an on-device Android IPC layer (`ContentProvider`-based `*.mesh` endpoints) that lets PAIOS discover and call tools exposed by compatible apps locally—with zero cloud relays.

Compatible apps in the ecosystem include:
- **PAIOS built-in tools**: On-device helpers such as battery status and the offline/SWR AI Core documentation search (`query_aicore_documentation`).
- **PTK (Puzzak's ToolKit)** (`page.puzzak.ptk`): Server telemetry, Statuspage incident monitoring, and TCP ping diagnostics.
- **Alerts** (`page.puzzak.alerts`): Ukraine air raid alerts and map status.

PAIOS supports multi-turn tool chaining (up to 6 chained tool calls per turn) and suppresses raw JSON flicker with clean tool-status indicators while a tool is being selected or executed. If an extension is disabled, timed out, or unavailable, PAIOS reports the failure honestly instead of inventing live data.

### 8. How do I enable, disable, or inspect connected extensions?
Open **Settings** -> **Extensions** inside PAIOS:
- **First-party extensions** (`page.puzzak.*`, `com.puzzak.*`) are enabled by default.
- **Third-party extensions** are disabled by default unless you enable them individually or turn on the **"Allow all new extensions"** master switch.
- Tap any connected extension to open its schema inspector and view its package ID, live status, exposed tools, and parameter schemas. Disabled extensions are excluded from prompts sent to Gemini Nano and blocked at execution time.

---

## Camera and Image Attachments

### 9. How do Camera and Gallery attachments work in the Assistant overlay?
In the Assistant overlay input bar, you can attach visuals using:
- **Gallery**: Pick one or more existing images from your device.
- **Camera (`Take Photo`)**: Launch Android's system camera (`ACTION_IMAGE_CAPTURE`) via a secure `FileProvider` cache file—without requiring PAIOS itself to hold the `CAMERA` runtime permission. Captured images are automatically EXIF-orientation corrected and temporary cache files are cleaned up after processing.

### 10. Why does attaching a photo replace the background screen capture?
When you pick an image from **Gallery** or take one with **Camera** inside the Assistant sheet, PAIOS automatically drops the passive background screenshot (and clears prior visual turn memory).

Multiple images in a single prompt are stitched vertically into one composite image (and optionally downsampled), which means keeping the background screenshot would split **Gemini Nano's** vision resolution budget between your photo and an unrelated screen capture. Dropping the passive screenshot guarantees **100% of the vision resolution budget** is dedicated to your photo.

### 11. Does the Assistant overlay remember my attached photo on follow-up questions?
Yes. Within an active Assistant overlay session, your attached image remains active across text-only follow-up questions so you can ask multiple questions about the same photo without re-attaching it. Closing or resetting the overlay session, removing the attachment, or attaching a new photo clears the previous visual memory.

---

## Troubleshooting and Known Limits

### 12. Why does PAIOS say my device or AI Core is unsupported?
PAIOS is a client for **Google AI Core / ML Kit GenAI (`Gemini Nano`)**:
- **Device & OS support**: Your device must be on Google's [supported devices list](https://developers.google.com/ml-kit/genai#prompt-device) with Google AI Core installed and up to date.
- **Bootloader state**: Google AI Core requires a **locked bootloader** and valid device attestation on stock builds; unlocked bootloaders typically cause AI Core to report the model as unavailable.
- **Model download**: On supported devices, Gemini Nano weights are managed and downloaded by Google AI Core in the background. You can check status and troubleshooting details in the onboarding wizard or in-app AI Core documentation.

### 13. Why are answers short, cut off, or less detailed than cloud LLMs?
Gemini Nano is a compact on-device model designed for privacy, speed, and battery efficiency—not a massive cloud model like Gemini Pro/Ultra or GPT-4:
- **Output token cap**: Google AI Core enforces a per-generation `maxOutputTokens` ceiling of **1–256 tokens** (`Settings` -> `Model parameters` -> `Max response tokens`). Long answers may require using the continuation feature.
- **Hallucinations & context window**: Complex multi-step reasoning or long chat histories can exceed the on-device context window. Try starting a new chat or keeping custom instructions concise.
- **Safety filters**: Profanity or slurs can trigger AI Core's built-in safety filters; if auto-retry is enabled, repeated filter hits can stall generation.

### 14. Why do older versions (below 1.1.2) fail to work or update?
Starting with `1.1.2`, PAIOS moved to the `page.puzzak.paios` package ID on Google Play and GitHub Releases. Versions older than `1.1.2` are deprecated and no longer supported. Install the latest release from [Google Play](https://play.google.com/store/apps/details?id=page.puzzak.paios) or [GitHub Releases](https://github.com/Puzzaks/PAIOS/releases/latest).

### 15. Where can I report a bug or request a feature?
See our [Support Guide](../.github/SUPPORT.md) for quick routing, or open an issue at [Puzzaks/PAIOS Issues](https://github.com/Puzzaks/PAIOS/issues) with your **device model**, **Android version**, **PAIOS version**, and **bootloader/AI Core status**.

---

## More Resources
- **Overview**: [README](../README.md)
- **Support & Help Routing**: [Support Guide](../.github/SUPPORT.md)
- **Transparency**: [System Prompt](../assets/prompts/system_default.md)
- **Roadmap**: [Project Roadmap](../ROADMAP.md)
- **Security**: [Security Policy](../SECURITY.md)
- **Contributing & Bug Reports**: [Contributing Guide](../CONTRIBUTING.md) · [Puzzaks/PAIOS Issues](https://github.com/Puzzaks/PAIOS/issues)
