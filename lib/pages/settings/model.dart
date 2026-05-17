import 'package:flutter/material.dart';
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

                            cards.cardGroup([
                              CardContents.addretract(
                                  title: engine.dict.value("temperature"),
                                  subtitle: engine.dict.value("temperature_desc").replaceAll("%value%", engine.temperature.toStringAsFixed(1)),
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
                            TextBlocks.info(
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
