import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:geminilocal/pages/chat.dart';
import 'package:geminilocal/storage/file_access_service.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../engine.dart';
import '../support/elements.dart';
import 'prompt_editor.dart';

class PromptViewerPage extends StatefulWidget {
  final String promptId;
  const PromptViewerPage({super.key, required this.promptId});
  @override
  PromptViewerPageState createState() => PromptViewerPageState();
}

class PromptViewerPageState extends State<PromptViewerPage> {

  String _formatTimestamp(dynamic raw) {
    if (raw == null) return '';
    try {
      final ms = int.parse(raw.toString());
      final dt = DateTime.fromMillisecondsSinceEpoch(ms);
      return DateFormat('dd MMM yyyy').format(dt);
    } catch (_) {
      return raw.toString();
    }
  }

  Future<void> _exportPrompt(AIEngine engine, BuildContext context) async {
    final name = engine.promptData.getPromptName(widget.promptId);
    final content = engine.promptData.getPromptContent(widget.promptId);
    final filename = FileAccessService.nameToFilename(name);
    final bytes = content.codeUnits;
    final xfile = XFile.fromData(
      Uint8List.fromList(bytes),
      name: filename,
      mimeType: 'text/markdown',
    );
    // Capture the box before the async share call — context not needed after this point
    await SharePlus.instance.share(
      ShareParams(
        files: [xfile],
        subject: name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
        canPop: true,
        child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              return Consumer<AIEngine>(builder: (context, engine, child) {
                final bool isUserPrompt = engine.promptData.userPrompts.containsKey(widget.promptId);
                final String content = engine.promptData.getPromptContent(widget.promptId);
                final Map promptMeta = isUserPrompt
                    ? engine.promptData.userPrompts[widget.promptId] ?? {}
                    : engine.promptData.defaultPrompts[widget.promptId] ?? {};

                final String? description = isUserPrompt
                    ? null
                    : engine.promptData.getPromptDisplayDescription(widget.promptId, engine.dict.locale);
                final String? author = isUserPrompt ? null : promptMeta["author"] as String?;
                final String updatedStr = _formatTimestamp(promptMeta["updated"]);

                return Scaffold(
                  appBar: AppBar(
                    leading: Padding(
                      padding: EdgeInsetsGeometry.only(left: 5),
                      child: IconButton(
                          onPressed: () { Navigator.pop(context); },
                          icon: Icon(Icons.arrow_back_rounded)
                      ),
                    ),
                    surfaceTintColor: Colors.transparent,
                    title: Text(engine.promptData.getPromptDisplayName(widget.promptId, engine.dict.locale)),
                    actions: [
                      // Export button — always visible
                      IconButton(
                        onPressed: content.isEmpty ? null : () => _exportPrompt(engine, context),
                        icon: Icon(Icons.share_rounded),
                        tooltip: engine.dict.value("export_prompt"),
                      ),
                      if (isUserPrompt)
                        IconButton(
                          onPressed: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(builder: (context) => PromptEditorPage(promptId: widget.promptId),
                                  settings: const RouteSettings(name: 'PromptEditorPage')),
                            );
                          },
                          icon: Icon(Icons.edit_rounded),
                          tooltip: engine.dict.value("edit"),
                        )
                      else
                        IconButton(
                          onPressed: () async {
                            // Capture navigator before any await so the context stays valid
                            final nav = Navigator.of(context);
                            await engine.promptData.cloneDefaultPrompt(widget.promptId);
                            if (!mounted) return;
                            final String clonedId = engine.promptData.userPrompts.keys.last;
                            nav.pushReplacement(
                              MaterialPageRoute(
                                builder: (context) => PromptEditorPage(promptId: clonedId),
                                settings: const RouteSettings(name: 'PromptEditorPage'),
                              ),
                            );
                          },
                          icon: Icon(Icons.copy_rounded),
                          tooltip: engine.dict.value("clone_prompt"),
                        ),
                    ],
                  ),
                  floatingActionButton: FloatingActionButton.extended(
                    onPressed: () {
                      engine.currentChat = "testing";
                      engine.contextSize = 0;
                      engine.context.clear();
                      engine.chats["testing"] = {"promptId": widget.promptId, "name": engine.dict.value("try_prompt")};
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => ChatPage(),
                            settings: const RouteSettings(name: 'ChatPage')),
                      );
                    },
                    icon: Icon(Icons.chat_bubble_outline_rounded),
                    label: Text(engine.dict.value("try_prompt")),
                  ),
                  body: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: content.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(24),
                              child: Center(child: Text(engine.dict.value("prompt_empty"))),
                            )
                          : Padding(
                              padding: const EdgeInsets.fromLTRB(15, 8, 15, 100),
                              child: Markdown(
                                data: content,
                                selectable: true,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                styleSheet: MarkdownStyleSheet(
                                  p: TextStyle(fontSize: 16),
                                ),
                              ),
                            ),
                      ),
                      if ((description != null && description.isNotEmpty) && (author != null && author.isNotEmpty) && updatedStr.isNotEmpty) ...[
                        SliverToBoxAdapter(
                          child: TextBlocks.info(
                              title: "$description\n${engine.dict.value("by_author").replaceAll("%author%", author)}\n${engine.dict.value("prompt_last_updated")}: $updatedStr",
                              context: context,
                              subtitle: "",
                              action: () {}
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              });
            }
        )
    );
  }
}
