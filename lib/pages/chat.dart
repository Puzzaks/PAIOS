import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geminilocal/pages/settings.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../engine.dart';
import 'support/elements.dart';


class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  @override
  ChatPageState createState() => ChatPageState();
}

class ChatPageState extends State<ChatPage> {
  text tWid = text();
  @override
  @override
  void initState() {
    super.initState();
  }
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          double scaffoldWidth = constraints.maxWidth;
          return Consumer<AIEngine>(builder: (context, engine, child) {
            return Scaffold(
              appBar: AppBar(
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
                  if(!(engine.responseText==""))IconButton(
                    icon: Icon(Icons.share_rounded),
                    tooltip: engine.dict.value("share"),
                    onPressed: engine.isLoading?null:() {
                      SharePlus.instance.share(
                          ShareParams(
                              title: engine.dict.value("share"),
                              text: engine.responseText
                          )
                      );
                    },
                  ),
                  if(engine.context.isNotEmpty)IconButton(
                    icon: Icon(Icons.delete_outline_rounded),
                    tooltip: engine.dict.value("clear_context"),
                    onPressed: engine.isLoading?null:() {
                      Fluttertoast.showToast(
                          msg: engine.dict.value("long_tap_clear"),
                          toastLength: Toast.LENGTH_SHORT,
                          fontSize: 16.0
                      );
                    },
                    onLongPress: (){
                      engine.clearContext();
                      Fluttertoast.showToast(
                          msg: engine.dict.value("long_tap_cleared"),
                          toastLength: Toast.LENGTH_SHORT,
                          fontSize: 16.0
                      );
                    },
                  ),
                  IconButton(
                    onPressed: (){
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => SettingsPage()),
                      );
                    },
                    tooltip: engine.dict.value("settings"),
                    icon: Icon(Icons.tune_rounded),
                  )
                ],
                actionsPadding: EdgeInsets.only(right:10),
              ),
              body: Builder(
                  builder: (context) {
                    return SafeArea(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          SizedBox(height: 10,),
                          Expanded(
                            child: Card(
                              clipBehavior: Clip.hardEdge,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.all(
                                    Radius.circular(30)
                                ),
                              ),
                              color: Theme.of(context).colorScheme.onPrimaryFixed,
                              child: SizedBox(
                                width: scaffoldWidth - 30,
                                child: Stack(
                                  children: [
                                    SingleChildScrollView(
                                      controller: engine.scroller,
                                      scrollDirection: Axis.vertical,
                                      child: Padding(
                                        padding: EdgeInsets.symmetric(
                                            vertical: 5,
                                            horizontal: 5
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            (engine.context.isEmpty && !engine.isLoading)
                                            ? Column(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Column(
                                                  children: tWid.chatlog(
                                                      conversation: [
                                                        {
                                                          "user": "User",
                                                          "message": engine.dict.value("mock_user_1")
                                                        },
                                                        {
                                                          "user": "Gemini",
                                                          "message": engine.dict.value("mock_gemini_1")
                                                        },
                                                        {
                                                          "user": "User",
                                                          "message": engine.dict.value("mock_user_2")
                                                        },
                                                        {
                                                          "user": "Gemini",
                                                          "message": engine.dict.value("mock_gemini_2")
                                                        },
                                                        {
                                                          "user": "User",
                                                          "message": engine.dict.value("mock_user_3")
                                                        },
                                                        {
                                                          "user": "Gemini",
                                                          "message": engine.dict.value("mock_gemini_3")
                                                        }
                                                      ],
                                                      context: context,
                                                      aiChunk: "",
                                                      lastUser: ""
                                                  ),
                                                ),
                                                text.infoShort(
                                                    title: engine.dict.value("welcome"),
                                                    context: context,
                                                    subtitle: "",
                                                    action: (){}
                                                )
                                              ],
                                            )
                                            : Column(
                                              children: tWid.chatlog(
                                                  conversation: engine.context,
                                                  context: context,
                                                  aiChunk: engine.responseText,
                                                  lastUser: engine.lastPrompt
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Column(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Container(),
                                        engine.isLoading
                                            ? Padding(
                                          padding: EdgeInsetsGeometry.symmetric(
                                              horizontal: 10,
                                              vertical: 0
                                          ),
                                          child: LinearProgressIndicator(
                                            borderRadius: BorderRadius.circular(20),
                                            value: engine.responseText == ""
                                                ? null
                                                : (engine.response.tokenCount!/engine.tokens)*1.25,
                                          ),
                                        )
                                            : Container()
                                      ],
                                    )
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 20
                            ),
                            child: TextField(
                              controller: engine.prompt,
                              autofocus: true,
                              onChanged: (change){engine.scrollChatlog(Duration(milliseconds: 250));},
                              onTap: () async {
                                engine.scrollChatlog(Duration(milliseconds: 250));
                                await Future.delayed(Duration(milliseconds: 500));
                                engine.scrollChatlog(Duration(milliseconds: 500));
                                },
                              readOnly: engine.isLoading,
                              decoration: InputDecoration(
                                isDense: true,
                                suffixIcon: engine.isLoading
                                  ? IconButton(
                                      icon: Icon(Icons.stop_rounded, size: 25,),
                                      tooltip: engine.dict.value("cancel_generate"),
                                      onPressed: (){engine.cancelGeneration();},
                                    )
                                  : IconButton(
                                      icon: Icon(Icons.send_rounded, size: 25,),
                                      tooltip: engine.dict.value("generate"),
                                      onPressed: (){engine.generateStream();},
                                    ),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.all(Radius.circular(20))
                                ),
                                hintText: engine.dict.value("prompt"),
                                alignLabelWithHint: true,
                                helperText: engine.isLoading && !(engine.responseText == "")
                                  ? engine.dict.value("generating_hint").replaceAll("%seconds%", ((engine.response.generationTimeMs??10)/1000).toStringAsFixed(2)).replaceAll("%tokens%", engine.response.tokenCount.toString()).replaceAll("%tokenspersec%", (engine.response.tokenCount!.toInt()/((engine.response.generationTimeMs??10)/1000)).toStringAsFixed(2))
                                  : engine.responseText==""
                                    ? engine.dict.value("no_context_yet")
                                    : engine.dict.value("generated_hint").replaceAll("%seconds%", ((engine.response.generationTimeMs??10)/1000).toStringAsFixed(2)).replaceAll("%tokens%", engine.response.text.split(" ").length.toString()).replaceAll("%tokenspersec%", (engine.response.tokenCount!.toInt()/((engine.response.generationTimeMs??10)/1000)).toStringAsFixed(2)),
                              ),
                              maxLines: 3,
                              minLines: 1,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
              ),
            );
          });
        }
    );
  }
}