import 'dart:async';
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
  static const Duration _httpTimeout = Duration(seconds: 5);

  Dictionary._internal(this.path, this.url);
  factory Dictionary({required String path, required String url}) {
    return Dictionary._internal(path, url);
  }

  Future<void> decideLanguage() async {
    final box = Hive.box('paios_storage');
    if (box.containsKey("language")) {
      locale = box.get("language", defaultValue: "en");
    } else {
      await setSystemLanguage();
    }
  }

  Future<void> setSystemLanguage() async {
    final box = Hive.box('paios_storage');
    // Remove the saved preference so decideLanguage() falls back to device locale on next boot
    await box.delete("language");
    String deviceLocale = "en";
    try {
      deviceLocale = Platform.localeName.split("_")[0];
    } catch (_) {}
    bool found = false;
    for (int a = 0; a < languages.length; a++) {
      if (languages[a]["id"] == deviceLocale) {
        locale = deviceLocale;
        found = true;
        break;
      }
    }
    if (!found) {
      locale = "en";
    }
  }

  saveLanguage(String variant) async {
    final box = Hive.box('paios_storage');
    for (int a = 0; a < languages.length; a++) {
      if (languages[a]["id"] == variant) {
        locale = variant;
        box.put("language", variant);
      }
    }
  }

  /// Stale-While-Revalidate (SWR) dictionary setup:
  /// 1. Immediately loads bundled assets as baseline and overlays any cached
  ///    Hive translations on top so startup never waits on network I/O and works
  ///    offline with cached strings.
  /// 2. Silently upgrades translations from GitHub in the background and invokes
  ///    [onUpdated] once downloaded.
  Future<void> setup({
    Future<void> Function(String, String, String)? log,
    VoidCallback? onUpdated,
  }) async {
    final box = Hive.box('paios_storage');

    // 1. Load bundled languages list first, then merge any additional cached languages
    final List<dynamic> mergedLanguages = <dynamic>[];
    final Set<String> seenLangIds = <String>{};
    try {
      final String assetLangList =
          await rootBundle.loadString('$path/languages.json');
      final dynamic decoded = jsonDecode(assetLangList);
      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map && item["id"] != null) {
            seenLangIds.add(item["id"].toString());
          }
          mergedLanguages.add(item);
        }
      }
    } catch (_) {}

    final String? cachedLangList = box.get("cached_languages_json");
    if (cachedLangList != null && cachedLangList.isNotEmpty) {
      try {
        final dynamic decoded = jsonDecode(cachedLangList);
        if (decoded is List) {
          if (mergedLanguages.isEmpty) {
            mergedLanguages.addAll(decoded);
          } else {
            for (final item in decoded) {
              if (item is Map && item["id"] != null) {
                final String id = item["id"].toString();
                if (!seenLangIds.contains(id)) {
                  seenLangIds.add(id);
                  mergedLanguages.add(item);
                }
              }
            }
          }
        }
      } catch (_) {}
    }

    if (mergedLanguages.isNotEmpty) {
      languages = mergedLanguages;
    }

    await decideLanguage();

    // 2. For each language, load bundled asset baseline + overlay cached Hive strings
    for (int i = 0; i < languages.length; i++) {
      final String langId = languages[i]["id"].toString();
      final Map<String, dynamic> mergedDict = <String, dynamic>{};

      try {
        final String assetDict =
            await rootBundle.loadString('$path/$langId.json');
        final dynamic decodedAsset = jsonDecode(assetDict);
        if (decodedAsset is Map) {
          mergedDict.addAll(Map<String, dynamic>.from(decodedAsset));
        }
      } catch (_) {
        // Fails silently if rootBundle doesn't have it (e.g. newly added remote lang)
      }

      final String? cachedDict = box.get("cached_dict_$langId");
      if (cachedDict != null && cachedDict.isNotEmpty) {
        try {
          final dynamic decodedCache = jsonDecode(cachedDict);
          if (decodedCache is Map) {
            mergedDict.addAll(Map<String, dynamic>.from(decodedCache));
          }
        } catch (_) {}
      }

      dictionary[langId] = mergedDict;
    }

    // 3. Fire non-blocking background GitHub refresh so app startup never blocks on HTTP
    if (!kDebugMode && url.isNotEmpty) {
      unawaited(
        _refreshFromRemoteInBackground(
          box: box,
          log: log,
          onUpdated: onUpdated,
        ),
      );
    }
  }

  Future<void> _refreshFromRemoteInBackground({
    required Box<dynamic> box,
    Future<void> Function(String, String, String)? log,
    VoidCallback? onUpdated,
  }) async {
    try {
      if (log != null) {
        await log("dict", "info",
            "Background-refreshing languages from $url/$path/languages.json");
      }
      final response = await http
          .get(Uri.parse("$url/$path/languages.json"))
          .timeout(_httpTimeout);
      if (response.statusCode == 200) {
        final String langBody = utf8.decode(response.bodyBytes);
        final dynamic decodedLangs = jsonDecode(langBody);
        if (decodedLangs is List) {
          languages = decodedLangs;
          await box.put("cached_languages_json", langBody);
          if (!box.containsKey("language")) {
            await decideLanguage();
          }

          bool anyUpdated = false;
          final List<Future<void>> tasks = <Future<void>>[];
          for (int i = 0; i < languages.length; i++) {
            final String langId = languages[i]["id"].toString();
            tasks.add(() async {
              try {
                final languageGet = await http
                    .get(Uri.parse("$url/$path/$langId.json"))
                    .timeout(_httpTimeout);
                if (languageGet.statusCode == 200) {
                  final String dictBody = utf8.decode(languageGet.bodyBytes);
                  final dynamic decodedRemote = jsonDecode(dictBody);
                  if (decodedRemote is Map) {
                    final Map<String, dynamic> current =
                        dictionary[langId] is Map
                            ? Map<String, dynamic>.from(
                                dictionary[langId] as Map)
                            : <String, dynamic>{};
                    current.addAll(Map<String, dynamic>.from(decodedRemote));
                    dictionary[langId] = current;
                    await box.put("cached_dict_$langId", dictBody);
                    anyUpdated = true;
                  }
                }
              } catch (_) {
                // Keep bundled + Hive cached dictionary for this language on timeout/offline
              }
            }());
          }
          await Future.wait(tasks);
          if (anyUpdated) {
            if (log != null) {
              await log("dict", "info",
                  "Background dictionary upgrade complete (${languages.length} locales)");
            }
            onUpdated?.call();
          }
        }
      }
    } catch (e) {
      if (log != null) {
        await log("dict", "info",
            "Offline or timeout during background dictionary check; using cached/bundled strings ($e)");
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
