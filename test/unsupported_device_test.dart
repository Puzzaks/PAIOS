import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geminilocal/engine.dart';
import 'package:geminilocal/services/doc_service.dart';
import 'package:geminilocal/storage/analytics_service.dart';
import 'package:geminilocal/storage/app_config.dart';
import 'package:geminilocal/storage/chat_repository.dart';
import 'package:geminilocal/storage/intro_slide_repository.dart';
import 'package:geminilocal/storage/prompt_repository.dart';
import 'package:geminilocal/storage/resource_repository.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AIEngine unsupported device / AICore availability detection', () {
    test('defaults to not known unavailable when modelInfo and logs are empty', () {
      final engine = AIEngine();
      expect(engine.isAiCoreKnownUnavailable, isFalse);
      expect(engine.isAiCoreAvailable, isTrue);
    });

    test('returns false when modelInfo has available: false', () {
      final engine = AIEngine();
      engine.modelInfo = {'available': false};
      expect(engine.isAiCoreKnownUnavailable, isTrue);
      expect(engine.isAiCoreAvailable, isFalse);
    });

    test('handles lowercase and mixed-case status "unavailable"', () {
      final engine = AIEngine();
      engine.modelInfo = {'status': 'unavailable'};
      expect(engine.isAiCoreKnownUnavailable, isTrue);
      expect(engine.isAiCoreAvailable, isFalse);

      engine.modelInfo = {'status': 'Unavailable'};
      expect(engine.isAiCoreKnownUnavailable, isTrue);
      expect(engine.isAiCoreAvailable, isFalse);
    });

    test('returns false when modelInfo has statusCode: 0', () {
      final engine = AIEngine();
      engine.modelInfo = {'statusCode': 0};
      expect(engine.isAiCoreKnownUnavailable, isTrue);
      expect(engine.isAiCoreAvailable, isFalse);
    });

    test('returns true when modelInfo reports available model', () {
      final engine = AIEngine();
      engine.modelInfo = {
        'available': true,
        'status': 'available',
        'statusCode': 3,
      };
      expect(engine.isAiCoreKnownUnavailable, isFalse);
      expect(engine.isAiCoreAvailable, isTrue);
    });

    test('returns false when modelDownloadLog last entry is AICore or Unavailable error', () {
      final engine = AIEngine();
      engine.modelDownloadLog = [
        {'status': 'Error', 'info': 'AICore', 'value': 'Unavailable'},
      ];
      expect(engine.isAiCoreKnownUnavailable, isTrue);
      expect(engine.isAiCoreAvailable, isFalse);

      engine.modelDownloadLog = [
        {'status': 'Error', 'info': 'AICore', 'value': 'NotInstalled'},
      ];
      expect(engine.isAiCoreKnownUnavailable, isTrue);
      expect(engine.isAiCoreAvailable, isFalse);

      engine.modelDownloadLog = [
        {'status': 'Error', 'info': 'Other', 'value': 'Unavailable'},
      ];
      expect(engine.isAiCoreKnownUnavailable, isTrue);
      expect(engine.isAiCoreAvailable, isFalse);
    });

    test('ignores non-AICore or older resolved download logs', () {
      final engine = AIEngine();
      engine.modelDownloadLog = [
        {'status': 'Error', 'info': 'AICore', 'value': 'Unavailable'},
        {'status': 'Available', 'info': 'Available', 'value': '0'},
      ];
      expect(engine.isAiCoreKnownUnavailable, isFalse);
      expect(engine.isAiCoreAvailable, isTrue);
    });

    test('generateStream fails fast without throwing when AICore is unavailable', () async {
      final engine = AIEngine();
      engine.modelInfo = {
        'available': false,
        'status': 'unavailable',
        'statusCode': 0,
      };
      engine.prompt.text = 'Hello Gemini Nano';

      var notified = 0;
      engine.addListener(() => notified++);

      await engine.generateStream();

      expect(engine.isLoading, isFalse);
      expect(engine.isGenerating, isFalse);
      expect(engine.isError, isTrue);
      expect(engine.status, isNotEmpty);
      expect(notified, greaterThanOrEqualTo(1));
    });
  });

  group('1-DOWNLOAD_ERROR bounded retry & toast throttling', () {
    const toastChannel = MethodChannel('PonnamKarthik/fluttertoast');
    const downloadChannel = MethodChannel('download_channel');
    const localAiChannel = MethodChannel('flutter_local_ai');

    late int toastCallCount;
    late int downloadListenCount;

    setUp(() {
      toastCallCount = 0;
      downloadListenCount = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(toastChannel, (call) async {
        if (call.method == 'showToast') {
          toastCallCount++;
          return true;
        }
        return null;
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(downloadChannel, (call) async {
        if (call.method == 'listen') {
          downloadListenCount++;
        }
        return null;
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(localAiChannel, (call) async {
        if (call.method == 'getModelInfo') {
          return <String, dynamic>{
            'available': false,
            'status': 'unavailable',
            'statusCode': 0,
          };
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(toastChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(downloadChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(localAiChannel, null);
    });

    test('caps 1-DOWNLOAD_ERROR automatic retries at maxDownloadErrorRetries', () async {
      final engine = AIEngine();
      addTearDown(engine.dispose);
      engine.config.firstLaunch = false;

      // Simulate 5 consecutive 1-DOWNLOAD_ERROR events
      for (int i = 0; i < 5; i++) {
        await engine.handleDownloadStatus('Error=Download=1-DOWNLOAD_ERROR');
      }

      expect(engine.downloadErrorRetryCount, AIEngine.maxDownloadErrorRetries);
      expect(downloadListenCount, AIEngine.maxDownloadErrorRetries);
      expect(engine.isAvailable, isFalse);
      expect(engine.modelDownloadLog, isNotEmpty);
      expect(engine.modelDownloadLog.last['value'], '1-DOWNLOAD_ERROR');
      // Toast should fire at most once once retries are exhausted
      expect(toastCallCount, 1);

      // Explicit user re-check resets retry counter
      await engine.checkEngine();
      expect(engine.downloadErrorRetryCount, 0);
    });

    test('does not spam toasts across repeated non-AICore errors', () async {
      final engine = AIEngine();
      addTearDown(engine.dispose);
      engine.config.firstLaunch = false;

      await engine.handleDownloadStatus('Error=Other=TransientFailure1');
      await engine.handleDownloadStatus('Error=Other=TransientFailure2');
      await engine.handleDownloadStatus('Error=Other=TransientFailure3');

      expect(toastCallCount, 1);
    });
  });

  group('Non-blocking startup & fast unavailable engine transitions', () {
    late Directory tempDir;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      tempDir = await Directory.systemTemp.createTemp('paios_startup_test_');
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

    test('AppConfig and repositories initFromHive complete fast without Firebase or network', () async {
      final box = Hive.box('paios_storage');
      await box.put('firstLaunch', false);
      await box.put('settings_user_updated', true);
      await box.put('tokens', 512);
      await box.put('modelReleaseStage', 'preview');
      await box.put('analytics', true);

      var notified = 0;
      final config = AppConfig(notifyEngine: () => notified++);
      final analytics = AnalyticsService(notifyEngine: () => notified++);
      final prompts = PromptRepository(notifyEngine: () => notified++);
      final resources = ResourceRepository(notifyEngine: () => notified++);
      final slides = IntroSlideRepository(notifyEngine: () => notified++);
      final chats = ChatRepository(
        notifyEngine: () => notified++,
        requestTitle: (_) async => 'Test',
        logEvent: (_, __, ___) async {},
        getDefaultPromptId: () => 'system_default',
      );

      final sw = Stopwatch()..start();
      await analytics.initFromHive();
      await config.initFromHive();
      await prompts.initFromHive('https://invalid.example.invalid');
      await resources.initFromHive('https://invalid.example.invalid');
      await slides.initFromHive('https://invalid.example.invalid');
      await chats.initFromHive();
      await DocService.instance.initialize();
      sw.stop();

      expect(sw.elapsedMilliseconds, lessThan(2000));
      expect(config.firstLaunch, isFalse);
      expect(config.tokens, 512);
      expect(config.modelReleaseStage, 'preview');
      expect(prompts.defaultPrompts, isNotEmpty);
      expect(resources.resources, isNotEmpty);
      expect(slides.slides, isNotEmpty);
    });

    test('AIEngine.start() sets appStarted=true fast and transitions cleanly to unavailable', () async {
      final box = Hive.box('paios_storage');
      await box.put('migration_completed', true);
      await box.put('firstLaunch', true);

      const downloadChannel = MethodChannel('download_channel');
      const localAiChannel = MethodChannel('flutter_local_ai');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(downloadChannel, (call) async => null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(localAiChannel, (call) async {
        if (call.method == 'getModelInfo') {
          return <String, dynamic>{
            'available': false,
            'status': 'unavailable',
            'statusCode': 0,
          };
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(downloadChannel, null);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(localAiChannel, null);
      });

      final engine = AIEngine();
      addTearDown(engine.dispose);

      final sw = Stopwatch()..start();
      await engine.start();
      sw.stop();

      expect(engine.appStarted, isTrue);
      expect(sw.elapsedMilliseconds, lessThan(2500));

      await engine.handleDownloadStatus('Error=AICore=Unavailable');
      expect(engine.isAvailable, isFalse);
      expect(engine.isAiCoreKnownUnavailable, isTrue);
      expect(engine.isAiCoreAvailable, isFalse);
    });
  });
}
