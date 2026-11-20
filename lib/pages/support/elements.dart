import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:m3x_chat/m3x_chat.dart';
import 'package:m3x_mesh/m3x_mesh.dart';
import 'package:provider/provider.dart';
import 'package:geminilocal/engine.dart';
import 'package:geminilocal/parts/translator.dart';


class Cards {
  double cardMarginV = 2;
  double cardMarginH = 15;
  Radius cardROuter = const Radius.circular(20);
  Radius cardRInner = const Radius.circular(5);
  Map<String,double> cardMargins = {"h":15, "v":2};
  late BuildContext context;

  double cardElevation = 3;

  Cards._internal(this.context);
  factory Cards({required BuildContext context}){
    return Cards._internal(context);
  }

  Color tintColor (context) {
    return Theme.of(context).colorScheme.primary;
  }

  Color cardColor (context) {
    return Theme.of(context).colorScheme.surfaceContainer;
  }

  Widget cardGroup(List<Widget> cards) {
    switch(cards.length){
      case 0: return const SizedBox.shrink();
      case 1: return Card(
        clipBehavior: Clip.hardEdge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(cardROuter),
        ),
        surfaceTintColor: tintColor(context),
        color: cardColor(context),
        elevation: cardElevation,
        margin: EdgeInsets.symmetric(
            horizontal: cardMarginH,
            vertical: cardMarginV
        ),
        child: SizedBox(
          width: double.infinity,
          child: cards[0],
        ),
      );
      case 2: return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            clipBehavior: Clip.hardEdge,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.only(
                  bottomRight: cardRInner,
                  topRight: cardROuter,
                  topLeft: cardROuter,
                  bottomLeft: cardRInner
              ),
            ),
            surfaceTintColor: tintColor(context),
            color: cardColor(context),
            elevation: cardElevation,
            margin: EdgeInsets.symmetric(
                horizontal: cardMarginH,
                vertical: cardMarginV
            ),
            child: cards[0],
          ),
          Card(
            clipBehavior: Clip.hardEdge,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.only(
                  bottomRight: cardROuter,
                  topRight: cardRInner,
                  topLeft: cardRInner,
                  bottomLeft: cardROuter
              ),
            ),
            surfaceTintColor: tintColor(context),
            color: cardColor(context),
            elevation: cardElevation,
            margin: EdgeInsets.symmetric(
                horizontal: cardMarginH,
                vertical: cardMarginV
            ),
            child: cards[1],
          ),
        ],
      );
      default:
        List<Widget> cardsOut = [];
        cardsOut.add(
            Card(
              clipBehavior: Clip.hardEdge,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.only(
                    bottomRight: cardRInner,
                    topRight: cardROuter,
                    topLeft: cardROuter,
                    bottomLeft: cardRInner
                ),
              ),
              surfaceTintColor: tintColor(context),
              color: cardColor(context),
              elevation: cardElevation,
              margin: EdgeInsets.symmetric(
                  horizontal: cardMarginH,
                  vertical: cardMarginV
              ),
              child: cards[0],
            )
        );
        for(int i = 1; i<cards.length - 1; i++){
          cardsOut.add(
              Card(
                clipBehavior: Clip.hardEdge,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.only(
                      bottomRight: cardRInner,
                      topRight: cardRInner,
                      topLeft: cardRInner,
                      bottomLeft: cardRInner
                  ),
                ),
                surfaceTintColor: tintColor(context),
                color: cardColor(context),
                elevation: cardElevation,
                margin: EdgeInsets.symmetric(
                    horizontal: cardMarginH,
                    vertical: cardMarginV
                ),
                child: cards[i],
              )
          );
        }
        cardsOut.add(
            Card(
              clipBehavior: Clip.hardEdge,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.only(
                    bottomRight: cardROuter,
                    topRight: cardRInner,
                    topLeft: cardRInner,
                    bottomLeft: cardROuter

                ),
              ),
              surfaceTintColor: tintColor(context),
              color: cardColor(context),
              elevation: cardElevation,
              margin: EdgeInsets.symmetric(
                  horizontal: cardMarginH,
                  vertical: cardMarginV
              ),
              child: cards[cards.length - 1],
            )
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: cardsOut,
        );
    }
  }
}

