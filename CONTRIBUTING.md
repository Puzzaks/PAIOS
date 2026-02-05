# Contributing to PAIOS

Thank you for your interest in contributing! PAIOS is a Flutter application designed for local, private AI interaction. I welcome contributions that improve stability, add new features, or enhance the user experience.

## Quick Start

### Project Structure
To help you navigate the codebase, here are the key components:
- **Core Logic**: `lib/engine.dart` (`AIEngine`) is the central state management provider. It handles initialization, AI generation streams, and app-wide state.
- **AI Interaction**: `lib/parts/gemini.dart` wraps the raw API calls to the local model.
- **Prompt Engineering**: `lib/parts/prompt.dart` constructs the prompts sent to the model (system prompt + user history + context). The **Master Prompt** itself is located at `assets/system_prompt.txt`.
- **UI**: All screens are located in `lib/pages/`. `chat.dart` manages the individual chat interface.

### Running Locally
1.  **Prerequisites**: [Flutter SDK](https://flutter.dev/docs/get-started/install) installed.
2.  **Clone**: Clone the repository `git clone https://github.com/Puzzaks/gemininano.git`
3.  **Dependencies**: Run `flutter pub get` to install packages.
4.  **Run**: `flutter run` (Android is the only targeted platform).

## Helping with Translations
I need your help to make PAIOS available to everyone!
1.  **Navigate** to `assets/translations/`.
2.  **Create** a new file for your language code (e.g., `es.json` for Spanish), copying the structure from `en.json`.
    -   **Important**: The app determines the system language by splitting the locale code by `_` and using only the first part (e.g., `en_US` becomes `en`). Therefore, file names and IDs **MUST** use only the two-letter language code (e.g., `es`, `zh`, `fr`). Regional codes like `zh_tw` or `en_gb` will **NOT** be matched automatically.
    -   You are also technically "welcome" to submit a Russian translation (`ru`). Please do so if you want to give me the satisfaction of declining your PR immediately.
3.  **Translate** the values (leave keys unchanged).
4.  **Register** your new language in `assets/translations/languages.json`. Example:
    ```json
    {
      "origin": "Español",
      "name": "Spanish",
      "id": "es"
    }
    ```
5.  **Test** (optionally) by running the app and selecting the language in settings.
      - By default the app will use ONLY the offline translation files when compiled in debug mode and use translations from GitHub in release mode.
      - In release mode, if you don't have internet connection, the app will always use the offline translation files.
6.  **Submit** a pull request.
7.  **Availability**: Once PR is merged, your translation will be available to all users once GitHub's CDN propagates the changes (usually within an hour, but sometimes it can take up to 24 hours). The app downloads translations from GitHub on each restart.

## Submitting Changes

### Pull Requests
- **Focus**: Keep PRs focused on a single issue or feature.
- **Testing**: If you modify the engine, please ensure you test the "Happy Path" (sending a message, getting a response) on a supported device if possible.
- **Changelog**: The `CHANGELOG.md` will be updated with update notes after the release, I will do my best to include all the changes from the maintainers with due attribution.

### Issues
- **Bug Reports**: Please include your device model and Android version, as device support is the most critical factor for this app. Make sure that your device is in the [supported devices list](https://developers.google.com/ml-kit/genai#prompt-device) and is not rooted - this is a Google's AI Core requirement.
- **Feature Requests**: I love new ideas! Please check the [Roadmap](ROADMAP.md) to see if it's already planned.

Thank you for helping make local AI better!
