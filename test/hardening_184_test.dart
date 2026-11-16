import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geminilocal/engine.dart';
import 'package:geminilocal/parts/prompt.dart';
import 'package:geminilocal/services/internal_tools_service.dart';
import 'package:hive/hive.dart';
import 'package:m3x_mesh/m3x_mesh.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeRouteSpec {
  final int statusCode;
  final String body;
  const _FakeRouteSpec(this.statusCode, this.body);
}

typedef _FakeRouteHandler = _FakeRouteSpec Function(Uri uri);

class _FakeHttpHeaders implements HttpHeaders {
  final Map<String, List<String>> values = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = [value.toString()];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  @override
  final int statusCode;
  final List<int> _bytes;

  _FakeHttpClientResponse(this.statusCode, String body)
      : _bytes = utf8.encode(body);

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable([_bytes]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientRequest implements HttpClientRequest {
  @override
  final Uri uri;
  final _FakeRouteHandler handler;
  @override
  final _FakeHttpHeaders headers = _FakeHttpHeaders();

  _FakeHttpClientRequest(this.uri, this.handler);

  @override
  Future<HttpClientResponse> close() async {
    final spec = handler(uri);
    return _FakeHttpClientResponse(spec.statusCode, spec.body);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClient implements HttpClient {
  final Queue<_FakeRouteHandler> handlers;

  @override
  Duration? connectionTimeout;

  _FakeHttpClient(this.handlers);

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    if (handlers.isEmpty) {
      throw StateError('Unexpected HTTP GET to $url');
    }
    return _FakeHttpClientRequest(url, handlers.removeFirst());
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String _extractPromptArg(Object? arguments) {
  if (arguments is Map) {
    final payload = arguments['payload'];
    if (payload is Map) {
      return payload['prompt']?.toString() ?? '';
    }
  }
  return '';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('stitchContinuation, ellipsis normalization, mid-word recovery & stutter guard', () {
    test('deduplicates repeated clause prefixes, trimmed-space seams, and short rollback tails', () {
      expect(
        AIEngine.stitchContinuation(
          'The forecast for November 16th is -0.5°C to ',
          'The forecast for November 16th is -0.5°C to 5.0°C',
        ),
        'The forecast for November 16th is -0.5°C to 5.0°C',
      );

      expect(
        AIEngine.stitchContinuation(
          'The forecast for November 16th is -0.5°C to ',
          'The forecast for November 16th is -0.5°C to\n5.0°C',
        ),
        'The forecast for November 16th is -0.5°C to\n5.0°C',
      );

      expect(
        AIEngine.stitchContinuation(
          'The forecast for November 16th is -0.5°C to about',
          'The forecast for November 16th is -0.5°C to 5.0°C',
        ),
        'The forecast for November 16th is -0.5°C to 5.0°C',
      );

      expect(
        AIEngine.stitchContinuation(
          'The forecast is cold today. Wind is 10 km/h.',
          'The forecast is cold today. Tomorrow it will snow.',
        ),
        'The forecast is cold today. Wind is 10 km/h. Tomorrow it will snow.',
      );
    });

    test('protects short word boundaries while completing mid-word cutoffs seamlessly', () {
      expect(
        AIEngine.stitchContinuation('lead to', 'today we see'),
        'lead to today we see',
      );
      expect(
        AIEngine.stitchContinuation('lead to', 'to win'),
        'lead to win',
      );
      expect(
        AIEngine.stitchContinuation('Eliezer Yud', 'Yudkowsky is a researcher.'),
        'Eliezer Yudkowsky is a researcher.',
      );
      expect(
        AIEngine.stitchContinuation('maximize paper', 'paperclips.'),
        'maximize paperclips.',
      );
    });

    test('normalizes leading/trailing continuation ellipses without eating decimals', () {
      expect(AIEngine.stripLeadingEllipsis('..also'), 'also');
      expect(AIEngine.stripLeadingEllipsis('. . . also'), 'also');
      expect(AIEngine.stripLeadingEllipsis('.5°C'), '.5°C');
      expect(
        AIEngine.stitchContinuation('Wait...', '...never mind.'),
        'Wait never mind.',
      );
      expect(
        AIEngine.stitchContinuation('Value is', '.5°C'),
        'Value is .5°C',
      );
    });

    test('detectAndTrimStutterLoop catches 3+ consecutive repeats and ignores valid numeric/code text', () {
      final stutter1 = AIEngine.detectAndTrimStutterLoop(
        'I think that and...that and...that and...that',
      );
      expect(stutter1.detected, isTrue);
      expect(stutter1.text, 'I think that and...that');

      final stutter2 = AIEngine.detectAndTrimStutterLoop(
        'The quick brown fox. The quick brown fox. The quick brown fox.',
      );
      expect(stutter2.detected, isTrue);
      expect(stutter2.text, 'The quick brown fox.');

      final numbersOnly = AIEngine.detectAndTrimStutterLoop(
        'Values: 10 10 10 10 10 10 10 10 10',
      );
      expect(numbersOnly.detected, isFalse);

      final insideCode = AIEngine.detectAndTrimStutterLoop(
        '```dart\nprint("repeat phrase");\nprint("repeat phrase");\nprint("repeat phrase");',
      );
      expect(insideCode.detected, isFalse);
    });
  });

  group('Prompt.generateContinuation & Prompt.generate tool guidance', () {
    test('splitTrailingPartialWord detects mid-word tail and generateContinuation adds complete-word restart cue', () async {
      final split = Prompt.splitTrailingPartialWord('Research by Eliezer Yud');
      expect(split, isNotNull);
      expect(split!.completeTail, 'Research by Eliezer ');
      expect(split.partialToken, 'Yud');

      expect(Prompt.splitTrailingPartialWord('Complete sentence.'), isNull);
      expect(Prompt.splitTrailingPartialWord('Trailing space '), isNull);

      final prompt = Prompt(ghUrl: 'https://github.com/Puzzaks/PAIOS');
      final cont = await prompt.generateContinuation(
        'You are PAIOS.',
        {'version': 'nano-v3'},
        'Research by Eliezer Yud',
        'Who is Eliezer Yudkowsky?',
      );
      expect(cont, contains('Research by Eliezer Yud'));
      expect(cont, contains('If "Yud" was cut off'));
      expect(cont, contains('Eliezer '));
    });

    test('Prompt.generate prefers wikipedia_summary for general topic questions', () async {
      final prompt = Prompt(ghUrl: 'https://github.com/Puzzaks/PAIOS');
      final generated = await prompt.generate(
        'Help',
        const [],
        const {'version': 'nano-v3'},
        tools: const [
          M3xTool(
            name: 'wikipedia_summary',
            app: 'paios',
            description: 'Summary',
            parameters: {'type': 'object', 'properties': {}},
          ),
        ],
      );
      expect(generated, contains('Prefer wikipedia_summary for general "What is X?" explanations'));
    });
  });

  group('AIEngine lifecycle, cancellation, continuation & tool rescue', () {
    late Directory tempDir;
    const localAiChannel = MethodChannel('flutter_local_ai');
    const eventsChannel = EventChannel('flutter_local_ai_events');

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      tempDir = await Directory.systemTemp.createTemp('paios_hardening_184_');
      Hive.init(tempDir.path);
      await Hive.openBox('paios_storage');

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(localAiChannel, (call) async {
        if (call.method == 'initAiCore' || call.method == 'init') {
          return {'status': 'available', 'available': true, 'statusCode': 3, 'version': 'nano-v3'};
        }
        if (call.method == 'getModelInfo') {
          return {'status': 'available', 'available': true, 'statusCode': 3, 'version': 'nano-v3'};
        }
        return null;
      });
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(eventsChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(localAiChannel, null);
      if (Hive.isBoxOpen('paios_storage')) {
        await Hive.box('paios_storage').close();
      }
      await Hive.deleteFromDisk();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('cancelGeneration during initEngine aborts stream launch and resets all turn flags', () async {
      final initCompleter = Completer<dynamic>();
      int generateEventsCalls = 0;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(localAiChannel, (call) async {
        if (call.method == 'init') {
          return initCompleter.future;
        }
        return {'status': 'available', 'available': true, 'statusCode': 3, 'version': 'nano-v3'};
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        eventsChannel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            generateEventsCalls++;
          },
        ),
      );

      final engine = AIEngine();
      addTearDown(engine.dispose);
      engine.isAvailable = true;
      engine.prompt.text = 'Explain fusion';

      final genFuture = engine.generateStream();
      // Give generateStream a microtask to enter initEngine
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(engine.isLoading, isTrue);
      expect(engine.isGenerating, isTrue);

      // Double-entry while initEngine is pending must be ignored
      final doubleEntry = engine.generateStream();
      await doubleEntry;

      await engine.cancelGeneration();
      expect(engine.isLoading, isFalse);
      expect(engine.isGenerating, isFalse);
      expect(engine.isContinuing, isFalse);
      expect(engine.isSynthesizing, isFalse);
      expect(engine.responseText, isEmpty);
      expect(engine.lastPrompt, isEmpty);
      expect(engine.streamingMessageTime, isNull);
      expect(engine.streamingUserMessageTime, isNull);

      initCompleter.complete('Initialized');
      await genFuture;

      expect(generateEventsCalls, 0);
      expect(engine.isLoading, isFalse);
      expect(engine.isGenerating, isFalse);
    });

    test('errorRetry retries cleanly after AiEventStatus.error and aborts if cancelled during delay', () async {
      int round = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        eventsChannel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            final promptArg = _extractPromptArg(arguments);
            if (promptArg.contains('Task: Create a short')) {
              scheduleMicrotask(() {
                events.success({'status': 'Streaming', 'response': {'text': 'Chat Title', 'reason': 'STOP'}});
                events.success({'status': 'Done', 'reason': 'STOP', 'response': {'text': 'Chat Title', 'reason': 'STOP'}});
              });
              return;
            }
            final currentRound = round++;
            scheduleMicrotask(() {
              if (currentRound == 0) {
                events.success({
                  'status': 'Error',
                  'error': 'Transient NPU busy',
                });
              } else {
                events.success({
                  'status': 'Streaming',
                  'response': {'text': 'Recovered answer.', 'reason': 'STOP'},
                });
                events.success({
                  'status': 'Done',
                  'reason': 'STOP',
                  'response': {'text': 'Recovered answer.', 'reason': 'STOP'},
                });
              }
            });
          },
        ),
      );

      final engine = AIEngine();
      addTearDown(engine.dispose);
      engine.isAvailable = true;
      engine.isInitialized = true;
      engine.errorRetry = true;
      engine.modelInfo = {'version': 'nano-v3'};
      engine.prompt.text = 'Hello';

      await engine.generateStream();
      for (int i = 0;
          i < 100 &&
              (engine.isLoading ||
                  engine.isGenerating ||
                  engine.context.length < 2 ||
                  !engine.chats.containsKey(engine.currentChat));
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(round, 2);
      expect(engine.isLoading, isFalse);
      expect(engine.isGenerating, isFalse);
      expect(engine.context.length, 2);
      expect(engine.context.last['message'], 'Recovered answer.');
    });

    test('errorRetry aborts cleanly if cancelled during 500ms retry backoff', () async {
      int round = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        eventsChannel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            round++;
            scheduleMicrotask(() {
              events.success({
                'status': 'Error',
                'error': 'Transient NPU busy',
              });
            });
          },
        ),
      );

      final engine = AIEngine();
      addTearDown(engine.dispose);
      engine.isAvailable = true;
      engine.isInitialized = true;
      engine.errorRetry = true;
      engine.modelInfo = {'version': 'nano-v3'};
      engine.prompt.text = 'Hello';

      await engine.generateStream();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await engine.cancelGeneration();
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(round, 1);
      expect(engine.isLoading, isFalse);
      expect(engine.isGenerating, isFalse);
    });

    test('unexpected stream closure (onDone without terminal event) and analyzeError unlock UI flags', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        eventsChannel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            scheduleMicrotask(() {
              events.endOfStream();
            });
          },
        ),
      );

