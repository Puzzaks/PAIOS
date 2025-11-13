
import 'package:geminilocal/interface/flutter_local_ai.dart';


/// Defines the status of an AI event.
enum AiEventStatus {
  /// The request has been sent and is processing.
  loading,

  /// A new chunk of data has arrived (for streaming).
  streaming,

  /// The full response is complete (for both streaming and one-shot).
  done,

  /// An error occurred.
  error,
}

/// A wrapper class for all events coming from the native AI plugin.
class AiEvent {
  final AiEventStatus status;
  final AiResponse? response;
  final String? error;

  AiEvent({
    required this.status,
    this.response,
    this.error,
  });

  /// Factory to create an AiEvent from the raw map from Kotlin.
  factory AiEvent.fromMap(Map<dynamic, dynamic> map) {
    final statusString = map['status'] as String;

    // FIX: Safely cast the nested response map
    final dynamic rawResponse = map['response'];
    final Map<String, dynamic>? responseMap =
    (rawResponse is Map) ? Map<String, dynamic>.from(rawResponse) : null;

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
      response: responseMap != null ? AiResponse.fromMap(responseMap) : null,
      error: errorString,
    );
  }
}
class Gemini {

  late FlutterLocalAi gemini;
  int tokens = 200;
  double temperature = 0.7; // Controls randomness (0.0 = deterministic, 1.0 = very random)
  bool isLoading = false;
  bool isAvailable = false;
  bool isInitialized = false;
  bool isInitializing = false;

  Gemini._internal(this.gemini);
  factory Gemini({required FlutterLocalAi gemini}){
    return Gemini._internal(gemini);
  }
}