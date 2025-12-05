import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../engine.dart';
import '../support/elements.dart';


class SettingsResources extends StatefulWidget {
  const SettingsResources({super.key});
  @override
  SettingsResourcesState createState() => SettingsResourcesState();
}

class SettingsResourcesState extends State<SettingsResources> {
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
                        title: Text(engine.dict.value("settings_resources")),
                        pinned: true,
                      ),
                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: engine.resources.keys.toList().map((collection){
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Category.settings(
                                    title: engine.dict.value(collection),
                                    context: context
                                ),
                                cards.cardGroup(
                                    engine.resources[collection].map((resource){
                                  return CardContents.tap(
                                      title: resource["name"],
                                      subtitle: resource["value"].split("://")[1].split("/")[0],
                                      action: () async {
                                        await launchUrl(
                                          Uri.parse(resource["value"]),
                                          mode: LaunchMode.externalApplication
                                        );
                                      }
                                  );
                                }).toList().cast<Widget>()
                                ),
                              ],
                            );
                          }).toList(),
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