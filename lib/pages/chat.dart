import 'dart:ui';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:geminilocal/pages/settings.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../engine.dart';
import '../elements.dart';
import 'package:flutter_markdown/flutter_markdown.dart';


class chatPage extends StatefulWidget {
  const chatPage({super.key});
  @override
  chatPageState createState() => chatPageState();
}

class chatPageState extends State<chatPage> {
  text tWid = text();
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
    return LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          double scaffoldHeight = constraints.maxHeight;
          double scaffoldWidth = constraints.maxWidth;
          return Consumer<aiEngine>(builder: (context, engine, child) {
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
                        labelPadding: EdgeInsets.all(0),
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
                  IconButton(
                    icon: Icon(Icons.delete_outline_rounded),
                    tooltip: engine.dict.value("clear_context"),
                    onPressed: engine.isLoading?null:() {
                      engine.clearContext();
                    },
                  ),
                  IconButton(
                    onPressed: (){
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => settingsPage()),
                      );
                    },
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
                              child: Container(
                                width: scaffoldWidth - 30,
                                child: SingleChildScrollView(
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
                                        Column(
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
                              ),
                            ),
                          ),
                          SizedBox(height: 10,),
                          Padding(
                            padding: EdgeInsetsGeometry.symmetric(horizontal: 20),
                            child: Text("Context: ${engine.context.split(" ").length}"),
                          ),
                          SizedBox(height: 10,),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 20
                            ),
                            child: TextField(
                              controller: engine.prompt,
                              autofocus: true,
                              onChanged: (change){engine.scrollChatlog(Duration(milliseconds: 250));},
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
                                labelText: engine.dict.value("prompt"),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.all(Radius.circular(20))
                                ),
                                hintText: engine.dict.value("prompt_hint"),
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