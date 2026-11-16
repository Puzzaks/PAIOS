import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as md;
import 'package:flutter/services.dart';
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
import 'package:geminilocal/services/internal_tools_service.dart';

class PaiosModelVariant {
  final String releaseStage;
  final String preference;
  final int statusCode;
  final String status;
  final bool available;
  final String? baseModelName;
  final bool isActive;

  const PaiosModelVariant({
    required this.releaseStage,
    required this.preference,
    required this.statusCode,
    required this.status,
    required this.available,
    this.baseModelName,
    this.isActive = false,
  });

  bool get isDownloadable => status == 'downloadable';
  bool get isDownloading => status == 'downloading';
  bool get isUnavailable => status == 'unavailable';
  bool get isSwitchable => !isUnavailable;

  String get authorLabel => AIEngine.formatNanoAuthor({
        if (baseModelName != null) 'baseModelName': baseModelName,
      });

  String get internalModelName {
    final raw = baseModelName?.trim();
    if (raw == null ||
        raw.isEmpty ||
        raw.toLowerCase() == 'null' ||
        raw.toLowerCase() == 'unknown') {
      return '$releaseStage-$preference';
    }
    final lower = raw.toLowerCase();
    if (lower.startsWith('nano-')) {
      return 'gemini-$lower';
    }
    if (lower.contains('gemini-')) {
      return lower;
    }
    return lower;
  }

