import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as md;
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geminilocal/pages/support/elements.dart';
import 'package:geminilocal/parts/prompt.dart';
import 'package:geminilocal/parts/translator.dart';
import 'parts/gemini.dart';

import 'package:geminilocal/storage/analytics_service.dart';
import 'package:geminilocal/storage/app_config.dart';
import 'package:geminilocal/storage/chat_repository.dart';
import 'package:geminilocal/storage/migration.dart';
import 'package:geminilocal/storage/prompt_repository.dart';
import 'package:geminilocal/storage/resource_repository.dart';

class AIEngine with md.ChangeNotifier {
  final gemini = GeminiNano();
  final prompt = md.TextEditingController();
  final instructions = md.TextEditingController();
  final chatName = md.TextEditingController();

  Dictionary dict = Dictionary(
    path: "assets/translations",
    url: "https://raw.githubusercontent.com/Puzzak/PAIOS-Dict/main",
  );
  Prompt promptEngine = Prompt(ghUrl: "https://github.com/Puzzak/PAIOS");
  AiResponse response = AiResponse(
    text: "Loading...",
    tokenCount: 1,
    chunk: "Loading...",
    generationTimeMs: 1,
    finishReason: "",
  );
  String responseText = "";
  bool isLoading = false;
  bool isAvailable = false;
  bool isInitialized = false;
  bool isInitializing = false;
  String status = "";
  bool isError = false;

  bool appStarted = false;
  String testPrompt = "";
  Map modelInfo = {};
  List modelDownloadLog = [];
  bool ignoreContext = false;
  bool isContinuing = false;
  String _lastFinishReason = ""; // captured from streaming events, read at done
  String _combinedResponse = ""; // accumulates across continuation calls
  String get combinedResponse => _combinedResponse; // read-only access for UI
  int _continuationCount = 0;    // how many continuations fired (for logging)
  // Cumulative generation stats across all continuation rounds (exposed to UI)
  int cumulativeGenerationMs = 0;
  int cumulativeTokenCount = 0;
  // Join-stitching state — resolved once per continuation round on first chunk
  bool _firstContinuationChunk = true;
  String _continuationJoinPrefix = "";  // space or newline to insert at join point
  bool _continuationLowerFirst = false; // lowercase the first char of continuation
  String _continuationStripPattern = ""; // regex to strip from start of cont text (e.g. duplicate code fence)

  md.ScrollController scroller = md.ScrollController();

  late final AppConfig config;
  late final ChatRepository chatData;
  late final AnalyticsService logger;
  late final PromptRepository promptData;
  late final ResourceRepository resourceData;

  AIEngine() {
    config = AppConfig(notifyEngine: genericRefresh);
    logger = AnalyticsService(notifyEngine: genericRefresh);
    promptData = PromptRepository(notifyEngine: genericRefresh, logEvent: logger.log);
    resourceData = ResourceRepository(notifyEngine: genericRefresh, logEvent: logger.log);
    chatData = ChatRepository(
      notifyEngine: genericRefresh,
      requestTitle: generateChatTitle,
      logEvent: logger.log,
      getDefaultPromptId: () => config.defaultPromptId,
    );
  }

  // Getters/Setters to maintain UI compatibility
  bool get firstLaunch => config.firstLaunch;
  int get tokens => config.tokens;
  set tokens(int value) => config.tokens = value;
  double get temperature => config.temperature;
  set temperature(double value) => config.temperature = value;
  int get usualModelSize => config.usualModelSize;
  bool get addCurrentTimeToRequests => config.addCurrentTimeToRequests;
  set addCurrentTimeToRequests(bool value) => config.addCurrentTimeToRequests = value;
  bool get shareLocale => config.shareLocale;
  set shareLocale(bool value) => config.shareLocale = value;
  bool get errorRetry => config.errorRetry;
  set errorRetry(bool value) => config.errorRetry = value;
  bool get ignoreInstructions => config.ignoreInstructions;
  set ignoreInstructions(bool value) => config.ignoreInstructions = value;

  Map get chats => chatData.chats;
  String get currentChat => chatData.currentChat;
  set currentChat(String value) => chatData.currentChat = value;
  List get context => chatData.context;
  set context(List value) => chatData.context = value;
  int get contextSize => chatData.contextSize;
  set contextSize(int value) => chatData.contextSize = value;
  String get lastPrompt => chatData.lastPrompt;
  set lastPrompt(String value) => chatData.lastPrompt = value;

  bool get analytics => logger.analyticsEnabled;
  set analytics(bool value) => logger.analyticsEnabled = value;
  bool get analyticsDone => logger.analyticsDone;
  List<Map> get logs => logger.logs;
  bool get isLoadingTitle => chatData.isLoadingTitle;
  
