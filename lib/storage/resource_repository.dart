import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:hive_flutter/hive_flutter.dart';

class ResourceRepository {
  final VoidCallback notifyEngine;
  final Future<void> Function(String, String, String)? logEvent;

  List<Map<String, dynamic>> resources = [];

  static const Map<String, Map<String, String>> _localizedResourceNames = {
    "zh-Hans": {
      "Use AICore with root access": "Root 设备使用 AICore",
      "Gemini Nano Availability": "Gemini Nano 可用性说明",
      "Google ML Kit Guides": "Google ML Kit 指南",
      "Original app idea": "原始应用灵感",
      "Application's GitHub repository": "应用的 GitHub 仓库",
      "Application's Google Store page": "应用的 Google Play 页面",
      "Developer's Website": "开发者网站",
    },
    "zh": {
      "Use AICore with root access": "在 Root 裝置上使用 AICore",
      "Gemini Nano Availability": "Gemini Nano 可用性說明",
      "Google ML Kit Guides": "Google ML Kit 指南",
      "Original app idea": "原始應用程式靈感",
      "Application's GitHub repository": "應用程式的 GitHub 儲存庫",
      "Application's Google Store page": "應用程式的 Google Play 頁面",
      "Developer's Website": "開發者網站",
    },
    "uk": {
      "Use AICore with root access": "Використання AICore з root-доступом",
      "Gemini Nano Availability": "Доступність Gemini Nano",
      "Google ML Kit Guides": "Посібники Google ML Kit",
      "Original app idea": "Оригінальна ідея додатка",
      "Application's GitHub repository": "GitHub-репозиторій додатка",
      "Application's Google Store page": "Сторінка додатка в Google Play",
      "Developer's Website": "Сайт розробника",
    },
    "de": {
      "Use AICore with root access": "AICore mit Root-Zugriff verwenden",
      "Gemini Nano Availability": "Verfügbarkeit von Gemini Nano",
      "Google ML Kit Guides": "Google ML Kit-Anleitungen",
      "Original app idea": "Ursprüngliche App-Idee",
      "Application's GitHub repository": "GitHub-Repository der App",
      "Application's Google Store page": "Google Play-Seite der App",
      "Developer's Website": "Website des Entwicklers",
    },
    "tr": {
      "Use AICore with root access": "Root erişimiyle AICore kullan",
      "Gemini Nano Availability": "Gemini Nano kullanılabilirliği",
      "Google ML Kit Guides": "Google ML Kit kılavuzları",
      "Original app idea": "Özgün uygulama fikri",
      "Application's GitHub repository": "Uygulamanın GitHub deposu",
      "Application's Google Store page": "Uygulamanın Google Play sayfası",
      "Developer's Website": "Geliştiricinin web sitesi",
    },
  };

  static const Map<String, String> _resourceValueOverrides = {
    "Application's Google Store page": "https://play.google.com/store/apps/details?id=page.puzzak.paios",
  };

  ResourceRepository({required this.notifyEngine, this.logEvent});

  void _applyResourceOverrides() {
    for (final resource in resources) {
      final name = resource["name"]?.toString();
      final value = _resourceValueOverrides[name];
      if (value != null) {
        resource["value"] = value;
      }
    }
  }

  Future<void> initFromHive(String url) async {
    final box = Hive.box('paios_storage');

    // Step 1: Cache
    final String? cached = box.get("cached_resources_json");
    if (cached != null) {
      resources = List<Map<String, dynamic>>.from(
        (jsonDecode(cached) as List).map((e) => Map<String, dynamic>.from(e)),
      );
    } else {
      // Step 2: Bundle fallback
      try {
        final raw = await rootBundle.loadString('assets/additional_resources.json');
        resources = List<Map<String, dynamic>>.from(
          (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e)),
        );
      } catch (_) {}
    }
    _applyResourceOverrides();

    // Step 3: Network refresh and cache update
    if (!kDebugMode) {
      try {
        if (logEvent != null) await logEvent!("resource_repo", "info", "Fetching resources from $url/assets/additional_resources.json");
        final response = await http.get(Uri.parse("$url/assets/additional_resources.json"));
        if (response.statusCode == 200) {
          if (logEvent != null) await logEvent!("resource_repo", "info", "Resources fetched successfully");
          final fetched = List<Map<String, dynamic>>.from(
            (jsonDecode(response.body) as List).map((e) => Map<String, dynamic>.from(e)),
          );
          resources = fetched;
          _applyResourceOverrides();
          box.put("cached_resources_json", jsonEncode(resources));
          notifyEngine();
        } else {
          if (logEvent != null) await logEvent!("resource_repo", "error", "Failed to fetch resources: ${response.statusCode}");
        }
      } catch (e) {
        if (logEvent != null) await logEvent!("resource_repo", "error", "Network error while fetching resources: $e");
      }
    }
  }

  /// Returns resources grouped by collection, filtered by type == "link"
  Map<String, List<Map<String, dynamic>>> get grouped {
    final Map<String, List<Map<String, dynamic>>> out = {};
    for (final r in resources) {
      if (r["type"] == "link") {
        final collection = r["collection"] as String? ?? "Other";
        out.putIfAbsent(collection, () => []).add(r);
      }
    }
    return out;
  }

  String getResourceDisplayName(Map<String, dynamic> resource, String locale) {
    final name = resource["name"]?.toString() ?? "";
    return _localizedResourceNames[locale]?[name] ?? name;
  }
}
