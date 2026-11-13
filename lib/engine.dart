import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as md;
import 'package:fluttertoast/fluttertoast.dart';
import 'package:m3x/m3x.dart' hide Dictionary, AnalyticsService, Cards;
import 'package:geminilocal/pages/support/elements.dart';
import 'package:geminilocal/parts/prompt.dart';
import 'package:geminilocal/parts/translator.dart';
import 'parts/gemini.dart';

import 'package:geminilocal/storage/analytics_service.dart';
import 'package:geminilocal/storage/app_config.dart';
import 'package:geminilocal/storage/chat_repository.dart';
import 'package:geminilocal/storage/intro_slide_repository.dart';
import 'package:geminilocal/storage/migration.dart';
import 'package:geminilocal/storage/prompt_repository.dart';
import 'package:geminilocal/storage/resource_repository.dart';
import 'package:geminilocal/services/doc_service.dart';

class AIEngine with md.ChangeNotifier {
  final gemini = GeminiNano();
  final toolRegistry = M3xToolRegistry();
  final docService = DocService.instance;
  late final meshClient = M3xMeshClient(
    localRegistry: toolRegistry,
    localAppId: 'paios',
    enableSimulation: false,
    bypassAuthInDebug: true,
  );
  final prompt = md.TextEditingController();
  final instructions = md.TextEditingController();
  final chatName = md.TextEditingController();

  Dictionary dict = Dictionary(
    path: "assets/translations",
    url: "https://raw.githubusercontent.com/Puzzaks/PAIOS/main",
  );
  Prompt promptEngine = Prompt(ghUrl: "https://github.com/Puzzaks/PAIOS");
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
  bool isGenerating = false;
  bool _isSynthesizing = false; // true when synthesizing tool call response
  bool get isSynthesizing => _isSynthesizing;
  String _currentSynthesisPrompt = "";
  Uint8List? pendingImageBytes;
  String? pendingImageName;
  String _lastFinishReason = ""; // captured from streaming events, read at done
  String _combinedResponse = ""; // accumulates across continuation calls
  String get combinedResponse => _combinedResponse; // read-only access for UI
  int _continuationCount = 0;    // how many continuations fired (for logging)
  int _streamGenerationId = 0;   // invalidates stale onDone/onError callbacks across streams
  bool _activeToolHandling = false;
  bool _forcedFinalSynthesis = false;
  bool _lastToolFailed = false;
  bool _lastToolErrorIsInfra = false;
  String _lastToolErrorText = "";
  Future<void>? _meshDiscoveryFuture;
  bool _meshDiscoveryCompleted = false;
  String _lastToolResultPayload = "";
  String _currentUserPromptForSynthesis = "";
  M3xToolCall? _lastToolCall;
  int _recoverableErrorRetries = 0;
  // Cumulative generation stats across all continuation rounds (exposed to UI)
  int cumulativeGenerationMs = 0;
  int cumulativeTokenCount = 0;
  // Join-stitching state — resolved once per continuation round on first chunk
  bool _firstContinuationChunk = true;
  String _continuationJoinPrefix = "";  // space or newline to insert at join point
  bool _continuationLowerFirst = false; // lowercase the first char of continuation
  String _continuationStripPattern = ""; // regex to strip from start of cont text (e.g. duplicate code fence)

  final Stopwatch _generationStopwatch = Stopwatch();
  bool _isCurrentSessionMultimodal = false;

  md.ScrollController scroller = md.ScrollController();

  late final AppConfig config;
  late final ChatRepository chatData;
  late final AnalyticsService logger;
  late final PromptRepository promptData;
  late final ResourceRepository resourceData;
  late final IntroSlideRepository introSlideData;

  AIEngine() {
    config = AppConfig(notifyEngine: genericRefresh);
    logger = AnalyticsService(notifyEngine: genericRefresh);
    promptData = PromptRepository(notifyEngine: genericRefresh, logEvent: logger.log);
    resourceData = ResourceRepository(notifyEngine: genericRefresh, logEvent: logger.log);
    introSlideData = IntroSlideRepository(notifyEngine: genericRefresh, logEvent: logger.log);
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
  bool get downsampleImages => config.downsampleImages;
  set downsampleImages(bool value) => config.downsampleImages = value;
  bool get enableMesh => config.enableMesh;
  set enableMesh(bool value) {
    config.enableMesh = value;
    meshClient.enabled = value;
    if (value && !_meshDiscoveryCompleted) {
      unawaited(ensureMeshToolsDiscovered());
    }
  }
  bool get autoArchiveAssistantChats => config.autoArchiveAssistantChats;
  set autoArchiveAssistantChats(bool value) {
    config.autoArchiveAssistantChats = value;
    notifyListeners();
  }

  static String _resolvedPackageName = '';
  static String get _selfPackageId =>
      _resolvedPackageName.isNotEmpty ? _resolvedPackageName : 'page.puzzak.paios';

  /// Canonicalizes an extension identifier, normalizing only PAIOS self-IDs to
  /// [_selfPackageId] and preserving all external reverse-DNS package IDs as-is.
  static String canonicalExtensionId(String raw) {
    final trimmed = raw.trim();
    final lower = trimmed.toLowerCase();
    final selfLower = _selfPackageId.toLowerCase();
    if (lower == 'paios' ||
        lower == 'geminilocal' ||
        lower == selfLower ||
        lower == 'page.puzzak.paios' ||
        lower == 'com.puzzak.geminilocal' ||
        lower == 'com.puzzak.paios') {
      return _selfPackageId;
    }
    return trimmed;
  }

  /// Resolves the canonical extension package ID for a [M3xTool],
  /// preferring `tool.packageName` over `tool.app`.
  static String canonicalToolExtensionId(M3xTool tool) {
    final raw = (tool.packageName != null && tool.packageName!.trim().isNotEmpty)
        ? tool.packageName!
        : (tool.app ?? '');
    return canonicalExtensionId(raw);
  }

  /// Checks whether an external mesh extension / package is permitted to run.
  /// First-party apps (`page.puzzak.*`, `com.puzzak.*`) are enabled by default.
  /// Third-party apps default to the state of `mesh_allow_all_new` (default `false`).
  bool isExtensionEnabled(String appPackage) {
    final canon = canonicalExtensionId(appPackage);
    if (canon == _selfPackageId) return true;
    final box = Hive.box('paios_storage');
    final key = 'mesh_extension_${canon}_enabled';
    if (box.containsKey(key)) {
      return box.get(key) == true;
    }
    // Check legacy raw key for backwards compatibility
    final legacyKey = 'mesh_extension_${appPackage}_enabled';
    if (box.containsKey(legacyKey)) {
      return box.get(legacyKey) == true;
    }
    final allowAllNew = box.get('mesh_allow_all_new', defaultValue: false) == true;
    if (canon.startsWith('page.puzzak.') || canon.startsWith('com.puzzak.')) {
      return true;
    }
    return allowAllNew;
  }

  Future<void> setExtensionEnabled(String appPackage, bool enabled) async {
    final canon = canonicalExtensionId(appPackage);
    final box = Hive.box('paios_storage');
    await box.put('mesh_extension_${canon}_enabled', enabled);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('mesh_extension_${canon}_enabled', enabled);
      if (canon != appPackage) {
        await prefs.setBool('mesh_extension_${appPackage}_enabled', enabled);
      }
    } catch (_) {}
    notifyListeners();
  }

  bool get allowAllNewExtensions {
    final box = Hive.box('paios_storage');
    return box.get('mesh_allow_all_new', defaultValue: false) == true;
  }

  Future<void> setAllowAllNewExtensions(bool value) async {
    final box = Hive.box('paios_storage');
    await box.put('mesh_allow_all_new', value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('mesh_allow_all_new', value);
    } catch (_) {}
    notifyListeners();
  }

