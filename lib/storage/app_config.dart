import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  final VoidCallback notifyEngine;
  
  int tokens = 256;
  double temperature = 0.7;
  bool addCurrentTimeToRequests = false;
  bool shareLocale = false;
  bool errorRetry = true;
  bool ignoreInstructions = false;
  bool downsampleImages = true;
  bool enableMesh = true;
  bool firstLaunch = true;
  String instructionsText = "";
  String repo = "Puzzaks/PAIOS";
  String defaultPromptId = "system_default";
  bool autoArchiveAssistantChats = true;
  String modelReleaseStage = "stable";
  String modelPreference = "full";
  bool enableThinking = false;
  
  // Future remote config overrides could go here
  int usualModelSize = 3854827928;

  AppConfig({required this.notifyEngine});

  static String normalizeReleaseStage(dynamic value) {
    return value?.toString().trim().toLowerCase() == "preview"
        ? "preview"
        : "stable";
  }

  static String normalizePreference(dynamic value) {
    return value?.toString().trim().toLowerCase() == "fast"
        ? "fast"
        : "full";
  }

  Future<void> endFirstLaunch() async {
    final box = Hive.box('paios_storage');
    await box.put("firstLaunch", false);
    firstLaunch = false;
    notifyEngine();
  }

  Future<void> saveSettings(
    String instructionsText, {
    String? promptContent,
    String? promptTitle,
  }) async {
    final box = Hive.box('paios_storage');
    await box.put("settings_user_updated", true); // Detach from upstream updates
    await box.put("temperature", temperature);
    await box.put("tokens", tokens);
    await box.put("instructions", instructionsText);
    await box.put("addCurrentTimeToRequests", addCurrentTimeToRequests);
    await box.put("shareLocale", shareLocale);
    await box.put("errorRetry", errorRetry);
    await box.put("ignoreInstructions", ignoreInstructions);
    await box.put("downsampleImages", downsampleImages);
    await box.put("enableMesh", enableMesh);
    await box.put("defaultPromptId", defaultPromptId);
    await box.put("autoArchiveAssistantChats", autoArchiveAssistantChats);
    await box.put("modelReleaseStage", modelReleaseStage);
    await box.put("modelPreference", modelPreference);
    await box.put("enableThinking", enableThinking);
    await syncToPrefs(
      promptContent: promptContent,
      promptTitle: promptTitle,
    );
  }

  /// Persists model channel, preference, and thinking mode flags to Hive
  /// and mirrors them into [SharedPreferences].
  Future<void> saveModelConfig() async {
    modelReleaseStage = normalizeReleaseStage(modelReleaseStage);
    modelPreference = normalizePreference(modelPreference);
    if (Hive.isBoxOpen('paios_storage')) {
      final box = Hive.box('paios_storage');
      await box.put("modelReleaseStage", modelReleaseStage);
      await box.put("modelPreference", modelPreference);
      await box.put("enableThinking", enableThinking);
    }
    await syncToPrefs();
  }

  /// Mirrors persisted configuration flags into [SharedPreferences] so
  /// native Android components (such as `MeshOverlayActivity`) stay in sync.
  Future<void> syncToPrefs({
    String? promptContent,
    String? promptTitle,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 2));
      await prefs.setString("defaultPromptId", defaultPromptId);
      await prefs.setBool("autoArchiveAssistantChats", autoArchiveAssistantChats);
      await prefs.setBool("downsampleImages", downsampleImages);
      await prefs.setBool("shareLocale", shareLocale);
      await prefs.setBool("enableMesh", enableMesh);
      await prefs.setString("modelReleaseStage", modelReleaseStage);
      await prefs.setString("modelPreference", modelPreference);
      await prefs.setBool("enableThinking", enableThinking);
      if (promptContent != null && promptContent.isNotEmpty) {
        await prefs.setString("defaultPromptContent", promptContent);
      }
      if (promptTitle != null && promptTitle.isNotEmpty) {
        await prefs.setString("defaultPromptTitle", promptTitle);
      }
    } catch (_) {}
  }

  void _applyRemoteConfigValues(
    FirebaseRemoteConfig remoteConfig, {
    required bool userUpdated,
  }) {
    final rcModelSize = remoteConfig.getInt("usualModelSize");
    if (rcModelSize > 0) {
      usualModelSize = rcModelSize;
    }
    final rcRepo = remoteConfig.getString("repo");
    if (rcRepo.isNotEmpty) {
      repo = rcRepo;
    }
    if (!userUpdated) {
      addCurrentTimeToRequests = remoteConfig.getBool("addCurrentTimeToRequests");
      shareLocale = remoteConfig.getBool("shareLocale");
      errorRetry = remoteConfig.getBool("errorRetry");
      ignoreInstructions = remoteConfig.getBool("ignoreInstructions");
      instructionsText = remoteConfig.getString("instructionsText");
      temperature = remoteConfig.getDouble("temperature");
      tokens = remoteConfig.getInt("tokens");
      final rcPromptId = remoteConfig.getString("defaultPromptId");
      if (rcPromptId.isNotEmpty) {
        defaultPromptId = rcPromptId;
      }
    }
  }

  Future<void> initFromHive() async {
    final Box<dynamic>? box =
        Hive.isBoxOpen('paios_storage') ? Hive.box('paios_storage') : null;
    firstLaunch = box?.get("firstLaunch", defaultValue: true) == true;

    downsampleImages = box?.get("downsampleImages", defaultValue: true) == true;
    enableMesh = box?.get("enableMesh", defaultValue: true) == true;
    autoArchiveAssistantChats =
        box?.get("autoArchiveAssistantChats", defaultValue: true) == true;
    modelReleaseStage = normalizeReleaseStage(
      box?.get("modelReleaseStage", defaultValue: "stable") ?? "stable",
    );
    modelPreference = normalizePreference(
      box?.get("modelPreference", defaultValue: "full") ?? "full",
    );
    enableThinking = box?.get("enableThinking", defaultValue: false) == true;

    final bool userUpdated =
        box?.get("settings_user_updated", defaultValue: false) == true;

    if (userUpdated && box != null) {
      if (kDebugMode) print("[REMOTE CONFIG] User settings detatched from upstream. Loading local Hive overrides.");
      addCurrentTimeToRequests = box.get("addCurrentTimeToRequests", defaultValue: false);
      shareLocale = box.get("shareLocale", defaultValue: false);
      errorRetry = box.get("errorRetry", defaultValue: true);
      ignoreInstructions = box.get("ignoreInstructions", defaultValue: false);
      instructionsText = box.get("instructions", defaultValue: "");
      temperature = box.get("temperature", defaultValue: 0.7);
      tokens = box.get("tokens", defaultValue: 512);
      defaultPromptId = box.get("defaultPromptId", defaultValue: "system_default");
    }

    FirebaseRemoteConfig? remoteConfig;
    try {
      if (Firebase.apps.isNotEmpty) {
        remoteConfig = FirebaseRemoteConfig.instance;
        await remoteConfig
            .setConfigSettings(RemoteConfigSettings(
              fetchTimeout: const Duration(seconds: 4),
              minimumFetchInterval: const Duration(hours: 1),
            ))
            .timeout(const Duration(seconds: 2));
        await remoteConfig
            .setDefaults(const {
              "temperature": 0.7,
              "tokens": 256,
              "usualModelSize": 3854827928,
              "addCurrentTimeToRequests": false,
              "shareLocale": false,
              "errorRetry": true,
              "ignoreInstructions": false,
              "instructionsText": "",
              "repo": "Puzzaks/PAIOS",
              "defaultPromptId": "system_default",
            })
            .timeout(const Duration(seconds: 2));
      }
    } catch (e) {
      remoteConfig = null;
      if (kDebugMode) print("[REMOTE CONFIG] Init failed. Using local/defaults. Error: $e");
    }

    if (remoteConfig != null) {
      try {
        _applyRemoteConfigValues(remoteConfig, userUpdated: userUpdated);
      } catch (_) {}

      final rc = remoteConfig;
      unawaited(
        rc
            .fetchAndActivate()
            .timeout(const Duration(seconds: 4))
            .then((updated) {
          if (kDebugMode) {
            print("[REMOTE CONFIG] Background fetch complete (updated=$updated).");
          }
          if (updated) {
            try {
              _applyRemoteConfigValues(rc, userUpdated: userUpdated);
              unawaited(syncToPrefs());
              notifyEngine();
            } catch (_) {}
          }
        }).catchError((e) {
          if (kDebugMode) {
            print("[REMOTE CONFIG] Failed to fetch in background. Using cached or defaults. Error: $e");
          }
        }),
      );
    }

    await syncToPrefs();
  }
}

