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
  int latestSpeed = 0;
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
    String convertSize(int size, bool isSpeed) {
      if (size < 1024) {
        return '$size B${isSpeed?"/s":""}';
      } else if (size < 10240) {
        double sizeKb = size / 1024;
        return '${sizeKb.toStringAsFixed(2)} KB${isSpeed?"/s":""}';
      } else if (size < 1048576) {
        double sizeKb = size / 1024;
        return '${sizeKb.toStringAsFixed(1)} KB${isSpeed?"/s":""}';
      } else if (size < 10485760) {
        double sizeMb = size / 1048576;
        return '${sizeMb.toStringAsFixed(2)} MB${isSpeed?"/s":""}';
      } else if (size < 104857600) {
        double sizeMb = size / 1048576;
        return '${sizeMb.toStringAsFixed(1)} MB${isSpeed?"/s":""}';
      } else if (size < 1073741824) {
        double sizeGb = size / 1073741824;
        return '${sizeGb.toStringAsFixed(2)} GB${isSpeed?"/s":""}';
      } else if (size < 10737418240) {
        double sizeGb = size / 1073741824;
        return '${sizeGb.toStringAsFixed(1)} GB${isSpeed?"/s":""}';
      } else {
        double sizeGb = size / 1073741824;
        return '${sizeGb.toInt()} GB${isSpeed?"/s":""}';
      }
    }
    String calcSpeed(List log){
      if(log.length > 1){
        int lastSize = int.parse(log[log.length-1]["value"]);
        int lastTime = ((log[log.length-1]["time"]+1) / 1000).toInt();
        int prevSize = int.parse(log[log.length-2]["value"]);
        int prevTime = (log[log.length-2]["time"] / 1000).toInt();
        if(lastTime == prevTime || lastSize == prevSize){
          return convertSize(latestSpeed, true);
        }
        if(lastTime == prevTime || lastSize == prevSize){
          return convertSize(latestSpeed, true);
        }
        int speed = ((lastSize - prevSize) / (lastTime - prevTime)).toInt();
        if(log.length > 2){
          int anotherSize = int.parse(log[log.length-3]["value"]);
          int anotherTime = (log[log.length-3]["time"] / 1000).toInt();
          if(prevSize == anotherSize || prevTime == anotherTime){
            return convertSize(latestSpeed, true);
          }
          int lastSpeed = ((prevSize - anotherSize) / (prevTime - anotherTime)).toInt();
          int avgSpeed = ((speed + lastSpeed)/2).toInt();
          if(avgSpeed < 100){
            return convertSize(latestSpeed, true);
          }else{
            latestSpeed = avgSpeed;
            return convertSize(avgSpeed, true);
          }
        }else{
          if(speed < 100){
            return convertSize(latestSpeed, true);
          }else{
            latestSpeed = speed;
            return convertSize(speed, true);
          }
        }
      }else{
        return convertSize(latestSpeed, true);
      }
    }
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          divider.settings(
                              title: engine.dict.value("settings_status"),
                              context: context
                          ),
                          cards.cardGroup([
                            if(engine.modelDownloadLog.isNotEmpty)
                              if(engine.modelDownloadLog[engine.modelDownloadLog.length-1]["status"] == "Download")
                                if(int.parse(engine.modelDownloadLog[engine.modelDownloadLog.length-1]["value"]) > 0)
                                  cardContents.progress(
                                      title: engine.dict.value(engine.modelDownloadLog[engine.modelDownloadLog.length-1]["info"]),
                                      subtitle: "${convertSize(int.parse(engine.modelDownloadLog[engine.modelDownloadLog.length-1]["value"]), false)}/~${convertSize(engine.usualModelSize, false)} (~${((int.parse(engine.modelDownloadLog[engine.modelDownloadLog.length-1]["value"]) / engine.usualModelSize)*100).toStringAsFixed(2)}%)",
                                      subsubtitle: engine.modelDownloadLog[engine.modelDownloadLog.length-1]["info"] == "waiting_network"?"": calcSpeed(engine.modelDownloadLog),
                                      progress: (int.parse(engine.modelDownloadLog[engine.modelDownloadLog.length-1]["value"])/engine.usualModelSize)
                                  ),
                            if(engine.modelDownloadLog.isNotEmpty)
                              if(engine.modelDownloadLog[engine.modelDownloadLog.length-1]["status"] == "Download")
                                if(int.parse(engine.modelDownloadLog[engine.modelDownloadLog.length-1]["value"]) == 0)
                                  cardContents.progress(
                                      title: engine.dict.value(engine.modelDownloadLog[engine.modelDownloadLog.length-1]["info"]),
                                      subtitle: "${convertSize(0, false)}/${convertSize(engine.usualModelSize, false)} (0%)",
                                      subsubtitle: "",
                                      progress: 0
                                  ),
                            if(engine.modelDownloadLog.isNotEmpty)
                              if(engine.modelDownloadLog[engine.modelDownloadLog.length-1]["status"] == "Available")
                                cardContents.static(
                                    title: "Gemini Nano ${engine.dict.value("available")}",
                                    subtitle: engine.modelInfo["version"] == null
                                        ? ""
                                        : engine.dict.value("model_available").replaceAll("%s", engine.modelInfo["version"])
                                ),
                            if(engine.modelDownloadLog.isNotEmpty)
                              if(engine.modelDownloadLog[engine.modelDownloadLog.length-1]["status"] == "Error")
                                cardContents.doubleTap(
                                    title: "Gemini Nano ${engine.dict.value("unavailable")}",
                                    subtitle: engine.dict.value("whoops"),
                                    action: () async {
                                      engine.gemini.openAICorePlayStore();
                                    },
                                  secondAction: (){
                                      engine.modelDownloadLog.clear();
                                      engine.checkEngine();
                                  },
                                  icon: Icons.refresh_rounded
                                )
                          ]),
                          divider.settings(
                              title: engine.dict.value("language_settings"),
                              context: context
                          ),
                          cards.cardGroup([
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
                                                    return cardContents.halfTap(
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
                          ]),
                          divider.settings(
                              title: engine.dict.value("settings_resources"),
                              context: context
                          ),
                          cards.cardGroup([
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
                          ]),
                          SizedBox(height: 20,),
                          if(engine.modelDownloadLog.isNotEmpty)
                            if(engine.modelDownloadLog[engine.modelDownloadLog.length-1]["status"] == "Download")
                              text.info(
                                  title: engine.dict.value("welcome_download").replaceAll("%size%", convertSize(engine.usualModelSize, false)),
                                  subtitle: "",
                                  action: () {},
                                  context: context
                              ),

                          if(engine.modelDownloadLog.isNotEmpty)
                            if(!(engine.modelDownloadLog[engine.modelDownloadLog.length-1]["status"] == "Download"))
                              text.info(
                                  title: engine.modelInfo["version"] == null
                                      ? engine.dict.value("welcome_unavailable")
                                      : engine.modelInfo["version"] == "Unknown"
                                      ? engine.dict.value("welcome_unavailable")
                                      : engine.dict.value("welcome_available"),
                                  subtitle: engine.dict.value("gh_repo"),
                                  action: () async {
                                    await launchUrl(
                                        Uri.parse('https://github.com/Puzzaks/geminilocal'),
                                        mode: LaunchMode.externalApplication
                                    );
                                  },
                                  context: context
                              ),
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