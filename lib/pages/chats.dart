import 'dart:convert';


import 'package:flutter/material.dart';
import 'package:geminilocal/pages/chat.dart';
import 'package:geminilocal/pages/archived_chats.dart';
import 'package:geminilocal/pages/settings.dart';
import 'package:geminilocal/pages/settings/chat.dart';
import 'package:provider/provider.dart';
import 'package:m3x_ui/m3x_ui.dart' show MotionBlurContainer;
import '../engine.dart';
import 'support/elements.dart';
import 'support/model_selector_dialog.dart';


class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key});
  @override
  ChatsPageState createState() => ChatsPageState();
}

class ChatsPageState extends State<ChatsPage> {
  bool isArchivedExpanded = false;

  String _modelVersionChipLabel(AIEngine engine) {
    final version = engine.modelInfo["version"]?.toString().trim();
    if (version != null && version.isNotEmpty && version != "null") {
      return version;
    }
    final status = engine.modelInfo["status"]?.toString().toLowerCase();
    final available = engine.modelInfo["available"];
    final statusCode = engine.modelInfo["statusCode"];
    final bool isUnavailable = !engine.isAiCoreAvailable ||
        status == "unavailable" ||
        available == false ||
        available?.toString().toLowerCase() == "false" ||
        (engine.modelInfo.isNotEmpty &&
            (statusCode == 0 || statusCode?.toString() == "0"));
    if (isUnavailable) {
      return engine.dict.value("aicore_unavailable");
    }
    return engine.dict.value("loading");
  }

