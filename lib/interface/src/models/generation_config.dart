/// Configuration for text generation
class GenerationConfig {
  /// Maximum number of tokens to generate
  final int maxTokens;

  /// Temperature for generation (0.0 to 1.0)
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
