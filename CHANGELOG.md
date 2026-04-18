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
