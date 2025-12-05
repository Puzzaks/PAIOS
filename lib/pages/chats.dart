import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:geminilocal/pages/chat.dart';
import 'package:geminilocal/pages/settings.dart';
import 'package:geminilocal/pages/settings/chat.dart';
import 'package:provider/provider.dart';
import '../engine.dart';
import 'support/elements.dart';


class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key});
  @override
  ChatsPageState createState() => ChatsPageState();
}

class ChatsPageState extends State<ChatsPage> {

  String timeAgo(time) {
    DateTime currentTime = DateTime.now();
    late DateTime pastTimestamp;
    if(time is int){
      pastTimestamp = DateTime.fromMillisecondsSinceEpoch(time);
    }else if(time is String){
      pastTimestamp = DateTime.fromMillisecondsSinceEpoch(int.parse(time));
    }else if(time is DateTime){
      pastTimestamp = time;
    }else{
      return "Not a DateTime!";
    }
    final Duration difference = currentTime.difference(pastTimestamp);

    final int seconds = difference.inSeconds.abs();
    final int minutes = difference.inMinutes.abs();
    final int hours = difference.inHours.abs();
    final int days = difference.inDays.abs();

    if (seconds < 60) {
      return 'just now';
    } else if (minutes < 60) {
      final String unit = minutes == 1 ? 'minute' : 'minutes';
      return '$minutes $unit';
    } else if (hours < 24) {
      final String unit = hours == 1 ? 'hour' : 'hours';
      return '$hours $unit';
    } else if (days < 30) { // Approximates within a month
      final String unit = days == 1 ? 'day' : 'days';
      return '$days $unit';
    } else if (days < 365) {
      final int months = (days / 30).round();
      final String unit = months == 1 ? 'month' : 'months';
      return '$months $unit';
    } else {
      final int years = (days / 365).round();
      final String unit = years == 1 ? 'year' : 'years';
      return '$years $unit';
    }
  }
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
                Widget chatCard (chat, key){
                  return CardContents.doubleTap(
                      title: chat["name"]??"Loading...",
                      subtitle: (engine.isLoading && engine.currentChat == key)
                          ? engine.dict.value("generating_hint").replaceAll("%seconds%", ((engine.response.generationTimeMs??10)/1000).toStringAsFixed(2)).replaceAll("%tokens%", engine.response.tokenCount.toString()).replaceAll("%tokenspersec%", (engine.response.tokenCount!.toInt()/((engine.response.generationTimeMs??10)/1000)).toStringAsFixed(2))
                          : timeAgo(chat["updated"]) == "just now"
                          ? "${engine.dict.value("updated")} ${engine.dict.value("just_now")}, ${engine.dict.value("messages")}: ${jsonDecode(chat["history"]).length}"
                          : "${engine.dict.value("updated")} ${timeAgo(chat["updated"]).split(" ")[0]} ${engine.dict.value(timeAgo(chat["updated"]).split(" ")[1])} ${engine.dict.value("ago")}, ${engine.dict.value("messages")}: ${jsonDecode(chat["history"]).length}",
                      action: (engine.isLoading && !(engine.currentChat == key))?(){}:() async {
                        if(!engine.isLoading){
                          engine.prompt.text = "";
                          engine.responseText = "";
                        }
                        engine.contextSize = int.parse(chat["tokens"]);
                        engine.context = jsonDecode(chat["history"]);
                        engine.currentChat = key;
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => ChatPage()),
                        );
                      },
                      icon: Icons.tune_rounded,
                      secondAction: (engine.isLoading && !(engine.currentChat == key))?(){}:(){
                        engine.isLoading = false;
                        engine.context.clear();
                        engine.contextSize = 0;
                        engine.context = jsonDecode(chat["history"]);
                        engine.currentChat = key;
                        showModalBottomSheet<void>(
                            context: context,
                            barrierLabel: chat["name"],
                            isScrollControlled: false,
                            enableDrag: true,
                            useSafeArea: true,
                            showDragHandle: true,
                            builder: (BuildContext topContext) {
                              return ChatSettingsPage();
                            }
                        );
                      }
                  );
                }
                return Scaffold(
                  floatingActionButton: FloatingActionButton.extended(
                    icon: Icon(Icons.add_rounded),
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    isExtended: true,
                    label: Text(engine.dict.value("new_chat")),
                    enableFeedback: true,
                    tooltip: engine.dict.value("new_chat"),
                    onPressed: engine.isLoading?(){}:(){
                      engine.currentChat = "0";
                      engine.context.clear();
                      engine.contextSize = 0;
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => ChatPage()),
                      );
                    },
                  ),
                  body: CustomScrollView(
                    slivers: <Widget>[
                      SliverAppBar.large(
                        surfaceTintColor: Colors.transparent,
                        title: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(engine.dict.value("title")),
                            Padding(
                              padding: EdgeInsetsGeometry.symmetric(
                                  vertical: 50,
                                  horizontal: 10
                              ),
                              child: Chip(
                                label: Text(
                                  engine.modelInfo["version"]??"Loading...",
                                  style: TextStyle(
                                  ),
                                ),
                                labelPadding: EdgeInsets.symmetric(
                                    horizontal: 5
                                ),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                backgroundColor: Theme.of(context).colorScheme.onPrimaryFixed,
                                surfaceTintColor: Colors.transparent,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadiusGeometry.circular(20),
                                    side: BorderSide(
                                        color: Colors.transparent
                                    )
                                ),
                              ),
                            ),
                          ],
                        ),
                        actions: [
                          IconButton(
                            onPressed: (){
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => SettingsPage()),
                              );
                            },
                            tooltip: engine.dict.value("settings"),
                            icon: Icon(Icons.settings_rounded),
                          )
                        ],
                        pinned: true,
                      ),
                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if(engine.isLoading && engine.currentChat == "0")Category.settings(
                                  title: engine.dict.value("new_chat"),
                                  context: context
                              ),
                            if(engine.isLoading && engine.currentChat == "0")cards.cardGroup([CardContents.tap(
                              action: (){
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => ChatPage()),
                                );
                              },
                                title: engine.dict.value("loading"),
                                subtitle: engine.dict.value("generating_hint").replaceAll("%seconds%", ((engine.response.generationTimeMs??10)/1000).toStringAsFixed(2)).replaceAll("%tokens%", engine.response.tokenCount.toString()).replaceAll("%tokenspersec%", (engine.response.tokenCount!.toInt()/((engine.response.generationTimeMs??10)/1000)).toStringAsFixed(2))
                            )]),

                            if(engine.chats.keys.toList().map((key){
                              Map chat = engine.chats[key]??{
                                "name": "Nonameyet",
                                "tokens":  "0",
                                "history": {},
                                "created": DateTime.now().millisecondsSinceEpoch.toString(),
                                "updated": DateTime.now().millisecondsSinceEpoch.toString()
                              };
                              if(chat["pinned"]??false){return Container();}
                            }).toList().whereNot((crd) => crd == null).isNotEmpty)Category.settings(
                                title: engine.dict.value("pinned_chats"),
                                context: context
                            ),
                            cards.cardGroup(
                                <Widget>[
                                  ...engine.chats.keys.toList().reversed.map((key){
                                    Map chat = engine.chats[key]??{
                                      "name": "Nonameyet",
                                      "tokens":  "0",
                                      "history": {},
                                      "created": DateTime.now().millisecondsSinceEpoch.toString(),
                                      "updated": DateTime.now().millisecondsSinceEpoch.toString()
                                    };
                                    if(chat["pinned"]??false){return chatCard(chat,key);}
                                  }).toList().whereNot((crd) => crd == null).cast<Widget>(),
                                ]
                            ),
                            if(engine.chats.keys.toList().map((key){
                              Map chat = engine.chats[key]??{
                                "name": "Nonameyet",
                                "tokens":  "0",
                                "history": {},
                                "created": DateTime.now().millisecondsSinceEpoch.toString(),
                                "updated": DateTime.now().millisecondsSinceEpoch.toString()
                              };
                              if(chat["pinned"]??false){return Container();}
                            }).toList().whereNot((crd) => crd == null).isNotEmpty)Category.settings(
                                title: engine.dict.value("other_chats"),
                                context: context
                            ),
                            if(engine.chats.keys.toList().map((key){
                              Map chat = engine.chats[key]??{
                                "name": "Nonameyet",
                                "tokens":  "0",
                                "history": {},
                                "created": DateTime.now().millisecondsSinceEpoch.toString(),
                                "updated": DateTime.now().millisecondsSinceEpoch.toString()
                              };
                              if(chat["pinned"]??false){return Container();}
                            }).toList().whereNot((crd) => crd == null).isEmpty)Category.settings(
                                title: engine.dict.value("your_chats"),
                                context: context
                            ),
                            cards.cardGroup(
                              <Widget>[
                                ...engine.chats.keys.toList().reversed.map((key){
                                  Map chat = engine.chats[key]??{
                                    "name": "Nonameyet",
                                    "tokens":  "0",
                                    "history": {},
                                    "created": DateTime.now().millisecondsSinceEpoch.toString(),
                                    "updated": DateTime.now().millisecondsSinceEpoch.toString()
                                  };
                                  if(!(chat["pinned"]??false)){return chatCard(chat,key);}
                                }).toList().whereNot((crd) => crd == null).cast<Widget>(),
                              ]
                            ),
                            text.info(
                                title: engine.isLoading?engine.dict.value("still_generating"):engine.dict.value(engine.chats.isEmpty?"no_chats":"chats_desc").replaceAll("%chatnum%", engine.chats.length.toString()),
                                subtitle: engine.chats.isEmpty?engine.dict.value("new_chat"):"",
                                action: engine.chats.isNotEmpty?(){}:engine.isLoading?(){}:(){
                                  engine.currentChat = "0";
                                  engine.context.clear();
                                  engine.contextSize = 0;
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (context) => ChatPage()),
                                  );
                                  },
                                context: context
                            ),
                            SizedBox(height: 75,)
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