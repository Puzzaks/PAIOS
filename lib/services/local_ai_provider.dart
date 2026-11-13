import 'dart:async';
import 'dart:convert';
import 'package:m3x_mesh/m3x_mesh.dart';
import '../parts/gemini.dart';

/// Gemini Nano Local AI Provider implementation for M3x Mesh.
///
/// Connects on-device Gemini Nano inference (via Google AICore or MLC LLM)
/// to the M3x agentic tool mesh.
class GeminiLocalAiProvider implements M3xAiProvider {
  /// The underlying Gemini Nano instance.
  final GeminiNano nano;

  GeminiLocalAiProvider({GeminiNano? nano}) : nano = nano ?? GeminiNano();

  @override
  String get name => 'gemini_local';

  @override
  bool get supportsLocalAi => true;

  @override
  Future<String> executePrompt(
    String prompt, {
    List<M3xTool>? tools,
    Map<String, dynamic>? context,
  }) async {
    final effectivePrompt = _buildPrompt(prompt, tools: tools);
    try {
      return await nano.generateText(prompt: effectivePrompt);
    } catch (e) {
      return 'Gemini Nano local execution error: $e';
    }
  }

  @override
  Stream<String> streamPrompt(
    String prompt, {
    List<M3xTool>? tools,
    Map<String, dynamic>? context,
  }) async* {
    final effectivePrompt = _buildPrompt(prompt, tools: tools);
    try {
      final stream = nano.generateTextEvents(prompt: effectivePrompt, stream: true);
      String previousText = '';
      await for (final event in stream) {
        if (event.status == AiEventStatus.streaming && event.response != null) {
          final chunk = event.response!.chunk;
          if (chunk != null && chunk.isNotEmpty) {
            yield chunk;
          } else {
            final currentText = event.response!.text;
            if (currentText.length > previousText.length) {
              yield currentText.substring(previousText.length);
              previousText = currentText;
            }
          }
        } else if (event.status == AiEventStatus.error) {
          yield event.error ?? 'Gemini Nano stream error';
          break;
        } else if (event.status == AiEventStatus.done) {
          break;
        }
      }
    } catch (e) {
      yield 'Gemini Nano streaming error: $e';
    }
  }

  String _buildPrompt(String basePrompt, {List<M3xTool>? tools}) {
    if (tools == null || tools.isEmpty || basePrompt.contains('[AVAILABLE TOOLS]')) {
      return basePrompt;
    }
    final buffer = StringBuffer(basePrompt);
    buffer.writeln('\n\n### [AVAILABLE TOOLS]');
    for (final tool in tools) {
      final appStr = tool.app != null ? ' (App: ${tool.app})' : '';
      buffer.writeln('- ${tool.name}$appStr: ${tool.description}');
      buffer.writeln('  Parameters: ${jsonEncode(tool.parameters)}');
    }
    buffer.writeln('\nTo invoke a tool, output ONLY valid JSON (double quotes everywhere) in this exact format with very short description:');
    buffer.writeln('{"action": "tool_call", "app": "<app>", "tool": "<tool>", "description": "Getting updates", "arguments": {}}');
    return buffer.toString();
  }
}