  Future<bool> isPackageInstalled(String pkg) async {
    final canon = canonicalExtensionId(pkg);
    try {
      final isInst = await meshClient.isPackageInstalled(canon);
      if (isInst) return true;
      if (canon != pkg) {
        final isRawInst = await meshClient.isPackageInstalled(pkg);
        if (isRawInst) return true;
      }
      final apps = await meshClient.listMeshApps();
      if (apps.any((a) => canonicalExtensionId(a) == canon)) return true;
      final tools = await meshClient.discoverInstalledTools();
      return tools.any((t) => canonicalToolExtensionId(t) == canon);
    } catch (_) {
      return false;
    }
  }

  bool get isAICoreBeta => (modelInfo["isBeta"] == "true");
  String get aicorePackageVersion => modelInfo["aicoreVersion"] ?? "Unknown";
  bool get isAICoreInstalled => (modelInfo["aicoreInstalled"] == "true");

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
  Future<void> saveSettings() {
    final activeId = config.defaultPromptId;
    final content = promptData.getPromptContent(activeId);
    final title = promptData.getPromptName(activeId);
    return config.saveSettings(
      instructions.text,
      promptContent: content,
      promptTitle: title,
    );
  }

  Future<void> syncActivePersonaToNative() async {
    try {
      final activeId = config.defaultPromptId;
      final content = promptData.getPromptContent(activeId);
      final title = promptData.getPromptName(activeId);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("defaultPromptId", activeId);
      if (content.isNotEmpty) {
        await prefs.setString("defaultPromptContent", content);
      }
      if (title.isNotEmpty) {
        await prefs.setString("defaultPromptTitle", title);
      }
      await prefs.setBool("autoArchiveAssistantChats", config.autoArchiveAssistantChats);
    } catch (_) {}
  }

  Future<void> _handleIncomingAssistantChat(Map<String, dynamic> payload) async {
    try {
      final rawMessages = payload['messages'];
      final unarchived = payload['unarchived'] == true;
      List conversation = [];
      if (rawMessages is String) {
        conversation = jsonDecode(rawMessages);
      } else if (rawMessages is List) {
        conversation = rawMessages;
      }
      if (conversation.isNotEmpty) {
        final isArchived = unarchived ? false : config.autoArchiveAssistantChats;
        final newChatId = await chatData.importAssistantChat(
          conversation,
          isArchived: isArchived,
        );
        if (unarchived && newChatId.isNotEmpty) {
          currentChat = newChatId;
          context = List.from(conversation);
          contextSize = int.tryParse(chats[newChatId]?["tokens"] ?? "0") ?? 0;
        }
        notifyListeners();
      }
    } catch (e) {
      await log("assistant", "error", "Failed to import assistant chat: $e");
    }
  }

  Future<void> _checkPendingAssistantChatsFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingStr = prefs.getString("pending_assistant_chats");
      if (pendingStr != null && pendingStr.isNotEmpty) {
        await prefs.remove("pending_assistant_chats");
        final decoded = jsonDecode(pendingStr);
        if (decoded is List) {
          for (var item in decoded) {
            if (item is Map) {
              final msgs = item["messages"];
              final unarchived = item["unarchived"] == true;
              if (msgs is List && msgs.isNotEmpty) {
                await chatData.importAssistantChat(
                  msgs,
                  isArchived: unarchived ? false : config.autoArchiveAssistantChats,
                );
              }
            }
          }
        }
      }
    } catch (_) {}
  }

  Future<void> pickImageAttachment() async {
    try {
      final res = await gemini.pickImage();
      if (res != null && res['bytes'] is Uint8List) {
        pendingImageBytes = res['bytes'] as Uint8List;
        pendingImageName = res['name']?.toString() ?? 'image.jpg';
        notifyListeners();
      }
    } catch (e) {
      await log("vision", "error", "Failed to pick image: $e");
    }
  }

  void clearImageAttachment() {
    pendingImageBytes = null;
    pendingImageName = null;
    notifyListeners();
  }

  scrollChatlog(Duration speed) {
    scroller.animateTo(
      scroller.position.maxScrollExtent,
      duration: speed,
      curve: md.Curves.fastOutSlowIn,
    );
  }

  Future<void> startAnalytics() => logger.startAnalytics();
  Future<void> stopAnalytics() => logger.stopAnalytics();
  Future<void> log(String name, String type, String message, {bool sendRemote = true}) =>
      logger.log(name, type, message, sendRemote: sendRemote);

  Future<void> _registerLocalTools() async {
    meshClient.registerLocalTool(
      M3xTool(
        name: 'query_local_ai',
        app: 'paios',
        description: 'Executes on-device Gemini inference via AICore/MLC LLM (supports text and multimodal image_base64).',
        parameters: {
          'type': 'object',
          'properties': {
            'prompt': {'type': 'string', 'description': 'Input prompt text'},
            'image_base64': {
              'type': 'string',
              'description': 'Optional base64-encoded image for multimodal vision',
            },
            'downsample': {
              'type': 'boolean',
              'description': 'Whether to downsample image to 768px for fast NPU prefill',
            },
          },
          'required': ['prompt'],
        },
        handler: (args) async {
          final promptText = args['prompt']?.toString() ?? '';
          final imageBase64 = args['image_base64']?.toString();
          final downsample = args['downsample'] is bool
              ? args['downsample'] as bool
              : config.downsampleImages;
          try {
            final res = await gemini.generateText(
              prompt: promptText,
              imageBase64: (imageBase64 != null && imageBase64.isNotEmpty)
                  ? imageBase64
                  : null,
              downsample: downsample,
            );
            return {
              'prompt': promptText,
              'response': res,
              'status': 'success',
            };
          } catch (e) {
            return {
              'prompt': promptText,
              'error': e.toString(),
              'status': 'error',
            };
          }
        },
      ),
    );

    meshClient.registerLocalTool(
      M3xTool(
        name: 'get_ai_status',
        app: 'paios',
        description: 'Returns PAIOS engine state, model readiness, and availability.',
        parameters: const {'type': 'object', 'properties': {}},
        handler: (args) async => {
          'engine_running': true,
          'model_available': isAvailable,
          'model_initialized': isInitialized,
          'status': status,
        },
      ),
    );

    docService.registerMeshTool(toolRegistry);
    await meshClient.startListening();
    await meshClient.syncDeclaredTools();
  }

  Future<void> ensureMeshToolsDiscovered({bool forceRefresh = false}) {
    if (!config.enableMesh) return Future.value();
    if (_meshDiscoveryCompleted && !forceRefresh) return Future.value();
    if (_meshDiscoveryFuture != null && !forceRefresh) {
      return _meshDiscoveryFuture!;
    }
    final future = () async {
      await log("init", "info", "Discovering sibling mesh tools");
      try {
        final discoveredTools = await meshClient
            .discoverInstalledTools()
            .timeout(const Duration(seconds: 4), onTimeout: () => <M3xTool>[]);
        toolRegistry.registerAll(discoveredTools);
        _meshDiscoveryCompleted = true;
        await log(
          "init",
          "info",
          "Dynamically discovered ${discoveredTools.length} mesh tools from installed apps: ${discoveredTools.map((t) => t.name).join(', ')}",
        );
        notifyListeners();
      } catch (e) {
        await log("init", "warning", "Failed to discover sibling tools: $e");
      } finally {
        _meshDiscoveryFuture = null;
      }
    }();
    _meshDiscoveryFuture = future;
    return future;
  }

  Future<void> start() async {
    await M3x.init();
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.packageName.isNotEmpty) {
        _resolvedPackageName = info.packageName;
      }
    } catch (_) {}
    await MigrationService.initiateMigration();
    await logger.initFromHive();
    await config.initFromHive();
    await docService.initialize();
    
    await log("init", "info", "Starting the app engine");
    await log("init", "info", "Starting the translations engine");
    dict = Dictionary(path: "assets/translations", url: "https://raw.githubusercontent.com/${config.repo}/main");
    await dict.setup(log: logger.log, onUpdated: genericRefresh);
    await log("init", "info", "Checking Gemini Nano status");
    await checkEngine();
    await log("init", "info", "Initializing the Prompt engine");
    promptEngine = Prompt(ghUrl: "https://github.com/${config.repo}");
    await promptData.initFromHive("https://raw.githubusercontent.com/${config.repo}/main");
    await promptEngine.initialize();
    await log("init", "info", "Initializing the Resource repository");
    await resourceData.initFromHive("https://raw.githubusercontent.com/${config.repo}/main");
    await log("init", "info", "Initializing Intro Slides repository");
    await introSlideData.initFromHive("https://raw.githubusercontent.com/${config.repo}/main");
    
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

    meshClient.enabled = config.enableMesh;
    await _registerLocalTools();

    appStarted = true;
    await log("init", "info", "App initiation complete");
    await syncActivePersonaToNative();

    gemini.setAssistantChatHandler((payload) async {
      await _handleIncomingAssistantChat(payload);
    });
    final initialAssistant = await gemini.getInitialAssistantChat();
    if (initialAssistant != null) {
      await _handleIncomingAssistantChat(initialAssistant);
    }
    await _checkPendingAssistantChatsFromPrefs();

    notifyListeners();

    if (config.enableMesh) {
      unawaited(ensureMeshToolsDiscovered());
    } else {
      await log("init", "info", "Agentic Mesh disabled by user configuration");
    }

    // Post-launch background documentation synchronization (Tier 3 SWR on each launch)
    unawaited(docService.syncRemoteDocs());
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


  /// Triggers background chat title generation once generation and synthesis are completely finished.
  void _checkAndTriggerTitle() {
    final currentChatId = chatData.currentChat;
    final chat = chatData.chats[currentChatId];
    if (chat != null && (chat["name"] == null || chat["name"] == "" || chat["name"] == "Still loading")) {
      unawaited(() async {
        try {
          String composeConversation = "";
          for (var line in chatData.context) {
            composeConversation = "$composeConversation\n - ${line["message"]}";
          }
          final title = await generateChatTitle(composeConversation);
          if (title.isNotEmpty && title != "Still loading" && chatData.chats.containsKey(currentChatId)) {
            chatData.chats[currentChatId]!["name"] = title;
            await chatData.saveChats();
          }
        } catch (_) {}
      }());
    }
  }

  Future<String> generateChatTitle(String input) async {
    if (_isSynthesizing || isGenerating || isLoading) {
      await log("model", "info", "Postponing chat title generation: AI generation/synthesis in progress", sendRemote: false);
      return "Still loading";
    }
    ignoreContext = true;
    String newTitle = "";
    await log("model", "info", "Generating new chat title", sendRemote: false);
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
    await log("model", "info", "Generating new prompt title", sendRemote: false);
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

  Future<void> initEngine({bool includeTools = true}) async {
    if (isInitializing) return;
    isInitializing = true;
    isError = false;
    notifyListeners();
    unawaited(docService.syncRemoteDocs());
    try {
      String currentPromptId = chatData.chats.containsKey(currentChat) ? chatData.chats[currentChat]["promptId"] ?? config.defaultPromptId : config.defaultPromptId;
      String specificPromptText = promptData.getPromptContent(currentPromptId);
      
      bool runAddTime = chatData.chats.containsKey(currentChat) && chatData.chats[currentChat].containsKey("addCurrentTime") ? chatData.chats[currentChat]["addCurrentTime"] : addCurrentTimeToRequests;
      bool runShareLocale = chatData.chats.containsKey(currentChat) && chatData.chats[currentChat].containsKey("shareLocale") ? chatData.chats[currentChat]["shareLocale"] : shareLocale;
      
      if (includeTools && config.enableMesh) {
        await ensureMeshToolsDiscovered();
      }

      final externalTools = toolRegistry.tools.where((t) {
        if (t.name == 'query_aicore_documentation') return true;
        final extId = canonicalToolExtensionId(t);
        if (extId == _selfPackageId || t.name == 'query_local_ai' || t.name == 'get_ai_status') {
          return false;
        }
        if (extId.isNotEmpty && !isExtensionEnabled(extId)) {
          return false;
        }
        return true;
      }).toList();

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
            tools: externalTools,
            includeTools: includeTools,
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
                  sendRemote: false,
                );
                analyzeError(
                  "Initialization",
                  "Did not get response from AICore communication attempt",
                );
              } else {
                if (initStatus.contains("Error")) {
                  await log("model", "error", initStatus, sendRemote: false);
                  analyzeError("Initialization", initStatus);
                } else {
                  await log("model", "info", "Model initialized successfully", sendRemote: false);
                  isAvailable = true;
                  isInitialized = true;
                }
              }
            });
          });
    } catch (e) {
      await log("model", "error", e.toString(), sendRemote: false);
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
  Future<void> _initForContinuation(String partialText, {bool isSynthesis = false}) async {
    if (isInitializing) return;
    isInitializing = true;
    isError = false;
    notifyListeners();
    try {
      String currentPromptId = chatData.chats.containsKey(currentChat) ? chatData.chats[currentChat]["promptId"] ?? config.defaultPromptId : config.defaultPromptId;
      String specificPromptText = promptData.getPromptContent(currentPromptId);
      bool runAddTime = chatData.chats.containsKey(currentChat) && chatData.chats[currentChat].containsKey("addCurrentTime") ? chatData.chats[currentChat]["addCurrentTime"] : addCurrentTimeToRequests;
      bool runShareLocale = chatData.chats.containsKey(currentChat) && chatData.chats[currentChat].containsKey("shareLocale") ? chatData.chats[currentChat]["shareLocale"] : shareLocale;
      final promptForContinuation = (isSynthesis && _currentSynthesisPrompt.isNotEmpty)
          ? _currentSynthesisPrompt
          : lastPrompt;
      final instruction = await promptEngine.generateContinuation(
        specificPromptText,
        modelInfo,
        partialText,
        promptForContinuation, // original question or synthesis prompt so model knows when it's done
        addTime: runAddTime,
        shareLocale: runShareLocale,
        currentLocale: dict.value("current_language"),
      );
      final initStatus = await gemini.init(instructions: instruction);
      if (initStatus == null || initStatus.contains("Error")) {
        await log("model", "error", "Continuation init failed: $initStatus", sendRemote: false);
        analyzeError("ContinuationInit", initStatus ?? "null");
      } else {
        await log("model", "info", "Model initialised for continuation", sendRemote: false);
        isAvailable = true;
        isInitialized = true;
      }
    } catch (e) {
      await log("model", "error", e.toString(), sendRemote: false);
      analyzeError("ContinuationInit", e);
    } finally {
      isInitializing = false;
      notifyListeners();
    }
  }

  String _getModelVersion() {
    final v = modelInfo["version"]?.toString();
    if (v != null && v.isNotEmpty && v != "null") {
      return v;
    }
    final aicoreV = modelInfo["aicoreVersion"]?.toString();
    if (aicoreV != null && aicoreV.isNotEmpty && aicoreV != "null") {
      return aicoreV;
    }
    return "unknown";
  }

  String _getCurrentPromptId() {
    if (chatData.chats.containsKey(currentChat)) {
      final id = chatData.chats[currentChat]["promptId"]?.toString();
      if (id != null && id.isNotEmpty) return id;
    }
    return config.defaultPromptId.isNotEmpty ? config.defaultPromptId : "system_default";
  }

  String _mapFinishReason(String? rawReason) {
    switch (rawReason) {
      case "-100":
        return "stop";
      case "0":
        return "max_tokens";
      case "1":
        return "timeout";
      case null:
      case "":
      case "null":
        return "stop";
      default:
        return rawReason.toLowerCase();
    }
  }

  String _classifyError(dynamic error) {
    if (error == null) return "none";
    final str = error.toString().toLowerCase();
    if (str.isEmpty || str == "none") return "none";
    if (str.contains("timeout") || str.contains("timed out")) {
      return "timeout";
    }
    if (str.contains("busy") || str.contains("resource_exhausted") || str.contains("model busy")) {
      return "model_busy";
    }
    if (str.contains("context") || str.contains("overflow") || str.contains("max_tokens") || str.contains("token limit")) {
      return "context_overflow";
    }
    if (str.contains("npu") || str.contains("unavailable") || str.contains("not installed") || str.contains("aicore") || str.contains("download_error")) {
      return "npu_unavailable";
    }
    if (str.contains("cancel")) {
      return "cancelled";
    }
    return "unknown";
  }

  int _extractErrorCode(dynamic error) {
    if (error == null) return 0;
    final str = error.toString();
    final match = RegExp(r'(?:code|error|status)[\s:=]+(-?\d+)', caseSensitive: false).firstMatch(str);
    if (match != null) {
      return int.tryParse(match.group(1)!) ?? 0;
    }
    final numMatch = RegExp(r'\b(-?\d{1,5})\b').firstMatch(str);
    if (numMatch != null) {
      return int.tryParse(numMatch.group(1)!) ?? 0;
    }
    return 0;
  }

  /// Cancels any ongoing generation
  Future<void> cancelGeneration() async {
    final wasLoading = isLoading;
    _aiSubscription?.cancel();
    isLoading = false;
    status = "Generation cancelled";
    notifyListeners();
    scrollChatlog(Duration(milliseconds: 250));
    await log("model", "error", "Cancelling generation", sendRemote: false);
    if (wasLoading) {
      await logger.logAiGeneration(
        success: false,
        latencyMs: _generationStopwatch.elapsedMilliseconds,
        tokensGenerated: cumulativeTokenCount + (response.tokenCount?.toInt() ?? 0),
        errorType: "cancelled",
        errorCode: 0,
        finishReason: "cancelled",
        modelVersion: _getModelVersion(),
        promptId: _getCurrentPromptId(),
        isMultimodal: _isCurrentSessionMultimodal,
      );
    }
  }

  Future<void> generateStream() async {
    if (prompt.text.isEmpty && pendingImageBytes == null) {
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

    // Capture and persist any attached image before starting stream
    final Uint8List? attachedImageBytes = pendingImageBytes;
    String? savedImagePath;
    if (attachedImageBytes != null) {
      savedImagePath = await chatData.saveChatImage(attachedImageBytes);
      chatData.lastImagePath = savedImagePath;
      pendingImageBytes = null;
      pendingImageName = null;
    }

    // Set initial state for this new stream
    _generationStopwatch.reset();
    _generationStopwatch.start();
    _isCurrentSessionMultimodal = attachedImageBytes != null || savedImagePath != null;

    _toolTurnCount = 0;
    _lastToolCallSignature = "";
    _forcedFinalSynthesis = false;
    _activeToolHandling = false;
    _lastToolFailed = false;
    _lastToolErrorIsInfra = false;
    _lastToolErrorText = "";
    _lastToolResultPayload = "";
    _lastToolCall = null;
    _recoverableErrorRetries = 0;
    final int myGenId = ++_streamGenerationId;
    bool receivedTerminalEvent = false;

    isLoading = true;
    isGenerating = true;
    isError = false;
    responseText = "";
    _lastFinishReason = ""; // reset for new generation
    _combinedResponse = ""; // reset accumulator
    isContinuing = false;
    _isSynthesizing = false;
    _continuationCount = 0;
    cumulativeGenerationMs = 0;
    cumulativeTokenCount = 0;
    status = "Sending prompt...";
    notifyListeners();

    double runTemperature = chatData.chats.containsKey(currentChat) && chatData.chats[currentChat].containsKey("chatTemperature") ? chatData.chats[currentChat]["chatTemperature"] : temperature;

    final String effectiveUserPrompt = prompt.text.trim().isNotEmpty
        ? prompt.text.trim()
        : "Describe this image.";

    final stream = gemini.generateTextEvents(
      prompt: "User's request: $effectiveUserPrompt",
      // No maxTokens — let the model generate freely; only OS timeout (reason 1) or natural stop (reason -100) will end it
      config: GenerationConfig(temperature: runTemperature),
      stream: true,
      imageBytes: attachedImageBytes,
      imagePath: savedImagePath,
      downsample: config.downsampleImages,
    );
    lastPrompt = effectiveUserPrompt;

    _aiSubscription = stream.listen(
      (AiEvent event) async {
        if (myGenId != _streamGenerationId) return;
        switch (event.status) {
          case AiEventStatus.loading:
            isLoading = true;
            responseText = "";
            status = dict.value("waiting_for_AI");
            await log("model", "info", "Waiting for model to initialize", sendRemote: false);
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
                  await log("model", "info", "Generation stopped (MAX_TOKENS)", sendRemote: false);
                  break;
                case "1":
                  if (kDebugMode) {
                    print("Generation stopped (OTHER): Generic stop reason.");
                  }
                  await log("model", "info", "Generation stopped (OTHER)", sendRemote: false);
                  break;
                case "-100":
                  if (kDebugMode) {
                    print(
                      "Generation stopped (STOP): Natural stop point of the model.",
                    );
                  }
                  await log("model", "info", "Generation stopped (STOP)", sendRemote: false);
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
                    sendRemote: false,
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
            receivedTerminalEvent = true;
            // ── Prominent finishReason debug log ─────────────────────────────
            // NOTE: _lastFinishReason is cached from streaming — the done event also carries fallback reason
            final String? doneReason = _lastFinishReason.isNotEmpty
                ? _lastFinishReason
                : event.reason;
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
            await log("model", "info", "Generation done. finishReason=$doneReason", sendRemote: false);
            // ─────────────────────────────────────────────────────────────────
            if (responseText == "") {
              if (errorRetry) {
                if (event.response?.text == null) {
                  isLoading = false;
                  isGenerating = false;
                  Fluttertoast.showToast(
                    msg: "Unable to generate response.",
                    toastLength: Toast.LENGTH_SHORT,
                    fontSize: 16.0,
                  );
                  await logger.logAiGeneration(
                    success: false,
                    latencyMs: _generationStopwatch.elapsedMilliseconds,
                    errorType: "empty_response",
                    errorCode: 0,
                    finishReason: "error",
                    modelVersion: _getModelVersion(),
                    promptId: _getCurrentPromptId(),
                    isMultimodal: _isCurrentSessionMultimodal,
                  );
                } else {
                  await Future.delayed(Duration(milliseconds: 500));
                  generateStream();
                }
              } else {
                isLoading = false;
                isGenerating = false;
                isError = true;
                status = "Error";
                responseText = event.error ?? "Unknown stream error";
                await log("model", "error", responseText, sendRemote: false);
                await logger.logAiGeneration(
                  success: false,
                  latencyMs: _generationStopwatch.elapsedMilliseconds,
                  errorType: _classifyError(responseText),
                  errorCode: _extractErrorCode(responseText),
                  finishReason: "error",
                  modelVersion: _getModelVersion(),
                  promptId: _getCurrentPromptId(),
                  isMultimodal: _isCurrentSessionMultimodal,
                );
              }
            } else {
              final toolMap = M3xToolCallParser.extract(responseText);
              if (toolMap != null) {
                _activeToolHandling = true;
                try {
                  await _handleToolCall(toolMap, originalPrompt: effectiveUserPrompt);
                } finally {
                  _activeToolHandling = false;
                }
                break;
              }

              final bool shouldContinue = _shouldContinueOnDone(doneReason, responseText);

              if (shouldContinue) {
                // Model was cut off by timeout / mid-JSON — snapshot stats, start silent continuation
                cumulativeGenerationMs += response.generationTimeMs?.toInt() ?? 0;
                cumulativeTokenCount += response.tokenCount?.toInt() ?? 0;
                _continuationCount++;
                _combinedResponse = responseText;
                await log("model", "info", "Response interrupted (reason=$doneReason), triggering continuation #$_continuationCount", sendRemote: false);
                if (kDebugMode) print("[AUTO-CONTINUE #$_continuationCount] reason=$doneReason");
                await continueGenerating();
              } else {
                if (M3xToolCallParser.looksLikeIncompleteToolCall(responseText)) {
                  await log("mesh", "error", "Discarding incomplete tool call after continuation limit: $responseText");
                  responseText = _buildIncompleteToolFallback();
                }
                // Natural stop or cap reached — commit
                isContinuing = false;
                isLoading = false;
                isGenerating = false;
                status = "Done";
                await addToContext();
                prompt.clear();

                final totalMs = cumulativeGenerationMs + (response.generationTimeMs?.toInt() ?? 0);
                final totalTokens = cumulativeTokenCount + (response.tokenCount?.toInt() ?? 0);
                final latency = totalMs > 0 ? totalMs : _generationStopwatch.elapsedMilliseconds;

                await logger.logAiGeneration(
                  success: true,
                  latencyMs: latency,
                  tokensGenerated: totalTokens,
                  finishReason: _mapFinishReason(doneReason),
                  modelVersion: _getModelVersion(),
                  promptId: _getCurrentPromptId(),
                  isMultimodal: _isCurrentSessionMultimodal,
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
            receivedTerminalEvent = true;
            if (errorRetry) {
              await Future.delayed(Duration(milliseconds: 500));
              generateStream();
            } else {
              isLoading = false;
              isGenerating = false;
              isError = true;
              status = "Error";
              responseText = event.error ?? "Unknown stream error";
              await log("model", "error", responseText, sendRemote: false);
              await logger.logAiGeneration(
                success: false,
                latencyMs: _generationStopwatch.elapsedMilliseconds,
                errorType: _classifyError(responseText),
                errorCode: _extractErrorCode(responseText),
                finishReason: "error",
                modelVersion: _getModelVersion(),
                promptId: _getCurrentPromptId(),
                isMultimodal: _isCurrentSessionMultimodal,
              );
            }
            break;
        }
        genericRefresh();
      },
      onError: (e) async {
        if (myGenId != _streamGenerationId) return;
        receivedTerminalEvent = true;
        isGenerating = false;
        if (errorRetry) {
          await Future.delayed(Duration(milliseconds: 500));
          generateStream();
        } else {
          await log("model", "error", e.toString(), sendRemote: false);
          analyzeError("Streaming", e);
          await logger.logAiGeneration(
            success: false,
            latencyMs: _generationStopwatch.elapsedMilliseconds,
            errorType: _classifyError(e),
            errorCode: _extractErrorCode(e),
            finishReason: "error",
            modelVersion: _getModelVersion(),
            promptId: _getCurrentPromptId(),
            isMultimodal: _isCurrentSessionMultimodal,
          );
        }
      },
      onDone: () {
        if (myGenId != _streamGenerationId ||
            receivedTerminalEvent ||
            _activeToolHandling ||
            isContinuing ||
            _isSynthesizing) {
          return;
        }
        // Final state update when stream closes unexpectedly without terminal event
        isLoading = false;
        isGenerating = false;
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

  bool _shouldContinueOnDone(String? reason, String text) {
    if (_continuationCount >= 4 || text.trim().isEmpty) return false;
    final upper = reason?.toUpperCase() ?? '';
    if (reason == "1" || upper == "OTHER" || upper == "MAX_TOKENS") {
      return true;
    }
    if (!_forcedFinalSynthesis && M3xToolCallParser.looksLikeIncompleteToolCall(text)) {
      return true;
    }
    return false;
  }

  bool _isInfrastructureToolError(String message) {
    final low = message.toLowerCase();
    return low.contains('is not running') ||
        low.contains('timed out') ||
        low.contains('timeout') ||
        low.contains('not implemented') ||
        low.contains('headless_overlay_required') ||
        low.contains('mesh communication error') ||
        low.contains('no response from contentprovider') ||
        low.contains('disabled in paios settings') ||
        low.contains('connection failed') ||
        low.contains('connection refused') ||
        low.contains('connection error') ||
        low.contains('failed to connect');
  }

  String? _extractSoftToolError(Map<String, dynamic>? resultMap) {
    if (resultMap == null) return null;
    if ((resultMap['found'] == false || resultMap['success'] == false) &&
        resultMap['error'] != null) {
      final msg = resultMap['error'].toString().trim();
      if (msg.isNotEmpty) return msg;
    }
    return null;
  }

  bool _looksLikeUnformattedToolEcho(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return true;
    if (trimmed.contains('[TOOL RESULT:')) return true;
    if (RegExp(r"^The tool '[^']+' from '[^']+' returned:", caseSensitive: false)
        .hasMatch(trimmed)) {
      return true;
    }
    return false;
  }

  bool _looksLikeHallucinatedNormalOnError(String text) {
    if (!_lastToolFailed) return false;
    final low = text.toLowerCase();
    return low.contains('no incidents') ||
        low.contains('no active incidents') ||
        low.contains('no ongoing incidents') ||
        low.contains('everything is normal') ||
        low.contains('all systems are operational');
  }

  String _humanizeKey(String raw) {
    final cleaned = raw.replaceAll('_', ' ').trim();
    if (cleaned.isEmpty) return raw;
    return cleaned[0].toUpperCase() + cleaned.substring(1);
  }

  String _formatReadableToolSummary(String toolName, dynamic decoded) {
    if (decoded is! Map) {
      return decoded.toString();
    }
    final lines = <String>[];
    decoded.forEach((key, value) {
      final label = _humanizeKey(key.toString());
      if (value is Map) {
        final subParts = value.entries
            .map((e) => '${_humanizeKey(e.key.toString())}: ${e.value}')
            .join(', ');
        if (subParts.isNotEmpty) lines.add('$label: $subParts');
      } else if (value is List) {
        if (value.isEmpty) {
          lines.add('$label: none');
        } else if (value.first is Map) {
          lines.add('$label (${value.length}):');
          for (final item in value.take(5)) {
            if (item is Map) {
              final summary = item.entries
                  .take(4)
                  .map((e) => '${_humanizeKey(e.key.toString())}: ${e.value}')
                  .join(', ');
              lines.add('• $summary');
            }
          }
          if (value.length > 5) {
            lines.add('• ...and ${value.length - 5} more');
          }
        } else {
          lines.add('$label: ${value.join(', ')}');
        }
      } else if (value != null && value.toString().isNotEmpty) {
        lines.add('$label: $value');
      }
    });
    if (lines.isEmpty) {
      return 'Completed ${toolName.isNotEmpty ? toolName : 'tool'} with no additional details.';
    }
    return lines.join('\n');
  }

  String _buildRecoverableErrorHint(String toolName, String errorMessage) {
    return 'Tool call "$toolName" failed: $errorMessage. '
        'Inspect the available tool schemas and retry once with valid parameters '
        '(or call a prerequisite discovery/list tool first if an identifier is missing), '
        'or explain the issue clearly if it cannot be resolved.';
  }

  String _buildIncompleteToolFallback() {
    if (_lastToolFailed && _lastToolErrorText.isNotEmpty) {
      final appLabel = _lastToolCall?.app;
      final scope = (_lastToolErrorIsInfra && appLabel != null && appLabel.isNotEmpty)
          ? " from '$appLabel'"
          : '';
      return "Unable to retrieve live data$scope: $_lastToolErrorText";
    }
    if (_lastToolResultPayload.isNotEmpty) {
      try {
        final decoded = jsonDecode(_lastToolResultPayload);
        return _formatReadableToolSummary(_lastToolCall?.tool ?? '', decoded);
      } catch (_) {
        return "Completed ${_lastToolCall?.tool ?? 'the requested action'}, but could not format the response.";
      }
    }
    return "The assistant could not complete a valid tool request for this query. Please try rephrasing or try again.";
  }

  /// Resolves the join rules between [partial] (accumulated so far) and the
  /// first [newContent] chunk from the continuation session. Sets the join fields
  /// so that subsequent streaming chunks are displayed correctly.
  void _resolveJoin(String partial, String newContent) {
    if (partial.isEmpty || newContent.isEmpty) return;
    final String lastChar = partial[partial.length - 1];
    final String firstChar = newContent[0];
    final String trimmedPartial = partial.trimLeft();
    final bool isJsonOrToolDraft = trimmedPartial.startsWith('{') ||
        trimmedPartial.startsWith('```json') ||
        M3xToolCallParser.looksLikeIncompleteToolCall(partial);

    if (isJsonOrToolDraft) {
      // Preserve exact JSON token boundaries — never inject whitespace or alter case.
      _continuationJoinPrefix = '';
      _continuationLowerFirst = false;
      _continuationStripPattern = _isInsideCodeBlock(partial)
          ? r'^```(?:json)?\s*'
          : '';
      return;
    }

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
  /// The model will see its own partial answer and continue — no user "please continue" turn,
  /// so it won't respond to a conversational prompt.
  Future<void> continueGenerating({bool isSynthesis = false}) async {
    if (isSynthesis) {
      _isSynthesizing = true;
    }
    final int myGenId = ++_streamGenerationId;
    bool receivedTerminalEvent = false;
    isContinuing = true;
    isGenerating = true;
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
    await _initForContinuation(_combinedResponse, isSynthesis: isSynthesis);
    if (myGenId != _streamGenerationId) return;

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
        if (myGenId != _streamGenerationId) return;
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
            receivedTerminalEvent = true;
            final String? contDoneReason = _lastFinishReason.isNotEmpty
                ? _lastFinishReason
                : event.reason;
            // Update the accumulator
            _combinedResponse = responseText;
            // Note: stats are only added to cumulative when RECURSING (see cutAgain branch).
            // On the commit path we leave them in response.x so the UI formula
            // cumulative + response.x is always correct without double-counting.
            if (kDebugMode) print("[AUTO-CONTINUE DONE] reason=$contDoneReason");
            await log("model", "info", "Continuation done. finishReason=$contDoneReason", sendRemote: false);

            bool cutAgain = _shouldContinueOnDone(contDoneReason, responseText);
            if (response.text.trim().isEmpty) {
              cutAgain = false;
            }

            if (cutAgain) {
              // Snapshot this session's stats into cumulative before starting the next round
              cumulativeGenerationMs += response.generationTimeMs?.toInt() ?? 0;
              cumulativeTokenCount += response.tokenCount?.toInt() ?? 0;
              _continuationCount++;
              await continueGenerating(isSynthesis: _isSynthesizing);
            } else {
              final completedToolMap = M3xToolCallParser.extract(responseText);
              if (completedToolMap != null) {
                isContinuing = false;
                _activeToolHandling = true;
                try {
                  if (_isSynthesizing) {
                    final synthPrompt = _currentUserPromptForSynthesis.isNotEmpty
                        ? _currentUserPromptForSynthesis
                        : lastPrompt;
                    await _handleSynthesisToolCall(completedToolMap, synthPrompt);
                  } else {
                    await _handleToolCall(completedToolMap, originalPrompt: lastPrompt);
                  }
                } finally {
                  _activeToolHandling = false;
                }
                break;
              }

              if (M3xToolCallParser.looksLikeIncompleteToolCall(responseText) ||
                  (_isSynthesizing &&
                      (_looksLikeUnformattedToolEcho(responseText) ||
                          _looksLikeHallucinatedNormalOnError(responseText)))) {
                await log("mesh", "error", "Discarding incomplete or unformatted tool response after continuation: $responseText");
                responseText = _buildIncompleteToolFallback();
              }

              // Commit — cumulative stays as-is; UI shows cumulative + response.x = total
              isContinuing = false;
              isLoading = false;
              isGenerating = false;
              status = "Done";

              if (_isSynthesizing) {
                _isSynthesizing = false;
                await chatData.appendMessage(user: "Gemini", message: responseText);
                prompt.clear();
                lastPrompt = "";
                _currentSynthesisPrompt = "";
                await log("mesh", "info", "Tool synthesis complete (via continuation)");
                await chatData.saveChat(chatData.context, chatID: chatData.currentChat);
                _checkAndTriggerTitle();
                try {
                  scrollChatlog(const Duration(milliseconds: 250));
                } catch (_) {}
              } else {
                await addToContext();
                prompt.clear();

                final totalMs = cumulativeGenerationMs + (response.generationTimeMs?.toInt() ?? 0);
                final totalTokens = cumulativeTokenCount + (response.tokenCount?.toInt() ?? 0);
                final latency = totalMs > 0 ? totalMs : _generationStopwatch.elapsedMilliseconds;

                await logger.logAiGeneration(
                  success: true,
                  latencyMs: latency,
                  tokensGenerated: totalTokens,
                  finishReason: _mapFinishReason(contDoneReason),
                  modelVersion: _getModelVersion(),
                  promptId: _getCurrentPromptId(),
                  isMultimodal: _isCurrentSessionMultimodal,
                );
              }
            }
            break;

          case AiEventStatus.error:
            receivedTerminalEvent = true;
            isContinuing = false;
            isLoading = false;
            isGenerating = false;
            isError = true;
            status = "Error during continuation";
            if (_isSynthesizing) {
              _isSynthesizing = false;
              if (_combinedResponse.isNotEmpty &&
                  !M3xToolCallParser.looksLikeIncompleteToolCall(_combinedResponse)) {
                responseText = _combinedResponse;
                await chatData.appendMessage(user: "Gemini", message: responseText);
                prompt.clear();
                lastPrompt = "";
              }
              await log("mesh", "error", "Error during tool synthesis continuation");
            } else if (_combinedResponse.isNotEmpty &&
                !M3xToolCallParser.looksLikeIncompleteToolCall(_combinedResponse)) {
              responseText = _combinedResponse;
              await addToContext();
              prompt.clear();

              final totalMs = cumulativeGenerationMs + (response.generationTimeMs?.toInt() ?? 0);
              final totalTokens = cumulativeTokenCount + (response.tokenCount?.toInt() ?? 0);
              final latency = totalMs > 0 ? totalMs : _generationStopwatch.elapsedMilliseconds;

              await logger.logAiGeneration(
                success: true,
                latencyMs: latency,
                tokensGenerated: totalTokens,
                finishReason: "timeout",
                modelVersion: _getModelVersion(),
                promptId: _getCurrentPromptId(),
                isMultimodal: _isCurrentSessionMultimodal,
              );
            } else {
              responseText = event.error ?? "Continuation failed";
              await log("model", "error", responseText, sendRemote: false);
              await logger.logAiGeneration(
                success: false,
                latencyMs: _generationStopwatch.elapsedMilliseconds,
                errorType: _classifyError(responseText),
                errorCode: _extractErrorCode(responseText),
                finishReason: "error",
                modelVersion: _getModelVersion(),
                promptId: _getCurrentPromptId(),
                isMultimodal: _isCurrentSessionMultimodal,
              );
            }
            break;
        }
        genericRefresh();
      },
      onError: (e) async {
        if (myGenId != _streamGenerationId) return;
        receivedTerminalEvent = true;
        isContinuing = false;
        isLoading = false;
        isGenerating = false;
        if (_isSynthesizing) {
          _isSynthesizing = false;
          if (_combinedResponse.isNotEmpty &&
              !M3xToolCallParser.looksLikeIncompleteToolCall(_combinedResponse)) {
            responseText = _combinedResponse;
            await chatData.appendMessage(user: "Gemini", message: responseText);
            prompt.clear();
            lastPrompt = "";
          }
          await log("mesh", "error", "Synthesis continuation error: $e");
          analyzeError("SynthesisContinuation", e);
        } else {
          await log("model", "error", "Continuation stream error: $e", sendRemote: false);
          if (_combinedResponse.isNotEmpty &&
              !M3xToolCallParser.looksLikeIncompleteToolCall(_combinedResponse)) {
            responseText = _combinedResponse;
            await addToContext();
            prompt.clear();

            final totalMs = cumulativeGenerationMs + (response.generationTimeMs?.toInt() ?? 0);
            final totalTokens = cumulativeTokenCount + (response.tokenCount?.toInt() ?? 0);
            final latency = totalMs > 0 ? totalMs : _generationStopwatch.elapsedMilliseconds;

            await logger.logAiGeneration(
              success: true,
              latencyMs: latency,
              tokensGenerated: totalTokens,
              finishReason: "timeout",
              modelVersion: _getModelVersion(),
              promptId: _getCurrentPromptId(),
              isMultimodal: _isCurrentSessionMultimodal,
            );
          } else {
            analyzeError("Continuation", e);
            await logger.logAiGeneration(
              success: false,
              latencyMs: _generationStopwatch.elapsedMilliseconds,
              errorType: _classifyError(e),
              errorCode: _extractErrorCode(e),
              finishReason: "error",
              modelVersion: _getModelVersion(),
              promptId: _getCurrentPromptId(),
              isMultimodal: _isCurrentSessionMultimodal,
            );
          }
        }
        genericRefresh();
      },
      onDone: () {
        if (myGenId != _streamGenerationId ||
            receivedTerminalEvent ||
            _activeToolHandling ||
            isContinuing ||
            _isSynthesizing) {
          return;
        }
        if (!isError) {
          isLoading = false;
          isGenerating = false;
          status = "Stream complete";
        }
        genericRefresh();
      },
    );

  }


  int _toolTurnCount = 0;
  String _lastToolCallSignature = "";

  Future<void> _commitSynthesisMessage(String message, {required String logNote}) async {
    isContinuing = false;
    isLoading = false;
    isGenerating = false;
    _isSynthesizing = false;
    status = "Done";
    responseText = message;
    await chatData.appendMessage(user: "Gemini", message: message);
    prompt.clear();
    lastPrompt = "";
    _currentSynthesisPrompt = "";
    await log("mesh", "info", logNote);
    await chatData.saveChat(chatData.context, chatID: chatData.currentChat);
    _checkAndTriggerTitle();
    try {
      scrollChatlog(const Duration(milliseconds: 250));
    } catch (_) {}
  }

  Future<void> _handleSynthesisToolCall(
    Map<String, dynamic> nextToolMap,
    String effectivePrompt,
  ) async {
    final nextCall = M3xToolCall.fromJson(nextToolMap);
    final nextSig = "${nextCall.tool}:${jsonEncode(nextCall.arguments)}";

    if (!_forcedFinalSynthesis && _toolTurnCount < 6 && nextSig != _lastToolCallSignature) {
      _isSynthesizing = false;
      await _handleToolCall(
        nextToolMap,
        originalPrompt: effectivePrompt,
        isFollowUpTurn: true,
      );
      return;
    }

    if (!_forcedFinalSynthesis) {
      await log(
        "mesh",
        "warning",
        "Suppressing follow-up tool call '${nextCall.tool}' (turns=$_toolTurnCount, duplicate=${nextSig == _lastToolCallSignature}); forcing tool-free synthesis.",
      );
      await _triggerToolSynthesis(
        _lastToolCall ?? nextCall,
        _lastToolResultPayload,
        userPrompt: effectivePrompt,
        forceFinalNoTools: true,
        toolErrorMessage: _lastToolFailed ? _lastToolErrorText : null,
      );
      return;
    }

    await log(
      "mesh",
      "error",
      "Model still emitted tool JSON despite forced tool-free synthesis; committing clean fallback.",
    );
    await _commitSynthesisMessage(
      _buildIncompleteToolFallback(),
      logNote: "Tool synthesis fallback committed",
    );
  }

  /// Handles agentic tool invocation across M3x mesh.
  Future<void> _handleToolCall(
    Map<String, dynamic> toolMap, {
    String originalPrompt = "",
    bool isFollowUpTurn = false,
  }) async {
    _toolTurnCount++;
    final call = M3xToolCall.fromJson(toolMap);
    _lastToolCall = call;
    final matchedTool = toolRegistry.get(call.tool);
    final effectiveApp = (call.app != null && call.app!.isNotEmpty)
        ? ((call.app!.contains('.') || matchedTool == null)
            ? call.app!
            : (matchedTool.packageName ?? call.app!))
        : (matchedTool?.packageName ?? matchedTool?.app ?? _selfPackageId);
    final canonEffectiveApp = canonicalExtensionId(effectiveApp);

    _lastToolCallSignature = "${call.tool}:${jsonEncode(call.arguments)}";

    await log("mesh", "info", "Detected tool call (#$_toolTurnCount): '${call.tool}' on app: '$effectiveApp' with arguments: ${jsonEncode(call.arguments)}");
    status = "Executing ${call.tool}...";
    isLoading = true;
    isGenerating = true;
    _isSynthesizing = true;
    notifyListeners();

    final toolResult = (canonEffectiveApp != _selfPackageId && !isExtensionEnabled(canonEffectiveApp))
        ? M3xToolResult.error(
            id: call.id,
            code: -32001,
            message: "Extension '$effectiveApp' is disabled in PAIOS settings.",
          )
        : await meshClient.callTool(
            effectiveApp,
            call.tool,
            call.arguments,
            callId: call.id,
          );

    final String resultPayload;
    String? toolErrorMessage;
    bool allowSelfCorrection = false;
    final String toolResultEntry;
    final String? softError =
        toolResult.isSuccess ? _extractSoftToolError(toolResult.result) : null;

    if (!toolResult.isSuccess || softError != null) {
      final errMsg = !toolResult.isSuccess
          ? (toolResult.error?.message ?? 'Unknown tool error')
          : softError!;
      final bool isInfra = _isInfrastructureToolError(errMsg);
      _lastToolFailed = true;
      _lastToolErrorText = errMsg;
      _lastToolErrorIsInfra = isInfra;
      toolErrorMessage = errMsg;

      if (isInfra) {
        resultPayload = jsonEncode({'error': errMsg, 'app': effectiveApp});
        toolResultEntry =
            "[TOOL ERROR — DATA UNAVAILABLE] Calling '${call.tool}' on '$effectiveApp' FAILED: $errMsg";
      } else {
        allowSelfCorrection = _recoverableErrorRetries == 0 && _toolTurnCount < 3;
        if (allowSelfCorrection) {
          _recoverableErrorRetries++;
        }
        resultPayload = !toolResult.isSuccess
            ? jsonEncode(toolResult.error?.toJson() ?? {'error': errMsg})
            : jsonEncode(toolResult.result ?? {'error': errMsg});
        toolResultEntry = allowSelfCorrection
            ? "[TOOL ERROR — PARAMETER] Calling '${call.tool}' failed: $errMsg"
            : "[TOOL ERROR — DATA UNAVAILABLE] Calling '${call.tool}' failed: $errMsg";
      }
      await log("mesh", "error", "Tool '${call.tool}' failed (infra=$isInfra, retry=$allowSelfCorrection): $resultPayload");
    } else {
      _lastToolFailed = false;
      _lastToolErrorText = "";
      _lastToolErrorIsInfra = false;
      resultPayload = jsonEncode(toolResult.result ?? {});
      toolResultEntry = "[TOOL RESULT: $resultPayload]";
      await log("mesh", "info", "Tool '${call.tool}' succeeded: $resultPayload");
    }
    _lastToolResultPayload = resultPayload;

    final effectiveOriginalPrompt = originalPrompt.isNotEmpty
        ? originalPrompt
        : (lastPrompt.isNotEmpty ? lastPrompt : prompt.text.trim());

    if (!isFollowUpTurn) {
      await chatData.appendMessage(
        user: "User",
        message: effectiveOriginalPrompt,
        imagePath: chatData.lastImagePath,
      );
      chatData.lastImagePath = null;
      lastPrompt = ""; // Clear lastPrompt / mark pending turn committed so it doesn't duplicate in the UI
    }

    await chatData.appendMessage(user: "Gemini", message: responseText);
    await chatData.appendMessage(user: "System", message: toolResultEntry);

    // Trigger second-stage continuation/synthesis so Gemini Nano explains the result in natural language.
    // On infrastructure errors or exhausted parameter retries, disable tools so the model reports the failure cleanly.
    // On first-turn recoverable parameter errors, allow 1 self-correction turn with tools enabled.
    await _triggerToolSynthesis(
      call,
      resultPayload,
      userPrompt: effectiveOriginalPrompt,
      forceFinalNoTools: toolErrorMessage != null && !allowSelfCorrection,
      toolErrorMessage: toolErrorMessage,
      isRecoverableError: allowSelfCorrection,
    );
  }

  /// Synthesizes tool execution result into conversational natural language.
  Future<void> _triggerToolSynthesis(
    M3xToolCall call,
    String resultPayload, {
    String userPrompt = "",
    bool forceFinalNoTools = false,
    String? toolErrorMessage,
    bool isRecoverableError = false,
  }) async {
    final int myGenId = ++_streamGenerationId;
    bool receivedTerminalEvent = false;
    _forcedFinalSynthesis = forceFinalNoTools;
    status = "Synthesizing answer...";
    isLoading = true;
    isGenerating = true;
    isContinuing = false;
    _isSynthesizing = true;
    responseText = "";
    _lastFinishReason = "";
    _continuationCount = 0;
    _combinedResponse = "";
    notifyListeners();

    await _aiSubscription?.cancel();

    // Re-initialize engine to ensure context includes the tool result (and strip tools if forcing final prose)
    await initEngine(includeTools: !forceFinalNoTools);
    if (myGenId != _streamGenerationId) return;

    final effectivePrompt = userPrompt.isNotEmpty
        ? userPrompt
        : (_currentUserPromptForSynthesis.isNotEmpty ? _currentUserPromptForSynthesis : lastPrompt);
    _currentUserPromptForSynthesis = effectivePrompt;
    final String langInstruction;
    if (shareLocale) {
      langInstruction = "Respond in ${dict.value("current_language")}.\n";
    } else {
      langInstruction = "Respond in the same language as \"$effectivePrompt\".\n";
    }

    if (toolErrorMessage != null && !isRecoverableError) {
      _currentSynthesisPrompt =
          "User question: \"$effectivePrompt\"\n\n"
          "Live data could not be retrieved because '${call.tool}' on '${call.app ?? 'mesh'}' failed: $toolErrorMessage\n\n"
          "$langInstruction"
          "Explain clearly in plain natural language that live data from '${call.app ?? 'the connected app'}' could not be retrieved right now and include the error reason. "
          "Do not invent results, do not claim everything is normal or there are no incidents, and do not output JSON.";
    } else if (toolErrorMessage != null && isRecoverableError) {
      _currentSynthesisPrompt =
          "User question: \"$effectivePrompt\"\n\n"
          "Tool output from ${call.tool}: $resultPayload\n\n"
          "$langInstruction"
          "${_buildRecoverableErrorHint(call.tool, toolErrorMessage)}";
    } else if (forceFinalNoTools) {
      _currentSynthesisPrompt =
          "User question: \"$effectivePrompt\"\n\n"
          "Live data from ${call.tool}:\n"
          "$resultPayload\n\n"
          "$langInstruction"
          "Summarize these results clearly in natural, conversational sentences to answer the user's question. Reply in plain prose only.";
    } else {
      _currentSynthesisPrompt =
          "User question: \"$effectivePrompt\"\n\n"
          "Live data from ${call.tool}:\n"
          "$resultPayload\n\n"
          "$langInstruction"
          "Answer the user's question directly in natural, conversational sentences using the live data above. "
          "Call a different tool only if another lookup with different arguments is still needed; never repeat ${call.tool} with the same arguments.";
    }

    final double runTemperature = chatData.chats.containsKey(currentChat) && chatData.chats[currentChat].containsKey("chatTemperature")
        ? chatData.chats[currentChat]["chatTemperature"]
        : temperature;

    final stream = gemini.generateTextEvents(
      prompt: _currentSynthesisPrompt,
      config: GenerationConfig(temperature: runTemperature),
      stream: true,
    );

    _aiSubscription = stream.listen(
      (AiEvent event) async {
        if (myGenId != _streamGenerationId) return;
        switch (event.status) {
          case AiEventStatus.loading:
            isLoading = true;
            status = "Synthesizing response...";
            notifyListeners();
            break;

          case AiEventStatus.streaming:
            isLoading = true;
            status = "Streaming response...";
            final String? fr = event.response?.finishReason;
            if (fr != null && fr != "null" && fr.isNotEmpty) {
              _lastFinishReason = fr;
            }
            if (event.response != null) {
              response = event.response!;
              responseText = event.response!.text;
              _combinedResponse = responseText;
            }
            try {
              scrollChatlog(const Duration(milliseconds: 250));
            } catch (_) {}
            break;

          case AiEventStatus.done:
            receivedTerminalEvent = true;
            final nextToolMap = M3xToolCallParser.extract(responseText);
            if (nextToolMap != null) {
              _activeToolHandling = true;
              try {
                await _handleSynthesisToolCall(nextToolMap, effectivePrompt);
              } finally {
                _activeToolHandling = false;
              }
              break;
            }

            final String? doneReason = _lastFinishReason.isNotEmpty
                ? _lastFinishReason
                : event.reason;
            final bool shouldContinue = _shouldContinueOnDone(doneReason, responseText);

            if (shouldContinue) {
              cumulativeGenerationMs += response.generationTimeMs?.toInt() ?? 0;
              cumulativeTokenCount += response.tokenCount?.toInt() ?? 0;
              _continuationCount++;
              _combinedResponse = responseText;
              isContinuing = true;
              await log("model", "info", "Tool synthesis interrupted (reason=$doneReason), triggering continuation #$_continuationCount", sendRemote: false);
              if (kDebugMode) print("[AUTO-CONTINUE #$_continuationCount] tool synthesis reason=$doneReason");
              await continueGenerating(isSynthesis: true);
            } else if (!forceFinalNoTools &&
                _looksLikeUnformattedToolEcho(responseText)) {
              await log(
                "mesh",
                "warning",
                "Synthesis returned empty or echoed tool wrapper; retrying with tool-free prose synthesis.",
              );
              await _triggerToolSynthesis(
                _lastToolCall ?? call,
                _lastToolResultPayload,
                userPrompt: effectivePrompt,
                forceFinalNoTools: true,
                toolErrorMessage: _lastToolFailed ? _lastToolErrorText : null,
                isRecoverableError: false,
              );
            } else {
              final bool badOutput =
                  M3xToolCallParser.looksLikeIncompleteToolCall(responseText) ||
                      _looksLikeUnformattedToolEcho(responseText) ||
                      _looksLikeHallucinatedNormalOnError(responseText);
              final finalMessage =
                  badOutput ? _buildIncompleteToolFallback() : responseText;
              await _commitSynthesisMessage(
                finalMessage,
                logNote: badOutput
                    ? "Tool synthesis plain-text fallback committed"
                    : "Tool synthesis complete",
              );
            }
            break;

          case AiEventStatus.error:
            receivedTerminalEvent = true;
            isLoading = false;
            isContinuing = false;
            isGenerating = false;
            _isSynthesizing = false;
            isError = true;
            status = "Error";
            responseText = event.error ?? "Error during tool synthesis";
            await log("mesh", "error", responseText);
            break;
        }
        genericRefresh();
      },
      onError: (e) async {
        if (myGenId != _streamGenerationId) return;
        receivedTerminalEvent = true;
        isLoading = false;
        isContinuing = false;
        isGenerating = false;
        _isSynthesizing = false;
        await log("mesh", "error", "Synthesis error: $e");
        analyzeError("Synthesis", e);
        genericRefresh();
      },
      onDone: () {
        if (myGenId != _streamGenerationId ||
            receivedTerminalEvent ||
            _activeToolHandling ||
            isContinuing ||
            _isSynthesizing) {
          return;
        }
        if (!isError) {
          isLoading = false;
          isGenerating = false;
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
