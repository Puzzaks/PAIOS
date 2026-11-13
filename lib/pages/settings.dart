import 'package:flutter/material.dart';
import 'package:geminilocal/pages/settings/logs.dart';
import 'package:geminilocal/pages/settings/prompts.dart';
import 'package:geminilocal/pages/settings/resources.dart';
import 'package:geminilocal/storage/file_access_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:m3x/m3x.dart' hide Cards, CardContents, Category, TextPart, text, Dictionary, AnalyticsService, GitHubExplorerPage;
import '../engine.dart';
import 'github_explorer_page.dart';
import 'support/elements.dart';
import 'package:geminilocal/pages/settings/model.dart';
import 'package:geminilocal/pages/settings/doc_explorer.dart';
import 'package:geminilocal/pages/settings/extensions.dart';


class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  SettingsPageState createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> {
  String? _promptDirPath;
  bool _isDefaultAssistant = false;
  bool _hasRequestedReview = false;

  @override
  void initState() {
    super.initState();
    _loadPromptDirPath();
    _checkAssistantStatus();
    _checkReviewStatus();
  }

  void _checkReviewStatus() {
    try {
      final box = Hive.box('paios_storage');
      final hasReview = box.get('hasRequestedReview', defaultValue: false) == true;
      if (mounted) setState(() => _hasRequestedReview = hasReview);
    } catch (_) {}
  }

  Future<void> _checkAssistantStatus() async {
    try {
      final isDef = await Provider.of<AIEngine>(context, listen: false).gemini.isDefaultAssistant();
      if (mounted) setState(() => _isDefaultAssistant = isDef);
    } catch (_) {}
  }

  Future<void> _openPlayStoreReview() async {
    try {
      final box = Hive.box('paios_storage');
      await box.put('hasRequestedReview', true);
      if (mounted) setState(() => _hasRequestedReview = true);
    } catch (_) {}

    try {
      final inAppReview = InAppReview.instance;
      if (await inAppReview.isAvailable()) {
        await inAppReview.requestReview();
      } else {
        await _launchStoreFallback();
      }
    } catch (_) {
      await _launchStoreFallback();
    }
  }