class CardContents {
  static Widget tap({
    required String title,
    required String subtitle,
    required VoidCallback action,
    Widget? trailing,
  }) {
    final bool hasSubtitle = subtitle.isNotEmpty;
    return InkWell(
      onTap: action,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: 20, vertical: 10
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!hasSubtitle) const SizedBox(height: 10),
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  if (hasSubtitle)
                    Text(subtitle)
                  else
                    const SizedBox(height: 10),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              trailing,
            ],
          ],
        ),
      ),
    );
  }
  static Widget halfTap({
    required String title,
    required String subtitle,
    required VoidCallback action,
    Widget? trailing,
  }) {
    final bool hasSubtitle = subtitle.isNotEmpty;
    return InkWell(
      onTap: action,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: 20, vertical: 10
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!hasSubtitle) const SizedBox(height: 5),
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  if (hasSubtitle)
                    Text(subtitle)
                  else
                    const SizedBox(height: 5),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              trailing,
            ],
          ],
        ),
      ),
    );
  }
  static Widget tapIcon({
    required String title,
    required String subtitle,
    required VoidCallback action,
    required IconData icon,
    required Color color,
    required Color colorBG
  }) {
    final bool hasSubtitle = subtitle.isNotEmpty;
    return InkWell(
      onTap: action,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: 20, vertical: 10
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            ClipRRect(
              clipBehavior: Clip.hardEdge,
              borderRadius: const BorderRadius.all(Radius.circular(35)),
              child: Container(
                height: 35,
                width: 35,
                color: colorBG,
                child: Icon(
                  icon,
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!hasSubtitle) const SizedBox(height: 10),
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  if (hasSubtitle)
                    Text(subtitle)
                  else
                    const SizedBox(height: 10),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  static Widget static({
    required String title,
    required String subtitle,
  }) {
    final bool hasSubtitle = subtitle.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: 20, vertical: 10
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!hasSubtitle) const SizedBox(height: 10),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  overflow: TextOverflow.ellipsis,
                ),
                if (hasSubtitle)
                  Text(
                    subtitle,
                    overflow: TextOverflow.ellipsis,
                  )
                else
                  const SizedBox(height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
  static Widget progress({
    required String title,
    required String subtitle,
    String subsubtitle = "",
    double? progress,
  }) {
    final bool hasSubtitle = subtitle.isNotEmpty;
    final bool hasSubsubtitle = subsubtitle.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: 20, vertical: 10
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            overflow: TextOverflow.ellipsis,
          ),
          if (hasSubtitle || hasSubsubtitle)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (hasSubtitle)
                  Flexible(
                    child: Text(
                      subtitle,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  const SizedBox.shrink(),
                if (hasSubtitle && hasSubsubtitle) const SizedBox(width: 8),
                if (hasSubsubtitle)
                  Flexible(
                    child: Text(
                      subsubtitle,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          Padding(
            padding: EdgeInsets.symmetric(
              vertical: !hasSubtitle ? 9 : 5
            ),
            child: LinearProgressIndicator(
              value: (progress == null || progress < 0)
                  ? null
                  : progress.clamp(0.0, 1.0),
              borderRadius: BorderRadius.circular(20),
            ),
          )
        ],
      ),
    );
  }
  static Widget doubleTap({
    required String title,
    required String subtitle,
    required VoidCallback action,
    required VoidCallback secondAction,
    required IconData icon
  }) {
    final bool hasSubtitle = subtitle.isNotEmpty;
    return InkWell(
      onTap: action,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: 20, vertical: 10
        ),
        child: IntrinsicHeight(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!hasSubtitle) const SizedBox(height: 10),
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (hasSubtitle)
                      Text(
                        subtitle,
                        overflow: TextOverflow.ellipsis,
                      )
                    else
                      const SizedBox(height: 10),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const VerticalDivider(
                    thickness: 3,
                    radius: BorderRadius.all(Radius.circular(15)),
                  ),
                  IconButton(
                    icon: Icon(
                      icon,
                      size: 32,
                    ),
                    onPressed: secondAction,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  static Widget longTap({
    required String title,
    required String subtitle,
    required VoidCallback action,
    required VoidCallback longAction,
  }) {
    final bool hasSubtitle = subtitle.isNotEmpty;
    return InkWell(
      onTap: action,
      onLongPress: longAction,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: 20, vertical: 10
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!hasSubtitle) const SizedBox(height: 10),
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  if (hasSubtitle)
                    Text(subtitle)
                  else
                    const SizedBox(height: 10),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  static Widget turn({
    required String title,
    required String subtitle,
    required VoidCallback? action,
    required ValueChanged<bool>? switcher,
    required bool value
  }) {
    final bool isEnabled = switcher != null;
    return Builder(
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return InkWell(
          onTap: isEnabled ? action : null,
          child: Padding(
            padding: const EdgeInsets.only(
                top: 10,
                bottom: 10,
                right: 15,
                left: 20
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: isEnabled
                              ? null
                              : colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          style: isEnabled
                              ? null
                              : TextStyle(
                                  color: colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.75),
                                ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Switch(
                  value: value,
                  onChanged: switcher,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  static Widget addretract({
    required String title,
    required String subtitle,
    required VoidCallback actionAdd,
    required VoidCallback actionRetract,
  }) {
    return Padding(
      padding: const EdgeInsets.only(
          top: 10,
          bottom: 10,
          right: 15,
          left: 20
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                if (subtitle.isNotEmpty)
                  Text(subtitle),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.remove_rounded),
                onPressed: actionRetract,
              ),
              IconButton(
                icon: const Icon(Icons.add_rounded),
                onPressed: actionAdd,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class Category {
  static Widget settings({
    required String title,
    required BuildContext context
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, left: 20, right: 20, bottom: 10),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}



// ignore: camel_case_types
class text {
  static Widget info({
    required String title,
    required String subtitle,
    required VoidCallback action,
    required BuildContext context
  }) {
    return Padding(
      padding: const EdgeInsets.only(
          bottom: 50,
          left: 20,
          right: 20,
          top: 10
      ),
      child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 24,
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (subtitle.isNotEmpty) const SizedBox(height: 5),
              if (subtitle.isNotEmpty)
                InkWell(
                  onTap: action,
                  child: Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline
                    ),
                  ),
                )
            ],
          )
      ),
    );
  }
  static Widget infoShort({
    required String title,
    required String subtitle,
    required VoidCallback action,
    required BuildContext context
  }) {
    return Padding(
      padding: const EdgeInsets.only(
          bottom: 0,
          left: 20,
          right: 20,
          top: 10
      ),
      child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 24,
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (subtitle.isNotEmpty) const SizedBox(height: 5),
              if (subtitle.isNotEmpty)
                InkWell(
                  onTap: action,
                  child: Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline
                    ),
                  ),
                )
            ],
          )
      ),
    );
  }
  Widget userMessage (String text, BuildContext context, double width){
    return Padding(
      padding: EdgeInsetsGeometry.only(
          bottom: 50,
          left: 20,
          right: 20,
          top: 10
      ),
      child: SizedBox(
          width: width - 40,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 24,
              ),
              const SizedBox(height: 20),
              Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          )
      ),
    );
  }

  static final Map<String, bool> _existingImagePathCache = <String, bool>{};

  static bool _imagePathExists(String? path, {bool useCache = true}) {
    if (path == null || path.isEmpty) return false;
    if (useCache) {
      final cached = _existingImagePathCache[path];
      if (cached != null) return cached;
    }
    bool exists = false;
    try {
      exists = File(path).existsSync();
    } catch (_) {
      exists = false;
    }
    if (useCache || exists) {
      if (_existingImagePathCache.length >= 256) {
        _existingImagePathCache.clear();
      }
      _existingImagePathCache[path] = exists;
    }
    return exists;
  }

  static String _dictOrDefault(Dictionary? dict, String key, String fallback) {
    if (dict == null) return fallback;
    if (!dict.dictionary.containsKey(dict.locale)) return fallback;
    final val = dict.value(key);
    if (val.isEmpty || val == '!!! $key' || val == key) {
      return fallback;
    }
    return val;
  }

  static String _senderOf(dynamic entry) {
    if (entry is Map) {
      return (entry['user'] ?? entry['sender'])?.toString() ?? '';
    }
    return '';
  }

  static MarkdownStyleSheet _buildAiMarkdownStyleSheet(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final codeStyle = (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
      fontFamily: 'monospace',
      fontSize: 12.5,
      color: colorScheme.onSurface,
      backgroundColor: Colors.transparent,
    );
    return MarkdownStyleSheet.fromTheme(theme).copyWith(
      a: TextStyle(
        color: colorScheme.primary,
        decoration: TextDecoration.underline,
        decorationColor: colorScheme.primary,
      ),
      code: codeStyle,
      codeblockPadding: const EdgeInsets.all(10),
      codeblockDecoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      blockquotePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      blockquoteDecoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: colorScheme.primary,
            width: 3,
          ),
        ),
      ),
    );
  }

  List<Widget> chatlog({
    required String aiChunk,
    String aiThoughtChunk = "",
    required String lastUser,
    required List conversation,
    required BuildContext context,
    String? pendingUserImagePath,
    Dictionary? dict,
    bool isContinuing = false,
    bool? isLoading,
    String? assistantAuthor,
    String? userAuthor,
    DateTime? streamingMessageTime,
    DateTime? streamingUserMessageTime,
  }) {
    AIEngine? engine;
    try {
      engine = Provider.of<AIEngine>(context, listen: false);
    } catch (_) {}

    final Dictionary? effectiveDict = dict ?? engine?.dict;
    final String effectiveThoughtChunk = aiThoughtChunk.isNotEmpty
        ? aiThoughtChunk
        : (engine?.currentThoughtChunk ?? "");
    final bool effectiveIsLoading = isLoading ?? (engine?.isLoading ?? false);
    final String resolvedAssistantAuthor =
        (assistantAuthor != null && assistantAuthor.trim().isNotEmpty)
            ? assistantAuthor.trim()
            : (engine?.assistantAuthorLabel ?? 'Gemini Nano');
    final String resolvedUserAuthor =
        (userAuthor != null && userAuthor.trim().isNotEmpty)
            ? userAuthor.trim()
            : _dictOrDefault(effectiveDict, 'chat_author_you', 'You');
    final DateTime? effectiveAiTime =
        streamingMessageTime ?? engine?.streamingMessageTime;
    final DateTime? effectiveUserTime =
        streamingUserMessageTime ?? engine?.streamingUserMessageTime;

    final String thinkingInProgressLabel = _dictOrDefault(
      effectiveDict,
      'thinking_in_progress',
      'Thinking...',
    );
    final String thoughtProcessLabel = _dictOrDefault(
      effectiveDict,
      'thought_process',
      'Thought process',
    );
    final String continuingLabel = _dictOrDefault(
      effectiveDict,
      'model_continuing',
      'Continuing response…',
    );
    final MarkdownStyleSheet aiStyleSheet = _buildAiMarkdownStyleSheet(context);

    final List<Widget> splits = [];
    final int lastUserIdx =
        conversation.lastIndexWhere((m) => _senderOf(m) == "User");
    final int lastGeminiIdx =
        conversation.lastIndexWhere((m) => _senderOf(m) == "Gemini");

    for (int i = 0; i < conversation.length; i++) {
      final rawLine = conversation[i];
      if (rawLine is! Map) continue;
      final String sender = _senderOf(rawLine);

      if (sender == "System") {
        // System tool results are attached to the corresponding ToolCallBubble
        continue;
      }

      final ChatMessage parsed = ChatMessage.fromLegacyMap(rawLine);
      final bool isUser = parsed.isUser;
      final String rawMsg = parsed.message;
      final String effectiveAuthor =
          (parsed.author != null && parsed.author!.trim().isNotEmpty)
              ? parsed.author!.trim()
              : (isUser ? resolvedUserAuthor : resolvedAssistantAuthor);

      if (isUser) {
        bool hasValidImage =
            parsed.imageBytes != null && parsed.imageBytes!.isNotEmpty;
        if (!hasValidImage &&
            parsed.imagePath != null &&
            parsed.imagePath!.isNotEmpty) {
          hasValidImage = _imagePathExists(parsed.imagePath);
        }
        if (rawMsg.isNotEmpty || hasValidImage) {
          splits.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: ChatMessageBubble(
                showAvatar: false,
                message: parsed.copyWith(
                  sender: sender.isNotEmpty ? sender : 'User',
                  isUser: true,
                  author: effectiveAuthor,
                ),
              ),
            ),
          );
        }
        continue;
      }

      // Only skip trailing duplicate matching the streaming AI chunk
      if (i == lastGeminiIdx &&
          aiChunk.isNotEmpty &&
          (rawMsg == aiChunk || aiChunk.startsWith(rawMsg))) {
        continue;
      }

      final toolCall = rawMsg.isNotEmpty ? _extractToolCall(rawMsg) : null;
      if (toolCall != null) {
        String? toolResult;
        if (i + 1 < conversation.length) {
          final nextLine = conversation[i + 1];
          if (nextLine is Map && _senderOf(nextLine) == "System") {
            final nextMsg = nextLine["message"]?.toString() ?? "";
            if (nextMsg.startsWith("[TOOL RESULT:")) {
              final match =
                  RegExp(r'^\[TOOL RESULT:\s*([\s\S]*)\]$').firstMatch(nextMsg.trim());
              toolResult = match != null ? match.group(1) : nextMsg;
            } else {
              toolResult = nextMsg;
            }
          }
        }
        splits.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: ChatMessageBubble(
              showAvatar: false,
              thoughtProcessLabel: thoughtProcessLabel,
              thinkingInProgressLabel: thinkingInProgressLabel,
              markdownStyleSheet: aiStyleSheet,
              message: parsed.copyWith(
                sender: sender.isNotEmpty ? sender : 'Gemini',
                isUser: false,
                author: effectiveAuthor,
                message: '',
              ),
              customContent: ToolCallBubble(
                toolCall: toolCall,
                rawMessage: rawMsg,
                toolResult: toolResult,
                dict: effectiveDict,
                embeddedInBubble: true,
              ),
            ),
          ),
        );
        continue;
      }

      if (rawMsg.isNotEmpty || parsed.hasThoughts) {
        final bool isActiveLastHistoryAi = isContinuing &&
            aiChunk.isEmpty &&
            lastUser.isEmpty &&
            i == lastGeminiIdx &&
            i > lastUserIdx;
        splits.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: ChatMessageBubble(
              showAvatar: false,
              thoughtProcessLabel: thoughtProcessLabel,
              thinkingInProgressLabel: thinkingInProgressLabel,
              markdownStyleSheet: aiStyleSheet,
              message: parsed.copyWith(
                sender: sender.isNotEmpty ? sender : 'Gemini',
                isUser: false,
                author: effectiveAuthor,
                isLoading: isActiveLastHistoryAi,
                loadingLabel: isActiveLastHistoryAi ? continuingLabel : null,
                clearLoadingLabel: !isActiveLastHistoryAi,
              ),
            ),
          ),
        );
      }
    }

    bool hasPendingImage = false;
    if (pendingUserImagePath != null && pendingUserImagePath.isNotEmpty) {
      hasPendingImage = _imagePathExists(pendingUserImagePath, useCache: false);
    }

    // Determine if the pending user prompt is already committed in the conversation list
    // (e.g., during tool execution / synthesis where _handleToolCall committed it prior to tool calls).
    bool isPendingUserCommitted = false;
    if (lastUser.isNotEmpty && lastUserIdx != -1) {
      final lastUserMsg =
          (conversation[lastUserIdx] as Map)["message"]?.toString() ?? "";
      if (lastUserMsg == lastUser) {
        final hasToolCallOrResult = conversation.sublist(lastUserIdx + 1).any(
          (m) =>
              m is Map &&
              (_senderOf(m) == "System" ||
                  (_senderOf(m) == "Gemini" &&
                      _extractToolCall(m["message"]?.toString() ?? "") != null)),
        );
        if (hasToolCallOrResult || lastUserIdx > lastGeminiIdx) {
          isPendingUserCommitted = true;
        }
      }
    }

    if ((lastUser.isNotEmpty || hasPendingImage) && !isPendingUserCommitted) {
      splits.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: ChatMessageBubble(
            showAvatar: false,
            message: ChatMessage(
              sender: 'User',
              author: resolvedUserAuthor,
              message: lastUser,
              isUser: true,
              timestamp: effectiveUserTime,
              imagePath: hasPendingImage ? pendingUserImagePath : null,
            ),
          ),
        ),
      );
    }

    final String trimmedLiveThought = effectiveThoughtChunk.trim();
    final bool hasLiveThought = trimmedLiveThought.isNotEmpty;
    final bool hasAiChunk = aiChunk.isNotEmpty;
    final bool isWaitingInitial =
        effectiveIsLoading && !hasAiChunk && !isContinuing;
    final bool isActiveContinuing = isContinuing && (isLoading ?? true);
    final bool hasCommittedAiForContinuation = isContinuing &&
        !hasAiChunk &&
        lastUser.isEmpty &&
        lastGeminiIdx != -1 &&
        lastGeminiIdx > lastUserIdx;
    final bool shouldRenderActiveAiBubble = hasAiChunk ||
        hasLiveThought ||
        (isWaitingInitial && !hasCommittedAiForContinuation);

    if (shouldRenderActiveAiBubble) {
      final completeTool = hasAiChunk ? _extractToolCall(aiChunk) : null;
      if (hasAiChunk &&
          (completeTool != null || _looksLikeStreamingToolDraft(aiChunk))) {
        final streamingTool = completeTool ?? _extractPartialToolCall(aiChunk);
        splits.add(
          Padding(
            key: const ValueKey<String>('active_ai_bubble'),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: ChatMessageBubble(
              showAvatar: false,
              thoughtProcessLabel: thoughtProcessLabel,
              thinkingInProgressLabel: thinkingInProgressLabel,
              markdownStyleSheet: aiStyleSheet,
              message: ChatMessage(
                sender: 'Gemini',
                author: resolvedAssistantAuthor,
                message: '',
                isUser: false,
                timestamp: effectiveAiTime,
                thoughts: hasLiveThought ? trimmedLiveThought : null,
                isThinkingStreaming: hasLiveThought && !hasAiChunk,
                isLoading: isActiveContinuing,
                loadingLabel: isActiveContinuing ? continuingLabel : null,
              ),
              customContent: ToolCallBubble(
                toolCall: streamingTool,
                rawMessage: aiChunk,
                toolResult: null,
                dict: effectiveDict,
                embeddedInBubble: true,
              ),
            ),
          ),
        );
      } else {
        final bool activeBubbleLoading =
            isWaitingInitial || isActiveContinuing;
        splits.add(
          Padding(
            key: const ValueKey<String>('active_ai_bubble'),
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: ChatMessageBubble(
              showAvatar: false,
              thoughtProcessLabel: thoughtProcessLabel,
              thinkingInProgressLabel: thinkingInProgressLabel,
              markdownStyleSheet: aiStyleSheet,
              message: ChatMessage(
                sender: 'Gemini',
                author: resolvedAssistantAuthor,
                message: aiChunk,
                isUser: false,
                timestamp: effectiveAiTime,
                thoughts: hasLiveThought ? trimmedLiveThought : null,
                isThinkingStreaming: hasLiveThought && !hasAiChunk,
                isLoading: activeBubbleLoading,
                loadingLabel: isActiveContinuing ? continuingLabel : null,
              ),
            ),
          ),
        );
      }
    }
    return splits;
  }
}

