import 'dart:async';
import 'package:flutter/services.dart';

class GenerationConfig {
  final int maxTokens;
  final double? temperature;
  final int candidates;
  const GenerationConfig({required this.maxTokens, this.temperature, this.candidates = 1});
  Map<String, dynamic> toMap() {
    return {
      'maxTokens': maxTokens,
      'candidates': 1,
      if (temperature != null) 'temperature': temperature,
    };
  }
}

enum AiEventStatus {loading, streaming, done, error}

class AiEvent {
  final AiEventStatus status;
  final AiResponse? response;
  final String? error;

  AiEvent({required this.status, this.response, this.error});

  factory AiEvent.fromMap(Map<dynamic, dynamic> map) {
    final statusString = map['status'] as String;
    final dynamic rawResponse = map['response'];
    final Map<String, dynamic>? responseMap = (rawResponse is Map)
        ? Map<String, dynamic>.from(rawResponse)
        : null;
    final errorString = map['error'] as String?;
    AiEventStatus status;
    switch (statusString) {
      case 'Loading':
        status = AiEventStatus.loading;
        break;
      case 'Streaming':
        status = AiEventStatus.streaming;
        break;
      case 'Done':
        status = AiEventStatus.done;
        break;
      case 'Error':
        status = AiEventStatus.error;
        break;
      default:
        throw Exception('Unknown AiEventStatus: $statusString');
    }

    return AiEvent(
      status: status,
      response: responseMap != null
          ? AiResponse.fromMap(responseMap)
          : null,
      error: errorString,
    );
  }
}

class AiResponse {
  final String text;
  final int? tokenCount;
  final String? chunk;
  final int? generationTimeMs;
  final String? finishReason;

  const AiResponse({required this.text, this.tokenCount, this.chunk, this.generationTimeMs, this.finishReason});

  factory AiResponse.fromMap(Map<String, dynamic> map) {
    return AiResponse(
      text: map['text'] as String,
      chunk: map['chunk'] as String?,
      tokenCount: map['tokenCount'] as int?,
      generationTimeMs: map['generationTimeMs'] as int?,
      finishReason: map['reason'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'text': text,
      if (tokenCount != null) 'tokenCount': tokenCount,
      if (generationTimeMs != null) 'generationTimeMs': generationTimeMs,
    };
  }
}


class GeminiNano {
  static const MethodChannel _methodChannel = MethodChannel('flutter_local_ai');      /// Send instructions for Kotlin part
  static const EventChannel _eventChannel = EventChannel('flutter_local_ai_events');  /// Receive updates
  EventChannel downloadChannel = EventChannel('download_channel');                    /// Status of model
  late Stream<String> statusStream;

  Future<Map<String, String>> getModelInfo() async {
    try {
      final Map<dynamic, dynamic>? info = await _methodChannel.invokeMethod('getModelInfo');
      if (info == null) {
        return {'status': 'Error', 'version': 'Null response from platform'};
      }
      return info.map((key, value) => MapEntry(key.toString(), value.toString()));
    } catch (e) {
      return {'status': 'Error', 'version': e.toString()};
    }
  }

  Future<String?> init({String? instructions}) async {
    final String? status = await _methodChannel.invokeMethod(
      'init',
      {'instructions': instructions},
    );
    return status;
  }

  Stream<AiEvent> _getAiEvents({required String prompt, GenerationConfig? config, required bool stream}){
    final arguments = {
      'method': stream ? 'generateTextStream' : 'generateText',
      'payload': {
        'prompt': prompt,
        'config': config?.toMap(),
      }
    };
    return _eventChannel.receiveBroadcastStream(arguments).map((event) {
      final Map<dynamic, dynamic> eventMap = Map<dynamic, dynamic>.from(event as Map);
      return AiEvent.fromMap(eventMap);
    });
  }

  Future<String> generateText({required String prompt, GenerationConfig? config}) async {
    final stream = _getAiEvents(
      prompt: prompt,
      config: config,
      stream: true,
    );
    bool isFinished = false;
    String response = "Loading...";
    stream.listen((AiEvent event) {
      if(event.status == AiEventStatus.streaming){
        response = event.response!.text;
      }
      if(event.status == AiEventStatus.done){
        isFinished = true;
      }
      if(event.status == AiEventStatus.error){
        response = "Error";
        isFinished = true;
      }
    });
    while(true){
      if(isFinished){
        return response;
      }else{
        await Future.delayed(Duration(milliseconds: 50));
      }
    }
  }

  Stream<AiResponse> generateTextStream({required String prompt, GenerationConfig? config}) {
    return _getAiEvents(
      prompt: prompt,
      config: config,
      stream: true,
    ).where((event) => event.status == AiEventStatus.streaming).map((event) => event.response!);
  }

  Stream<AiEvent> generateTextEvents({required String prompt, GenerationConfig? config, bool stream = true}) {
    return _getAiEvents(
      prompt: prompt,
      config: config,
      stream: stream,
    );
  }

  Future<void> openAICorePlayStore() async {
    await _methodChannel.invokeMethod('openAICorePlayStore');
  }

  Future<void> dispose() async {
    await _methodChannel.invokeMethod('dispose');
  }
}
