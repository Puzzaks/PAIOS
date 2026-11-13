import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:hive_flutter/hive_flutter.dart';

class IntroSlideRepository {
  final VoidCallback notifyEngine;
  final Future<void> Function(String, String, String)? logEvent;
  static const Duration _httpTimeout = Duration(seconds: 5);

  List<Map<String, dynamic>> slides = [];

  IntroSlideRepository({required this.notifyEngine, this.logEvent});

  Future<void> initFromHive(String url) async {
    final box = Hive.box('paios_storage');

    // Step 1: Load Cached Hive override if available
    final String? cached = box.get("cached_intro_slides_json");
    if (cached != null && cached.isNotEmpty) {
      try {
        final decoded = jsonDecode(cached);
        if (decoded is List) {
          slides = List<Map<String, dynamic>>.from(
            decoded.map((e) => Map<String, dynamic>.from(e as Map)),
          );
        }
      } catch (_) {}
    }

    // Fallback to bundled asset
    if (slides.isEmpty) {
      try {
        final raw = await rootBundle.loadString('assets/data/intro_slides.json');
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          slides = List<Map<String, dynamic>>.from(
            decoded.map((e) => Map<String, dynamic>.from(e as Map)),
          );
        }
      } catch (_) {}
    }

    // Step 2: Non-blocking background network refresh from GitHub SWR
    if (!kDebugMode && url.isNotEmpty) {
      unawaited(_refreshSlidesInBackground(url, box));
    }
  }

  Future<void> _refreshSlidesInBackground(String url, Box<dynamic> box) async {
    try {
      if (logEvent != null) {
        await logEvent!(
          "intro_slide_repo",
          "info",
          "Background-fetching configurable slides from $url/assets/data/intro_slides.json",
        );
      }
      final response = await http
          .get(Uri.parse("$url/assets/data/intro_slides.json"))
          .timeout(_httpTimeout);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is List) {
          slides = List<Map<String, dynamic>>.from(
            decoded.map((e) => Map<String, dynamic>.from(e as Map)),
          );
          await box.put("cached_intro_slides_json", response.body);
          notifyEngine();
        }
      }
    } catch (e) {
      if (logEvent != null) {
        await logEvent!(
          "intro_slide_repo",
          "info",
          "Offline or timeout during background slides refresh ($e)",
        );
      }
    }
  }

  /// Filters slides for active branch ('all', 'supported', or 'unsupported')
  List<Map<String, dynamic>> getSlidesForBranch(bool isSupported) {
    final targetBranch = isSupported ? 'supported' : 'unsupported';
    return slides.where((s) {
      final b = (s['branch'] as String? ?? 'all').toLowerCase();
      return b == 'all' || b == targetBranch;
    }).toList();
  }

  static IconData getIcon(String? name) {
    switch (name) {
      case 'forum_rounded':
      case 'forum':
        return Icons.forum_rounded;
      case 'volunteer_activism_rounded':
      case 'volunteer_activism':
        return Icons.volunteer_activism_rounded;
      case 'campaign_rounded':
      case 'campaign':
        return Icons.campaign_rounded;
      case 'hub_rounded':
      case 'hub':
        return Icons.hub_rounded;
      case 'star_rounded':
      case 'star':
        return Icons.star_rounded;
      case 'psychology_rounded':
      case 'psychology':
        return Icons.psychology_rounded;
      case 'assistant_rounded':
      case 'assistant':
        return Icons.assistant_rounded;
      case 'query_stats_rounded':
      case 'query_stats':
        return Icons.query_stats_rounded;
      case 'favorite_rounded':
      case 'favorite':
        return Icons.favorite_rounded;
      case 'help_outline_rounded':
      case 'help':
        return Icons.help_outline_rounded;
      default:
        return Icons.info_rounded;
    }
  }
}
