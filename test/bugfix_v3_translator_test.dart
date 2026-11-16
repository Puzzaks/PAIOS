import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geminilocal/engine.dart';
import 'package:geminilocal/parts/prompt.dart';
import 'package:geminilocal/parts/translator.dart';
import 'package:geminilocal/storage/chat_repository.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:m3x_mesh/m3x_mesh.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Prompt.generateContinuation compactness & tail bounding', () {
    test('bounds long partialText to tail while keeping exact ending', () async {
      final prompt = Prompt(ghUrl: 'https://github.com/Puzzaks/PAIOS');
      final longPersona = List.generate(100, (i) => 'persona_$i').join(' ');
      final longQuestion = List.generate(80, (i) => 'question_$i').join(' ');
      final longPartial =
          '${List.generate(250, (i) => 'token$i').join(' ')} I prioritize your';

      final continuation = await prompt.generateContinuation(
        longPersona,
        {'version': 'nano-v3'},
        longPartial,
        longQuestion,
        addTime: true,
        shareLocale: true,
        currentLocale: 'en',
      );

      expect(continuation.length, lessThan(1200));
      expect(continuation, contains('I prioritize your'));
      expect(continuation, isNot(contains('token0 ')));
      expect(
        continuation,
        contains('Continue seamlessly from the exact end without repeating.'),
      );
      expect(continuation, contains('Language: en.'));
    });

    test('includes JSON completion guidance for incomplete tool draft', () async {
      final prompt = Prompt(ghUrl: 'https://github.com/Puzzaks/PAIOS');
      final continuation = await prompt.generateContinuation(
        'You are PAIOS.',
        {'version': 'nano-v3'},
        '{"tool": "get_battery_status", "app": "pa',
        'Check battery',
      );

      expect(continuation, contains('{"tool": "get_battery_status", "app": "pa'));
      expect(continuation, contains('remaining valid JSON characters'));
    });
  });

  group('Dictionary mojibake detection, repair & Hive self-healing', () {
    late Directory tempDir;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      tempDir = await Directory.systemTemp.createTemp('paios_dict_mojibake_');
      Hive.init(tempDir.path);
      await Hive.openBox('paios_storage');
    });

    tearDown(() async {
      if (Hive.isBoxOpen('paios_storage')) {
        await Hive.box('paios_storage').close();
      }
      await Hive.deleteFromDisk();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('detects and repairs CP1251/Latin-1 mojibake without false positives on valid Ukrainian', () {
      expect(Dictionary.hasMojibake('Continuing responseвЂ¦'), isTrue);
      expect(Dictionary.hasMojibake('Item вЂў one вЂ” two вЂ™s'), isTrue);
      expect(Dictionary.hasMojibake('Continuing responseâ€¦'), isTrue);
      expect(Dictionary.hasMojibake('РџСЂРёРІС–С‚'), isTrue);

      expect(Dictionary.repairMojibake('Continuing responseвЂ¦'), 'Continuing response…');
      expect(Dictionary.repairMojibake('РџСЂРёРІС–С‚'), 'Привіт');

      // Valid Ukrainian words starting with Р / С + і / е must NOT trigger mojibake
      expect(Dictionary.hasMojibake('Continuing response…'), isFalse);
      expect(Dictionary.hasMojibake('Рік тому'), isFalse);
      expect(Dictionary.hasMojibake('Сім днів'), isFalse);
      expect(Dictionary.hasMojibake('Рецепт успіху'), isFalse);
      expect(Dictionary.hasMojibake('Система працює'), isFalse);
    });

    test('heals poisoned Hive cache on setup() using clean bundled asset', () async {
      final box = Hive.box('paios_storage');
      await box.put(
        'cached_dict_en',
        jsonEncode({
          'model_continuing': 'Continuing responseвЂ¦',
          'remote_only_key': 'Bullet вЂў point',
        }),
      );

      final dict = Dictionary(
        path: 'assets/translations',
        url: '',
      );
      await dict.setup();
      dict.locale = 'en';

      expect(dict.value('model_continuing'), 'Continuing response…');
      expect(dict.value('remote_only_key'), 'Bullet • point');

      // Hive cache itself was rewritten clean
      final healedCache =
          jsonDecode(box.get('cached_dict_en') as String) as Map<String, dynamic>;
      expect(healedCache['model_continuing'], 'Continuing response…');
      expect(healedCache['remote_only_key'], 'Bullet • point');
    });

    test('rejects mojibaked remote GitHub JSON over clean bundled baseline', () async {
      final box = Hive.box('paios_storage');
      final dict = Dictionary(
        path: 'assets/translations',
        url: 'https://raw.example.invalid',
      );
      dict.customHttpClient = MockClient((request) async {
        if (request.url.path.endsWith('/languages.json')) {
          return http.Response.bytes(
            utf8.encode(jsonEncode([
              {'id': 'en', 'name': 'English'},
            ])),
            200,
          );
        }
        if (request.url.path.endsWith('/en.json')) {
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              'model_continuing': 'Continuing responseвЂ¦',
              'new_remote_entry': 'Dash вЂ” test',
            })),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      await dict.setup();
      await dict.refreshFromRemoteForTest(box: box);
      dict.locale = 'en';

      expect(dict.value('model_continuing'), 'Continuing response…');
      expect(dict.value('new_remote_entry'), 'Dash — test');

      final stored =
          jsonDecode(box.get('cached_dict_en') as String) as Map<String, dynamic>;
      expect(stored['model_continuing'], 'Continuing response…');
      expect(stored['new_remote_entry'], 'Dash — test');
    });
  });

  group('AIEngine v3 continuation & assistant open navigation callback', () {
    late Directory tempDir;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      tempDir = await Directory.systemTemp.createTemp('paios_engine_bugfix_');
      Hive.init(tempDir.path);
      await Hive.openBox('paios_storage');

      const localAiChannel = MethodChannel('flutter_local_ai');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(localAiChannel, (call) async => null);
    });

    tearDown(() async {
      const localAiChannel = MethodChannel('flutter_local_ai');
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

    test('shouldContinueOnDone handles v3 reasons, stall guard, prose cap=3, code cap=10, empty-args abort, and null-reason heuristic', () {
      final engine = AIEngine();
      addTearDown(engine.dispose);
      engine.modelInfo = {'isNanoV4': false};
      engine.toolRegistry.register(
        const M3xTool(
          name: 'wikipedia_summary',
          app: 'paios',
          description: 'Search Wikipedia',
          parameters: {
            'type': 'object',
            'required': ['query'],
            'properties': {
              'query': {'type': 'string'},
            },
          },
        ),
      );

      expect(AIEngine.maxProseContinuations, 3);
      expect(engine.shouldContinueOnDoneForTest('1', 'Partial'), isTrue);
      expect(engine.shouldContinueOnDoneForTest('-100', 'Partial'), isTrue);
      expect(engine.shouldContinueOnDoneForTest('MAX_TOKENS', 'Partial'), isTrue);
      expect(engine.shouldContinueOnDoneForTest('LIMIT', 'Partial'), isTrue);
      expect(engine.shouldContinueOnDoneForTest('OTHER', 'Partial'), isTrue);
      expect(engine.shouldContinueOnDoneForTest('0', 'I prioritize your'), isFalse);
      expect(engine.shouldContinueOnDoneForTest('STOP', 'I prioritize your'), isFalse);

      // Runaway prose cap = 3 (count 2 passes, count 3 stops)
      expect(
        engine.shouldContinueOnDoneForTest('1', 'Partial prose', continuationCount: 2),
        isTrue,
      );
      expect(
        engine.shouldContinueOnDoneForTest('1', 'Partial prose', continuationCount: 3),
        isFalse,
      );

      // Open code block allows up to 10 continuations (count 9 passes, count 10 stops)
      expect(
        engine.shouldContinueOnDoneForTest('1', '```dart\nPartial', continuationCount: 9),
        isTrue,
      );
      expect(
        engine.shouldContinueOnDoneForTest('1', '```dart\nPartial', continuationCount: 10),
        isFalse,
      );

      // Empty arguments: {} on a tool requiring arguments aborts tool JSON continuation
      expect(
        engine.shouldContinueOnDoneForTest(
          'MAX_TOKENS',
          '{"tool": "wikipedia_summary", "arguments": {}',
        ),
        isFalse,
      );
      expect(
        engine.shouldContinueOnDoneForTest(
          'MAX_TOKENS',
          '{"tool": "wikipedia_summary", "args": {"query": "Alpha',
        ),
        isTrue,
      );

      // Stall guard & char limit
      expect(
        engine.shouldContinueOnDoneForTest(
          '1',
          'Partial',
          lastRoundAddedNonWs: 0,
        ),
        isFalse,
      );
      expect(
        engine.shouldContinueOnDoneForTest('1', 'a' * AIEngine.maxContinuationChars),
        isFalse,
      );

      // Null-reason mid-clause safety retry on v3 only
      expect(
        engine.shouldContinueOnDoneForTest(null, 'I prioritize your'),
        isTrue,
      );
      expect(
        engine.shouldContinueOnDoneForTest('null', 'older,'),
        isTrue,
      );
      expect(
        engine.shouldContinueOnDoneForTest('', "Here'"),
        isTrue,
      );
      expect(
        engine.shouldContinueOnDoneForTest(null, 'Complete sentence.'),
        isFalse,
      );
      expect(
        engine.shouldContinueOnDoneForTest(
          null,
          'I prioritize your',
          nullReasonCount: AIEngine.maxNullReasonContinuations,
        ),
        isFalse,
      );

      engine.modelInfo = {'isNanoV4': true};
      expect(
        engine.shouldContinueOnDoneForTest(null, 'I prioritize your'),
        isFalse,
      );
    });

    test('triggers onOpenAssistantChat on unarchived: true (live & cold-start pending flush)', () async {
      final engine = AIEngine();
      addTearDown(engine.dispose);

      var openCount = 0;
      engine.onOpenAssistantChat = () => openCount++;

      // Cold start before appStarted == true queues navigation until flush
      await engine.handleIncomingAssistantChatForTest({
        'messages': jsonEncode([
          {'user': 'User', 'message': 'Hi', 'time': '1'},
          {'user': 'Gemini', 'message': 'Hello!', 'time': '2'},
        ]),
        'unarchived': true,
      });

      expect(engine.currentChat, isNotEmpty);
      expect(openCount, 0);
      expect(engine.hasPendingOpenAssistantChat, isTrue);

      engine.appStarted = true;
      engine.flushPendingAssistantChatNavigation();
      expect(openCount, 1);
      expect(engine.hasPendingOpenAssistantChat, isFalse);

      // Archived chat import must NOT trigger navigation
      await engine.handleIncomingAssistantChatForTest({
        'messages': jsonEncode([
          {'user': 'User', 'message': 'Archived', 'time': '3'},
        ]),
        'unarchived': false,
      });
      expect(openCount, 1);

      // Live unarchived chat triggers immediately
      await engine.handleIncomingAssistantChatForTest({
        'messages': jsonEncode([
          {'user': 'User', 'message': 'Expand me', 'time': '4'},
        ]),
        'unarchived': true,
      });
      expect(openCount, 2);
    });

    test('formatNanoAuthor formats Gemini Nano versions and fallbacks accurately', () {
      expect(AIEngine.formatNanoAuthor(null), 'Gemini Nano');
      expect(AIEngine.formatNanoAuthor({}), 'Gemini Nano');
      expect(AIEngine.formatNanoAuthor({'version': 'Unknown'}), 'Gemini Nano');
      expect(
        AIEngine.formatNanoAuthor({
          'status': 'Error',
          'version': 'TimeoutException after 0:00:04',
        }),
        'Gemini Nano',
      );
      expect(AIEngine.formatNanoAuthor({'version': 'nano-v3'}), 'Gemini Nano v3');
      expect(AIEngine.formatNanoAuthor({'baseModelName': 'Gemini Nano 3'}), 'Gemini Nano v3');
      expect(AIEngine.formatNanoAuthor({'version': 'nano-v4'}), 'Gemini Nano v4');
      expect(AIEngine.formatNanoAuthor({'baseModelName': 'AICore Nano 4'}), 'Gemini Nano v4');
      expect(AIEngine.formatNanoAuthor({'isNanoV4': true, 'baseModelName': 'Unknown'}), 'Gemini Nano v4');
      expect(AIEngine.formatNanoAuthor({'version': 'nano-v2'}), 'Gemini Nano v2');
      expect(AIEngine.formatNanoAuthor({'baseModelName': 'gemini-nano-1.5'}), 'Gemini Nano v1.5');

      final engine = AIEngine();
      addTearDown(engine.dispose);
      engine.modelInfo = {'baseModelName': 'nano-v3', 'isNanoV4': false};
      expect(engine.assistantAuthorLabel, 'Gemini Nano v3');
      engine.modelInfo = {'isNanoV4': true};
      expect(engine.assistantAuthorLabel, 'Gemini Nano v4');
    });

    test('modelVariants and availableModelVariants map, sort, and filter variants cleanly', () {
      final engine = AIEngine();
      addTearDown(engine.dispose);

      expect(engine.modelVariants, isEmpty);
      expect(engine.availableModelVariants, isEmpty);

      engine.modelInfo = {
        'releaseStage': 'preview',
        'preference': 'full',
        'status': 'available',
        'statusCode': 3,
        'available': true,
        'baseModelName': 'nano-v4',
        'modelVariants': [
          {
            'releaseStage': 'stable',
            'preference': 'fast',
            'statusCode': 0,
            'status': 'unavailable',
            'available': false,
            'baseModelName': null,
            'isActive': false,
          },
          {
            'releaseStage': 'preview',
            'preference': 'fast',
            'statusCode': 1,
            'status': 'downloadable',
            'available': false,
            'baseModelName': null,
            'isActive': false,
          },
          {
            'releaseStage': 'stable',
            'preference': 'full',
            'statusCode': 3,
            'status': 'available',
            'available': true,
            'baseModelName': 'nano-v3',
            'isActive': false,
          },
          {
            'releaseStage': 'preview',
            'preference': 'full',
            'statusCode': 3,
            'status': 'available',
            'available': true,
            'baseModelName': 'nano-v4',
            'isActive': true,
          },
        ],
      };

      expect(engine.modelVariants.length, 4);
      expect(engine.modelVariants[0].releaseStage, 'stable');
      expect(engine.modelVariants[0].preference, 'full');
      expect(engine.modelVariants[0].isActive, isFalse);
      expect(engine.modelVariants[1].releaseStage, 'stable');
      expect(engine.modelVariants[1].preference, 'fast');
      expect(engine.modelVariants[1].status, 'unavailable');
      expect(engine.modelVariants[2].releaseStage, 'preview');
      expect(engine.modelVariants[2].preference, 'full');
      expect(engine.modelVariants[2].isActive, isTrue);
      expect(engine.modelVariants[3].releaseStage, 'preview');
      expect(engine.modelVariants[3].preference, 'fast');
      expect(engine.modelVariants[3].isDownloadable, isTrue);

      final switchable = engine.availableModelVariants;
      expect(switchable.length, 3);
      expect(switchable[0]['releaseStage'], 'stable');
      expect(switchable[0]['preference'], 'full');
      expect(switchable[0]['authorLabel'], 'Gemini Nano v3');
      expect(switchable[1]['releaseStage'], 'preview');
      expect(switchable[1]['preference'], 'full');
      expect(switchable[1]['authorLabel'], 'Gemini Nano v4');
      expect(switchable[1]['isActive'], isTrue);
      expect(switchable[2]['releaseStage'], 'preview');
      expect(switchable[2]['preference'], 'fast');
      expect(switchable[2]['isDownloadable'], isTrue);

      // Legacy fallback without modelVariants array
      engine.modelInfo = {
        'releaseStage': 'stable',
        'preference': 'full',
        'status': 'available',
        'statusCode': 3,
        'available': true,
        'stableFastAvailable': true,
        'previewFullAvailable': false,
        'previewFastAvailable': false,
      };
      expect(engine.modelVariants.length, 4);
      expect(engine.availableModelVariants.length, 2);
    });

    test('internalModelName, selectorModelVariants deduplication, and active-inference switch lock', () async {
      const v3 = PaiosModelVariant(
        releaseStage: 'stable',
        preference: 'full',
        statusCode: 3,
        status: 'available',
        available: true,
        baseModelName: 'nano-v3',
      );
      const v4Fast = PaiosModelVariant(
        releaseStage: 'preview',
        preference: 'fast',
        statusCode: 3,
        status: 'available',
        available: true,
        baseModelName: 'nano-v4-fast',
      );
      const unknownFallback = PaiosModelVariant(
        releaseStage: 'preview',
        preference: 'fast',
        statusCode: 1,
        status: 'downloadable',
        available: false,
        baseModelName: null,
      );
      expect(v3.internalModelName, 'gemini-nano-v3');
      expect(v4Fast.internalModelName, 'gemini-nano-v4-fast');
      expect(unknownFallback.internalModelName, 'preview-fast');

      final engine = AIEngine();
      addTearDown(engine.dispose);
      engine.modelInfo = {
        'releaseStage': 'stable',
        'preference': 'fast',
        'status': 'available',
        'statusCode': 3,
        'available': true,
        'baseModelName': 'nano-v3',
        'modelVariants': [
          {
            'releaseStage': 'preview',
            'preference': 'fast',
            'statusCode': 3,
            'status': 'available',
            'available': true,
            'baseModelName': 'nano-v4-fast',
            'isActive': false,
          },
          {
            'releaseStage': 'stable',
            'preference': 'full',
            'statusCode': 3,
            'status': 'available',
            'available': true,
            'baseModelName': 'nano-v3',
            'isActive': false,
          },
          {
            'releaseStage': 'preview',
            'preference': 'full',
            'statusCode': 1,
            'status': 'downloadable',
            'available': false,
            'baseModelName': 'nano-v4-full',
            'isActive': false,
          },
          {
            'releaseStage': 'stable',
            'preference': 'fast',
            'statusCode': 3,
            'status': 'available',
            'available': true,
            'baseModelName': 'nano-v3',
            'isActive': true,
          },
        ],
      };

      final selector = engine.selectorModelVariants;
      expect(selector.length, 3);
      expect(selector.map((v) => v.internalModelName).toList(), [
        'gemini-nano-v3',
        'gemini-nano-v4-full',
        'gemini-nano-v4-fast',
      ]);
      // Deduplicated stable nano-v3 inherits active status from stable/fast
      expect(selector[0].isActive, isTrue);
      expect(selector[1].isDownloadable, isTrue);
      expect(selector[2].isActive, isFalse);

      // setModelConfiguration ignores mid-generation switches when isLoading == true
      engine.config.modelReleaseStage = 'stable';
      engine.config.modelPreference = 'full';
      engine.isLoading = true;
      await engine.setModelConfiguration(
        releaseStage: 'preview',
        preference: 'fast',
      );
      expect(engine.modelReleaseStage, 'stable');
      expect(engine.modelPreference, 'full');
      expect(engine.isSwitchingModelConfig, isFalse);
    });

    test('author, thoughtProcess, and streamingMessageTime persist across save/load and importAssistantChat', () async {
      final engine = AIEngine();
      addTearDown(engine.dispose);
      engine.modelInfo = {'baseModelName': 'nano-v4', 'isNanoV4': true};

      final userTs = DateTime.fromMillisecondsSinceEpoch(1700000001000);
      final aiTs = DateTime.fromMillisecondsSinceEpoch(1700000005555);
      engine.streamingUserMessageTime = userTs;
      engine.streamingMessageTime = aiTs;
      engine.lastPrompt = 'Explain quantum tunneling';
      engine.responseText = 'Particles can cross barriers.';
      engine.currentThoughtChunk = 'Recall wave equation';

      await engine.addToContext();

      expect(engine.streamingMessageTime, isNull);
      expect(engine.streamingUserMessageTime, isNull);
      expect(engine.context.length, 2);
      expect(engine.context[0]['time'], '1700000001000');
      expect(engine.context[0].containsKey('author'), isFalse);
      expect(engine.context[1]['time'], '1700000005555');
      expect(engine.context[1]['author'], 'Gemini Nano v4');
      expect(engine.context[1]['thoughtProcess'], 'Recall wave equation');

      // Update image description on user message and ensure Gemini metadata remains intact
      final chatId = engine.currentChat;
      await engine.chatData.updateMessageImageDescription(
        chatId,
        'Diagram of potential barrier',
        messageIndex: 0,
      );

      // Reload from Hive into a fresh ChatRepository
      final reloaded = ChatRepository(
        notifyEngine: () {},
        requestTitle: (_) async => 'Title',
        logEvent: (_, __, ___) async {},
        getDefaultPromptId: () => 'system_default',
      );
      await reloaded.initFromHive();
      final decodedHistory = jsonDecode(reloaded.chats[chatId]['history'] as String) as List;
      expect(decodedHistory[0]['imageDescription'], 'Diagram of potential barrier');
      expect(decodedHistory[1]['author'], 'Gemini Nano v4');
      expect(decodedHistory[1]['time'], '1700000005555');
      expect(decodedHistory[1]['thoughtProcess'], 'Recall wave equation');

      // importAssistantChat backfills missing author while preserving explicit author and time
      final importedId = await engine.chatData.importAssistantChat(
        [
          {'user': 'User', 'message': 'Hi', 'time': '111'},
          {'user': 'Gemini', 'message': 'Hello without author', 'time': '222'},
          {
            'user': 'Gemini',
            'author': 'Gemini Nano v3',
            'message': 'Explicit author',
            'time': '333',
            'thoughtProcess': 'Kept thought',
          },
        ],
        title: 'Imported Session',
        defaultAssistantAuthor: 'Gemini Nano v4',
      );
      final importedHistory =
          jsonDecode(engine.chats[importedId]['history'] as String) as List;
      expect(importedHistory[0]['time'], '111');
      expect(importedHistory[1]['author'], 'Gemini Nano v4');
      expect(importedHistory[1]['time'], '222');
      expect(importedHistory[2]['author'], 'Gemini Nano v3');
      expect(importedHistory[2]['time'], '333');
      expect(importedHistory[2]['thoughtProcess'], 'Kept thought');
    });

    test('stripLeadingEllipsis and continuation join normalize ellipsis seams cleanly', () async {
      expect(AIEngine.stripLeadingEllipsis('...presented'), 'presented');
      expect(AIEngine.stripLeadingEllipsis('…to'), 'to');
      expect(AIEngine.stripLeadingEllipsis('  ...consequences.'), 'consequences.');

      const localAiChannel = MethodChannel('flutter_local_ai');
      const eventsChannel = EventChannel('flutter_local_ai_events');

      final pairs = <({String first, String second, String expected})>[
        (first: 'often', second: '...presented', expected: 'often presented'),
        (first: 'lead', second: '...to', expected: 'lead to'),
        (
          first: 'considerations.',
          second: '...consequences.',
          expected: 'considerations. consequences.',
        ),
      ];

      for (final pair in pairs) {
        int callIndex = 0;
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
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockStreamHandler(
          eventsChannel,
          MockStreamHandler.inline(
            onListen: (arguments, events) {
              final round = callIndex++;
              scheduleMicrotask(() {
                if (round == 0) {
                  events.success({
                    'status': 'Streaming',
                    'response': {'text': pair.first, 'reason': 'MAX_TOKENS'},
                  });
                  events.success({
                    'status': 'Done',
                    'reason': 'MAX_TOKENS',
                    'response': {'text': pair.first, 'reason': 'MAX_TOKENS'},
                  });
                } else {
                  events.success({
                    'status': 'Streaming',
                    'response': {'text': pair.second, 'reason': 'STOP'},
                  });
                  events.success({
                    'status': 'Done',
                    'reason': 'STOP',
                    'response': {'text': pair.second, 'reason': 'STOP'},
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
        engine.modelInfo = {'status': 'available', 'available': true, 'statusCode': 3, 'version': 'nano-v3'};
        engine.prompt.text = 'Explain ${pair.first}';
        engine.lastPrompt = 'Explain ${pair.first}';

        await engine.generateStream();
        for (int w = 0;
            w < 80 &&
                (engine.isLoading ||
                    engine.isGenerating ||
                    engine.isContinuing ||
                    engine.context.length < 2 ||
                    engine.lastPrompt.isNotEmpty ||
                    !engine.chats.containsKey(engine.currentChat));
            w++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(engine.context.length, 2);
        expect(engine.context.last['message'], pair.expected);
        expect(engine.responseText, isEmpty);
        expect(engine.lastPrompt, isEmpty);
      }

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(eventsChannel, null);
    });

    test('failed tool call fallback clears lastPrompt & responseText without duplicate bubbles, and all 5 locales include new keys', () async {
      for (final code in ['en', 'uk', 'de', 'tr', 'zh']) {
        final raw = File('assets/translations/$code.json').readAsStringSync();
        expect(raw.contains('\u0432\u0402'), isFalse);
        expect(raw.contains('\uFFFD'), isFalse);
        final map = jsonDecode(raw) as Map<String, dynamic>;
        expect(map['tool_fallback_infra_error'], contains('{app}'));
        expect(map['tool_fallback_infra_error'], contains('{error}'));
        expect(map['tool_fallback_partial_error'], contains('{tool}'));
        expect(map['tool_fallback_invalid_request'], isA<String>());
        expect(map['onboarding_download_required'], isA<String>());
        expect(map['model_download_speed_remaining'], contains('{speed}'));
        expect(map['model_download_speed_remaining'], contains('{remaining}'));
      }

      const localAiChannel = MethodChannel('flutter_local_ai');
      const eventsChannel = EventChannel('flutter_local_ai_events');
      int streamRound = 0;

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
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        eventsChannel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            final round = streamRound++;
            scheduleMicrotask(() {
              if (round == 0) {
                const toolJson = '{"tool": "disabled_ext_tool", "app": "ptk", "arguments": {}}';
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
                // Echoed malformed/incomplete tool wrapper during synthesis triggers fallback commit
                const badSynth = '{"tool": "disabled_ext_tool", "description": "retry", "arguments":';
                events.success({
                  'status': 'Streaming',
                  'response': {'text': badSynth, 'reason': 'STOP'},
                });
                events.success({
                  'status': 'Done',
                  'reason': 'STOP',
                  'response': {'text': badSynth, 'reason': 'STOP'},
                });
              }
            });
          },
        ),
      );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockStreamHandler(eventsChannel, null);
      });

      final engine = AIEngine();
      addTearDown(engine.dispose);
      engine.isAvailable = true;
      engine.isInitialized = true;
      engine.modelInfo = {'status': 'available', 'available': true, 'statusCode': 3, 'version': 'nano-v3'};
      engine.toolRegistry.register(
        const M3xTool(
          name: 'disabled_ext_tool',
          app: 'ptk',
          packageName: 'page.puzzak.ptk',
          description: 'Test disabled extension tool',
          parameters: {'type': 'object', 'properties': {}},
        ),
      );
      engine.setExtensionEnabled('page.puzzak.ptk', false);
      engine.prompt.text = 'Check PTK status';
      engine.lastPrompt = 'Check PTK status';

      await engine.generateStream();
      for (int w = 0;
          w < 80 &&
              (engine.isLoading ||
                  engine.isGenerating ||
                  engine.isSynthesizing ||
                  engine.context.length < 4);
          w++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }

      // Exactly 1 User message, 1 tool Gemini message, 1 System error, 1 fallback Gemini synthesis
      final userMsgs = engine.context.where((m) => m['user'] == 'User').toList();
      final geminiMsgs = engine.context.where((m) => m['user'] == 'Gemini').toList();
      final systemMsgs = engine.context.where((m) => m['user'] == 'System').toList();
      expect(userMsgs.length, 1);
      expect(userMsgs.single['message'], 'Check PTK status');
      expect(systemMsgs.length, 1);
      expect(geminiMsgs.length, 2);
      expect(engine.lastPrompt, isEmpty);
      expect(engine.responseText, isEmpty);
    });
  });
}
