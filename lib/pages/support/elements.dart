import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:m3x_mesh/m3x_mesh.dart';
import 'package:url_launcher/url_launcher.dart';
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
    double width = (WidgetsBinding.instance.platformDispatcher.views.first.physicalSize / WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio).width;
    switch(cards.length){
      case 0: return Container();
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
          width: width - (cardMarginH * 2),
          child: cards[0],
        ),
      );
      case 2: return Column(
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
        return Column(children: cardsOut);
    }
  }
}

class CardContents {
  static Widget tap({
    required String title,
    required String subtitle,
    required VoidCallback action,
  }) {
    double width = (WidgetsBinding.instance.platformDispatcher.views.first.physicalSize / WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio).width;
    return InkWell(
      onTap: action,
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: 20, vertical: 10
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(height: subtitle == ""?10:0,),
                SizedBox(
                  width: width - 70,
                  child: Text(
                    title,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
                subtitle == ""?Container(height: 10,):
                SizedBox(
                  width: width - 70,
                  child: Text(
                      subtitle
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  static Widget halfTap({
    required String title,
    required String subtitle,
    required VoidCallback action,
  }) {
    double width = (WidgetsBinding.instance.platformDispatcher.views.first.physicalSize / WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio).width;
    return InkWell(
      onTap: action,
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: 20, vertical: 10
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(height: subtitle == ""?5:0,),
                SizedBox(
                  width: width - 190,
                  child: Text(
                    title,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
                subtitle == ""?Container(height: 5,):
                SizedBox(
                  width: width - 190,
                  child: Text(
                      subtitle
                  ),
                ),
              ],
            ),
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
    double width = (WidgetsBinding.instance.platformDispatcher.views.first.physicalSize / WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio).width;
    return InkWell(
      onTap: action,
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: 20, vertical: 10
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            ClipRRect(
              clipBehavior: Clip.hardEdge,
              borderRadius: BorderRadius.all(Radius.circular(35)),
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
            SizedBox(width: 15,),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(height: subtitle == ""?10:0,),
                SizedBox(
                  width: width - 120,
                  child: Text(
                    title,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
                subtitle == ""?Container(height: 10,):
                SizedBox(
                  width: width - 120,
                  child: Text(
                      subtitle
                  ),
                ),
              ],
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
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: 20, vertical: 10
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(height: subtitle == ""?10:0,),
          Text(
            title,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            overflow: TextOverflow.ellipsis,
          ),
          subtitle == ""?Container(height: 10,):
          Text(
            subtitle,
            overflow: TextOverflow.ellipsis,
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
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: 20, vertical: 10
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(height: subtitle == ""?0:0,),
          Text(
            title,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            overflow: TextOverflow.ellipsis,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              subtitle == ""?Container():
              Text(
                subtitle,
                overflow: TextOverflow.ellipsis,
              ),
              subsubtitle == ""?Container():
              Text(
                subsubtitle,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          Padding(
            padding: EdgeInsetsGeometry.symmetric(
              vertical: subtitle == ""?9:5
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
    double width = (WidgetsBinding.instance.platformDispatcher.views.first.physicalSize / WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio).width;

    return InkWell(
      onTap: action,
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: 20, vertical: 10
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(height: subtitle == ""?10:0,),
                ConstrainedBox(
                  constraints: BoxConstraints(
                      minWidth: 100,
                      maxWidth: width - 140
                  ),
                  child: Text(
                    title,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                subtitle == ""?Container(height: 10,):
                ConstrainedBox(
                  constraints: BoxConstraints(
                      minWidth: 100,
                      maxWidth: width - 140
                  ),
                  child: Text(
                    subtitle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            IntrinsicHeight(
              child: Row(
                children: [
                  VerticalDivider(thickness: 3,radius: BorderRadius.all(Radius.circular(15)),),
                  IconButton(
                    icon: Icon(
                      icon,
                      size: 32,
                    ),
                    onPressed: secondAction,
                  ),
                ],
              ),
            )

          ],
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
    double width = (WidgetsBinding.instance.platformDispatcher.views.first.physicalSize / WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio).width;
    return InkWell(
      onTap: action,
      onLongPress: longAction,
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: 20, vertical: 10
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(height: subtitle == ""?10:0,),
                SizedBox(
                  width: width - 70,
                  child: Text(
                    title,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
                subtitle == ""?Container(height: 10,):
                SizedBox(
                  width: width - 70,
                  child: Text(
                    subtitle
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  static Widget turn({
    required String title,
    required String subtitle,
    required VoidCallback action,
    required ValueChanged<bool> switcher,
    required bool value
  }) {
    double width = (WidgetsBinding.instance.platformDispatcher.views.first.physicalSize / WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio).width;
    return InkWell(
      onTap: action,
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
            Container(
              constraints: BoxConstraints(
                maxWidth: width - 140
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  Text(
                    subtitle,
                  ),
                ],
              ),
            ),
            Switch(
              value: value, onChanged: switcher,
            ),
          ],
        ),
      ),
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              Text(
                subtitle,
              ),
            ],
          ),
          Row(
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
    double width = (WidgetsBinding.instance.platformDispatcher.views.first.physicalSize / WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio).width;
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
                title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              subtitle == ""?Container():const SizedBox(height: 5),
              subtitle == ""?Container():InkWell(
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
    double width = (WidgetsBinding.instance.platformDispatcher.views.first.physicalSize / WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio).width;
    return Padding(
      padding: EdgeInsetsGeometry.only(
          bottom: 0,
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
                title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              subtitle == ""?Container():const SizedBox(height: 5),
              subtitle == ""?Container():InkWell(
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

  static void _showFullScreenImageDialog(BuildContext context, String imagePath) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Colors.black87,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 5.0,
                child: Center(
                  child: Image.file(
                    File(imagePath),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: SafeArea(
                child: IconButton.filledTonal(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _buildBubbleImageThumbnail(
    BuildContext context,
    String imagePath, {
    required bool hasTextBelow,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: hasTextBelow ? 2.0 : 0.0),
      child: GestureDetector(
        onTap: () => _showFullScreenImageDialog(context, imagePath),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: Image.file(
              File(imagePath),
              fit: BoxFit.cover,
              height: 200,
            ),
          ),
        ),
      ),
    );
  }

  static Widget _buildAiMarkdownBubble(BuildContext context, String data) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final codeStyle = (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
      fontFamily: 'monospace',
      fontSize: 12.5,
      color: colorScheme.onSurface,
      backgroundColor: Colors.transparent,
    );
    final styleSheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final double availableWidth =
            constraints.hasBoundedWidth && constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : (MediaQuery.maybeSizeOf(context)?.width ?? 400.0);
        // Reserve card margin (4 + 36 = 40) and inner padding (16 * 2 = 32).
        final double innerBudget = (availableWidth - 72.0).clamp(0.0, availableWidth);
        final double aiMaxWidth = availableWidth < 220.0
            ? innerBudget
            : (availableWidth * 0.80).clamp(180.0, 560.0).clamp(0.0, innerBudget);

        return Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Flexible(
              child: Card(
                elevation: 0,
                margin: const EdgeInsets.only(left: 4.0, right: 36.0, top: 2.0, bottom: 4.0),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                color: colorScheme.surfaceContainerHigh,
                clipBehavior: Clip.hardEdge,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 12.0,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: aiMaxWidth,
                      minWidth: 0.0,
                    ),
                    child: MarkdownBody(
                      styleSheet: styleSheet,
                      onTapLink: (String text, String? href, String title) async {
                        if (href == null || href.isEmpty) return;
                        final uri = Uri.tryParse(href);
                        if (uri != null) {
                          try {
                            await launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            );
                          } catch (_) {}
                        }
                      },
                      selectable: true,
                      data: data,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> chatlog({
    required String aiChunk,
    required String lastUser,
    required List conversation,
    required BuildContext context,
    String? pendingUserImagePath,
    Dictionary? dict,
  }) {
    final double width = MediaQuery.maybeSizeOf(context)?.width ?? 400.0;
    final double userMaxWidth = (width * 0.78).clamp(160.0, 560.0);
    List<Widget> splits = [];
    final int lastUserIdx = conversation.lastIndexWhere((m) => m["user"] == "User");
    final int lastGeminiIdx = conversation.lastIndexWhere((m) => m["user"] == "Gemini");
    for (int i = 0; i < conversation.length; i++) {
      var line = conversation[i];

      if (line["user"] == "System") {
        // System tool results are attached to the corresponding ToolCallBubble
        continue;
      }

      if (line["user"] == "User") {
        String userMessage = line["message"]?.toString() ?? "";
        String? imagePath = line["imagePath"]?.toString();
        bool hasValidImage = false;
        if (imagePath != null && imagePath.isNotEmpty) {
          try {
            hasValidImage = File(imagePath).existsSync();
          } catch (_) {
            hasValidImage = false;
          }
        }
        if (userMessage.isNotEmpty || hasValidImage) {
          splits.add(
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                        bottom: 0,
                        top: 0
                    ),
                    child: Card(
                      elevation: 0,
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                      clipBehavior: Clip.hardEdge,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 15
                        ),
                        child: Container(
                          constraints: BoxConstraints(
                              maxWidth: userMaxWidth,
                              minWidth: 0
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (hasValidImage)
                                _buildBubbleImageThumbnail(
                                  context,
                                  imagePath!,
                                  hasTextBelow: userMessage.isNotEmpty,
                                ),
                              if (userMessage.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 6.0,
                                    left: 4.0,
                                    right: 4.0,
                                    bottom: 2.0,
                                  ),
                                  child: Text(
                                    userMessage,
                                    textAlign: TextAlign.start,
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.onSecondary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                ],
              )
          );
        }
      }
      if (line["user"] == "Gemini") {
        String aiMessage = line["message"]?.toString() ?? "";
        // Only skip trailing duplicate matching the streaming AI chunk
        if (i == lastGeminiIdx && aiChunk.isNotEmpty && (aiMessage == aiChunk || aiChunk.startsWith(aiMessage))) {
          continue;
        }
        if (aiMessage.isNotEmpty) {
          final toolCall = _extractToolCall(aiMessage);
          if (toolCall != null) {
            String? toolResult;
            if (i + 1 < conversation.length) {
              final nextLine = conversation[i + 1];
              if (nextLine["user"] == "System") {
                final nextMsg = nextLine["message"]?.toString() ?? "";
                if (nextMsg.startsWith("[TOOL RESULT:")) {
                  final match = RegExp(r'^\[TOOL RESULT:\s*([\s\S]*)\]$').firstMatch(nextMsg.trim());
                  toolResult = match != null ? match.group(1) : nextMsg;
                } else {
                  toolResult = nextMsg;
                }
              }
            }
            splits.add(
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: ToolCallBubble(
                  toolCall: toolCall,
                  rawMessage: aiMessage,
                  toolResult: toolResult,
                  dict: dict,
                ),
              ),
            );
            continue;
          }

          splits.add(_buildAiMarkdownBubble(context, aiMessage));
        }
      }
    }
    bool hasPendingImage = false;
    if (pendingUserImagePath != null && pendingUserImagePath.isNotEmpty) {
      try {
        hasPendingImage = File(pendingUserImagePath).existsSync();
      } catch (_) {
        hasPendingImage = false;
      }
    }

    // Determine if the pending user prompt is already committed in the conversation list
    // (e.g., during tool execution / synthesis where _handleToolCall committed it prior to tool calls).
    bool isPendingUserCommitted = false;
    if (lastUser.isNotEmpty && lastUserIdx != -1) {
      final lastUserMsg = conversation[lastUserIdx]["message"]?.toString() ?? "";
      if (lastUserMsg == lastUser) {
        final hasToolCallOrResult = conversation.sublist(lastUserIdx + 1).any(
          (m) => m["user"] == "System" || (m["user"] == "Gemini" && _extractToolCall(m["message"]?.toString() ?? "") != null),
        );
        if (hasToolCallOrResult || lastUserIdx > lastGeminiIdx) {
          isPendingUserCommitted = true;
        }
      }
    }

    if ((lastUser.isNotEmpty || hasPendingImage) && !isPendingUserCommitted) {
      splits.add(
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                  bottom: 0,
                  top: 0
              ),
              child: Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.onSecondaryContainer,
                clipBehavior: Clip.hardEdge,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 15
                  ),
                  child: Container(
                    constraints: BoxConstraints(
                        maxWidth: userMaxWidth,
                        minWidth: 0
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hasPendingImage)
                          _buildBubbleImageThumbnail(
                            context,
                            pendingUserImagePath!,
                            hasTextBelow: lastUser.isNotEmpty,
                          ),
                        if (lastUser.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(
                              top: 6.0,
                              left: 4.0,
                              right: 4.0,
                              bottom: 2.0,
                            ),
                            child: Text(
                              lastUser,
                              textAlign: TextAlign.start,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSecondary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          ],
        )
      );
    }
    if (!(aiChunk == "")) {
      final streamingTool = _extractToolCall(aiChunk);
      if (streamingTool != null) {
        splits.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: ToolCallBubble(
              toolCall: streamingTool,
              rawMessage: aiChunk,
              toolResult: null,
              dict: dict,
            ),
          ),
        );
      } else {
        splits.add(_buildAiMarkdownBubble(context, aiChunk));
      }
    }
    return splits;
  }
}

typedef TextPart = text;

/// Extracts and parses an M3x agentic tool call from [text], if present.
Map<String, dynamic>? _extractToolCall(String text) {
  return M3xToolCallParser.extract(text);
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

  const ToolCallBubble({
    super.key,
    required this.toolCall,
    required this.rawMessage,
    this.toolResult,
    this.dict,
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

    final toolName = (widget.toolCall['tool'] ??
            widget.toolCall['name'] ??
            widget.toolCall['method'] ??
            'tool')
        .toString();
    final arguments = _extractArguments(
      widget.toolCall['arguments'] ??
          widget.toolCall['params'] ??
          widget.toolCall['args'],
    );
    final desc = widget.toolCall['description']?.toString().trim();
    final parsedResult = _ParsedToolResult.fromRaw(widget.toolResult);

    final IconData toolIcon = parsedResult.isError
        ? Icons.error_outline_rounded
        : (toolName == 'query_aicore_documentation'
            ? Icons.menu_book_rounded
            : (toolName.contains('battery')
                ? Icons.battery_charging_full_rounded
                : Icons.build_circle_outlined));

    final String title;
    if (desc != null && desc.isNotEmpty) {
      title = desc;
    } else if (toolName == 'query_aicore_documentation') {
      final query = arguments['query'] ?? arguments['topic'] ?? arguments['q'] ?? 'AICore';
      final template = dict?.value('tool_reading_docs') ?? "Reading documentation for '%s'";
      title = template.contains('%s') ? template.replaceAll('%s', query.toString()) : "$template ($query)";
    } else if (toolName == 'get_battery_status') {
      title = dict?.value('tool_checking_battery') ?? "Checking battery status";
    } else {
      final template = dict?.value('tool_using') ?? "Using tool: %s";
      title = template.contains('%s') ? template.replaceAll('%s', toolName) : "$template: $toolName";
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

    final String resultLabelBase = dict?.value('tool_result') ?? "Tool Result";
    final String resultLabel = parsedResult.isError && parsedResult.errorCode != null
        ? '$resultLabelBase (${parsedResult.errorCode})'
        : resultLabelBase;

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
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Collapsed Row (Always visible)
                        Row(
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
                            Expanded(
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
                                    maxLines: 2,
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
                        ),

                        // Expanded Details
                        if (_isExpanded) ...[
                          const SizedBox(height: 12),
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                          ),
                          const SizedBox(height: 10),

                          // Tool Request
                          Text(
                            dict?.value('tool_request') ?? "Tool Request",
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