  Future<void> _launchStoreFallback() async {
    final selfPkg = AIEngine.canonicalExtensionId('paios');
    try {
      final marketUri = Uri.parse('market://details?id=$selfPkg');
      final webUri = Uri.parse('https://play.google.com/store/apps/details?id=$selfPkg');
      final launched = await launchUrl(marketUri, mode: LaunchMode.externalApplication);
      if (!launched) {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      try {
        final webUri = Uri.parse('https://play.google.com/store/apps/details?id=$selfPkg');
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
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
                        child: MotionBlurContainer(
                          child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SettingsBentoHeader(
                              appName: M3x.appName.isNotEmpty
                                  ? M3x.appName
                                  : engine.dict.value("title"),
                              subtitle: M3x.appDescription,
                              icon: Icons.hexagon_rounded,
                              versionDisplay: M3x.versionDisplay,
                              onVersionTap: () => _showChangelogDialog(context, engine),
                              onModulesTap: () => _showModulesDialog(context, engine),
                            ),
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
                                                            await engine.dict.saveLanguage(language["id"]);
                                                            if (!mounted) return;
                                                            setState(() {});
                                                            if (!dialogContext.mounted) return;
                                                            Navigator.of(dialogContext).pop();
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
                                    if (!mounted) return;
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
                                  title: engine.dict.value("extensions"),
                                  subtitle: engine.dict.value("extensions_desc"),
                                  icon: Icons.extension_rounded,
                                  colorBG: Theme.of(context).colorScheme.primaryContainer,
                                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                                  action: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => const ExtensionsSettingsPage(),
                                      ),
                                    );
                                  }
                              ),
                              CardContents.turn(
                                  title: engine.dict.value("auto_archive_assistant"),
                                  subtitle: engine.dict.value("auto_archive_assistant_desc"),
                                  action: (){
                                    setState(() {
                                      engine.autoArchiveAssistantChats = !engine.autoArchiveAssistantChats;
                                    });
                                    engine.saveSettings();
                                  },
                                  switcher: (value){
                                    setState(() {
                                      engine.autoArchiveAssistantChats = value;
                                    });
                                    engine.saveSettings();
                                  },
                                  value: engine.autoArchiveAssistantChats
                              ),
                              if (!_isDefaultAssistant)
                                CardContents.tapIcon(
                                    title: engine.dict.value("set_as_default_assistant"),
                                    subtitle: engine.dict.value("set_as_default_assistant_desc"),
                                    icon: Icons.assistant_rounded,
                                    colorBG: Theme.of(context).colorScheme.primaryContainer,
                                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                                    action: () async {
                                      await engine.gemini.openAssistantSettings();
                                      await Future.delayed(const Duration(seconds: 1));
                                      _checkAssistantStatus();
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
                              ),
                              CardContents.tapIcon(
                                  title: engine.dict.value("gh_repo"),
                                  subtitle: engine.dict.value("gh_repo_desc"),
                                  icon: Icons.explore_rounded,
                                  colorBG: Theme.of(context).colorScheme.primaryFixedDim,
                                  color: Theme.of(context).colorScheme.onPrimaryFixed,
                                  action: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => const GitHubExplorerPage(),
                                        settings: const RouteSettings(name: 'GitHubExplorerPage'),
                                      ),
                                    );
                                  }
                              ),
                              CardContents.tapIcon(
                                  title: engine.dict.value("doc_explorer_title"),
                                  subtitle: engine.dict.value("doc_explorer_desc"),
                                  icon: Icons.menu_book_rounded,
                                  colorBG: Theme.of(context).colorScheme.primaryFixedDim,
                                  color: Theme.of(context).colorScheme.onPrimaryFixed,
                                  action: () => DocExplorerPage.open(context),
                              ),
                              if (!_hasRequestedReview)
                                CardContents.tapIcon(
                                    title: engine.dict.value("review_play_store"),
                                    subtitle: engine.dict.value("review_play_store_desc"),
                                    icon: Icons.star_rate_rounded,
                                    colorBG: Theme.of(context).colorScheme.primaryFixedDim,
                                    color: Theme.of(context).colorScheme.onPrimaryFixed,
                                    action: _openPlayStoreReview
                                ),
                            ]),
                            Category.settings(
                                title: engine.dict.value("settings_ai"),
                                context: context
                            ),
                            cards.cardGroup([
                              CardContents.tapIcon(
                                  title: engine.dict.value("settings_ai"),
                                  subtitle: engine.isAICoreBeta
                                      ? "${engine.dict.value("settings_ai_desc")} (${engine.dict.value("aicore_beta_badge")})"
                                      : engine.dict.value("settings_ai_desc"),
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
                                  subtitle: engine.promptData.getPromptName(engine.config.defaultPromptId),
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
                            text.info(
                                title: engine.dict.value("prompt_dir_desc"),
                                context: context,
                                subtitle: "",
                                action: () {}
                            )
                          ],
                        ),
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

  void _showChangelogDialog(BuildContext context, AIEngine engine) {
    SettingsBentoHeader.showChangelogDialog(
      context,
      title: engine.dict.value("changelog"),
      subtitle: M3x.versionDisplay,
      changelogContent: M3x.changelogContent.isNotEmpty ? M3x.changelogContent : null,
      emptyMessage: engine.dict.value("no_changelog"),
      icon: Icons.history_rounded,
    );
  }

  void _showModulesDialog(BuildContext context, AIEngine engine) {
    final deps = M3x.dependencies;
    SettingsBentoHeader.showDependenciesDialog(
      context,
      title: '${engine.dict.value("installed_packages")} (${deps.length})',
      subtitle: engine.dict.value("installed_packages_desc"),
      workspaceBadge: engine.dict.value("package_workspace"),
      pubBadge: engine.dict.value("package_pub"),
      dependencies: deps,
      onPackageTap: (name, spec, isWorkspace) {
        if (!isWorkspace) {
          launchUrl(
            Uri.parse('https://pub.dev/packages/$name'),
            mode: LaunchMode.externalApplication,
          );
        }
      },
    );
  }
}
