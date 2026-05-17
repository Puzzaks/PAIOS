import 'package:flutter/material.dart';
import 'package:geminilocal/pages/settings/prompt_editor.dart';
import 'package:provider/provider.dart';
import '../../engine.dart';
import '../support/elements.dart';
import 'package:geminilocal/pages/settings/prompt_viewer.dart';

class PromptsPage extends StatefulWidget {
  const PromptsPage({super.key});
  @override
  PromptsPageState createState() => PromptsPageState();
}

class PromptsPageState extends State<PromptsPage> {
  @override
  Widget build(BuildContext context) {
    return PopScope(
        canPop: true,
        child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              Cards cards = Cards(context: context);
              return Consumer<AIEngine>(builder: (context, engine, child) {
                String activeId = engine.config.defaultPromptId;

                return Scaffold(
                  floatingActionButton: FloatingActionButton.extended(
                    icon: Icon(Icons.add_rounded),
                    label: Text(engine.dict.value("create_prompt_custom")),
                    onPressed: () {
                       String customId = "user_${DateTime.now().millisecondsSinceEpoch}";
                       engine.promptData.addUserPrompt(customId, engine.dict.value("new_prompt_name"), "", "User");
                       Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => PromptEditorPage(promptId: customId),
                          settings: const RouteSettings(name: 'PromptEditorPage')),
                       );
                    },
                  ),
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
                        title: Text(engine.dict.value("prompt_manager_title")),
                        pinned: true,
                      ),
                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Default / system prompts ───────────────────────
                            Category.settings(
                                title: engine.dict.value("default_prompts_title"),
                                context: context
                            ),
                            cards.cardGroup([
                              ...engine.promptData.defaultPrompts.keys.map((key) {
                                Map prompt = engine.promptData.defaultPrompts[key];
                                bool isSelected = (key == activeId);
                                return CardContents.doubleTap(
                                    title: engine.promptData.getPromptDisplayName(key, engine.dict.locale),
                                    subtitle: engine.dict.value("by_author").replaceAll("%author%", prompt["author"] ?? "Google"),
                                    action: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (context) => PromptViewerPage(promptId: key),
                                            settings: const RouteSettings(name: 'PromptViewerPage')),
                                      );
                                    },
                                    icon: isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                    secondAction: () {
                                      setState(() {
                                        engine.config.defaultPromptId = key;
                                      });
                                      engine.saveSettings();
                                    }
                                );
                              }).toList().cast<Widget>(),
                            ]),

                            // ── User prompts ───────────────────────────────────
                            Category.settings(
                                title: engine.dict.value("user_prompts_title"),
                                context: context
                            ),
                            cards.cardGroup([
                              ...engine.promptData.userPrompts.keys.map((key) {
                                Map prompt = engine.promptData.userPrompts[key];
                                bool isSelected = (key == activeId);
                                return CardContents.doubleTap(
                                    title: prompt["name"] ?? "Custom",
                                    subtitle: "",
                                    action: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (context) => PromptViewerPage(promptId: key),
                                            settings: const RouteSettings(name: 'PromptViewerPage')),
                                      );
                                    },
                                    icon: isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                    secondAction: () {
                                      setState(() {
                                        engine.config.defaultPromptId = key;
                                      });
                                      engine.saveSettings();
                                    }
                                );
                              }).toList().cast<Widget>(),
                              if(engine.promptData.userPrompts.isEmpty)
                                CardContents.tap(
                                    title: engine.dict.value("no_user_prompts"),
                                    subtitle: engine.dict.value("no_user_prompts_desc"),
                                    action: () {
                                      String customId = "user_${DateTime.now().millisecondsSinceEpoch}";
                                      engine.promptData.addUserPrompt(customId, engine.dict.value("new_prompt_name"), "", "User");
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (context) => PromptEditorPage(promptId: customId),
                                            settings: const RouteSettings(name: 'PromptEditorPage')),
                                      );
                                    }
                                )
                            ]),
                            TextBlocks.infoShort(
                               title: engine.dict.value("prompt_manager_info"),
                               subtitle: "",
                               action: () {},
                               context: context,
                             ),
                            SizedBox(height: 75)
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
