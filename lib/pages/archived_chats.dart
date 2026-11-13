import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';
import 'package:m3x_ui/m3x_ui.dart' show MotionBlurContainer;
import '../engine.dart';
import 'chat.dart';
import 'settings/chat.dart';
import 'support/elements.dart';

class ArchivedChatsPage extends StatefulWidget {
  const ArchivedChatsPage({super.key});

  @override
  ArchivedChatsPageState createState() => ArchivedChatsPageState();
}

class ArchivedChatsPageState extends State<ArchivedChatsPage> {
  String timeAgo(dynamic time) {
    DateTime currentTime = DateTime.now();
    late DateTime pastTimestamp;
    if (time is int) {
      pastTimestamp = DateTime.fromMillisecondsSinceEpoch(time);
    } else if (time is String) {
      pastTimestamp = DateTime.fromMillisecondsSinceEpoch(int.parse(time));
    } else if (time is DateTime) {
      pastTimestamp = time;
    } else {
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
    } else if (days < 30) {
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

  void _showChatOptionsSheet(BuildContext context, AIEngine engine, String key, Map chat) {
    showModalBottomSheet<void>(
      context: context,
      barrierLabel: chat["name"],
      isScrollControlled: false,
      enableDrag: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        final cards = Cards(context: sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text(
                    chat["name"] ?? engine.dict.value("archived_chats"),
                    style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                cards.cardGroup([
                  CardContents.tap(
                    title: engine.dict.value("unarchive_chat"),
                    subtitle: engine.dict.value("unarchive_chat_desc"),
                    action: () async {
                      Navigator.pop(sheetContext);
                      await engine.chatData.unarchiveChat(key);
                      Fluttertoast.showToast(
                        msg: engine.dict.value("chat_unarchived"),
                        toastLength: Toast.LENGTH_SHORT,
                        fontSize: 16.0,
                      );
                      if (mounted) setState(() {});
                    },
                  ),
                  CardContents.tap(
                    title: engine.dict.value("chat_settings"),
                    subtitle: engine.dict.value("change_name"),
                    action: () {
                      Navigator.pop(sheetContext);
                      engine.currentChat = key;
                      engine.context = jsonDecode(chat["history"] ?? "[]");
                      engine.contextSize = int.tryParse(chat["tokens"]?.toString() ?? "0") ?? 0;
                      showModalBottomSheet<void>(
                        context: context,
                        barrierLabel: chat["name"],
                        isScrollControlled: false,
                        enableDrag: true,
                        useSafeArea: true,
                        showDragHandle: true,
                        builder: (_) => const ChatSettingsPage(),
                      );
                    },
                  ),
                  CardContents.longTap(
                    title: engine.dict.value("delete_chat"),
                    subtitle: engine.dict.value("delete_chat_desc"),
                    action: () {
                      Fluttertoast.showToast(
                        msg: engine.dict.value("long_tap_delete"),
                        toastLength: Toast.LENGTH_SHORT,
                        fontSize: 16.0,
                      );
                    },
                    longAction: () async {
                      Navigator.pop(sheetContext);
                      await engine.chatData.deleteChat(key);
                      Fluttertoast.showToast(
                        msg: engine.dict.value("chat_deleted"),
                        toastLength: Toast.LENGTH_SHORT,
                        fontSize: 16.0,
                      );
                      if (mounted) setState(() {});
                    },
                  ),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final cards = Cards(context: context);
        return Consumer<AIEngine>(builder: (context, engine, child) {
          int getChatUpdated(dynamic key) {
            final chat = engine.chats[key];
            if (chat is Map && chat["updated"] != null) {
              final u = chat["updated"];
              if (u is int) return u;
              if (u is String) return int.tryParse(u) ?? 0;
            }
            return 0;
          }

          final archivedChatKeys = engine.chats.keys
              .where((k) => k != "testing" && k != "0")
              .where((key) {
                final chat = engine.chats[key];
                final isPinned = chat is Map && (chat["pinned"] ?? false) == true;
                final isArchived = chat is Map && (chat["isArchived"] ?? false) == true;
                return !isPinned && isArchived;
              })
              .toList()
            ..sort((a, b) => getChatUpdated(b).compareTo(getChatUpdated(a)));

          Widget chatCard(dynamic chat, String key) {
            return Dismissible(
              key: Key("archived_chat_$key"),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 24),
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.unarchive_rounded,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      engine.dict.value("unarchive_chat"),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              confirmDismiss: (direction) async {
                await engine.chatData.unarchiveChat(key);
                Fluttertoast.showToast(
                  msg: engine.dict.value("chat_unarchived"),
                  toastLength: Toast.LENGTH_SHORT,
                  fontSize: 16.0,
                );
                return true;
              },
              child: CardContents.doubleTap(
                title: chat["name"] ?? "Loading...",
                subtitle: timeAgo(chat["updated"]) == "just now"
                    ? "${engine.dict.value("updated")} ${engine.dict.value("just_now")}, ${engine.dict.value("messages")}: ${jsonDecode(chat["history"] ?? "[]").length}"
                    : "${engine.dict.value("updated")} ${timeAgo(chat["updated"]).split(" ")[0]} ${engine.dict.value(timeAgo(chat["updated"]).split(" ")[1])} ${engine.dict.value("ago")}, ${engine.dict.value("messages")}: ${jsonDecode(chat["history"] ?? "[]").length}",
                action: () async {
                  if (!engine.isLoading) {
                    engine.prompt.text = "";
                    engine.responseText = "";
                  }
                  engine.contextSize = int.tryParse(chat["tokens"]?.toString() ?? "0") ?? 0;
                  engine.context = jsonDecode(chat["history"] ?? "[]");
                  engine.currentChat = key;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ChatPage(),
                      settings: const RouteSettings(name: 'ChatPage'),
                    ),
                  );
                },
                icon: Icons.tune_rounded,
                secondAction: () {
                  _showChatOptionsSheet(context, engine, key, chat);
                },
              ),
            );
          }

          return Scaffold(
            body: CustomScrollView(
              slivers: <Widget>[
                SliverAppBar.large(
                  surfaceTintColor: Colors.transparent,
                  leading: Padding(
                    padding: const EdgeInsets.only(left: 5),
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  ),
                  title: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(engine.dict.value("archived_chats")),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 50,
                          horizontal: 10,
                        ),
                        child: Chip(
                          label: Text(
                            archivedChatKeys.length.toString(),
                          ),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                          surfaceTintColor: Colors.transparent,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: const BorderSide(color: Colors.transparent),
                          ),
                        ),
                      ),
                    ],
                  ),
                  pinned: true,
                ),
                SliverToBoxAdapter(
                  child: MotionBlurContainer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (archivedChatKeys.isNotEmpty) ...[
                          Category.settings(
                            title: engine.dict.value("archived_chats"),
                            context: context,
                          ),
                          cards.cardGroup(
                            archivedChatKeys.map((key) {
                              Map chat = engine.chats[key] ?? {
                                "name": "Nonameyet",
                                "tokens": "0",
                                "history": "[]",
                                "created": DateTime.now().millisecondsSinceEpoch.toString(),
                                "updated": DateTime.now().millisecondsSinceEpoch.toString(),
                              };
                              return chatCard(chat, key);
                            }).toList(),
                          ),
                        ] else ...[
                          const SizedBox(height: 48),
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.archive_outlined,
                                    size: 64,
                                    color: Theme.of(context).colorScheme.outline,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    engine.dict.value("no_archived_chats"),
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 75),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }
}
