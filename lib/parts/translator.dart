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

  @visibleForTesting
  http.Client? customHttpClient;

  @visibleForTesting
  bool allowRemoteInDebug = false;

  static final RegExp _cp1251MojibakeRegex = RegExp(
    r'вЂ|[\u0420\u0421][\u0402-\u0403\u0408-\u040F\u0452-\u0453\u0458-\u045F\u2018-\u203A\u2122\u00A4\u00A6\u00A7\u00A9\u00AB\u00AC\u00AE\u00B0\u00B1\u00B5-\u00B7\u00BB]',
  );
  static final RegExp _latin1MojibakeRegex = RegExp(
    r'â€|â„|Ã[\u0080-\u00BF]',
  );

  // CP1251 bytes 0x80..0xFF -> Unicode codepoint table (0x80..0xBF explicit, 0xC0..0xFF = U+0410..U+044F)
  static const List<int> _cp1251High0x80To0xBF = <int>[
    0x0402, 0x0403, 0x201A, 0x0453, 0x201E, 0x2026, 0x2020, 0x2021, // 80..87
    0x20AC, 0x2030, 0x0409, 0x2039, 0x040A, 0x040C, 0x040B, 0x040F, // 88..8F
    0x0452, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, // 90..97
    0x0098, 0x2122, 0x0459, 0x203A, 0x045A, 0x045C, 0x045B, 0x045F, // 98..9F
    0x00A0, 0x040E, 0x045E, 0x0408, 0x00A4, 0x0490, 0x00A6, 0x00A7, // A0..A7
    0x0401, 0x00A9, 0x0404, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x0407, // A8..AF
    0x00B0, 0x00B1, 0x0406, 0x0456, 0x0491, 0x00B5, 0x00B6, 0x00B7, // B0..B7
    0x0451, 0x2116, 0x0454, 0x00BB, 0x0458, 0x0405, 0x0455, 0x0457, // B8..BF
  ];

  // Windows-1252 bytes 0x80..0x9F -> Unicode codepoint table (0xA0..0xFF = direct U+00A0..U+00FF)
  static const List<int> _win12520x80To0x9F = <int>[
    0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, // 80..87
    0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F, // 88..8F
    0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, // 90..97
    0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178, // 98..9F
  ];

  static final Map<int, int> _cp1251Reverse = <int, int>{
    for (int i = 0; i < _cp1251High0x80To0xBF.length; i++)
      _cp1251High0x80To0xBF[i]: 0x80 + i,
    for (int i = 0; i < 64; i++) 0x0410 + i: 0xC0 + i,
  };

  static final Map<int, int> _win1252Reverse = <int, int>{
    for (int i = 0; i < _win12520x80To0x9F.length; i++)
      _win12520x80To0x9F[i]: 0x80 + i,
    for (int cp = 0xA0; cp <= 0xFF; cp++) cp: cp,
  };

  static const Map<String, String> _knownMojibakeReplacements = <String, String>{
    'вЂ¦': '…',
    'вЂў': '•',
    'вЂ”': '—',
    'вЂ“': '–',
    'вЂ™': '’',
    'вЂ˜': '‘',
    'вЂњ': '“',
    'вЂќ': '”',
    'вЂћ': '„',
    'в„ў': '™',
    'â€¦': '…',
    'â€¢': '•',
    'â€”': '—',
    'â€“': '–',
    'â€™': '’',
    'â€˜': '‘',
    'â€œ': '“',
    'â€\u009d': '”',
    'â€ž': '„',
    'â„¢': '™',
  };

  static String? _tryDecodeSingleByteRunAsUtf8(
    String input,
    Map<int, int> reverseTable,
  ) {
    final List<int> bytes = <int>[];
    bool hasHighBytes = false;
    for (final int cp in input.runes) {
      if (cp < 0x80) {
        bytes.add(cp);
      } else {
        final int? mapped = reverseTable[cp];
        if (mapped == null) return null;
        bytes.add(mapped);
        hasHighBytes = true;
      }
    }
    if (!hasHighBytes) return null;
    try {
      final decoded = utf8.decode(bytes, allowMalformed: false);
      if (decoded.runes.length < input.runes.length) {
        return decoded;
      }
    } catch (_) {}
    return null;
  }

  /// Returns true if [value] contains CP1251 or Latin-1/Windows-1252 UTF-8 mojibake.
  static bool hasMojibake(String value) {
    if (value.isEmpty) return false;
    if (_cp1251MojibakeRegex.hasMatch(value) ||
        _latin1MojibakeRegex.hasMatch(value)) {
      return true;
    }
    // Catch pure Cyrillic-pair CP1251 mojibake (e.g. "РџСЂРёРІС–С‚") via exact UTF-8 reversibility
    if (RegExp(r'(?:[РСТ][\u0400-\u045F\u2018-\u203A\u2122\u00A0-\u00BF]){2,}')
        .hasMatch(value)) {
      final decoded = _tryDecodeSingleByteRunAsUtf8(value, _cp1251Reverse);
      if (decoded != null && decoded != value) {
        return true;
      }
    }
    return false;
  }

  /// Repairs CP1251 / Windows-1252 UTF-8 mojibake back to clean UTF-8.
  static String repairMojibake(String value) {
    if (value.isEmpty) return value;
    final cpDecoded = _tryDecodeSingleByteRunAsUtf8(value, _cp1251Reverse);
    if (cpDecoded != null && !hasMojibake(cpDecoded)) {
      return cpDecoded;
    }
    final winDecoded = _tryDecodeSingleByteRunAsUtf8(value, _win1252Reverse);
    if (winDecoded != null && !hasMojibake(winDecoded)) {
      return winDecoded;
    }
    String fixed = value;
    _knownMojibakeReplacements.forEach((bad, good) {
      if (fixed.contains(bad)) {
        fixed = fixed.replaceAll(bad, good);
      }
    });
    return fixed;
  }

  /// Sanitizes a translation string, preferring [cleanFallback] if [value] is mojibaked.
  static String sanitizeTranslationValue(
    String value, {
    String? cleanFallback,
  }) {
    if (!hasMojibake(value)) return value;
    if (cleanFallback != null &&
        cleanFallback.isNotEmpty &&
        !hasMojibake(cleanFallback)) {
      return cleanFallback;
    }
    return repairMojibake(value);
  }

  Dictionary._internal(this.path, this.url);
  factory Dictionary({required String path, required String url}) {
    return Dictionary._internal(path, url);
  }

  Future<void> decideLanguage() async {
    if (!Hive.isBoxOpen('paios_storage')) {
      await setSystemLanguage();
      return;
    }
    final box = Hive.box('paios_storage');
    if (box.containsKey("language")) {
      locale = box.get("language", defaultValue: "en");
    } else {
      await setSystemLanguage();
    }
  }

  Future<void> setSystemLanguage() async {
    if (Hive.isBoxOpen('paios_storage')) {
      final box = Hive.box('paios_storage');
      // Remove the saved preference so decideLanguage() falls back to device locale on next boot
      await box.delete("language");
    }
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
    final Box<dynamic>? box =
        Hive.isBoxOpen('paios_storage') ? Hive.box('paios_storage') : null;

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

    final String? cachedLangList = box?.get("cached_languages_json");
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
      final Map<String, dynamic> assetDictMap = <String, dynamic>{};
      final Map<String, dynamic> mergedDict = <String, dynamic>{};

      try {
        final String assetDict =
            await rootBundle.loadString('$path/$langId.json');
        final dynamic decodedAsset = jsonDecode(assetDict);
        if (decodedAsset is Map) {
          decodedAsset.forEach((k, v) {
            final key = k.toString();
            final val = sanitizeTranslationValue(v.toString());
            assetDictMap[key] = val;
            mergedDict[key] = val;
          });
        }
      } catch (_) {
        // Fails silently if rootBundle doesn't have it (e.g. newly added remote lang)
      }

      final String? cachedDict = box?.get("cached_dict_$langId");
      if (cachedDict != null && cachedDict.isNotEmpty) {
        try {
          final dynamic decodedCache = jsonDecode(cachedDict);
          if (decodedCache is Map) {
            bool cacheHadMojibake = false;
            decodedCache.forEach((k, v) {
              final key = k.toString();
              final rawVal = v.toString();
              if (hasMojibake(rawVal)) {
                cacheHadMojibake = true;
              }
              final cleanFallback = assetDictMap[key]?.toString();
              mergedDict[key] = sanitizeTranslationValue(
                rawVal,
                cleanFallback: cleanFallback,
              );
            });
            if (cacheHadMojibake && box != null) {
              await box.put("cached_dict_$langId", jsonEncode(mergedDict));
            }
          }
        } catch (_) {}
      }

      dictionary[langId] = mergedDict;
    }

    // 3. Fire non-blocking background GitHub refresh so app startup never blocks on HTTP
    if ((!kDebugMode || allowRemoteInDebug) && url.isNotEmpty && box != null) {
      unawaited(
        _refreshFromRemoteInBackground(
          box: box,
          log: log,
          onUpdated: onUpdated,
        ),
      );
    }
  }

  @visibleForTesting
  Future<void> refreshFromRemoteForTest({
    required Box<dynamic> box,
    Future<void> Function(String, String, String)? log,
    VoidCallback? onUpdated,
  }) =>
      _refreshFromRemoteInBackground(box: box, log: log, onUpdated: onUpdated);

  Future<void> _refreshFromRemoteInBackground({
    required Box<dynamic> box,
    Future<void> Function(String, String, String)? log,
    VoidCallback? onUpdated,
  }) async {
    final client = customHttpClient;
    Future<http.Response> fetchUrl(Uri uri) => client != null
        ? client.get(uri).timeout(_httpTimeout)
        : http.get(uri).timeout(_httpTimeout);

    try {
      if (log != null) {
        await log("dict", "info",
            "Background-refreshing languages from $url/$path/languages.json");
      }
      final response = await fetchUrl(Uri.parse("$url/$path/languages.json"));
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
                final languageGet =
                    await fetchUrl(Uri.parse("$url/$path/$langId.json"));
                if (languageGet.statusCode == 200) {
                  final String dictBody = utf8.decode(languageGet.bodyBytes);
                  final dynamic decodedRemote = jsonDecode(dictBody);
                  if (decodedRemote is Map) {
                    final Map<String, dynamic> current =
                        dictionary[langId] is Map
                            ? Map<String, dynamic>.from(
                                dictionary[langId] as Map)
                            : <String, dynamic>{};
                    final Map<String, dynamic> sanitizedRemote =
                        <String, dynamic>{};
                    decodedRemote.forEach((k, v) {
                      final key = k.toString();
                      final rawVal = v.toString();
                      final existing = current[key]?.toString();
                      final cleanExisting =
                          (existing != null && !hasMojibake(existing))
                              ? existing
                              : null;
                      final safeVal = sanitizeTranslationValue(
                        rawVal,
                        cleanFallback: cleanExisting,
                      );
                      sanitizedRemote[key] = safeVal;
                      current[key] = safeVal;
                    });
                    dictionary[langId] = current;
                    await box.put(
                      "cached_dict_$langId",
                      jsonEncode(sanitizedRemote),
                    );
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
