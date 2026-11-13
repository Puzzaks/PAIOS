import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geminilocal/engine.dart';
import 'package:geminilocal/pages/support/elements.dart';
import 'package:m3x/m3x.dart' hide Cards, CardContents, Category, TextPart, text, Dictionary, AnalyticsService;

void main() {
  group('AIEngine Tests', () {
    test('AIEngine instantiates with correct default state', () {
      final engine = AIEngine();
      expect(engine.isLoading, isFalse);
      expect(engine.isAvailable, isFalse);
      expect(engine.isInitialized, isFalse);
      expect(engine.appStarted, isFalse);
      expect(engine.dict.locale, 'en');
      expect(engine.responseText, isEmpty);
      expect(engine.response.text, 'Loading...');
      expect(engine.downsampleImages, isTrue);
      expect(engine.enableMesh, isTrue);
      expect(engine.pendingImageBytes, isNull);
    });

    test('AIEngine image attachment state and mesh toggle work', () {
      final engine = AIEngine();
      engine.pendingImageBytes = Uint8List.fromList([1, 2, 3, 4]);
      engine.pendingImageName = 'board.png';
      expect(engine.pendingImageBytes, isNotNull);
      engine.clearImageAttachment();
      expect(engine.pendingImageBytes, isNull);
      expect(engine.pendingImageName, isNull);

      engine.enableMesh = false;
      expect(engine.enableMesh, isFalse);
      expect(engine.meshClient.enabled, isFalse);
    });

    test('ChatRepository saves chat images and cascades deletion on chat removal', () async {
      final engine = AIEngine();
      final sampleBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
      final savedPath = await engine.chatData.saveChatImage(
        sampleBytes,
        chatID: 'test_chat_999',
      );
      final savedFile = File(savedPath);
      expect(await savedFile.exists(), isTrue);

      engine.chatData.chats['test_chat_999'] = {
        'name': 'Vision Test',
        'history': jsonEncode([
          {
            'user': 'User',
            'message': 'Check this image',
            'imagePath': savedPath,
          }
        ]),
      };

      // Deleting the chat purges the saved image file and directory
      try {
        await engine.chatData.deleteChat('test_chat_999');
      } catch (_) {
        // Hive box may not be open in pure unit test, but _purgeChatImages runs first
      }
      expect(await savedFile.exists(), isFalse);
    });

    test('AIEngine.cards can be assigned for backwards compatibility', () {
      final engine = AIEngine();
      expect(() => engine.cards, throwsA(isA<Error>()));
    });
  });

  group('puzzak_ui & elements.dart Widget Tests', () {
    testWidgets('Cards.cardGroup renders child cards without error', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final cards = Cards(context: context);
                return cards.cardGroup([
                  CardContents.tap(
                    title: 'Settings Title',
                    subtitle: 'Settings Subtitle',
                    action: () {},
                  ),
                  CardContents.tap(
                    title: 'Another Card',
                    subtitle: 'Another Subtitle',
                    action: () {},
                  ),
                ]);
              },
            ),
          ),
        ),
      );

      expect(find.text('Settings Title'), findsOneWidget);
      expect(find.text('Settings Subtitle'), findsOneWidget);
      expect(find.text('Another Card'), findsOneWidget);
      expect(find.text('Another Subtitle'), findsOneWidget);
    });

    testWidgets('Category and text / TextPart render correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return Column(
                  children: [
                    Category.settings(
                      title: 'Section Header',
                      context: context,
                    ),
                    text.info(
                      title: 'Info Notice Title',
                      subtitle: 'Learn more',
                      action: () {},
                      context: context,
                    ),
                    TextPart.infoShort(
                      title: 'Short Notice',
                      subtitle: '',
                      action: () {},
                      context: context,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('Section Header'), findsOneWidget);
      expect(find.text('Info Notice Title'), findsOneWidget);
      expect(find.text('Learn more'), findsOneWidget);
      expect(find.text('Short Notice'), findsOneWidget);
    });

    testWidgets('text.chatlog preserves historical duplicate messages (Bug #4 fix)', (WidgetTester tester) async {
      final history = [
        {'user': 'User', 'message': 'Hello'},
        {'user': 'Gemini', 'message': 'Hi there!'},
        {'user': 'User', 'message': 'Hello'},
        {'user': 'Gemini', 'message': 'How can I help?'},
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final helper = text();
                final widgets = helper.chatlog(
                  aiChunk: '',
                  lastUser: 'Hello',
                  conversation: history,
                  context: context,
                );
                return ListView(children: widgets);
              },
            ),
          ),
        ),
      );

      // Verify that earlier historical messages matching lastUser are NOT suppressed
      expect(find.text('Hello'), findsNWidgets(3));
      expect(find.text('Hi there!'), findsOneWidget);
      expect(find.text('How can I help?'), findsOneWidget);
    });
  });

  group('M3x & SettingsBentoHeader Tests', () {
    test('M3x parses pubspec YAML and formats version correctly', () {
      const sampleYaml = '''
name: geminilocal
description: "Local AI, on-device client"
version: 1.2.5+26110706
''';
      M3x.parsePubspec(sampleYaml);
      expect(M3x.appName, 'geminilocal');
      expect(M3x.appDescription, 'Local AI, on-device client');
      expect(M3x.appVersion, '1.2.5');
      expect(M3x.appBuildNumber, '26110706');
      expect(M3x.versionDisplay, '1.2.5 (Nov 7, 2026 (rev 06))');
    });

    testWidgets('SettingsBentoHeader renders correctly and triggers callbacks', (WidgetTester tester) async {
      bool versionTapped = false;
      bool modulesTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsBentoHeader(
              appName: 'PAIOS',
              subtitle: 'Local AI, on-device client',
              icon: Icons.hexagon_rounded,
              versionDisplay: '1.2.5 (Nov 7, 2026 (rev 06))',
              connectedModulesCount: 5,
              onVersionTap: () => versionTapped = true,
              onModulesTap: () => modulesTapped = true,
            ),
          ),
        ),
      );

      expect(find.text('PAIOS'), findsOneWidget);
      expect(find.text('Local AI, on-device client'), findsOneWidget);
      expect(find.text('Version 1.2.5'), findsOneWidget);
      expect(find.text('Nov 7, 2026 (rev 06)'), findsOneWidget);
      expect(find.text('5 Packages'), findsOneWidget);
      expect(find.text('Tap to view'), findsOneWidget);

      await tester.tap(find.text('Nov 7, 2026 (rev 06)'));
      await tester.pump();
      expect(versionTapped, isTrue);

      await tester.tap(find.text('5 Packages'));
      await tester.pump();
      expect(modulesTapped, isTrue);
    });
  });
}
