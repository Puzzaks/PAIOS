import 'package:dynamic_color/dynamic_color.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geminilocal/pages/chats.dart';
import 'package:geminilocal/pages/intro.dart';
import 'package:geminilocal/pages/support/elements.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'engine.dart';
import 'firebase_options.dart';




Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
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
    WidgetsFlutterBinding.ensureInitialized();
    Provider.of<AIEngine>(context, listen: false).start();

  }
  @override
  Widget build(BuildContext context) {
    FirebaseAnalytics analytics = FirebaseAnalytics.instance;
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
      final activeDark = darkColorScheme ?? defaultDarkColorScheme;
      SharedPreferences.getInstance().then((prefs) {
        prefs.setInt('theme_color_primary', activeDark.primary.toARGB32());
        prefs.setInt('theme_color_surface', activeDark.surface.toARGB32());
        prefs.setInt('theme_color_background', activeDark.surface.toARGB32());
        prefs.setInt('theme_color_on_surface', activeDark.onSurface.toARGB32());
      });
      return MaterialApp(
        navigatorObservers: [
          FirebaseAnalyticsObserver(
            analytics: analytics,
            nameExtractor: (settings) => settings.name,
          ),
        ],
        theme: themeData(lightColorScheme ?? defaultLightColorScheme),
        darkTheme: themeData(darkColorScheme ?? defaultDarkColorScheme),
        themeMode: ThemeMode.system,
        debugShowCheckedModeBanner: kDebugMode,
        initialRoute: 'ChatsPage',
        onGenerateRoute: (settings) {
          return MaterialPageRoute(
            settings: settings,
            builder: (context) {
              return LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
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
              });
            },
          );
        },
      );
    });
  }
}