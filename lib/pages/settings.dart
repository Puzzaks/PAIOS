import 'package:flutter/material.dart';
import 'package:geminilocal/pages/settings/modelSettings.dart';
import 'package:geminilocal/pages/settings/settingsResources.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../engine.dart';
import 'support/elements.dart';
import 'package:intl/intl.dart';


class settingsPage extends StatefulWidget {
  const settingsPage({super.key});
  @override
  settingsPageState createState() => settingsPageState();
}

class settingsPageState extends State<settingsPage> {
  @override
  void initState() {
    super.initState();
  }
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
        child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
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
                                                      return cardContents.halfTap(
                                                          title: language["origin"],
                                                          subtitle: language["name"] == language["origin"] ? "" : language["name"],
                                                          action: () async {
                                                            setState(() {
                                                              engine.dict.saveLanguage(language["id"]);
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
                              cardContents.turn(
                                  title: engine.dict.value("error_retry"),
                                  subtitle: engine.dict.value("error_retry_desc"),
                                  action: (){
                                    setState(() {
                                      engine.errorRetry = !engine.errorRetry;
                                    });
                                    engine.saveSettings();
                                  },
                                  switcher: (value){
                                    setState(() {
                                      engine.errorRetry = !engine.errorRetry;
                                    });
                                    engine.saveSettings();
                                  },
                                  value: engine.errorRetry
                              ),
                              cardContents.tap(
                                  title: engine.dict.value("open_aicore_settings"),
                                  subtitle: engine.dict.value("in_play_store"),
                                  action: () async {
                                    engine.gemini.openAICorePlayStore();
                                  }
                              ),
                            ]),
                            divider.settings(
                                title: engine.dict.value("settings_ai"),
                                context: context
                            ),
                            cards.cardGroup([
                              cardContents.tapIcon(
                                  title: engine.dict.value("settings_ai"),
                                  subtitle: engine.dict.value("settings_ai_desc"),
                                  icon: Icons.auto_awesome_rounded,
                                  colorBG: Theme.of(context).colorScheme.primaryFixedDim,
                                  color: Theme.of(context).colorScheme.onPrimaryFixed,
                                  action: (){
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => modelSettings()),
                                    );
                                  }
                              )
                            ]),
                            divider.settings(
                                title: engine.dict.value("settings_resources"),
                                context: context
                            ),
                            cards.cardGroup([
                              cardContents.tapIcon(
                                  title: engine.dict.value("settings_resources"),
                                  subtitle: engine.dict.value("settings_resources_desc"),
                                  icon: Icons.dataset_linked_rounded,
                                  colorBG: Theme.of(context).colorScheme.primaryFixedDim,
                                  color: Theme.of(context).colorScheme.onPrimaryFixed,
                                  action: (){
                                    engine.resources.clear();
                                    for(var resource in engine.promptEngine.resources){
                                      if(resource["type"] == "link"){
                                        if(engine.resources.containsKey(resource["collection"])){
                                          engine.resources[resource["collection"]].add(resource);
                                        }else{
                                          engine.resources[resource["collection"]] = [resource];
                                        }
                                      }
                                    }
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => settingsResources()),
                                    );
                                  }
                              )
                            ]),
                            text.info(
                              title: engine.dict.value("settings_info").replaceAll("%year%", DateFormat('yyyy').format(DateTime.now())),
                              context: context,
                              subtitle: engine.dict.value("gh_repo"),
                              action: () async {
                                await launchUrl(
                                Uri.parse('https://github.com/Puzzaks/geminilocal'),
                                mode: LaunchMode.externalApplication
                                );
                              }
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