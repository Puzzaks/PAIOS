import 'dart:async';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class AnalyticsService {
  bool analyticsEnabled = true;
  bool analyticsDone = false;
  List<Map> logs = [];
  final VoidCallback notifyEngine;

  AnalyticsService({required this.notifyEngine});

  Future<void> startAnalytics() async {
    try {
      if (Hive.isBoxOpen('paios_storage')) {
        final box = Hive.box('paios_storage');
        await box.put("analytics", true);
      }
    } catch (_) {}
    analyticsEnabled = true;

    try {
      if (Firebase.apps.isNotEmpty) {
        FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterError;
        await Future.wait([
          FirebaseAnalytics.instance
              .setAnalyticsCollectionEnabled(true)
              .timeout(const Duration(seconds: 2)),
          FirebaseAnalytics.instance
              .setConsent()
              .timeout(const Duration(seconds: 2)),
          Firebase.app()
              .setAutomaticDataCollectionEnabled(true)
              .timeout(const Duration(seconds: 2)),
          Firebase.app()
              .setAutomaticResourceManagementEnabled(true)
              .timeout(const Duration(seconds: 2)),
        ]);
        analyticsDone = true;
      }
    } catch (e) {
      if (kDebugMode) {
        print("Analytics init failed or timed out: $e");
      }
    }

    unawaited(log("application", "info", "Enabling analytics"));
  }

  Future<void> stopAnalytics() async {
    try {
      if (Hive.isBoxOpen('paios_storage')) {
        final box = Hive.box('paios_storage');
        await box.put("analytics", false);
      }
    } catch (_) {}
    analyticsEnabled = false;

    try {
      if (Firebase.apps.isNotEmpty) {
        await Future.wait([
          FirebaseAnalytics.instance
              .setAnalyticsCollectionEnabled(false)
              .timeout(const Duration(seconds: 2)),
          Firebase.app()
              .setAutomaticDataCollectionEnabled(false)
              .timeout(const Duration(seconds: 2)),
          Firebase.app()
              .setAutomaticResourceManagementEnabled(false)
              .timeout(const Duration(seconds: 2)),
        ]);
      }
    } catch (_) {}

    unawaited(log("application", "info", "Disabling analytics"));
  }

  Future<void> log(String name, String type, String message, {bool sendRemote = true}) async {
    if (logs.isEmpty) {
      logs.add({
        "thread": name,
        "time": DateTime.now().millisecondsSinceEpoch,
        "type": type,
        "message": message,
      });
    } else {
      if (logs.last["thread"] == name &&
          logs.last["type"] == type &&
          logs.last["message"] == message) {
        logs.last["time"] = DateTime.now().millisecondsSinceEpoch;
        if (kDebugMode) {
          print("Still alive, did the last thing said above");
        }
      } else {
        logs.add({
          "thread": name,
          "time": DateTime.now().millisecondsSinceEpoch,
          "type": type,
          "message": message,
        });
        if (kDebugMode) {
          print("${type}_$name: $message");
        }
      }
    }

    // Bubble up to engine so UI can see the new logs
    notifyEngine();

    if (sendRemote &&
        analyticsEnabled &&
        analyticsDone &&
        Firebase.apps.isNotEmpty) {
      unawaited(
        FirebaseAnalytics.instance
            .logEvent(
              name: name,
              parameters: <String, Object>{'type': type, 'message': message},
            )
            .timeout(const Duration(seconds: 2))
            .catchError((e) {
          if (kDebugMode) {
            print("Analytics failed. Not waiting anymore. Error: $e");
          }
        }),
      );
    }
  }

  Future<void> logAiGeneration({
    required bool success,
    required int latencyMs,
    int tokensGenerated = 0,
    String errorType = 'none',
    int errorCode = 0,
    String finishReason = 'unknown',
    String modelVersion = 'unknown',
    String promptId = 'system_default',
    bool isMultimodal = false,
  }) async {
    final double tokensPerSec = latencyMs > 0 
        ? (tokensGenerated / (latencyMs / 1000.0)) 
        : 0.0;

    // 1. Maintain in-memory diagnostic log entry
    await log(
      "model",
      success ? "info" : "error",
      success
          ? "Generation completed: ${tokensGenerated}t in ${latencyMs}ms (${tokensPerSec.toStringAsFixed(1)} t/s)"
          : "Generation failed ($errorType, code $errorCode)",
      sendRemote: false,
    );

    // 2. Dispatch standardized atomic event to GA4
    if (analyticsEnabled && analyticsDone && Firebase.apps.isNotEmpty) {
      try {
        await FirebaseAnalytics.instance
            .logEvent(
              name: 'ai_generation_completed',
              parameters: <String, Object>{
                'status': success ? 'success' : 'error',
                'is_error': success ? 0 : 1, // Metric: Sum
                'is_success': success ? 1 : 0, // Metric: Sum
                'generation_count': 1, // Metric: Sum (The true denominator!)
                'error_type': errorType, // Dimension: "none", "timeout", "model_busy", "context_overflow", "npu_unavailable"
                'error_code': errorCode, // Metric: native code
                'finish_reason': finishReason, // Dimension: "stop", "max_tokens", "timeout", "error"
                'latency_ms': latencyMs, // Metric: Avg
                'tokens_generated': tokensGenerated, // Metric: Sum
                'tokens_per_sec': double.parse(tokensPerSec.toStringAsFixed(2)),
                'model_version': modelVersion, // Dimension: "nano-v3", "nano-v2"
                'prompt_id': promptId, // Dimension: active prompt id
                'is_multimodal': isMultimodal ? 1 : 0,
              },
            )
            .timeout(const Duration(seconds: 2));
      } catch (e) {
        if (kDebugMode) print("GA4 ai_generation_completed logging error: $e");
      }
    }
  }

  Future<void> initFromHive() async {
    if (!Hive.isBoxOpen('paios_storage')) return;
    final box = Hive.box('paios_storage');
    if (box.containsKey("analytics")) {
      analyticsEnabled = box.get("analytics", defaultValue: true);
      if (analyticsEnabled) {
        await startAnalytics();
      }
    } else {
      await startAnalytics();
    }
  }
}
