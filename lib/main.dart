import 'dart:async';
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

Future<void> _initFirebaseNonBlocking() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 4));
  } catch (_) {}
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final Future<void> firebaseInitFuture = _initFirebaseNonBlocking();
  runApp(ChangeNotifierProvider(
    create: (context) => AIEngine(),
    child: MyApp(firebaseInitFuture: firebaseInitFuture),
  ));
}

class MyApp extends StatefulWidget {
  final Future<void>? firebaseInitFuture;
  const MyApp({super.key, this.firebaseInitFuture});
  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> with WidgetsBindingObserver {
  AIEngine? _engine;
  int? _lastWrittenPrimary;
  int? _lastWrittenSurface;
  int? _lastWrittenOnSurface;

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
    WidgetsBinding.instance.addObserver(this);
    final engine = Provider.of<AIEngine>(context, listen: false);
    _engine = engine;
    engine.onOpenAssistantChat = _openAssistantChat;
    engine.start();
    widget.firebaseInitFuture?.whenComplete(() {
      if (!mounted) return;
      if (engine.analytics && !engine.analyticsDone && Firebase.apps.isNotEmpty) {
        unawaited(engine.startAnalytics());
      }
      setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _engine?.onAppResumed();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_engine?.onOpenAssistantChat == _openAssistantChat) {
      _engine?.onOpenAssistantChat = null;
    }
    super.dispose();
  }

  void _persistThemeColorsIfChanged(ColorScheme activeDark) {
    final primary = activeDark.primary.toARGB32();
    final surface = activeDark.surface.toARGB32();
    final onSurface = activeDark.onSurface.toARGB32();
    if (_lastWrittenPrimary == primary &&
        _lastWrittenSurface == surface &&
        _lastWrittenOnSurface == onSurface) {
      return;
    }
    _lastWrittenPrimary = primary;
    _lastWrittenSurface = surface;
    _lastWrittenOnSurface = onSurface;
    SharedPreferences.getInstance().then((prefs) {
      if (prefs.getInt('theme_color_primary') != primary) {
        prefs.setInt('theme_color_primary', primary);
      }
      if (prefs.getInt('theme_color_surface') != surface) {
        prefs.setInt('theme_color_surface', surface);
      }
      if (prefs.getInt('theme_color_background') != surface) {
        prefs.setInt('theme_color_background', surface);
      }
      if (prefs.getInt('theme_color_on_surface') != onSurface) {
        prefs.setInt('theme_color_on_surface', onSurface);
      }
    }).catchError((_) {});
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
      _persistThemeColorsIfChanged(activeDark);
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