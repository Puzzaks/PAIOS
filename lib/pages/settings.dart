import 'dart:ui';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../engine.dart';
import '../elements.dart';


class settingsPage extends StatefulWidget {
  const settingsPage({super.key});
  @override
  settingsPageState createState() => settingsPageState();
}

class settingsPageState extends State<settingsPage> {
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
    return PopScope(
        onPopInvoked: (didPop) {
          if(didPop) {
            print("PopScope successfully popped the main navigator.");
          }
        },
      canPop: true,
        child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              double scaffoldHeight = constraints.maxHeight;
              double scaffoldWidth = constraints.maxWidth;
              Cards cards = Cards(context: context);
              return Consumer<aiEngine>(builder: (context, engine, child) {
                return Scaffold(
                  body: CustomScrollView(
                    slivers: <Widget>[
                      SliverAppBar.large(
                        surfaceTintColor: Colors.transparent,
                        leading: Padding(
                          padding: EdgeInsetsGeometry.only(left: 5),
                          child: IconButton(
                              onPressed: (){
                                Navigator.pop(context);
                              },
                              icon: Icon(Icons.arrow_back_rounded)
                          ),
                        ),
                        title: Text(engine.dict.value("settings")),
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
                              cardContents.static(
                                  title: engine.dict.value("context_title"),
                                  subtitle: engine.dict.value("context_desc").replaceAll("%c", (engine.context.split(" ").length-1).toString())
                              ),
                            ]),
                            divider.settings(
                                title: engine.dict.value("settings_app"),
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
                            ]),
                            divider.settings(
                                title: engine.dict.value("settings_ai"),
                                context: context
                            ),
                            cards.cardGroup([
                              cardContents.turn(
                                  title: engine.dict.value("add_time"),
                                  subtitle: engine.dict.value("add_time_desc"),
                                  action: (){
                                    setState(() {
                                      engine.addCurrentTimeToRequests = !engine.addCurrentTimeToRequests;
                                    });
                                    engine.saveSettings();
                                  },
                                  switcher: (value){
                                    setState(() {
                                      engine.addCurrentTimeToRequests = !engine.addCurrentTimeToRequests;
                                    });
                                    engine.saveSettings();
                                  },
                                  value: engine.addCurrentTimeToRequests
                              ),
                              cardContents.addretract(
                                  title: engine.dict.value("temperature"),
                                  subtitle: engine.temperature.toStringAsFixed(1),
                                  actionAdd: (){
                                    if(engine.temperature < 0.9){
                                      setState(() {
                                        engine.temperature = engine.temperature + 0.1;
                                      });
                                      engine.saveSettings();
                                    }
                                  },
                                  actionRetract: (){
                                    if(engine.temperature > 0.1){
                                      setState(() {
                                        engine.temperature = engine.temperature - 0.1;
                                      });
                                      engine.saveSettings();
                                    }
                                  }
                              ),
                              cardContents.addretract(
                                  title: engine.dict.value("tokens"),
                                  subtitle: engine.tokens.toString(),
                                  actionAdd: engine.tokens > 225?(){}:(){
                                    setState(() {
                                      engine.tokens = engine.tokens + 32;
                                    });
                                    engine.saveSettings();
                                  },
                                  actionRetract: engine.tokens < 63?(){}:(){
                                    setState(() {
                                      engine.tokens = engine.tokens - 32;
                                    });
                                    engine.saveSettings();
                                  }
                              )
                            ]),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                  horizontal: 20
                              ),
                              child: TextField(
                                controller: engine.instructions,
                                onChanged: (text){
                                  engine.saveSettings();
                                },
                                decoration: InputDecoration(
                                  labelText: engine.dict.value("instructions"),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
                                  hintText: engine.dict.value("instructions_hint"),
                                  helperText: engine.dict.value("ai_may_not_differ_prompt_and_instructions"),
                                ),
                                maxLines: 3,
                                minLines: 1,
                              ),
                            ),
                            divider.settings(
                                title: engine.dict.value("settings_resources"),
                                context: context
                            ),
                            cards.cardGroup([
                              cardContents.tap(
                                  title: engine.dict.value("open_aicore_settings"),
                                  subtitle: engine.dict.value("in_play_store"),
                                  action: () async {
                                    engine.checkAICore();
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
                              )
                            ]),
                            text.info(
                              title: engine.dict.value("welcome_available"),
                              context: context,
                              subtitle: "",
                              action: (){}
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
  }
}