import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../engine.dart';
import '../support/elements.dart';


class LogsPage extends StatefulWidget {
  const LogsPage({super.key});
  @override
  LogsPageState createState() => LogsPageState();
}

class LogsPageState extends State<LogsPage> {
  List recentTitles = [];
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
                appBar: AppBar(
                  leading: Padding(
                    padding: EdgeInsetsGeometry.only(left: 5),
                    child: IconButton(
                        onPressed: (){
                          Navigator.pop(context);
                        },
                        icon: Icon(Icons.arrow_back_rounded)
                    ),
                  ),
                  surfaceTintColor: Colors.transparent,
                  title: Text(engine.dict.value(engine.analytics?"logs_with_analytics":"logs_no_analytics")),
                ),
                body: Builder(
                    builder: (context) {
                      return SingleChildScrollView(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Category.settings(
                                title: engine.dict.value("analytics_title"),
                                context: context
                            ),
                            cards.cardGroup([
                              CardContents.turn(
                                  title: engine.dict.value("analytics"),
                                  subtitle: engine.dict.value("analytics_desc"),
                                  action: (){
                                    if(engine.analytics){
                                      engine.stopAnalytics();
                                    }else{
                                      engine.startAnalytics();
                                    }
                                    setState(() {
                                      engine.analytics = !engine.analytics;
                                    });
                                  },
                                  switcher: (value){
                                    if(engine.analytics){
                                      engine.stopAnalytics();
                                    }else{
                                      engine.startAnalytics();
                                    }
                                    setState(() {
                                      engine.analytics = !engine.analytics;
                                    });
                                  },
                                  value: engine.analytics
                              ),
                            ]),
                            Category.settings(
                                title: engine.dict.value("logs_no_analytics"),
                                context: context
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: engine.logs.map((message){
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 2,
                                      horizontal: 10
                                  ),
                                  child: Text(
                                    "${DateTime.fromMillisecondsSinceEpoch(message["time"] as int).toIso8601String().replaceAll("T", " ").split(".")[0]} - ${message["thread"]} ${message["type"]}: ${message["message"]}",
                                    style: TextStyle(
                                        color: message["type"] == "error"
                                            ? Theme.of(context).colorScheme.error
                                            : message["type"] == "warning"
                                            ? Theme.of(context).colorScheme.error.withGreen(255)
                                            : null
                                    ),
                                  ),
                                );
                              }).toList().reversed.toList(),
                            ),
                            TextBlocks.info(
                                title: engine.dict.value(engine.analytics?"logs_info_analytics":"logs_info_local"),
                                subtitle: "",
                                action: (){},
                                context: context
                            )
                          ],
                        ),
                      );
                    }
                ),
              );
            });
          }
      ),
    );
  }
}
