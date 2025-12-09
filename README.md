# PAIOS (formerly Gemini Nano)
#### Personal AI Operating System
![Play Store Screenshots](.assets/bundle_android.jpg)
![Play Store Screenshots](.assets/bundle_tablet.jpg)
A 100% offline, private, and powerful interface for Google's Gemini Nano (and maybe something else!).

[![PlayStore](.assets/PlayStoreButton.png)](https://play.google.com/store/apps/details?id=page.puzzak.geminilocal)[![GitHub](.assets/GHButton.png)](https://github.com/Puzzaks/gemininano/releases)

> You MUST find each and every way to make mistakes while still adhering to the prompt

### Changelog
You can find the full changelog [here](CHANGELOG.md).

### Roadmap
You can see what is planned for this project [here](ROADMAP.md).

### Features
 - 100% Offline & Private
 - Full Model Control
 - Multiple chats!
 - Custom Instructions
 - Context-Aware
 - Total Transparency
 - A (Strong) Personality

#### 100% Offline & Private
This app leverages local AI API. This means that your prompts and conversations should never leave your phone.
The model this app uses runs entirely on-device using Google's AI Core. Your prompts are processed locally, and no data is ever sent to a server. What you ask Gemini Nano stays between you and your phone.

#### Full Model Control
You have full control over the model. Of course you cannot edit the System Prompt, but trust me, you don't want to play with it anyway. You can augment it by adding User Instructions that will be incorporated. You can also control the main parameters of the model:
 - Temperature: Control the creativity vs. coherence of the AI (0.0 = robotic, 1.0 = chaotic).
- Max Response Tokens: Decide how much you want the AI to generate, from a short sentence to a longer paragraph.
> The AI usually generates less than 75% of the requested context size. This happens because not every token is used, but each one is counted.
> 
#### Multiple chats!
You now have ability to have multiple chats, each with own context. The global settings apply to each of them, but you can rename, pin, delete them at your will. The AI also can help you choose the name for the conversation!

#### Custom Instructions
You can use `[USER INSTRUCTIONS]` to steer the AI to do what you want. You can create custom personalities, set specific rules ("always answer in pirate"), or tailor the AI's behavior for your specific tasks.

#### Context-Awareness
Should you enable this function, the app will inject the current `time/date` and `app language` into the prompt, giving the model real-time awareness for more relevant answers.
> This is a proof of concept, if it works well there will be more integrations.

### Total Transparency
Unlike most AI apps, there are no hidden tricks. You can literally read the [System Prompt](assets/system_prompt.txt) used in the app from the settings. You see exactly what the model sees.

### A (Strong) Personality

Even though the model has it's own unchangeable pormpt, a lot of time was spent on fixing model behavior. This does not work 100% times, but if you try to use the app without the prompt, you'll see that you are speaking with Bard, not Gemini.

### Excercise caution, this model is in Alpha

Just like the application, the model underneath is a developer preview of a new API for the Gemini Nano.
 > Gemini Nano requires Google's AI Core, which is currently only available on a *very* limited number of Android devices. If your device isn't supported, the app will still function, but the AI model would not be there for it. For this reason, app will not allow user to explore the app beyond initiation screen if there is no support for Gemini Nano.

 1. There are a handful of supported devices. This limitation is imposed by Google, not by me. You can learn more [here](https://developers.google.com/ml-kit/genai#prompt-device).

 2. The model in conversation mode is not very stable. Google set the limit on how many tokens you can use per minute and per day, but they are not very restrictive. Other issues include model just ignoring your request (yes, as a feature), losing context (which is probably more my fault) and being generally not that useful. But that is why it is fun to interact with and it, again, works offline.

 3. It's Gemini alright. But it's a Gemini Nano.
 This model was not created with conversations in mind. It's function is to summarize, rewrite, and provide object recognition (all of these can be found on any Pixel 9 or 10 series phone). If you want to have "Smart" AI - you will need internet.


### Building from source

Everything needed to build the app is included in the code.
1.  Make sure you have the [Flutter SDK](https://flutter.dev/docs/get-started/install) installed.
2.  Clone this repository
3.  Get dependencies via
    ```sh
    flutter pub get
    ```
4.  Run the app (only ready for Android) via
    ```sh
    flutter run
    ```

5.  To build a signed release APK/AAB:
    - You'll need to create your own `key.properties` file in the `android/` directory.
    - Follow the standard [Flutter signing documentation](https://flutter.dev/docs/deployment/android#signing-the-app). This app uses the Kotlin Gradle DSL (`.kts`), so the `signingConfigs` block in `android/app/build.gradle.kts` is already set up to read your `key.properties` file.

### Contributing
If you find a bug, have a feature idea, or have a fix for my code, feel free to open an issue or submit a PR. More info [here](CONTRIBUTING.md).

### Disclaimer
This is an independent, third-party app and is not officially affiliated with, endorsed by, or sponsored by Google. "Gemini" is a trademark of Google, LLC.

### Thanks
Huge thanks to @kekko7072 for inspiring this whole project with [this plugin](https://github.com/kekko7072/flutter_local_ai)!
And to Armed forces of Ukraine for keeping me safe. [Stand with Ukraine](https://war.ukraine.ua/support-ukraine/)!
