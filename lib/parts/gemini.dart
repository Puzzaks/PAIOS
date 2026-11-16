import 'dart:async';
import 'package:flutter/services.dart';

class GenerationConfig {
  final int? maxTokens;
  final double? temperature;
  final int candidates;
  final bool enableThinking;
  const GenerationConfig({
    this.maxTokens,
    this.temperature,
    this.candidates = 1,
    this.enableThinking = false,
  });
  Map<String, dynamic> toMap() {
    return {
      if (maxTokens != null) 'maxTokens': maxTokens,
      'candidates': candidates,
      if (temperature != null) 'temperature': temperature,
      'enableThinking': enableThinking,
    };
  }
}

enum AiEventStatus {loading, streaming, done, error}

class AiEvent {
  final AiEventStatus status;
  final AiResponse? response;
  final String? error;
  final String? reason;
  final String? thought;

  AiEvent({
    required this.status,
    this.response,
    this.error,
    this.reason,
    this.thought,
  });

  factory AiEvent.fromMap(Map<dynamic, dynamic> map) {
    final statusString = map['status'] as String;
    final dynamic rawResponse = map['response'];
    final Map<String, dynamic>? responseMap = (rawResponse is Map)
        ? Map<String, dynamic>.from(rawResponse)
        : null;
    final errorString = map['error'] as String?;
    String? reasonString =
        (map['reason'] ?? responseMap?['reason'])?.toString();
    if (reasonString != null &&
        (reasonString.isEmpty ||
            reasonString == 'null' ||
            reasonString == 'UNKNOWN')) {
      reasonString = null;
    }
    String? thoughtString =
        (map['thought'] ?? responseMap?['thought'])?.toString();
    if (thoughtString != null &&
        (thoughtString.isEmpty || thoughtString == 'null')) {
      thoughtString = null;
    }
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
      reason: reasonString,
      thought: thoughtString,
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
      text: (map['text'] ?? '').toString(),
      chunk: map['chunk']?.toString(),
      tokenCount: (map['tokenCount'] as num?)?.toInt(),
      generationTimeMs: (map['generationTimeMs'] as num?)?.toInt(),
      finishReason: map['reason']?.toString(),
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

  Map<String, dynamic> _normalizeModelInfoMap(Map<dynamic, dynamic>? raw) {
    if (raw == null) {
      return {
        'status': 'Error',
        'available': false,
        'version': 'Null response from platform',
      };
    }
    final map = <String, dynamic>{};
    raw.forEach((key, value) {
      if (key != null && value != null) {
        map[key.toString()] = value;
      }
    });
    if (map.containsKey('version') && map['version'] != null) {
      map['version'] = map['version'].toString();
    }
    return map;
  }

  Future<Map<String, dynamic>> getModelInfo({
    String releaseStage = 'stable',
    String preference = 'full',
  }) async {
    try {
      final Map<dynamic, dynamic>? info = await _methodChannel.invokeMethod(
        'getModelInfo',
        {
          'releaseStage': releaseStage,
          'preference': preference,
        },
      );
      return _normalizeModelInfoMap(info);
    } catch (e) {
      return {'status': 'Error', 'available': false, 'version': e.toString()};
    }
  }

  Future<Map<String, dynamic>> initAiCore({
    String? instructions,
    String releaseStage = 'stable',
    String preference = 'full',
  }) async {
    try {
      final dynamic res = await _methodChannel.invokeMethod(
        'initAiCore',
        {
          if (instructions != null) 'instructions': instructions,
          'releaseStage': releaseStage,
          'preference': preference,
        },
      );
      if (res is Map) {
        return _normalizeModelInfoMap(res);
      }
      return await getModelInfo(
        releaseStage: releaseStage,
        preference: preference,
      );
    } on MissingPluginException {
      await init(
        instructions: instructions,
        releaseStage: releaseStage,
        preference: preference,
      );
      return await getModelInfo(
        releaseStage: releaseStage,
        preference: preference,
      );
    } catch (e) {
      return {'status': 'Error', 'available': false, 'version': e.toString()};
    }
  }

  Future<Map<String, dynamic>> switchModelConfig({
    required String releaseStage,
    required String preference,
  }) async {
    try {
      final dynamic res = await _methodChannel.invokeMethod(
        'switchModelConfig',
        {
          'releaseStage': releaseStage,
          'preference': preference,
        },
      );
      if (res is Map) {
        return _normalizeModelInfoMap(res);
      }
      return await getModelInfo(
        releaseStage: releaseStage,
        preference: preference,
      );
    } on MissingPluginException {
      return await getModelInfo(
        releaseStage: releaseStage,
        preference: preference,
      );
    } catch (e) {
      return {'status': 'Error', 'available': false, 'version': e.toString()};
    }
  }

  Future<Map<String, dynamic>> downloadModel({
    required String releaseStage,
    required String preference,
  }) async {
    try {
      final dynamic res = await _methodChannel.invokeMethod(
        'downloadModel',
        {
          'releaseStage': releaseStage,
          'preference': preference,
        },
      );
      if (res is Map) {
        return _normalizeModelInfoMap(res);
      }
      return await getModelInfo(
        releaseStage: releaseStage,
        preference: preference,
      );
    } catch (e) {
      return {'status': 'Error', 'available': false, 'version': e.toString()};
    }
  }

  Future<String?> init({
    String? instructions,
    String releaseStage = 'stable',
    String preference = 'full',
  }) async {
    final dynamic res = await _methodChannel.invokeMethod(
      'init',
      {
        'instructions': instructions,
        'releaseStage': releaseStage,
        'preference': preference,
      },
    );
    if (res is Map) {
      final map = _normalizeModelInfoMap(res);
      final status = map['status']?.toString() ?? '';
      if (map['available'] == true || status.toLowerCase() == 'available') {
        return 'Available=Available=0';
      }
      if (status.toLowerCase() == 'unavailable') {
        return 'Error=AICore=Unavailable';
      }
      return status.isNotEmpty ? status : 'Available=Available=0';
    }
    return res?.toString();
  }

  Future<Map<String, dynamic>?> pickImage() async {
    final Map<dynamic, dynamic>? res =
        await _methodChannel.invokeMethod('pickImage');
    if (res == null) return null;
    return res.map((key, value) => MapEntry(key.toString(), value));
  }

  Stream<AiEvent> _getAiEvents({
    required String prompt,
    GenerationConfig? config,
    required bool stream,
    Uint8List? imageBytes,
    String? imagePath,
    String? imageBase64,
    bool downsample = true,
  }) {
    final arguments = {
      'method': stream ? 'generateTextStream' : 'generateText',
      'payload': {
        'prompt': prompt,
        'config': config?.toMap(),
        if (imageBytes != null) 'imageBytes': imageBytes,
        if (imagePath != null) 'imagePath': imagePath,
        if (imageBase64 != null) 'imageBase64': imageBase64,
        'downsample': downsample,
      }
    };
    return _eventChannel.receiveBroadcastStream(arguments).map((event) {
      final Map<dynamic, dynamic> eventMap = Map<dynamic, dynamic>.from(event as Map);
      return AiEvent.fromMap(eventMap);
    });
  }

  Future<String> generateText({
    required String prompt,
    GenerationConfig? config,
    Uint8List? imageBytes,
    String? imagePath,
    String? imageBase64,
    bool downsample = true,
  }) async {
    final stream = _getAiEvents(
      prompt: prompt,
      config: config,
      stream: true,
      imageBytes: imageBytes,
      imagePath: imagePath,
      imageBase64: imageBase64,
      downsample: downsample,
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

  Stream<AiResponse> generateTextStream({
    required String prompt,
    GenerationConfig? config,
    Uint8List? imageBytes,
    String? imagePath,
    String? imageBase64,
    bool downsample = true,
  }) {
    return _getAiEvents(
      prompt: prompt,
      config: config,
      stream: true,
      imageBytes: imageBytes,
      imagePath: imagePath,
      imageBase64: imageBase64,
      downsample: downsample,
    ).where((event) => event.status == AiEventStatus.streaming).map((event) => event.response!);
  }

  Stream<AiEvent> generateTextEvents({
    required String prompt,
    GenerationConfig? config,
    bool stream = true,
    Uint8List? imageBytes,
    String? imagePath,
    String? imageBase64,
    bool downsample = true,
  }) {
    return _getAiEvents(
      prompt: prompt,
      config: config,
      stream: stream,
      imageBytes: imageBytes,
      imagePath: imagePath,
      imageBase64: imageBase64,
      downsample: downsample,
    );
  }

  /// Executes an isolated one-shot on-device inference without modifying active
  /// session instructions or cancelling any running chat stream.
  Future<String> generateInternalInference({
    required String prompt,
    String? instructions,
    Uint8List? imageBytes,
    int maxTokens = 192,
    double temperature = 0.2,
  }) async {
    final int clampedTokens = maxTokens.clamp(1, 256);
    final String? result = await _methodChannel.invokeMethod<String>(
      'generateInternalInference',
      {
        'prompt': prompt,
        if (instructions != null && instructions.isNotEmpty)
          'instructions': instructions,
        if (imageBytes != null && imageBytes.isNotEmpty)
          'imageBytes': imageBytes,
        'maxTokens': clampedTokens,
        'temperature': temperature,
      },
    );
    return result ?? '';
  }

  Future<void> openAICorePlayStore() async {
    await _methodChannel.invokeMethod('openAICorePlayStore');
  }

  Future<void> openAICoreBetaProgram() async {
    await _methodChannel.invokeMethod('openAICoreBetaProgram');
  }

  Future<void> openAICoreDevSettings() async {
    await _methodChannel.invokeMethod('openAICoreDevSettings');
  }

  Future<Map<String, dynamic>?> getInitialAssistantChat() async {
    try {
      final res = await _methodChannel.invokeMethod('getInitialAssistantChat');
      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
    } catch (_) {}
    return null;
  }

  void setAssistantChatHandler(void Function(Map<String, dynamic> payload) handler) {
    _methodChannel.setMethodCallHandler((call) async {
      if (call.method == 'onAssistantChatReceived' && call.arguments is Map) {
        handler(Map<String, dynamic>.from(call.arguments as Map));
      }
    });
  }

  Future<bool> isDefaultAssistant() async {
    try {
      final bool? isDefault = await _methodChannel.invokeMethod<bool>('isDefaultAssistant');
      return isDefault ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openAssistantSettings() async {
    try {
      await _methodChannel.invokeMethod('openAssistantSettings');
    } catch (_) {}
  }

  Future<void> dispose() async {
    try {
      await _methodChannel.invokeMethod('dispose');
    } catch (_) {}
  }
}