  List<Map<String, dynamic>> get logsList => logs.cast<Map<String, dynamic>>();

  /// Subscription to manage the active AI stream
  StreamSubscription<AiEvent>? _aiSubscription;

  late Cards cards;

  /// This junk is to update all pages in case we have a modal that is focused in which case setState will not update content underneath it
  void genericRefresh() {
    notifyListeners();
  }

  Future<void> endFirstLaunch() => config.endFirstLaunch();
  Future<void> saveSettings() => config.saveSettings(instructions.text);

  scrollChatlog(Duration speed) {
    scroller.animateTo(
      scroller.position.maxScrollExtent,
      duration: speed,
      curve: md.Curves.fastOutSlowIn,
    );
  }

  Future<void> startAnalytics() => logger.startAnalytics();
  Future<void> stopAnalytics() => logger.stopAnalytics();
  Future<void> log(String name, String type, String message) => logger.log(name, type, message);

  Future<void> start() async {
    await MigrationService.initiateMigration();
    await logger.initFromHive();
    await config.initFromHive();
    
    await log("init", "info", "Starting the app engine");
    await log("init", "info", "Starting the translations engine");
    dict = Dictionary(path: "assets/translations", url: "https://raw.githubusercontent.com/${config.repo}/main");
    await dict.setup(log: logger.log);
    await log("init", "info", "Checking Gemini Nano status");
    await checkEngine();
    await log("init", "info", "Initializing the Prompt engine");
    promptEngine = Prompt(ghUrl: "https://github.com/${config.repo}");
    await promptData.initFromHive("https://raw.githubusercontent.com/${config.repo}/main");
    await promptEngine.initialize();
    await log("init", "info", "Initializing the Resource repository");
    await resourceData.initFromHive("https://raw.githubusercontent.com/${config.repo}/main");
    
    await log(
      "init",
      "info",
      "Firebase analytics: ${analytics ? "Enabled" : "Disabled"}",
    );

    await chatData.initFromHive();
    await log(
      "init",
      "info",
      "Add DateTime to prompt: ${addCurrentTimeToRequests ? "Enabled" : "Disabled"}",
    );
    await log(
      "init",
      "info",
      "Add app locale to prompt: ${shareLocale ? "Enabled" : "Disabled"}",
    );
    await log(
      "init",
      "info",
      "Retry on error: ${errorRetry ? "Enabled" : "Disabled"}",
    );
    await log(
      "init",
      "info",
      "Ignore instructions: ${ignoreInstructions ? "Enabled" : "Disabled"}",
    );
    appStarted = true;
    await log("init", "info", "App initiation complete");
    notifyListeners();
  }

  void addDownloadLog(String log) {
    modelDownloadLog.add({
      "status": log.split("=")[0],
      "info": log.split("=")[1],
      "value": log.split("=")[2],
      "time": DateTime.now().millisecondsSinceEpoch,
    });
    notifyListeners();
  }

  lateNetCheck() async {
    while (firstLaunch) {
      final connectivityResult = await (Connectivity().checkConnectivity());
      if (!connectivityResult.contains(ConnectivityResult.wifi)) {
        if (modelDownloadLog.isNotEmpty) {
          if (!(modelDownloadLog[modelDownloadLog.length - 1]["info"] ==
              "waiting_network")) {
            if (modelDownloadLog[modelDownloadLog.length - 1]["info"] ==
                "downloading_model") {
              addDownloadLog(
                "Download=waiting_network=${modelDownloadLog[modelDownloadLog.length - 1]["value"]}",
              );
            }
          }
        }
      } else {
        if (modelDownloadLog.isNotEmpty) {
          if ((modelDownloadLog[modelDownloadLog.length - 1]["info"] ==
              "waiting_network")) {
            addDownloadLog(
              "Download=downloading_model=${modelDownloadLog[modelDownloadLog.length - 1]["value"]}",
            );
          }
        }
      }
      await Future.delayed(Duration(seconds: 2));
    }
  }

  String convertSize(int size, bool isSpeed) {
    if (size < 1024) {
      return '$size B${isSpeed ? "/s" : ""}';
    } else if (size < 10240) {
      double sizeKb = size / 1024;
      return '${sizeKb.toStringAsFixed(2)} KB${isSpeed ? "/s" : ""}';
    } else if (size < 1048576) {
      double sizeKb = size / 1024;
      return '${sizeKb.toStringAsFixed(1)} KB${isSpeed ? "/s" : ""}';
    } else if (size < 10485760) {
      double sizeMb = size / 1048576;
      return '${sizeMb.toStringAsFixed(2)} MB${isSpeed ? "/s" : ""}';
    } else if (size < 104857600) {
      double sizeMb = size / 1048576;
      return '${sizeMb.toStringAsFixed(1)} MB${isSpeed ? "/s" : ""}';
    } else if (size < 1073741824) {
      double sizeGb = size / 1073741824;
      return '${sizeGb.toStringAsFixed(2)} GB${isSpeed ? "/s" : ""}';
    } else if (size < 10737418240) {
      double sizeGb = size / 1073741824;
      return '${sizeGb.toStringAsFixed(1)} GB${isSpeed ? "/s" : ""}';
    } else {
      double sizeGb = size / 1073741824;
      return '${sizeGb.toInt()} GB${isSpeed ? "/s" : ""}';
    }
  }