  int _chatMessageCount(dynamic chat) {
    if (chat is! Map) return 0;
    final cachedCount = chat["messageCount"];
    if (cachedCount is int) return cachedCount;
    final rawHistory = chat["history"];
    if (rawHistory is String && rawHistory.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawHistory);
        if (decoded is List) return decoded.length;
      } catch (_) {}
    } else if (rawHistory is List) {
      return rawHistory.length;
    }
    return 0;
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
                  final String? rawName = chat["name"]?.toString();
                  final String displayTitle = (rawName == null || rawName.isEmpty)
                      ? engine.dict.value("loading")
                      : (rawName == "Still loading"
                          ? engine.dict.value("generating_title")
                          : rawName);
                  return CardContents.doubleTap(
                      title: displayTitle,
                      subtitle: (engine.isLoading && engine.currentChat == key)
                          ? engine.dict.value("generating_hint").replaceAll("%seconds%", ((engine.response.generationTimeMs??10)/1000).toStringAsFixed(2)).replaceAll("%tokens%", (engine.response.tokenCount ?? 0).toString()).replaceAll("%tokenspersec%", ((engine.response.tokenCount?.toInt() ?? 0)/((engine.response.generationTimeMs??10)/1000)).toStringAsFixed(2))
                          : "${engine.dict.value("updated")} ${formatTimeAgo(chat["updated"], engine.dict)}, ${engine.dict.value("messages")}: ${_chatMessageCount(chat)}",
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
                          MaterialPageRoute(builder: (context) => ChatPage(),
                              settings: const RouteSettings(name: 'ChatPage')),
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
                int getChatUpdated(dynamic key) {
                  final chat = engine.chats[key];
                  if (chat is Map && chat["updated"] != null) {
                    final u = chat["updated"];
                    if (u is int) return u;
                    if (u is String) return int.tryParse(u) ?? 0;
                  }
                  return 0;
                }

                final allValidKeys = engine.chats.keys
                    .where((k) => k != "testing" && k != "0")
                    .toList()
                  ..sort((a, b) => getChatUpdated(b).compareTo(getChatUpdated(a)));

                final pinnedChatKeys = allValidKeys.where((key) {
                  final chat = engine.chats[key];
                  return (chat is Map && (chat["pinned"] ?? false) == true);
                }).toList();

                final otherChatKeys = allValidKeys.where((key) {
                  final chat = engine.chats[key];
                  final isPinned = chat is Map && (chat["pinned"] ?? false) == true;
                  final isArchived = chat is Map && (chat["isArchived"] ?? false) == true;
                  return !isPinned && !isArchived;
                }).toList();

                final archivedChatKeys = allValidKeys.where((key) {
                  final chat = engine.chats[key];
                  final isPinned = chat is Map && (chat["pinned"] ?? false) == true;
                  final isArchived = chat is Map && (chat["isArchived"] ?? false) == true;
                  return !isPinned && isArchived;
                }).toList();

                return Scaffold(
                  floatingActionButton: FloatingActionButton.extended(
                    icon: Icon(Icons.add_rounded),
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    isExtended: true,
                    label: Text(engine.dict.value("new_chat")),
                    enableFeedback: true,
                    tooltip: engine.dict.value("new_chat"),
                    onPressed: engine.isLoading ? () {} : () {
                      engine.startNewChat();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChatPage(),
                          settings: const RouteSettings(name: 'ChatPage'),
                        ),
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
                            Flexible(
                              child: Padding(
                                padding: EdgeInsetsGeometry.symmetric(
                                    vertical: 50,
                                    horizontal: 10
                                ),
                                child: ActionChip(
                                  tooltip: engine.dict.value("model_selector_title"),
                                  onPressed: engine.isSwitchingModelConfig
                                      ? null
                                      : () {
                                          showModelSelectorDialog(
                                            context,
                                            engine,
                                            showModelSettingsLink: true,
                                          );
                                        },
                                  label: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          _modelVersionChipLabel(engine),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      if (engine.isSwitchingModelConfig)
                                        const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      else
                                        const Icon(
                                          Icons.keyboard_arrow_down_rounded,
                                          size: 16,
                                        ),
                                    ],
                                  ),
                                  labelPadding: const EdgeInsets.symmetric(
                                      horizontal: 5
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  backgroundColor: Theme.of(context).colorScheme.onPrimaryFixed,
                                  surfaceTintColor: Colors.transparent,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadiusGeometry.circular(20),
                                      side: const BorderSide(
                                          color: Colors.transparent
                                      )
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        actions: [
                          IconButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const ArchivedChatsPage(),
                                  settings: const RouteSettings(name: 'ArchivedChatsPage'),
                                ),
                              );
                            },
                            tooltip: engine.dict.value("archived_chats"),
                            icon: Badge(
                              isLabelVisible: archivedChatKeys.isNotEmpty,
                              label: Text(archivedChatKeys.length.toString()),
                              child: const Icon(Icons.archive_outlined),
                            ),
                          ),
                          IconButton(
                            onPressed: (){
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => SettingsPage(),
                                    settings: const RouteSettings(name: 'SettingsPage')),
                              );
                            },
                            tooltip: engine.dict.value("settings"),
                            icon: Icon(Icons.settings_rounded),
                          )
                        ],
                        pinned: true,
                      ),
                      SliverToBoxAdapter(
                        child: MotionBlurContainer(
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
                                    MaterialPageRoute(builder: (context) => ChatPage(),
                                        settings: const RouteSettings(name: 'ChatPage')),
                                  );
                                },
                                  title: engine.dict.value("loading"),
                                  subtitle: engine.dict.value("generating_hint").replaceAll("%seconds%", ((engine.response.generationTimeMs??10)/1000).toStringAsFixed(2)).replaceAll("%tokens%", (engine.response.tokenCount ?? 0).toString()).replaceAll("%tokenspersec%", ((engine.response.tokenCount?.toInt() ?? 0)/((engine.response.generationTimeMs??10)/1000)).toStringAsFixed(2))
                              )]),

                              if (pinnedChatKeys.isNotEmpty) ...[
                                Category.settings(
                                  title: engine.dict.value("pinned_chats"),
                                  context: context,
                                ),
                                cards.cardGroup(
                                  pinnedChatKeys.map((key) {
                                    Map chat = engine.chats[key] ?? {
                                      "name": engine.dict.value("new_chat"),
                                      "tokens": "0",
                                      "history": "[]",
                                      "created": DateTime.now().millisecondsSinceEpoch.toString(),
                                      "updated": DateTime.now().millisecondsSinceEpoch.toString(),
                                    };
                                    return chatCard(chat, key);
                                  }).toList(),
                                ),
                              ],
                              if (otherChatKeys.isNotEmpty) ...[
                                Category.settings(
                                  title: engine.dict.value(pinnedChatKeys.isNotEmpty ? "other_chats" : "your_chats"),
                                  context: context,
                                ),
                                cards.cardGroup(
                                  otherChatKeys.map((key) {
                                    Map chat = engine.chats[key] ?? {
                                      "name": engine.dict.value("new_chat"),
                                      "tokens": "0",
                                      "history": "[]",
                                      "created": DateTime.now().millisecondsSinceEpoch.toString(),
                                      "updated": DateTime.now().millisecondsSinceEpoch.toString(),
                                    };
                                    return chatCard(chat, key);
                                  }).toList(),
                                ),
                              ],
                              if (archivedChatKeys.isNotEmpty) ...[
                                Category.settings(
                                  title: "${engine.dict.value("archived")} (${archivedChatKeys.length})",
                                  context: context,
                                ),
                                cards.cardGroup([
                                  CardContents.doubleTap(
                                    title: engine.dict.value("archived_chats"),
                                    subtitle: "${archivedChatKeys.length} ${engine.dict.value("chats")}",
                                    icon: isArchivedExpanded
                                        ? Icons.keyboard_arrow_up_rounded
                                        : Icons.keyboard_arrow_down_rounded,
                                    action: () {
                                      setState(() {
                                        isArchivedExpanded = !isArchivedExpanded;
                                      });
                                    },
                                    secondAction: () {
                                      setState(() {
                                        isArchivedExpanded = !isArchivedExpanded;
                                      });
                                    },
                                  ),
                                  if (isArchivedExpanded)
                                    ...archivedChatKeys.map((key) {
                                      Map chat = engine.chats[key] ?? {
                                        "name": engine.dict.value("new_chat"),
                                        "tokens": "0",
                                        "history": "[]",
                                        "created": DateTime.now().millisecondsSinceEpoch.toString(),
                                        "updated": DateTime.now().millisecondsSinceEpoch.toString(),
                                      };
                                      return chatCard(chat, key);
                                    }),
                                ]),
                              ],
                              text.info(
                                  title: engine.isLoading?engine.dict.value("still_generating"):engine.dict.value(engine.chats.isEmpty?"no_chats":"chats_desc").replaceAll("%chatnum%", engine.chats.length.toString()),
                                  subtitle: engine.chats.isEmpty?engine.dict.value("new_chat"):"",
                                  action: engine.chats.isNotEmpty?(){}:engine.isLoading?(){}:(){
                                    engine.startNewChat();
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (context) => ChatPage(),
                                          settings: const RouteSettings(name: 'ChatPage')
                                      ),
                                    );
                                    },
                                  context: context
                              ),
                              SizedBox(height: 75,)
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
}