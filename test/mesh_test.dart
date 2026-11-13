import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geminilocal/engine.dart';
import 'package:geminilocal/pages/support/elements.dart';
import 'package:geminilocal/parts/prompt.dart';
import 'package:geminilocal/services/local_ai_provider.dart';
import 'package:m3x_mesh/m3x_mesh.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('m3x_mesh & Agentic Tools Integration Tests', () {
    test('GeminiLocalAiProvider conforms to M3xAiProvider contract', () {
      final provider = GeminiLocalAiProvider();
      expect(provider.name, 'gemini_local');
      expect(provider.supportsLocalAi, isTrue);
    });

    test('Prompt.generate injects [AVAILABLE TOOLS] schema when tools are provided', () async {
      final prompt = Prompt(ghUrl: 'https://github.com/Puzzak/PAIOS');
      final tools = [
        M3xTool(
          name: 'ping_host',
          app: 'ptk',
          description: 'Pings a destination IP',
          parameters: {
            'type': 'object',
            'properties': {'host': {'type': 'string'}},
            'required': ['host'],
          },
        ),
      ];
      final output = await prompt.generate(
        'System prompt text',
        [],
        {'version': '1.0.0'},
        tools: tools,
      );
      expect(output.contains('### [AVAILABLE TOOLS]'), isTrue);
      expect(output.contains('ping_host'), isTrue);
      expect(output.contains('ptk'), isTrue);
      expect(output.contains('tool_call'), isTrue);
    });

    test('AIEngine initializes M3xMeshClient and M3xToolRegistry', () {
      final engine = AIEngine();
      expect(engine.meshClient, isNotNull);
      expect(engine.meshClient.bypassAuthInDebug, isTrue);
      expect(engine.toolRegistry, isNotNull);
    });

    test('M3xMeshClient queries and executes simulated tools from ptk and the2k48', () async {
      final client = M3xMeshClient(bypassAuthInDebug: true);
      final ptkTools = await client.queryTools('ptk');
      expect(ptkTools.any((t) => t.name == 'ping_host'), isTrue);

      final gameTools = await client.queryTools('the2k48');
      expect(gameTools.any((t) => t.name == 'get_high_score'), isTrue);

      final result = await client.callTool('ptk', 'ping_host', {'host': '8.8.8.8'});
      expect(result.isSuccess, isTrue);
      expect(result.result!['status'], 'success');
      expect(result.result!['host'], '8.8.8.8');
    });

    test('M3xMeshClient executes local simulated geminilocal tool query_local_ai', () async {
      final client = M3xMeshClient(bypassAuthInDebug: true);
      final result = await client.callTool('geminilocal', 'query_local_ai', {'prompt': 'Hello'});
      expect(result.isSuccess, isTrue);
      expect(result.result!['response'], contains('Simulated on-device response'));
    });

    test('M3xToolCall serialization supports description field', () {
      final call = M3xToolCall(
        id: '123',
        name: 'query_aicore_documentation',
        arguments: {'query': 'AICore'},
        description: 'Reading documentation for AICore',
      );
      expect(call.description, 'Reading documentation for AICore');
      final json = call.toJson();
      expect(json['description'], 'Reading documentation for AICore');

      final fromJson = M3xToolCall.fromJson(json);
      expect(fromJson.description, 'Reading documentation for AICore');
      expect(fromJson.name, 'query_aicore_documentation');
    });

    test('Prompt tool schema includes description field in template', () async {
      final prompt = Prompt(ghUrl: 'https://github.com/Puzzak/PAIOS');
      final tools = [
        M3xTool(
          name: 'get_battery_status',
          description: 'Checks device battery level and charging state',
          parameters: {'type': 'object', 'properties': {}},
        ),
      ];
      final output = await prompt.generate(
        'System prompt text',
        [],
        {'version': '1.0.0'},
        tools: tools,
      );
      expect(output, contains('"description": "Checking live data"'));
    });

    testWidgets('ToolCallBubble renders collapsed state and expands on tap', (tester) async {
      final toolCall = {
        'action': 'tool_call',
        'tool': 'query_aicore_documentation',
        'description': 'Reading AICore documentation',
        'arguments': {'query': 'AICore tokens'},
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ToolCallBubble(
              toolCall: toolCall,
              rawMessage: '{"tool": "query_aicore_documentation"}',
              toolResult: '{"status": "ok", "content": "Tokens documentation"}',
            ),
          ),
        ),
      );

      // Collapsed state: Title visible, Complete badge removed in 1.5.5, detail hidden
      expect(find.text('Reading AICore documentation'), findsOneWidget);
      expect(find.text('Complete'), findsNothing);
      expect(find.text('Tool Request'), findsNothing);
      expect(find.text('Tool Result'), findsNothing);

      // Tap to expand
      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();

      // Expanded state: Request and Result visible
      expect(find.text('Tool Request'), findsOneWidget);
      expect(find.text('Tool Result'), findsOneWidget);
      expect(find.textContaining('query_aicore_documentation'), findsOneWidget);
      expect(find.textContaining('Tokens documentation'), findsOneWidget);
    });

    testWidgets('text.chatlog converts tool call to ToolCallBubble and consumes system result', (tester) async {
      final t = text();
      final conversation = [
        {'user': 'User', 'message': 'How do tokens work in AICore?'},
        {
          'user': 'Gemini',
          'message': '```json\n{"action": "tool_call", "tool": "query_aicore_documentation", "description": "Reading AICore documentation", "arguments": {"query": "tokens"}}\n```',
        },
        {
          'user': 'System',
          'message': '[TOOL RESULT: {"tokens": 4096}]',
        },
        {'user': 'Gemini', 'message': 'Tokens are computed on-device with a 4096 context window.'},
      ];

      late List<Widget> widgets;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                widgets = t.chatlog(
                  aiChunk: '',
                  lastUser: '',
                  conversation: conversation,
                  context: context,
                );
                return ListView(children: widgets);
              },
            ),
          ),
        ),
      );

      // ToolCallBubble is rendered for the tool call
      expect(find.byType(ToolCallBubble), findsOneWidget);
      expect(find.text('Reading AICore documentation'), findsOneWidget);

      // Raw tool result [TOOL RESULT: ...] is NOT rendered as raw plain text
      expect(find.textContaining('[TOOL RESULT:'), findsNothing);

      // Natural language synthesis answer is rendered
      expect(find.textContaining('Tokens are computed on-device with a 4096 context window.'), findsOneWidget);
    });
  });
}
