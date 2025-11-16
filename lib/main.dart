import 'dart:ui';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:geminilocal/pages/chat.dart';
import 'package:geminilocal/pages/intro.dart';
import 'package:provider/provider.dart';
import 'engine.dart';




void main() {
  runApp(ChangeNotifierProvider(
    create: (context) => aiEngine(),
    child: const MyApp(),
  ));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> {


  void initState() {
    super.initState();
    Provider.of<aiEngine>(context, listen: false).start();
    // WidgetsFlutterBinding.ensureInitialized();
    // WidgetsBinding.instance.addPostFrameCallback((_) async {
    // });
  }
  Widget build(BuildContext context) {
    final _defaultLightColorScheme = ColorScheme.fromSwatch(primarySwatch: Colors.teal);
    final _defaultDarkColorScheme = ColorScheme.fromSwatch(primarySwatch: Colors.teal, brightness: Brightness.dark);
    ThemeData _themeData (colorSheme){
      return ThemeData(
        colorScheme: colorSheme,
        cardTheme: CardThemeData(
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            clipBehavior: Clip.hardEdge
        ),
        useMaterial3: true,
      );
    }
    TextStyle blacker = const TextStyle(
        color: Colors.black
    );
    return DynamicColorBuilder(builder: (lightColorScheme, darkColorScheme) {
      return MaterialApp(
        theme: _themeData(lightColorScheme ?? _defaultLightColorScheme).copyWith(
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
              },
            ),
            cardColor: Colors.grey,
            iconTheme: const IconThemeData(
                color: Colors.black
            ),
            textTheme: TextTheme(
                displayLarge: blacker,
                displayMedium: blacker,
                displaySmall: blacker,
                headlineLarge: blacker,
                headlineMedium: blacker,
                headlineSmall: blacker,
                titleLarge: blacker,
                titleMedium: blacker,
                titleSmall: blacker,
                bodyLarge: blacker,
                bodyMedium: blacker,
                bodySmall: blacker,
                labelLarge: blacker,
                labelMedium: blacker,
                labelSmall: blacker
            )
        ),
        darkTheme: _themeData(darkColorScheme ?? _defaultDarkColorScheme).copyWith(
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: {
              TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
            },
          ),
        ),
        themeMode: ThemeMode.system,
        debugShowCheckedModeBanner: false,
        home: LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
          double scaffoldHeight = constraints.maxHeight;
          double scaffoldWidth = constraints.maxWidth;
          return Consumer<aiEngine>(builder: (context, engine, child) {
            Widget settingsDivider(String name,{double leftPadding = 20}){
              return Padding(
                padding: EdgeInsets.only(
                    top:10, left: leftPadding, right: 15, bottom: 5
                ),
                child: Text(
                  name,
                  style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w100
                  ),
                ),
              );
            }
            return AnimatedCrossFade(
                alignment: Alignment.center,
                duration: const Duration(milliseconds: 500),
                firstChild: AnimatedCrossFade(
                  alignment: Alignment.center,
                  duration: const Duration(milliseconds: 250),
                  firstChild: Container(
                    height: scaffoldHeight,
                    width: scaffoldWidth,
                    child: introPage(),
                  ),
                  secondChild: Container(
                    height: scaffoldHeight,
                    width: scaffoldWidth,
                    child: chatPage(),
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