  lateProgressCheck() async {
    Map lastUpdate = {};
    while (firstLaunch) {
      await Future.delayed(Duration(seconds: 15));
      if (lastUpdate == {}) {
        if (modelDownloadLog.isNotEmpty) {
          lastUpdate = modelDownloadLog[modelDownloadLog.length - 1];
        }
      }
      if (modelDownloadLog.isNotEmpty) {
        if (lastUpdate == modelDownloadLog[modelDownloadLog.length - 1]) {
          /// Nothing changed in the last 15 seconds, assume we have restarted and are not getting updates; We must restart the checkEngine. So...
          checkEngine();
          await log(
            "model",
            "warning",
            "Stopped getting model download events",
          );
        } else {
          lastUpdate = modelDownloadLog[modelDownloadLog.length - 1];
        }
      }
    }
  }

  Future<void> checkEngine() async {
    if (modelDownloadLog.isEmpty) {
      lateNetCheck();
      lateProgressCheck();
    }
    modelDownloadLog.clear();
    gemini.statusStream = gemini.downloadChannel.receiveBroadcastStream().map(
      (dynamic event) => event.toString(),
    );
    gemini.statusStream.listen(
      (String downloadStatus) async {
        switch (downloadStatus.split("=")[0]) {
          case "Available":
            modelInfo = await gemini.getModelInfo();
            if (modelInfo["version"] == null) {
              await log(
                "model",
                "warning",
                "Model version was not reported, trying again",
              );
              await Future.delayed(Duration(seconds: 2));
              checkEngine();
            } else {
              if (modelInfo["status"] == "Available") {
                addDownloadLog("Available=Available=0");
                await log("model", "info", "Model is ready");
                endFirstLaunch();
              } else {
                if (downloadStatus.split("=")[1] == "Download") {
                  if (!(modelDownloadLog[modelDownloadLog.length - 1]["info"] ==
                      "waiting_network")) {
                    addDownloadLog("Download=downloading_model=0");
                    await log("model", "info", "Downloading model");
                  }
                } else {
                  addDownloadLog(downloadStatus);
                }
              }
            }
            break;
          case "Download":
            if (modelDownloadLog.isEmpty) {
              addDownloadLog(downloadStatus);
            } else {
              if (!modelDownloadLog[modelDownloadLog.length - 1]["value"]
                  .contains("error")) {
                await log(
                  "model",
                  "info",
                  "Downloading, ${convertSize(int.parse(modelDownloadLog[modelDownloadLog.length - 1]["value"]), false)}",
                );
                if (int.parse(downloadStatus.split("=")[2]) >
                    int.parse(
                      modelDownloadLog[modelDownloadLog.length - 1]["value"],
                    )) {
                  addDownloadLog(downloadStatus);
                }
              }
            }
            break;
          case "Error":
            addDownloadLog(downloadStatus);
            await log("model", "error", downloadStatus.split("=")[2]);
            if (downloadStatus.split("=")[2].contains("1-DOWNLOAD_ERROR")) {
              checkEngine();
            } else {
              Fluttertoast.showToast(
                msg: "Gemini Nano ${dict.value("unavailable")}",
                toastLength: Toast.LENGTH_SHORT,
                fontSize: 16.0,
              );
            }
            break;
          default:
            addDownloadLog(downloadStatus);
        }
      },
      onError: (e) async {
        await log("model", "error", e);
        analyzeError("Received new status: ", e);
      },
      onDone: () {
        notifyListeners();
      },
    );
  }

  /// Saves the last exchange (user prompt + AI response) to Hive via ChatRepository.
  /// The response text lives on the engine; the repository handles everything else.
  Future<void> addToContext() async {
    await chatData.addToContext(responseText);
    responseText = "";
  }

  /// Persists the current in-memory chats map to Hive via ChatRepository.
  Future<void> saveChats() => chatData.saveChats();

  /// Removes a chat from Hive (no-op for sentinel IDs "0" / "testing").
  Future<void> deleteChat(String chatID) => chatData.deleteChat(chatID);


