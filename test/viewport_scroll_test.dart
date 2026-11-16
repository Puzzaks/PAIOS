import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geminilocal/engine.dart';
import 'package:geminilocal/pages/chat.dart';
import 'package:geminilocal/pages/chats.dart';
import 'package:geminilocal/pages/intro.dart';
import 'package:geminilocal/pages/settings/model.dart';
import 'package:geminilocal/pages/support/elements.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:m3x_chat/m3x_chat.dart';
import 'package:m3x_ui/m3x_ui.dart' show MotionBlurContainer;
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

  Future<AIEngine> createTestEngine(WidgetTester tester, {required bool supported}) async {
    final box = Hive.box('paios_storage');
    await box.clear();
    await box.put('firstLaunch', true);

    final engine = AIEngine();
    engine.dict.locale = 'en';
    engine.dict.dictionary = {'en': enTranslations};
    engine.introSlideData.slides = List<Map<String, dynamic>>.from(introSlides);
    engine.promptData.defaultPrompts = Map<String, dynamic>.from(defaultPrompts);
    engine.config.firstLaunch = true;

    if (supported) {
      engine.isAvailable = true;
      engine.modelInfo = {
        'status': 'available',
        'available': true,
        'statusCode': 2,
        'version': '2026.11.01',
        'deviceModel': 'Google Pixel 9',
        'osVersion': 'Android 15',
        'aicoreInstalled': true,
      };
      engine.modelDownloadLog = [
        {
          'status': 'Download',
          'info': 'downloading_model',
          'value': '512000000',
          'time': 1000,
        },
        {
          'status': 'Download',
          'info': 'downloading_model',
          'value': '1024000000',
          'time': 2000,
        },
      ];
    } else {
      engine.isAvailable = false;
      engine.modelInfo = {
        'status': 'unavailable',
        'available': false,
        'statusCode': 0,
        'deviceModel': 'Android Emulator 320w',
        'osVersion': 'Android 14',
        'aicoreInstalled': false,
      };
      engine.modelDownloadLog = [
        {
          'status': 'Error',
          'info': 'AICore',
          'value': 'Unavailable',
          'time': 1000,
        },
      ];
    }

    return engine;
  }

  Future<void> configureViewport(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  Widget wrapWithApp(AIEngine engine, Widget home) {
    return ChangeNotifierProvider<AIEngine>.value(
      value: engine,
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: home,
      ),
    );
  }

  Future<void> pumpFrames(WidgetTester tester, {int steps = 6}) async {
    await tester.pump();
    for (int i = 0; i < steps; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> verifyCurrentSlideScrollsIfOverflowing(WidgetTester tester) async {
    final scrollables = find.descendant(
      of: find.byType(PageView),
      matching: find.byType(SingleChildScrollView),
    );
    expect(scrollables, findsAtLeastNWidgets(1));

    // Find the visible SingleChildScrollView inside the current slide
    for (final element in scrollables.evaluate()) {
      final scrollableState = tester.state<ScrollableState>(
        find.descendant(
          of: find.byWidget(element.widget),
          matching: find.byType(Scrollable),
        ).first,
      );
      final position = scrollableState.position;
      if (position.maxScrollExtent > 10.0) {
        final double initialOffset = position.pixels;
        await tester.drag(find.byWidget(element.widget), const Offset(0, -180));
        await pumpFrames(tester);
        expect(
          position.pixels,
          greaterThan(initialOffset),
          reason: 'Vertical SingleChildScrollView inside slide should scroll down on drag',
        );
        // Drag back up so top controls/content stay accessible
        await tester.drag(find.byWidget(element.widget), const Offset(0, 180));
        await pumpFrames(tester);
      }
    }
  }

  Future<void> runCapturingErrors(Future<void> Function() body) async {
    final errors = <FlutterErrorDetails>[];
    final prevOnError = FlutterError.onError;
    FlutterError.onError = (details) => errors.add(details);
    try {
      await body();
    } finally {
      FlutterError.onError = prevOnError;
    }
    expect(
      errors,
      isEmpty,
      reason: 'FlutterErrors: ${errors.map((e) => e.exceptionAsString()).join('\n')}',
    );
  }

  for (final viewport in const [Size(320, 480), Size(360, 640)]) {
    group('Viewport ${viewport.width.toInt()}x${viewport.height.toInt()}', () {
      testWidgets('IntroPage Branch A (Supported) navigates all slides & scrolls with zero overflows', (tester) async {
        await configureViewport(tester, viewport);
        await runCapturingErrors(() async {
          final engine = await createTestEngine(tester, supported: true);
          await tester.pumpWidget(wrapWithApp(engine, const IntroPage()));
          await pumpFrames(tester);

          // Branch A has 6 built-in slides + 1 remote slide ("all") = 7 slides
          final nextLabel = engine.dict.value('intro_next');
          final getStartedLabel = engine.dict.value('intro_get_started');

          for (int slideIdx = 0; slideIdx < 6; slideIdx++) {
            await verifyCurrentSlideScrollsIfOverflowing(tester);
            final nextBtn = find.widgetWithText(FilledButton, nextLabel);
            expect(nextBtn, findsOneWidget, reason: 'Slide $slideIdx should show Next button');
            await tester.tap(nextBtn);
            await pumpFrames(tester);
          }

          // Last slide (remote support_ukraine slide)
          await verifyCurrentSlideScrollsIfOverflowing(tester);
          final getStartedBtn = find.text(getStartedLabel);
          expect(getStartedBtn, findsOneWidget);
          await tester.tap(getStartedBtn);
          await pumpFrames(tester);
          expect(engine.firstLaunch, isFalse);
        });
      });

      testWidgets('IntroPage Branch B (Unsupported) navigates B-1, B-2, B-3 & scrolls with zero overflows', (tester) async {
        await configureViewport(tester, viewport);
        await runCapturingErrors(() async {
          final engine = await createTestEngine(tester, supported: false);
          await tester.pumpWidget(wrapWithApp(engine, const IntroPage()));
          await pumpFrames(tester);

          // Slide B-1: verify hardware & catalog cards render and vertical scroll works
          expect(find.text(engine.dict.value('intro_aicore_unsupported_title')), findsOneWidget);
          await verifyCurrentSlideScrollsIfOverflowing(tester);

          // Navigate to Slide B-2 via Next button
          final nextLabel = engine.dict.value('intro_next');
          await tester.tap(find.widgetWithText(FilledButton, nextLabel));
          await pumpFrames(tester);

          // Slide B-2: verify troubleshooting & action cards render and vertical scroll works
          expect(find.text(engine.dict.value('intro_troubleshooting_title')), findsOneWidget);
          await verifyCurrentSlideScrollsIfOverflowing(tester);

          // Navigate to Slide B-3 (remote slide) via Next button
          await tester.tap(find.widgetWithText(FilledButton, nextLabel));
          await pumpFrames(tester);

          final getStartedLabel = engine.dict.value('intro_get_started');
          expect(find.text(getStartedLabel), findsOneWidget);

          // Swipe back to Slide B-2 and test "Continue to App" action button after scrolling
          await tester.drag(find.byType(PageView), const Offset(250, 0));
          await pumpFrames(tester);
          expect(find.text(engine.dict.value('intro_troubleshooting_title')), findsOneWidget);

          final continueText = engine.dict.value('btn_continue_to_app');
          await tester.ensureVisible(find.text(continueText));
          await pumpFrames(tester);
          await tester.tap(find.text(continueText));
          await pumpFrames(tester);
          expect(engine.firstLaunch, isFalse);
        });
      });

      testWidgets('ChatsPage scrolls 10+ chats with aiCoreAvailable=false and zero overflows', (tester) async {
        await configureViewport(tester, viewport);
        await runCapturingErrors(() async {
          final engine = await createTestEngine(tester, supported: false);
          final now = DateTime.now().millisecondsSinceEpoch;
          final mockChats = <String, dynamic>{};
          for (int i = 1; i <= 12; i++) {
            mockChats['chat_$i'] = {
              'name': 'Very Long Conversation Title Number $i For Narrow Emulator Viewport Testing',
              'tokens': '${i * 42}',
              'history': jsonEncode([
                {'user': 'User', 'message': 'Hello $i'},
                {'user': 'Gemini', 'message': 'Reply $i'},
              ]),
              'created': now - i * 60000,
              'updated': now - i * 60000,
              'pinned': i <= 2,
              'isArchived': i >= 11,
            };
          }
          engine.chatData.chats = mockChats;

          await tester.pumpWidget(wrapWithApp(engine, const ChatsPage()));
          await pumpFrames(tester);

          final customScroll = find.byType(CustomScrollView);
          expect(customScroll, findsOneWidget);
          final scrollableState = tester.state<ScrollableState>(
            find.descendant(of: customScroll, matching: find.byType(Scrollable)).first,
          );
          expect(scrollableState.position.maxScrollExtent, greaterThan(0));

          await tester.drag(customScroll, const Offset(0, -300));
          await pumpFrames(tester);
          expect(scrollableState.position.pixels, greaterThan(0));
        });
      });

      testWidgets('ChatPage shows unavailable banner, scrolls long messages/bubbles with zero overflows', (tester) async {
        await configureViewport(tester, viewport);
        await runCapturingErrors(() async {
          final engine = await createTestEngine(tester, supported: false);
          engine.currentChat = 'chat_long';
          engine.chatData.chats = {
            'chat_long': {
              'name': 'Long Narrow Viewport Stress Chat Title',
              'tokens': '512',
              'history': '[]',
              'created': 1000,
              'updated': 2000,
            },
          };
          engine.context = [
            {
              'user': 'User',
              'message': 'This is an intentionally very long user prompt message that must wrap cleanly inside a 320px narrow emulator viewport without causing any horizontal RenderFlex overflow.',
            },
            {
              'user': 'Gemini',
              'thoughtProcess': 'Step 1: Analyze viewport constraints.\nStep 2: Ensure ThoughtProcessBubble does not overflow.\n' * 8,
              'message': '```json\n{"action": "tool_call", "tool": "query_aicore_documentation", "description": "Checking AICore docs for narrow viewports", "arguments": {"query": "viewport constraints"}}\n```',
            },
            {
              'user': 'System',
              'message': '[TOOL RESULT: {"status": "ok", "summary": "All constraints bounded properly across 320x480 and 360x640 viewports."}]',
            },
            {
              'user': 'Gemini',
              'message': '### Narrow Viewport Summary\n\nHere is a long Markdown response with **bold text**, `inline_code_identifier_that_is_fairly_long`, and a fenced code block:\n\n```dart\nfinal result = "Responsive Material 3 CardGroup layout without physicalSize!";\n```\n\nPlus extra paragraphs to guarantee vertical scrolling exceeds the viewport height.\n\nParagraph 2: Testing smooth scrolling.\n\nParagraph 3: End of test conversation.',
            },
          ];

          await tester.pumpWidget(wrapWithApp(engine, const ChatPage()));
          await pumpFrames(tester);

          // Unsupported-device errorContainer banner is visible
          expect(find.text(engine.dict.value('chat_aicore_unavailable_title')), findsOneWidget);

          // Expand ChatThoughtsBlock inside ChatMessageBubble & ToolCallBubble and verify zero overflows
          expect(find.byType(ChatMessageBubble), findsAtLeastNWidgets(3));
          expect(find.byType(CircleAvatar), findsNothing);
          await tester.ensureVisible(find.byType(ChatThoughtsBlock));
          await tester.tap(find.byType(ChatThoughtsBlock));
          await pumpFrames(tester);

          await tester.ensureVisible(find.byType(ToolCallBubble));
          await tester.tap(find.byType(ToolCallBubble));
          await pumpFrames(tester);

          // Verify ChatPage's vertical SingleChildScrollView scrolls
          expect(engine.scroller.hasClients, isTrue);
          expect(engine.scroller.position.maxScrollExtent, greaterThan(0));
          final double beforeDrag = engine.scroller.offset;
          final chatScroll = find.byWidgetPredicate(
            (w) => w is SingleChildScrollView && w.controller == engine.scroller,
          );
          expect(chatScroll, findsOneWidget);
          await tester.drag(chatScroll, const Offset(0, -150));
          await pumpFrames(tester);
          expect(engine.scroller.offset, isNot(equals(beforeDrag)));
        });
      });

      testWidgets('CardGroup inside AlertDialog and CardContents.addretract render cleanly without overflow', (tester) async {
        await configureViewport(tester, viewport);
        await runCapturingErrors(() async {
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(useMaterial3: true),
              home: Scaffold(
                body: Builder(
                  builder: (context) {
                    final cards = Cards(context: context);
                    return SingleChildScrollView(
                      child: Column(
                        children: [
                          cards.cardGroup([
                            CardContents.addretract(
                              title: 'Very Long Stepper Title That Must Wrap Cleanly',
                              subtitle: 'Detailed stepper subtitle for narrow screens',
                              actionAdd: () {},
                              actionRetract: () {},
                            ),
                            CardContents.progress(
                              title: 'Downloading Model Weights',
                              subtitle: '512.0 MB / 3.59 GB (14.2%)',
                              subsubtitle: '18.42 MB/s',
                              progress: 0.142,
                            ),
                          ]),
                          ElevatedButton(
                            onPressed: () {
                              showDialog<void>(
                                context: context,
                                builder: (dCtx) => AlertDialog(
                                  title: const Text('Select Language'),
                                  content: SingleChildScrollView(
                                    child: Cards(context: dCtx).cardGroup([
                                      CardContents.halfTap(
                                        title: 'English (United States)',
                                        subtitle: 'Default system language',
                                        action: () => Navigator.pop(dCtx),
                                      ),
                                    ]),
                                  ),
                                ),
                              );
                            },
                            child: const Text('Open Dialog'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          );

          await tester.tap(find.text('Open Dialog'));
          await pumpFrames(tester);
          expect(find.text('English (United States)'), findsOneWidget);
        });
      });
    });
  }

  testWidgets('ChatPage renders model_continuing inside active AI Card at 320x480 with no standalone Chip or overflow', (tester) async {
    await configureViewport(tester, const Size(320, 480));
    await runCapturingErrors(() async {
      final engine = await createTestEngine(tester, supported: true);
      engine.currentChat = 'chat_continue';
      engine.chatData.chats = {
        'chat_continue': {
          'name': 'Continuation Test Chat',
          'tokens': '128',
          'history': '[]',
          'created': 1000,
          'updated': 2000,
        },
      };
      engine.context = [
        {
          'user': 'User',
          'message': 'First prompt',
        },
        {
          'user': 'Gemini',
          'message': 'Older historical AI reply that must not show continuation.',
        },
        {
          'user': 'User',
          'message': 'Continue explaining the architecture in detail.',
        },
      ];
      engine.lastPrompt = 'Continue explaining the architecture in detail.';
      engine.responseText = 'Active streaming partial AI reply that is about to continue.';
      engine.isLoading = true;
      engine.isContinuing = true;

      await tester.pumpWidget(wrapWithApp(engine, const ChatPage()));
      await pumpFrames(tester);

      final continuingLabel = engine.dict.value('model_continuing');
      expect(find.byType(Chip), findsNothing);
      expect(find.text(continuingLabel), findsOneWidget);

      final olderAiCard = find.ancestor(
        of: find.textContaining('Older historical AI reply'),
        matching: find.byType(Card),
      ).first;
      final activeAiCard = find.ancestor(
        of: find.textContaining('Active streaming partial AI reply'),
        matching: find.byType(Card),
      ).first;

      expect(
        find.descendant(of: olderAiCard, matching: find.text(continuingLabel)),
        findsNothing,
      );
      expect(
        find.descendant(of: activeAiCard, matching: find.text(continuingLabel)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: activeAiCard, matching: find.byType(ChatAnimatedSkeleton)),
        findsOneWidget,
      );

      // Verify skeleton disappears cleanly when continuation ends
      engine.isContinuing = false;
      engine.isLoading = false;
      engine.genericRefresh();
      await pumpFrames(tester);

      expect(find.text(continuingLabel), findsNothing);
      expect(find.byType(ChatAnimatedSkeleton), findsNothing);
      expect(find.byType(Chip), findsNothing);
    });
  });

  group('m3x_chat Integration & Model Selector Tests', () {
    for (final viewport in const [Size(320, 480), Size(360, 640)]) {
      testWidgets(
        'ModelSettings shows simplified selector trigger and opens popup without overflow at ${viewport.width.toInt()}x${viewport.height.toInt()}',
        (tester) async {
          await configureViewport(tester, viewport);
          await runCapturingErrors(() async {
            final engine = await createTestEngine(tester, supported: true);
            engine.modelInfo = {
              'status': 'available',
              'available': true,
              'statusCode': 3,
              'version': 'nano-v3',
              'baseModelName': 'nano-v3',
              'releaseStage': 'stable',
              'preference': 'full',
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
                {
                  'releaseStage': 'preview',
                  'preference': 'fast',
                  'statusCode': 3,
                  'status': 'available',
                  'available': true,
                  'baseModelName': 'nano-v4',
                  'isActive': false,
                },
              ],
            };

            await tester.pumpWidget(wrapWithApp(engine, const ModelSettings()));
            await pumpFrames(tester);

            // SegmentedButton controls are replaced with the compact selector row
            expect(find.byType(SegmentedButton<String>), findsNothing);
            final selectorTile = find.text(engine.dict.value('model_selector_title'));
            expect(selectorTile, findsOneWidget);

            await tester.ensureVisible(selectorTile);
            await tester.tap(selectorTile);
            await pumpFrames(tester);

            expect(find.byType(AlertDialog), findsOneWidget);
            expect(find.textContaining('Gemini Nano v3'), findsAtLeastNWidgets(1));
            expect(find.textContaining('Gemini Nano v4'), findsAtLeastNWidgets(1));

            await tester.tap(find.text(engine.dict.value('close')));
            await pumpFrames(tester);
            expect(find.byType(AlertDialog), findsNothing);
          });
        },
      );
    }

    testWidgets('ChatsPage nano-v3/nano-v4 chip opens model selector popup, preserves fixed order, and locks while generating', (tester) async {
      const localAiChannel = MethodChannel('flutter_local_ai');
      Map<String, dynamic>? switchedModelInfo;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(localAiChannel, (call) async {
        if (call.method == 'switchModelConfig') {
          return switchedModelInfo;
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(localAiChannel, null);
      });

      await configureViewport(tester, const Size(360, 640));
      await runCapturingErrors(() async {
        final engine = await createTestEngine(tester, supported: true);
        final updatedV4FastInfo = <String, dynamic>{
          'status': 'available',
          'available': true,
          'statusCode': 3,
          'version': 'nano-v4-fast',
          'baseModelName': 'nano-v4-fast',
          'releaseStage': 'preview',
          'preference': 'fast',
          'modelVariants': [
            {
              'releaseStage': 'preview',
              'preference': 'fast',
              'statusCode': 3,
              'status': 'available',
              'available': true,
              'baseModelName': 'nano-v4-fast',
              'isActive': true,
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
          ],
        };
        switchedModelInfo = updatedV4FastInfo;
        engine.modelInfo = {
          'status': 'available',
          'available': true,
          'statusCode': 3,
          'version': 'nano-v3',
          'baseModelName': 'nano-v3',
          'releaseStage': 'stable',
          'preference': 'full',
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
              'isActive': true,
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
          ],
        };

        await tester.pumpWidget(wrapWithApp(engine, const ChatsPage()));
        await pumpFrames(tester);

        final chipFinder = find.byType(ActionChip);
        expect(chipFinder, findsAtLeastNWidgets(1));
        expect(
          find.descendant(of: chipFinder.last, matching: find.text('nano-v3')),
          findsOneWidget,
        );

        await tester.tap(chipFinder.last);
        await pumpFrames(tester);

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text(engine.dict.value('model_selector_title')), findsOneWidget);
        expect(find.text(engine.dict.value('model_selector_open_settings')), findsOneWidget);
        expect(find.text('gemini-nano-v3'), findsOneWidget);
        expect(find.text('gemini-nano-v4-full'), findsOneWidget);
        expect(find.text('gemini-nano-v4-fast'), findsOneWidget);
        expect(find.text('Gemini Nano v3 • ${engine.dict.value('model_selector_active')}'), findsOneWidget);
        expect(find.text('Gemini Nano v4 • ${engine.dict.value('model_selector_download')}'), findsOneWidget);
        expect(find.text('Gemini Nano v4 • ${engine.dict.value('model_selector_available')}'), findsOneWidget);
        expect(find.byIcon(Icons.radio_button_checked_rounded), findsOneWidget);
        expect(find.byIcon(Icons.radio_button_unchecked_rounded), findsOneWidget);
        expect(find.byIcon(Icons.download_rounded), findsOneWidget);

        // Assert fixed order: stable/full -> preview/full -> preview/fast
        final double v3YBefore = tester.getTopLeft(find.text('gemini-nano-v3')).dy;
        final double v4FullYBefore = tester.getTopLeft(find.text('gemini-nano-v4-full')).dy;
        final double v4FastYBefore = tester.getTopLeft(find.text('gemini-nano-v4-fast')).dy;
        expect(v3YBefore, lessThan(v4FullYBefore));
        expect(v4FullYBefore, lessThan(v4FastYBefore));

        // Select the gemini-nano-v4-fast (preview/fast) variant
        await tester.tap(find.text('gemini-nano-v4-fast'));
        await pumpFrames(tester);

        expect(find.byType(AlertDialog), findsNothing);
        expect(engine.modelReleaseStage, 'preview');
        expect(engine.modelPreference, 'fast');
        expect(engine.isSwitchingModelConfig, isFalse);

        await tester.tap(find.text('nano-v4-fast').last);
        await pumpFrames(tester);

        expect(find.byType(AlertDialog), findsOneWidget);
        // Fixed order preserved even after preview/fast became active
        final double v3YAfter = tester.getTopLeft(find.text('gemini-nano-v3')).dy;
        final double v4FullYAfter = tester.getTopLeft(find.text('gemini-nano-v4-full')).dy;
        final double v4FastYAfter = tester.getTopLeft(find.text('gemini-nano-v4-fast')).dy;
        expect(v3YAfter, lessThan(v4FullYAfter));
        expect(v4FullYAfter, lessThan(v4FastYAfter));

        // Active-inference lock: setting isLoading=true disables switching inside dialog
        engine.isLoading = true;
        engine.genericRefresh();
        await pumpFrames(tester);

        expect(
          find.text(engine.dict.value('model_selector_locked_generating')),
          findsOneWidget,
        );
        await tester.tap(find.text('gemini-nano-v3'), warnIfMissed: false);
        await pumpFrames(tester);

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(engine.modelReleaseStage, 'preview');
        expect(engine.modelPreference, 'fast');

        await tester.tap(find.text(engine.dict.value('close')));
        await pumpFrames(tester);
        expect(find.byType(AlertDialog), findsNothing);
      });
    });

    testWidgets(
      'ModelSettings fixes FeatureStatus 1/2 codes, displays active internalModelName, and locks selector during generation',
      (tester) async {
        await configureViewport(tester, const Size(360, 640));
        await runCapturingErrors(() async {
          final engine = await createTestEngine(tester, supported: true);
          engine.modelInfo = {
            'status': '1',
            'statusCode': 1,
            'available': false,
            'baseModelName': 'nano-v4-full',
            'releaseStage': 'preview',
            'preference': 'full',
            'modelVariants': [
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
                'isActive': true,
              },
            ],
          };

          await tester.pumpWidget(wrapWithApp(engine, const ModelSettings()));
          await pumpFrames(tester);

          // FeatureStatus.DOWNLOADABLE = 1 -> shows Downloadable + download button
          expect(
            find.textContaining(engine.dict.value('model_status_downloadable')),
            findsOneWidget,
          );
          expect(
            find.text(engine.dict.value('download_preview_model')),
            findsOneWidget,
          );
          expect(
            find.textContaining('gemini-nano-v4-full'),
            findsOneWidget,
          );

          // FeatureStatus.DOWNLOADING = 2 -> shows Downloading...
          engine.modelInfo = {
            ...engine.modelInfo,
            'status': '2',
            'statusCode': 2,
          };
          engine.genericRefresh();
          await pumpFrames(tester);
          expect(
            find.textContaining(engine.dict.value('model_status_downloading')),
            findsOneWidget,
          );
          expect(
            find.text(engine.dict.value('downloading_preview_model')),
            findsOneWidget,
          );

          // Active-inference lock on ModelSettings selector row
          engine.isLoading = true;
          engine.genericRefresh();
          await pumpFrames(tester);
          expect(
            find.textContaining(engine.dict.value('model_selector_locked_generating')),
            findsOneWidget,
          );
          expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
          await tester.tap(find.text(engine.dict.value('model_selector_title')));
          await pumpFrames(tester);
          expect(find.byType(AlertDialog), findsNothing);
        });
      },
    );

    testWidgets(
      'ChatPage short bubbles shrink-wrap tightly and scrolling nested ChatThoughtsBlock does not blur outer MotionBlurContainer',
      (tester) async {
        await configureViewport(tester, const Size(360, 640));
        await runCapturingErrors(() async {
          final engine = await createTestEngine(tester, supported: true);
          engine.currentChat = 'chat_short_blur';
          engine.chatData.chats = {
            'chat_short_blur': {
              'name': 'Short & Blur Isolation',
              'tokens': '32',
              'history': '[]',
              'created': 1000,
              'updated': 2000,
            },
          };
          engine.context = [
            {
              'user': 'User',
              'message': 'Hi',
            },
            {
              'user': 'Gemini',
              'message': 'OK',
            },
            {
              'user': 'Gemini',
              'thoughtProcess': List.generate(
                30,
                (i) => 'Thought line $i: verifying nested scroll isolation.',
              ).join('\n'),
              'message': 'Detailed thoughts check.',
            },
          ];

          await tester.pumpWidget(wrapWithApp(engine, const ChatPage()));
          await pumpFrames(tester);

          final userBubble = find.ancestor(
            of: find.text('Hi'),
            matching: find.byType(ChatMessageBubble),
          ).first;
          final userCard = find.descendant(
            of: userBubble,
            matching: find.byType(Card),
          ).first;

          final aiBubble = find.ancestor(
            of: find.text('OK'),
            matching: find.byType(ChatMessageBubble),
          ).first;
          final aiCard = find.descendant(
            of: aiBubble,
            matching: find.byType(Card),
          ).first;

          final double chatBubbleConstraintWidth =
              tester.getSize(userBubble).width;
          expect(
            tester.getSize(userCard).width,
            lessThan(chatBubbleConstraintWidth * 0.5),
          );
          expect(
            tester.getSize(aiCard).width,
            lessThan(chatBubbleConstraintWidth * 0.5),
          );

          // Expand ChatThoughtsBlock and scroll inside it
          await tester.tap(find.byType(ChatThoughtsBlock));
          await pumpFrames(tester);

          final thoughtsScroll = find.descendant(
            of: find.byType(ChatThoughtsBlock),
            matching: find.byType(SingleChildScrollView),
          );
          expect(thoughtsScroll, findsOneWidget);

          final outerMotionBlur = find.descendant(
            of: find.byType(ChatPage),
            matching: find.byType(MotionBlurContainer),
          ).first;
          final outerImageFilteredFinder = find.descendant(
            of: outerMotionBlur,
            matching: find.byType(ImageFiltered),
          ).first;
          expect(
            tester.widget<ImageFiltered>(outerImageFilteredFinder).enabled,
            isFalse,
          );

          await tester.fling(thoughtsScroll, const Offset(0, -300), 1800);
          for (int i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 16));
            expect(
              tester.widget<ImageFiltered>(outerImageFilteredFinder).enabled,
              isFalse,
              reason:
                  'Scrolling nested ChatThoughtsBlock must not trigger blur on outer MotionBlurContainer',
            );
          }
          await pumpFrames(tester);

          final thoughtsScrollableState = tester.state<ScrollableState>(
            find.descendant(
              of: thoughtsScroll,
              matching: find.byType(Scrollable),
            ).first,
          );
          expect(thoughtsScrollableState.position.pixels, greaterThan(0));
        });
      },
    );

    testWidgets(
      'ChatPage uses showAvatar: false, animates ChatAnimatedSkeleton on isLoading, renders ChatThoughtsBlock inside single bubble, and reveals author + timestamp on tap',
      (tester) async {
        await configureViewport(tester, const Size(360, 640));
        await runCapturingErrors(() async {
          final engine = await createTestEngine(tester, supported: true);
          engine.modelInfo = {
            'status': 'available',
            'available': true,
            'statusCode': 3,
            'version': 'nano-v4',
            'baseModelName': 'nano-v4',
          };
          engine.currentChat = 'chat_m3x';
          engine.chatData.chats = {
            'chat_m3x': {
              'name': 'm3x_chat Test',
              'tokens': '64',
              'history': '[]',
              'created': 1000,
              'updated': 2000,
            },
          };

          final msgTime = DateTime(2026, 11, 15, 14, 25, 30);
          engine.context = [
            {
              'user': 'User',
              'time': msgTime.millisecondsSinceEpoch.toString(),
              'message': 'Summarize local thoughts',
            },
            {
              'user': 'Gemini',
              'author': 'Gemini Nano v4',
              'time': msgTime.add(const Duration(seconds: 5)).millisecondsSinceEpoch.toString(),
              'thoughtProcess': 'Reasoning inside the same ChatMessageBubble.',
              'message': 'Here is the **concise** summary.',
            },
          ];
          engine.lastPrompt = 'Next question';
          engine.streamingUserMessageTime = msgTime.add(const Duration(seconds: 10));
          engine.streamingMessageTime = msgTime.add(const Duration(seconds: 11));
          engine.isLoading = true;
          engine.responseText = '';

          await tester.pumpWidget(wrapWithApp(engine, const ChatPage()));
          await pumpFrames(tester);

          // 1. No avatars rendered in PAIOS
          expect(find.byType(CircleAvatar), findsNothing);

          // 2. ChatThoughtsBlock is rendered inside the single ChatMessageBubble
          final aiBubbles = find.byType(ChatMessageBubble);
          expect(aiBubbles, findsNWidgets(4)); // 2 committed + pending user + loading AI
          final committedAiBubble = aiBubbles.at(1);
          expect(
            find.descendant(
              of: committedAiBubble,
              matching: find.byType(ChatThoughtsBlock),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: committedAiBubble,
              matching: find.textContaining('concise'),
            ),
            findsOneWidget,
          );

          // 3. Initial loading renders ChatAnimatedSkeleton, then animates out when text arrives
          expect(find.byType(ChatAnimatedSkeleton), findsOneWidget);

          engine.responseText = 'Streaming reply starts now.';
          engine.isLoading = false;
          engine.genericRefresh();
          await pumpFrames(tester, steps: 8);

          expect(find.byType(ChatAnimatedSkeleton), findsNothing);
          expect(find.textContaining('Streaming reply starts now.'), findsOneWidget);

          // 4. Tapping bubbles reveals author & formatted timestamp metadata
          final userBubble = aiBubbles.at(0);
          await tester.ensureVisible(userBubble);
          await tester.tap(userBubble);
          await pumpFrames(tester);
          expect(
            find.textContaining(engine.dict.value('chat_author_you')),
            findsOneWidget,
          );
          expect(find.textContaining('14:25:30'), findsOneWidget);

          await tester.ensureVisible(committedAiBubble);
          await tester.tap(committedAiBubble);
          await pumpFrames(tester);
          expect(find.textContaining('Gemini Nano v4'), findsOneWidget);
          expect(find.textContaining('14:25:35'), findsOneWidget);
        });
      },
    );

    testWidgets(
      'ToolCallBubble(embeddedInBubble: true) has no nested AnimatedContainer card and shrink-wraps when collapsed',
      (tester) async {
        await configureViewport(tester, const Size(360, 640));
        await runCapturingErrors(() async {
          final engine = await createTestEngine(tester, supported: true);
          engine.currentChat = 'chat_tool_shrink';
          engine.chatData.chats = {
            'chat_tool_shrink': {
              'name': 'Tool Shrink Test',
              'tokens': '32',
              'history': '[]',
              'created': 1000,
              'updated': 2000,
            },
          };
          engine.context = [
            {
              'user': 'User',
              'message': 'Ping',
            },
            {
              'user': 'Gemini',
              'message': '{"tool": "ping", "description": "Ping", "arguments": {}}',
            },
            {
              'user': 'System',
              'message': '[TOOL RESULT: {"ok": true}]',
            },
          ];

          await tester.pumpWidget(wrapWithApp(engine, const ChatPage()));
          await pumpFrames(tester);

          final toolBubbleFinder = find.byType(ToolCallBubble);
          expect(toolBubbleFinder, findsOneWidget);
          expect(
            tester.widget<ToolCallBubble>(toolBubbleFinder).embeddedInBubble,
            isTrue,
          );
          expect(
            find.descendant(
              of: toolBubbleFinder,
              matching: find.byType(AnimatedContainer),
            ),
            findsNothing,
          );

          final outerBubble = find.ancestor(
            of: toolBubbleFinder,
            matching: find.byType(ChatMessageBubble),
          ).first;
          final outerCard = find.descendant(
            of: outerBubble,
            matching: find.byType(Card),
          ).first;
          final double maxBubbleWidth = tester.getSize(outerBubble).width;
          expect(
            tester.getSize(outerCard).width,
            lessThan(maxBubbleWidth * 0.75),
          );
        });
      },
    );

    testWidgets(
      'Failed tool call fallback renders single User bubble and single AI synthesis bubble without duplicates',
      (tester) async {
        await configureViewport(tester, const Size(360, 640));
        await runCapturingErrors(() async {
          final engine = await createTestEngine(tester, supported: true);
          engine.currentChat = 'chat_no_dup';
          engine.chatData.chats = {
            'chat_no_dup': {
              'name': 'No Dupes Test',
              'tokens': '48',
              'history': '[]',
              'created': 1000,
              'updated': 2000,
            },
          };
          engine.context = [
            {
              'user': 'User',
              'message': 'Check server telemetry',
            },
            {
              'user': 'Gemini',
              'message': '{"tool": "get_servers", "app": "ptk", "arguments": {}}',
            },
            {
              'user': 'System',
              'message': '[TOOL ERROR — DATA UNAVAILABLE] Calling get_servers failed: Connection refused',
            },
            {
              'user': 'Gemini',
              'message': 'Unable to retrieve live data from ptk: Connection refused',
            },
          ];
          // Even if lastPrompt briefly matched during a transition, chatlog must not double-render User
          engine.lastPrompt = 'Check server telemetry';
          engine.responseText = '';

          await tester.pumpWidget(wrapWithApp(engine, const ChatPage()));
          await pumpFrames(tester);

          expect(find.text('Check server telemetry'), findsOneWidget);
          expect(
            find.text('Unable to retrieve live data from ptk: Connection refused'),
            findsOneWidget,
          );
          expect(find.byType(ChatMessageBubble), findsNWidgets(3));
        });
      },
    );

    testWidgets(
      'Multi-model background download preserves Model A, tracks progress/speed/remaining, keeps Model B unselectable, and updates ModelSettings',
      (tester) async {
        const localAiChannel = MethodChannel('flutter_local_ai');
        final downloadCompleter = Completer<Map<String, dynamic>>();
        String? invokedMethod;
        Map<dynamic, dynamic>? invokedArgs;

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(localAiChannel, (call) async {
          invokedMethod = call.method;
          invokedArgs = call.arguments as Map<dynamic, dynamic>?;
          if (call.method == 'downloadVariant') {
            return downloadCompleter.future;
          }
          if (call.method == 'getModelInfo') {
            return {
              'status': 'available',
              'available': true,
              'statusCode': 3,
              'version': 'nano-v3',
              'baseModelName': 'nano-v3',
              'releaseStage': 'stable',
              'preference': 'full',
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
                {
                  'releaseStage': 'preview',
                  'preference': 'full',
                  'statusCode': 3,
                  'status': 'available',
                  'available': true,
                  'baseModelName': 'nano-v4-full',
                  'isActive': false,
                },
              ],
            };
          }
          return null;
        });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(localAiChannel, null);
        });

        await configureViewport(tester, const Size(320, 480));
        await runCapturingErrors(() async {
          final engine = await createTestEngine(tester, supported: true);
          engine.config.modelReleaseStage = 'stable';
          engine.config.modelPreference = 'full';
          engine.modelInfo = {
            'status': 'available',
            'available': true,
            'statusCode': 3,
            'version': 'nano-v3',
            'baseModelName': 'nano-v3',
            'releaseStage': 'stable',
            'preference': 'full',
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
              {
                'releaseStage': 'preview',
                'preference': 'full',
                'statusCode': 1,
                'status': 'downloadable',
                'available': false,
                'baseModelName': 'nano-v4-full',
                'isActive': false,
              },
            ],
          };

          await tester.pumpWidget(wrapWithApp(engine, const ChatsPage()));
          await pumpFrames(tester);

          await tester.tap(find.byType(ActionChip).last);
          await pumpFrames(tester);

          expect(find.byType(AlertDialog), findsOneWidget);
          expect(find.text('gemini-nano-v4-full'), findsOneWidget);

          // Tap downloadable Model B -> starts background downloadVariant WITHOUT switching Model A or closing dialog
          await tester.tap(find.text('gemini-nano-v4-full'));
          await pumpFrames(tester);

          expect(invokedMethod, 'downloadVariant');
          expect(invokedArgs?['releaseStage'], 'preview');
          expect(invokedArgs?['preference'], 'full');
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(engine.modelReleaseStage, 'stable');
          expect(engine.modelPreference, 'full');
          expect(engine.downloadStateFor('preview', 'full')?.isDownloading, isTrue);

          // Feed live download progress event (100 MB total, 50 MB downloaded -> 50.0 MB remaining)
          await engine.handleDownloadChannelEvent({
            'releaseStage': 'preview',
            'preference': 'full',
            'status': 'downloading',
            'bytesDownloaded': 52428800,
            'bytesToDownload': 104857600,
          });
          await pumpFrames(tester);

          final dlState = engine.downloadStateFor('preview', 'full')!;
          expect(dlState.progress, closeTo(0.5, 0.001));
          expect(dlState.remainingBytes, 52428800);
          expect(find.byType(LinearProgressIndicator), findsOneWidget);
          expect(find.text('50%'), findsOneWidget);
          expect(find.textContaining('50.0 MB remaining'), findsOneWidget);

          // Tapping Model B while downloading does nothing (unselectable)
          await tester.tap(find.text('gemini-nano-v4-full'), warnIfMissed: false);
          await pumpFrames(tester);
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(engine.modelReleaseStage, 'stable');

          await tester.tap(find.text(engine.dict.value('close')));
          await pumpFrames(tester);

          // Verify ModelSettings displays the background download progress while Model A remains active
          await tester.pumpWidget(wrapWithApp(engine, const ModelSettings()));
          await pumpFrames(tester);
          expect(find.byType(LinearProgressIndicator), findsOneWidget);
          expect(find.text('50%'), findsOneWidget);
          expect(find.textContaining('gemini-nano-v4-full'), findsAtLeastNWidgets(1));

          // Complete background download cleanly
          downloadCompleter.complete({
            'modelVariants': [
              {
                'releaseStage': 'preview',
                'preference': 'full',
                'statusCode': 3,
                'status': 'available',
                'available': true,
                'baseModelName': 'nano-v4-full',
                'isActive': false,
              },
            ],
          });
          await pumpFrames(tester);
        });
      },
    );

    testWidgets(
      'IntroPage keeps supported device with 0 downloaded models in Branch A and unlocks Get Started once single stable model finishes',
      (tester) async {
        await configureViewport(tester, const Size(320, 480));
        await runCapturingErrors(() async {
          final engine = await createTestEngine(tester, supported: true);
          engine.isAvailable = false;
          engine.modelDownloadLog = [];
          engine.modelInfo = {
            'status': 'downloadable',
            'available': false,
            'statusCode': 1,
            'releaseStage': 'stable',
            'preference': 'full',
            'deviceModel': 'Google Pixel 9',
            'osVersion': 'Android 15',
            'aicoreInstalled': true,
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
              {
                'releaseStage': 'preview',
                'preference': 'full',
                'statusCode': 1,
                'status': 'downloadable',
                'available': false,
                'baseModelName': 'nano-v4-full',
                'isActive': false,
              },
            ],
          };

          expect(engine.hasAnySupportedModel, isTrue);
          expect(engine.hasAnyAvailableModel, isFalse);

          await tester.pumpWidget(wrapWithApp(engine, const IntroPage()));
          await pumpFrames(tester);

          // Must route to Branch A (NOT Branch B) and hide Skip while 0 models are downloaded
          expect(
            find.text(engine.dict.value('intro_mind_on_device_title')),
            findsOneWidget,
          );
          expect(
            find.text(engine.dict.value('intro_aicore_unsupported_title')),
            findsNothing,
          );
          expect(find.text(engine.dict.value('intro_skip')), findsNothing);

          // Navigate to Slide A-4 (model download step)
          final nextLabel = engine.dict.value('intro_next');
          for (int i = 0; i < 3; i++) {
            await tester.tap(find.widgetWithText(FilledButton, nextLabel));
            await pumpFrames(tester);
          }

          expect(
            find.text(engine.dict.value('onboarding_download_required')),
            findsOneWidget,
          );
          expect(
            find.text(engine.dict.value('onboarding_download_model')),
            findsOneWidget,
          );

          // Simulate live DownloadStarted.bytesToDownload progress on stable model
          await engine.handleDownloadChannelEvent({
            'releaseStage': 'stable',
            'preference': 'full',
            'status': 'downloading',
            'bytesDownloaded': 524288000,
            'bytesToDownload': 1048576000,
          });
          await pumpFrames(tester);
          expect(find.byType(LinearProgressIndicator), findsOneWidget);
          expect(find.textContaining('50.0%'), findsOneWidget);

          // Advance to final slide — Get Started must be disabled with helper label
          for (int i = 3; i < 6; i++) {
            await tester.tap(find.widgetWithText(FilledButton, nextLabel));
            await pumpFrames(tester);
          }

          final getStartedLabel = engine.dict.value('intro_get_started');
          expect(find.text(getStartedLabel), findsOneWidget);
          expect(
            find.text(engine.dict.value('onboarding_download_required')),
            findsOneWidget,
          );
          await tester.tap(find.text(getStartedLabel));
          await pumpFrames(tester);
          expect(engine.firstLaunch, isTrue);

          // Completing ONLY the single default stable model unlocks Get Started (preview remains downloadable)
          engine.isAvailable = true;
          engine.modelInfo = {
            ...engine.modelInfo,
            'status': 'available',
            'available': true,
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
              {
                'releaseStage': 'preview',
                'preference': 'full',
                'statusCode': 1,
                'status': 'downloadable',
                'available': false,
                'baseModelName': 'nano-v4-full',
                'isActive': false,
              },
            ],
          };
          engine.genericRefresh();
          await pumpFrames(tester);

          expect(engine.hasAnyAvailableModel, isTrue);
          expect(
            find.text(engine.dict.value('onboarding_download_required')),
            findsNothing,
          );
          await tester.tap(find.text(getStartedLabel));
          await pumpFrames(tester);
          expect(engine.firstLaunch, isFalse);
        });
      },
    );
  });
}
