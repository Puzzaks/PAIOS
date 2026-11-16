import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geminilocal/engine.dart';
import 'package:geminilocal/pages/support/elements.dart';
import 'package:geminilocal/parts/prompt.dart';
import 'package:m3x_mesh/m3x_mesh.dart';

void main() {
  group('1.8.1 UTF-8 mojibake & translation regressions', () {
    test('translations and github_explorer_page contain zero Windows-1251 mojibake', () {
      final translationDir = Directory('assets/translations');
      expect(translationDir.existsSync(), isTrue);

      for (final entity in translationDir.listSync().whereType<File>()) {
        final content = entity.readAsStringSync();
        expect(
          content.contains('\u0432\u0402'),
          isFalse,
          reason: '${entity.path} contains CP1251 mojibake',
        );
        expect(
          content.contains('\uFFFD'),
          isFalse,
          reason: '${entity.path} contains replacement character',
        );
      }

      final ghExplorer = File('lib/pages/github_explorer_page.dart').readAsStringSync();
      expect(ghExplorer.contains('\u0432\u0402'), isFalse);
      expect(ghExplorer.contains('\u2022'), isTrue);
    });

    test('all 5 locale files include concise channel_preview and new capability keys', () {
      for (final code in ['en', 'de', 'tr', 'uk', 'zh']) {
        final raw = File('assets/translations/$code.json').readAsStringSync();
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final preview = map['channel_preview'] as String;
        expect(preview.length, lessThanOrEqualTo(12), reason: '$code channel_preview too long');
        expect(map['fast_unavailable_on_channel'], isA<String>());
        expect(map['full_unavailable_on_channel'], isA<String>());
        expect(map['model_status_downloadable'], isA<String>());
        expect(map['model_status_downloading'], isA<String>());
      }
    });
  });

  group('Prompt & tool draft detection regressions', () {
    test('Prompt.generate clarifies empty args syntax for parameterless tools', () async {
      final prompt = Prompt(ghUrl: 'https://github.com/Puzzaks/PAIOS');
      final generated = await prompt.generate(
        'Help',
        const [],
        const {'version': '1.0'},
        tools: const [
          M3xTool(
            name: 'get_battery_status',
            app: 'paios',
            description: 'Checks battery',
            parameters: {'type': 'object', 'properties': {}},
          ),
        ],
      );
      expect(generated, contains('set "args": {} (never leave "args": empty)'));
    });

    test('Prompt.generateContinuation recognizes tool+args JSON drafts and plain code fences', () async {
      final prompt = Prompt(ghUrl: 'https://github.com/Puzzaks/PAIOS');
      final toolArgsDraft = await prompt.generateContinuation(
        'Help',
        const {'version': '1.0'},
        '"tool": "wikipedia_summary", "args": {"query": "Alpha',
        'Tell me about Alphabet',
      );
      expect(toolArgsDraft, contains('incomplete JSON tool call'));

      final plainFenceDraft = await prompt.generateContinuation(
        'Help',
        const {'version': '1.0'},
        '```\n{"tool": "get_battery_status"',
        'Battery?',
      );
      expect(plainFenceDraft, contains('incomplete JSON tool call'));
    });

    test('looksLikeStreamingToolDraft matches plain triple-backtick JSON fence but not python fence', () {
      expect(looksLikeStreamingToolDraft('```\n{"tool": "wikipedia_summary"'), isTrue);
      expect(looksLikeStreamingToolDraft('```json\n{"tool": "wikipedia_summary"'), isTrue);
      expect(looksLikeStreamingToolDraft('{"tool": "wikipedia_summary"'), isTrue);
      expect(looksLikeStreamingToolDraft('```python\nprint("hello")'), isFalse);
    });
  });

  group('AIEngine model capability flags', () {
    test('reads channel-specific Fast and Full availability with safe defaults', () {
      final engine = AIEngine();
      expect(engine.isStableFastAvailable, isTrue);
      expect(engine.isFastAvailableForSelectedChannel, isTrue);
      expect(engine.isFullAvailableForSelectedChannel, isTrue);

      engine.modelInfo = {
        'stableFastAvailable': false,
        'previewFastAvailable': true,
        'previewFullAvailable': false,
      };
      engine.config.modelReleaseStage = 'stable';
      expect(engine.isStableFastAvailable, isFalse);
      expect(engine.isFastAvailableForSelectedChannel, isFalse);
      expect(engine.isFullAvailableForSelectedChannel, isTrue);

      engine.config.modelReleaseStage = 'preview';
      expect(engine.isFastAvailableForSelectedChannel, isTrue);
      expect(engine.isFullAvailableForSelectedChannel, isFalse);
    });
  });
}