  Future<String> generateChatTitle(String input) async {
    ignoreContext = true;
    String newTitle = "";
    await log("model", "info", "Generating new chat title");
    await generateTitle("Task: Create a short, 3-5 word title for this conversation.\n"
        "Rules:\n"
        "1. DO NOT use full sentences.\n"
        "2. DO NOT use phrases like \"The conversation is about\" or \"Summary of\".\n"
        "3. Be extremely concise.\n"
        "4. The title MUST be in the same language as the conversation.\n"
        "5. The title MUST be about whole conversation if there is more than one message.\n"
        "6. The title MUST NOT contain ANY name of any conversation party like \"Gemini\", \"Gemini's\", \"User\" or \"User's\".\n"
        "Examples:\n"
        "Conversation: \"Hello, how are you?\"\n"
        "Title: Greeting\n\n"
        "Conversation: \"Привіт, як справи?\"\n"
        "Title: Привітання\n\n"
        "Conversation: \"Write a python script to sort a list\"\n"
        "Title: Python sorting script\n\n"
        "Conversation: \"Why is the sky blue?\"\n"
        "Title: Sky color explanation\n\n"
        "Conversation: \"I need help with my printer\"\n"
        "Title: Printer troubleshooting\n\n"
        "Conversation: \"sdlkfjsdf\"\n"
        "Title: Random characters\n\n"
        "Conversation: \n\"$input\"\n"
        "Title: ")
        .then((title) {
      newTitle = title;
    });
    return newTitle;
  }

  Future<String> generatePromptTitle(String input) async {
    ignoreContext = true;
    String newTitle = "";
    await log("model", "info", "Generating new prompt title");
    await generateTitle("Task: Create a short, 3-5 word title for this prompt.\n"
        "Rules:\n"
        "1. DO NOT use full sentences.\n"
        "2. DO NOT use phrases like \"The prompt is about\" or \"Summary of\".\n"
        "3. Be extremely concise.\n"
        "4. The title MUST be in the same language as the prompt.\n"
        "5. The title MUST be about whole prompt.\n"
        "6. The title MUST NOT contain ANY name of any party like \"Gemini\", \"Gemini's\", \"User\" or \"User's\".\n"
        "7. The title must not be a word-for-word representation for small prompts.\n"
        "8. If the prompt is empty, title it like \"Empty prompt\" or \"No prompt\" or in similar way.\n"
        "Examples:\n"
        "Prompt: \"Speak only in pirate language, do not break character\"\n"
        "Title: Pirate speak\n\n"
        "Prompt: \"Розмовляй як науковець\"\n"
        "Title: Науковець\n\n"
        "Prompt: \"Be a coding assistant, do not try to do anything but fix, optimize or refactor the code\"\n"
        "Title: Coding assistant\n\n"
        "Prompt: \"sdlkfjsdf\"\n"
        "Title: Bad prompt (gibberish)\n\n"
        "Prompt: \"\"\n"
        "Title: Empty prompt\n\n"
        "Prompt: \n\"$input\"\n"
        "Title: ")
        .then((title) {
      newTitle = title;
    });
    return newTitle;
  }

  Future<String> generateTitle(String input) async {
    ignoreContext = true;
    String newTitle = "";
    await gemini.init().then((initStatus) async {
      ignoreContext = false;
      if (initStatus == null) {
        analyzeError(
          "Initialization",
          "Did not get response from AICore communication attempt",
        );
      } else {
        if (initStatus.contains("Error")) {
          analyzeError("Initialization", initStatus);
        } else {
          await gemini
              .generateText(
            prompt: input,
            config: GenerationConfig(maxTokens: 20, temperature: 0.7),
          )
              .then((title) {
            newTitle = title.split('\n').first;
            newTitle = newTitle.replaceAll(RegExp(r'[*#_`]'), '').trim();
            if (newTitle.length > 40) {
              newTitle = "${newTitle.substring(0, 40)}...";
            }
          });
        }
      }
    });
    return newTitle.trim().replaceAll(".", "");
  }


  Future<void> clearContext() async {
    await chatData.clearContext();
    responseText = "";
  }

