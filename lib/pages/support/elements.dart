import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';


class Cards {
  double cardMarginV = 2;
  double cardMarginH = 15;
  Radius cardROuter = const Radius.circular(20);
  Radius cardRInner = const Radius.circular(5);
  Map<String,double> cardMargins = {"h":15, "v":2};
  late BuildContext context;

  Cards._internal(this.context);
  factory Cards({required BuildContext context}){
    return Cards._internal(context);
  }

  Widget cardGroup(List<Widget> cards) {
    double width = (WidgetsBinding.instance.platformDispatcher.views.first.physicalSize / WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio).width;
    double height = (WidgetsBinding.instance.platformDispatcher.views.first.physicalSize / WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio).height;
    switch(cards.length){
      case 0: return Container();
      case 1: return Card(
        clipBehavior: Clip.hardEdge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(cardROuter),
        ),
        color: Theme.of(context).colorScheme.onPrimaryFixed,
        margin: EdgeInsets.symmetric(
            horizontal: cardMarginH,
            vertical: cardMarginV
        ),
        child: Container(
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
            color: Theme.of(context).colorScheme.onPrimaryFixed,
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
            color: Theme.of(context).colorScheme.onPrimaryFixed,
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
              color: Theme.of(context).colorScheme.onPrimaryFixed,
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
                color: Theme.of(context).colorScheme.onPrimaryFixed,
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
              color: Theme.of(context).colorScheme.onPrimaryFixed,
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

class cardContents {
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
                Container(
                  width: width - 70,
                  child: Text(
                    title,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
                subtitle == ""?Container(height: 10,):
                Container(
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
                Container(height: subtitle == ""?10:0,),
                Container(
                  width: width - 150,
                  child: Text(
                    title,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
                subtitle == ""?Container(height: 10,):
                Container(
                  width: width - 150,
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
                Container(
                  width: width - 120,
                  child: Text(
                    title,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
                subtitle == ""?Container(height: 10,):
                Container(
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
  static Widget doubleTap({
    required String title,
    required String subtitle,
    required VoidCallback action,
    required VoidCallback secondAction,
    required IconData icon
  }) {
    double width = (WidgetsBinding.instance.platformDispatcher.views.first.physicalSize / WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio).width;
    double height = (WidgetsBinding.instance.platformDispatcher.views.first.physicalSize / WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio).height;

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
                Container(
                  width: width - 70,
                  child: Text(
                    title,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
                subtitle == ""?Container(height: 10,):
                Container(
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

class divider {
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
      child: Container(
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
      child: Container(
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
      child: Container(
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
  List<Widget> chatlog({
    required String aiChunk,
    required String lastUser,
    required List conversation,
    required BuildContext context
  }) {
    double width = (WidgetsBinding.instance.platformDispatcher.views.first.physicalSize / WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio).width;
    List<Widget> splits = [];
    for(var line in conversation){
      if(line["user"] == "User"){
        String userMessage = line["message"];
        if(!(lastUser == userMessage) && !(userMessage == "")) {
          splits.add(
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Padding(
                    padding: EdgeInsetsGeometry.only(
                        bottom: 0,
                        top: 0
                    ),
                    child: Card(
                      elevation: 0,
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                      clipBehavior: Clip.hardEdge,
                      child: Padding(
                        padding: EdgeInsetsGeometry.symmetric(
                            vertical: 10,
                            horizontal: 15
                        ),
                        child: Container(
                          constraints: BoxConstraints(
                              maxWidth: width - 200,
                              minWidth: 0
                          ),
                          child: Text(
                            userMessage,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSecondary,
                            ),
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
      if(line["user"] == "Gemini"){
        String AIMessage = line["message"];
        if(!(AIMessage == aiChunk) && !(AIMessage == "")) {
          splits.add(
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsetsGeometry.only(
                        bottom: 0,
                        top: 0
                    ),
                    child: Card(
                      elevation: 0,
                      clipBehavior: Clip.hardEdge,
                      child: Padding(
                        padding: EdgeInsetsGeometry.symmetric(
                            vertical: 10,
                            horizontal: 15
                        ),
                        child: Container(
                          constraints: BoxConstraints(
                              maxWidth: width - 150,
                              minWidth: 0.0
                          ),
                          child: MarkdownBody(
                            onTapLink: (String text, String? href, String title) async {
                              await launchUrl(
                                  Uri.parse(href!),
                                  mode: LaunchMode.externalApplication
                              );
                            },
                            selectable: true,
                            data: AIMessage,
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
    }
    if(!(lastUser == "")) {
      splits.add(
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Padding(
              padding: EdgeInsetsGeometry.only(
                  bottom: 0,
                  top: 0
              ),
              child: Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.onSecondaryContainer,
                clipBehavior: Clip.hardEdge,
                child: Padding(
                  padding: EdgeInsetsGeometry.symmetric(
                      vertical: 10,
                      horizontal: 15
                  ),
                  child: Container(
                    constraints: BoxConstraints(
                        maxWidth: width - 200,
                        minWidth: 0
                    ),
                    child: Text(
                      lastUser,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            )
          ],
        )
    );
    }
    if(!(aiChunk == "")) {
      splits.add(
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsetsGeometry.only(
                  bottom: 0,
                  top: 0
              ),
              child: Card(
                elevation: 0,
                clipBehavior: Clip.hardEdge,
                child: Padding(
                  padding: EdgeInsetsGeometry.symmetric(
                      vertical: 10,
                      horizontal: 15
                  ),
                  child: Container(
                    constraints: BoxConstraints(
                        maxWidth: width - 150,
                        minWidth: 0.0
                    ),
                    child: MarkdownBody(
                      onTapLink: (String text, String? href, String title) async {
                        await launchUrl(
                          Uri.parse(href!),
                          mode: LaunchMode.externalApplication
                        );
                      },
                      selectable: true,
                      data: aiChunk,
                    ),
                  ),
                ),
              ),
            )
          ],
        )
    );
    }
    return splits;
  }
}
