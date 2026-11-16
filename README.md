<div align="center">
  <h1>PAIOS</h1>
  <h3>Personal AI Operating System</h3>
    A 100% offline, private, and powerful interface for Google's Gemini Nano
    <br>
    (and maybe something else!)
    <br>
  <!-- Badges -->
  <a href="https://github.com/Puzzaks/PAIOS/releases">
    <img src="https://img.shields.io/github/v/release/Puzzaks/PAIOS?style=flat-square" height="20" alt="Latest Release"></a>
  <a href="https://github.com/Puzzaks/PAIOS/blob/master/LICENSE">
    <img src="https://img.shields.io/github/license/Puzzaks/PAIOS?style=flat-square" height="20" alt="License"></a>
  <a href="https://youtu.be/iY3FBMTA15A?si=yvlWUuvsfuw4Tg4e&t=831">
    <img src="https://img.shields.io/badge/As_Featured_In-HowToMen-ff0000?style=for-the-badge&logo=youtube&logoColor=white" height="20" alt="Featured in HowToMen"/></a>
<br>
  <!-- Download Buttons -->
  <a href="https://play.google.com/store/apps/details?id=page.puzzak.paios">
    <img src=".assets/PlayStoreButton.png" alt="Get it on Google Play" />
  </a>
  <a href="https://github.com/Puzzaks/PAIOS/releases/latest">
    <img src=".assets/GHButton.png" alt="Download on GitHub" />
  </a>
<br>
  <!-- Screenshots -->
  <img src=".assets/bundle_android.jpg" width="100%" alt="Phone Screenshot" />
</div>

<br>

> You MUST find each and every way to make mistakes while still adhering to the prompt

---

### Features
- **100% Offline & Private by design**: Inference runs on-device with Gemini nano (`Google AI Core`). Prompts, chats, and attachments stay on your phone (optional online extensions are strictly opt-in and off by default).
- **On-Device Models, Multi-Model Manager & Thinking Mode**:
  - Switch between **Stable** (Currently `gemini-nano-v3`) and **Preview/Beta** (`gemini-nano-v4-full` / `v4-fast`) channels.
  - Download any model your device supports.
  - Thinking mode with Nano-v4.
  - Custom `[USER INSTRUCTIONS]` Markdown prompt import/export, per-chat temperature & max-token controls, optional time/language context, and auto-continuation for longer answers.
- **System Assistant Role, Vision & Screen Context**:
  - Set PAIOS as Android's Digital Assistant!
  - Capture photo or attach from the gallery (yes, it's been a year, it is finally done).
  - Intelligent ability to check out the screen context in assistant mode - when needed.
- **RAG, Agentism & Modular Extensions**:
  - Using IPC (already implemented in [PTK](https://github.com/Puzzaks/PTK), and upcoming `Air Raid Alerts`) supporting up to 6-turn tool chaining and per-app / per-module Extensions Settings.
  - Tool calls as bundled modules (Documentation, basic Device Info and screen resolver) and opt-in modules for online capabilities (Wikipedia, DuckDuckGo, Open-Meteo Weather).
- **M3 Expressive UI, Docs Explorer, 5 Languages and so much more**:
  - Custom UI package (TBD) that builds upon Material 3 eXpressive
  - 23-page GenAI/AICore Docs Explorer (bundled offline + live `.md.txt` sync + RAG tool)
  - Multilingual support - 5 languages (`EN / UK / ZH / DE / TR` - or you can add yours :) ),
  - GitHub issue and documentation viewer in-app
  - Changelog and package list viewer in-app
  - Transparent [System Prompt](assets/prompts/system_default.md) and prompt viewer in-app.

### Status, Requirements & Known Limits
Google AI Core / ML Kit GenAI Prompt API is now in **Beta**, powering `gemini-nano-v3` (Stable) and `gemini-nano-v4` (Preview/Beta) on-device.
- **Device & OS Requirements**: Requires **Android 14+ (`minSdk 34`)**, **8 GB+ RAM**, a **locked bootloader**, and Google AI Core across supported chipsets including **Pixel 8/9/10** (Tensor G3/G4+), **Samsung Galaxy S24/Z6/S25** (Snapdragon 8 Gen 3/Elite, Exynos 2400/2500), and devices powered by **MediaTek Dimensity 9300+**.
- **Model & Safety Behavior**: Native on-device limits (256-token output cap / 25s generation window) are mitigated by bounded auto-continuation and cutoff rescue, though compact on-device reasoning remains smaller than cloud LLMs (such as Gemini Pro/Ultra). AICore safety/policy filters trigger automatic `[POLICY FALLBACK RETRY]` or clean error states rather than an unrecoverable soft-lock.

### Nightly Builds & Testing
- **Google Group Tester Opt-In**: Opt in via [Google Group](https://groups.google.com/g/paios-nightlies) and then joining via [Play Store](https://play.google.com/apps/testing/page.puzzak.paios)
- **Google Play Open Testing**: Enroll on the app's [Google Play Store page](https://play.google.com/store/apps/details?id=page.puzzak.paios)
- **GitHub Nightly Prereleases**: [Puzzaks/PAIOS Releases](https://github.com/Puzzaks/PAIOS/releases)

### Resources
- **FAQ**: [Frequently Asked Questions](docs/FAQ.md)
- **Support & Help**: [Support Guide](.github/SUPPORT.md)
- **Changelog**: [Full history](CHANGELOG.md)
- **Roadmap**: [Future plans](ROADMAP.md)
- **Contributing & Translations**: [How to build and help](CONTRIBUTING.md)
- **Security**: [Security Policy](SECURITY.md)
- **Code of Conduct**: [Code of Conduct](CODE_OF_CONDUCT.md)

---

### Disclaimer
This is an independent, third-party app and is not officially affiliated with, endorsed by, or sponsored by Google. "Gemini" is a trademark of Google, LLC.

*Note: Versions prior to `1.1.2` used a legacy package ID and are no longer supported — see the [FAQ](docs/FAQ.md#14-why-do-older-versions-below-112-fail-to-work-or-update).*

### Credits
Huge thanks to @kekko7072 for inspiring this project with [this plugin](https://github.com/kekko7072/flutter_local_ai)!<br>
[Google Antigravity](https://antigravity.google/) for AI reviews and suggestions during development!<br>
And to Armed forces of Ukraine for keeping me safe. [Stand with Ukraine](https://war.ukraine.ua/support-ukraine/)!