  Future<void> initEngine() async {
    if (isInitializing) return;
    isInitializing = true;
    isError = false;
    notifyListeners();
    try {
      String currentPromptId = chatData.chats.containsKey(currentChat) ? chatData.chats[currentChat]["promptId"] ?? config.defaultPromptId : config.defaultPromptId;
      String specificPromptText = promptData.getPromptContent(currentPromptId);
      
      bool runAddTime = chatData.chats.containsKey(currentChat) && chatData.chats[currentChat].containsKey("addCurrentTime") ? chatData.chats[currentChat]["addCurrentTime"] : addCurrentTimeToRequests;
      bool runShareLocale = chatData.chats.containsKey(currentChat) && chatData.chats[currentChat].containsKey("shareLocale") ? chatData.chats[currentChat]["shareLocale"] : shareLocale;
      
      await promptEngine
          .generate(
            specificPromptText,
            context,
            modelInfo,
            currentLocale: dict.value("current_language"),
            addTime: runAddTime,
            shareLocale: runShareLocale,
            ignoreInstructions: ignoreInstructions,
            ignoreContext: ignoreContext,
          )
          .then((instruction) async {
            await gemini.init(instructions: instruction).then((
              initStatus,
            ) async {
              if (initStatus == null) {
                await log(
                  "model",
                  "error",
                  "Did not get response from AICore communication attempt",
                );
                analyzeError(
                  "Initialization",
                  "Did not get response from AICore communication attempt",
                );
              } else {
                if (initStatus.contains("Error")) {
                  await log("model", "error", initStatus);
                  analyzeError("Initialization", initStatus);
                } else {
                  await log("model", "info", "Model initialized successfully");
                  isAvailable = true;
                  isInitialized = true;
                }
              }
            });
          });
    } catch (e) {
      await log("model", "error", e.toString());
      analyzeError("Initialization", e);
    } finally {
      isInitializing = false;
      notifyListeners();
    }
  }

  /// Sets the error state
  void analyzeError(String action, dynamic e) {
    isAvailable = false;
    isError = true;
    isInitialized = false;
    isInitializing = false;
    status = "Error during $action: ${e.toString()}";
    notifyListeners();
  }

  /// Re-initialises the session specifically for silent continuation.
  /// Uses [generateContinuation] which embeds the original question + partial text
  /// as a system directive — no user turn, so the model continues without addressing anyone.
  Future<void> _initForContinuation(String partialText) async {
    if (isInitializing) return;
    isInitializing = true;
    isError = false;
    notifyListeners();
    try {
      String currentPromptId = chatData.chats.containsKey(currentChat) ? chatData.chats[currentChat]["promptId"] ?? config.defaultPromptId : config.defaultPromptId;
      String specificPromptText = promptData.getPromptContent(currentPromptId);
      bool runAddTime = chatData.chats.containsKey(currentChat) && chatData.chats[currentChat].containsKey("addCurrentTime") ? chatData.chats[currentChat]["addCurrentTime"] : addCurrentTimeToRequests;
      bool runShareLocale = chatData.chats.containsKey(currentChat) && chatData.chats[currentChat].containsKey("shareLocale") ? chatData.chats[currentChat]["shareLocale"] : shareLocale;
      final instruction = await promptEngine.generateContinuation(
        specificPromptText,
        modelInfo,
        partialText,
        lastPrompt, // original question so model knows when it's done
        addTime: runAddTime,
        shareLocale: runShareLocale,
        currentLocale: dict.value("current_language"),
      );
      final initStatus = await gemini.init(instructions: instruction);
      if (initStatus == null || initStatus.contains("Error")) {
        await log("model", "error", "Continuation init failed: $initStatus");
        analyzeError("ContinuationInit", initStatus ?? "null");
      } else {
        await log("model", "info", "Model initialised for continuation");
        isAvailable = true;
        isInitialized = true;
      }
    } catch (e) {
      await log("model", "error", e.toString());
      analyzeError("ContinuationInit", e);
    } finally {
      isInitializing = false;
      notifyListeners();
    }
  }

  /// Cancels any ongoing generation
  Future<void> cancelGeneration() async {
    _aiSubscription?.cancel();
    isLoading = false;
    status = "Generation cancelled";
    notifyListeners();
    scrollChatlog(Duration(milliseconds: 250));
    await log("model", "error", "Cancelling generation");
  }

