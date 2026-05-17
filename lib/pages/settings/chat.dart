import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';
import '../../engine.dart';
import '../settings.dart';
import '../support/elements.dart';


class ChatSettingsPage extends StatefulWidget {
  const ChatSettingsPage({super.key});
  @override
  ChatSettingsPageState createState() => ChatSettingsPageState();
}

class ChatSettingsPageState extends State<ChatSettingsPage> {
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
                  leading: Container(),
                  leadingWidth: 0,
                  surfaceTintColor: Colors.transparent,
                  title: Text(engine.dict.value("chat_settings")),
                ),
                body: Builder(
                    builder: (context) {
                      return SingleChildScrollView(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (engine.currentChat != "0") Category.settings(
                                title: engine.dict.value("chat_settings"),
                                context: context
                            ),
                            if (engine.currentChat != "0") cards.cardGroup([
                              if(!engine.isLoading) CardContents.doubleTap(
                                    title: engine.chats[engine.currentChat]?["name"]??engine.dict.value("new_chat"),
                                    subtitle: engine.dict.value("change_name"),
                                    action: (){
                                      List<Widget> cardlist = [];
                                      if(recentTitles.isNotEmpty) {
                                        for (int i = 0; i < recentTitles.length; i++) {
                                          cardlist.add(
                                              CardContents.halfTap(
                                                  title: recentTitles[i],
                                                  subtitle: "",
                                                  action: () {
                                                    recentTitles.remove(recentTitles[i]);
                                                    Navigator.of(context).pop();
                                                    setState(() {
                                                      engine.chats[engine.currentChat]?["name"] = recentTitles[i];
                                                    });
                                                    engine.saveChats();
                                                  }
                                              )
                                          );
                                        }
                                      }
                                      engine.chatName.text = engine.chats[engine.currentChat]?["name"];
                                      showDialog(
                                        context: context,
                                        builder: (BuildContext newContext) => AlertDialog(
                                          contentPadding: EdgeInsets.symmetric(
                                              horizontal: 0,
                                              vertical: 15
                                          ),
                                          titlePadding: EdgeInsets.only(
                                              top: 20,
                                              right: 20,
                                              left: 20
                                          ),
                                          title: Text(engine.dict.value("edit_name")),
                                          content: Container(
                                              constraints:BoxConstraints(
                                                  minHeight: 0,
                                                  maxHeight: 300
                                              ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Padding(
                                                    padding: EdgeInsetsGeometry.symmetric(
                                                        horizontal: 15
                                                    ),
                                                    child: Row(
                                                        crossAxisAlignment: CrossAxisAlignment.center,
                                                        children: [
                                                          Expanded(
                                                              child: TextField(
                                                                controller: engine.chatName,
                                                                autofocus: true,
                                                                keyboardType: TextInputType.text,
                                                                decoration: InputDecoration(
                                                                  labelText: engine.dict.value("chat_name"),
                                                                  border: OutlineInputBorder(
                                                                      borderRadius: BorderRadius.all(Radius.circular(20)),
                                                                      borderSide: BorderSide(color: Colors.grey)
                                                                  ),
                                                                ),
                                                              )
                                                          ),
                                                          Padding(
                                                            padding: const EdgeInsets.only(left: 15),
                                                            child: IconButton(
                                                                onPressed: () async {
                                                                  if(engine.chatName.text.isEmpty){
                                                                    Fluttertoast.showToast(
                                                                        msg: engine.dict.value("name_wrong"),
                                                                        toastLength: Toast.LENGTH_SHORT,
                                                                        fontSize: 16.0
                                                                    );
                                                                  }else {
                                                                    setState(() {
                                                                      engine.chats[engine.currentChat]?["name"] = engine.chatName.text.trim();
                                                                    });
                                                                    engine.saveChats();
                                                                    Navigator.of(newContext).pop();
                                                                  }
                                                                },
                                                                icon: const Icon(Icons.save_rounded)
                                                            )
                                                            ,)
                                                        ]
                                                    ),
                                                  ),
                                                  if(cardlist.isNotEmpty)Category.settings(
                                                      title: engine.dict.value("previous_names"),
                                                      context: context
                                                  ),
                                                  if(cardlist.isNotEmpty)Container(
                                                    constraints: BoxConstraints(
                                                        minHeight: 0,
                                                        maxHeight: 194
                                                    ),
                                                    child: SingleChildScrollView(
                                                        child: cards.cardGroup(cardlist)
                                                    ),
                                                  )
                                                ],
                                              )
                                          ),
                                        ),
                                      );
                                    },
                                    icon: Icons.auto_awesome_rounded,
                                    secondAction: () async {
                                      String newTitle = "Generating...";
                                      setState(() {
                                        engine.isLoading = true;
                                      });
                                      if(!recentTitles.contains(engine.chats[engine.currentChat]?["name"])){
                                        recentTitles.add(engine.chats[engine.currentChat]?["name"]);
                                      }
                                      String composeConversation = "";
                                      if(jsonDecode(engine.chats[engine.currentChat]?["history"]).length > 2){
                                        for (var line in jsonDecode(engine.chats[engine.currentChat]?["history"])){
                                          composeConversation = "$composeConversation\n - ${line["message"]}";
                                        }
                                      }else{
                                        composeConversation = jsonDecode(engine.chats[engine.currentChat]?["history"])[0]["message"];
                                      }
                                      await engine.generateChatTitle(composeConversation).then((output){
                                        newTitle = output;
                                      });
                                      setState(() {
                                        engine.chats[engine.currentChat]!["name"] = newTitle;
                                        engine.isLoading = false;
                                      });
                                    }
                                ),
                              if(engine.isLoading) CardContents.progress(
                                    title: engine.dict.value("generating_title"),
                                    subtitle: "",
                                    subsubtitle: "",
                                    progress: 0
                                ),
                              if (engine.currentChat != "0") CardContents.turn(
                                  title: engine.dict.value("pin_chat"),
                                  subtitle: engine.dict.value("pin_chat_desc"),
                                  action: (){
                                    setState(() {
                                      engine.chats[engine.currentChat]?["pinned"] = !(engine.chats[engine.currentChat]?["pinned"]??false);
                                    });
                                    engine.saveChats();
                                  },
                                  switcher: (value){
                                    setState(() {
                                      engine.chats[engine.currentChat]?["pinned"] = !(engine.chats[engine.currentChat]?["pinned"]??false);
                                    });
                                    engine.saveChats();
                                  },
                                  value: engine.chats[engine.currentChat]?["pinned"]??false
                              ),
                              if (engine.context.isNotEmpty) CardContents.longTap(
                                  title: engine.dict.value("clear_context"),
                                  subtitle: engine.dict.value("context_desc").replaceAll("%c", engine.chats[engine.currentChat]?["tokens"]??"0"),
                                  action: () {
                                    Fluttertoast.showToast(
                                        msg: engine.dict.value("long_tap_clear"),
                                        toastLength: Toast.LENGTH_SHORT,
                                        fontSize: 16.0
                                    );
                                  },
                                  longAction: (){
                                    engine.clearContext();
                                    Fluttertoast.showToast(
                                        msg: engine.dict.value("long_tap_cleared"),
                                        toastLength: Toast.LENGTH_SHORT,
                                        fontSize: 16.0
                                    );
                                    Navigator.pop(context);
                                  }
                              )
                            ]),
                            Category.settings(
                                title: engine.dict.value("settings_ai"),
                                context: context
                            ),
                            cards.cardGroup([
                              CardContents.tap(
                                  title: engine.dict.value("chat_prompt"),
                                  subtitle: engine.promptData.getPromptDisplayName(engine.chats[engine.currentChat]?["promptId"] ?? engine.config.defaultPromptId, engine.dict.locale),
                                  action: () {
                                    showDialog(
                                        context: context,
                                        builder: (BuildContext dialogContext) => AlertDialog(
                                            title: Text(engine.dict.value("select_prompt")),
                                            content: Container(
                                                constraints: BoxConstraints(maxHeight: 300),
                                                child: SingleChildScrollView(
                                                    child: cards.cardGroup([
                                                      ...engine.promptData.defaultPrompts.keys.map((key) {
                                                        return CardContents.halfTap(
                                                            title: engine.promptData.getPromptDisplayName(key, engine.dict.locale),
                                                            subtitle: engine.dict.value("system_prompt"),
                                                            action: () {
                                                              setState(() {
                                                                engine.chats[engine.currentChat]!["promptId"] = key;
                                                              });
                                                              engine.saveChats();
                                                              Navigator.pop(dialogContext);
                                                            }
                                                        );
                                                      }).toList().cast<Widget>(),
                                                      ...engine.promptData.userPrompts.keys.map((key) {
                                                        return CardContents.halfTap(
                                                            title: engine.promptData.userPrompts[key]["name"] ?? "Custom",
                                                            subtitle: engine.dict.value("user_prompts_title"),
                                                            action: () {
                                                              setState(() {
                                                                engine.chats[engine.currentChat]!["promptId"] = key;
                                                              });
                                                              engine.saveChats();
                                                              Navigator.pop(dialogContext);
                                                            }
                                                        );
                                                      }).toList().cast<Widget>(),
                                                    ])
                                                )
                                            )
                                        )
                                    );
                                  }
                              ),
                              CardContents.addretract(
                                  title: engine.dict.value("temperature"),
                                  subtitle: (engine.chats[engine.currentChat]?["chatTemperature"] ?? engine.temperature).toStringAsFixed(1),
                                  actionAdd: (){
                                    if((engine.chats[engine.currentChat]?["chatTemperature"] ?? engine.temperature) < 0.9){
                                      setState(() {
                                        engine.chats[engine.currentChat]!["chatTemperature"] = (engine.chats[engine.currentChat]?["chatTemperature"] ?? engine.temperature) + 0.1;
                                      });
                                      engine.saveChats();
                                    }
                                  },
                                  actionRetract: (){
                                    if((engine.chats[engine.currentChat]?["chatTemperature"] ?? engine.temperature) > 0.1){
                                      setState(() {
                                        engine.chats[engine.currentChat]!["chatTemperature"] = (engine.chats[engine.currentChat]?["chatTemperature"] ?? engine.temperature) - 0.1;
                                      });
                                      engine.saveChats();
                                    }
                                  }
                              ),
                              CardContents.turn(
                                  title: engine.dict.value("add_time"),
                                  subtitle: engine.dict.value("add_time_desc"),
                                  action: (){
                                    setState(() {
                                      engine.chats[engine.currentChat]!["addCurrentTime"] = !(engine.chats[engine.currentChat]?["addCurrentTime"] ?? engine.addCurrentTimeToRequests);
                                    });
                                    engine.saveChats();
                                  },
                                  switcher: (value){
                                    setState(() {
                                      engine.chats[engine.currentChat]!["addCurrentTime"] = !(engine.chats[engine.currentChat]?["addCurrentTime"] ?? engine.addCurrentTimeToRequests);
                                    });
                                    engine.saveChats();
                                  },
                                  value: engine.chats[engine.currentChat]?["addCurrentTime"] ?? engine.addCurrentTimeToRequests
                              ),
                              CardContents.turn(
                                  title: engine.dict.value("add_lang"),
                                  subtitle: engine.dict.value("add_lang_desc"),
                                  action: (){
                                    setState(() {
                                      engine.chats[engine.currentChat]!["shareLocale"] = !(engine.chats[engine.currentChat]?["shareLocale"] ?? engine.shareLocale);
                                    });
                                    engine.saveChats();
                                  },
                                  switcher: (value){
                                    setState(() {
                                      engine.chats[engine.currentChat]!["shareLocale"] = !(engine.chats[engine.currentChat]?["shareLocale"] ?? engine.shareLocale);
                                    });
                                    engine.saveChats();
                                  },
                                  value: engine.chats[engine.currentChat]?["shareLocale"] ?? engine.shareLocale
                              ),
                            ]),
                            TextBlocks.info(
                                title: engine.dict.value("chat_settings_desc"),
                                subtitle: engine.dict.value("chat_settings_subtitle"),
                                action: (){
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (context) => SettingsPage(),
                                        settings: const RouteSettings(name: 'SettingsPage')),
                                  );
                                },
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