      final engine = AIEngine();
      addTearDown(engine.dispose);
      engine.isAvailable = true;
      engine.isInitialized = true;
      engine.modelInfo = {'version': 'nano-v3'};
      engine.prompt.text = 'Test unexpected close';

      await engine.generateStream();
      for (int i = 0; i < 40 && (engine.isLoading || engine.isGenerating); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(engine.isLoading, isFalse);
      expect(engine.isGenerating, isFalse);
      expect(engine.isContinuing, isFalse);
      expect(engine.isSynthesizing, isFalse);

      engine.isContinuing = true;
      engine.analyzeError('TestAction', Exception('boom'));
      expect(engine.isContinuing, isFalse);
      expect(engine.isLoading, isFalse);
      expect(engine.isGenerating, isFalse);
    });

    test('dynamic continuation stitching deduplicates multi-token repeated clause live and stops on zero net progress', () async {
      int round = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        eventsChannel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            final promptArg = _extractPromptArg(arguments);
            if (promptArg.contains('Task: Create a short')) {
              scheduleMicrotask(() {
                events.success({'status': 'Streaming', 'response': {'text': 'Chat Title', 'reason': 'STOP'}});
                events.success({'status': 'Done', 'reason': 'STOP', 'response': {'text': 'Chat Title', 'reason': 'STOP'}});
              });
              return;
            }
            final r = round++;
            scheduleMicrotask(() {
              if (r == 0) {
                const p0 = 'The forecast for November 16th is -0.5°C to ';
                events.success({
                  'status': 'Streaming',
                  'response': {'text': p0, 'reason': 'MAX_TOKENS'},
                });
                events.success({
                  'status': 'Done',
                  'reason': 'MAX_TOKENS',
                  'response': {'text': p0, 'reason': 'MAX_TOKENS'},
                });
              } else if (r == 1) {
                // Streams tiny token first, then full overlapping clause
                events.success({
                  'status': 'Streaming',
                  'response': {'text': 'The', 'reason': 'null'},
                });
                events.success({
                  'status': 'Streaming',
                  'response': {
                    'text': 'The forecast for November 16th is -0.5°C to 5.0°C.',
                    'reason': 'STOP',
                  },
                });
                events.success({
                  'status': 'Done',
                  'reason': 'STOP',
                  'response': {
                    'text': 'The forecast for November 16th is -0.5°C to 5.0°C.',
                    'reason': 'STOP',
                  },
                });
              }
            });
          },
        ),
      );

      final engine = AIEngine();
      addTearDown(engine.dispose);
      engine.isAvailable = true;
      engine.isInitialized = true;
      engine.modelInfo = {'version': 'nano-v3'};
      engine.prompt.text = 'Weather forecast';

      await engine.generateStream();
      for (int i = 0;
          i < 80 &&
              (engine.isLoading ||
                  engine.isGenerating ||
                  engine.isContinuing ||
                  engine.context.length < 2 ||
                  !engine.chats.containsKey(engine.currentChat));
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(engine.context.length, 2);
      expect(
        engine.context.last['message'],
        'The forecast for November 16th is -0.5°C to 5.0°C.',
      );
    });

    test('malformed JSON draft allows "description" key and rescues Turn-1 incomplete tool draft with tool-free retry', () async {
      final initInstructions = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(localAiChannel, (call) async {
        if (call.method == 'init') {
          final args = call.arguments as Map?;
          initInstructions.add(args?['instructions']?.toString() ?? '');
          return 'Initialized';
        }
        return {'status': 'available', 'available': true, 'statusCode': 3, 'version': 'nano-v3'};
      });

      int streamRound = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        eventsChannel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            final promptArg = _extractPromptArg(arguments);
            if (promptArg.contains('Task: Create a short')) {
              scheduleMicrotask(() {
                events.success({'status': 'Streaming', 'response': {'text': 'Chat Title', 'reason': 'STOP'}});
                events.success({'status': 'Done', 'reason': 'STOP', 'response': {'text': 'Chat Title', 'reason': 'STOP'}});
              });
              return;
            }
            final r = streamRound++;
            scheduleMicrotask(() {
              if (r == 0) {
                // Turn 1 cuts off inside a tool JSON draft containing "description"
                const draft = '{"tool": "wikipedia_summary", "description": "lookup", "args": {"query": "Paperclip';
                events.success({
                  'status': 'Streaming',
                  'response': {'text': draft, 'reason': 'MAX_TOKENS'},
                });
                events.success({
                  'status': 'Done',
                  'reason': 'MAX_TOKENS',
                  'response': {'text': draft, 'reason': 'MAX_TOKENS'},
                });
              } else if (r == 1) {
                // Continuation round still ends incomplete
                const cont = ' Maximizer"';
                events.success({
                  'status': 'Streaming',
                  'response': {'text': cont, 'reason': 'STOP'},
                });
                events.success({
                  'status': 'Done',
                  'reason': 'STOP',
                  'response': {'text': cont, 'reason': 'STOP'},
                });
              } else {
                // Tool-free fallback generation answers conceptually!
                const answer = 'A paperclip maximizer is a thought experiment by Nick Bostrom.';
                events.success({
                  'status': 'Streaming',
                  'response': {'text': answer, 'reason': 'STOP'},
                });
                events.success({
                  'status': 'Done',
                  'reason': 'STOP',
                  'response': {'text': answer, 'reason': 'STOP'},
                });
              }
            });
          },
        ),
      );

      final engine = AIEngine();
      addTearDown(engine.dispose);
      engine.isAvailable = true;
      engine.isInitialized = true;
      engine.modelInfo = {'version': 'nano-v3'};
      engine.toolRegistry.register(
        const M3xTool(
          name: 'wikipedia_summary',
          app: 'paios',
          description: 'Search Wikipedia',
          parameters: {
            'type': 'object',
            'required': ['query'],
            'properties': {'query': {'type': 'string'}},
          },
        ),
      );
      engine.setExtensionEnabled('paios.wikipedia', true);
      engine.prompt.text = "What's a paperclip Maximizer?";

      await engine.generateStream();
      for (int i = 0;
          i < 100 &&
              (engine.isLoading ||
                  engine.isGenerating ||
                  engine.isContinuing ||
                  engine.context.length < 2 ||
                  !engine.chats.containsKey(engine.currentChat));
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Continuation ran (round 1 because "description" was NOT rejected!), then tool-free retry ran (round 2)
      expect(streamRound, 3);
      expect(initInstructions.last, isNot(contains('### [AVAILABLE TOOLS]')));
      expect(engine.context.last['message'], contains('Nick Bostrom'));
      expect(
        engine.logger.logs.any(
          (l) => (l['message']?.toString() ?? '').contains(
            'Tool request invalid/incomplete on turn 1; retrying without tools',
          ),
        ),
        isTrue,
      );
    });

    test('stutter loop in continueGenerating trims repeats and halts further continuation', () async {
      int round = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        eventsChannel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            final promptArg = _extractPromptArg(arguments);
            if (promptArg.contains('Task: Create a short')) {
              scheduleMicrotask(() {
                events.success({'status': 'Streaming', 'response': {'text': 'Chat Title', 'reason': 'STOP'}});
                events.success({'status': 'Done', 'reason': 'STOP', 'response': {'text': 'Chat Title', 'reason': 'STOP'}});
              });
              return;
            }
            final r = round++;
            scheduleMicrotask(() {
              if (r == 0) {
                const p0 = 'I think that ';
                events.success({
                  'status': 'Streaming',
                  'response': {'text': p0, 'reason': 'MAX_TOKENS'},
                });
                events.success({
                  'status': 'Done',
                  'reason': 'MAX_TOKENS',
                  'response': {'text': p0, 'reason': 'MAX_TOKENS'},
                });
              } else {
                const loopText = 'and...that and...that and...that';
                events.success({
                  'status': 'Streaming',
                  'response': {'text': loopText, 'reason': 'MAX_TOKENS'},
                });
                events.success({
                  'status': 'Done',
                  'reason': 'MAX_TOKENS',
                  'response': {'text': loopText, 'reason': 'MAX_TOKENS'},
                });
              }
            });
          },
        ),
      );

      final engine = AIEngine();
      addTearDown(engine.dispose);
      engine.isAvailable = true;
      engine.isInitialized = true;
      engine.modelInfo = {'version': 'nano-v3'};
      engine.prompt.text = 'Explain something';

      await engine.generateStream();
      for (int i = 0;
          i < 80 &&
              (engine.isLoading ||
                  engine.isGenerating ||
                  engine.isContinuing ||
                  engine.context.length < 2 ||
                  !engine.chats.containsKey(engine.currentChat));
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Despite MAX_TOKENS on round 1, stutter detector halted further continuations
      expect(round, 2);
      expect(engine.context.length, 2);
      expect(engine.context.last['message'], 'I think that and...that');
    });

    test('cancelGeneration while meshClient.callTool is in flight aborts chat mutation and synthesis', () async {
      final toolCompleter = Completer<Map<String, dynamic>>();
      int streamCalls = 0;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        eventsChannel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            streamCalls++;
            scheduleMicrotask(() {
              const toolJson = '{"tool": "slow_test_tool", "app": "paios", "args": {"query": "test"}}';
              events.success({
                'status': 'Streaming',
                'response': {'text': toolJson, 'reason': 'STOP'},
              });
              events.success({
                'status': 'Done',
                'reason': 'STOP',
                'response': {'text': toolJson, 'reason': 'STOP'},
              });
            });
          },
        ),
      );

      final engine = AIEngine();
      addTearDown(engine.dispose);
      engine.isAvailable = true;
      engine.isInitialized = true;
      engine.modelInfo = {'version': 'nano-v3'};
      engine.meshClient.registerLocalTool(
        M3xTool(
          name: 'slow_test_tool',
          app: 'paios',
          description: 'Slow tool',
          parameters: {
            'type': 'object',
            'required': ['query'],
            'properties': {'query': {'type': 'string'}},
          },
          handler: (_) => toolCompleter.future,
        ),
      );
      engine.prompt.text = 'Run slow tool';

      await engine.generateStream();
      for (int i = 0; i < 40 && !engine.isSynthesizing; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 15));
      }
      expect(engine.isSynthesizing, isTrue);

      await engine.cancelGeneration();
      expect(engine.isLoading, isFalse);
      expect(engine.isSynthesizing, isFalse);

      toolCompleter.complete({'found': true, 'result': 'late'});
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // No synthesis stream started and no messages appended after cancellation
      expect(streamCalls, 1);
      expect(engine.context, isEmpty);
      expect(engine.isLoading, isFalse);
      expect(engine.isSynthesizing, isFalse);
    });

    test('tool synthesis prompt guides fallback to own knowledge when tool returns found: false', () async {
      final synthesisPrompts = <String>[];
      const syntheticResponse = 'Here is what I know from general knowledge.';
      int round = 0;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        eventsChannel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            final promptArg = _extractPromptArg(arguments);
            if (promptArg.contains('Task: Create a short')) {
              scheduleMicrotask(() {
                events.success({'status': 'Streaming', 'response': {'text': 'Chat Title', 'reason': 'STOP'}});
                events.success({'status': 'Done', 'reason': 'STOP', 'response': {'text': 'Chat Title', 'reason': 'STOP'}});
              });
              return;
            }
            final r = round++;
            if (r == 1 && promptArg.isNotEmpty) {
              synthesisPrompts.add(promptArg);
            }
            scheduleMicrotask(() {
              if (r == 0) {
                const toolJson = '{"tool": "not_found_tool", "app": "paios", "args": {"query": "xyz"}}';
                events.success({
                  'status': 'Streaming',
                  'response': {'text': toolJson, 'reason': 'STOP'},
                });
                events.success({
                  'status': 'Done',
                  'reason': 'STOP',
                  'response': {'text': toolJson, 'reason': 'STOP'},
                });
              } else {
                events.success({
                  'status': 'Streaming',
                  'response': {'text': syntheticResponse, 'reason': 'STOP'},
                });
                events.success({
                  'status': 'Done',
                  'reason': 'STOP',
                  'response': {'text': syntheticResponse, 'reason': 'STOP'},
                });
              }
            });
          },
        ),
      );

      final engine = AIEngine();
      addTearDown(engine.dispose);
      engine.isAvailable = true;
      engine.isInitialized = true;
      engine.modelInfo = {'version': 'nano-v3'};
      engine.meshClient.registerLocalTool(
        M3xTool(
          name: 'not_found_tool',
          app: 'paios',
          description: 'Mock search returning found: false',
          parameters: {
            'type': 'object',
            'required': ['query'],
            'properties': {'query': {'type': 'string'}},
          },
          handler: (_) async => {
            'found': false,
            'message': 'No instant answer found; try rephrasing your query.',
          },
        ),
      );
      engine.prompt.text = 'Explain xyz';

      await engine.generateStream();
      for (int i = 0;
          i < 80 &&
              (engine.isLoading ||
                  engine.isGenerating ||
                  engine.isSynthesizing ||
                  engine.context.length < 4 ||
                  !engine.chats.containsKey(engine.currentChat));
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(synthesisPrompts, hasLength(1));
      expect(
        synthesisPrompts.single,
        contains(
          "The online lookup returned no direct result. Answer the user's question from your own knowledge if possible, or briefly say you couldn't find it.",
        ),
      );
      expect(engine.context.last['message'], syntheticResponse);
    });
  });

  group('InternalToolsService hardening & argument normalization', () {
    test('normalizeToolArgs maps aliases and falls back wikipedia_details without question to wikipedia_summary', () async {
      final norm1 = InternalToolsService.normalizeToolArgs(
        'wikipedia_details',
        {'topic': 'Paperclip maximizer'},
        fallbackQuestion: "What's a paperclip Maximizer?",
      );
      expect(norm1['query'], 'Paperclip maximizer');
      expect(norm1['question'], "What's a paperclip Maximizer?");

      final handlers = Queue<_FakeRouteHandler>.from([
        (uri) {
          expect(uri.path, '/w/rest.php/v1/search/title');
          expect(uri.queryParameters['q'], 'Paperclip maximizer');
          return _FakeRouteSpec(
            200,
            jsonEncode({
              'pages': [
                {'key': 'Paperclip_maximizer', 'title': 'Paperclip maximizer'},
              ],
            }),
          );
        },
        (uri) {
          // Verified: called summary REST endpoint, NOT action=query extracts!
          expect(uri.path, '/api/rest_v1/page/summary/Paperclip_maximizer');
          return _FakeRouteSpec(
            200,
            jsonEncode({
              'title': 'Paperclip maximizer',
              'extract': 'Thought experiment illustrating AI alignment risk.',
            }),
          );
        },
      ]);

      final service = InternalToolsService(
        onlineCheckFn: () async => true,
        httpClientFactory: () => _FakeHttpClient(handlers),
      );

      final res = await service.executeOnlineTool(
        'wikipedia_details',
        {'title': 'Paperclip maximizer'},
      );
      expect(res['found'], isTrue);
      expect(res['title'], 'Paperclip maximizer');
    });

    test('wikipediaDetails falls back to ranked sections if readerAgent times out', () async {
      final longParagraph = List.filled(
        25,
        'Climate in Kyiv features warm summers and snowy winters.',
      ).join(' ');
      final handlers = Queue<_FakeRouteHandler>.from([
        (uri) => _FakeRouteSpec(
              200,
              jsonEncode({
                'pages': [
                  {'key': 'Kyiv', 'title': 'Kyiv'},
                ],
              }),
            ),
        (uri) => _FakeRouteSpec(
              200,
              jsonEncode({
                'query': {
                  'pages': {
                    '1': {
                      'pageid': 1,
                      'title': 'Kyiv',
                      'extract': '== Climate ==\n$longParagraph',
                    },
                  },
                },
              }),
            ),
      ]);

      final service = InternalToolsService(
        onlineCheckFn: () async => true,
        httpClientFactory: () => _FakeHttpClient(handlers),
        readerAgentTimeout: const Duration(milliseconds: 30),
      );

      final res = await service.wikipediaDetails(
        'Kyiv',
        'What is the climate?',
        readerAgent: (text, question) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return 'Should time out';
        },
      );

      expect(res['found'], isTrue);
      expect(res['condensed'], isFalse);
      expect(res['details'], contains('Climate in Kyiv'));
    });

    test('duckDuckGoSearch omits wikipedia_summary hint when paios.wikipedia is disabled', () async {
      final handlers = Queue<_FakeRouteHandler>.from([
        (uri) => _FakeRouteSpec(
              200,
              jsonEncode({
                'Heading': '',
                'AbstractText': '',
                'Answer': '',
                'Definition': '',
                'RelatedTopics': [],
              }),
            ),
      ]);

      final service = InternalToolsService(
        onlineCheckFn: () async => true,
        httpClientFactory: () => _FakeHttpClient(handlers),
        isModuleEnabled: (id) => id != InternalToolsService.moduleWikipedia,
      );

      final res = await service.duckDuckGoSearch('obscure query');
      expect(res['found'], isFalse);
      expect(res['message'], isNot(contains('wikipedia_summary')));
    });
  });

  group('Mid-clause cutoff detection & bounded STOP rescue', () {
    late Directory tempDir;
    const localAiChannel = MethodChannel('flutter_local_ai');
    const eventsChannel = EventChannel('flutter_local_ai_events');

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      tempDir = await Directory.systemTemp.createTemp('paios_stop_cutoff_');
      Hive.init(tempDir.path);
      await Hive.openBox('paios_storage');

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(localAiChannel, (call) async {
        if (call.method == 'initAiCore' || call.method == 'init') {
          return {'status': 'available', 'available': true, 'statusCode': 3, 'version': 'nano-v3'};
        }
        if (call.method == 'getModelInfo') {
          return {'status': 'available', 'available': true, 'statusCode': 3, 'version': 'nano-v3'};
        }
        return null;
      });
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(eventsChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(localAiChannel, null);
      if (Hive.isBoxOpen('paios_storage')) {
        await Hive.box('paios_storage').close();
      }
      await Hive.deleteFromDisk();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('isLikelyMidClauseCutoff catches preposition/determiner + modifier tails without false positives', () {
      expect(
        AIEngine.isLikelyMidClauseCutoff(
          'The concept of a "paperclip maximizer" is a thought experiment that highlights a potential risk with advanced',
        ),
        isTrue,
      );
      expect(AIEngine.isLikelyMidClauseCutoff('It raises concerns with extreme'), isTrue);
      expect(AIEngine.isLikelyMidClauseCutoff('This can lead to unintended'), isTrue);
      expect(AIEngine.isLikelyMidClauseCutoff('Understanding the field of artificial'), isTrue);
      expect(AIEngine.isLikelyMidClauseCutoff('Here is an example of a potential'), isTrue);
      expect(AIEngine.isLikelyMidClauseCutoff('We need to adapt to the new'), isTrue);
      expect(AIEngine.isLikelyMidClauseCutoff('I prioritize your'), isTrue);

      // Complete short/non-punctuated answers and punctuated answers must return false
      expect(AIEngine.isLikelyMidClauseCutoff('Hi'), isFalse);
      expect(AIEngine.isLikelyMidClauseCutoff('For'), isFalse);
      expect(AIEngine.isLikelyMidClauseCutoff('Yes, I can help with that'), isFalse);
      expect(AIEngine.isLikelyMidClauseCutoff('Everything looks great'), isFalse);
      expect(AIEngine.isLikelyMidClauseCutoff('Sure, I can help with that today.'), isFalse);
      expect(AIEngine.isLikelyMidClauseCutoff('Back in 5 minutes'), isFalse);
      expect(AIEngine.isLikelyMidClauseCutoff('Everything is set for dinner'), isFalse);
      expect(AIEngine.isLikelyMidClauseCutoff('Everything is ready for tomorrow'), isFalse);
      expect(AIEngine.isLikelyMidClauseCutoff('Yes, all good'), isFalse);

      // Trailing transitive -ing participle cutoffs vs complete -ing replies
      expect(
        AIEngine.isLikelyMidClauseCutoff(
          'It focuses on aligning AI goals with human values and ensuring',
        ),
        isTrue,
      );
      expect(
        AIEngine.isLikelyMidClauseCutoff(
          'This reduces risk without compromising',
        ),
        isTrue,
      );
      expect(AIEngine.isLikelyMidClauseCutoff('Nothing is missing.'), isFalse);
      expect(AIEngine.isLikelyMidClauseCutoff('Good morning'), isFalse);
      expect(AIEngine.isLikelyMidClauseCutoff('Thanks for helping'), isFalse);
      expect(AIEngine.isLikelyMidClauseCutoff('Thanks for asking'), isFalse);
    });

    test('shouldContinueOnDone rescues STOP/0 once on v3 prose and synthesis mid-clause cutoffs and respects all guards', () {
      final engine = AIEngine();
      addTearDown(engine.dispose);
      engine.modelInfo = {'isNanoV4': false};

      const truncated =
          'The concept of a "paperclip maximizer" is a thought experiment that highlights a potential risk with advanced';

      expect(AIEngine.maxStopCutoffContinuations, 1);
      expect(engine.shouldContinueOnDoneForTest('STOP', truncated), isTrue);
      expect(engine.shouldContinueOnDoneForTest('0', truncated), isTrue);
      expect(
        engine.shouldContinueOnDoneForTest(
          'STOP',
          truncated,
          stopCutoffCount: AIEngine.maxStopCutoffContinuations,
        ),
        isFalse,
      );
      // v1.8.7: tool-synthesis responses (e.g. "The forecast for") also get 1 bounded STOP mid-clause rescue
      expect(
        engine.shouldContinueOnDoneForTest('STOP', truncated, isSynthesis: true),
        isTrue,
      );
      expect(
        engine.shouldContinueOnDoneForTest(
          'STOP',
          'The forecast for',
          isSynthesis: true,
        ),
        isTrue,
      );
      expect(
        engine.shouldContinueOnDoneForTest(
          'STOP',
          'The forecast for today is sunny with a high of 18°C.',
          isSynthesis: true,
        ),
        isFalse,
      );
      expect(
        engine.shouldContinueOnDoneForTest('STOP', '```dart\nprint(1);\n```'),
        isFalse,
      );
      expect(
        engine.shouldContinueOnDoneForTest(
          'STOP',
          '{"tool": "wikipedia_summary", "args": {"query": "Alpha',
        ),
        isFalse,
      );
      // Single-word dangling tails stay false (< 2 words), short 3-word possessive stays false,
      // while short preposition cutoffs ("The forecast for") rescue on STOP
      expect(
        engine.shouldContinueOnDoneForTest('STOP', 'For'),
        isFalse,
      );
      expect(
        engine.shouldContinueOnDoneForTest('STOP', 'I prioritize your'),
        isFalse,
      );
      expect(
        engine.shouldContinueOnDoneForTest('STOP', 'Everything is set for dinner'),
        isFalse,
      );

      engine.modelInfo = {'isNanoV4': true};
      expect(engine.shouldContinueOnDoneForTest('STOP', truncated), isFalse);
      expect(
        engine.shouldContinueOnDoneForTest(
          'STOP',
          'The forecast for',
          isSynthesis: true,
        ),
        isFalse,
      );
    });

    test('generateStream rescues a single STOP mid-clause cutoff via continueGenerating and halts after maxStopCutoffContinuations=1', () async {
      int streamRound = 0;
      const truncatedHead =
          'The concept of a "paperclip maximizer" is a thought experiment that highlights a potential risk with advanced';
      const continuationTail = 'AI systems with unintended';
      const thirdTail = 'consequences.';

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        eventsChannel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            final promptArg = _extractPromptArg(arguments);
            if (promptArg.contains('Task: Create a short')) {
              scheduleMicrotask(() {
                events.success({'status': 'Streaming', 'response': {'text': 'Paperclip Maximizer', 'reason': 'STOP'}});
                events.success({'status': 'Done', 'reason': 'STOP', 'response': {'text': 'Paperclip Maximizer', 'reason': 'STOP'}});
              });
              return;
            }
            final r = streamRound++;
            scheduleMicrotask(() {
              if (r == 0) {
                events.success({
                  'status': 'Streaming',
                  'response': {'text': truncatedHead, 'reason': 'STOP'},
                });
                events.success({
                  'status': 'Done',
                  'reason': 'STOP',
                  'response': {'text': truncatedHead, 'reason': 'STOP'},
                });
              } else if (r == 1) {
                // Even if the continuation also ends mid-clause with STOP, cap=1 halts here
                events.success({
                  'status': 'Streaming',
                  'response': {'text': continuationTail, 'reason': 'STOP'},
                });
                events.success({
                  'status': 'Done',
                  'reason': 'STOP',
                  'response': {'text': continuationTail, 'reason': 'STOP'},
                });
              } else {
                events.success({
                  'status': 'Streaming',
                  'response': {'text': thirdTail, 'reason': 'STOP'},
                });
                events.success({
                  'status': 'Done',
                  'reason': 'STOP',
                  'response': {'text': thirdTail, 'reason': 'STOP'},
                });
              }
            });
          },
        ),
      );

      final engine = AIEngine();
      addTearDown(engine.dispose);
      engine.isAvailable = true;
      engine.isInitialized = true;
      engine.modelInfo = {'version': 'nano-v3', 'isNanoV4': false};
      engine.prompt.text = 'Explain the paperclip maximizer';

      await engine.generateStream();
      for (int i = 0;
          i < 80 &&
              (engine.isLoading ||
                  engine.isGenerating ||
                  engine.isContinuing ||
                  engine.context.length < 2 ||
                  !engine.chats.containsKey(engine.currentChat));
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(streamRound, 2);
      expect(engine.context.length, 2);
      expect(
        engine.context.last['message'],
        '$truncatedHead $continuationTail',
      );
    });

    test('disabled paios.wikipedia is absent from toolRegistry.tools and Prompt.generate omits Wikipedia guidance for non-Wikipedia tools', () async {
      final engine = AIEngine();
      addTearDown(engine.dispose);

      await engine.setExtensionEnabled('paios.wikipedia', true);
      expect(
        engine.toolRegistry.tools.any((t) => t.name == 'wikipedia_summary'),
        isTrue,
      );
      expect(
        engine.toolRegistry.tools.any((t) => t.name == 'wikipedia_details'),
        isTrue,
      );

      await engine.setExtensionEnabled('paios.wikipedia', false);
      expect(
        engine.toolRegistry.tools.any((t) => t.name == 'wikipedia_summary'),
        isFalse,
      );
      expect(
        engine.toolRegistry.tools.any((t) => t.name == 'wikipedia_details'),
        isFalse,
      );

      final prompt = Prompt(ghUrl: 'https://github.com/Puzzaks/PAIOS');
      final generated = await prompt.generate(
        'Help',
        const [],
        const {'version': 'nano-v3'},
        tools: const [
          M3xTool(
            name: 'get_battery_status',
            app: 'paios',
            description: 'Battery',
            parameters: {'type': 'object', 'properties': {}},
          ),
        ],
      );
      expect(generated, contains('### [AVAILABLE TOOLS]'));
      expect(
        generated,
        isNot(contains('Prefer wikipedia_summary for general "What is X?" explanations')),
      );
      expect(generated, isNot(contains('wikipedia_details')));
    });

    test('shouldContinueOnDone rescues hard contraction/delimiter and mid-clause cutoffs on STOP during synthesis with cap=1', () {
      final engine = AIEngine();
      addTearDown(engine.dispose);
      engine.modelInfo = {'isNanoV4': false};

      expect(
        engine.shouldContinueOnDoneForTest(
          'STOP',
          "Right now, I can'",
          isSynthesis: true,
        ),
        isTrue,
      );
      expect(
        engine.shouldContinueOnDoneForTest(
          'STOP',
          'The temperature today is 12°C,',
          isSynthesis: true,
        ),
        isTrue,
      );
      expect(
        engine.shouldContinueOnDoneForTest(
          'STOP',
          'The forecast for',
          isSynthesis: true,
        ),
        isTrue,
      );
      expect(
        engine.shouldContinueOnDoneForTest(
          'STOP',
          "Right now, I can'",
          isSynthesis: true,
          stopCutoffCount: AIEngine.maxStopCutoffContinuations,
        ),
        isFalse,
      );
      expect(
        engine.shouldContinueOnDoneForTest(
          'STOP',
          'The concept highlights a potential risk with advanced',
          isSynthesis: true,
        ),
        isTrue,
      );
      expect(
        engine.shouldContinueOnDoneForTest(
          'STOP',
          'The concept highlights a potential risk with advanced',
          isSynthesis: true,
          stopCutoffCount: AIEngine.maxStopCutoffContinuations,
        ),
        isFalse,
      );
      expect(
        engine.shouldContinueOnDoneForTest(
          'STOP',
          'The forecast for Kyiv today is 18°C and sunny.',
          isSynthesis: true,
        ),
        isFalse,
      );
    });

    test('Nano v4 thought <ctrl42>call:... with empty responseText promotes and executes tool cleanly without leaking prompt or raw ctrl tags', () async {
      int streamRound = 0;
      String? executedQuery;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        eventsChannel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            final promptArg = _extractPromptArg(arguments);
            if (promptArg.contains('Task: Create a short')) {
              scheduleMicrotask(() {
                events.success({'status': 'Streaming', 'response': {'text': 'Paperclip Maximizer', 'reason': 'STOP'}});
                events.success({'status': 'Done', 'reason': 'STOP', 'response': {'text': 'Paperclip Maximizer', 'reason': 'STOP'}});
              });
              return;
            }
            final r = streamRound++;
            scheduleMicrotask(() {
              if (r == 0) {
                const ctrlThought =
                    'Checking Wikipedia first.\n<ctrl42>call:wikipedia_summary{query: "paperclip maximizer"}<ctrl43>';
                events.success({
                  'status': 'Streaming',
                  'thought': ctrlThought,
                  'response': {'text': '', 'reason': 'STOP'},
                });
                events.success({
                  'status': 'Done',
                  'reason': 'STOP',
                  'thought': ctrlThought,
                  'response': {'text': '', 'reason': 'STOP'},
                });
              } else {
                const answer =
                    'A paperclip maximizer is a thought experiment by Nick Bostrom about an AI optimizing paperclips.';
                events.success({
                  'status': 'Streaming',
                  'response': {'text': answer, 'reason': 'STOP'},
                });
                events.success({
                  'status': 'Done',
                  'reason': 'STOP',
                  'response': {'text': answer, 'reason': 'STOP'},
                });
              }
            });
          },
        ),
      );

      final engine = AIEngine();
      addTearDown(engine.dispose);
      engine.isAvailable = true;
      engine.isInitialized = true;
      engine.modelInfo = {'version': 'nano-v4', 'isNanoV4': true};
      final wikiTool = M3xTool(
        name: 'wikipedia_summary',
        app: 'paios',
        description: 'Search Wikipedia',
        parameters: {
          'type': 'object',
          'required': ['query'],
          'properties': {'query': {'type': 'string'}},
        },
        handler: (args) async {
          executedQuery = args['query']?.toString();
          return {
            'found': true,
            'title': 'Paperclip maximizer',
            'extract': 'A thought experiment described by Nick Bostrom.',
          };
        },
      );
      await engine.setExtensionEnabled('paios.wikipedia', true);
      engine.toolRegistry.register(wikiTool);
      engine.meshClient.registerLocalTool(wikiTool);
      engine.prompt.text = 'Explain the paperclip maximizer';

      await engine.generateStream();
      for (int i = 0;
          i < 80 &&
              (engine.isLoading ||
                  engine.isGenerating ||
                  engine.isSynthesizing ||
                  engine.context.length < 4);
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(executedQuery, 'paperclip maximizer');
      expect(streamRound, 2);
      expect(engine.prompt.text, isEmpty);
      expect(engine.lastPrompt, isEmpty);
      expect(engine.context.last['message'], contains('Nick Bostrom'));
      final geminiToolTurn = engine.context[1];
      expect(geminiToolTurn['thoughtProcess'], 'Checking Wikipedia first.');
      expect(geminiToolTurn['thoughtProcess'], isNot(contains('<ctrl')));
    });

    test('empty stream responseText="" with errorRetry=true caps at 1 retry instead of looping forever', () async {
      int streamCalls = 0;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        eventsChannel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            streamCalls++;
            scheduleMicrotask(() {
              events.success({
                'status': 'Streaming',
                'response': {'text': '', 'reason': 'STOP'},
              });
              events.success({
                'status': 'Done',
                'reason': 'STOP',
                'response': {'text': '', 'reason': 'STOP'},
              });
            });
          },
        ),
      );

      final engine = AIEngine();
      addTearDown(engine.dispose);
      engine.isAvailable = true;
      engine.isInitialized = true;
      engine.errorRetry = true;
      engine.modelInfo = {'version': 'nano-v4', 'isNanoV4': true};
      engine.prompt.text = 'Hello';

      await engine.generateStream();
      for (int i = 0; i < 60 && (engine.isLoading || engine.isGenerating || streamCalls < 2); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      await Future<void>.delayed(const Duration(milliseconds: 600));

      // Initial attempt + maxEmptyStreamRetries (1) = 2 total stream calls
      expect(streamCalls, 2);
      expect(engine.isLoading, isFalse);
      expect(engine.isGenerating, isFalse);
    });

    test('startNewChat resets draft, response, attachment, currentChat, and context when idle', () {
      final engine = AIEngine();
      addTearDown(engine.dispose);

      engine.currentChat = '12345';
      engine.context.add({'user': 'User', 'message': 'Old turn'});
      engine.contextSize = 42;
      engine.prompt.text = 'Unfinished draft';
      engine.responseText = 'Partial response';
      engine.currentThoughtChunk = 'Thought';
      engine.lastPrompt = 'Old prompt';
      engine.pendingImageBytes = Uint8List.fromList([1, 2, 3]);
      engine.pendingImageName = 'photo.jpg';
      engine.chatData.lastImagePath = '/tmp/photo.jpg';
      engine.isError = true;
      engine.status = 'Error';

      engine.startNewChat();

      expect(engine.currentChat, '0');
      expect(engine.context, isEmpty);
      expect(engine.contextSize, 0);
      expect(engine.prompt.text, isEmpty);
      expect(engine.responseText, isEmpty);
      expect(engine.currentThoughtChunk, isEmpty);
      expect(engine.lastPrompt, isEmpty);
      expect(engine.pendingImageBytes, isNull);
      expect(engine.pendingImageName, isNull);
      expect(engine.chatData.lastImagePath, isNull);
      expect(engine.isError, isFalse);
      expect(engine.status, isEmpty);
    });

    test('handleDownloadStatus sets isAvailable = true when Available=Available=0 reports available without version', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(localAiChannel, (call) async {
        if (call.method == 'getModelInfo') {
          return {
            'status': 'available',
            'available': true,
            'statusCode': 3,
            'version': null,
          };
        }
        return null;
      });

      final engine = AIEngine();
      addTearDown(engine.dispose);
      engine.isAvailable = false;
      engine.variantDownloads['stable:full'] = const PaiosVariantDownloadState(
        releaseStage: 'stable',
        preference: 'full',
        status: 'downloading',
        bytesDownloaded: 512,
        totalBytes: 1024,
      );
      engine.isDownloadingModel = true;

      await engine.handleDownloadStatus('Available=Available=0');

      expect(engine.isAvailable, isTrue);
      expect(engine.isDownloadingModel, isFalse);
      expect(engine.variantDownloads['stable:full']?.isCompleted, isTrue);
      expect(engine.downloadErrorRetryCount, 0);
    });
  });
}
