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
  
  // Future remote config overrides could go here
  int usualModelSize = 3854827928;

  AppConfig({required this.notifyEngine});

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
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("defaultPromptId", defaultPromptId);
      await prefs.setBool("autoArchiveAssistantChats", autoArchiveAssistantChats);
      await prefs.setBool("downsampleImages", downsampleImages);
      await prefs.setBool("shareLocale", shareLocale);
      if (promptContent != null && promptContent.isNotEmpty) {
        await prefs.setString("defaultPromptContent", promptContent);
      }
      if (promptTitle != null && promptTitle.isNotEmpty) {
        await prefs.setString("defaultPromptTitle", promptTitle);
      }
    } catch (_) {}
  }

  Future<void> initFromHive() async {
    final box = Hive.box('paios_storage');
    firstLaunch = box.get("firstLaunch", defaultValue: true);
    
    final remoteConfig = FirebaseRemoteConfig.instance;
    await remoteConfig.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: const Duration(seconds: 10),
      minimumFetchInterval: const Duration(hours: 1),
    ));
    await remoteConfig.setDefaults(const {
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
    });
    
    try {
      await remoteConfig.fetchAndActivate();
      if (kDebugMode) print("[REMOTE CONFIG] Successfully fetched latest configs from cloud.");
    } catch (e) {
      if (kDebugMode) print("[REMOTE CONFIG] Failed to fetch. Using cached or defaults. Error: $e");
    }

    usualModelSize = remoteConfig.getInt("usualModelSize");
    repo = remoteConfig.getString("repo");
    
    downsampleImages = box.get("downsampleImages", defaultValue: true);
    enableMesh = box.get("enableMesh", defaultValue: true);
    autoArchiveAssistantChats = box.get("autoArchiveAssistantChats", defaultValue: true);

    bool userUpdated = box.get("settings_user_updated", defaultValue: false);
    
    if (userUpdated) {
      if (kDebugMode) print("[REMOTE CONFIG] User settings detatched from upstream. Loading local Hive overrides.");
      addCurrentTimeToRequests = box.get("addCurrentTimeToRequests", defaultValue: false);
      shareLocale = box.get("shareLocale", defaultValue: false);
      errorRetry = box.get("errorRetry", defaultValue: true);
      ignoreInstructions = box.get("ignoreInstructions", defaultValue: false);
      instructionsText = box.get("instructions", defaultValue: "");
      temperature = box.get("temperature", defaultValue: 0.7);
      tokens = box.get("tokens", defaultValue: 512);
      defaultPromptId = box.get("defaultPromptId", defaultValue: "system_default");
    } else {
      if (kDebugMode) print("[REMOTE CONFIG] Using optimal upstream parameters.");
      addCurrentTimeToRequests = remoteConfig.getBool("addCurrentTimeToRequests");
      shareLocale = remoteConfig.getBool("shareLocale");
      errorRetry = remoteConfig.getBool("errorRetry");
      ignoreInstructions = remoteConfig.getBool("ignoreInstructions");
      instructionsText = remoteConfig.getString("instructionsText");
      temperature = remoteConfig.getDouble("temperature");
      tokens = remoteConfig.getInt("tokens");
      defaultPromptId = remoteConfig.getString("defaultPromptId");
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!prefs.containsKey("downsampleImages")) {
        await prefs.setBool("downsampleImages", downsampleImages);
      }
      await prefs.setString("defaultPromptId", defaultPromptId);
      await prefs.setBool("autoArchiveAssistantChats", autoArchiveAssistantChats);
    } catch (_) {}
  }
}

