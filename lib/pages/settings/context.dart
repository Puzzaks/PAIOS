import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../engine.dart';
import '../support/elements.dart';
import 'package:flutter_markdown/flutter_markdown.dart';


class ModelSettingsContext extends StatefulWidget {
  const ModelSettingsContext({super.key});
  @override
  ModelSettingsContextState createState() => ModelSettingsContextState();
}

class ModelSettingsContextState extends State<ModelSettingsContext> {
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
                        title: Text(engine.dict.value("system_prompt")),
                        pinned: true,
                      ),
                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20
                              ),
                              child: MarkdownBody(
                                onTapLink: (String text, String? href, String title) async {
                                  await launchUrl(
                                      Uri.parse(href!),
                                      mode: LaunchMode.externalApplication
                                  );
                                },
                                selectable: true,
                                data: engine.testPrompt.split("replaceme")[0],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20
                              ),
                              child: TextField(
                                controller: engine.instructions,
                                onChanged: (whatever){
                                  engine.saveSettings();
                                },
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
                                  hintText: engine.dict.value("instructions"),
                                ),
                                maxLines: 3,
                                minLines: 1,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20
                              ),
                              child: MarkdownBody(
                                onTapLink: (String text, String? href, String title) async {
                                  await launchUrl(
                                      Uri.parse(href!),
                                      mode: LaunchMode.externalApplication
                                  );
                                },
                                selectable: true,
                                data: engine.testPrompt.split("replaceme")[1],
                              ),
                            ),
                            text.info(
                                title: engine.dict.value("instructions_desc"),
                                context: context,
                                subtitle: engine.dict.value("recommend_changes_gh"),
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