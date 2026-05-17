import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/services.dart';

class Dictionary {
  List languages = [];
  bool systemLanguage = false;
  Map dictionary = {};
  String locale = "en";
  String path = "";
  String url = "";

  Dictionary._internal(this.path, this.url);
  factory Dictionary({required String path, required String url}) {
    return Dictionary._internal(path, url);
  }

  bool _hasLanguage(String id) {
    return languages.any((language) => language is Map && language["id"] == id);
  }

  List _decodeLanguageList(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is List) return decoded;
    return [];
  }

  Map _decodeDictionary(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is Map) return decoded;
    return {};
  }

  void _mergeLanguages(List incoming) {
    final merged = <Map>[];

    void addOrReplace(dynamic language) {
      if (language is! Map || language["id"] == null) return;
      final id = language["id"].toString();
      final normalizedLanguage = Map.from(language);
      final existingIndex = merged.indexWhere((item) => item["id"] == id);
      if (existingIndex >= 0) {
        merged[existingIndex] = {
          ...merged[existingIndex],
          ...normalizedLanguage,
        };
      } else {
        merged.add(normalizedLanguage);
      }
    }

    for (final language in languages) {
      addOrReplace(language);
    }
    for (final language in incoming) {
      addOrReplace(language);
    }

    languages = merged;
  }

  String _resolveSystemLocale(String platformLocale) {
    final normalized = platformLocale.replaceAll("-", "_");
    final parts = normalized
        .split("_")
        .where((part) => part.trim().isNotEmpty)
        .toList();
    if (parts.isEmpty) return _hasLanguage("en") ? "en" : locale;

    final exactId = parts.join("-");
    if (_hasLanguage(exactId)) return exactId;

    final language = parts.first.toLowerCase();
    if (language == "zh") {
      final markers = parts.skip(1).map((part) => part.toLowerCase());
      final wantsTraditional = markers.any(
        (part) => part == "tw" || part == "hk" || part == "mo" || part == "hant",
      );

      if (wantsTraditional && _hasLanguage("zh")) return "zh";
      if (_hasLanguage("zh-Hans")) return "zh-Hans";
      if (_hasLanguage("zh")) return "zh";
    }

    if (_hasLanguage(language)) return language;
    return _hasLanguage("en") ? "en" : locale;
  }

  Future<void> _loadBundledAndCachedDictionaries(Box box) async {
    for (int i = 0; i < languages.length; i++) {
      final language = languages[i];
      if (language is! Map || language["id"] == null) continue;
      final langId = language["id"].toString();
      final mergedDict = {};

      try {
        final assetDict = await rootBundle.loadString('$path/$langId.json');
        mergedDict.addAll(_decodeDictionary(assetDict));
      } catch (e) {
        // Fails silently if rootBundle doesn't have it (e.g. newly added lang)
      }

      final cachedDict = box.get("cached_dict_$langId");
      if (cachedDict is String) {
        try {
          mergedDict.addAll(_decodeDictionary(cachedDict));
        } catch (e) {
          if (kDebugMode) print("Failed to parse cached dictionary for $langId: $e");
        }
      }

      if (mergedDict.isNotEmpty) {
        dictionary[langId] = mergedDict;
      }
    }
  }

  decideLanguage() async {
    final box = Hive.box('paios_storage');
    if (box.containsKey("language")) {
      final savedLocale = box.get("language", defaultValue: "en").toString();
      if (_hasLanguage(savedLocale)) {
        locale = savedLocale;
      } else {
        await setSystemLanguage();
      }
    } else {
      await setSystemLanguage();
    }
  }

  setSystemLanguage() async {
    final box = Hive.box('paios_storage');
    // Remove the saved preference so decideLanguage() falls back to device locale on next boot
    await box.delete("language");
    systemLanguage = true;
    locale = _resolveSystemLocale(Platform.localeName);
  }

  saveLanguage(String variant) async {
    final box = Hive.box('paios_storage');
    for (int a = 0; a < languages.length; a++) {
      if (languages[a]["id"] == variant) {
        locale = variant;
        systemLanguage = false;
        box.put("language", variant);
      }
    }
  }

  setup({Future<void> Function(String, String, String)? log}) async {
    final box = Hive.box('paios_storage');

    // Load bundled languages first so new built-in languages are never hidden by stale cache.
    String assetLangList = await rootBundle.loadString('$path/languages.json');
    languages = _decodeLanguageList(assetLangList);

    String? cachedLangList = box.get("cached_languages_json");
    if (cachedLangList != null) {
      try {
        _mergeLanguages(_decodeLanguageList(cachedLangList));
      } catch (e) {
        if (kDebugMode) print("Failed to parse cached languages: $e");
      }
    }

    await decideLanguage();
    await _loadBundledAndCachedDictionaries(box);

    if (!kDebugMode) {
      try {
        if (log != null) await log("dict", "info", "Fetching languages from $url/$path/languages.json");
        final response = await http.get(Uri.parse("$url/$path/languages.json"));
        if (response.statusCode == 200) {
          if (log != null) await log("dict", "info", "Language list fetched successfully");
          _mergeLanguages(_decodeLanguageList(response.body));
          box.put("cached_languages_json", response.body); // Update persistent cache
          // Only re-decide language if the user has no saved preference.
          // If they saved one, keep it - never let the network refresh override it.
          if (!box.containsKey("language")) await decideLanguage();
          await _loadBundledAndCachedDictionaries(box);

          for (int i = 0; i < languages.length; i++) {
            final language = languages[i];
            if (language is! Map || language["id"] == null) continue;
            String langId = language["id"].toString();
            final languageGet = await http.get(Uri.parse("$url/$path/$langId.json"));
            if (languageGet.statusCode == 200) {
              if (log != null) await log("dict", "info", "Downloaded dictionary for $langId");
              final mergedDict = {};
              if (dictionary[langId] is Map) {
                mergedDict.addAll(dictionary[langId]);
              }
              mergedDict.addAll(_decodeDictionary(languageGet.body));
              dictionary[langId] = mergedDict;
              box.put("cached_dict_$langId", languageGet.body); // Update persistent cache
            } else {
              if (log != null) await log("dict", "warning", "Failed to download dictionary for $langId: ${languageGet.statusCode}");
            }
          }
        } else {
          if (log != null) await log("dict", "error", "Failed to fetch language list: ${response.statusCode}");
        }
      } catch (e) {
        if (kDebugMode) print("Falling back to strictly offline Languages! Error: $e");
        if (log != null) await log("dict", "error", "Network error during dictionary setup: $e");
      }
    }
  }

  String value(String entry) {
    if (!dictionary.containsKey(locale)) {
      return "Loading...";
    }
    if (!dictionary[locale].containsKey(entry)) {
      if (!dictionary["en"].containsKey(entry)) {
        if (kDebugMode) {
          return "!!! $entry";
        } else {
          return entry;
        }
      }
      if (kDebugMode) {
        return "!${dictionary["en"][entry].toString()}!";
      } else {
        return dictionary["en"][entry].toString();
      }
    }
    return dictionary[locale][entry].toString();
  }
}
