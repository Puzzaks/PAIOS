import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../engine.dart';
import '../support/elements.dart';

class PromptEditorPage extends StatefulWidget {
  final String promptId;
  const PromptEditorPage({super.key, required this.promptId});
  @override
  PromptEditorPageState createState() => PromptEditorPageState();
}

class PromptEditorPageState extends State<PromptEditorPage> {
  late TextEditingController contentController;
  late TextEditingController nameController;
  List recentTitles = [];

  @override
  void initState() {
    super.initState();
    contentController = TextEditingController();
    nameController = TextEditingController();
    
    // Retrieve initial data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final engine = Provider.of<AIEngine>(context, listen: false);
      contentController.text = engine.promptData.getPromptContent(widget.promptId);
      nameController.text = engine.promptData.getPromptName(widget.promptId);
    });
  }

  @override
  void dispose() {
    contentController.dispose();
    nameController.dispose();
    super.dispose();
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
                    title: Text(engine.promptData.getPromptName(widget.promptId)),
                    actions: [
                      IconButton(
                        onPressed: () {
                           engine.promptData.deleteUserPrompt(widget.promptId);
                           Navigator.pop(context);
                        },
                        icon: Icon(Icons.delete_rounded),
                        tooltip: engine.dict.value("delete"),
                      ),
                      IconButton(
                        onPressed: () async {
                           final currentName = engine.promptData.getPromptName(widget.promptId);
                           final defaultName = engine.dict.value("new_prompt_name");
                           // Always save content immediately so nothing is lost
                           await engine.promptData.addUserPrompt(
                             widget.promptId,
                             currentName,
                             contentController.text,
                             "User",
                           );
                           Fluttertoast.showToast(msg: engine.dict.value("saved"));
                           // If name is still the default sentinel, auto-generate one
                           if (currentName == defaultName) {
                             setState(() { engine.isLoading = true; });
                             final oldName = engine.promptData.getPromptName(widget.promptId);
                             if (!recentTitles.contains(oldName)) recentTitles.add(oldName);
                             String newTitle = defaultName;
                             await engine.generatePromptTitle(contentController.text).then((output) {
                               if (output.isNotEmpty) newTitle = output.replaceAll('"', '');
                             });
                             await engine.promptData.addUserPrompt(
                               widget.promptId,
                               newTitle,
                               contentController.text,
                               "User",
                             );
                             setState(() { engine.isLoading = false; });
                           }
                        },
                        icon: Icon(Icons.save_rounded),
                        tooltip: engine.dict.value("save"),
                      ),
                    ],
                  ),
                  body: CustomScrollView(
                    slivers: <Widget>[
                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            cards.cardGroup([
                              if(!engine.isLoading)
                                CardContents.doubleTap(
                                    title: engine.promptData.getPromptName(widget.promptId),
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
                                                    String oldName = recentTitles[i];
                                                    recentTitles.remove(recentTitles[i]);
                                                    Navigator.of(context).pop();
                                                    setState(() {
                                                      engine.promptData.addUserPrompt(
                                                        widget.promptId, 
                                                        oldName, 
                                                        contentController.text, 
                                                        "User"
                                                      );
                                                    });
                                                  }
                                              )
                                          );
                                        }
                                      }
                                      nameController.text = engine.promptData.getPromptName(widget.promptId);
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
                                                                controller: nameController,
                                                                autofocus: true,
                                                                keyboardType: TextInputType.text,
                                                                decoration: InputDecoration(
                                                                  labelText: engine.dict.value("prompt_name"),
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
                                                                  if(nameController.text.isEmpty){
                                                                    Fluttertoast.showToast(
                                                                        msg: engine.dict.value("name_wrong"),
                                                                        toastLength: Toast.LENGTH_SHORT,
                                                                        fontSize: 16.0
                                                                    );
                                                                  }else {
                                                                    setState(() {
                                                                      engine.promptData.addUserPrompt(
                                                                         widget.promptId, 
                                                                         nameController.text.trim(), 
                                                                         contentController.text, 
                                                                         "User"
                                                                      );
                                                                    });
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
                                      String oldName = engine.promptData.getPromptName(widget.promptId);
                                      if(!recentTitles.contains(oldName)){
                                        recentTitles.add(oldName);
                                      }
                                      await engine.generatePromptTitle(contentController.text).then((output){
                                        newTitle = output.replaceAll('"', '');
                                      });
                                      setState(() {
                                        engine.promptData.addUserPrompt(
                                           widget.promptId, 
                                           newTitle, 
                                           contentController.text, 
                                           "User"
                                        );
                                        engine.isLoading = false;
                                      });
                                    }
                                ),
                              if(engine.isLoading)
                                CardContents.progress(
                                    title: engine.dict.value("generating_title"),
                                    subtitle: "",
                                    subsubtitle: "",
                                    progress: 0
                                )
                            ]),
                            Padding(
                                padding: EdgeInsets.all(15),
                                child: TextField(
                                    controller: contentController,
                                    maxLines: null,
                                    minLines: 15,
                                    decoration: InputDecoration(
                                      hintText: engine.dict.value("prompt_content_hint"),
                                      border: OutlineInputBorder(
                                          borderRadius: BorderRadius.all(Radius.circular(20)),
                                      ),
                                    ),
                                    onChanged: (val) {
                                       // we can optionally auto-save, but let's rely on save button.
                                    },
                                )
                            ),
                            TextBlocks.infoShort(
                              title: engine.dict.value("prompt_md_desc"),
                              subtitle: engine.dict.value("prompt_md_docs_link"),
                              action: () async {
                                await launchUrl(
                                    Uri.parse('https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax'),
                                    mode: LaunchMode.externalApplication
                                );
                              },
                              context: context,
                            ),
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
