import 'dart:async';
import 'package:flutter/services.dart';
import '../../parts/gemini.dart';
import 'models/ai_response.dart';
import 'models/generation_config.dart';

/// Main class for interacting with local AI
class FlutterLocalAi {
  /// MethodChannel for one-shot commands (init, dispose).
  static const MethodChannel _methodChannel = MethodChannel('flutter_local_ai');

  /// EventChannel for ALL AI data requests (one-shot and streaming).
  static const EventChannel _eventChannel =
  EventChannel('flutter_local_ai_events'); // <-- Renamed!

  Future<Map<String, String>> getModelInfo() async {
    try {
      final Map<dynamic, dynamic>? info =
      await _methodChannel.invokeMethod('getModelInfo');
      if (info == null) {
        return {'status': 'Error', 'version': 'Null response from platform'};
      }
      // Convert from Map<dynamic, dynamic> to Map<String, String>
      return info.map((key, value) =>
          MapEntry(key.toString(), value.toString()));
    } catch (e) {
      return {'status': 'Error', 'version': e.toString()};
    }
  }
  /// Initializes the AI module.
  Future<String?> init({String? instructions}) async {
    final String? status = await _methodChannel.invokeMethod(
      'init',
      {'instructions': instructions},
    );
    return status;
  }

  /// The new, unified private function that gets the event stream.
  Stream<AiEvent> _getAiEvents({
    required String prompt,
    GenerationConfig? config,
    required bool stream,
  }) {
    // Arguments to tell Kotlin which method to run
    final arguments = {
      'method': stream ? 'generateTextStream' : 'generateText',
      'payload': {
        'prompt': prompt,
        'config': config?.toMap(),
      }
    };

    // Listen to the stream and map the raw map to our clean AiEvent object
    return _eventChannel
        .receiveBroadcastStream(arguments)
        .map((event) {
      // FIX: Don't use 'as'. Do a safe conversion.
      // This handles the Map<Object?, Object?> from the platform.
      final Map<dynamic, dynamic> eventMap = Map<dynamic, dynamic>.from(event as Map);
      return AiEvent.fromMap(eventMap);
    });
  }

  /// Generates a single text response (one-shot).
  ///
  /// This now uses the unified event stream under the hood, but
  /// returns a simple [Future] for convenience.
  Future<AiResponse> generateText({
    required String prompt,
    GenerationConfig? config,
  }) async {
    final stream = _getAiEvents(
      prompt: prompt,
      config: config,
      stream: false, // Tell Kotlin to run the one-shot method
    );

    // Wait for the first "Done" or "Error" event
    final event = await stream.firstWhere(
          (e) => e.status == AiEventStatus.done || e.status == AiEventStatus.error,
    );

    if (event.status == AiEventStatus.error) {
      throw Exception(event.error ?? 'Unknown AI Error');
    }

    return event.response!;
  }

  /// Generates a stream of text chunks.
  ///
  /// This also uses the unified event stream and filters for
  /// just the [AiEventStatus.streaming] events.
  Stream<AiResponse> generateTextStream({
    required String prompt,
    GenerationConfig? config,
  }) {
    return _getAiEvents(
      prompt: prompt,
      config: config,
      stream: true, // Tell Kotlin to run the streaming method
    )
        .where((event) => event.status == AiEventStatus.streaming) // Only care about streaming chunks
        .map((event) => event.response!); // Extract the response
  }

  /// Returns the raw [Stream<AiEvent>] for you to handle all
  /// statuses (Loading, Streaming, Done, Error) in your UI.
  /// This is great for showing loading spinners, etc.
  Stream<AiEvent> generateTextEvents({
    required String prompt,
    GenerationConfig? config,
    bool stream = true, // Default to streaming
  }) {
    return _getAiEvents(
      prompt: prompt,
      config: config,
      stream: stream,
    );
  }

  /// Opens the Google Play Store page for AICore.
  Future<void> openAICorePlayStore() async {
    await _methodChannel.invokeMethod('openAICorePlayStore');
  }

  /// Disposes of the AI model and resources.
  Future<void> dispose() async {
    await _methodChannel.invokeMethod('dispose');
  }
}
