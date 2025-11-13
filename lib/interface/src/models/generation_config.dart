/// Configuration for text generation
class GenerationConfig {
  /// Maximum number of tokens to generate
  final int maxTokens;

  /// Temperature for generation (0.0 to 1.0)
  final double? temperature;

  const GenerationConfig({this.maxTokens = 100, this.temperature});

  Map<String, dynamic> toMap() {
    return {
      'maxTokens': maxTokens,
      if (temperature != null) 'temperature': temperature,
    };
  }
}