  Future<void> generateStream() async {
    if (prompt.text.isEmpty) {
      status = "Please enter your prompt";
      isError = true;
      notifyListeners();
      return;
    }
    if (isLoading) return; // Don't run if already generating

    // Ensure engine is ready
    if (!isInitializing) {
      await initEngine();
    }

    // Cancel any old streams
    await _aiSubscription?.cancel();

    // Set initial state for this new stream
    isLoading = true;
    isError = false;
    responseText = "";
    _lastFinishReason = ""; // reset for new generation
    _combinedResponse = ""; // reset accumulator
    isContinuing = false;
    _continuationCount = 0;
    cumulativeGenerationMs = 0;
    cumulativeTokenCount = 0;
    status = "Sending prompt...";
    notifyListeners();

    double runTemperature = chatData.chats.containsKey(currentChat) && chatData.chats[currentChat].containsKey("chatTemperature") ? chatData.chats[currentChat]["chatTemperature"] : temperature;

    final stream = gemini.generateTextEvents(
      prompt: "User's request: ${prompt.text.trim()}",
      // No maxTokens — let the model generate freely; only OS timeout (reason 1) or natural stop (reason -100) will end it
      config: GenerationConfig(temperature: runTemperature),
      stream: true,
    );
    lastPrompt = prompt.text.trim();

    _aiSubscription = stream.listen(
      (AiEvent event) async {
        switch (event.status) {
          case AiEventStatus.loading:
            isLoading = true;
            responseText = "";
            status = dict.value("waiting_for_AI");
            await log("model", "info", "Waiting for model to initialize");
            notifyListeners();
            break;

          case AiEventStatus.streaming:
            isLoading = true;
            String? finishReason = event.response?.finishReason;
            // Capture finishReason whenever the API reports one (it won't be on the done event)
            if (finishReason != null && finishReason != "null" && finishReason.isNotEmpty) {
              _lastFinishReason = finishReason;
            }
            if (!(event.response?.finishReason == "null")) {
              switch (finishReason ?? "null") {
                case "0":
                  if (kDebugMode) {
                    print(
                      "Generation stopped (MAX_TOKENS): The maximum number of output tokens as specified in the request was reached.",
                    );
                  }
                  await log("model", "info", "Generation stopped (MAX_TOKENS)");
                  break;
                case "1":
                  if (kDebugMode) {
                    print("Generation stopped (OTHER): Generic stop reason.");
                  }
                  await log("model", "info", "Generation stopped (OTHER)");
                  break;
                case "-100":
                  if (kDebugMode) {
                    print(
                      "Generation stopped (STOP): Natural stop point of the model.",
                    );
                  }
                  await log("model", "info", "Generation stopped (STOP)");
                  break;
                default:
                  if (kDebugMode) {
                    print(
                      "Generation stopped (Code ${event.response?.finishReason}): Reason for stop was not specified",
                    );
                  }
                  await log(
                    "model",
                    "info",
                    "Generation stopped (Code ${event.response?.finishReason})",
                  );
                  break;
              }
            }
            status = "Streaming response...";
            if (event.response != null) {
              response = event.response!;
              responseText = event.response!.text;
            }
            try {
              scrollChatlog(Duration(milliseconds: 250));
              await Future.delayed(Duration(milliseconds: 500));
              scrollChatlog(Duration(milliseconds: 250));
            } catch (e) {
              if (kDebugMode) {
                print("Can't scroll: $e");
              }
              await Future.delayed(Duration(milliseconds: 500));
            }
            break;

          case AiEventStatus.done:
            // ── Prominent finishReason debug log ─────────────────────────────
            // NOTE: _lastFinishReason is cached from streaming — the done event never carries it
            final String? doneReason = _lastFinishReason.isEmpty ? null : _lastFinishReason;
            if (kDebugMode) {
              final String friendlyReason = switch (doneReason) {
                "-100" => "STOP (natural end)",
                "0"    => "MAX_TOKENS (token budget exhausted)",
                "1"    => "OTHER (timeout or forced stop)",
                null   => "null (no reason reported during streaming)",
                _      => "UNKNOWN code: $doneReason",
              };
              print("╔═══════════════════════════════════════════╗");
              print("║  GENERATION DONE  finishReason: $friendlyReason");
              print("║  responseText length: ${responseText.length} chars");
              print("╚═══════════════════════════════════════════╝");
            }
            await log("model", "info", "Generation done. finishReason=$doneReason");
            // ─────────────────────────────────────────────────────────────────
            if (responseText == "") {
              if (errorRetry) {
                if (event.response?.text == null) {
                  isLoading = false;
                  Fluttertoast.showToast(
                    msg: "Unable to generate response.",
                    toastLength: Toast.LENGTH_SHORT,
                    fontSize: 16.0,
                  );
                } else {
                  await Future.delayed(Duration(milliseconds: 500));
                  generateStream();
                }
              } else {
                isLoading = false;
                isError = true;
                status = "Error";
                responseText = event.error ?? "Unknown stream error";
                await log("model", "error", responseText);
              }
            } else {
              // Only continue on reason "1" (OS timeout — model was genuinely mid-answer).
              // Reason "0" should no longer appear (maxTokens removed), but if it does we commit.
              // Reason "-100" / null = natural STOP — always commit.
              final bool shouldContinue = doneReason == "1"; // continue on timeout only

              if (shouldContinue) {
                // Model was cut off by timeout — snapshot stats, start silent continuation
                cumulativeGenerationMs += response.generationTimeMs?.toInt() ?? 0;
                cumulativeTokenCount += response.tokenCount?.toInt() ?? 0;
                _continuationCount++;
                _combinedResponse = responseText;
                await log("model", "info", "Response timed out, triggering continuation #$_continuationCount");
                if (kDebugMode) print("[AUTO-CONTINUE #$_continuationCount] timeout");
                // Only inject partial AI text — no user turn (continuation uses system-level [CONTINUATION] prompt)
                context.add({"user": "Gemini", "time": DateTime.now().millisecondsSinceEpoch.toString(), "message": _combinedResponse});
                await _triggerContinuation();
              } else {
                // Natural stop or cap reached — commit
                isContinuing = false;
                isLoading = false;
                status = "Done";
                await addToContext();
                prompt.clear();
                await log(
                  "model",
                  "info",
                  dict
                      .value("generated_hint")
                      .replaceAll("%seconds%", ((cumulativeGenerationMs + (response.generationTimeMs ?? 0)) / 1000).toStringAsFixed(2))
                      .replaceAll("%tokens%", (cumulativeTokenCount + (response.tokenCount?.toInt() ?? 0)).toString())
                      .replaceAll("%tokenspersec%", cumulativeGenerationMs + (response.generationTimeMs ?? 0) > 0
                          ? ((cumulativeTokenCount + (response.tokenCount?.toInt() ?? 0)) / ((cumulativeGenerationMs + (response.generationTimeMs ?? 0)) / 1000)).toStringAsFixed(2)
                          : "0.00"),
                );
                try {
                  scrollChatlog(Duration(milliseconds: 250));
                } catch (e) {
                  if (kDebugMode) print("Can't scroll: $e");
                }
              }
            }
            break;

          case AiEventStatus.error:
            if (errorRetry) {
              await Future.delayed(Duration(milliseconds: 500));
              generateStream();
            } else {
              isLoading = false;
              isError = true;
              status = "Error";
              responseText = event.error ?? "Unknown stream error";
              await log("model", "error", responseText);
            }
            break;
        }
        genericRefresh();
      },
      onError: (e) async {
        if (errorRetry) {
          await Future.delayed(Duration(milliseconds: 500));
          generateStream();
        } else {
          await log("model", "error", e);
          analyzeError("Streaming", e);
        }
      },
      onDone: () {
        // Final state update when stream closes
        isLoading = false;
        if (!isError) {
          status = "Stream complete";
        }
        genericRefresh();
      },
    );
  }

