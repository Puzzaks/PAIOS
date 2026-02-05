<div align="center">
  <h1>PAIOS</h1>
  <h3>Personal AI Operating System</h3>
    A 100% offline, private, and powerful interface for Google's Gemini Nano
    <br>
    (and maybe something else!)
    <br>
  <!-- Badges -->
  <a href="https://github.com/Puzzaks/gemininano/releases">
    <img src="https://img.shields.io/github/v/release/Puzzaks/gemininano?style=flat-square" height="25" alt="Latest Release">
  </a>
  <a href="https://github.com/Puzzaks/gemininano/blob/master/LICENSE">
    <img src="https://img.shields.io/github/license/Puzzaks/gemininano?style=flat-square" height="25" alt="License">
  </a>
  <a href="https://youtu.be/iY3FBMTA15A?si=yvlWUuvsfuw4Tg4e&t=831">
    <img src="https://img.shields.io/badge/As_Featured_In-HowToMen-ff0000?style=for-the-badge&logo=youtube&logoColor=white" height="25" alt="Featured in HowToMen" />
  </a>

  > **Important**: Starting from the update 1.1.2, the app has different package name. Older versions are no longer working due to Play Store issue with previous package and it's listing. Sorry for the inconvenience!

  

  <!-- Download Buttons -->
  <a href="https://play.google.com/store/apps/details?id=page.puzzak.paios">
    <img src=".assets/PlayStoreButton.png" width="48%" alt="Get it on Google Play" />
  </a>
  &nbsp;
  <a href="https://github.com/Puzzaks/gemininano/releases/latest">
    <img src=".assets/GHButton.png" width="48%" alt="Download on GitHub" />
  </a>

  
  <!-- Screenshots -->
  <img src=".assets/bundle_android.jpg" width="100%" alt="Phone Screenshot" />
  <br>
  <img src=".assets/bundle_tablet.jpg" width="100%" alt="Tablet Screenshot" />
</div>

<br>

> You MUST find each and every way to make mistakes while still adhering to the prompt

---

### Features
 - **100% Offline & Private**: Runs entirely on-device using Google's AI Core. No data leaves your phone.
 - **Full Model Control**: Adjust Temperature and Max Response Tokens.
 - **Multiple Chats**: Create, rename, and pin multiple conversations with their own context.
 - **Custom Instructions**: Steer the AI with `[USER INSTRUCTIONS]` for specific personas or tasks.
 - **Context-Aware**: Optional injection of current time/date and app language.
 - **Transparency**: View the actual [System Prompt](assets/system_prompt.txt) used.

### Caveats (Alpha Status)
PAIOS acts as a client for the underlying Gemini Nano model, which is a developer preview.
- **Device Support**: Requires a supported device with Google AI Core (e.g., Pixel 9/10 series).
- **Model Behavior**: The model is optimized for on-device use (summarization, smart reply). While powerful for its size, do not expect the same reasoning or knowledge depth as cloud-based "big" LLMs (like Gemini Pro/Ultra or GPT-4). It may hallucinate or lose context.
- **Censorship**: Typing curses or slurs may soft-lock the app if auto-retry is enabled due to internal model filters.

### Resources
- **Changelog**: [Full history](CHANGELOG.md)
- **Roadmap**: [Future plans](ROADMAP.md)
- **Contributing & Translations**: [How to build and help](CONTRIBUTING.md)

---

### Disclaimer
This is an independent, third-party app and is not officially affiliated with, endorsed by, or sponsored by Google. "Gemini" is a trademark of Google, LLC.

### Credits
Huge thanks to @kekko7072 for inspiring this project with [this plugin](https://github.com/kekko7072/flutter_local_ai)!<br>
[Google Antigravity](https://antigravity.google/) for AI reviews and suggestions during development!<br>
And to Armed forces of Ukraine for keeping me safe. [Stand with Ukraine](https://war.ukraine.ua/support-ukraine/)!
