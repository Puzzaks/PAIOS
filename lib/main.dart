import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geminilocal/pages/chats.dart';
import 'package:geminilocal/pages/intro.dart';
import 'package:geminilocal/pages/support/elements.dart';
import 'package:provider/provider.dart';
import 'engine.dart';




void main() {
  runApp(ChangeNotifierProvider(
    create: (context) => AIEngine(),
    child: const MyApp(),
  ));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> {

@override
  void initState() {
    super.initState();
    Provider.of<AIEngine>(context, listen: false).start();
  }
  @override
  Widget build(BuildContext context) {
    final defaultLightColorScheme = ColorScheme.fromSwatch(
        primarySwatch: Colors.teal,
    );
    final defaultDarkColorScheme = defaultLightColorScheme.copyWith(
        brightness: Brightness.dark
    );
    ThemeData themeData (colorSheme){
      return ThemeData(
        colorScheme: colorSheme,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          },
        ),
        cardTheme: CardThemeData(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            clipBehavior: Clip.hardEdge,
        ),
        useMaterial3: true,
      );
    }
    return DynamicColorBuilder(builder: (lightColorScheme, darkColorScheme) {
      return MaterialApp(
        theme: themeData(lightColorScheme ?? defaultLightColorScheme),
        darkTheme: themeData(darkColorScheme ?? defaultDarkColorScheme),
        themeMode: ThemeMode.system,
        debugShowCheckedModeBanner: kDebugMode,
        home: LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
          double scaffoldHeight = constraints.maxHeight;
          double scaffoldWidth = constraints.maxWidth;
          return Consumer<AIEngine>(builder: (context, engine, child) {
            engine.cards = Cards(context: context);
            return AnimatedCrossFade(
                alignment: Alignment.center,
                duration: const Duration(milliseconds: 500),
                firstChild: AnimatedCrossFade(
                  alignment: Alignment.center,
                  duration: const Duration(milliseconds: 250),
                  firstChild: SizedBox(
                    height: scaffoldHeight,
                    width: scaffoldWidth,
                    child: IntroPage(),
                  ),
                  secondChild: SizedBox(
                    height: scaffoldHeight,
                    width: scaffoldWidth,
                    child: ChatsPage(),
                  ),
                  crossFadeState: engine.firstLaunch? CrossFadeState.showFirst : CrossFadeState.showSecond,
                ),
                secondChild: Center(
                  child: CircularProgressIndicator(
                    strokeCap: StrokeCap.round,
                  ),
                ),
              crossFadeState: engine.appStarted? CrossFadeState.showFirst : CrossFadeState.showSecond,
            );
          });
        }),
      );
    });
  }
}