  /// Returns true if [text] ends inside an open code fence (odd number of ``` markers).
  bool _isInsideCodeBlock(String text) {
    return RegExp(r'```').allMatches(text).length % 2 == 1;
  }

  /// Resolves the join rules between [partial] (accumulated so far) and the
  /// first [newContent] chunk from the continuation session. Sets the join fields
  /// so that subsequent streaming chunks are displayed correctly.
  void _resolveJoin(String partial, String newContent) {
    if (partial.isEmpty || newContent.isEmpty) return;
    final String lastChar = partial[partial.length - 1];
    final String firstChar = newContent[0];

    if (_isInsideCodeBlock(partial)) {
      // We're inside an open code block — the model may have re-opened it.
      // Ensure a newline separator and strip any duplicate ``` opening.
      _continuationJoinPrefix = (lastChar == '\n') ? '' : '\n';
      // Match things like: ```php\n  or  ```\n  or  ``` at start
      _continuationStripPattern = r'^```[a-zA-Z0-9]*\n?';
      _continuationLowerFirst = false;
    } else {
      // Plain prose join
      final bool endsWithBoundary = lastChar == ' ' || lastChar == '\n';
      final bool startsWithBoundary = firstChar == ' ' || firstChar == '\n';
      if (!endsWithBoundary && !startsWithBoundary) {
        // No whitespace at join point — add a space
        _continuationJoinPrefix = ' ';
        // Only lowercase if the first char is a letter (not a symbol or digit)
        final bool isLetter = RegExp(r'[A-Z]').hasMatch(firstChar);
        _continuationLowerFirst = isLetter;
      }
      // If partial ends with punctuation like . ! ? the model likely started a
      // new sentence correctly — leave capitalisation alone.
      final bool endsWithSentence = '.!?'.contains(lastChar);
      if (endsWithSentence) {
        _continuationLowerFirst = false;
      }
    }
  }

