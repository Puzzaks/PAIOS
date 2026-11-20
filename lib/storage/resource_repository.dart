import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:hive_flutter/hive_flutter.dart';
import '../parts/translator.dart';

class ResourceRepository {
  final VoidCallback notifyEngine;
  final Future<void> Function(String, String, String)? logEvent;
  static const Duration _httpTimeout = Duration(seconds: 5);

  List<Map<String, dynamic>> resources = [];

  ResourceRepository({required this.notifyEngine, this.logEvent});

  static ({List<Map<String, dynamic>> items, bool sanitized}) _sanitizeResources(
    List<dynamic> rawList,
  ) {
    bool sanitized = false;
    final items = List<Map<String, dynamic>>.from(
      rawList.map((e) {
        final map = Map<String, dynamic>.from(e as Map);
        for (final k in const ['value', 'url']) {
          final v = map[k];
          if (v is String && v.contains('id=page.puzzak.geminilocal')) {
            map[k] = v.replaceAll(
              'id=page.puzzak.geminilocal',
              'id=page.puzzak.paios',
            );
            sanitized = true;
          }
        }
        return map;
      }),
    );
    return (items: items, sanitized: sanitized);
  }

  Future<void> initFromHive(String url) async {
    final Box<dynamic>? box =
        Hive.isBoxOpen('paios_storage') ? Hive.box('paios_storage') : null;

    // Step 1: Load Bundled fallback first, or Cached Hive override if available
    final String? cached = box?.get("cached_resources_json");
    if (cached != null && cached.isNotEmpty) {
      try {
        final decoded = jsonDecode(cached) as List;
        final result = _sanitizeResources(decoded);
        resources = result.items;
        if (result.sanitized && box != null) {
          await box.put("cached_resources_json", jsonEncode(resources));
        }
      } catch (_) {}
    }

    if (resources.isEmpty) {
      try {
        final raw =
            await rootBundle.loadString('assets/additional_resources.json');
        final decoded = jsonDecode(raw) as List;
        resources = _sanitizeResources(decoded).items;
      } catch (_) {}
    }

    // Step 2: Non-blocking background network refresh and cache update
    if (!kDebugMode && url.isNotEmpty && box != null) {
      unawaited(_refreshResourcesInBackground(url, box));
    }
  }

  Future<void> _refreshResourcesInBackground(
    String url,
    Box<dynamic> box,
  ) async {
    try {
      if (logEvent != null) {
        await logEvent!(
          "resource_repo",
          "info",
          "Background-fetching resources from $url/assets/additional_resources.json",
        );
      }
      final response = await http
          .get(Uri.parse("$url/assets/additional_resources.json"))
          .timeout(_httpTimeout);
      if (response.statusCode == 200) {
        final String body = utf8.decode(response.bodyBytes);
        final decoded = jsonDecode(body) as List;
        final sanitized = _sanitizeResources(decoded);
        resources = sanitized.items;
        await box.put(
          "cached_resources_json",
          sanitized.sanitized ? jsonEncode(resources) : body,
        );
        notifyEngine();
      }
    } catch (e) {
      if (logEvent != null) {
        await logEvent!(
          "resource_repo",
          "info",
          "Offline or timeout during background resource refresh; using cached/bundled resources ($e)",
        );
      }
    }
  }

  static const Map<String, List<String>> _resourceNameKeyMap = {
    "Use AICore with root access": ["resource_aicore_root"],
    "Gemini Nano Availability": ["resource_nano_availability"],
    "Google ML Kit Guides": ["resource_mlkit_guides"],
    "Original app idea": ["resource_original_idea"],
    "Application's GitHub repository": ["resource_github_repo", "gh_repo"],
    "Application's Google Store page": ["resource_play_store", "in_play_store"],
    "Developer's Website": ["resource_dev_website"],
  };

  /// Returns a localized display name for [resource] when [dict] contains a
  /// matching translation key, falling back safely to `resource["name"]`.
  String getResourceDisplayName(
    Map<String, dynamic> resource, [
    Dictionary? dict,
  ]) {
    final rawName = resource['name']?.toString() ?? '';
    if (dict != null) {
      final explicitKey =
          (resource['i18nKey'] ?? resource['translationKey'])?.toString().trim();
      if (explicitKey != null && explicitKey.isNotEmpty) {
        final localized = dict.tryValue(explicitKey);
        if (localized != null) return localized;
      }
      final candidateKeys = _resourceNameKeyMap[rawName];
      if (candidateKeys != null) {
        for (final key in candidateKeys) {
          final localized = dict.tryValue(key);
          if (localized != null) return localized;
        }
      }
    }
    return rawName;
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
}
