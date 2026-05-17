import 'package:flutter/material.dart';
import 'package:geminilocal/pages/settings/logs.dart';
import 'package:geminilocal/pages/settings/prompts.dart';
import 'package:geminilocal/pages/settings/resources.dart';
import 'package:geminilocal/storage/file_access_service.dart';
import 'package:provider/provider.dart';
import '../engine.dart';
import 'support/elements.dart';
import 'package:geminilocal/pages/settings/model.dart';


class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  SettingsPageState createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> {
  String? _promptDirPath;

  @override
  void initState() {
    super.initState();
    _loadPromptDirPath();
  }

  Future<void> _loadPromptDirPath() async {
    final path = await FileAccessService.getDirectoryDisplayPath();
    if (mounted) setState(() => _promptDirPath = path);
  }
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
        child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              return Consumer<AIEngine>(builder: (context, engine, child) {
                Cards cards = engine.cards;
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
                        title: Text(engine.dict.value("settings")),
                        pinned: true,
                      ),
                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Category.settings(
                                title: engine.dict.value("settings_app"),
                                context: context
                            ),
                            cards.cardGroup([
                              CardContents.doubleTap(
                                  title: engine.dict.value("select_language"),
                                  subtitle: engine.dict.value("select_language_auto_long"),
                                  icon: Icons.app_settings_alt_rounded,
                                  action: () {
                                    showDialog(
                                      context: context,
                                      builder:
                                          (BuildContext dialogContext) =>
                                          AlertDialog(
                                            contentPadding: EdgeInsets.only(
                                              top: 10,
                                              bottom: 15,
                                            ),
                                            titlePadding: EdgeInsets.only(
                                                top: 20,
                                                right: 20,
                                                left: 20
                                            ),
                                            title: Text(engine.dict.value("select_language")),
                                            content: SingleChildScrollView(
                                                child: cards.cardGroup(
                                                    engine.dict.languages.map((language) {
                                                      return CardContents.halfTap(
                                                          title: language["origin"],
                                                          subtitle: language["name"] == language["origin"] ? "" : language["name"],
                                                          action: () async {
                                                            final navigator = Navigator.of(dialogContext);
                                                            await engine.dict.saveLanguage(language["id"]);
                                                            if (!mounted) return;
                                                            setState(() {});
                                                            navigator.pop();
                                                          }
                                                      );
                                                    }).toList().cast<Widget>()
                                                )
                                            ),
                                          ),
                                    );
                                  },
                                  secondAction: () async {
                                    await engine.dict.setSystemLanguage();
                                    setState(() {});
                                  }
                              ),
                              CardContents.turn(
                                  title: engine.dict.value("error_retry"),
                                  subtitle: engine.dict.value("error_retry_desc"),
                                  action: (){
                                    setState(() {
                                      engine.errorRetry = !engine.errorRetry;
                                    });
                                    engine.saveSettings();
                                  },
                                  switcher: (value){
                                    setState(() {
                                      engine.errorRetry = !engine.errorRetry;
                                    });
                                    engine.saveSettings();
                                  },
                                  value: engine.errorRetry
                              ),
                              CardContents.tapIcon(
                                  title: engine.dict.value("open_aicore_settings"),
                                  subtitle: engine.dict.value("in_play_store"),
                                  icon: Icons.android_rounded,
                                  colorBG: Theme.of(context).colorScheme.primaryFixedDim,
                                  color: Theme.of(context).colorScheme.onPrimaryFixed,
                                  action: () async {
                                    engine.gemini.openAICorePlayStore();
                                  }
                              ),
                              CardContents.tapIcon(
                                  title: engine.dict.value(engine.analytics?"logs_with_analytics":"logs_no_analytics"),
                                  subtitle: "",
                                  icon: Icons.checklist_rounded,
                                  colorBG: Theme.of(context).colorScheme.primaryFixedDim,
                                  color: Theme.of(context).colorScheme.onPrimaryFixed,
                                  action: (){
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => LogsPage(),
                                          settings: const RouteSettings(name: 'LogsPage')),
                                    );
                                  }
                              ),
                              CardContents.tapIcon(
                                  title: engine.dict.value("settings_resources"),
                                  subtitle: engine.dict.value("settings_resources_desc"),
                                  icon: Icons.dataset_linked_rounded,
                                  colorBG: Theme.of(context).colorScheme.primaryFixedDim,
                                  color: Theme.of(context).colorScheme.onPrimaryFixed,
                                  action: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => SettingsResources(),
                                        settings: const RouteSettings(name: 'SettingsResources'),
                                      ),
                                    );
                                  }
                              )
                            ]),
                            Category.settings(
                                title: engine.dict.value("settings_ai"),
                                context: context
                            ),
                            cards.cardGroup([
                              CardContents.tapIcon(
                                  title: engine.dict.value("settings_ai"),
                                  subtitle: engine.dict.value("settings_ai_desc"),
                                  icon: Icons.auto_awesome_rounded,
                                  colorBG: Theme.of(context).colorScheme.primaryFixedDim,
                                  color: Theme.of(context).colorScheme.onPrimaryFixed,
                                  action: (){
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => ModelSettings(),
                                          settings: const RouteSettings(name: 'ModelSettings')),
                                    );
                                  }
                              ),
                              CardContents.tapIcon(
                                  title: engine.dict.value("prompt_manager_title"),
                                  subtitle: engine.promptData.getPromptDisplayName(engine.config.defaultPromptId, engine.dict.locale),
                                  icon: Icons.edit_note_rounded,
                                  colorBG: Theme.of(context).colorScheme.primaryFixedDim,
                                  color: Theme.of(context).colorScheme.onPrimaryFixed,
                                  action: () async {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => PromptsPage(),
                                          settings: const RouteSettings(name: 'PromptsPage')),
                                    );
                                  }
                              ),
                              CardContents.tapIcon(
                                  title: engine.dict.value("prompt_dir_title"),
                                  subtitle: _promptDirPath ?? engine.dict.value("prompt_dir_none"),
                                  icon: Icons.folder_open_rounded,
                                  colorBG: Theme.of(context).colorScheme.primaryFixedDim,
                                  color: Theme.of(context).colorScheme.onPrimaryFixed,
                                  action: () async {
                                    final picked = await FileAccessService.pickDirectory();
                                    if (picked != null) {
                                      setState(() => _promptDirPath = picked);
                                    }
                                  }
                              ),
                            ]),
                            TextBlocks.info(
                                title: engine.dict.value("prompt_dir_desc"),
                                context: context,
                                subtitle: "",
                                action: () {}
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