  /// Continues a generation that was cut off (finishReason 0=MAX_TOKENS or 1=OTHER/timeout).
  /// One temporary context entry (partial Gemini turn) must already be in [context] when called.
  /// The model will see its own partial answer and continue — no user "please continue" turn,
  /// so it won't respond to a conversational prompt.
  Future<void> _triggerContinuation() async {
    isContinuing = true;
    _lastFinishReason = "";
    _firstContinuationChunk = true;   // reset join state for this round
    _continuationJoinPrefix = "";
    _continuationLowerFirst = false;
    _continuationStripPattern = "";
    // Show full accumulated text immediately while continuation fires up
    responseText = _combinedResponse;
    notifyListeners();

    await _aiSubscription?.cancel();
    // Use the continuation-specific init: system-level [CONTINUATION] directive,
    // no user turn, so the model simply outputs more text without addressing anyone
    await _initForContinuation(_combinedResponse);

    final double runTemperature = chatData.chats.containsKey(currentChat) && chatData.chats[currentChat].containsKey("chatTemperature") ? chatData.chats[currentChat]["chatTemperature"] : temperature;

    // Send a minimal system cue — the actual instruction is in the system prompt
    // This is NOT shown to the user and does NOT appear as a user message in context
    final stream = gemini.generateTextEvents(
      prompt: "Continue.",
      config: GenerationConfig(temperature: runTemperature), // no token cap
      stream: true,
    );

    _aiSubscription = stream.listen(
      (AiEvent event) async {
        switch (event.status) {
          case AiEventStatus.loading:
            status = dict.value("waiting_for_AI");
            notifyListeners();
            break;

          case AiEventStatus.streaming:
            final String? fr = event.response?.finishReason;
            if (fr != null && fr != "null" && fr.isNotEmpty) {
              _lastFinishReason = fr;
            }
            if (event.response != null) {
              response = event.response!;
              String contText = event.response!.text;
              // Resolve join rules once on the first chunk
              if (_firstContinuationChunk && contText.isNotEmpty) {
                _firstContinuationChunk = false;
                _resolveJoin(_combinedResponse, contText);
              }
              // Strip duplicate code-fence opening if detected
              if (_continuationStripPattern.isNotEmpty) {
                contText = contText.replaceFirst(RegExp(_continuationStripPattern), '');
              }
              // Lowercase first char if needed
              if (_continuationLowerFirst && contText.isNotEmpty) {
                contText = contText[0].toLowerCase() + contText.substring(1);
              }
              // Seamlessly prepend everything accumulated before this call
              responseText = _combinedResponse + _continuationJoinPrefix + contText;
            }
            try { scrollChatlog(Duration(milliseconds: 250)); } catch (_) {}
            break;

          case AiEventStatus.done:
            final String? contDoneReason = _lastFinishReason.isEmpty ? null : _lastFinishReason;
            // Update the accumulator
            _combinedResponse = responseText;
            // Note: stats are only added to cumulative when RECURSING (see cutAgain branch).
            // On the commit path we leave them in response.x so the UI formula
            // cumulative + response.x is always correct without double-counting.
            // Remove the temp partial AI context entry (1 entry only, no user turn)
            if (context.isNotEmpty) {
              context.removeLast();
            }
            if (kDebugMode) print("[AUTO-CONTINUE DONE] reason=$contDoneReason");
            await log("model", "info", "Continuation done. finishReason=$contDoneReason");

            final bool cutAgain = contDoneReason == "1"; // continue on timeout only

            if (cutAgain) {
              // Snapshot this session's stats into cumulative before starting the next round
              cumulativeGenerationMs += response.generationTimeMs?.toInt() ?? 0;
              cumulativeTokenCount += response.tokenCount?.toInt() ?? 0;
              _continuationCount++;
              context.add({"user": "Gemini", "time": DateTime.now().millisecondsSinceEpoch.toString(), "message": _combinedResponse});
              await _triggerContinuation();
            } else {
              // Commit — cumulative stays as-is; UI shows cumulative + response.x = total
              isContinuing = false;
              isLoading = false;
              status = "Done";
              await addToContext();
              prompt.clear();
            }
            break;

          case AiEventStatus.error:
            isContinuing = false;
            isLoading = false;
            isError = true;
            status = "Error during continuation";
            // Save whatever we accumulated so user doesn't lose it
            if (_combinedResponse.isNotEmpty) {
              responseText = _combinedResponse;
              await addToContext();
              prompt.clear();
            } else {
              responseText = event.error ?? "Continuation failed";
              await log("model", "error", responseText);
            }
            break;
        }
        genericRefresh();
      },
      onError: (e) async {
        isContinuing = false;
        isLoading = false;
        await log("model", "error", "Continuation stream error: $e");
        if (_combinedResponse.isNotEmpty) {
          responseText = _combinedResponse;
          await addToContext();
          prompt.clear();
        } else {
          analyzeError("Continuation", e);
        }
        genericRefresh();
      },
      onDone: () {
        if (!isError && !isContinuing) {
          isLoading = false;
          status = "Stream complete";
        }
        genericRefresh();
      },
    );

  }

  /// Clean up resources
  @override
  void dispose() {
    prompt.dispose();
    instructions.dispose();
    _aiSubscription?.cancel(); // Cancel stream
    gemini.dispose(); // Tell native code to clean up
    super.dispose();
  }
}
