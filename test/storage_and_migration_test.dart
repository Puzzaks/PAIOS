import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geminilocal/engine.dart';
import 'package:geminilocal/parts/translator.dart';
import 'package:geminilocal/storage/chat_repository.dart';
import 'package:geminilocal/storage/file_access_service.dart';
import 'package:geminilocal/storage/migration.dart';
import 'package:geminilocal/storage/prompt_repository.dart';
import 'package:geminilocal/storage/resource_repository.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FileAccessService.nameToFilename Unicode & fallback sanitization', () {
    test('preserves ASCII, Cyrillic, and Chinese letters while falling back on symbols-only names', () {
      expect(
        FileAccessService.nameToFilename('My Custom Prompt'),
        'my_custom_prompt.md',
      );
      expect(
        FileAccessService.nameToFilename('Мій промпт'),
        'мій_промпт.md',
      );
      expect(
        FileAccessService.nameToFilename('海盗人格'),
        '海盗人格.md',
      );
      expect(
        FileAccessService.nameToFilename('???!!!'),
        'prompt.md',
      );
    });
  });

  group('Storage repositories, MigrationService, and AICore 606 detection', () {
    late Directory tempDir;
    const localAiChannel = MethodChannel('flutter_local_ai');

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      tempDir = await Directory.systemTemp.createTemp('paios_storage_migration_test_');
      Hive.init(tempDir.path);
      await Hive.openBox('paios_storage');

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(localAiChannel, (call) async => null);
    });

    tearDown(() async {
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

    test(
      'ResourceRepository.initFromHive sanitizes cached legacy Play Store URLs and persists back to Hive',
      () async {
        final box = Hive.box('paios_storage');
        final legacyResources = <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'PAIOS on Google Play',
            'type': 'link',
            'collection': 'Official',
            'value':
                'https://play.google.com/store/apps/details?id=page.puzzak.geminilocal',
            'url':
                'https://play.google.com/store/apps/details?id=page.puzzak.geminilocal&hl=en',
          },
          <String, dynamic>{
            'name': 'GitHub Repo',
            'type': 'link',
            'collection': 'Official',
            'value': 'https://github.com/Puzzaks/PAIOS',
          },
        ];
        await box.put('cached_resources_json', jsonEncode(legacyResources));

        final repo = ResourceRepository(notifyEngine: () {});
        await repo.initFromHive('');

        expect(repo.resources.length, 2);
        expect(
          repo.resources[0]['value'],
          'https://play.google.com/store/apps/details?id=page.puzzak.paios',
        );
        expect(
          repo.resources[0]['url'],
          'https://play.google.com/store/apps/details?id=page.puzzak.paios&hl=en',
        );
        expect(
          repo.resources[1]['value'],
          'https://github.com/Puzzaks/PAIOS',
        );

        final persistedRaw = box.get('cached_resources_json') as String?;
        expect(persistedRaw, isNotNull);
        expect(persistedRaw, isNot(contains('id=page.puzzak.geminilocal')));
        expect(persistedRaw, contains('id=page.puzzak.paios'));
      },
    );

    test(
      'ResourceRepository.initFromHive loads and sanitizes bundled additional_resources.json when Hive cache is absent',
      () async {
        final repo = ResourceRepository(notifyEngine: () {});
        await repo.initFromHive('');

        expect(repo.resources, isNotEmpty);
        final serialized = jsonEncode(repo.resources);
        expect(serialized, isNot(contains('id=page.puzzak.geminilocal')));
        expect(serialized, contains('id=page.puzzak.paios'));
      },
    );

    test(
      'PromptRepository.getPromptDisplayName and getPromptDisplayDescription localize built-in prompts and preserve custom user prompts',
      () async {
        final ukMap = jsonDecode(
          File('assets/translations/uk.json').readAsStringSync(),
        ) as Map<String, dynamic>;
        final enMap = jsonDecode(
          File('assets/translations/en.json').readAsStringSync(),
        ) as Map<String, dynamic>;
        final dict = Dictionary(path: 'assets/translations', url: '')
          ..locale = 'uk'
          ..dictionary = <String, dynamic>{
            'uk': ukMap,
            'en': enMap,
          };

        final repo = PromptRepository(notifyEngine: () {});
        await repo.initFromHive('');

        // Built-in prompts resolve to localized UK strings when Dictionary is provided
        expect(
          repo.getPromptDisplayName('system_default', dict),
          ukMap['prompt_default_name'],
        );
        expect(
          repo.getPromptDisplayDescription('system_default', dict),
          ukMap['prompt_default_desc'],
        );
        expect(
          repo.getPromptDisplayName('pirate', dict),
          ukMap['prompt_pirate_name'],
        );
        expect(
          repo.getPromptDisplayDescription('pirate', dict),
          ukMap['prompt_pirate_desc'],
        );

        // Falls back to bundled/default metadata when dict is null
        expect(repo.getPromptDisplayName('system_default'), isNotEmpty);
        expect(repo.getPromptDisplayDescription('system_default'), isNotEmpty);

        // Custom user prompts always return stored name & description verbatim
        repo.userPrompts['user_custom_1'] = <String, dynamic>{
          'id': 'user_custom_1',
          'name': 'My Custom Persona',
          'description': 'Custom user description',
          'content': 'Be concise.',
        };
        expect(
          repo.getPromptDisplayName('user_custom_1', dict),
          'My Custom Persona',
        );
        expect(
          repo.getPromptDisplayDescription('user_custom_1', dict),
          'Custom user description',
        );
      },
    );

    test(
      'ResourceRepository.getResourceDisplayName localizes via i18nKey, translationKey, and legacy name map with safe fallback',
      () {
        final ukMap = jsonDecode(
          File('assets/translations/uk.json').readAsStringSync(),
        ) as Map<String, dynamic>;
        final enMap = jsonDecode(
          File('assets/translations/en.json').readAsStringSync(),
        ) as Map<String, dynamic>;
        final dict = Dictionary(path: 'assets/translations', url: '')
          ..locale = 'uk'
          ..dictionary = <String, dynamic>{
            'uk': ukMap,
            'en': enMap,
          };

        final repo = ResourceRepository(notifyEngine: () {});

        // Explicit i18nKey / translationKey takes precedence
        expect(
          repo.getResourceDisplayName(
            {'name': 'GitHub Repo', 'i18nKey': 'res_git_title'},
            dict,
          ),
          ukMap['res_git_title'],
        );
        expect(
          repo.getResourceDisplayName(
            {'name': 'Website', 'translationKey': 'res_website_title'},
            dict,
          ),
          ukMap['res_website_title'],
        );

        // Legacy _resourceNameKeyMap fallback (gh_repo / in_play_store)
        expect(
          repo.getResourceDisplayName(
            {'name': "Application's GitHub repository"},
            dict,
          ),
          ukMap['gh_repo'],
        );
        expect(
          repo.getResourceDisplayName(
            {'name': "Application's Google Store page"},
            dict,
          ),
          ukMap['in_play_store'],
        );

        // Unmapped or null dictionary falls back cleanly to raw resource['name']
        expect(
          repo.getResourceDisplayName(
            {'name': 'Custom Community Guide'},
            dict,
          ),
          'Custom Community Guide',
        );
        expect(
          repo.getResourceDisplayName(
            {'name': "Application's GitHub repository", 'i18nKey': 'res_git_title'},
          ),
          "Application's GitHub repository",
        );
      },
    );

    test(
      'ChatRepository CRUD (saveChat, deleteChat, archive/unarchive & archived assistant chat persistence)',
      () async {
        int notifyCount = 0;
        final loggedEvents = <String>[];
        final chatRepo = ChatRepository(
          notifyEngine: () => notifyCount++,
          requestTitle: (_) async => 'Generated Test Title',
          logEvent: (category, type, message) async {
            loggedEvents.add('$category:$type:$message');
          },
          getDefaultPromptId: () => 'default_prompt',
        );

        final conversation = <Map<String, dynamic>>[
          <String, dynamic>{
            'user': 'User',
            'message': 'Hello local model',
            'time': '1700000000000',
          },
          <String, dynamic>{
            'user': 'Gemini',
            'message': 'Hi there!',
            'time': '1700000001000',
          },
        ];

        chatRepo.contextSize = 6;
        await chatRepo.saveChat(conversation, chatID: 'chat_101');

        expect(chatRepo.chats.containsKey('chat_101'), isTrue);
        expect(chatRepo.chats['chat_101']['name'], 'Generated Test Title');
        expect(chatRepo.chats['chat_101']['messageCount'], 2);
        expect(chatRepo.chats['chat_101']['isArchived'], isFalse);
        expect(chatRepo.chats['chat_101']['pinned'], isFalse);
        expect(chatRepo.chats['chat_101']['promptId'], 'default_prompt');
        expect(notifyCount, greaterThan(0));

        // Updating existing chat updates messageCount
        await chatRepo.saveChat(
          [
            ...conversation,
            <String, dynamic>{
              'user': 'User',
              'message': 'Follow-up question',
              'time': '1700000002000',
            },
          ],
          chatID: 'chat_101',
        );
        expect(chatRepo.chats['chat_101']['messageCount'], 3);

        // Pinned chats cannot be archived until unpinned
        chatRepo.chats['chat_101']['pinned'] = true;
        await chatRepo.archiveChat('chat_101');
        expect(chatRepo.chats['chat_101']['isArchived'], isFalse);

        chatRepo.chats['chat_101']['pinned'] = false;
        await chatRepo.archiveChat('chat_101');
        expect(chatRepo.chats['chat_101']['isArchived'], isTrue);

        await chatRepo.unarchiveChat('chat_101');
        expect(chatRepo.chats['chat_101']['isArchived'], isFalse);

        // Save/import an archived assistant chat directly and verify Hive persistence
        final archivedId = await chatRepo.importAssistantChat(
          conversation,
          isArchived: true,
          title: 'Archived Overlay Session',
          defaultAssistantAuthor: 'Gemini Nano v3',
        );
        expect(archivedId, isNotEmpty);
        expect(chatRepo.chats[archivedId]['isArchived'], isTrue);
        expect(chatRepo.chats[archivedId]['name'], 'Archived Overlay Session');
        expect(chatRepo.chats[archivedId]['messageCount'], 2);

        // Verify reload from Hive preserves both chats
        final reloadedRepo = ChatRepository(
          notifyEngine: () {},
          requestTitle: (_) async => 'Unused',
          logEvent: (_, __, ___) async {},
          getDefaultPromptId: () => 'default_prompt',
        );
        await reloadedRepo.initFromHive();
        expect(reloadedRepo.chats.containsKey('chat_101'), isTrue);
        expect(reloadedRepo.chats.containsKey(archivedId), isTrue);
        expect(reloadedRepo.chats[archivedId]['isArchived'], isTrue);
        expect(reloadedRepo.chats['chat_101']['messageCount'], 3);
        expect(reloadedRepo.chats[archivedId]['messageCount'], 2);

        // Delete chat_101 and verify removal from Hive
        await chatRepo.deleteChat('chat_101');
        expect(chatRepo.chats.containsKey('chat_101'), isFalse);

        final box = Hive.box('paios_storage');
        final persistedChats =
            jsonDecode(box.get('chats') as String) as Map<String, dynamic>;
        expect(persistedChats.containsKey('chat_101'), isFalse);
        expect(persistedChats.containsKey(archivedId), isTrue);
      },
    );

    test(
      'MigrationService performs one-shot SharedPreferences -> Hive migration and clears legacy preferences',
      () async {
        final box = Hive.box('paios_storage');
        await box.clear();

        SharedPreferences.setMockInitialValues(<String, Object>{
          'language': 'uk',
          'tokens': 512,
          'temperature': 0.65,
          'shareLocale': true,
          'tags': <String>['alpha', 'beta'],
        });

        await MigrationService.initiateMigration();

        expect(box.get(MigrationService.migrationFlag), isTrue);
        expect(box.get('language'), 'uk');
        expect(box.get('tokens'), 512);
        expect(box.get('temperature'), 0.65);
        expect(box.get('shareLocale'), isTrue);
        expect(box.get('tags'), equals(<String>['alpha', 'beta']));

        // Legacy SharedPreferences should be cleared after successful verification
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getKeys(), isEmpty);

        // Subsequent migration calls are a no-op when migration_completed == true
        await prefs.setString('language', 'de');
        await MigrationService.initiateMigration();
        expect(box.get('language'), 'uk');
      },
    );

    test(
      'AIEngine.isAiCoreFeatureNotFoundError detects 606 and FEATURE_NOT_FOUND across error fields and ignores 601/normal states',
      () {
        final engine = AIEngine();
        addTearDown(engine.dispose);

        // Default clean state -> false
        expect(engine.isAiCoreFeatureNotFoundError, isFalse);

        // Error 601 (BUSY / Preparation error) -> false
        engine.lastAiCoreError = 'AiCoreException: ErrorCode 601';
        engine.unsupportedReason = 'Error 601 while preparing session';
        engine.modelInfo = <String, dynamic>{
          'status': 'unavailable',
          'statusCode': 601,
          'error': 'ErrorCode 601',
        };
        expect(engine.isAiCoreFeatureNotFoundError, isFalse);

        // lastAiCoreError with 606 -> true
        engine.lastAiCoreError =
            'com.google.android.apps.motive.AiCoreException: ErrorCode 606';
        expect(engine.isAiCoreFeatureNotFoundError, isTrue);
        engine.lastAiCoreError = '';
        expect(engine.isAiCoreFeatureNotFoundError, isFalse);

        // unsupportedReason with FEATURE_NOT_FOUND -> true
        engine.unsupportedReason = 'Preparation failed: FEATURE_NOT_FOUND';
        expect(engine.isAiCoreFeatureNotFoundError, isTrue);
        engine.unsupportedReason = '';
        expect(engine.isAiCoreFeatureNotFoundError, isFalse);

        // modelInfo with 606 -> true
        engine.modelInfo = <String, dynamic>{
          'status': 'unavailable',
          'error': 'AICore returned status 606',
        };
        expect(engine.isAiCoreFeatureNotFoundError, isTrue);

        // modelInfo with feature_not_found -> true
        engine.modelInfo = <String, dynamic>{
          'status': 'unavailable',
          'unsupportedReason': 'feature_not_found in AICore catalog',
        };
        expect(engine.isAiCoreFeatureNotFoundError, isTrue);
      },
    );
  });
}
