import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geminilocal/pages/settings/chat.dart';
import 'package:provider/provider.dart';
import 'package:m3x_ui/m3x_ui.dart' show MotionBlurContainer;
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
  void initState() {
    super.initState();
  }
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            double scaffoldWidth = constraints.maxWidth;
            return Consumer<AIEngine>(builder: (context, engine, child) {
              return Scaffold(
                appBar: AppBar(
                  leading: Padding(
                    padding: EdgeInsetsGeometry.only(left: 5),
                    child: IconButton(
                        onPressed: (){
                          if (engine.currentChat == "testing") {
                            engine.chats.remove("testing");
                          }
                          engine.currentChat = "0";
                          engine.context.clear();
                          engine.contextSize = 0;
                          Navigator.pop(context);
                        },
                        icon: Icon(Icons.arrow_back_rounded)
                    ),
                  ),
                  title: Text(engine.chats[engine.currentChat]?["name"]??engine.dict.value("new_chat")),
                  actions: [
                    if(engine.currentChat != "testing")IconButton(
                      icon: Icon(Icons.tune_rounded),
                      tooltip: engine.dict.value("chat_settings"),
                      onPressed: () {
                        engine.chats[engine.currentChat] = engine.chats[engine.currentChat] ?? {};
                        showModalBottomSheet<void>(
                            context: context,
                            barrierLabel: engine.chats[engine.currentChat]?["name"],
                            isScrollControlled: false,
                            enableDrag: true,
                            useSafeArea: true,
                            showDragHandle: true,
                            builder: (BuildContext topContext) {
                              return ChatSettingsPage();
                            }
                        );
                      },
                    ),
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
                                      MotionBlurContainer(
                                        child: SingleChildScrollView(
                                          controller: engine.scroller,
                                          scrollDirection: Axis.vertical,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 5,
                                                horizontal: 12.0
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
                                                          lastUser: "",
                                                          dict: engine.dict,
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
                                                  children: [
                                                    ...tWid.chatlog(
                                                        conversation: engine.context,
                                                        context: context,
                                                        aiChunk: engine.responseText,
                                                        lastUser: engine.lastPrompt,
                                                        pendingUserImagePath: engine.chatData.lastImagePath,
                                                         dict: engine.dict,
                                                    ),
                                                    // Chip shown ONLY between continuation rounds (waiting, not streaming new content)
                                                    if (engine.isContinuing && engine.responseText == engine.combinedResponse)
                                                      Align(
                                                        alignment: Alignment.centerLeft,
                                                        child: Padding(
                                                          padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
                                                          child: Chip(
                                                            avatar: SizedBox(
                                                              width: 14,
                                                              height: 14,
                                                              child: CircularProgressIndicator(strokeWidth: 2),
                                                            ),
                                                            label: Text(engine.dict.value("model_continuing")),
                                                            visualDensity: VisualDensity.compact,
                                                            padding: EdgeInsets.zero,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (engine.pendingImageBytes != null)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                                child: Card(
                                  elevation: 0,
                                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    child: Row(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(10),
                                          child: Image.memory(
                                            engine.pendingImageBytes!,
                                            width: 48,
                                            height: 48,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                engine.pendingImageName ?? 'image.jpg',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Theme.of(context).colorScheme.primaryContainer,
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  engine.downsampleImages
                                                      ? engine.dict.value("vision_fast_badge")
                                                      : engine.dict.value("vision_full_badge"),
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.close_rounded, size: 20),
                                          tooltip: engine.dict.value("remove_image"),
                                          onPressed: () {
                                            HapticFeedback.lightImpact();
                                            engine.clearImageAttachment();
                                          },
                                        ),
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
                                readOnly: engine.isLoading || engine.isContinuing,
                                decoration: InputDecoration(
                                  isDense: true,
                                  prefixIcon: IconButton(
                                    icon: const Icon(Icons.add_photo_alternate_outlined, size: 24),
                                    tooltip: engine.dict.value("attach_image"),
                                    onPressed: (engine.isLoading || engine.isContinuing)
                                        ? null
                                        : () {
                                            HapticFeedback.lightImpact();
                                            engine.pickImageAttachment();
                                          },
                                  ),
                                  suffixIcon: (engine.isLoading || engine.isContinuing)
                                      ? IconButton(
                                    icon: Icon(Icons.stop_rounded, size: 25,),
                                    tooltip: engine.dict.value("cancel_generate"),
                                    onPressed: () {
                                      HapticFeedback.lightImpact();
                                      engine.cancelGeneration();
                                    },
                                  )
                                      : IconButton(
                                    icon: Icon(Icons.send_rounded, size: 25,),
                                    tooltip: engine.dict.value("generate"),
                                    onPressed: () {
                                      HapticFeedback.lightImpact();
                                      engine.generateStream();
                                    },
                                  ),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.all(Radius.circular(20))
                                  ),
                                  hintText: engine.dict.value("prompt"),
                                  alignLabelWithHint: true,
                                  helperText: engine.isLoading && !(engine.responseText == "")
                                      ? engine.dict.value("generating_hint")
                                          .replaceAll("%seconds%", ((engine.cumulativeGenerationMs + (engine.response.generationTimeMs??0))/1000).toStringAsFixed(2))
                                          .replaceAll("%tokens%", (engine.cumulativeTokenCount + (engine.response.tokenCount?.toInt()??0)).toString())
                                          .replaceAll("%tokenspersec%", engine.cumulativeGenerationMs + (engine.response.generationTimeMs??0) > 0
                                              ? ((engine.cumulativeTokenCount + (engine.response.tokenCount?.toInt()??0)) / ((engine.cumulativeGenerationMs + (engine.response.generationTimeMs??0))/1000)).toStringAsFixed(2)
                                              : "0")
                                      : engine.responseText==""
                                      ? engine.dict.value("no_context_yet")
                                      : engine.dict.value("generated_hint")
                                          .replaceAll("%seconds%", ((engine.cumulativeGenerationMs + (engine.response.generationTimeMs??0))/1000).toStringAsFixed(2))
                                          .replaceAll("%tokens%", (engine.cumulativeTokenCount + (engine.response.tokenCount?.toInt()??0)).toString())
                                          .replaceAll("%tokenspersec%", engine.cumulativeGenerationMs + (engine.response.generationTimeMs??0) > 0
                                              ? ((engine.cumulativeTokenCount + (engine.response.tokenCount?.toInt()??0)) / ((engine.cumulativeGenerationMs + (engine.response.generationTimeMs??0))/1000)).toStringAsFixed(2)
                                              : "0"),
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
      ),
    );
  }
}
