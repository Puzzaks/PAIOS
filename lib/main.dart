import 'package:dynamic_color/dynamic_color.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geminilocal/pages/chat.dart';
import 'package:geminilocal/pages/chats.dart';
import 'package:geminilocal/pages/intro.dart';
import 'package:geminilocal/pages/support/elements.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'engine.dart';
import 'firebase_options.dart';




final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 4));
  } catch (_) {}
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
  AIEngine? _engine;

  void _openAssistantChat() {
    void pushChat() {
      final nav = appNavigatorKey.currentState;
      if (nav == null || !mounted) return;
      nav.popUntil((route) => route.isFirst);
      nav.push(
        MaterialPageRoute(
          builder: (_) => const ChatPage(),
          settings: const RouteSettings(name: 'ChatPage'),
        ),
      );
    }

    if (appNavigatorKey.currentState != null) {
      pushChat();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => pushChat());
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsFlutterBinding.ensureInitialized();
    final engine = Provider.of<AIEngine>(context, listen: false);
    _engine = engine;
    engine.onOpenAssistantChat = _openAssistantChat;
    engine.start();
  }

  @override
  void dispose() {
    if (_engine?.onOpenAssistantChat == _openAssistantChat) {
      _engine?.onOpenAssistantChat = null;
    }
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    FirebaseAnalytics? analytics;
    try {
      if (Firebase.apps.isNotEmpty) {
        analytics = FirebaseAnalytics.instance;
      }
    } catch (_) {}
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
      }).catchError((_) {});
      return MaterialApp(
        navigatorKey: appNavigatorKey,
        navigatorObservers: [
          if (analytics != null)
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
                  if (engine.appStarted && engine.hasPendingOpenAssistantChat) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      engine.flushPendingAssistantChatNavigation();
                    });
                  }
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