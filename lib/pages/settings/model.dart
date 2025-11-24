import 'package:flutter/material.dart';
import 'package:geminilocal/pages/settings/context.dart';
import 'package:provider/provider.dart';
import '../../engine.dart';
import '../support/elements.dart';


class ModelSettings extends StatefulWidget {
  const ModelSettings({super.key});
  @override
  ModelSettingsState createState() => ModelSettingsState();
}

class ModelSettingsState extends State<ModelSettings> {
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
              return Consumer<AIEngine>(builder: (context, engine, child) {
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
                        title: Text(engine.dict.value("settings_ai")),
                        pinned: true,
                      ),
                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            divider.settings(
                                title: engine.dict.value("system_prompt"),
                                context: context
                            ),
                            cards.cardGroup([
                              CardContents.turn(
                                  title: engine.dict.value("ignore_instructions"),
                                  subtitle: engine.dict.value("ignore_instructions_desc"),
                                  action: (){
                                    setState(() {
                                      engine.ignoreInstructions = !engine.ignoreInstructions;
                                    });
                                    engine.saveSettings();
                                  },
                                  switcher: (value){
                                    setState(() {
                                      engine.ignoreInstructions = !engine.ignoreInstructions;
                                    });
                                    engine.saveSettings();
                                  },
                                  value: engine.ignoreInstructions
                              ),
                              CardContents.tap(
                                  title: engine.dict.value("system_prompt"),
                                  subtitle: engine.dict.value("system_prompt_desc"),
                                  action: () async {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => ModelSettingsContext()),
                                    );
                                    engine.testPrompt = await engine.promptEngine.generate(
                                        "replaceme",
                                        engine.context,
                                        engine.modelInfo,
                                      shareLocale: engine.shareLocale,
                                      addTime: engine.addCurrentTimeToRequests,
                                      currentLocale: engine.dict.value("current_language")
                                    );
                                  }
                              )
                            ]),
                            divider.settings(
                                title: engine.dict.value("settings_ai"),
                                context: context
                            ),
                            cards.cardGroup([
                              CardContents.addretract(
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
                              CardContents.addretract(
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
                              ),
                            ]),
                            divider.settings(
                                title: engine.dict.value("shared_data"),
                                context: context
                            ),
                            cards.cardGroup([
                              CardContents.turn(
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
                              CardContents.turn(
                                  title: engine.dict.value("add_lang"),
                                  subtitle: engine.dict.value("add_lang_desc"),
                                  action: (){
                                    setState(() {
                                      engine.shareLocale = !engine.shareLocale;
                                    });
                                    engine.saveSettings();
                                  },
                                  switcher: (value){
                                    setState(() {
                                      engine.shareLocale = !engine.shareLocale;
                                    });
                                    engine.saveSettings();
                                  },
                                  value: engine.shareLocale
                              ),
                            ]),
                            divider.settings(
                                title: engine.dict.value("reset_model_settings"),
                                context: context
                            ),
                            cards.cardGroup([
                              CardContents.tap(
                                  title: engine.dict.value("reset_model_context"),
                                  subtitle: engine.dict.value("context_desc").replaceAll("%c", engine.contextSize.toString()),
                                  action: (){
                                    engine.clearContext();
                                  }
                              ),
                              CardContents.tap(
                                  title: engine.dict.value("reset_model_prompt"),
                                  subtitle: engine.instructions.text.isEmpty?engine.dict.value("reset_model_prompt_desc"):"",
                                  action: engine.instructions.text.isEmpty?(){}:(){
                                    engine.instructions.clear();
                                    engine.saveSettings();
                                    setState(() {});
                                  }
                              ),
                              CardContents.tap(
                                  title: engine.dict.value("reset_model_params"),
                                  subtitle: engine.dict.value("reset_model_params_desc"),
                                  action: () async {
                                    engine.temperature = 0.7;
                                    engine.tokens = 256;
                                    await engine.saveSettings();
                                    setState(() {});
                                  }
                              ),
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