  PaiosModelVariant copyWith({
    String? releaseStage,
    String? preference,
    int? statusCode,
    String? status,
    bool? available,
    String? baseModelName,
    bool? isActive,
  }) {
    return PaiosModelVariant(
      releaseStage: releaseStage ?? this.releaseStage,
      preference: preference ?? this.preference,
      statusCode: statusCode ?? this.statusCode,
      status: status ?? this.status,
      available: available ?? this.available,
      baseModelName: baseModelName ?? this.baseModelName,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, dynamic> toMap() => {
        'releaseStage': releaseStage,
        'preference': preference,
        'statusCode': statusCode,
        'status': status,
        'available': available,
        'baseModelName': baseModelName,
        'internalModelName': internalModelName,
        'authorLabel': authorLabel,
        'isActive': isActive,
        'isSwitchable': isSwitchable,
        'isDownloadable': isDownloadable,
        'isDownloading': isDownloading,
      };

  factory PaiosModelVariant.fromMap(Map<dynamic, dynamic> map) {
    final stage = AppConfig.normalizeReleaseStage(map['releaseStage']);
    final pref = AppConfig.normalizePreference(map['preference']);
    final rawStatus = map['status']?.toString().trim().toLowerCase();
    final rawCode = map['statusCode'];
    final int code = rawCode is num
        ? rawCode.toInt()
        : switch (rawStatus) {
            'available' => 3,
            'downloading' => 2,
            'downloadable' => 1,
            _ => (map['available'] == true ? 3 : 0),
          };
    final String status = (rawStatus != null &&
            (rawStatus == 'available' ||
                rawStatus == 'downloadable' ||
                rawStatus == 'downloading' ||
                rawStatus == 'unavailable'))
        ? rawStatus
        : switch (code) {
            3 => 'available',
            2 => 'downloading',
            1 => 'downloadable',
            _ => 'unavailable',
          };
    final bool avail = map['available'] is bool
        ? map['available'] as bool
        : (status == 'available' || code == 3);
    final rawName = map['baseModelName']?.toString().trim();
    final String? name = (rawName != null &&
            rawName.isNotEmpty &&
            rawName.toLowerCase() != 'null' &&
            rawName.toLowerCase() != 'unknown')
        ? rawName
        : null;
    final bool active = map['isActive'] == true;
    return PaiosModelVariant(
      releaseStage: stage,
      preference: pref,
      statusCode: code,
      status: status,
      available: avail,
      baseModelName: name,
      isActive: active,
    );
  }
}

class PaiosVariantDownloadState {
  final String releaseStage;
  final String preference;
  final String variantKey;
  final String status;
  final int bytesDownloaded;
  final int totalBytes;
  final double bytesPerSec;
  final String? error;

  const PaiosVariantDownloadState({
    required this.releaseStage,
    required this.preference,
    String? variantKey,
    this.status = 'idle',
    this.bytesDownloaded = 0,
    this.totalBytes = 0,
    this.bytesPerSec = 0.0,
    this.error,
  }) : variantKey = variantKey ?? '$releaseStage:$preference';

  double get progress {
    if (status == 'completed') return 1.0;
    if (totalBytes <= 0 || bytesDownloaded <= 0) return 0.0;
    return (bytesDownloaded / totalBytes).clamp(0.0, 1.0);
  }

  int get remainingBytes {
    if (totalBytes <= 0) return 0;
    final diff = totalBytes - bytesDownloaded;
    return diff > 0 ? diff : 0;
  }

  bool get isDownloading => status == 'started' || status == 'downloading';
  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';

  PaiosVariantDownloadState copyWith({
    String? releaseStage,
    String? preference,
    String? variantKey,
    String? status,
    int? bytesDownloaded,
    int? totalBytes,
    double? bytesPerSec,
    String? error,
    bool clearError = false,
  }) {
    final nextStage = releaseStage ?? this.releaseStage;
    final nextPref = preference ?? this.preference;
    return PaiosVariantDownloadState(
      releaseStage: nextStage,
      preference: nextPref,
      variantKey: variantKey ?? '$nextStage:$nextPref',
      status: status ?? this.status,
      bytesDownloaded: bytesDownloaded ?? this.bytesDownloaded,
      totalBytes: totalBytes ?? this.totalBytes,
      bytesPerSec: bytesPerSec ?? this.bytesPerSec,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class AIEngine with md.ChangeNotifier {
  final gemini = GeminiNano();
  static const MethodChannel _localAiChannel = MethodChannel('flutter_local_ai');
  final toolRegistry = M3xToolRegistry();
  final docService = DocService.instance;
  late final InternalToolsService internalToolsService =
      InternalToolsService(isModuleEnabled: isExtensionEnabled);
  static const MethodChannel _meshHostChannel =
      MethodChannel('page.puzzak.paios/mesh');
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
  String currentThoughtChunk = "";
  String _rawThoughtChunk = "";
  DateTime? streamingMessageTime;
  DateTime? streamingUserMessageTime;
  bool isLoading = false;
  bool isAvailable = false;
  bool isInitialized = false;
  bool isInitializing = false;
  bool isSwitchingModelConfig = false;
  bool isDownloadingModel = false;
  static const int maxDownloadErrorRetries = 2;
  bool _unavailableToastShown = false;
  int _downloadErrorRetryCount = 0;
  @visibleForTesting
  int get downloadErrorRetryCount => _downloadErrorRetryCount;
  bool _lateNetCheckRunning = false;
  bool _lateProgressCheckRunning = false;
  bool _disposed = false;
  StreamSubscription<dynamic>? _statusSubscription;
  String status = "";
  bool isError = false;

  bool appStarted = false;
  String testPrompt = "";
  Map modelInfo = {};
  List modelDownloadLog = [];
  final Map<String, PaiosVariantDownloadState> variantDownloads = {};
  final Map<String, List<({int timeMs, int bytes})>> _downloadSpeedSamples = {};
  bool ignoreContext = false;
  bool isContinuing = false;
  bool isGenerating = false;
  bool _isSynthesizing = false; // true when synthesizing tool call response
  bool get isSynthesizing => _isSynthesizing;
  String _currentSynthesisPrompt = "";
  Uint8List? pendingImageBytes;
  String? pendingImageName;
  static const int maxContinuations = 10;
  static const int maxProseContinuations = 3;
  static const int maxToolJsonContinuations = 1;
  static const int maxProseSoftStopChars = 1600;
  static const int maxProseHardStopChars = 2400;
  static const int maxContinuationChars = 12000;
  static const int maxNullReasonContinuations = 3;
  static const int maxStopCutoffContinuations = 1;
  static const int maxEmptyStreamRetries = 1;

  String _lastFinishReason = ""; // captured from streaming events, read at done
  String _combinedResponse = ""; // accumulates across continuation calls
  String get combinedResponse => _combinedResponse; // read-only access for UI
  int _continuationCount = 0;    // how many continuations fired (for logging)
  int _nullReasonContinuationCount = 0;
  int _stopCutoffContinuationCount = 0;
  int _emptyStreamRetryCount = 0;
  int _streamGenerationId = 0;   // invalidates stale onDone/onError callbacks across streams
  bool _activeToolHandling = false;
  bool _forcedFinalSynthesis = false;
  bool _toolFreeFallbackUsed = false;
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

  final Stopwatch _generationStopwatch = Stopwatch();
  bool _isCurrentSessionMultimodal = false;
  Uint8List? _turnImageBytesForMemory;
  String? _turnImagePathForMemory;
  String? _turnChatIdForMemory;
  bool _isCapturingVisualMemory = false;

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

  /// Checks whether an internal or external mesh extension / package is permitted to run.
  /// Internal modules use `InternalToolsService.defaultEnabledForModule`
  /// (offline docs/device default `true`, online modules default `false`).
  /// First-party apps (`page.puzzak.*`, `com.puzzak.*`) are enabled by default.
  /// Third-party apps default to the state of `mesh_allow_all_new` (default `false`).
  bool isExtensionEnabled(String appPackage) {
    final internalMod = InternalToolsService.moduleById(appPackage);
    if (internalMod != null) {
      if (Hive.isBoxOpen('paios_storage')) {
        final box = Hive.box('paios_storage');
        final key = InternalToolsService.prefKeyForModule(internalMod.id);
        if (box.containsKey(key)) {
          return box.get(key) == true;
        }
      }
      return internalMod.defaultEnabled;
    }
    final canon = canonicalExtensionId(appPackage);
    if (canon == _selfPackageId) return true;
    if (!Hive.isBoxOpen('paios_storage')) return false;
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

  bool isInternalModuleEnabled(String moduleId) {
    final mod = InternalToolsService.moduleById(moduleId);
    if (mod == null) return false;
    return isExtensionEnabled(mod.id);
  }

  bool isToolModuleEnabled(String toolName) {
    final mod = InternalToolsService.moduleForTool(toolName);
    if (mod == null) return true;
    return isExtensionEnabled(mod.id);
  }

  Future<void> setExtensionEnabled(String appPackage, bool enabled) async {
    final internalMod = InternalToolsService.moduleById(appPackage);
    final canon = internalMod != null
        ? internalMod.id
        : canonicalExtensionId(appPackage);
    if (Hive.isBoxOpen('paios_storage')) {
      final box = Hive.box('paios_storage');
      await box.put('mesh_extension_${canon}_enabled', enabled);
    }
    _syncInternalToolRegistrations();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('mesh_extension_${canon}_enabled', enabled);
      if (canon != appPackage && internalMod == null) {
        await prefs.setBool('mesh_extension_${appPackage}_enabled', enabled);
      }
    } catch (_) {}
    await _syncLocalToolRegistrations();
    notifyListeners();
  }

  Future<void> _syncInternalModulePreferences() async {
    try {
      if (!Hive.isBoxOpen('paios_storage')) return;
      final box = Hive.box('paios_storage');
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 2));
      for (final mod in InternalToolsService.modules) {
        final key = mod.prefKey;
        if (box.containsKey(key)) {
          final val = box.get(key) == true;
          if (prefs.getBool(key) != val) {
            await prefs.setBool(key, val);
          }
        } else if (prefs.containsKey(key)) {
          final val = prefs.getBool(key) ?? mod.defaultEnabled;
          await box.put(key, val);
        }
      }
    } catch (_) {}
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

  bool _modelBool(String key, {bool defaultValue = false}) {
    if (!modelInfo.containsKey(key) || modelInfo[key] == null) {
      return defaultValue;
    }
    final val = modelInfo[key];
    if (val is bool) return val;
    if (val is num) return val != 0;
    final str = val.toString().trim().toLowerCase();
    if (str.isEmpty || str == "null") return defaultValue;
    return str == "true" || str == "1";
  }

  bool get isAICoreBeta => _modelBool("isBeta");
  String get aicorePackageVersion =>
      modelInfo["aicoreVersion"]?.toString() ?? "Unknown";
  bool get isAICoreInstalled => _modelBool("aicoreInstalled");

  String get modelReleaseStage => config.modelReleaseStage;
  String get modelPreference => config.modelPreference;
  bool get enableThinking => config.enableThinking;
  bool get isNanoV4Active => _modelBool("isNanoV4");
  bool get isThinkingModeAvailable => _modelBool("isThinkingModeAvailable");
  bool get isSystemPromptAvailable => _modelBool("isSystemPromptAvailable");
  bool get isCachingAvailable => _modelBool("isCachingAvailable");
  bool get fellBackToStable => _modelBool("fellBackToStable");
  bool get isStableFastAvailable =>
      _modelBool("stableFastAvailable", defaultValue: true);
  bool get isPreviewAvailable =>
      _modelBool("previewAvailable", defaultValue: true);
  bool get isPreviewFastAvailable =>
      _modelBool("previewFastAvailable", defaultValue: true);
  bool get isPreviewFullAvailable =>
      _modelBool("previewFullAvailable", defaultValue: true);
  bool get isFastAvailable => _modelBool("fastAvailable", defaultValue: true);

  bool get isFastAvailableForSelectedChannel {
    if (modelReleaseStage == 'preview') {
      return modelInfo.containsKey('previewFastAvailable')
          ? isPreviewFastAvailable
          : isFastAvailable;
    }
    return modelInfo.containsKey('stableFastAvailable')
        ? isStableFastAvailable
        : isFastAvailable;
  }

  bool get isFullAvailableForSelectedChannel {
    if (modelReleaseStage == 'preview') {
      return isPreviewFullAvailable;
    }
    return true;
  }

  Future<bool> _syncConfigWithModelCapabilities() async {
    bool changed = false;
    final syncedStage = AppConfig.normalizeReleaseStage(
      modelInfo["releaseStage"] ?? config.modelReleaseStage,
    );
    final syncedPref = AppConfig.normalizePreference(
      modelInfo["preference"] ?? config.modelPreference,
    );

    if (!fellBackToStable &&
        syncedStage == config.modelReleaseStage &&
        syncedPref != config.modelPreference) {
      config.modelPreference = syncedPref;
      changed = true;
    } else if (config.modelReleaseStage == 'stable' &&
        config.modelPreference == 'fast' &&
        !isFastAvailableForSelectedChannel) {
      config.modelPreference = 'full';
      changed = true;
    } else if (config.modelReleaseStage == 'preview' &&
        config.modelPreference == 'full' &&
        !isFullAvailableForSelectedChannel &&
        isFastAvailableForSelectedChannel) {
      config.modelPreference = 'fast';
      changed = true;
    }

    if (changed) {
      await config.saveModelConfig();
    }
    return changed;
  }
  String get modelFeatureStatus =>
      (modelInfo["status"]?.toString() ?? "unavailable").toLowerCase();

  bool get _isRawModelInfoUnavailable {
    if (modelInfo.isEmpty) return false;
    final statusStr = modelInfo['status']?.toString().trim().toLowerCase();
    final availableVal = modelInfo['available'];
    final isExplicitlyFalse = availableVal == false ||
        availableVal?.toString().trim().toLowerCase() == 'false';
    final statusCodeVal = modelInfo['statusCode'];
    final isZeroStatusCode = statusCodeVal == 0 ||
        statusCodeVal?.toString().trim() == '0';
    final isDownloadState = statusStr == 'downloadable' ||
        statusStr == 'downloading' ||
        statusCodeVal == 1 ||
        statusCodeVal == 2 ||
        statusCodeVal?.toString().trim() == '1' ||
        statusCodeVal?.toString().trim() == '2';
    return !isDownloadState &&
        (isExplicitlyFalse ||
            statusStr == 'unavailable' ||
            isZeroStatusCode);
  }

  bool get hasAnySupportedModel {
    if (modelInfo.containsKey('hasAnySupportedModel') &&
        modelInfo['hasAnySupportedModel'] != null &&
        _modelBool('hasAnySupportedModel')) {
      return true;
    }
    return modelVariants.any((v) => !v.isUnavailable);
  }

  bool get hasAnyAvailableModel {
    if (modelInfo.containsKey('hasAnyAvailableModel') &&
        modelInfo['hasAnyAvailableModel'] != null &&
        _modelBool('hasAnyAvailableModel')) {
      return true;
    }
    return modelVariants.any((v) => v.available);
  }

  bool get _hasInitializationProbed =>
      modelInfo.isNotEmpty || modelDownloadLog.isNotEmpty || isInitialized;

  bool get isAiCoreKnownUnavailable {
    if (!_hasInitializationProbed) return false;
    if (hasAnySupportedModel) return false;
    if (_isRawModelInfoUnavailable) return true;
    if (modelDownloadLog.isNotEmpty) {
      final last = modelDownloadLog.last;
      if (last is Map) {
        final logStatus = last['status']?.toString().trim().toLowerCase();
        final logInfo = last['info']?.toString().trim().toLowerCase();
        final logValue = last['value']?.toString().trim().toLowerCase();
        if (logStatus == 'error' &&
            (logInfo == 'aicore' || logValue == 'unavailable')) {
          return true;
        }
      }
    }
    return false;
  }

  bool get isAiCoreAvailable => !isAiCoreKnownUnavailable;

  String lastAiCoreError = "";
  String unsupportedReason = "";

  static final RegExp _featureNotFound606Regex = RegExp(
    r'(?:\b606\b|feature[_\s-]*not[_\s-]*found)',
    caseSensitive: false,
  );

  static bool _matchesFeatureNotFound606(dynamic raw) {
    if (raw == null) return false;
    final text = raw.toString().trim();
    if (text.isEmpty) return false;
    return _featureNotFound606Regex.hasMatch(text);
  }

  /// Returns `true` when AICore / ML Kit GenAI reported `ErrorCode 606`
  /// (`FEATURE_NOT_FOUND`), indicating the AICore system stub is installed
  /// without a provisioned on-device Gemini Nano model catalog.
  bool get isAiCoreFeatureNotFoundError {
    if (_matchesFeatureNotFound606(lastAiCoreError) ||
        _matchesFeatureNotFound606(unsupportedReason) ||
        _matchesFeatureNotFound606(status)) {
      return true;
    }
    for (final key in const [
      'error',
      'downloadError',
      'unsupportedReason',
      'lastAiCoreError',
      'version',
      'status',
      'statusCode',
    ]) {
      if (_matchesFeatureNotFound606(modelInfo[key])) {
        return true;
      }
    }
    for (final entry in modelDownloadLog) {
      if (entry is Map) {
        if (_matchesFeatureNotFound606(entry['status']) ||
            _matchesFeatureNotFound606(entry['info']) ||
            _matchesFeatureNotFound606(entry['value'])) {
          return true;
        }
      } else if (_matchesFeatureNotFound606(entry)) {
        return true;
      }
    }
    for (final dl in variantDownloads.values) {
      if (_matchesFeatureNotFound606(dl.error)) {
        return true;
      }
    }
    for (final entry in logs) {
      if (entry['name'] == 'model' &&
          entry['type'] == 'error' &&
          _matchesFeatureNotFound606(entry['message'])) {
        return true;
      }
    }
    return false;
  }

  String _unavailableStatusMessage() {
    if (isAiCoreFeatureNotFoundError) {
      final hint = dict.value("aicore_error_606_hint");
      if (hint.isNotEmpty &&
          hint != "Loading..." &&
          hint != "aicore_error_606_hint" &&
          !hint.startsWith("!!!")) {
        return hint;
      }
    }
    final translated = dict.value("intro_aicore_unsupported_desc");
    if (translated.isNotEmpty &&
        translated != "Loading..." &&
        translated != "intro_aicore_unsupported_desc" &&
        !translated.startsWith("!!!")) {
      return translated;
    }
    return "Google AICore with Gemini Nano is currently unavailable on this device.";
  }

  String _unavailableToastText() {
    final val = dict.value("unavailable");
    if (val.isEmpty ||
        val == "Loading..." ||
        val == "unavailable" ||
        val.startsWith("!!!")) {
      return "Gemini Nano is unavailable";
    }
    return "Gemini Nano $val";
  }

  Future<void> _showToast(String msg) async {
    try {
      await Fluttertoast.showToast(
        msg: msg,
        toastLength: Toast.LENGTH_SHORT,
        fontSize: 16.0,
      ).timeout(const Duration(seconds: 2));
    } catch (_) {}
  }
  bool get effectiveEnableThinking =>
      (isNanoV4Active || isThinkingModeAvailable) ? true : config.enableThinking;

  String get activeModelName {
    final raw = modelInfo["baseModelName"]?.toString().trim();
    if (raw != null && raw.isNotEmpty && raw != "null") return raw;
    return "Gemini Nano";
  }

  String get activeReleaseStage {
    final raw = modelInfo["releaseStage"]?.toString().trim();
    if (raw != null && raw.isNotEmpty && raw != "null") return raw;
    return config.modelReleaseStage;
  }

  String get activePreference {
    final raw = modelInfo["preference"]?.toString().trim();
    if (raw != null && raw.isNotEmpty && raw != "null") return raw;
    return config.modelPreference;
  }

  static final RegExp _nanoV4Regex = RegExp(
    r'(?:^|[^a-z0-9])(v4|nano[\s\-_]?4)(?:[^a-z0-9]|$)',
    caseSensitive: false,
  );
  static final RegExp _nanoV3Regex = RegExp(
    r'(?:^|[^a-z0-9])(v3|nano[\s\-_]?3)(?:[^a-z0-9]|$)',
    caseSensitive: false,
  );
  static final RegExp _nanoV2Regex = RegExp(
    r'(?:^|[^a-z0-9])(v2|nano[\s\-_]?2)(?:[^a-z0-9]|$)',
    caseSensitive: false,
  );
  static final RegExp _generalNanoVersionRegex = RegExp(
    r'v?(\d+(?:\.\d+)?)',
    caseSensitive: false,
  );

  /// Formats a human-friendly assistant author string such as `"Gemini Nano v4"`
  /// or `"Gemini Nano v3"` from a `modelInfo` capability map.
  static String formatNanoAuthor(Map? modelInfo) {
    if (modelInfo == null || modelInfo.isEmpty) return 'Gemini Nano';
    final rawIsV4 = modelInfo['isNanoV4'];
    final bool isV4 = rawIsV4 == true ||
        rawIsV4 == 1 ||
        rawIsV4?.toString().trim().toLowerCase() == 'true';
    if (isV4) return 'Gemini Nano v4';

    final statusStr = modelInfo['status']?.toString().trim().toLowerCase() ?? '';
    final candidates = <String>[
      modelInfo['baseModelName']?.toString().trim() ?? '',
      if (statusStr != 'error') modelInfo['version']?.toString().trim() ?? '',
    ];

    for (final raw in candidates) {
      if (raw.isEmpty) continue;
      final lower = raw.toLowerCase();
      if (lower == 'null' ||
          lower == 'unknown' ||
          lower == 'not installed' ||
          lower.startsWith('null response')) {
        continue;
      }
      if (_nanoV4Regex.hasMatch(raw)) return 'Gemini Nano v4';
      if (_nanoV3Regex.hasMatch(raw)) return 'Gemini Nano v3';
      if (_nanoV2Regex.hasMatch(raw)) return 'Gemini Nano v2';
      final match = _generalNanoVersionRegex.firstMatch(raw);
      if (match != null) {
        final ver = match.group(1);
        if (ver != null && ver.isNotEmpty) {
          return 'Gemini Nano v$ver';
        }
      }
    }
    return 'Gemini Nano';
  }

  String get assistantAuthorLabel => formatNanoAuthor(modelInfo);

  static int _compareVariants(PaiosModelVariant a, PaiosModelVariant b) {
    final stageA = a.releaseStage == 'stable' ? 0 : 1;
    final stageB = b.releaseStage == 'stable' ? 0 : 1;
    if (stageA != stageB) return stageA.compareTo(stageB);
    final prefA = a.preference == 'full' ? 0 : 1;
    final prefB = b.preference == 'full' ? 0 : 1;
    return prefA.compareTo(prefB);
  }

  static bool _hasVariantDistinction(String internalName) {
    return internalName.contains('fast') || internalName.contains('full');
  }

  static bool _isNanoV4InternalName(String internalName) {
    return _nanoV4Regex.hasMatch(internalName);
  }

  /// All 4 standard Gemini Nano variants (`stable/full`, `stable/fast`,
  /// `preview/full`, `preview/fast`) sorted by readiness and preference.
  List<PaiosModelVariant> get modelVariants {
    final rawVariants = modelInfo['modelVariants'];
    if (rawVariants is List && rawVariants.isNotEmpty) {
      final parsed = rawVariants
          .whereType<Map>()
          .map((m) => PaiosModelVariant.fromMap(m))
          .toList();
      if (parsed.isNotEmpty) {
        parsed.sort(_compareVariants);
        return List.unmodifiable(parsed);
      }
    }

    if (modelInfo.isEmpty) return const [];

    final currentStage = AppConfig.normalizeReleaseStage(
      modelInfo['releaseStage'] ?? config.modelReleaseStage,
    );
    final currentPref = AppConfig.normalizePreference(
      modelInfo['preference'] ?? config.modelPreference,
    );
    final rawStatus = modelInfo['status']?.toString().trim().toLowerCase();
    final activeAvailable = _modelBool('available') || rawStatus == 'available';
    final activeStatus = (rawStatus != null &&
            (rawStatus == 'available' ||
                rawStatus == 'downloadable' ||
                rawStatus == 'downloading' ||
                rawStatus == 'unavailable'))
        ? rawStatus
        : (activeAvailable ? 'available' : 'unavailable');
    final activeCode = modelInfo['statusCode'] is num
        ? (modelInfo['statusCode'] as num).toInt()
        : switch (activeStatus) {
            'available' => 3,
            'downloading' => 2,
            'downloadable' => 1,
            _ => 0,
          };
    final activeNameRaw = (modelInfo['baseModelName'] ??
            (rawStatus != 'error' ? modelInfo['version'] : null))
        ?.toString()
        .trim();
    final activeName = (activeNameRaw != null &&
            activeNameRaw.isNotEmpty &&
            activeNameRaw.toLowerCase() != 'null' &&
            activeNameRaw.toLowerCase() != 'unknown')
        ? activeNameRaw
        : null;

    PaiosModelVariant buildLegacy(String stage, String pref) {
      final isCurrent = stage == currentStage && pref == currentPref;
      if (isCurrent) {
        return PaiosModelVariant(
          releaseStage: stage,
          preference: pref,
          statusCode: activeCode,
          status: activeStatus,
          available: activeCode == 3 || activeStatus == 'available',
          baseModelName: activeName,
          isActive: true,
        );
      }
      final bool comboAvailable;
      if (stage == 'stable' && pref == 'full') {
        comboAvailable = !_isRawModelInfoUnavailable;
      } else if (stage == 'stable' && pref == 'fast') {
        comboAvailable = modelInfo['stableFastAvailable'] == true ||
            (currentStage == 'stable' && modelInfo['fastAvailable'] == true);
      } else if (stage == 'preview' && pref == 'full') {
        comboAvailable = modelInfo['previewFullAvailable'] == true;
      } else {
        comboAvailable = modelInfo['previewFastAvailable'] == true ||
            (currentStage == 'preview' && modelInfo['fastAvailable'] == true);
      }
      return PaiosModelVariant(
        releaseStage: stage,
        preference: pref,
        statusCode: comboAvailable ? 3 : 0,
        status: comboAvailable ? 'available' : 'unavailable',
        available: comboAvailable,
        baseModelName: null,
        isActive: false,
      );
    }

    final synthesized = <PaiosModelVariant>[
      buildLegacy('stable', 'full'),
      buildLegacy('stable', 'fast'),
      buildLegacy('preview', 'full'),
      buildLegacy('preview', 'fast'),
    ]..sort(_compareVariants);
    return List.unmodifiable(synthesized);
  }

  /// Switchable/downloadable model variants in fixed hardware order, collapsing
  /// duplicate same-stage variants only when `internalModelName` lacks a
  /// fast/full distinction (e.g. `gemini-nano-v3`), while never collapsing `v4`.
  List<PaiosModelVariant> get selectorModelVariants {
    final switchable = modelVariants.where((v) => v.isSwitchable).toList();
    if (switchable.length <= 1) return List.unmodifiable(switchable);

    final result = <PaiosModelVariant>[];
    for (final variant in switchable) {
      final name = variant.internalModelName;
      final canCollapse =
          !_hasVariantDistinction(name) && !_isNanoV4InternalName(name);
      if (canCollapse) {
        final existingIdx = result.indexWhere(
          (existing) =>
              existing.releaseStage == variant.releaseStage &&
              existing.internalModelName == name &&
              !_hasVariantDistinction(existing.internalModelName) &&
              !_isNanoV4InternalName(existing.internalModelName),
        );
        if (existingIdx != -1) {
          final existing = result[existingIdx];
          if (variant.isActive && !existing.isActive) {
            result[existingIdx] = existing.copyWith(isActive: true);
          }
          continue;
        }
      }
      result.add(variant);
    }
    return List.unmodifiable(result);
  }

  /// Clean sorted list of switchable/downloadable model variants for the
  /// simplified selector UI.
  List<Map<String, dynamic>> get availableModelVariants => List.unmodifiable(
        modelVariants
            .where((v) => v.isSwitchable)
            .map((v) => v.toMap())
            .toList(),
      );

  Future<void> setEnableThinking(bool value) async {
    config.enableThinking = value;
    await config.saveModelConfig();
    notifyListeners();
  }

  Future<void> setModelConfiguration({
    String? releaseStage,
    String? preference,
  }) async {
    if (isLoading) return;
    if (releaseStage != null) {
      config.modelReleaseStage = AppConfig.normalizeReleaseStage(releaseStage);
    }
    if (preference != null) {
      config.modelPreference = AppConfig.normalizePreference(preference);
    } else if (releaseStage != null) {
      if (config.modelReleaseStage == 'stable' &&
          config.modelPreference == 'fast' &&
          modelInfo.containsKey('stableFastAvailable') &&
          !isStableFastAvailable) {
        config.modelPreference = 'full';
      } else if (config.modelReleaseStage == 'preview' &&
          config.modelPreference == 'full' &&
          modelInfo.containsKey('previewFullAvailable') &&
          !isPreviewFullAvailable &&
          (!modelInfo.containsKey('previewFastAvailable') || isPreviewFastAvailable)) {
        config.modelPreference = 'fast';
      }
    }
    await config.saveModelConfig();

    isSwitchingModelConfig = true;
    notifyListeners();
    try {
      final updated = await gemini.switchModelConfig(
        releaseStage: config.modelReleaseStage,
        preference: config.modelPreference,
      );
      if (updated.isNotEmpty &&
          updated['status']?.toString().toLowerCase() != 'error') {
        modelInfo = updated;
        isAvailable = _modelBool("available") || modelFeatureStatus == "available";
        isInitialized = false;
        await _syncConfigWithModelCapabilities();
      } else if (updated['status']?.toString().toLowerCase() == 'error') {
        await log(
          "model",
          "error",
          "Model config switch returned error: ${updated['version']}",
          sendRemote: false,
        );
      }
      await log(
        "model",
        "info",
        "Switched model config to ${config.modelReleaseStage}/${config.modelPreference} "
            "(active: $activeReleaseStage/$activePreference, nanoV4=$isNanoV4Active, "
            "thinkingAvailable=$isThinkingModeAvailable, fallback=$fellBackToStable)",
        sendRemote: false,
      );
    } catch (e) {
      await log("model", "error", "Failed to switch model config: $e", sendRemote: false);
    } finally {
      isSwitchingModelConfig = false;
      notifyListeners();
    }
  }

  PaiosVariantDownloadState? downloadStateFor(String stage, String pref) {
    final key =
        '${AppConfig.normalizeReleaseStage(stage)}:${AppConfig.normalizePreference(pref)}';
    return variantDownloads[key];
  }

  Future<void> refreshModelInfo() async {
    if (_disposed) return;
    try {
      final info = await gemini
          .getModelInfo(
            releaseStage: config.modelReleaseStage,
            preference: config.modelPreference,
          )
          .timeout(const Duration(seconds: 4));
      if (_disposed) return;
      if (info.isNotEmpty) {
        modelInfo = info;
        isAvailable = _modelBool("available") || modelFeatureStatus == "available";
        await _syncConfigWithModelCapabilities();
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> downloadVariant(String releaseStage, String preference) async {
    final stage = AppConfig.normalizeReleaseStage(releaseStage);
    final pref = AppConfig.normalizePreference(preference);
    final key = '$stage:$pref';
    final previous = variantDownloads[key];
    final initialTotal =
        (previous != null && previous.totalBytes > 0) ? previous.totalBytes : usualModelSize;

    _downloadSpeedSamples[key] = [
      (timeMs: DateTime.now().millisecondsSinceEpoch, bytes: 0),
    ];
    variantDownloads[key] = PaiosVariantDownloadState(
      releaseStage: stage,
      preference: pref,
      variantKey: key,
      status: 'started',
      bytesDownloaded: 0,
      totalBytes: initialTotal,
      bytesPerSec: 0.0,
    );
    isDownloadingModel = true;
    notifyListeners();

    try {
      if (_statusSubscription == null) {
        _attachDownloadStatusSubscription(
          arguments: const {'triggerInit': false},
        );
      }
      final dynamic res = await _localAiChannel.invokeMethod('downloadVariant', {
        'releaseStage': stage,
        'preference': pref,
      });
      if (_disposed) return;
      if (res is Map) {
        final downloadErr = res['downloadError']?.toString().trim();
        if (downloadErr != null && downloadErr.isNotEmpty) {
          _downloadSpeedSamples.remove(key);
          variantDownloads[key] = (variantDownloads[key] ??
                  PaiosVariantDownloadState(
                    releaseStage: stage,
                    preference: pref,
                    variantKey: key,
                  ))
              .copyWith(
            status: 'failed',
            bytesPerSec: 0.0,
            error: downloadErr,
          );
        } else {
          final rawVariants = res['modelVariants'];
          if (rawVariants is List) {
            for (final item in rawVariants.whereType<Map>()) {
              final v = PaiosModelVariant.fromMap(item);
              if (v.releaseStage == stage &&
                  v.preference == pref &&
                  v.available) {
                final cur = variantDownloads[key];
                final total = (cur != null && cur.totalBytes > 0)
                    ? cur.totalBytes
                    : usualModelSize;
                _downloadSpeedSamples.remove(key);
                variantDownloads[key] = PaiosVariantDownloadState(
                  releaseStage: stage,
                  preference: pref,
                  variantKey: key,
                  status: 'completed',
                  bytesDownloaded: total,
                  totalBytes: total,
                  bytesPerSec: 0.0,
                );
                await refreshModelInfo();
                break;
              }
            }
          }
        }
      }
      await log(
        "model",
        "info",
        "Triggered background downloadVariant for $stage/$pref (active remains ${config.modelReleaseStage}/${config.modelPreference})",
        sendRemote: false,
      );
    } catch (e) {
      _downloadSpeedSamples.remove(key);
      variantDownloads[key] = (variantDownloads[key] ??
              PaiosVariantDownloadState(
                releaseStage: stage,
                preference: pref,
                variantKey: key,
              ))
          .copyWith(
        status: 'failed',
        bytesPerSec: 0.0,
        error: e.toString(),
      );
      await log(
        "model",
        "error",
        "Failed to download variant $stage/$pref: $e",
        sendRemote: false,
      );
    } finally {
      isDownloadingModel = variantDownloads.values.any((s) => s.isDownloading);
      notifyListeners();
    }
  }

  Future<void> downloadSelectedModel() async {
    if (isDownloadingModel) return;
    isDownloadingModel = true;
    notifyListeners();
    try {
      final updated = await gemini.downloadModel(
        releaseStage: config.modelReleaseStage,
        preference: config.modelPreference,
      );
      if (updated.isNotEmpty) {
        modelInfo = updated;
        isAvailable = _modelBool("available") || modelFeatureStatus == "available";
      }
      await log(
        "model",
        "info",
        "Triggered downloadModel for ${config.modelReleaseStage}/${config.modelPreference}, status=$modelFeatureStatus",
        sendRemote: false,
      );
    } catch (e) {
      await log("model", "error", "Failed to download model: $e", sendRemote: false);
    } finally {
      isDownloadingModel = false;
      notifyListeners();
    }
  }

  static final RegExp _ctrlToolCallPrefixRegex = RegExp(
    r'<ctrl\d+>\s*call:([a-zA-Z0-9_.:-]+)\s*\{',
    caseSensitive: false,
  );
  static final RegExp _strayCtrlTagRegex = RegExp(
    r'<ctrl\d+>',
    caseSensitive: false,
  );

  static String _sanitizeThoughtChunk(String input) {
    if (input.isEmpty) return '';
    final out = StringBuffer();
    int cursor = 0;
    for (final match in _ctrlToolCallPrefixRegex.allMatches(input)) {
      if (match.start < cursor) continue;
      final openBrace = match.end - 1;
      final closeBrace = _findBalancedBraceEnd(input, openBrace);
      if (closeBrace == -1) continue;
      out.write(input.substring(cursor, match.start));
      int after = closeBrace + 1;
      final tailMatch = RegExp(r'^\s*<ctrl\d+>', caseSensitive: false)
          .firstMatch(input.substring(after));
      if (tailMatch != null) {
        after += tailMatch.end;
      }
      cursor = after;
    }
    out.write(input.substring(cursor));
    return out
        .toString()
        .replaceAll(_strayCtrlTagRegex, '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  void _clearThoughtChunk() {
    _rawThoughtChunk = "";
    currentThoughtChunk = "";
  }

  void _appendThoughtChunk(String? incoming) {
    final trimmed = incoming?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    if (_rawThoughtChunk.isEmpty || trimmed.startsWith(_rawThoughtChunk)) {
      _rawThoughtChunk = trimmed;
    } else if (!_rawThoughtChunk.endsWith(trimmed)) {
      _rawThoughtChunk = "$_rawThoughtChunk\n\n$trimmed";
    }
    currentThoughtChunk = _sanitizeThoughtChunk(_rawThoughtChunk);
  }

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

  /// Callback invoked when an assistant overlay session is opened in the full app.
  VoidCallback? onOpenAssistantChat;
  bool _pendingOpenAssistantChat = false;
  bool get hasPendingOpenAssistantChat => _pendingOpenAssistantChat;

  void flushPendingAssistantChatNavigation() {
    if (_pendingOpenAssistantChat && appStarted && onOpenAssistantChat != null) {
      _pendingOpenAssistantChat = false;
      onOpenAssistantChat!.call();
    }
  }

  /// Subscription to manage the active AI stream
  StreamSubscription<AiEvent>? _aiSubscription;

  late Cards cards;

  /// This junk is to update all pages in case we have a modal that is focused in which case setState will not update content underneath it
  void genericRefresh() {
    notifyListeners();
  }

  void notify() {
    genericRefresh();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
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

  @visibleForTesting
  Future<void> handleIncomingAssistantChatForTest(Map<String, dynamic> payload) =>
      _handleIncomingAssistantChat(payload);

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
          defaultAssistantAuthor: assistantAuthorLabel,
        );
        if (unarchived && newChatId.isNotEmpty) {
          currentChat = newChatId;
          final rawHistory = chats[newChatId]?["history"];
          if (rawHistory is String && rawHistory.isNotEmpty) {
            try {
              final decoded = jsonDecode(rawHistory);
              context = decoded is List ? decoded : List.from(conversation);
            } catch (_) {
              context = List.from(conversation);
            }
          } else {
            context = List.from(conversation);
          }
          contextSize = int.tryParse(chats[newChatId]?["tokens"] ?? "0") ?? 0;
          if (onOpenAssistantChat != null && appStarted) {
            notifyListeners();
            onOpenAssistantChat!.call();
            return;
          }
          _pendingOpenAssistantChat = true;
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
                  defaultAssistantAuthor: assistantAuthorLabel,
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
    if (!scroller.hasClients) return;
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

    await _syncLocalToolRegistrations(startListener: true);
  }

  void _syncInternalToolRegistrations() {
    for (final mod in InternalToolsService.modules) {
      if (!isExtensionEnabled(mod.id)) {
        for (final spec in mod.tools) {
          toolRegistry.unregister(spec.name);
        }
        continue;
      }
      for (final spec in mod.tools) {
        if (!isToolModuleEnabled(spec.name)) {
          toolRegistry.unregister(spec.name);
          continue;
        }
        if (spec.name == 'query_aicore_documentation') {
          docService.registerMeshTool(toolRegistry);
          continue;
        }
        if (spec.name == 'get_battery_status') {
          toolRegistry.register(
            M3xTool(
              name: spec.name,
              app: spec.app,
              description: spec.description,
              parameters: spec.parameters,
              handler: (args) async {
                try {
                  final res = await _meshHostChannel.invokeMapMethod<String, dynamic>(
                    'getBatteryStatus',
                  );
                  final level = res?['level'] ?? -1;
                  final charging = res?['charging'] == true;
                  final batteryStatus = res?['status']?.toString() ??
                      (charging ? 'Charging' : 'Discharging');
                  return {
                    'level': level,
                    'battery_level':
                        (level is int && level >= 0) ? '$level%' : 'unknown',
                    'charging': charging,
                    'is_charging': charging,
                    'status': batteryStatus,
                  };
                } catch (e) {
                  return {
                    'error': e.toString(),
                    'message': 'Unable to read device battery status: $e',
                  };
                }
              },
            ),
          );
          continue;
        }
        toolRegistry.register(
          M3xTool(
            name: spec.name,
            app: spec.app,
            description: spec.description,
            parameters: spec.parameters,
            handler: (args) => internalToolsService.executeOnlineTool(
              spec.name,
              args,
              fallbackQuestion: lastPrompt,
              readerAgent: spec.name == 'wikipedia_details'
                  ? (text, question) => gemini.generateInternalInference(
                        prompt: 'Question: $question\n\nWikipedia excerpt:\n$text',
                        instructions:
                            'Extract only the concise facts that answer the user\'s question from this Wikipedia excerpt.',
                        maxTokens: 160,
                        temperature: 0.2,
                      )
                  : null,
            ),
          ),
        );
      }
    }
  }

  Future<void> _syncLocalToolRegistrations({bool startListener = false}) async {
    _syncInternalToolRegistrations();
    if (startListener) {
      try {
        await meshClient.startListening().timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
    try {
      await meshClient.syncDeclaredTools().timeout(const Duration(seconds: 2));
    } catch (_) {}
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
    try {
      await M3x.init().timeout(const Duration(seconds: 3));
    } catch (_) {}
    try {
      final info = await PackageInfo.fromPlatform()
          .timeout(const Duration(seconds: 3));
      if (info.packageName.isNotEmpty) {
        _resolvedPackageName = info.packageName;
      }
    } catch (_) {}
    try {
      await MigrationService.initiateMigration()
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
    try {
      await logger.initFromHive().timeout(const Duration(seconds: 3));
    } catch (_) {}
    try {
      await config.initFromHive().timeout(const Duration(seconds: 3));
    } catch (_) {}
    try {
      await _syncInternalModulePreferences()
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
    try {
      await docService.initialize().timeout(const Duration(seconds: 3));
    } catch (_) {}

    unawaited(log("init", "info", "Starting the app engine"));
    unawaited(log("init", "info", "Starting the translations engine"));
    dict = Dictionary(
      path: "assets/translations",
      url: "https://raw.githubusercontent.com/${config.repo}/main",
    );
    try {
      await dict
          .setup(log: logger.log, onUpdated: genericRefresh)
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
    unawaited(log("init", "info", "Checking Gemini Nano status"));
    try {
      await checkEngine().timeout(const Duration(seconds: 3));
    } catch (_) {}
    unawaited(log("init", "info", "Initializing the Prompt engine"));
    promptEngine = Prompt(ghUrl: "https://github.com/${config.repo}");
    try {
      await promptData
          .initFromHive("https://raw.githubusercontent.com/${config.repo}/main")
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
    try {
      await promptEngine.initialize().timeout(const Duration(seconds: 3));
    } catch (_) {}
    unawaited(log("init", "info", "Initializing the Resource repository"));
    try {
      await resourceData
          .initFromHive("https://raw.githubusercontent.com/${config.repo}/main")
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
    unawaited(log("init", "info", "Initializing Intro Slides repository"));
    try {
      await introSlideData
          .initFromHive("https://raw.githubusercontent.com/${config.repo}/main")
          .timeout(const Duration(seconds: 3));
    } catch (_) {}

    unawaited(
      log(
        "init",
        "info",
        "Firebase analytics: ${analytics ? "Enabled" : "Disabled"}",
      ),
    );

    try {
      await chatData.initFromHive().timeout(const Duration(seconds: 3));
    } catch (_) {}
    unawaited(
      log(
        "init",
        "info",
        "Add DateTime to prompt: ${addCurrentTimeToRequests ? "Enabled" : "Disabled"}",
      ),
    );
    unawaited(
      log(
        "init",
        "info",
        "Add app locale to prompt: ${shareLocale ? "Enabled" : "Disabled"}",
      ),
    );
    unawaited(
      log(
        "init",
        "info",
        "Retry on error: ${errorRetry ? "Enabled" : "Disabled"}",
      ),
    );
    unawaited(
      log(
        "init",
        "info",
        "Ignore instructions: ${ignoreInstructions ? "Enabled" : "Disabled"}",
      ),
    );

    meshClient.enabled = config.enableMesh;
    try {
      await _registerLocalTools().timeout(const Duration(seconds: 3));
    } catch (_) {}

    appStarted = true;
    notifyListeners();
    unawaited(log("init", "info", "App initiation complete"));

    unawaited(syncActivePersonaToNative());

    gemini.setAssistantChatHandler((payload) async {
      await _handleIncomingAssistantChat(payload);
    });
    try {
      final initialAssistant = await gemini
          .getInitialAssistantChat()
          .timeout(const Duration(seconds: 2));
      if (initialAssistant != null) {
        await _handleIncomingAssistantChat(initialAssistant);
      }
    } catch (_) {}
    try {
      await _checkPendingAssistantChatsFromPrefs()
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
    flushPendingAssistantChatNavigation();

    if (config.enableMesh) {
      unawaited(ensureMeshToolsDiscovered());
    } else {
      unawaited(log("init", "info", "Agentic Mesh disabled by user configuration"));
    }

    // Post-launch background documentation synchronization (Tier 3 SWR on each launch)
    unawaited(docService.syncRemoteDocs());
  }

  void addDownloadLog(String log) {
    final parts = log.split("=");
    modelDownloadLog.add({
      "status": parts.isNotEmpty ? parts[0] : log,
      "info": parts.length > 1 ? parts[1] : "",
      "value": parts.length > 2 ? parts[2] : "",
      "time": DateTime.now().millisecondsSinceEpoch,
    });
    notifyListeners();
  }

  lateNetCheck() async {
    if (_lateNetCheckRunning) return;
    _lateNetCheckRunning = true;
    try {
      while (firstLaunch && !_disposed) {
        if (isAiCoreKnownUnavailable &&
            modelFeatureStatus != 'downloading' &&
            modelFeatureStatus != 'downloadable') {
          return;
        }
        try {
          final connectivityResult = await Connectivity()
              .checkConnectivity()
              .timeout(const Duration(seconds: 2));
          if (_disposed) return;
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
        } catch (_) {}
        await Future.delayed(const Duration(seconds: 2));
      }
    } finally {
      _lateNetCheckRunning = false;
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
    if (_lateProgressCheckRunning) return;
    _lateProgressCheckRunning = true;
    try {
      Map lastUpdate = {};
      while (firstLaunch && !_disposed) {
        if (isAiCoreKnownUnavailable &&
            modelFeatureStatus != 'downloading' &&
            modelFeatureStatus != 'downloadable') {
          return;
        }
        await Future.delayed(const Duration(seconds: 15));
        if (_disposed) return;
        if (isAiCoreKnownUnavailable &&
            modelFeatureStatus != 'downloading' &&
            modelFeatureStatus != 'downloadable') {
          return;
        }
        if (lastUpdate.isEmpty) {
          if (modelDownloadLog.isNotEmpty) {
            lastUpdate = modelDownloadLog[modelDownloadLog.length - 1];
          }
        }
        if (modelDownloadLog.isNotEmpty) {
          if (lastUpdate == modelDownloadLog[modelDownloadLog.length - 1]) {
            /// Nothing changed in the last 15 seconds, assume we have restarted and are not getting updates; We must restart the checkEngine. So...
            unawaited(checkEngine(isAutoRetry: true));
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
    } finally {
      _lateProgressCheckRunning = false;
    }
  }

  Future<void> checkEngine({bool isAutoRetry = false}) async {
    if (_disposed) return;
    if (!isAutoRetry) {
      _downloadErrorRetryCount = 0;
      _unavailableToastShown = false;
    }
    if (modelDownloadLog.isEmpty) {
      lateNetCheck();
      lateProgressCheck();
    }
    modelDownloadLog.clear();
    unawaited(() async {
      try {
        final info = await gemini
            .getModelInfo(
              releaseStage: config.modelReleaseStage,
              preference: config.modelPreference,
            )
            .timeout(const Duration(seconds: 4));
        if (_disposed) return;
        if (info.isNotEmpty) {
          modelInfo = info;
          isAvailable = _modelBool("available") || modelFeatureStatus == "available";
          await _syncConfigWithModelCapabilities();
          notifyListeners();
        }
      } catch (_) {}
    }());
    await _statusSubscription?.cancel();
    _attachDownloadStatusSubscription();
  }

  void _attachDownloadStatusSubscription({dynamic arguments}) {
    final rawDownloadStream = arguments == null
        ? gemini.downloadChannel.receiveBroadcastStream()
        : gemini.downloadChannel.receiveBroadcastStream(arguments);
    gemini.statusStream = rawDownloadStream.map(
      (dynamic event) => event.toString(),
    );
    _statusSubscription = rawDownloadStream.listen(
      (dynamic event) async {
        await _handleDownloadChannelEvent(event);
      },
      onError: (e) async {
        await log("model", "error", e.toString());
        analyzeError("Received new status: ", e);
      },
      onDone: () {
        if (!_disposed) {
          notifyListeners();
        }
      },
    );
  }

  static int? _parseIntField(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  static String _normalizeDownloadStatus(dynamic raw) {
    final s = raw?.toString().trim().toLowerCase() ?? '';
    switch (s) {
      case 'started':
      case 'download_started':
      case 'downloadstarted':
        return 'started';
      case 'downloading':
      case 'progress':
      case 'download_progress':
      case 'downloadprogress':
        return 'downloading';
      case 'completed':
      case 'available':
      case 'download_completed':
      case 'downloadcompleted':
        return 'completed';
      case 'failed':
      case 'error':
      case 'download_failed':
      case 'downloadfailed':
        return 'failed';
      case 'idle':
        return 'idle';
      default:
        return s.isEmpty ? 'downloading' : s;
    }
  }

  double _computeSlidingWindowSpeed(String key, int bytesDownloaded) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final samples = _downloadSpeedSamples.putIfAbsent(key, () => []);
    if (samples.isNotEmpty && bytesDownloaded < samples.last.bytes) {
      samples.clear();
    }
    samples.add((timeMs: nowMs, bytes: bytesDownloaded));

    // Keep roughly a 1-second sliding window while retaining an anchor sample
    // so speed stays stable across irregular update intervals.
    while (samples.length > 2 &&
        (nowMs - samples.first.timeMs) > 1000 &&
        (nowMs - samples[1].timeMs) >= 1000) {
      samples.removeAt(0);
    }

    if (samples.length < 2) {
      return variantDownloads[key]?.bytesPerSec ?? 0.0;
    }
    final dtMs = samples.last.timeMs - samples.first.timeMs;
    final dBytes = samples.last.bytes - samples.first.bytes;
    if (dtMs <= 0 || dBytes < 0) {
      return variantDownloads[key]?.bytesPerSec ?? 0.0;
    }
    return (dBytes * 1000.0) / dtMs;
  }

  @visibleForTesting
  Future<void> handleDownloadChannelEvent(dynamic event) =>
      _handleDownloadChannelEvent(event);

  Future<void> _handleDownloadChannelEvent(dynamic event) async {
    if (_disposed) return;
    if (event is Map) {
      await _handleStructuredDownloadEvent(Map<dynamic, dynamic>.from(event));
      return;
    }
    final rawStr = event?.toString() ?? '';
    final trimmed = rawStr.trim();
    if (trimmed.startsWith('{')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          await _handleStructuredDownloadEvent(decoded);
          return;
        }
      } catch (_) {}
    }
    await handleDownloadStatus(rawStr);
  }

  Future<void> _handleStructuredDownloadEvent(Map<dynamic, dynamic> map) async {
    if (_disposed) return;
    final rawVariantKey = map['variantKey']?.toString().trim() ?? '';
    String? rawStage = map['releaseStage']?.toString();
    String? rawPref = map['preference']?.toString();
    if ((rawStage == null || rawStage.trim().isEmpty) &&
        rawVariantKey.contains(':')) {
      final parts = rawVariantKey.split(':');
      rawStage = parts[0];
      if ((rawPref == null || rawPref.trim().isEmpty) && parts.length > 1) {
        rawPref = parts[1];
      }
    }
    final stage = AppConfig.normalizeReleaseStage(
      rawStage ?? config.modelReleaseStage,
    );
    final pref = AppConfig.normalizePreference(
      rawPref ?? config.modelPreference,
    );
    final key = rawVariantKey.isNotEmpty ? rawVariantKey : '$stage:$pref';

    final statusNorm = _normalizeDownloadStatus(map['status']);
    final incomingBytes = _parseIntField(
      map['bytes'] ?? map['bytesDownloaded'] ?? map['totalBytesDownloaded'],
    );
    final incomingTotal = _parseIntField(
      map['bytesToDownload'] ?? map['totalBytes'],
    );
    final previous = variantDownloads[key];

    final int resolvedTotalBytes;
    if (incomingTotal != null && incomingTotal > 0) {
      resolvedTotalBytes = incomingTotal;
    } else if (previous != null && previous.totalBytes > 0) {
      resolvedTotalBytes = previous.totalBytes;
    } else {
      resolvedTotalBytes = usualModelSize;
    }

    final int resolvedBytes =
        incomingBytes ?? previous?.bytesDownloaded ?? 0;

    switch (statusNorm) {
      case 'started':
        _downloadSpeedSamples[key] = [
          (timeMs: DateTime.now().millisecondsSinceEpoch, bytes: resolvedBytes),
        ];
        variantDownloads[key] = PaiosVariantDownloadState(
          releaseStage: stage,
          preference: pref,
          variantKey: key,
          status: 'started',
          bytesDownloaded: resolvedBytes,
          totalBytes: resolvedTotalBytes,
          bytesPerSec: 0.0,
        );
        isDownloadingModel = true;
        if (modelDownloadLog.isEmpty ||
            modelDownloadLog.last['info'] != 'downloading_model') {
          addDownloadLog('Download=downloading_model=$resolvedBytes');
        } else {
          notifyListeners();
        }
        break;

      case 'downloading':
        final speed = _computeSlidingWindowSpeed(key, resolvedBytes);
        variantDownloads[key] = PaiosVariantDownloadState(
          releaseStage: stage,
          preference: pref,
          variantKey: key,
          status: 'downloading',
          bytesDownloaded: resolvedBytes,
          totalBytes: resolvedTotalBytes,
          bytesPerSec: speed,
        );
        isDownloadingModel = true;
        final lastVal = modelDownloadLog.isNotEmpty
            ? (modelDownloadLog.last['value']?.toString() ?? '')
            : '';
        final parsedLast = int.tryParse(lastVal);
        if (modelDownloadLog.isEmpty ||
            (!lastVal.contains('error') &&
                (parsedLast == null || resolvedBytes > parsedLast))) {
          addDownloadLog('Download=downloading_model=$resolvedBytes');
        } else {
          notifyListeners();
        }
        break;

      case 'completed':
        _downloadSpeedSamples.remove(key);
        final finalBytes =
            resolvedBytes > 0 ? resolvedBytes : resolvedTotalBytes;
        variantDownloads[key] = PaiosVariantDownloadState(
          releaseStage: stage,
          preference: pref,
          variantKey: key,
          status: 'completed',
          bytesDownloaded: finalBytes,
          totalBytes: resolvedTotalBytes,
          bytesPerSec: 0.0,
        );
        isDownloadingModel =
            variantDownloads.values.any((s) => s.isDownloading);
        addDownloadLog('Available=Download=0');
        await refreshModelInfo();
        break;

      case 'failed':
        _downloadSpeedSamples.remove(key);
        final errMsg = (map['error'] ?? map['message'] ?? 'Download failed')
            .toString()
            .trim();
        lastAiCoreError = errMsg;
        variantDownloads[key] = PaiosVariantDownloadState(
          releaseStage: stage,
          preference: pref,
          variantKey: key,
          status: 'failed',
          bytesDownloaded: resolvedBytes,
          totalBytes: resolvedTotalBytes,
          bytesPerSec: 0.0,
          error: errMsg,
        );
        isDownloadingModel =
            variantDownloads.values.any((s) => s.isDownloading);
        addDownloadLog('Error=Download=$errMsg');
        break;

      default:
        variantDownloads[key] = (previous ??
                PaiosVariantDownloadState(
                  releaseStage: stage,
                  preference: pref,
                  variantKey: key,
                ))
            .copyWith(
          status: statusNorm,
          bytesDownloaded: resolvedBytes,
          totalBytes: resolvedTotalBytes,
        );
        isDownloadingModel =
            variantDownloads.values.any((s) => s.isDownloading);
        notifyListeners();
    }
  }

  @visibleForTesting
  Future<void> handleDownloadStatus(String downloadStatus) async {
    if (_disposed) return;
    final parts = downloadStatus.split("=");
    final activeKey = '$activeReleaseStage:$activePreference';
    switch (parts[0]) {
      case "Available":
      case "available":
        modelInfo = await gemini
            .getModelInfo(
              releaseStage: config.modelReleaseStage,
              preference: config.modelPreference,
            )
            .timeout(
              const Duration(seconds: 4),
              onTimeout: () => <String, dynamic>{},
            );
        if (_disposed) return;
        final bool reportedAvailable = _modelBool("available") ||
            hasAnyAvailableModel ||
            modelFeatureStatus == "available";
        if (reportedAvailable) {
          isAvailable = true;
          _downloadErrorRetryCount = 0;
          _unavailableToastShown = false;
          _downloadSpeedSamples.remove(activeKey);
          final prev = variantDownloads[activeKey];
          if (prev != null && (prev.isDownloading || prev.isFailed)) {
            final total = prev.totalBytes > 0 ? prev.totalBytes : usualModelSize;
            variantDownloads[activeKey] = prev.copyWith(
              status: 'completed',
              bytesDownloaded: total,
              totalBytes: total,
              bytesPerSec: 0.0,
              clearError: true,
            );
          }
          isDownloadingModel =
              variantDownloads.values.any((s) => s.isDownloading);
          addDownloadLog("Available=Available=0");
          await log("model", "info", "Model is ready");
          notifyListeners();
        } else if (modelInfo["version"] == null) {
          if (_downloadErrorRetryCount < maxDownloadErrorRetries) {
            _downloadErrorRetryCount++;
            await log(
              "model",
              "warning",
              "Model version was not reported, trying again ($_downloadErrorRetryCount/$maxDownloadErrorRetries)",
            );
            await Future.delayed(const Duration(seconds: 2));
            if (!_disposed) {
              await checkEngine(isAutoRetry: true);
            }
          } else {
            isAvailable = false;
            notifyListeners();
          }
        } else {
          final subState = parts.length > 1 ? parts[1] : "";
          if (subState == "Download") {
            if (modelDownloadLog.isEmpty ||
                modelDownloadLog.last["info"] != "waiting_network") {
              addDownloadLog("Download=downloading_model=0");
              await log("model", "info", "Downloading model");
            }
          } else {
            addDownloadLog(downloadStatus);
          }
        }
        break;
      case "Download":
        final parsedIncoming =
            parts.length > 2 ? int.tryParse(parts[2]) : null;
        if (parsedIncoming != null) {
          final prev = variantDownloads[activeKey];
          final total = (prev != null && prev.totalBytes > 0)
              ? prev.totalBytes
              : usualModelSize;
          final speed = _computeSlidingWindowSpeed(activeKey, parsedIncoming);
          variantDownloads[activeKey] = PaiosVariantDownloadState(
            releaseStage: activeReleaseStage,
            preference: activePreference,
            variantKey: activeKey,
            status: 'downloading',
            bytesDownloaded: parsedIncoming,
            totalBytes: total,
            bytesPerSec: speed,
          );
          isDownloadingModel = true;
        }
        if (modelDownloadLog.isEmpty) {
          addDownloadLog(downloadStatus);
        } else {
          final lastVal = modelDownloadLog.last["value"]?.toString() ?? "";
          if (!lastVal.contains("error")) {
            final parsedLast = int.tryParse(lastVal);
            if (parsedLast != null) {
              await log(
                "model",
                "info",
                "Downloading, ${convertSize(parsedLast, false)}",
              );
            }
            if (parsedIncoming != null &&
                (parsedLast == null || parsedIncoming > parsedLast)) {
              addDownloadLog(downloadStatus);
            }
          }
        }
        break;
      case "Error":
        final errInfo = parts.length > 1 ? parts[1] : "";
        final errDetail = parts.length > 2 ? parts[2] : downloadStatus;
        lastAiCoreError = errDetail;
        if (variantDownloads.containsKey(activeKey) &&
            variantDownloads[activeKey]!.isDownloading) {
          _downloadSpeedSamples.remove(activeKey);
          variantDownloads[activeKey] = variantDownloads[activeKey]!.copyWith(
            status: 'failed',
            bytesPerSec: 0.0,
            error: errDetail,
          );
          isDownloadingModel =
              variantDownloads.values.any((s) => s.isDownloading);
        }
        addDownloadLog(downloadStatus);
        await log("model", "error", errDetail);
        if (errDetail.contains("1-DOWNLOAD_ERROR")) {
          if (_downloadErrorRetryCount < maxDownloadErrorRetries) {
            _downloadErrorRetryCount++;
            await log(
              "model",
              "warning",
              "Download error ($errDetail); retrying ($_downloadErrorRetryCount/$maxDownloadErrorRetries)",
              sendRemote: false,
            );
            await checkEngine(isAutoRetry: true);
          } else {
            isAvailable = false;
            notifyListeners();
            if (!firstLaunch && !_unavailableToastShown) {
              _unavailableToastShown = true;
              await _showToast(_unavailableToastText());
            }
          }
        } else if (errInfo == "AICore" || errDetail == "Unavailable") {
          isAvailable = false;
          notifyListeners();
          if (!firstLaunch && !_unavailableToastShown) {
            _unavailableToastShown = true;
            await _showToast(_unavailableToastText());
          }
        } else {
          if (!_unavailableToastShown) {
            _unavailableToastShown = true;
            await _showToast(_unavailableToastText());
          }
        }
        break;
      default:
        addDownloadLog(downloadStatus);
    }
  }

  /// Saves the last exchange (user prompt + AI response) to Hive via ChatRepository.
  /// The response text lives on the engine; the repository handles everything else.
  Future<void> addToContext() async {
    final committedResponse = responseText;
    final trimmedThought = _sanitizeThoughtChunk(currentThoughtChunk).trim();
    final aiTime = streamingMessageTime ?? DateTime.now();
    final userTime = streamingUserMessageTime ?? aiTime;
    responseText = "";
    _clearThoughtChunk();
    streamingMessageTime = null;
    streamingUserMessageTime = null;
    await chatData.addToContext(
      committedResponse,
      thoughtProcess: trimmedThought.isNotEmpty ? trimmedThought : null,
      author: assistantAuthorLabel,
      userTime: userTime,
      aiTime: aiTime,
    );
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
          if (_disposed) return;
          String composeConversation = "";
          for (var line in chatData.context) {
            composeConversation = "$composeConversation\n - ${line["message"]}";
          }
          final title = await generateChatTitle(composeConversation);
          if (_disposed) return;
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
    await gemini
        .init(
          releaseStage: config.modelReleaseStage,
          preference: config.modelPreference,
        )
        .then((initStatus) async {
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


  void startNewChat() {
    currentChat = "0";
    context.clear();
    contextSize = 0;
    if (!isLoading && !isGenerating && !isContinuing && !_isSynthesizing) {
      _clearTurnVisualMemory();
      prompt.clear();
      responseText = "";
      _clearThoughtChunk();
      lastPrompt = "";
      pendingImageBytes = null;
      pendingImageName = null;
      chatData.lastImagePath = null;
      chatData.lastImageDescription = null;
      streamingMessageTime = null;
      streamingUserMessageTime = null;
      isError = false;
      status = "";
    }
    notifyListeners();
  }

  Future<void> clearContext() async {
    _clearTurnVisualMemory();
    await chatData.clearContext();
    responseText = "";
    _clearThoughtChunk();
    streamingMessageTime = null;
    streamingUserMessageTime = null;
  }

  Future<void> initEngine({
    bool includeTools = true,
    bool hasAttachedImage = false,
  }) async {
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
        if (t.name == 'query_local_ai' || t.name == 'get_ai_status') {
          return false;
        }
        final internalMod = InternalToolsService.moduleForTool(t.name);
        if (internalMod != null) {
          return isExtensionEnabled(internalMod.id);
        }
        final extId = canonicalToolExtensionId(t);
        if (extId == _selfPackageId) {
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
            hasAttachedImage: hasAttachedImage,
          )
          .then((instruction) async {
            await gemini
                .init(
                  instructions: instruction,
                  releaseStage: config.modelReleaseStage,
                  preference: config.modelPreference,
                )
                .then((
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
                  if (initStatus.contains("AICore") &&
                      initStatus.contains("Unavailable")) {
                    status = _unavailableStatusMessage();
                    if (modelInfo.isEmpty) {
                      modelInfo = {
                        "status": "unavailable",
                        "available": false,
                        "statusCode": 0,
                      };
                    }
                    notifyListeners();
                  }
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

  void _resetTurnLifecycleFlags() {
    isLoading = false;
    isGenerating = false;
    isContinuing = false;
    _isSynthesizing = false;
    _activeToolHandling = false;
    _forcedFinalSynthesis = false;
  }

  /// Sets the error state
  void analyzeError(String action, dynamic e) {
    isAvailable = false;
    isError = true;
    isInitialized = false;
    isInitializing = false;
    _resetTurnLifecycleFlags();
    lastAiCoreError = e?.toString() ?? "";
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
        maxQuestionChars: isSynthesis
            ? 1400
            : Prompt.defaultContinuationQuestionChars,
      );
      final initStatus = await gemini.init(
        instructions: instruction,
        releaseStage: config.modelReleaseStage,
        preference: config.modelPreference,
      );
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
      case "0":
        return "stop";
      case "1":
        return "max_tokens";
      case "-100":
        return "other";
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
    final wasLoading = isLoading ||
        isGenerating ||
        isContinuing ||
        _isSynthesizing ||
        _activeToolHandling;
    _streamGenerationId++;
    final sub = _aiSubscription;
    _aiSubscription = null;
    unawaited(sub?.cancel());
    _clearTurnVisualMemory();
    _resetTurnLifecycleFlags();
    _toolFreeFallbackUsed = false;
    _combinedResponse = "";
    _currentSynthesisPrompt = "";
    _currentUserPromptForSynthesis = "";
    _lastFinishReason = "";
    _continuationCount = 0;
    _nullReasonContinuationCount = 0;
    _stopCutoffContinuationCount = 0;
    _emptyStreamRetryCount = 0;
    _toolTurnCount = 0;
    _lastToolCallSignature = "";
    _recoverableErrorRetries = 0;
    _lastToolFailed = false;
    _lastToolErrorIsInfra = false;
    _lastToolErrorText = "";
    _lastToolResultPayload = "";
    _lastToolCall = null;
    _clearThoughtChunk();
    responseText = "";
    lastPrompt = "";
    chatData.lastImagePath = null;
    streamingMessageTime = null;
    streamingUserMessageTime = null;
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

  Future<void> generateStream({bool isEmptyStreamRetry = false}) async {
    if (prompt.text.isEmpty && pendingImageBytes == null) {
      status = "Please enter your prompt";
      isError = true;
      notifyListeners();
      return;
    }
    if (isLoading ||
        isGenerating ||
        isContinuing ||
        _isSynthesizing ||
        _activeToolHandling) {
      return; // Don't run if already generating
    }

    if (isAiCoreKnownUnavailable) {
      final oldSub = _aiSubscription;
      _aiSubscription = null;
      await oldSub?.cancel();
      _resetTurnLifecycleFlags();
      isError = true;
      status = _unavailableStatusMessage();
      if (!_unavailableToastShown) {
        _unavailableToastShown = true;
        await _showToast(_unavailableToastText());
      }
      notifyListeners();
      return;
    }

    // Allocate generation ID and lock active flags BEFORE the first await so
    // rapid double-taps or cancelGeneration() during saveChatImage/initEngine
    // cannot double-enter or resurrect a cancelled turn.
    final int myGenId = ++_streamGenerationId;
    _resetTurnLifecycleFlags();
    isLoading = true;
    isGenerating = true;
    isError = false;
    _toolFreeFallbackUsed = false;
    _toolTurnCount = 0;
    _lastToolCallSignature = "";
    _lastToolFailed = false;
    _lastToolErrorIsInfra = false;
    _lastToolErrorText = "";
    _lastToolResultPayload = "";
    _lastToolCall = null;
    _recoverableErrorRetries = 0;
    if (!isEmptyStreamRetry) {
      _emptyStreamRetryCount = 0;
    }
    responseText = "";
    _clearThoughtChunk();
    _lastFinishReason = ""; // reset for new generation
    _combinedResponse = ""; // reset accumulator
    _currentSynthesisPrompt = "";
    _currentUserPromptForSynthesis = "";
    _continuationCount = 0;
    _nullReasonContinuationCount = 0;
    _stopCutoffContinuationCount = 0;
    cumulativeGenerationMs = 0;
    cumulativeTokenCount = 0;
    streamingUserMessageTime = DateTime.now();
    streamingMessageTime = DateTime.now();
    status = "Sending prompt...";
    notifyListeners();

    // Cancel any old streams
    final prevSub = _aiSubscription;
    _aiSubscription = null;
    await prevSub?.cancel();
    if (myGenId != _streamGenerationId || _disposed) return;

    // Capture and persist any attached image before initializing/starting stream
    final Uint8List? attachedImageBytes = pendingImageBytes;
    String? savedImagePath;
    if (attachedImageBytes != null) {
      savedImagePath = await chatData.saveChatImage(attachedImageBytes);
      if (myGenId != _streamGenerationId || _disposed) return;
      chatData.lastImagePath = savedImagePath;
      pendingImageBytes = null;
      pendingImageName = null;
      _turnImageBytesForMemory = attachedImageBytes;
      _turnImagePathForMemory = savedImagePath;
      _turnChatIdForMemory = chatData.currentChat;
    } else {
      _clearTurnVisualMemory();
    }

    final String? imagePath = savedImagePath;
    final bool hasAttachedImage =
        imagePath != null && imagePath.trim().isNotEmpty;

    // Ensure engine is ready with current attachment cue in instructions
    if (!isInitializing) {
      await initEngine(hasAttachedImage: hasAttachedImage);
    }
    if (myGenId != _streamGenerationId || _disposed) return;

    if (isError || (!isInitializing && !isInitialized) || isAiCoreKnownUnavailable) {
      _resetTurnLifecycleFlags();
      isError = true;
      streamingMessageTime = null;
      streamingUserMessageTime = null;
      if (isAiCoreKnownUnavailable) {
        status = _unavailableStatusMessage();
        if (!_unavailableToastShown) {
          _unavailableToastShown = true;
          await _showToast(_unavailableToastText());
          if (myGenId != _streamGenerationId || _disposed) return;
        }
      } else if (status.isEmpty) {
        status = "Failed to initialize Gemini Nano.";
      }
      notifyListeners();
      return;
    }

    // Set initial state for this new stream
    _generationStopwatch.reset();
    _generationStopwatch.start();
    _isCurrentSessionMultimodal = attachedImageBytes != null || hasAttachedImage;

    bool receivedTerminalEvent = false;
    streamingMessageTime = DateTime.now();

    double runTemperature = chatData.chats.containsKey(currentChat) && chatData.chats[currentChat].containsKey("chatTemperature") ? chatData.chats[currentChat]["chatTemperature"] : temperature;

    final String effectiveUserPrompt = prompt.text.trim().isNotEmpty
        ? prompt.text.trim()
        : "Describe this image.";
    final String userTurnPrompt = hasAttachedImage
        ? "[Image attached to this message]\nUser's request: $effectiveUserPrompt"
        : "User's request: $effectiveUserPrompt";

    final stream = gemini.generateTextEvents(
      prompt: userTurnPrompt,
      // No maxTokens — let the model generate freely; only OS timeout (reason 1) or natural stop (reason -100) will end it
      config: GenerationConfig(
        temperature: runTemperature,
        enableThinking: effectiveEnableThinking,
      ),
      stream: true,
      imageBytes: attachedImageBytes,
      imagePath: imagePath,
      downsample: config.downsampleImages,
    );
    lastPrompt = effectiveUserPrompt;

    _aiSubscription = stream.listen(
      (AiEvent event) async {
        if (myGenId != _streamGenerationId || _disposed) return;
        switch (event.status) {
          case AiEventStatus.loading:
            isLoading = true;
            responseText = "";
            status = dict.value("waiting_for_AI");
            await log("model", "info", "Waiting for model to initialize", sendRemote: false);
            if (myGenId != _streamGenerationId || _disposed) return;
            notifyListeners();
            break;

          case AiEventStatus.streaming:
            isLoading = true;
            streamingMessageTime = DateTime.now();
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
                      "Generation stopped (STOP): Natural stop point of the model.",
                    );
                  }
                  await log("model", "info", "Generation stopped (STOP)", sendRemote: false);
                  break;
                case "1":
                  if (kDebugMode) {
                    print(
                      "Generation stopped (MAX_TOKENS): The maximum number of output tokens as specified in the request was reached.",
                    );
                  }
                  await log("model", "info", "Generation stopped (MAX_TOKENS)", sendRemote: false);
                  break;
                case "-100":
                  if (kDebugMode) {
                    print("Generation stopped (OTHER): Generic stop reason.");
                  }
                  await log("model", "info", "Generation stopped (OTHER)", sendRemote: false);
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
              if (myGenId != _streamGenerationId || _disposed) return;
            }
            status = "Streaming response...";
            _appendThoughtChunk(event.thought);
            if (event.response != null) {
              response = event.response!;
              responseText = event.response!.text;
            }
            try {
              scrollChatlog(Duration(milliseconds: 250));
              await Future.delayed(Duration(milliseconds: 500));
              if (myGenId != _streamGenerationId || _disposed) return;
              scrollChatlog(Duration(milliseconds: 250));
            } catch (e) {
              if (kDebugMode) {
                print("Can't scroll: $e");
              }
              await Future.delayed(Duration(milliseconds: 500));
              if (myGenId != _streamGenerationId || _disposed) return;
            }
            break;

          case AiEventStatus.done:
            receivedTerminalEvent = true;
            _appendThoughtChunk(event.thought);
            // ── Prominent finishReason debug log ─────────────────────────────
            // NOTE: _lastFinishReason is cached from streaming — the done event also carries fallback reason
            final String? doneReason = _lastFinishReason.isNotEmpty
                ? _lastFinishReason
                : event.reason;
            if (kDebugMode) {
              final String friendlyReason = switch (doneReason) {
                "0"    => "STOP (natural end)",
                "1"    => "MAX_TOKENS (token budget exhausted)",
                "-100" => "OTHER (timeout or forced stop)",
                null   => "null (no reason reported during streaming)",
                _      => "UNKNOWN code: $doneReason",
              };
              print("╔═══════════════════════════════════════════╗");
              print("║  GENERATION DONE  finishReason: $friendlyReason");
              print("║  responseText length: ${responseText.length} chars");
              print("╚═══════════════════════════════════════════╝");
            }
            await log(
              "model",
              "info",
              "Generation done. finishReason=$doneReason (nanoV4=$isNanoV4Active, chars=${responseText.length})",
              sendRemote: false,
            );
            if (myGenId != _streamGenerationId || _disposed) return;
            // ─────────────────────────────────────────────────────────────────
            final String rawThoughtForPromotion = _rawThoughtChunk.trim().isNotEmpty
                ? _rawThoughtChunk
                : currentThoughtChunk;
            if (responseText.trim().isEmpty &&
                rawThoughtForPromotion.trim().isNotEmpty) {
              final thoughtToolMap = _extractToolCall(
                rawThoughtForPromotion,
                userPrompt: effectiveUserPrompt,
                mutateResponseOnGreeting: false,
              );
              if (thoughtToolMap != null) {
                currentThoughtChunk =
                    _sanitizeThoughtChunk(rawThoughtForPromotion);
                responseText = jsonEncode(thoughtToolMap);
                _combinedResponse = responseText;
                _emptyStreamRetryCount = 0;
                _activeToolHandling = true;
                try {
                  await _handleToolCall(
                    thoughtToolMap,
                    originalPrompt: effectiveUserPrompt,
                  );
                } finally {
                  _activeToolHandling = false;
                }
                break;
              }
            }
            if (responseText.trim().isEmpty) {
              if (errorRetry) {
                if (event.response?.text == null ||
                    _emptyStreamRetryCount >= maxEmptyStreamRetries) {
                  _emptyStreamRetryCount = 0;
                  _resetTurnLifecycleFlags();
                  _clearThoughtChunk();
                  responseText = "";
                  streamingMessageTime = null;
                  streamingUserMessageTime = null;
                  await _showToast("Unable to generate response.");
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
                  _emptyStreamRetryCount++;
                  _resetTurnLifecycleFlags();
                  await Future.delayed(Duration(milliseconds: 500));
                  if (myGenId != _streamGenerationId || _disposed) return;
                  unawaited(generateStream(isEmptyStreamRetry: true));
                  return;
                }
              } else {
                _emptyStreamRetryCount = 0;
                _resetTurnLifecycleFlags();
                _clearThoughtChunk();
                isError = true;
                streamingMessageTime = null;
                streamingUserMessageTime = null;
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
              _emptyStreamRetryCount = 0;
              if (_isPureGreeting(effectiveUserPrompt)) {
                final stripped = _stripGreetingAccidentalToolBlock(responseText);
                if (stripped != null) {
                  await log(
                    "mesh",
                    "info",
                    "Stripped accidental trailing tool JSON after greeting prose.",
                  );
                  if (myGenId != _streamGenerationId || _disposed) return;
                  responseText = stripped;
                  _combinedResponse = stripped;
                }
              }
              final toolMap = _extractToolCall(
                responseText,
                userPrompt: effectiveUserPrompt,
              );
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
                // Model was cut off by timeout / token limit / mid-JSON — snapshot stats, start silent continuation
                cumulativeGenerationMs += response.generationTimeMs?.toInt() ?? 0;
                cumulativeTokenCount += response.tokenCount?.toInt() ?? 0;
                if (_isMissingFinishReason(doneReason) &&
                    !M3xToolCallParser.looksLikeIncompleteToolCall(responseText)) {
                  _nullReasonContinuationCount++;
                } else if (_isStopFinishReason(doneReason)) {
                  _stopCutoffContinuationCount++;
                }
                _continuationCount++;
                _combinedResponse = responseText;
                await log(
                  "model",
                  "info",
                  "Response interrupted (reason=$doneReason, nanoV4=$isNanoV4Active), triggering continuation #$_continuationCount",
                  sendRemote: false,
                );
                if (myGenId != _streamGenerationId || _disposed) return;
                if (kDebugMode) print("[AUTO-CONTINUE #$_continuationCount] reason=$doneReason");
                await continueGenerating();
              } else {
                final bool invalidTurn1Tool =
                    M3xToolCallParser.looksLikeIncompleteToolCall(responseText) ||
                        _looksLikeInvalidToolJson(responseText);
                if (invalidTurn1Tool) {
                  if (!_toolFreeFallbackUsed &&
                      !_lastToolFailed &&
                      _lastToolResultPayload.isEmpty &&
                      !_isSynthesizing) {
                    await _triggerToolFreeFallbackAnswer(effectiveUserPrompt);
                    break;
                  }
                  await log("mesh", "error", "Discarding incomplete tool call after continuation limit: $responseText");
                  responseText = _buildIncompleteToolFallback();
                } else {
                  responseText = trimTrailingIncompleteSentence(responseText);
                }
                // Natural stop or cap reached — commit
                _resetTurnLifecycleFlags();
                status = "Done";
                await addToContext();
                prompt.clear();
                unawaited(_captureVisualMemoryIfNeeded());

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
              _resetTurnLifecycleFlags();
              await Future.delayed(Duration(milliseconds: 500));
              if (myGenId != _streamGenerationId || _disposed) return;
              unawaited(generateStream());
              return;
            } else {
              _clearTurnVisualMemory();
              _resetTurnLifecycleFlags();
              isError = true;
              streamingMessageTime = null;
              streamingUserMessageTime = null;
              status = "Error";
              _clearThoughtChunk();
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
        if (myGenId != _streamGenerationId || _disposed) return;
        receivedTerminalEvent = true;
        _resetTurnLifecycleFlags();
        if (errorRetry) {
          await Future.delayed(Duration(milliseconds: 500));
          if (myGenId != _streamGenerationId || _disposed) return;
          unawaited(generateStream());
          return;
        } else {
          _clearThoughtChunk();
          streamingMessageTime = null;
          streamingUserMessageTime = null;
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
      onDone: () => _handleUnexpectedStreamClose(myGenId, receivedTerminalEvent),
    );
  }

  /// Returns true if [text] ends inside an open code fence (odd number of ``` markers).
  bool _isInsideCodeBlock(String text) {
    return RegExp(r'```').allMatches(text).length % 2 == 1;
  }

  static final RegExp _leadingEllipsisPattern =
      RegExp(r'^\s*(?:\.{2,}|…+|\.\s*\.\s*\.)\s*');
  static final RegExp _trailingEllipsisPattern =
      RegExp(r'(?:\.{3,}|…+)\s*$');
  static final RegExp _wordCharRegex = RegExp(r'[\p{L}\p{N}]', unicode: true);
  static final RegExp _joinBoundaryCharRegex =
      RegExp(r'[\s,.;:!?\(\)\[\]{}"“”' "'" r'’\-—/…]');

  /// Strips leading continuation ellipses (`...` / `…`) and trailing whitespace
  /// after them before evaluating joins or appending continuation chunks.
  static String stripLeadingEllipsis(String chunk) {
    if (chunk.isEmpty) return chunk;
    return chunk.replaceFirst(_leadingEllipsisPattern, '');
  }

  static bool _isValidSuffixPrefixOverlap(
    String existing,
    String incoming,
    int len,
  ) {
    if (len <= 0) return false;
    if (len >= 8) return true;
    final startIdx = existing.length - len;
    final startsAtBoundary =
        startIdx == 0 || _joinBoundaryCharRegex.hasMatch(existing[startIdx - 1]);
    if (!startsAtBoundary) return false;

    final endsAtBoundary = len == incoming.length ||
        _joinBoundaryCharRegex.hasMatch(incoming[len]) ||
        _joinBoundaryCharRegex.hasMatch(incoming[len - 1]);
    if (endsAtBoundary) return true;

    // Mid-word cutoff completion: e.g. existing ends with "Yud" (len >= 3) and
    // incoming starts with "Yudkowsky" so "Yud" + "kowsky" => "Yudkowsky".
    final isMidWordCompletion = len >= 3 &&
        _wordCharRegex.hasMatch(existing[existing.length - 1]) &&
        len < incoming.length &&
        _wordCharRegex.hasMatch(incoming[len]);
    return isMidWordCompletion;
  }

  static int _findSuffixPrefixOverlap(
    String existing,
    String incoming, {
    int maxLookback = 240,
  }) {
    final limit = existing.length < incoming.length
        ? existing.length
        : incoming.length;
    final maxLen = limit < maxLookback ? limit : maxLookback;
    for (int len = maxLen; len >= 1; len--) {
      final suffix = existing.substring(existing.length - len);
      if (incoming.startsWith(suffix) &&
          _isValidSuffixPrefixOverlap(existing, incoming, len)) {
        return len;
      }
    }
    return 0;
  }

  static ({String text, bool detected}) _trimRepeatedTrailingClause(
    String text, {
    int minClauseChars = 24,
  }) {
    final trimmed = text.trimRight();
    if (trimmed.length < minClauseChars * 2) {
      return (text: text, detected: false);
    }
    if (RegExp(r'```').allMatches(trimmed).length % 2 == 1) {
      return (text: text, detected: false);
    }
    final boundaryMatches = RegExp(
      r'[.!?。！？]["”’\x27\)\]\*_]*\s+',
    ).allMatches(trimmed).toList();
    if (boundaryMatches.isEmpty) {
      return (text: text, detected: false);
    }
    final lastMatch = boundaryMatches.last;
    final String beforeBoundary =
        trimmed.substring(0, lastMatch.end).trimRight();
    final String trailingClause = trimmed.substring(lastMatch.end).trim();
    if (trailingClause.length < minClauseChars ||
        beforeBoundary.length < minClauseChars) {
      return (text: text, detected: false);
    }

    int searchFrom = 0;
    while (searchFrom <= beforeBoundary.length - trailingClause.length) {
      final int idx = beforeBoundary.indexOf(trailingClause, searchFrom);
      if (idx < 0) break;
      final bool startsAtBoundary =
          idx == 0 || _joinBoundaryCharRegex.hasMatch(beforeBoundary[idx - 1]);
      if (startsAtBoundary) {
        return (text: beforeBoundary, detected: true);
      }
      searchFrom = idx + 1;
    }
    return (text: text, detected: false);
  }

  /// Stitches [incoming] onto [existing] across auto-continuation boundaries,
  /// normalizing ellipses, deduplicating suffix/prefix overlaps and repeated
  /// trailing clauses, and joining mid-word cutoffs seamlessly.
  static String stitchContinuation(String existing, String incoming) =>
      _stitchContinuationWithMeta(existing, incoming).text;

  static ({String text, bool trimmedLoop}) _stitchContinuationWithMeta(
    String existing,
    String incoming,
  ) {
    String cleaned = stripLeadingEllipsis(incoming);
    if (existing.isEmpty) return (text: cleaned, trimmedLoop: false);
    if (cleaned.isEmpty) return (text: existing, trimmedLoop: false);

    final trimmedExistingLeft = existing.trimLeft();
    final bool isJsonOrToolDraft = trimmedExistingLeft.startsWith('{') ||
        trimmedExistingLeft.startsWith('```json') ||
        RegExp(r'^```(?:json)?\s*\{', caseSensitive: false)
            .hasMatch(trimmedExistingLeft) ||
        M3xToolCallParser.looksLikeIncompleteToolCall(existing);
    final bool insideCodeBlock = RegExp(r'```').allMatches(existing).length % 2 == 1;

    if (isJsonOrToolDraft) {
      if (insideCodeBlock) {
        cleaned = stripLeadingEllipsis(
          cleaned.replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), ''),
        );
      }
      if (cleaned.isEmpty) return (text: existing, trimmedLoop: false);
      final overlap = _findSuffixPrefixOverlap(existing, cleaned);
      if (overlap >= 4) {
        return (text: existing + cleaned.substring(overlap), trimmedLoop: false);
      }
      return (text: existing + cleaned, trimmedLoop: false);
    }

    if (insideCodeBlock) {
      cleaned = stripLeadingEllipsis(
        cleaned.replaceFirst(RegExp(r'^```[a-zA-Z0-9]*\n?'), ''),
      );
      if (cleaned.isEmpty) return (text: existing, trimmedLoop: false);
      final overlap = _findSuffixPrefixOverlap(existing, cleaned);
      if (overlap > 0) {
        return (text: existing + cleaned.substring(overlap), trimmedLoop: false);
      }
      final sep = (existing.endsWith('\n') || cleaned.startsWith('\n')) ? '' : '\n';
      return (text: '$existing$sep$cleaned', trimmedLoop: false);
    }

    // Plain prose: strip trailing standalone continuation ellipsis from existing
    final String baseExisting = existing.replaceFirst(_trailingEllipsisPattern, '');
    if (baseExisting.isEmpty) return (text: cleaned, trimmedLoop: false);

    // 1. Direct suffix-prefix overlap check
    final int directOverlap = _findSuffixPrefixOverlap(baseExisting, cleaned);
    if (directOverlap > 0) {
      final remainder = cleaned.substring(directOverlap);
      if (remainder.isEmpty) return (text: baseExisting, trimmedLoop: false);
      final joined = baseExisting + remainder;
      final clauseTrim = _trimRepeatedTrailingClause(joined);
      return (text: clauseTrim.text, trimmedLoop: clauseTrim.detected);
    }

    // 2. Trailing-space-trimmed suffix-prefix overlap (e.g. "...to " + "...to\n5.0")
    final String trimmedBase = baseExisting.trimRight();
    if (trimmedBase.length < baseExisting.length && trimmedBase.isNotEmpty) {
      final int trimmedOverlap = _findSuffixPrefixOverlap(trimmedBase, cleaned);
      if (trimmedOverlap > 0) {
        final remainder = cleaned.substring(trimmedOverlap);
        if (remainder.isEmpty) return (text: baseExisting, trimmedLoop: false);
        final joined = RegExp(r'^\s').hasMatch(remainder)
            ? trimmedBase + remainder
            : baseExisting + remainder;
        final clauseTrim = _trimRepeatedTrailingClause(joined);
        return (text: clauseTrim.text, trimmedLoop: clauseTrim.detected);
      }
    }

    // 3. Repeated trailing clause / sentence rollback within last 280 chars (>= 18 chars)
    const int minClauseMatch = 18;
    bool strippedPrefix = false;
    if (cleaned.length >= minClauseMatch && baseExisting.length >= minClauseMatch) {
      final int windowStart =
          baseExisting.length > 280 ? baseExisting.length - 280 : 0;
      final String probe = cleaned.substring(0, minClauseMatch);
      int searchFrom = baseExisting.length - minClauseMatch;
      while (searchFrom >= windowStart) {
        final int idx = baseExisting.lastIndexOf(probe, searchFrom);
        if (idx < windowStart) break;
        final bool startsAtBoundary =
            idx == 0 || _joinBoundaryCharRegex.hasMatch(baseExisting[idx - 1]);
        if (startsAtBoundary) {
          int matchLen = minClauseMatch;
          final int maxMatch = (baseExisting.length - idx) < cleaned.length
              ? (baseExisting.length - idx)
              : cleaned.length;
          while (matchLen < maxMatch &&
              matchLen < 240 &&
              baseExisting[idx + matchLen] == cleaned[matchLen]) {
            matchLen++;
          }
          final String trailingTail = baseExisting.substring(idx + matchLen);
          if (trailingTail.length <= 28 && !RegExp(r'[.!?]').hasMatch(trailingTail)) {
            final joined = baseExisting.substring(0, idx) + cleaned;
            final clauseTrim = _trimRepeatedTrailingClause(joined);
            return (text: clauseTrim.text, trimmedLoop: clauseTrim.detected);
          }
          final String deduped = cleaned.substring(matchLen).trimLeft();
          if (deduped.isEmpty) return (text: baseExisting, trimmedLoop: true);
          cleaned = deduped;
          strippedPrefix = true;
          break;
        }
        searchFrom = idx - 1;
      }
    }

    // 3b. Earlier-sentence prefix deduplication across full baseExisting (>= 24 chars)
    const int minFullPrefixMatch = 24;
    if (!strippedPrefix &&
        cleaned.length >= minFullPrefixMatch &&
        baseExisting.length >= minFullPrefixMatch) {
      final String probe = cleaned.substring(0, minFullPrefixMatch);
      int searchFrom = baseExisting.length - minFullPrefixMatch;
      while (searchFrom >= 0) {
        final int idx = baseExisting.lastIndexOf(probe, searchFrom);
        if (idx < 0) break;
        final bool startsAtBoundary =
            idx == 0 || _joinBoundaryCharRegex.hasMatch(baseExisting[idx - 1]);
        if (startsAtBoundary) {
          int matchLen = minFullPrefixMatch;
          final int maxMatch = (baseExisting.length - idx) < cleaned.length
              ? (baseExisting.length - idx)
              : cleaned.length;
          while (matchLen < maxMatch &&
              baseExisting[idx + matchLen] == cleaned[matchLen]) {
            matchLen++;
          }
          final String deduped = cleaned.substring(matchLen).trimLeft();
          if (deduped.isEmpty) return (text: baseExisting, trimmedLoop: true);
          cleaned = deduped;
          break;
        }
        searchFrom = idx - 1;
      }
    }

    // 4. Plain prose boundary join
    final String lastChar = baseExisting[baseExisting.length - 1];
    final String firstChar = cleaned[0];
    final bool endsWithBoundary =
        lastChar == ' ' || lastChar == '\n' || lastChar == '\t';
    final bool startsWithBoundary =
        firstChar == ' ' || firstChar == '\n' || firstChar == '\t';
    final bool endsWithJoiningPunct = lastChar == "'" ||
        lastChar == '’' ||
        lastChar == '(' ||
        lastChar == '[' ||
        lastChar == '{' ||
        lastChar == '"' ||
        lastChar == '“' ||
        lastChar == '-' ||
        lastChar == '—' ||
        lastChar == '/';
    final bool startsWithDecimal = RegExp(r'^\.\d').hasMatch(cleaned);
    final bool startsWithPunct =
        !startsWithDecimal && ',.;:!?)]:"\'’”%'.contains(firstChar);

    final String joined = (!endsWithBoundary &&
            !startsWithBoundary &&
            !endsWithJoiningPunct &&
            !startsWithPunct)
        ? '$baseExisting $cleaned'
        : '$baseExisting$cleaned';
    final clauseTrim = _trimRepeatedTrailingClause(joined);
    return (text: clauseTrim.text, trimmedLoop: clauseTrim.detected);
  }

  /// Detects a trailing stutter/repetition loop (3+ consecutive repeats of a
  /// >=12-char phrase or multi-word sequence like `"and...that"`, or a trailing
  /// clause `>= 24` chars after a sentence boundary that duplicates an earlier
  /// clause in the message) and trims back cleanly.
  static ({String text, bool detected}) detectAndTrimStutterLoop(String text) {
    final trimmed = text.trimRight();
    if (trimmed.length < 24) return (text: text, detected: false);
    if (RegExp(r'```').allMatches(trimmed).length % 2 == 1) {
      return (text: text, detected: false);
    }

    final longRepeat = RegExp(
      r'(.{12,160}?)(?:\s*\1){2,}$',
      dotAll: true,
    ).firstMatch(trimmed);
    if (longRepeat != null) {
      final unit = longRepeat.group(1)!;
      if (RegExp(r'[\p{L}]', unicode: true).allMatches(unit).length >= 2) {
        return (
          text: trimmed.substring(0, longRepeat.start) + unit,
          detected: true,
        );
      }
    }

    final shortWordRepeat = RegExp(
      r'([\p{L}\p{N}]+(?:(?:\.{2,}|…|\s+|[,;:\-]+)[\p{L}\p{N}]+)+)(?:(?:\s+|[,;:\-…]+)*\1){2,}$',
      unicode: true,
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (shortWordRepeat != null) {
      final unit = shortWordRepeat.group(1)!;
      if (unit.length >= 6 &&
          RegExp(r'[\p{L}]', unicode: true).allMatches(unit).length >= 2) {
        return (
          text: trimmed.substring(0, shortWordRepeat.start) + unit,
          detected: true,
        );
      }
    }

    final repeatedClause = _trimRepeatedTrailingClause(trimmed);
    if (repeatedClause.detected) {
      return repeatedClause;
    }

    return (text: text, detected: false);
  }

  bool _looksLikeInvalidToolJson(String text) {
    if (M3xToolCallParser.looksLikeIncompleteToolCall(text)) return true;
    final trimmed = text.trim();
    if (!trimmed.startsWith('{') && !trimmed.startsWith('```')) return false;
    return RegExp(
      r'''["'](?:tool|method)["']\s*:|["']action["']\s*:\s*["']tool(?:_)?call["']''',
      caseSensitive: false,
    ).hasMatch(trimmed);
  }

  static final RegExp _openMidClauseTailRegex = RegExp(r'[,;:\-—(\[\{]$');
  static final RegExp _contractionApostropheTailRegex = RegExp(r"[A-Za-z0-9]['’]$");
  static final RegExp _terminalPunctTailRegex = RegExp(r'[.!?…"”’`\)\]。！？]$|"$');
  static final RegExp _trailingMarkdownWithTerminalRegex = RegExp(r'[.!?…"”’`\)\]。！？][*_]+$');
  static final RegExp _completeSentenceBoundaryRegex = RegExp(r'[.!?]["”’\)\]*_]*$');
  static final RegExp _draftToolNameRegex = RegExp(
    r'''["'](?:tool|method)["']\s*:\s*["']([^"']+)["']''',
    caseSensitive: false,
  );
  static final RegExp _draftEmptyArgsRegex = RegExp(
    r'''["'](?:args|arguments|params)["']\s*:\s*\{\s*\}''',
    caseSensitive: false,
  );

  bool _toolRequiresArguments(String toolName) {
    final normalized = toolName.trim();
    if (normalized.isEmpty) return false;
    final tool = toolRegistry.get(normalized);
    if (tool != null) {
      final req = tool.parameters['required'];
      if (req is List && req.isNotEmpty) return true;
      final props = tool.parameters['properties'];
      if (req == null && props is Map && props.isNotEmpty) return true;
      return false;
    }
    final mod = InternalToolsService.moduleForTool(normalized);
    if (mod != null) {
      for (final spec in mod.tools) {
        if (spec.name == normalized.toLowerCase()) {
          final req = spec.parameters['required'];
          if (req is List && req.isNotEmpty) return true;
          final props = spec.parameters['properties'];
          if (req == null && props is Map && props.isNotEmpty) return true;
          return false;
        }
      }
    }
    return false;
  }

  bool _isMalformedToolJsonDraft(String text) {
    if (!M3xToolCallParser.looksLikeIncompleteToolCall(text)) return false;
    if (_draftEmptyArgsRegex.hasMatch(text)) {
      final match = _draftToolNameRegex.firstMatch(text);
      final toolName = match?.group(1) ?? '';
      if (_toolRequiresArguments(toolName)) {
        return true;
      }
    }
    return false;
  }

  int effectiveMaxContinuationsFor(String text) {
    if (M3xToolCallParser.looksLikeIncompleteToolCall(text)) {
      return maxToolJsonContinuations;
    }
    return _isInsideCodeBlock(text) ? maxContinuations : maxProseContinuations;
  }

  static bool _endsAtCompleteSentenceBoundary(String text) {
    if (text.endsWith('\n\n') || RegExp(r'\n\s*\n$').hasMatch(text)) {
      return true;
    }
    final trimmed = text.trimRight();
    if (trimmed.isEmpty) return false;
    return _completeSentenceBoundaryRegex.hasMatch(trimmed);
  }

  static bool _isMissingFinishReason(String? reason) {
    final norm = reason?.trim() ?? '';
    if (norm.isEmpty) return true;
    final upper = norm.toUpperCase();
    return upper == 'NULL' || upper == 'UNKNOWN' || upper == 'FINISH_REASON_UNSPECIFIED';
  }

  static bool _isStopFinishReason(String? reason) {
    final norm = reason?.trim() ?? '';
    if (norm.isEmpty) return false;
    final upper = norm.toUpperCase();
    return norm == '0' || upper == 'STOP';
  }

  static int _countWords(String text) =>
      text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

  static const Set<String> _danglingTailWords = {
    'to', 'and', 'or', 'but', 'of', 'the', 'a', 'an', 'with', 'for', 'in',
    'on', 'at', 'by', 'from', 'into', 'about', 'as', 'that', 'which', 'who',
    'your', 'its', 'their', 'this', 'these', 'those', 'my', 'our', 'is', 'are',
    'was', 'were', 'can', 'will', 'would', 'should', 'could', 'may', 'might',
  };

  static const Set<String> _transitiveIngTailWords = {
    'ensuring', 'including', 'providing', 'creating', 'making', 'requiring',
    'involving', 'preventing', 'maintaining', 'developing', 'building',
    'allowing', 'enabling', 'reducing', 'increasing', 'supporting',
    'addressing', 'protecting', 'achieving', 'aligning', 'explaining',
    'illustrating', 'highlighting', 'leading', 'showing', 'demonstrating',
    'offering', 'using', 'trying', 'seeking', 'getting', 'taking', 'giving',
    'finding', 'keeping', 'holding', 'leaving', 'bringing',
  };

  static const Set<String> _ingLeadInWords = {
    'and', 'or', 'while', 'by', 'for', 'of', 'without', 'to', 'before',
    'after',
  };

  static const Set<String> _nonCutoffIngWords = {
    'morning', 'evening', 'nothing', 'something', 'anything', 'everything',
    'thing', 'being', 'feeling', 'meaning', 'missing', 'helping', 'asking',
    'waiting', 'listening', 'coming', 'going', 'working', 'happening',
    'existing', 'remaining', 'pending', 'lasting', 'willing', 'sharing',
    'caring', 'understanding', 'looking', 'talking', 'speaking', 'playing',
    'sleeping', 'running', 'walking', 'living', 'dying', 'ending', 'starting',
    'beginning', 'changing', 'growing', 'moving', 'standing', 'sitting',
    'falling', 'rising', 'raining', 'snowing', 'driving', 'traveling',
    'learning', 'studying', 'relaxing', 'resting', 'celebrating', 'improving',
    'recovering',
  };

  static bool _isLikelyTrailingIngParticiple(
    String lastWord,
    String penultWord,
  ) {
    if (!lastWord.endsWith('ing') || !RegExp(r'^[a-z]+$').hasMatch(lastWord)) {
      return false;
    }
    if (_nonCutoffIngWords.contains(lastWord)) return false;
    if (_transitiveIngTailWords.contains(lastWord)) return true;
    return lastWord.length >= 6 && _ingLeadInWords.contains(penultWord);
  }

  static const Set<String> _danglingPrepositionOrConjunctionWords = {
    'to', 'and', 'or', 'but', 'of', 'with', 'for', 'in', 'on', 'at', 'by',
    'from', 'into', 'about', 'as',
  };

  static bool _endsWithDanglingPrepositionOrConjunction(String text) {
    final trimmed = text.trimRight();
    if (trimmed.isEmpty) return false;
    final rawWords =
        trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (rawWords.isEmpty) return false;
    final lastWord = _normalizeCutoffToken(rawWords.last);
    return _danglingPrepositionOrConjunctionWords.contains(lastWord);
  }

  static const Set<String> _prepositionsBeforeDemonstrative = {
    'with', 'for', 'of', 'in', 'on', 'at', 'by', 'from', 'into', 'about',
    'to', 'like', 'after', 'before', 'without', 'under', 'over', 'between',
    'through',
  };

  static const Set<String> _modifierLeadInWords = {
    'with', 'for', 'in', 'on', 'at', 'by', 'from', 'into', 'of', 'to',
    'the', 'a', 'an', 'their', 'its', 'our', 'your', 'some', 'such',
  };

  static const Set<String> _knownTrailingModifiers = {
    'advanced', 'potential', 'modern', 'high', 'low', 'new', 'further',
    'certain', 'extreme', 'major', 'minor', 'critical', 'specific',
    'similar', 'various', 'several', 'multiple', 'complex', 'large', 'small',
    'strong', 'weak', 'wide', 'broad', 'narrow', 'direct', 'indirect',
    'proper', 'primary', 'secondary', 'unique', 'entire', 'exact',
    'accurate', 'precise', 'heavy', 'unsafe', 'dangerous', 'serious',
    'severe', 'significant', 'important', 'artificial', 'unintended',
    'unexpected', 'sophisticated', 'autonomous', 'intelligent',
    'superintelligent', 'global', 'digital', 'physical', 'mental', 'social',
    'medical', 'legal', 'moral', 'ethical', 'economic', 'political',
    'technical', 'practical', 'scientific', 'environmental',
    'computational', 'additional', 'existing', 'emerging', 'growing',
    'increasing', 'developing', 'evolving', 'underlying', 'surrounding',
    'remaining', 'following', 'preceding', 'leading', 'fundamental',
    'essential', 'vital', 'crucial', 'necessary', 'possible', 'unlikely',
    'available', 'effective', 'efficient', 'reliable', 'recent', 'current',
    'previous', 'next', 'different', 'highly', 'extremely', 'increasingly',
    'particularly', 'especially', 'potentially', 'significantly',
    'relatively', 'completely', 'fully', 'partially', 'rapidly', 'newly',
    'widely', 'closely', 'strongly', 'deeply', 'unusually', 'unexpectedly',
    'critically', 'severely', 'heavily', 'broadly',
  };

  static const Set<String> _nonModifierAlNouns = {
    'animal', 'hospital', 'capital', 'journal', 'festival', 'terminal',
    'general', 'material', 'mineral', 'individual', 'official', 'original',
    'crystal', 'arrival', 'survival', 'removal', 'approval', 'proposal',
    'refusal', 'disposal', 'betrayal', 'portrayal', 'funeral', 'cathedral',
    'scandal', 'sandal', 'mammal', 'manual', 'signal', 'casual', 'visual',
  };

  static const Set<String> _nonModifierIcNouns = {
    'public', 'classic', 'critic', 'fabric', 'plastic', 'static', 'metric',
    'clinic', 'picnic', 'traffic', 'garlic', 'tropic', 'mosaic', 'tunic',
    'relic', 'attic', 'comic', 'topic', 'music', 'logic', 'magic', 'panic',
    'basic',
  };

  static const Set<String> _nonModifierIveNouns = {
    'native', 'motive', 'archive', 'detective', 'narrative', 'objective',
    'directive', 'adjective', 'executive', 'initiative', 'alternative',
    'perspective', 'representative', 'incentive',
  };

  static const Set<String> _nonModifierBleNouns = {
    'vegetable', 'syllable', 'parable', 'variable', 'portable', 'timetable',
    'turntable', 'constable', 'mandible', 'crucible',
  };

  static const Set<String> _nonModifierRyNouns = {
    'library', 'january', 'february', 'summary', 'history', 'factory',
    'category', 'century', 'country', 'victory', 'mystery', 'battery',
    'gallery', 'surgery', 'delivery', 'recovery', 'discovery', 'scenery',
    'grocery', 'bakery', 'salary', 'glossary', 'boundary', 'dictionary',
    'vocabulary', 'secretary', 'commentary', 'documentary', 'anniversary',
    'territory', 'directory', 'inventory', 'laboratory', 'dormitory',
    'observatory', 'trajectory', 'accessory', 'memory', 'theory',
  };

  static const Set<String> _nonModifierNtNouns = {
    'moment', 'present', 'client', 'student', 'parent', 'patient', 'percent',
    'incident', 'accident', 'resident', 'president', 'assistant', 'merchant',
    'servant', 'restaurant', 'elephant', 'account', 'amount', 'extent',
    'intent', 'consent', 'content', 'talent', 'contestant', 'participant',
    'consultant', 'accountant', 'defendant', 'applicant', 'inhabitant',
    'immigrant', 'sergeant', 'lieutenant', 'peasant', 'tenant', 'tyrant',
    'infant', 'mutant', 'pendant', 'quadrant', 'remnant', 'covenant',
    'solvent', 'agent', 'opponent', 'component', 'exponent', 'recipient',
    'coefficient', 'ingredient', 'nutrient', 'gradient', 'quotient', 'orient',
    'torrent', 'garment', 'segment', 'fragment',
  };

  static String _normalizeCutoffToken(String raw) => raw
      .toLowerCase()
      .replaceAll(RegExp(r'''^["'“‘(\[\{*_`]+|["'”’)\]\},;:*_`]+$'''), '');

  static bool _isLikelyTrailingModifier(String word) {
    if (word.length < 3 || !RegExp(r'^[a-z]+$').hasMatch(word)) return false;
    if (_knownTrailingModifiers.contains(word)) return true;
    if (word.length >= 6 && word.endsWith('ous')) return true;
    if (word.length >= 6 &&
        (word.endsWith('ful') || word.endsWith('less'))) {
      return true;
    }
    if (word.length >= 6 &&
        word.endsWith('ed') &&
        !word.endsWith('eed') &&
        word != 'hundred') {
      return true;
    }
    if (word.length >= 7 &&
        word.endsWith('al') &&
        !_nonModifierAlNouns.contains(word)) {
      return true;
    }
    if (word.length >= 6 &&
        word.endsWith('ic') &&
        !_nonModifierIcNouns.contains(word)) {
      return true;
    }
    if (word.length >= 6 &&
        word.endsWith('ive') &&
        !_nonModifierIveNouns.contains(word)) {
      return true;
    }
    if (word.length >= 7 &&
        (word.endsWith('able') || word.endsWith('ible')) &&
        !_nonModifierBleNouns.contains(word)) {
      return true;
    }
    if (word.length >= 7 &&
        (word.endsWith('ary') || word.endsWith('ory')) &&
        !_nonModifierRyNouns.contains(word)) {
      return true;
    }
    if (word.length >= 6 &&
        (word.endsWith('ant') || word.endsWith('ent')) &&
        !word.endsWith('ment') &&
        !_nonModifierNtNouns.contains(word)) {
      return true;
    }
    return false;
  }

  static bool isLikelyMidClauseCutoff(String text) {
    final trimmed = text.trimRight();
    if (trimmed.isEmpty) return false;
    if (_openMidClauseTailRegex.hasMatch(trimmed)) return true;
    if (_contractionApostropheTailRegex.hasMatch(trimmed)) return true;
    if (_trailingMarkdownWithTerminalRegex.hasMatch(trimmed)) return false;
    if (_terminalPunctTailRegex.hasMatch(trimmed)) return false;

    final rawWords =
        trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (rawWords.isEmpty) return false;

    final lastWord = _normalizeCutoffToken(rawWords.last);
    final penultWord = rawWords.length >= 2
        ? _normalizeCutoffToken(rawWords[rawWords.length - 2])
        : '';

    if (rawWords.length >= 2 && _danglingTailWords.contains(lastWord)) {
      final isDemonstrativeObject =
          (lastWord == 'that' ||
              lastWord == 'this' ||
              lastWord == 'these' ||
              lastWord == 'those') &&
          _prepositionsBeforeDemonstrative.contains(penultWord);
      if (!isDemonstrativeObject) {
        return true;
      }
    }

    if (rawWords.length >= 4 &&
        _modifierLeadInWords.contains(penultWord) &&
        _isLikelyTrailingModifier(lastWord)) {
      return true;
    }

    if (rawWords.length >= 4 &&
        _isLikelyTrailingIngParticiple(lastWord, penultWord)) {
      return true;
    }

    return false;
  }

  static final RegExp _priorSentenceEndRegex =
      RegExp(r'[.!?。！？]["”’\x27\)\]\*_]*(?=\s+\S)');

  /// Trims a trailing incomplete sentence/clause at final commit when a prior
  /// complete sentence (`>= 25` chars) exists in [text]. Preserves single-sentence
  /// texts, complete texts, code blocks, and tool JSON drafts unchanged.
  static String trimTrailingIncompleteSentence(String text) {
    final trimmed = text.trimRight();
    if (trimmed.isEmpty) return text;
    if (RegExp(r'```').allMatches(trimmed).length % 2 == 1) return text;
    if (M3xToolCallParser.looksLikeIncompleteToolCall(trimmed)) return text;
    if (!isLikelyMidClauseCutoff(trimmed)) return text;

    final matches = _priorSentenceEndRegex.allMatches(trimmed).toList();
    for (int i = matches.length - 1; i >= 0; i--) {
      final candidatePrefix =
          trimmed.substring(0, matches[i].end).trimRight();
      if (candidatePrefix.length >= 25 &&
          !isLikelyMidClauseCutoff(candidatePrefix)) {
        return candidatePrefix;
      }
    }
    return text;
  }

  @visibleForTesting
  bool shouldContinueOnDoneForTest(
    String? reason,
    String text, {
    int? lastRoundAddedNonWs,
    int? continuationCount,
    int? nullReasonCount,
    int? stopCutoffCount,
    bool? isSynthesis,
  }) =>
      _shouldContinueOnDone(
        reason,
        text,
        lastRoundAddedNonWs: lastRoundAddedNonWs,
        continuationCountOverride: continuationCount,
        nullReasonCountOverride: nullReasonCount,
        stopCutoffCountOverride: stopCutoffCount,
        isSynthesisOverride: isSynthesis,
      );

  bool _shouldContinueOnDone(
    String? reason,
    String text, {
    int? lastRoundAddedNonWs,
    int? continuationCountOverride,
    int? nullReasonCountOverride,
    int? stopCutoffCountOverride,
    bool? isSynthesisOverride,
  }) {
    final effectiveCount = continuationCountOverride ?? _continuationCount;
    final effectiveNullCount = nullReasonCountOverride ?? _nullReasonContinuationCount;
    final effectiveStopCutoffCount =
        stopCutoffCountOverride ?? _stopCutoffContinuationCount;
    if (text.trim().isEmpty) return false;
    if (text.length >= maxContinuationChars) return false;
    if (lastRoundAddedNonWs != null && lastRoundAddedNonWs <= 0) return false;

    final bool isToolDraft = M3xToolCallParser.looksLikeIncompleteToolCall(text);
    if (isToolDraft && _isMalformedToolJsonDraft(text)) {
      return false;
    }
    if (effectiveCount >= effectiveMaxContinuationsFor(text)) {
      return false;
    }

    final bool insideCodeBlock = _isInsideCodeBlock(text);
    if (!insideCodeBlock && !isToolDraft) {
      if (text.length >= maxProseHardStopChars) {
        return false;
      }
      if (text.length >= maxProseSoftStopChars &&
          _endsAtCompleteSentenceBoundary(text)) {
        return false;
      }
    }

    final norm = reason?.trim() ?? '';
    final upper = norm.toUpperCase();
    if (!_isMissingFinishReason(norm)) {
      if (norm == "1" ||
          norm == "-100" ||
          upper == "OTHER" ||
          upper == "MAX_TOKENS" ||
          upper == "LIMIT" ||
          upper.contains("MAX_TOKENS") ||
          upper.contains("LIMIT")) {
        return true;
      }
      if (_isStopFinishReason(norm)) {
        if (!isNanoV4Active &&
            !insideCodeBlock &&
            !isToolDraft &&
            effectiveStopCutoffCount < maxStopCutoffContinuations &&
            text.length < maxProseSoftStopChars) {
          final trimmed = text.trimRight();
          final hasHardTokenCut =
              _contractionApostropheTailRegex.hasMatch(trimmed) ||
                  _openMidClauseTailRegex.hasMatch(trimmed);
          if (hasHardTokenCut) {
            return true;
          }
          final int minWords =
              _endsWithDanglingPrepositionOrConjunction(text) ? 2 : 4;
          if (_countWords(text) >= minWords &&
              isLikelyMidClauseCutoff(text)) {
            return true;
          }
        }
        return false;
      }
    }

    if (!_forcedFinalSynthesis && isToolDraft) {
      return true;
    }

    if (!isNanoV4Active &&
        _isMissingFinishReason(norm) &&
        effectiveNullCount < maxNullReasonContinuations &&
        isLikelyMidClauseCutoff(text)) {
      return true;
    }
    return false;
  }

  static final RegExp _pureGreetingTrailingPunctuation =
      RegExp(r'[!.,?~…]+$');
  static final RegExp _openingJsonFenceSuffix =
      RegExp(r'```(?:json)?\s*$', caseSensitive: false);
  static final RegExp _closingFencePrefix = RegExp(r'^\s*```');
  static const Set<String> _pureGreetings = {
    'hi',
    'hello',
    'hey',
    'heyo',
    'sup',
    'greetings',
    'привіт',
    'добрий день',
  };

  bool _isPureGreeting(String userPrompt) {
    final normalized = userPrompt
        .trim()
        .toLowerCase()
        .replaceAll(_pureGreetingTrailingPunctuation, '')
        .trim();
    return _pureGreetings.contains(normalized);
  }

  static int _findBalancedBraceEnd(String text, int startIdx) {
    int depth = 0;
    bool inString = false;
    int stringQuote = 0;
    bool escapeNext = false;

    for (int i = startIdx; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if (inString) {
        if (escapeNext) {
          escapeNext = false;
          continue;
        }
        if (code == 0x5C /* '\' */) {
          escapeNext = true;
          continue;
        }
        if (code == stringQuote) {
          inString = false;
          stringQuote = 0;
        }
        continue;
      }
      if (code == 0x22 /* '"' */ || code == 0x27 /* "'" */) {
        inString = true;
        stringQuote = code;
      } else if (code == 0x7B /* '{' */) {
        depth++;
      } else if (code == 0x7D /* '}' */) {
        depth--;
        if (depth == 0) {
          return i;
        }
      }
    }
    return -1;
  }

  /// Strips an accidental trailing JSON tool-call block (complete or truncated)
  /// when conversational or refusal prose precedes it. Returns `null` if no
  /// such block with preceding prose is present.
  String? _stripGreetingAccidentalToolBlock(String text) {
    for (int i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) != 0x7B /* '{' */) continue;

      final endIdx = _findBalancedBraceEnd(text, i);
      final bool isToolJson = endIdx != -1
          ? M3xToolCallParser.extract(text.substring(i, endIdx + 1)) != null
          : M3xToolCallParser.looksLikeIncompleteToolCall(text.substring(i));
      if (!isToolJson) {
        if (endIdx != -1) i = endIdx;
        continue;
      }

      int blockStart = i;
      final fenceMatch =
          _openingJsonFenceSuffix.firstMatch(text.substring(0, i));
      if (fenceMatch != null) {
        blockStart = fenceMatch.start;
      }

      final before = text.substring(0, blockStart).trimRight();
      if (before.isEmpty) {
        return null;
      }

      if (endIdx == -1) {
        return before;
      }

      int blockEnd = endIdx + 1;
      final closeFence =
          _closingFencePrefix.firstMatch(text.substring(blockEnd));
      if (closeFence != null) {
        blockEnd += closeFence.end;
      }
      final after = text.substring(blockEnd).trimLeft();
      return after.isEmpty ? before : '$before\n\n$after'.trim();
    }
    return null;
  }

  static String _normalizeCtrlObjectToJson(String rawObj) {
    final out = StringBuffer();
    int i = 0;
    while (i < rawObj.length) {
      final ch = rawObj[i];
      if (ch == '"' || ch == "'") {
        final quote = ch;
        out.write('"');
        i++;
        bool escaped = false;
        while (i < rawObj.length) {
          final c = rawObj[i];
          if (escaped) {
            out.write(c);
            escaped = false;
          } else if (c == r'\') {
            out.write(c);
            escaped = true;
          } else if (c == quote) {
            out.write('"');
            i++;
            break;
          } else if (quote == "'" && c == '"') {
            out.write(r'\"');
          } else {
            out.write(c);
          }
          i++;
        }
        continue;
      }
      if (RegExp(r'[A-Za-z_]').hasMatch(ch)) {
        final prevNonWs = _lastNonWhitespaceChar(out);
        if (prevNonWs == '{' || prevNonWs == ',') {
          int end = i + 1;
          while (end < rawObj.length &&
              RegExp(r'[A-Za-z0-9_]').hasMatch(rawObj[end])) {
            end++;
          }
          int afterWs = end;
          while (afterWs < rawObj.length &&
              (rawObj[afterWs] == ' ' ||
                  rawObj[afterWs] == '\t' ||
                  rawObj[afterWs] == '\n' ||
                  rawObj[afterWs] == '\r')) {
            afterWs++;
          }
          if (afterWs < rawObj.length && rawObj[afterWs] == ':') {
            out.write('"');
            out.write(rawObj.substring(i, end));
            out.write('"');
            i = end;
            continue;
          }
        }
      }
      out.write(ch);
      i++;
    }
    return out.toString().replaceAll(RegExp(r',\s*([}\]])'), r'$1');
  }

  static String? _lastNonWhitespaceChar(StringBuffer buf) {
    final s = buf.toString();
    for (int i = s.length - 1; i >= 0; i--) {
      final c = s[i];
      if (c != ' ' && c != '\t' && c != '\n' && c != '\r') {
        return c;
      }
    }
    return null;
  }

  Map<String, dynamic>? _extractCtrlToolCall(String text) {
    for (final match in _ctrlToolCallPrefixRegex.allMatches(text)) {
      final rawName = match.group(1)?.trim() ?? '';
      if (rawName.isEmpty) continue;
      final openBrace = match.end - 1;
      final closeBrace = _findBalancedBraceEnd(text, openBrace);
      if (closeBrace == -1) continue;
      final rawArgs = text.substring(openBrace, closeBrace + 1);
      Map<String, dynamic>? argsMap;
      try {
        final decoded = jsonDecode(rawArgs);
        if (decoded is Map) {
          argsMap = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
      if (argsMap == null) {
        try {
          final normalized = _normalizeCtrlObjectToJson(rawArgs);
          final decoded = jsonDecode(normalized);
          if (decoded is Map) {
            argsMap = Map<String, dynamic>.from(decoded);
          }
        } catch (_) {}
      }
      if (argsMap == null) continue;

      String toolName =
          rawName.contains(':') ? rawName.split(':').last.trim() : rawName;
      String? appName;
      if (toolName.contains('.') &&
          toolRegistry.get(toolName) == null &&
          InternalToolsService.moduleForTool(toolName) == null) {
        final parts = toolName.split('.');
        if (parts.length == 2 &&
            (toolRegistry.get(parts[1]) != null ||
                InternalToolsService.moduleForTool(parts[1]) != null)) {
          appName = parts[0];
          toolName = parts[1];
        }
      }
      return <String, dynamic>{
        'tool': toolName,
        if (appName != null && appName.isNotEmpty) 'app': appName,
        'arguments': argsMap,
      };
    }
    return null;
  }

  Map<String, dynamic>? _extractToolCall(
    String text, {
    required String userPrompt,
    bool mutateResponseOnGreeting = true,
  }) {
    if (_isPureGreeting(userPrompt)) {
      final sanitized = _stripGreetingAccidentalToolBlock(text);
      if (sanitized != null) {
        if (mutateResponseOnGreeting) {
          responseText = sanitized;
          _combinedResponse = sanitized;
        }
        return null;
      }
    }
    return M3xToolCallParser.extract(text) ?? _extractCtrlToolCall(text);
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
    if (RegExp(r'\bfound\s*:\s*true\b', caseSensitive: false).hasMatch(trimmed) &&
        RegExp(r'\b(extract|description|url|details)\s*:', caseSensitive: false)
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

  String _formatReadableToolSummary(String toolName, dynamic decoded) {
    return InternalToolsService.formatResultForSynthesis(toolName, decoded);
  }

  String _buildRecoverableErrorHint(String toolName, String errorMessage) {
    return 'Tool call "$toolName" failed: $errorMessage. '
        'Inspect the available tool schemas and retry once with valid parameters '
        '(or call a prerequisite discovery/list tool first if an identifier is missing), '
        'or explain the issue clearly if it cannot be resolved.';
  }

  String _dictValueOrFallback(String key, String fallback) {
    final val = dict.value(key);
    if (val.isEmpty ||
        val == "Loading..." ||
        val == key ||
        val.startsWith("!!!")) {
      return fallback;
    }
    return val;
  }

  String _buildIncompleteToolFallback() {
    if (_lastToolFailed && _lastToolErrorText.isNotEmpty) {
      final appLabel = _lastToolCall?.app?.trim();
      final hasInfraApp =
          _lastToolErrorIsInfra && appLabel != null && appLabel.isNotEmpty;
      final scope = hasInfraApp ? " from '$appLabel'" : '';
      final fallback = "Unable to retrieve live data$scope: $_lastToolErrorText";
      final raw = _dictValueOrFallback('tool_fallback_infra_error', fallback);
      return raw
          .replaceAll('{app}', hasInfraApp ? appLabel : 'the connected app')
          .replaceAll('{error}', _lastToolErrorText);
    }
    if (_lastToolResultPayload.isNotEmpty) {
      try {
        final decoded = jsonDecode(_lastToolResultPayload);
        return _formatReadableToolSummary(_lastToolCall?.tool ?? '', decoded);
      } catch (_) {
        final toolName = _lastToolCall?.tool.trim() ?? '';
        final toolLabel = toolName.isNotEmpty ? toolName : 'the requested action';
        final fallback =
            "Completed $toolLabel, but could not format the response.";
        final raw =
            _dictValueOrFallback('tool_fallback_partial_error', fallback);
        return raw.replaceAll('{tool}', toolLabel);
      }
    }
    return _dictValueOrFallback(
      'tool_fallback_invalid_request',
      "The assistant could not complete a valid tool request for this query. Please try rephrasing or try again.",
    );
  }

  /// Handles unexpected native stream closure without a terminal Done/Error event.
  void _handleUnexpectedStreamClose(int myGenId, bool receivedTerminalEvent) {
    if (myGenId != _streamGenerationId ||
        _disposed ||
        receivedTerminalEvent ||
        _activeToolHandling) {
      return;
    }
    _aiSubscription = null;
    final wasSynthesizing = _isSynthesizing;
    _resetTurnLifecycleFlags();

    final candidate = responseText.trim().isNotEmpty
        ? responseText
        : _combinedResponse;
    final hasValidPartial = candidate.trim().isNotEmpty &&
        !M3xToolCallParser.looksLikeIncompleteToolCall(candidate) &&
        !_looksLikeInvalidToolJson(candidate);

    if (hasValidPartial && !isError) {
      responseText = candidate;
      if (wasSynthesizing) {
        unawaited(
          _commitSynthesisMessage(
            candidate,
            logNote: "Tool synthesis committed after unexpected stream close",
          ),
        );
        return;
      }
      status = "Stream complete";
      unawaited(() async {
        await addToContext();
        prompt.clear();
        unawaited(_captureVisualMemoryIfNeeded());
        genericRefresh();
      }());
      return;
    }

    responseText = "";
    lastPrompt = "";
    _clearThoughtChunk();
    _combinedResponse = "";
    _currentSynthesisPrompt = "";
    streamingMessageTime = null;
    streamingUserMessageTime = null;
    if (!isError) {
      status = "Stream complete";
    }
    genericRefresh();
  }

  /// Retries Turn-1 once WITHOUT tools when Nano outputs an incomplete or invalid
  /// tool-call draft for a conceptual/non-tool query.
  Future<void> _triggerToolFreeFallbackAnswer(String originalUserPrompt) async {
    _toolFreeFallbackUsed = true;
    final int myGenId = ++_streamGenerationId;
    bool receivedTerminalEvent = false;

    _resetTurnLifecycleFlags();
    _forcedFinalSynthesis = true;
    isLoading = true;
    isGenerating = true;
    isError = false;
    responseText = "";
    _clearThoughtChunk();
    _lastFinishReason = "";
    _combinedResponse = "";
    _continuationCount = 0;
    _nullReasonContinuationCount = 0;
    _stopCutoffContinuationCount = 0;
    streamingMessageTime = DateTime.now();
    status = "Retrying without tools...";
    notifyListeners();

    await log(
      "mesh",
      "warning",
      "Tool request invalid/incomplete on turn 1; retrying without tools",
    );
    if (myGenId != _streamGenerationId || _disposed) return;

    final prevSub = _aiSubscription;
    _aiSubscription = null;
    await prevSub?.cancel();
    if (myGenId != _streamGenerationId || _disposed) return;

    final String? imagePath = chatData.lastImagePath;
    final bool hasAttachedImage =
        imagePath != null && imagePath.trim().isNotEmpty;

    await initEngine(includeTools: false, hasAttachedImage: hasAttachedImage);
    if (myGenId != _streamGenerationId || _disposed) return;

    if (isError || (!isInitializing && !isInitialized) || isAiCoreKnownUnavailable) {
      _resetTurnLifecycleFlags();
      responseText = _buildIncompleteToolFallback();
      status = "Done";
      await addToContext();
      prompt.clear();
      notifyListeners();
      return;
    }

    final effectivePrompt = originalUserPrompt.trim().isNotEmpty
        ? originalUserPrompt.trim()
        : (lastPrompt.trim().isNotEmpty
            ? lastPrompt.trim()
            : "Please answer my previous question.");
    lastPrompt = effectivePrompt;
    final userTurnPrompt = hasAttachedImage
        ? "[Image attached to this message]\nUser's request: $effectivePrompt"
        : "User's request: $effectivePrompt";
    final double runTemperature = chatData.chats.containsKey(currentChat) &&
            chatData.chats[currentChat].containsKey("chatTemperature")
        ? chatData.chats[currentChat]["chatTemperature"]
        : temperature;

    final stream = gemini.generateTextEvents(
      prompt: userTurnPrompt,
      config: GenerationConfig(
        temperature: runTemperature,
        enableThinking: effectiveEnableThinking,
      ),
      stream: true,
      imageBytes: _turnImageBytesForMemory,
      imagePath: imagePath,
      downsample: config.downsampleImages,
    );

    _aiSubscription = stream.listen(
      (AiEvent event) async {
        if (myGenId != _streamGenerationId || _disposed) return;
        switch (event.status) {
          case AiEventStatus.loading:
            isLoading = true;
            responseText = "";
            status = dict.value("waiting_for_AI");
            notifyListeners();
            break;

          case AiEventStatus.streaming:
            isLoading = true;
            streamingMessageTime = DateTime.now();
            status = "Streaming response...";
            _appendThoughtChunk(event.thought);
            final String? fr = event.response?.finishReason;
            if (fr != null && fr != "null" && fr.isNotEmpty) {
              _lastFinishReason = fr;
            }
            if (event.response != null) {
              response = event.response!;
              responseText = stripLeadingEllipsis(event.response!.text);
            }
            try {
              scrollChatlog(const Duration(milliseconds: 250));
            } catch (_) {}
            break;

          case AiEventStatus.done:
            receivedTerminalEvent = true;
            _appendThoughtChunk(event.thought);
            final String? doneReason = _lastFinishReason.isNotEmpty
                ? _lastFinishReason
                : event.reason;

            final bool emittedTool = M3xToolCallParser.extract(responseText) != null ||
                _extractCtrlToolCall(responseText) != null ||
                M3xToolCallParser.looksLikeIncompleteToolCall(responseText) ||
                _looksLikeInvalidToolJson(responseText);
            if (emittedTool || responseText.trim().isEmpty) {
              await log(
                "mesh",
                "error",
                "Tool-free fallback retry also failed or emitted tool JSON; committing fallback message.",
              );
              if (myGenId != _streamGenerationId || _disposed) return;
              responseText = _buildIncompleteToolFallback();
              _resetTurnLifecycleFlags();
              status = "Done";
              await addToContext();
              prompt.clear();
              unawaited(_captureVisualMemoryIfNeeded());
              break;
            }

            final bool shouldContinue = _shouldContinueOnDone(doneReason, responseText);
            if (shouldContinue) {
              cumulativeGenerationMs += response.generationTimeMs?.toInt() ?? 0;
              cumulativeTokenCount += response.tokenCount?.toInt() ?? 0;
              if (_isMissingFinishReason(doneReason)) {
                _nullReasonContinuationCount++;
              } else if (_isStopFinishReason(doneReason)) {
                _stopCutoffContinuationCount++;
              }
              _continuationCount++;
              _combinedResponse = responseText;
              await continueGenerating();
            } else {
              responseText = trimTrailingIncompleteSentence(responseText);
              _resetTurnLifecycleFlags();
              status = "Done";
              await addToContext();
              prompt.clear();
              unawaited(_captureVisualMemoryIfNeeded());
            }
            break;

          case AiEventStatus.error:
            receivedTerminalEvent = true;
            _resetTurnLifecycleFlags();
            responseText = _buildIncompleteToolFallback();
            status = "Done";
            await addToContext();
            prompt.clear();
            break;
        }
        genericRefresh();
      },
      onError: (e) async {
        if (myGenId != _streamGenerationId || _disposed) return;
        receivedTerminalEvent = true;
        _resetTurnLifecycleFlags();
        responseText = _buildIncompleteToolFallback();
        status = "Done";
        await addToContext();
        prompt.clear();
        genericRefresh();
      },
      onDone: () => _handleUnexpectedStreamClose(myGenId, receivedTerminalEvent),
    );
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
    // Show full accumulated text immediately while continuation fires up
    responseText = _combinedResponse;
    notifyListeners();

    final prevSub = _aiSubscription;
    _aiSubscription = null;
    await prevSub?.cancel();
    if (myGenId != _streamGenerationId || _disposed) return;

    // Use the continuation-specific init: system-level [CONTINUATION] directive,
    // no user turn, so the model simply outputs more text without addressing anyone
    await _initForContinuation(_combinedResponse, isSynthesis: isSynthesis);
    if (myGenId != _streamGenerationId || _disposed) return;

    final double runTemperature = chatData.chats.containsKey(currentChat) && chatData.chats[currentChat].containsKey("chatTemperature") ? chatData.chats[currentChat]["chatTemperature"] : temperature;

    // Send a minimal system cue — the actual instruction is in the system prompt
    // This is NOT shown to the user and does NOT appear as a user message in context
    final stream = gemini.generateTextEvents(
      prompt: "Continue.",
      config: GenerationConfig(
        temperature: runTemperature,
        enableThinking: effectiveEnableThinking,
      ), // no token cap
      stream: true,
    );

    _aiSubscription = stream.listen(
      (AiEvent event) async {
        if (myGenId != _streamGenerationId || _disposed) return;
        switch (event.status) {
          case AiEventStatus.loading:
            status = dict.value("waiting_for_AI");
            notifyListeners();
            break;

          case AiEventStatus.streaming:
            streamingMessageTime = DateTime.now();
            final bool hasThought =
                event.thought != null && event.thought!.trim().isNotEmpty;
            _appendThoughtChunk(event.thought);
            final String? fr = event.response?.finishReason;
            if (fr != null && fr != "null" && fr.isNotEmpty) {
              _lastFinishReason = fr;
            }
            if (event.response != null) {
              response = event.response!;
              // Dynamically re-stitch cumulative response.text against _combinedResponse
              // so multi-token overlaps are deduplicated live without freezing on token 1.
              responseText = stitchContinuation(_combinedResponse, event.response!.text);
            }
            if (hasThought || (event.response != null && responseText != _combinedResponse)) {
              isContinuing = false;
            }
            try { scrollChatlog(Duration(milliseconds: 250)); } catch (_) {}
            break;

          case AiEventStatus.done:
            receivedTerminalEvent = true;
            _appendThoughtChunk(event.thought);
            final String? contDoneReason = _lastFinishReason.isNotEmpty
                ? _lastFinishReason
                : event.reason;

            final stitchMeta =
                _stitchContinuationWithMeta(_combinedResponse, response.text);
            String stitched = stitchMeta.text;
            if (!_isSynthesizing && _isPureGreeting(lastPrompt)) {
              final stripped = _stripGreetingAccidentalToolBlock(stitched);
              if (stripped != null) {
                await log(
                  "mesh",
                  "info",
                  "Stripped accidental trailing tool JSON after greeting prose (continuation).",
                );
                if (myGenId != _streamGenerationId || _disposed) return;
                stitched = stripped;
              }
            }

            final stutterCheck = detectAndTrimStutterLoop(stitched);
            final bool loopDetected =
                stitchMeta.trimmedLoop || stutterCheck.detected;
            if (loopDetected) {
              await log(
                "model",
                "warning",
                "Detected and trimmed continuation stutter loop at round #$_continuationCount.",
                sendRemote: false,
              );
              if (myGenId != _streamGenerationId || _disposed) return;
              stitched = stutterCheck.text;
            }

            final int prevNonWs =
                _combinedResponse.replaceAll(RegExp(r'\s+'), '').length;
            final int nextNonWs =
                stitched.replaceAll(RegExp(r'\s+'), '').length;
            final int netAddedNonWs = nextNonWs - prevNonWs;

            // Update accumulator and displayed responseText consistently
            _combinedResponse = stitched;
            responseText = stitched;

            // Note: stats are only added to cumulative when RECURSING (see cutAgain branch).
            // On the commit path we leave them in response.x so the UI formula
            // cumulative + response.x is always correct without double-counting.
            if (kDebugMode) print("[AUTO-CONTINUE DONE] reason=$contDoneReason netAddedNonWs=$netAddedNonWs");
            await log(
              "model",
              "info",
              "Continuation #$_continuationCount done. finishReason=$contDoneReason (nanoV4=$isNanoV4Active, netNonWs=$netAddedNonWs, stutter=$loopDetected, totalChars=${responseText.length})",
              sendRemote: false,
            );
            if (myGenId != _streamGenerationId || _disposed) return;

            bool cutAgain = _shouldContinueOnDone(
              contDoneReason,
              responseText,
              lastRoundAddedNonWs: netAddedNonWs,
            );
            if (netAddedNonWs <= 0 || loopDetected) {
              cutAgain = false;
            }

            if (cutAgain) {
              // Snapshot this session's stats into cumulative before starting the next round
              cumulativeGenerationMs += response.generationTimeMs?.toInt() ?? 0;
              cumulativeTokenCount += response.tokenCount?.toInt() ?? 0;
              if (_isMissingFinishReason(contDoneReason) &&
                  !M3xToolCallParser.looksLikeIncompleteToolCall(responseText)) {
                _nullReasonContinuationCount++;
              } else if (_isStopFinishReason(contDoneReason)) {
                _stopCutoffContinuationCount++;
              }
              _continuationCount++;
              await continueGenerating(isSynthesis: _isSynthesizing);
            } else {
              final completedToolMap = _isSynthesizing
                  ? (M3xToolCallParser.extract(responseText) ??
                      _extractCtrlToolCall(responseText))
                  : _extractToolCall(responseText, userPrompt: lastPrompt);
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

              final bool badToolDraft =
                  M3xToolCallParser.looksLikeIncompleteToolCall(responseText) ||
                      _looksLikeInvalidToolJson(responseText);
              if (!_isSynthesizing &&
                  badToolDraft &&
                  !_toolFreeFallbackUsed &&
                  !_lastToolFailed &&
                  _lastToolResultPayload.isEmpty) {
                await _triggerToolFreeFallbackAnswer(lastPrompt);
                break;
              }

              if (badToolDraft ||
                  (_isSynthesizing &&
                      (_looksLikeUnformattedToolEcho(responseText) ||
                          _looksLikeHallucinatedNormalOnError(responseText)))) {
                await log("mesh", "error", "Discarding incomplete or unformatted tool response after continuation: $responseText");
                if (myGenId != _streamGenerationId || _disposed) return;
                responseText = _buildIncompleteToolFallback();
              } else {
                responseText = trimTrailingIncompleteSentence(responseText);
                _combinedResponse = responseText;
              }

              // Commit — cumulative stays as-is; UI shows cumulative + response.x = total
              final wasSynthesizing = _isSynthesizing;
              _resetTurnLifecycleFlags();
              status = "Done";

              if (wasSynthesizing) {
                final committedText = responseText;
                final trimmedThought = _sanitizeThoughtChunk(currentThoughtChunk).trim();
                final commitTime = streamingMessageTime ?? DateTime.now();
                responseText = "";
                _clearThoughtChunk();
                streamingMessageTime = null;
                streamingUserMessageTime = null;
                prompt.clear();
                lastPrompt = "";
                _currentSynthesisPrompt = "";
                await chatData.appendMessage(
                  user: "Gemini",
                  author: assistantAuthorLabel,
                  message: committedText,
                  time: commitTime,
                  thoughtProcess: trimmedThought.isNotEmpty ? trimmedThought : null,
                );
                await log("mesh", "info", "Tool synthesis complete (via continuation)");
                await chatData.saveChat(chatData.context, chatID: chatData.currentChat);
                _checkAndTriggerTitle();
                unawaited(_captureVisualMemoryIfNeeded());
                try {
                  scrollChatlog(const Duration(milliseconds: 250));
                } catch (_) {}
              } else {
                await addToContext();
                prompt.clear();
                unawaited(_captureVisualMemoryIfNeeded());

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
            final wasSynthesizing = _isSynthesizing;
            _resetTurnLifecycleFlags();
            isError = true;
            status = "Error during continuation";
            if (wasSynthesizing) {
              if (_combinedResponse.isNotEmpty &&
                  !M3xToolCallParser.looksLikeIncompleteToolCall(_combinedResponse)) {
                final committedText = _combinedResponse;
                responseText = "";
                final trimmedThought = _sanitizeThoughtChunk(currentThoughtChunk).trim();
                final commitTime = streamingMessageTime ?? DateTime.now();
                await chatData.appendMessage(
                  user: "Gemini",
                  author: assistantAuthorLabel,
                  message: committedText,
                  time: commitTime,
                  thoughtProcess: trimmedThought.isNotEmpty ? trimmedThought : null,
                );
                prompt.clear();
                lastPrompt = "";
              }
              _clearThoughtChunk();
              streamingMessageTime = null;
              streamingUserMessageTime = null;
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
              _clearThoughtChunk();
              streamingMessageTime = null;
              streamingUserMessageTime = null;
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
        if (myGenId != _streamGenerationId || _disposed) return;
        receivedTerminalEvent = true;
        final wasSynthesizing = _isSynthesizing;
        _resetTurnLifecycleFlags();
        if (wasSynthesizing) {
          if (_combinedResponse.isNotEmpty &&
              !M3xToolCallParser.looksLikeIncompleteToolCall(_combinedResponse)) {
            final committedText = _combinedResponse;
            responseText = "";
            final trimmedThought = _sanitizeThoughtChunk(currentThoughtChunk).trim();
            final commitTime = streamingMessageTime ?? DateTime.now();
            await chatData.appendMessage(
              user: "Gemini",
              author: assistantAuthorLabel,
              message: committedText,
              time: commitTime,
              thoughtProcess: trimmedThought.isNotEmpty ? trimmedThought : null,
            );
            prompt.clear();
            lastPrompt = "";
          }
          _clearThoughtChunk();
          streamingMessageTime = null;
          streamingUserMessageTime = null;
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
            _clearThoughtChunk();
            streamingMessageTime = null;
            streamingUserMessageTime = null;
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
      onDone: () => _handleUnexpectedStreamClose(myGenId, receivedTerminalEvent),
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
    responseText = "";
    final trimmedThought = _sanitizeThoughtChunk(currentThoughtChunk).trim();
    final commitTime = streamingMessageTime ?? DateTime.now();
    _clearThoughtChunk();
    streamingMessageTime = null;
    streamingUserMessageTime = null;
    prompt.clear();
    lastPrompt = "";
    _currentSynthesisPrompt = "";
    await chatData.appendMessage(
      user: "Gemini",
      author: assistantAuthorLabel,
      message: message,
      time: commitTime,
      thoughtProcess: trimmedThought.isNotEmpty ? trimmedThought : null,
    );
    await log("mesh", "info", logNote);
    await chatData.saveChat(chatData.context, chatID: chatData.currentChat);
    _checkAndTriggerTitle();
    unawaited(_captureVisualMemoryIfNeeded());
    try {
      scrollChatlog(const Duration(milliseconds: 250));
    } catch (_) {}
  }

  static String _canonicalizeToolName(String rawName) {
    final norm = rawName.trim();
    switch (norm.toLowerCase()) {
      case 'about_paios':
      case 'paios_info':
      case 'get_paios_info':
        return 'query_aicore_documentation';
      default:
        return norm;
    }
  }

  Future<void> _handleSynthesisToolCall(
    Map<String, dynamic> nextToolMap,
    String effectivePrompt,
  ) async {
    final rawCall = M3xToolCall.fromJson(nextToolMap);
    final canonName = _canonicalizeToolName(rawCall.tool);
    final nextCall = canonName == rawCall.tool
        ? rawCall
        : M3xToolCall(
            id: rawCall.id,
            name: canonName,
            app: rawCall.app,
            arguments: rawCall.arguments,
          );
    final nextSig = "${nextCall.tool}:${jsonEncode(nextCall.arguments)}";

    if (!_forcedFinalSynthesis && _toolTurnCount < 6 && nextSig != _lastToolCallSignature) {
      _isSynthesizing = false;
      final normalizedMap = Map<String, dynamic>.from(nextToolMap);
      normalizedMap['tool'] = nextCall.tool;
      await _handleToolCall(
        normalizedMap,
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
    final int myGenId = _streamGenerationId;
    _toolTurnCount++;
    final rawCall = M3xToolCall.fromJson(toolMap);
    final canonName = _canonicalizeToolName(rawCall.tool);
    final call = canonName == rawCall.tool
        ? rawCall
        : M3xToolCall(
            id: rawCall.id,
            name: canonName,
            app: rawCall.app,
            arguments: rawCall.arguments,
          );
    _lastToolCall = call;
    final matchedTool = toolRegistry.get(call.tool);
    final effectiveApp = (call.app != null && call.app!.isNotEmpty)
        ? ((call.app!.contains('.') || matchedTool == null)
            ? call.app!
            : (matchedTool.packageName ?? call.app!))
        : (matchedTool?.packageName ?? matchedTool?.app ?? _selfPackageId);
    final canonEffectiveApp = canonicalExtensionId(effectiveApp);

    final effectiveOriginalPrompt = originalPrompt.isNotEmpty
        ? originalPrompt
        : (lastPrompt.isNotEmpty ? lastPrompt : prompt.text.trim());
    final internalMod = InternalToolsService.moduleForTool(call.tool);
    final Map<String, dynamic> effectiveArgs = internalMod != null
        ? InternalToolsService.normalizeToolArgs(
            call.tool,
            call.arguments,
            fallbackQuestion: effectiveOriginalPrompt,
          )
        : call.arguments;

    _lastToolCallSignature = "${call.tool}:${jsonEncode(effectiveArgs)}";

    await log("mesh", "info", "Detected tool call (#$_toolTurnCount): '${call.tool}' on app: '$effectiveApp' with arguments: ${jsonEncode(effectiveArgs)}");
    if (myGenId != _streamGenerationId || _disposed) return;

    status = "Executing ${call.tool}...";
    isLoading = true;
    isGenerating = true;
    _isSynthesizing = true;
    notifyListeners();

    final bool isPermitted = internalMod != null
        ? isExtensionEnabled(internalMod.id)
        : (canonEffectiveApp == _selfPackageId ||
            isExtensionEnabled(canonEffectiveApp));
    final toolResult = !isPermitted
        ? M3xToolResult.error(
            id: call.id,
            code: -32001,
            message:
                "Extension '${internalMod?.id ?? effectiveApp}' is disabled in PAIOS settings.",
          )
        : await meshClient.callTool(
            effectiveApp,
            call.tool,
            effectiveArgs,
            callId: call.id,
          );
    if (myGenId != _streamGenerationId || _disposed) return;

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
    if (myGenId != _streamGenerationId || _disposed) return;
    _lastToolResultPayload = resultPayload;

    if (!isFollowUpTurn) {
      await chatData.appendMessage(
        user: "User",
        message: effectiveOriginalPrompt,
        time: streamingUserMessageTime,
        imagePath: chatData.lastImagePath,
      );
      if (myGenId != _streamGenerationId || _disposed) return;
      streamingUserMessageTime = null;
      chatData.lastImagePath = null;
      lastPrompt = ""; // Clear lastPrompt / mark pending turn committed so it doesn't duplicate in the UI
    }

    final trimmedThought = _sanitizeThoughtChunk(currentThoughtChunk).trim();
    await chatData.appendMessage(
      user: "Gemini",
      author: assistantAuthorLabel,
      message: responseText,
      time: streamingMessageTime,
      thoughtProcess: trimmedThought.isNotEmpty ? trimmedThought : null,
    );
    if (myGenId != _streamGenerationId || _disposed) return;
    _clearThoughtChunk();
    streamingMessageTime = null;
    await chatData.appendMessage(user: "System", message: toolResultEntry);
    if (myGenId != _streamGenerationId || _disposed) return;

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
    _clearThoughtChunk();
    _lastFinishReason = "";
    _continuationCount = 0;
    _nullReasonContinuationCount = 0;
    _stopCutoffContinuationCount = 0;
    _combinedResponse = "";
    streamingMessageTime = DateTime.now();
    notifyListeners();

    final prevSub = _aiSubscription;
    _aiSubscription = null;
    await prevSub?.cancel();
    if (myGenId != _streamGenerationId || _disposed) return;

    // Re-initialize engine to ensure context includes the tool result (and strip tools if forcing final prose)
    await initEngine(includeTools: !forceFinalNoTools, hasAttachedImage: false);
    if (myGenId != _streamGenerationId || _disposed) return;

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

    bool isNotFoundResult = false;
    if (toolErrorMessage == null && resultPayload.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(resultPayload);
        if (decoded is Map && decoded['found'] == false) {
          isNotFoundResult = true;
        }
      } catch (_) {}
    }

    final String readableToolData = toolErrorMessage == null
        ? InternalToolsService.formatResultForSynthesis(call.tool, resultPayload)
        : resultPayload;

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
          "Tool output from ${call.tool}: $readableToolData\n\n"
          "$langInstruction"
          "${_buildRecoverableErrorHint(call.tool, toolErrorMessage)}";
    } else if (isNotFoundResult) {
      _currentSynthesisPrompt =
          "User question: \"$effectivePrompt\"\n\n"
          "Lookup note from ${call.tool}: $readableToolData\n\n"
          "$langInstruction"
          "The online lookup returned no direct result. Answer the user's question from your own knowledge if possible, or briefly say you couldn't find it."
          "${forceFinalNoTools ? ' Do not output JSON.' : ' Call a different enabled tool only if clearly needed; never repeat ${call.tool} with the same arguments.'}";
    } else if (forceFinalNoTools) {
      _currentSynthesisPrompt =
          "User question: \"$effectivePrompt\"\n\n"
          "Live data from ${call.tool}:\n"
          "$readableToolData\n\n"
          "$langInstruction"
          "Summarize clearly in natural, conversational Markdown (never repeat raw JSON field names like 'found', 'title', 'description', 'extract', or 'url'). Include source links nicely as Markdown links if helpful.";
    } else {
      _currentSynthesisPrompt =
          "User question: \"$effectivePrompt\"\n\n"
          "Live data from ${call.tool}:\n"
          "$readableToolData\n\n"
          "$langInstruction"
          "Summarize clearly in natural, conversational Markdown (never repeat raw JSON field names like 'found', 'title', 'description', 'extract', or 'url'). Include source links nicely as Markdown links if helpful. "
          "Call a different tool only if another lookup with different arguments is still needed; never repeat ${call.tool} with the same arguments.";
    }

    final double runTemperature = chatData.chats.containsKey(currentChat) && chatData.chats[currentChat].containsKey("chatTemperature")
        ? chatData.chats[currentChat]["chatTemperature"]
        : temperature;

    final stream = gemini.generateTextEvents(
      prompt: _currentSynthesisPrompt,
      config: GenerationConfig(
        temperature: runTemperature,
        enableThinking: effectiveEnableThinking,
      ),
      stream: true,
    );

    _aiSubscription = stream.listen(
      (AiEvent event) async {
        if (myGenId != _streamGenerationId || _disposed) return;
        switch (event.status) {
          case AiEventStatus.loading:
            isLoading = true;
            status = "Synthesizing response...";
            notifyListeners();
            break;

          case AiEventStatus.streaming:
            isLoading = true;
            streamingMessageTime = DateTime.now();
            status = "Streaming response...";
            _appendThoughtChunk(event.thought);
            final String? fr = event.response?.finishReason;
            if (fr != null && fr != "null" && fr.isNotEmpty) {
              _lastFinishReason = fr;
            }
            if (event.response != null) {
              response = event.response!;
              responseText = stripLeadingEllipsis(event.response!.text);
              _combinedResponse = responseText;
            }
            try {
              scrollChatlog(const Duration(milliseconds: 250));
            } catch (_) {}
            break;

          case AiEventStatus.done:
            receivedTerminalEvent = true;
            _appendThoughtChunk(event.thought);
            var nextToolMap =
                M3xToolCallParser.extract(responseText) ??
                    _extractCtrlToolCall(responseText);
            if (nextToolMap == null && responseText.trim().isEmpty) {
              final rawThought = _rawThoughtChunk.trim().isNotEmpty
                  ? _rawThoughtChunk
                  : currentThoughtChunk;
              if (rawThought.trim().isNotEmpty) {
                nextToolMap = _extractCtrlToolCall(rawThought) ??
                    M3xToolCallParser.extract(rawThought);
                if (nextToolMap != null) {
                  currentThoughtChunk = _sanitizeThoughtChunk(rawThought);
                  responseText = jsonEncode(nextToolMap);
                }
              }
            }
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
            await log(
              "model",
              "info",
              "Tool synthesis done. finishReason=$doneReason (nanoV4=$isNanoV4Active, chars=${responseText.length})",
              sendRemote: false,
            );
            if (myGenId != _streamGenerationId || _disposed) return;
            final bool shouldContinue = _shouldContinueOnDone(doneReason, responseText);

            if (shouldContinue) {
              cumulativeGenerationMs += response.generationTimeMs?.toInt() ?? 0;
              cumulativeTokenCount += response.tokenCount?.toInt() ?? 0;
              if (_isMissingFinishReason(doneReason) &&
                  !M3xToolCallParser.looksLikeIncompleteToolCall(responseText)) {
                _nullReasonContinuationCount++;
              } else if (_isStopFinishReason(doneReason)) {
                _stopCutoffContinuationCount++;
              }
              _continuationCount++;
              _combinedResponse = responseText;
              isContinuing = true;
              await log(
                "model",
                "info",
                "Tool synthesis interrupted (reason=$doneReason, nanoV4=$isNanoV4Active), triggering continuation #$_continuationCount",
                sendRemote: false,
              );
              if (myGenId != _streamGenerationId || _disposed) return;
              if (kDebugMode) print("[AUTO-CONTINUE #$_continuationCount] tool synthesis reason=$doneReason");
              await continueGenerating(isSynthesis: true);
            } else if (!forceFinalNoTools &&
                _looksLikeUnformattedToolEcho(responseText)) {
              await log(
                "mesh",
                "warning",
                "Synthesis returned empty or echoed tool wrapper; retrying with tool-free prose synthesis.",
              );
              if (myGenId != _streamGenerationId || _disposed) return;
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
              final finalMessage = badOutput
                  ? _buildIncompleteToolFallback()
                  : trimTrailingIncompleteSentence(responseText);
              _forcedFinalSynthesis = false;
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
            _resetTurnLifecycleFlags();
            isError = true;
            status = "Error";
            _clearThoughtChunk();
            streamingMessageTime = null;
            streamingUserMessageTime = null;
            responseText = event.error ?? "Error during tool synthesis";
            await log("mesh", "error", responseText);
            break;
        }
        genericRefresh();
      },
      onError: (e) async {
        if (myGenId != _streamGenerationId || _disposed) return;
        receivedTerminalEvent = true;
        _resetTurnLifecycleFlags();
        _clearThoughtChunk();
        streamingMessageTime = null;
        streamingUserMessageTime = null;
        await log("mesh", "error", "Synthesis error: $e");
        analyzeError("Synthesis", e);
        genericRefresh();
      },
      onDone: () => _handleUnexpectedStreamClose(myGenId, receivedTerminalEvent),
    );
  }

  void _clearTurnVisualMemory() {
    _turnImageBytesForMemory = null;
    _turnImagePathForMemory = null;
    _turnChatIdForMemory = null;
  }

  Future<void> _captureVisualMemoryIfNeeded() async {
    final Uint8List? bytes = _turnImageBytesForMemory;
    final String? imagePath = _turnImagePathForMemory;
    final String? chatId =
        (_turnChatIdForMemory != null &&
                _turnChatIdForMemory!.isNotEmpty &&
                _turnChatIdForMemory != "0")
            ? _turnChatIdForMemory
            : (chatData.currentChat.isNotEmpty && chatData.currentChat != "0"
                ? chatData.currentChat
                : null);
    _clearTurnVisualMemory();

    if (bytes == null ||
        bytes.isEmpty ||
        imagePath == null ||
        imagePath.isEmpty ||
        chatId == null ||
        chatId.isEmpty) {
      return;
    }
    if (isGenerating ||
        isLoading ||
        _isSynthesizing ||
        isContinuing ||
        _isCapturingVisualMemory) {
      return;
    }

    _isCapturingVisualMemory = true;
    try {
      await Future.delayed(const Duration(milliseconds: 50));
      if (isGenerating || isLoading || _isSynthesizing || isContinuing) {
        return;
      }

      final note = (await gemini.generateInternalInference(
        imageBytes: bytes,
        prompt: "Summarize this image for chat memory.",
        instructions:
            "Concisely describe the key subjects/scene and transcribe any important readable text verbatim in 2-4 sentences.",
        maxTokens: 160,
        temperature: 0.2,
      ))
          .trim();

      if (note.isEmpty || isGenerating || isLoading) {
        return;
      }

      final updated = await chatData.updateMessageImageDescription(
        chatId,
        note,
        imagePath: imagePath,
      );
      if (updated) {
        await log(
          "vision",
          "info",
          "Cached post-turn visual memory (${note.length} chars) for $imagePath",
          sendRemote: false,
        );
        notifyListeners();
      }
    } catch (e) {
      await log(
        "vision",
        "warning",
        "Post-turn visual memory skipped: $e",
        sendRemote: false,
      );
    } finally {
      _isCapturingVisualMemory = false;
    }
  }

  /// Clean up resources
  @override
  void dispose() {
    _disposed = true;
    prompt.dispose();
    instructions.dispose();
    _statusSubscription?.cancel();
    _aiSubscription?.cancel(); // Cancel stream
    unawaited(gemini.dispose()); // Tell native code to clean up
    super.dispose();
  }
}
