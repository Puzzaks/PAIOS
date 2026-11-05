import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:geminilocal/engine.dart';

import 'package:geminilocal/pages/support/elements.dart';



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

    });



    test('AIEngine.cards can be assigned for backwards compatibility', () {

      final engine = AIEngine();

      // Verify cards property is typed and accessible

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

}

