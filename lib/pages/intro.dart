import 'dart:ui';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../engine.dart';
import 'support/elements.dart';


class introPage extends StatefulWidget {
  const introPage({super.key});
  @override
  introPageState createState() => introPageState();
}

class introPageState extends State<introPage> {
  @override
  @override
  void initState() {
    super.initState();
  }
  final MaterialStateProperty<Icon?> thumbIcon = MaterialStateProperty.resolveWith<Icon?>(
        (Set<MaterialState> states) {
      if (states.contains(MaterialState.selected)) {
        return const Icon(Icons.check);
      }
      return const Icon(Icons.close);
    },
  );
  @override
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
        darkTheme: _themeData(darkColorScheme ?? _defaultDarkColorScheme),
        themeMode: ThemeMode.system,
        debugShowCheckedModeBanner: false,
        home: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            double scaffoldHeight = constraints.maxHeight;
            double scaffoldWidth = constraints.maxWidth;
            Cards cards = Cards(context: context);
            return Consumer<aiEngine>(builder: (context, engine, child) {
              return Scaffold(
                // The entire body is a CustomScrollView
                body: CustomScrollView(
                  slivers: <Widget>[
                    // This is the animated, collapsing app bar
                    SliverAppBar.large(
                      surfaceTintColor: Colors.transparent,
                      title: const Text('Gemini Nano'),
                      // 'pinned: true' makes the app bar stick to the top
                      // 'floating: false' and 'snap: false' are the default
                      // and give the standard "scroll up to collapse" behavior.
                      pinned: true,
                    ),
                    SliverToBoxAdapter(
                      child: Column(
                        children: [
                          cardContents.static(
                              title: "Gemini Nano ${
                                  engine.modelInfo["version"] == null
                                      ? engine.dict.value("unavailable")
                                      : engine.modelInfo["version"] == "Unknown"
                                      ? engine.dict.value("unavailable")
                                      : engine.dict.value("available")
                              }",
                              subtitle: engine.modelInfo["version"] == null
                                  ? ""
                                  : engine.modelInfo["version"] == "Unknown"
                                  ? ""
                                  : engine.dict.value("model_available").replaceAll("%s", engine.modelInfo["version"])
                          ),
                          Padding(
                            padding: EdgeInsetsGeometry.only(
                                bottom: 20,
                                left: 20,
                                right: 20,
                                top: 10
                            ),
                            child: Container(
                              width: scaffoldWidth - 40,
                              child: engine.modelInfo["version"] == null
                                  ? Text(engine.dict.value("welcome_unavailable"))
                                  : engine.modelInfo["version"] == "Unknown"
                                  ? Text(engine.dict.value("welcome_unavailable"))
                                  : Text(engine.dict.value("welcome_available")),
                            ),
                          ),
                          cards.cardGroup([
                            cardContents.static(
                                title: "Gemini Nano ${
                                    engine.modelInfo["version"] == null
                                        ? engine.dict.value("unavailable")
                                        : engine.modelInfo["version"] == "Unknown"
                                          ? engine.dict.value("unavailable")
                                          : engine.dict.value("available")
                                }",
                                subtitle: engine.modelInfo["version"] == null
                                    ? ""
                                    : engine.modelInfo["version"] == "Unknown"
                                      ? ""
                                      : engine.dict.value("model_available").replaceAll("%s", engine.modelInfo["version"])
                            ),
                            cardContents.longTap(
                                title: engine.dict.value("select_language"),
                                subtitle: engine.dict.value("select_language_auto_long"),
                                action: () {
                                  showDialog(
                                    context: context,
                                    builder:
                                        (BuildContext dialogContext) =>
                                        AlertDialog(
                                          contentPadding: EdgeInsets.only(
                                            top: 10,
                                            bottom: 15,
                                          ),
                                          titlePadding: EdgeInsets.only(
                                              top: 20,
                                              right: 20,
                                              left: 20
                                          ),
                                          title: Text(engine.dict.value("select_language")),
                                          content: SingleChildScrollView(
                                              child: cards.cardGroup(
                                                  engine.dict.languages.map((language) {
                                                    return cardContents.tap(
                                                        title: language["origin"],
                                                        subtitle: language["name"] == language["origin"] ? "" : language["name"],
                                                        action: () async {
                                                          setState(() {
                                                            engine.dict.locale = language["id"];
                                                          });
                                                          Navigator.of(dialogContext).pop();
                                                        }
                                                    );
                                                  }).toList().cast<Widget>()
                                              )
                                          ),
                                        ),
                                  );
                                },
                                longAction: (){
                                  setState(() {
                                    engine.dict.setSystemLanguage();
                                  });
                                }
                            ),
                            cardContents.tap(
                                title: engine.dict.value("open_aicore_settings"),
                                subtitle: engine.dict.value("in_play_store"),
                                action: () async {
                                  engine.gemini.openAICorePlayStore();
                                }
                            ),
                            cardContents.tap(
                                title: engine.dict.value("gh_repo"),
                                subtitle: engine.dict.value("tap_to_open"),
                                action: () async {
                                  await launchUrl(
                                      Uri.parse('https://github.com/Puzzaks/geminilocal'),
                                      mode: LaunchMode.externalApplication
                                  );
                                }
                            ),
                            cardContents.tap(
                                title: engine.dict.value("documentation"),
                                subtitle: engine.dict.value("tap_to_open"),
                                action: () async {
                                  await launchUrl(
                                      Uri.parse('https://developers.google.com/ml-kit/genai#prompt-device')
                                  );
                                }
                            ),
                            if(!(engine.modelInfo["version"] == null))
                              if(!(engine.modelInfo["version"] == "Unknown"))
                                cardContents.tap(
                                    title: engine.dict.value("continue"),
                                    subtitle: "",
                                    action: () {
                                      engine.endFirstLaunch();
                                    }
                                ),
                          ]),
                          SizedBox(
                            height: 30,
                          )
                        ],
                      ),
                    ),
                  ],

                ),
              );
            });
          }
        )
      );
    });
  }
}