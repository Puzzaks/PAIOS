import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:hive_flutter/hive_flutter.dart';

class ResourceRepository {
  final VoidCallback notifyEngine;
  final Future<void> Function(String, String, String)? logEvent;
  static const Duration _httpTimeout = Duration(seconds: 5);

  List<Map<String, dynamic>> resources = [];

  ResourceRepository({required this.notifyEngine, this.logEvent});

  Future<void> initFromHive(String url) async {
    final box = Hive.box('paios_storage');

    // Step 1: Load Bundled fallback first, or Cached Hive override if available
    final String? cached = box.get("cached_resources_json");
    if (cached != null && cached.isNotEmpty) {
      try {
        resources = List<Map<String, dynamic>>.from(
          (jsonDecode(cached) as List).map((e) => Map<String, dynamic>.from(e)),
        );
      } catch (_) {}
    }

    if (resources.isEmpty) {
      try {
        final raw =
            await rootBundle.loadString('assets/additional_resources.json');
        resources = List<Map<String, dynamic>>.from(
          (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e)),
        );
      } catch (_) {}
    }

    // Step 2: Non-blocking background network refresh and cache update
    if (!kDebugMode && url.isNotEmpty) {
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
        final fetched = List<Map<String, dynamic>>.from(
          (jsonDecode(response.body) as List)
              .map((e) => Map<String, dynamic>.from(e)),
        );
        resources = fetched;
        await box.put("cached_resources_json", response.body);
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
