/// Response from AI generation
class AiResponse {
  final String text;
  final int? tokenCount;
  final String? chunk;
  final int? generationTimeMs;
  final String? finishReason;

  const AiResponse({
    required this.text,
    this.tokenCount,
    this.chunk,
    this.generationTimeMs,
    this.finishReason,
  });

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
