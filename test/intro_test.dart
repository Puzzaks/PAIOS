import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geminilocal/engine.dart';
import 'package:geminilocal/pages/intro.dart';
import 'package:geminilocal/storage/intro_slide_repository.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, dynamic> enTranslations;
  late List<Map<String, dynamic>> introSlides;
  late Map<String, dynamic> defaultPrompts;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Hive.openBox('paios_storage', bytes: Uint8List(0));

    final enRaw = await rootBundle.loadString('assets/translations/en.json');
    enTranslations = Map<String, dynamic>.from(jsonDecode(enRaw) as Map);

    final slidesRaw = await rootBundle.loadString('assets/data/intro_slides.json');
    introSlides = List<Map<String, dynamic>>.from(
      (jsonDecode(slidesRaw) as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );

    final promptsRaw = await rootBundle.loadString('assets/prompts/prompts_index.json');
    final decodedPrompts = jsonDecode(promptsRaw);
    if (decodedPrompts is List) {
      defaultPrompts = {
        for (final item in decodedPrompts)
          item['id'].toString(): Map<String, dynamic>.from(item as Map),
      };
    } else {
      defaultPrompts = Map<String, dynamic>.from(decodedPrompts as Map);
    }
  });

  tearDownAll(() async {
    await Hive.close();
  });

  Future<AIEngine> createIntroEngine() async {
    final box = Hive.box('paios_storage');
    await box.clear();
    await box.put('firstLaunch', true);

    final engine = AIEngine();
    engine.dict.locale = 'en';
    engine.dict.dictionary = {'en': enTranslations};
    engine.introSlideData.slides = List<Map<String, dynamic>>.from(introSlides);
    engine.promptData.defaultPrompts = Map<String, dynamic>.from(defaultPrompts);
    engine.config.firstLaunch = true;
    return engine;
  }

  Future<void> pumpIntroFrames(WidgetTester tester) async {
    await tester.pump();
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> goToSlideA4(WidgetTester tester, AIEngine engine) async {
    final nextLabel = engine.dict.value('intro_next');
    for (int i = 0; i < 3; i++) {
      await tester.tap(find.widgetWithText(FilledButton, nextLabel));
      await pumpIntroFrames(tester);
    }
  }

  group('IntroSlideRepository Tests', () {
    test('getIcon maps common icon names to Material IconData', () {
      expect(IntroSlideRepository.getIcon('forum_rounded'), isNotNull);
      expect(IntroSlideRepository.getIcon('volunteer_activism_rounded'), isNotNull);
      expect(IntroSlideRepository.getIcon('hub_rounded'), isNotNull);
      expect(IntroSlideRepository.getIcon('unknown_icon'), isNotNull);
    });

    test('getSlidesForBranch filters correctly by active branch', () {
      final repo = IntroSlideRepository(notifyEngine: () {});
      repo.slides = [
        {"id": "slide_all", "branch": "all"},
        {"id": "slide_supp", "branch": "supported"},
        {"id": "slide_unsupp", "branch": "unsupported"},
      ];

      final supportedSlides = repo.getSlidesForBranch(true);
      expect(supportedSlides.map((s) => s["id"]), containsAll(["slide_all", "slide_supp"]));
      expect(supportedSlides.map((s) => s["id"]), isNot(contains("slide_unsupp")));

      final unsupportedSlides = repo.getSlidesForBranch(false);
      expect(unsupportedSlides.map((s) => s["id"]), containsAll(["slide_all", "slide_unsupp"]));
      expect(unsupportedSlides.map((s) => s["id"]), isNot(contains("slide_supp")));
    });
  });

  group('IntroPage Slide A-4 State Tests', () {
    testWidgets('shows Gemini Nano Ready state and hides download cards when hasAnyAvailableModel is true', (tester) async {
      final engine = await createIntroEngine();
      engine.isAvailable = true;
      engine.modelInfo = {
        'status': 'available',
        'available': true,
        'hasAnySupportedModel': true,
        'hasAnyAvailableModel': true,
        'statusCode': 3,
        'version': 'nano-v3',
        'modelVariants': [
          {
            'releaseStage': 'stable',
            'preference': 'full',
            'statusCode': 3,
            'status': 'available',
            'available': true,
            'baseModelName': 'nano-v3',
            'isActive': true,
          },
        ],
      };
      // Include a stale Download log entry to ensure Ready & Downloading never show together
      engine.modelDownloadLog = [
        {
          'status': 'Download',
          'info': 'downloading_model',
          'value': '512000000',
          'time': 1000,
        },
      ];

      expect(engine.hasAnyAvailableModel, isTrue);

      await tester.pumpWidget(
        ChangeNotifierProvider<AIEngine>.value(
          value: engine,
          child: MaterialApp(
            theme: ThemeData(useMaterial3: true),
            home: const IntroPage(),
          ),
        ),
      );
      await pumpIntroFrames(tester);
      await goToSlideA4(tester, engine);

      expect(find.text('Gemini Nano Ready'), findsAtLeastNWidgets(1));
      expect(
        find.text(engine.dict.value('intro_gemini_nano_ready_desc')),
        findsOneWidget,
      );
      expect(
        find.text(engine.dict.value('intro_gemini_nano_title')),
        findsNothing,
      );
      expect(
        find.text(engine.dict.value('intro_gemini_nano_desc')),
        findsNothing,
      );
      expect(find.text(engine.dict.value('downloading_model')), findsNothing);
      expect(find.textContaining('Downloading...'), findsNothing);
      expect(find.text(engine.dict.value('welcome_gtfo')), findsNothing);
    });

    testWidgets('shows Download Gemini Nano state when stable variant is downloadable and not downloaded', (tester) async {
      final engine = await createIntroEngine();
      engine.isAvailable = false;
      engine.modelDownloadLog = [];
      engine.modelInfo = {
        'status': 'downloadable',
        'available': false,
        'hasAnySupportedModel': true,
        'hasAnyAvailableModel': false,
        'statusCode': 1,
        'modelVariants': [
          {
            'releaseStage': 'stable',
            'preference': 'full',
            'statusCode': 1,
            'status': 'downloadable',
            'available': false,
            'baseModelName': 'nano-v3',
            'isActive': true,
          },
        ],
      };

      expect(engine.hasAnyAvailableModel, isFalse);

      await tester.pumpWidget(
        ChangeNotifierProvider<AIEngine>.value(
          value: engine,
          child: MaterialApp(
            theme: ThemeData(useMaterial3: true),
            home: const IntroPage(),
          ),
        ),
      );
      await pumpIntroFrames(tester);
      await goToSlideA4(tester, engine);

      expect(find.text('Download Gemini Nano'), findsOneWidget);
      expect(
        find.text(engine.dict.value('intro_gemini_nano_downloadable_desc')),
        findsOneWidget,
      );
      expect(
        find.text(engine.dict.value('onboarding_download_model')),
        findsOneWidget,
      );
      expect(find.text('Gemini Nano Ready'), findsNothing);
      expect(
        find.text(engine.dict.value('intro_gemini_nano_title')),
        findsNothing,
      );
    });
  });
}