typedef TextPart = text;

/// Collapsible Material 3 pill/card displaying Gemini Nano's reasoning trace
/// above the corresponding assistant response.
class ThoughtProcessBubble extends StatefulWidget {
  final String thought;
  final bool isStreaming;
  final Dictionary? dict;

  const ThoughtProcessBubble({
    super.key,
    required this.thought,
    this.isStreaming = false,
    this.dict,
  });

  @override
  State<ThoughtProcessBubble> createState() => _ThoughtProcessBubbleState();
}

class _ThoughtProcessBubbleState extends State<ThoughtProcessBubble>
    with SingleTickerProviderStateMixin {
  late bool _isExpanded;
  bool _userToggled = false;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.isStreaming;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
      lowerBound: 0.45,
      upperBound: 1.0,
    );
    if (widget.isStreaming) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant ThoughtProcessBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isStreaming != oldWidget.isStreaming) {
      if (widget.isStreaming) {
        _pulseController.repeat(reverse: true);
      } else {
        _pulseController.stop();
        _pulseController.value = 1.0;
      }
      if (!_userToggled) {
        _isExpanded = widget.isStreaming;
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dict = widget.dict;

    final String label = widget.isStreaming
        ? text._dictOrDefault(dict, 'thinking_in_progress', 'Thinking...')
        : text._dictOrDefault(dict, 'thought_process', 'Thought process');

    return LayoutBuilder(
      builder: (context, constraints) {
        final double availableWidth =
            constraints.hasBoundedWidth && constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : (MediaQuery.maybeSizeOf(context)?.width ?? 400.0);
        // Reserve left (4) + right (36) padding around the bubble.
        final double innerBudget = (availableWidth - 40.0).clamp(0.0, availableWidth);
        final double maxBubbleWidth = availableWidth < 220.0
            ? innerBudget
            : (availableWidth * 0.80).clamp(180.0, 560.0).clamp(0.0, innerBudget);

        return Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(
              left: 4.0,
              right: 36.0,
              top: 2.0,
              bottom: 2.0,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxBubbleWidth),
              child: AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                alignment: Alignment.topLeft,
                child: Material(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: widget.isStreaming
                          ? colorScheme.tertiary.withValues(alpha: 0.45)
                          : colorScheme.outlineVariant.withValues(alpha: 0.45),
                      width: 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() {
                        _userToggled = true;
                        _isExpanded = !_isExpanded;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12.0,
                        vertical: 8.0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FadeTransition(
                                opacity: _pulseController,
                                child: Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    color: colorScheme.tertiaryContainer,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.psychology_alt_rounded,
                                    size: 14,
                                    color: colorScheme.onTertiaryContainer,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: FadeTransition(
                                  opacity: _pulseController,
                                  child: Text(
                                    label,
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              AnimatedRotation(
                                turns: _isExpanded ? 0.5 : 0.0,
                                duration: const Duration(milliseconds: 200),
                                child: Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 18,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          if (_isExpanded) ...[
                            const SizedBox(height: 8),
                            Divider(
                              height: 1,
                              thickness: 1,
                              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                            ),
                            const SizedBox(height: 8),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 240),
                              child: SingleChildScrollView(
                                child: SelectableText(
                                  widget.thought,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Extracts and parses an M3x agentic tool call from [text], if present.
Map<String, dynamic>? _extractToolCall(String text) {
  return M3xToolCallParser.extract(text);
}

/// Returns true immediately as soon as [text] begins streaming a JSON/fenced tool draft.
bool looksLikeStreamingToolDraft(String text) {
  final trimmed = text.trimLeft();
  if (trimmed.isEmpty) return false;
  final lower = trimmed.toLowerCase();
  if (trimmed.startsWith('{') ||
      lower.startsWith('```json') ||
      RegExp(r'^```(?:json)?\s*\{', caseSensitive: false).hasMatch(trimmed)) {
    return true;
  }
  return M3xToolCallParser.looksLikeIncompleteToolCall(text);
}

bool _looksLikeStreamingToolDraft(String text) =>
    looksLikeStreamingToolDraft(text);

/// Uses full [M3xToolCallParser.extract] if complete, or regex-extracts partial fields mid-stream.
Map<String, dynamic> _extractPartialToolCall(String text) {
  final full = M3xToolCallParser.extract(text);
  if (full != null) return full;

  final partial = <String, dynamic>{};
  final toolMatch = RegExp(
    r'''["'](?:tool|name|method)["']\s*:\s*["']((?:\\.|[^"'\\\r\n])*)["']''',
  ).firstMatch(text);
  if (toolMatch != null) {
    final val = toolMatch.group(1)?.replaceAll(r'\_', '_').replaceAll(r'\"', '"').trim() ?? '';
    if (val.isNotEmpty) partial['tool'] = val;
  }

  final descMatch = RegExp(
    r'''["']description["']\s*:\s*["']((?:\\.|[^"'\\\r\n])*)["']''',
  ).firstMatch(text);
  if (descMatch != null) {
    final val = descMatch.group(1)?.replaceAll(r'\_', '_').replaceAll(r'\"', '"').trim() ?? '';
    if (val.isNotEmpty) partial['description'] = val;
  }

  final appMatch = RegExp(
    r'''["']app["']\s*:\s*["']((?:\\.|[^"'\\\r\n])*)["']''',
  ).firstMatch(text);
  if (appMatch != null) {
    final val = appMatch.group(1)?.replaceAll(r'\_', '_').replaceAll(r'\"', '"').trim() ?? '';
    if (val.isNotEmpty) partial['app'] = val;
  }

  return partial;
}

bool _isVerboseToolDescription(String? desc) {
  final trimmed = desc?.trim() ?? '';
  if (trimmed.isEmpty || trimmed.length > 44) return true;
  final lower = trimmed.toLowerCase();
  return lower.startsWith('returns ') ||
      lower.startsWith('checks whether ') ||
      lower.startsWith('provides ') ||
      lower.startsWith('retrieves ') ||
      lower.startsWith('lists ') ||
      lower.startsWith('searches official ');
}

String _humanizeToolName(String toolName, {String appName = '', Dictionary? dict}) {
  final trimmed = toolName.trim();
  if (trimmed.isEmpty) {
    return text._dictOrDefault(dict, 'tool_selecting', 'Selecting a tool...');
  }
  final lower = trimmed.toLowerCase();
  if (lower == 'query_aicore_documentation') {
    return text._dictOrDefault(dict, 'tool_searching_docs', 'Searching documentation');
  }
  if (lower == 'inspect_screen') {
    return text._dictOrDefault(dict, 'tool_inspecting_screen', 'Inspecting screen');
  }
  if (lower == 'get_battery_status') {
    return text._dictOrDefault(dict, 'tool_checking_battery', 'Checking battery');
  }
  if (lower == 'wikipedia_summary') {
    return text._dictOrDefault(dict, 'tool_searching_wikipedia', 'Searching Wikipedia');
  }
  if (lower == 'wikipedia_details') {
    return text._dictOrDefault(dict, 'tool_reading_wikipedia', 'Reading Wikipedia');
  }
  if (lower == 'duckduckgo_search') {
    return text._dictOrDefault(dict, 'tool_searching_duckduckgo', 'Searching DuckDuckGo');
  }
  if (lower == 'weather_forecast') {
    return text._dictOrDefault(dict, 'tool_checking_weather', 'Checking weather');
  }

  final normalized = trimmed
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]}_${m[2]}')
      .toLowerCase();
  final rawTokens = normalized
      .split(RegExp(r'[_\-.:/\s]+'))
      .where((t) => t.isNotEmpty)
      .toList();

  final appSlug = appName.trim().toLowerCase().split('.').last;
  final prefixes = <String>{
    'alerts',
    'demo',
    'ptk',
    'paios',
    'geminilocal',
    'ggscanus',
    'binotool',
    'the2k48',
    'm3x',
    'mesh',
    'app',
    if (appSlug.isNotEmpty) appSlug,
  };
  while (rawTokens.length > 1 && prefixes.contains(rawTokens.first)) {
    rawTokens.removeAt(0);
  }
  if (rawTokens.isEmpty) {
    return text._dictOrDefault(dict, 'tool_selecting', 'Selecting a tool...');
  }

  const verbMap = <String, String>{
    'get': 'Checking',
    'check': 'Checking',
    'fetch': 'Fetching',
    'read': 'Reading',
    'list': 'Listing',
    'search': 'Searching',
    'query': 'Searching',
    'find': 'Finding',
    'run': 'Running',
    'exec': 'Running',
    'execute': 'Running',
    'create': 'Creating',
    'add': 'Adding',
    'update': 'Updating',
    'set': 'Setting',
    'delete': 'Deleting',
    'remove': 'Removing',
    'sync': 'Syncing',
    'refresh': 'Refreshing',
    'open': 'Opening',
    'launch': 'Opening',
    'toggle': 'Toggling',
    'analyze': 'Analyzing',
    'inspect': 'Inspecting',
    'ping': 'Pinging',
    'send': 'Sending',
  };
  const listAdjectives = <String>{
    'active',
    'all',
    'open',
    'recent',
    'pending',
    'enabled',
    'installed',
    'available',
  };

  final first = rawTokens.first;
  final mappedVerb = verbMap[first];
  if (mappedVerb != null) {
    final rest = rawTokens.skip(1).take(3).toList();
    if (rest.isEmpty) {
      return first == 'ping' ? 'Pinging service' : '$mappedVerb status';
    }
    if (first == 'list' && rest.length == 1 && listAdjectives.contains(rest[0])) {
      return '$mappedVerb ${rest[0]} items';
    }
    return '$mappedVerb ${rest.join(' ')}';
  }

  final words = rawTokens.take(4).toList();
  final firstWord = words.first;
  final capitalized = '${firstWord[0].toUpperCase()}${firstWord.substring(1)}';
  return words.length > 1 ? '$capitalized ${words.skip(1).join(' ')}' : capitalized;
}

class _ParsedToolResult {
  final bool hasResult;
  final bool isError;
  final int? errorCode;
  final String? errorMessage;
  final String displayText;

  const _ParsedToolResult({
    required this.hasResult,
    required this.isError,
    this.errorCode,
    this.errorMessage,
    required this.displayText,
  });

  factory _ParsedToolResult.fromRaw(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) {
      return const _ParsedToolResult(
        hasResult: false,
        isError: false,
        displayText: '',
      );
    }

    const encoder = JsonEncoder.withIndent('  ');

    // System-recorded [TOOL ERROR ...] entry from AIEngine
    if (trimmed.startsWith('[TOOL ERROR')) {
      final errMatch = RegExp(
        r'^\[TOOL ERROR[^\]]*\]\s*([\s\S]*?)(?:\s+You MUST inform the user[\s\S]*)?$',
      ).firstMatch(trimmed);
      final cleaned = (errMatch?.group(1) ?? trimmed).trim();
      return _ParsedToolResult(
        hasResult: true,
        isError: true,
        errorMessage: cleaned,
        displayText: cleaned,
      );
    }

    try {
      final decoded = jsonDecode(trimmed);
      final pretty = encoder.convert(decoded);
      if (decoded is Map) {
        final errorField = decoded['error'];
        if (errorField is Map) {
          final codeVal = errorField['code'];
          final int? codeInt = codeVal is int
              ? codeVal
              : int.tryParse(codeVal?.toString() ?? '');
          final msg = errorField['message']?.toString();
          return _ParsedToolResult(
            hasResult: true,
            isError: true,
            errorCode: codeInt,
            errorMessage: msg,
            displayText: pretty,
          );
        }
        if (errorField != null &&
            errorField != false &&
            errorField.toString().trim().isNotEmpty) {
          return _ParsedToolResult(
            hasResult: true,
            isError: true,
            errorMessage: errorField.toString(),
            displayText: pretty,
          );
        }

        // Direct JSON-RPC / M3xToolError payload: {"code": -32603, "message": ...}
        final codeVal = decoded['code'];
        final int? codeInt = codeVal is int
            ? codeVal
            : int.tryParse(codeVal?.toString() ?? '');
        final bool isJsonRpcErr = codeInt != null &&
            codeInt < 0 &&
            decoded.containsKey('message');
        final bool isMcpErr = decoded['isError'] == true;
        if (isJsonRpcErr || isMcpErr) {
          return _ParsedToolResult(
            hasResult: true,
            isError: true,
            errorCode: codeInt,
            errorMessage: decoded['message']?.toString() ??
                decoded['detail']?.toString(),
            displayText: pretty,
          );
        }
      }
      return _ParsedToolResult(
        hasResult: true,
        isError: false,
        displayText: pretty,
      );
    } catch (_) {
      return _ParsedToolResult(
        hasResult: true,
        isError: false,
        displayText: trimmed,
      );
    }
  }
}

/// A dedicated Material 3 expandable card widget for agentic tool calls in chat.
class ToolCallBubble extends StatefulWidget {
  final Map<String, dynamic> toolCall;
  final String rawMessage;
  final String? toolResult;
  final Dictionary? dict;
  final bool embeddedInBubble;

  const ToolCallBubble({
    super.key,
    required this.toolCall,
    required this.rawMessage,
    this.toolResult,
    this.dict,
    this.embeddedInBubble = false,
  });

  @override
  State<ToolCallBubble> createState() => _ToolCallBubbleState();
}

class _ToolCallBubbleState extends State<ToolCallBubble> {
  bool _isExpanded = false;

  String _formatJson(dynamic data) {
    const encoder = JsonEncoder.withIndent('  ');
    try {
      if (data is String) {
        final decoded = jsonDecode(data);
        return encoder.convert(decoded);
      }
      return encoder.convert(data);
    } catch (_) {
      return data?.toString() ?? '';
    }
  }

  Map<String, dynamic> _extractArguments(dynamic rawArgs) {
    if (rawArgs is Map) {
      return Map<String, dynamic>.from(rawArgs);
    }
    if (rawArgs is String && rawArgs.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawArgs);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  Widget _buildCodePanel({
    required Color backgroundColor,
    required Color borderColor,
    required Color textColor,
    required String content,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 280),
        child: SingleChildScrollView(
          child: SelectableText(
            content,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dict = widget.dict;

    final rawToolName = (widget.toolCall['tool'] ??
            widget.toolCall['name'] ??
            widget.toolCall['method'] ??
            '')
        .toString()
        .trim();
    final toolName = rawToolName.isEmpty ? 'tool' : rawToolName;
    final appName = (widget.toolCall['app'] ?? '').toString().trim();
    final arguments = _extractArguments(
      widget.toolCall['arguments'] ??
          widget.toolCall['params'] ??
          widget.toolCall['args'],
    );
    final desc = widget.toolCall['description']?.toString().trim();
    final parsedResult = _ParsedToolResult.fromRaw(widget.toolResult);

    final IconData toolIcon = parsedResult.isError
        ? Icons.error_outline_rounded
        : (rawToolName == 'query_aicore_documentation'
            ? Icons.menu_book_rounded
            : (rawToolName == 'inspect_screen'
                ? Icons.screenshot_monitor_rounded
                : (rawToolName.contains('battery')
                    ? Icons.battery_charging_full_rounded
                    : Icons.build_circle_outlined)));

    final String title;
    if (!_isVerboseToolDescription(desc)) {
      title = desc!;
    } else if (rawToolName.isEmpty) {
      title = text._dictOrDefault(dict, 'tool_selecting', 'Selecting a tool...');
    } else {
      title = _humanizeToolName(rawToolName, appName: appName, dict: dict);
    }

    final Color badgeBg = parsedResult.isError
        ? colorScheme.errorContainer
        : colorScheme.primaryContainer.withValues(alpha: 0.8);
    final Color badgeFg = parsedResult.isError
        ? colorScheme.onErrorContainer
        : colorScheme.onPrimaryContainer;
    final Color cardBorderColor = parsedResult.isError
        ? colorScheme.error.withValues(alpha: 0.55)
        : colorScheme.outlineVariant.withValues(alpha: 0.5);

    final String resultLabelBase = text._dictOrDefault(dict, 'tool_result', 'Tool Result');
    final String resultLabel = parsedResult.isError && parsedResult.errorCode != null
        ? '$resultLabelBase (${parsedResult.errorCode})'
        : resultLabelBase;

    final Widget headerRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: badgeBg,
            shape: BoxShape.circle,
          ),
          child: Icon(
            toolIcon,
            size: 16,
            color: badgeFg,
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          fit: FlexFit.loose,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (parsedResult.isError &&
                  parsedResult.errorMessage != null &&
                  parsedResult.errorMessage!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    parsedResult.errorCode != null
                        ? '[${parsedResult.errorCode}] ${parsedResult.errorMessage}'
                        : parsedResult.errorMessage!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.error,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        AnimatedRotation(
          turns: _isExpanded ? 0.5 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 20,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    final Widget innerContent = Padding(
      padding: widget.embeddedInBubble
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          headerRow,
          if (_isExpanded) ...[
            SizedBox(height: widget.embeddedInBubble ? 10 : 12),
            Divider(
              height: 1,
              thickness: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 10),

            // Tool Request
            Text(
              text._dictOrDefault(dict, 'tool_request', 'Tool Request'),
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            _buildCodePanel(
              backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
              borderColor: colorScheme.outlineVariant.withValues(alpha: 0.3),
              textColor: colorScheme.onSurface,
              content: _formatJson({
                'tool': toolName,
                if (widget.toolCall['app'] != null) 'app': widget.toolCall['app'],
                if (desc != null && desc.isNotEmpty) 'description': desc,
                'arguments': arguments,
              }),
            ),

            // Tool Result (if present)
            if (parsedResult.hasResult) ...[
              const SizedBox(height: 10),
              Text(
                resultLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: parsedResult.isError
                      ? colorScheme.error
                      : colorScheme.secondary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              _buildCodePanel(
                backgroundColor: parsedResult.isError
                    ? colorScheme.errorContainer.withValues(alpha: 0.45)
                    : colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
                borderColor: parsedResult.isError
                    ? colorScheme.error.withValues(alpha: 0.4)
                    : colorScheme.outlineVariant.withValues(alpha: 0.3),
                textColor: parsedResult.isError
                    ? colorScheme.onErrorContainer
                    : colorScheme.onSurface,
                content: parsedResult.displayText,
              ),
            ],
          ],
        ],
      ),
    );

    if (widget.embeddedInBubble) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() {
              _isExpanded = !_isExpanded;
            });
          },
          child: innerContent,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double availableWidth =
            constraints.hasBoundedWidth && constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : (MediaQuery.maybeSizeOf(context)?.width ?? 400.0);
        final double maxBubbleWidth = availableWidth < 200.0
            ? availableWidth
            : (availableWidth * 0.85).clamp(180.0, 560.0).clamp(0.0, availableWidth);

        return Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxBubbleWidth),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: cardBorderColor,
                  width: 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() {
                      _isExpanded = !_isExpanded;
                    });
                  },
                  child: innerContent,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}


/// Formats an epoch-ms [int], numeric/ISO [String], or [DateTime] into a
/// localized relative time string (e.g. `"just now"`, `"5 minutes ago"`).
String formatTimeAgo(dynamic time, [Dictionary? dict]) {
  late DateTime pastTimestamp;
  if (time is int) {
    pastTimestamp = DateTime.fromMillisecondsSinceEpoch(time);
  } else if (time is String) {
    final parsedInt = int.tryParse(time.trim());
    if (parsedInt != null) {
      pastTimestamp = DateTime.fromMillisecondsSinceEpoch(parsedInt);
    } else {
      final parsedDt = DateTime.tryParse(time.trim());
      if (parsedDt == null) return '';
      pastTimestamp = parsedDt;
    }
  } else if (time is DateTime) {
    pastTimestamp = time;
  } else {
    return '';
  }

  final Duration difference = DateTime.now().difference(pastTimestamp);
  final int seconds = difference.inSeconds.abs();
  final int minutes = difference.inMinutes.abs();
  final int hours = difference.inHours.abs();
  final int days = difference.inDays.abs();

  if (seconds < 60) {
    return text._dictOrDefault(dict, 'just_now', 'just now');
  }

  final int value;
  final String singularKey;
  final String singularFallback;
  final String pluralKey;
  final String pluralFallback;

  if (minutes < 60) {
    value = minutes;
    singularKey = 'minute_singular';
    singularFallback = text._dictOrDefault(dict, 'minute', 'minute');
    pluralKey = 'minutes_plural';
    pluralFallback = text._dictOrDefault(dict, 'minutes', 'minutes');
  } else if (hours < 24) {
    value = hours;
    singularKey = 'hour_singular';
    singularFallback = text._dictOrDefault(dict, 'hour', 'hour');
    pluralKey = 'hours_plural';
    pluralFallback = text._dictOrDefault(dict, 'hours', 'hours');
  } else if (days < 30) {
    value = days;
    singularKey = 'day_singular';
    singularFallback = text._dictOrDefault(dict, 'day', 'day');
    pluralKey = 'days_plural';
    pluralFallback = text._dictOrDefault(dict, 'days', 'days');
  } else if (days < 365) {
    value = (days / 30).round();
    singularKey = 'month_singular';
    singularFallback = text._dictOrDefault(dict, 'month', 'month');
    pluralKey = 'months_plural';
    pluralFallback = text._dictOrDefault(dict, 'months', 'months');
  } else {
    value = (days / 365).round();
    singularKey = 'year_singular';
    singularFallback = text._dictOrDefault(dict, 'year', 'year');
    pluralKey = 'years_plural';
    pluralFallback = text._dictOrDefault(dict, 'years', 'years');
  }

  final String unit = value == 1
      ? text._dictOrDefault(dict, singularKey, singularFallback)
      : text._dictOrDefault(dict, pluralKey, pluralFallback);
  final String agoLabel = text._dictOrDefault(dict, 'ago', 'ago');
  return '$value $unit $agoLabel';
}
