import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class ChatRepository {
  final VoidCallback notifyEngine;
  final Future<String> Function(String) requestTitle;
  final Future<void> Function(String, String, String) logEvent;

  List context = [];
  int contextSize = 0;
  Map chats = {};
  String currentChat = "0";
  String lastPrompt = "";
  String? lastImagePath;
  String Function() getDefaultPromptId;

  bool isLoadingTitle = false;

  ChatRepository({
    required this.notifyEngine,
    required this.requestTitle,
    required this.logEvent,
    required this.getDefaultPromptId,
  });

  String _resolveBaseStorageDir() {
    try {
      if (Hive.isBoxOpen('paios_storage')) {
        final box = Hive.box('paios_storage');
        if (box.path != null && box.path!.isNotEmpty) {
          return File(box.path!).parent.path;
        }
      }
    } catch (_) {}
    return Directory.systemTemp.path;
  }

  /// Ensures [currentChat] has a concrete ID (allocating a timestamp ID if currently `"0"`).
  String ensureActiveChatId() {
    if (currentChat == "0") {
      currentChat = DateTime.now().millisecondsSinceEpoch.toString();
    }
    return currentChat;
  }

  /// Saves [imageBytes] persistently under `<appDataDir>/chat_images/chat_<chatId>/img_<timestamp>.jpg`
  /// and returns the saved file path.
  Future<String> saveChatImage(
    Uint8List imageBytes, {
    String? chatID,
  }) async {
    final effectiveChatId = (chatID != null && chatID.isNotEmpty && chatID != "0")
        ? chatID
        : ensureActiveChatId();
    final baseDir = _resolveBaseStorageDir();
    final chatImgDir = Directory(
      '$baseDir${Platform.pathSeparator}chat_images${Platform.pathSeparator}chat_$effectiveChatId',
    );
    if (!await chatImgDir.exists()) {
      await chatImgDir.create(recursive: true);
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File(
      '${chatImgDir.path}${Platform.pathSeparator}img_$timestamp.jpg',
    );
    await file.writeAsBytes(imageBytes, flush: true);
    return file.path;
  }

  /// Deletes all attached image files referenced in [messages] as well as the
  /// `<appDataDir>/chat_images/chat_<chatId>` directory.
  Future<void> _purgeChatImages(String chatID, [List? messages]) async {
    try {
      final List allMessages = [];
      if (messages != null) {
        allMessages.addAll(messages);
      }
      if (chats.containsKey(chatID)) {
        final rawHistory = chats[chatID]?["history"];
        if (rawHistory is String && rawHistory.isNotEmpty) {
          try {
            final decoded = jsonDecode(rawHistory);
            if (decoded is List) {
              allMessages.addAll(decoded);
            }
          } catch (_) {}
        } else if (rawHistory is List) {
          allMessages.addAll(rawHistory);
        }
      }

      for (final item in allMessages) {
        if (item is Map) {
          final imgPath = item["imagePath"]?.toString();
          if (imgPath != null && imgPath.isNotEmpty) {
            final f = File(imgPath);
            if (await f.exists()) {
              await f.delete();
            }
          }
        }
      }

      if (chatID.isNotEmpty && chatID != "0") {
        final baseDir = _resolveBaseStorageDir();
        final chatImgDir = Directory(
          '$baseDir${Platform.pathSeparator}chat_images${Platform.pathSeparator}chat_$chatID',
        );
        if (await chatImgDir.exists()) {
          await chatImgDir.delete(recursive: true);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print("Error purging chat images for $chatID: $e");
      }
    }
  }

  Future<void> initFromHive() async {
    final box = Hive.box('paios_storage');
    if (box.containsKey("context")) {
      context = jsonDecode(box.get("context", defaultValue: "[]"));
      contextSize = box.get("contextSize", defaultValue: 0);
    }
    if (box.containsKey("chats")) {
      chats = jsonDecode(box.get("chats", defaultValue: "{}"));
    }
    await logEvent("init", "info", chats.isEmpty ? "No chats found" : "Found chats: ${chats.length}");
  }

  Future<void> addToContext(String responseText, {String? userImagePath}) async {
    final box = Hive.box('paios_storage');
    final effectiveImagePath = userImagePath ?? lastImagePath;

    contextSize = contextSize + responseText.split(' ').length + lastPrompt.split(' ').length;
    context.add({
      "user": "User",
      "time": DateTime.now().millisecondsSinceEpoch.toString(),
      "message": lastPrompt,
      if (effectiveImagePath != null && effectiveImagePath.isNotEmpty)
        "imagePath": effectiveImagePath,
    });
    context.add({
      "user": "Gemini",
      "time": DateTime.now().millisecondsSinceEpoch.toString(),
      "message": responseText,
    });

    if (currentChat == "testing") {
      lastPrompt = "";
      lastImagePath = null;
      notifyEngine();
      return;
    }

    await box.put("context", jsonEncode(context));
    await box.put("contextSize", contextSize);

    if (currentChat == "0") {
      currentChat = DateTime.now().millisecondsSinceEpoch.toString();
    }

    await saveChat(context, chatID: currentChat);

    lastPrompt = "";
    lastImagePath = null;
    notifyEngine();
  }

  /// Appends a single message to context and persists to Hive.
  Future<void> appendMessage({
    required String user,
    required String message,
    String? imagePath,
  }) async {
    final box = Hive.box('paios_storage');
    contextSize += message.split(' ').length;
    context.add({
      "user": user,
      "time": DateTime.now().millisecondsSinceEpoch.toString(),
      "message": message,
      if (imagePath != null && imagePath.isNotEmpty) "imagePath": imagePath,
    });

    if (currentChat == "testing") {
      notifyEngine();
      return;
    }

    await box.put("context", jsonEncode(context));
    await box.put("contextSize", contextSize);

    if (currentChat == "0") {
      currentChat = DateTime.now().millisecondsSinceEpoch.toString();
    }

    await saveChat(context, chatID: currentChat);
    notifyEngine();
  }

  Future<void> deleteChat(String chatID) async {
    if (chats.containsKey(chatID) && !(chatID == "0")) {
      await _purgeChatImages(chatID);
      chats.remove(chatID);
      final box = Hive.box('paios_storage');
      await box.put("chats", jsonEncode(chats));
      notifyEngine();
      await logEvent("application", "info", "Deleting chat");
    }
  }

  Future<void> saveChats() async {
    final box = Hive.box('paios_storage');
    await box.put("chats", jsonEncode(chats));
    notifyEngine();
  }

  Future<void> saveChat(List conversation, {String chatID = "0"}) async {
    if (chatID == "testing") return;

    final box = Hive.box('paios_storage');
    if (chatID == "0") {
      chatID = DateTime.now().millisecondsSinceEpoch.toString();
    }

    if (conversation.isNotEmpty) {
      if (chats.containsKey(chatID)) {
        if (!chats[chatID]!.containsKey("name")) {
          await Future.delayed(const Duration(milliseconds: 500));
          await requestTitle(conversation[0]["message"]).then((newTitle) {
            chats[chatID]!["name"] = newTitle;
          });
        }
        chats[chatID]!["history"] = jsonEncode(conversation).toString();
        chats[chatID]!["updated"] = DateTime.now().millisecondsSinceEpoch.toString();
        chats[chatID]!["tokens"] = contextSize.toString();
        await logEvent("application", "info", "Saving chat. Length: ${contextSize.toString()}");
      } else {
        isLoadingTitle = true;
        notifyEngine();

        await Future.delayed(const Duration(milliseconds: 500));
        String newTitle = "Still loading";
        String composeConversation = "";
        for (var line in conversation) {
          composeConversation = "$composeConversation\n - ${line["message"]}";
        }
        await requestTitle(composeConversation).then((result) {
          newTitle = result;
        });

        isLoadingTitle = false;

        chats[chatID] = {
          "name": newTitle,
          "tokens": contextSize.toString(),
          "pinned": false,
          "isArchived": false,
          "promptId": getDefaultPromptId(),
          "history": jsonEncode(conversation).toString(),
          "created": DateTime.now().millisecondsSinceEpoch.toString(),
          "updated": DateTime.now().millisecondsSinceEpoch.toString(),
        };
        await logEvent("application", "info", "Saving new chat");
      }
    }
    await box.put("chats", jsonEncode(chats));
    notifyEngine();
  }

  Future<void> archiveChat(String chatID) async {
    if (!chats.containsKey(chatID)) return;
    if (chats[chatID]?["pinned"] == true) {
      // Rule: Pinned chats CANNOT be archived (unpin first)
      await logEvent("application", "warning", "Cannot archive pinned chat $chatID");
      return;
    }
    chats[chatID]?["isArchived"] = true;
    final box = Hive.box('paios_storage');
    await box.put("chats", jsonEncode(chats));
    notifyEngine();
    await logEvent("application", "info", "Archived chat $chatID");
  }

  Future<void> unarchiveChat(String chatID) async {
    if (!chats.containsKey(chatID)) return;
    chats[chatID]?["isArchived"] = false;
    // Moves it to the top of all chats by setting updatedAt = DateTime.now()
    chats[chatID]?["updated"] = DateTime.now().millisecondsSinceEpoch.toString();
    final box = Hive.box('paios_storage');
    await box.put("chats", jsonEncode(chats));
    notifyEngine();
    await logEvent("application", "info", "Unarchived chat $chatID");
  }

  Future<String> importAssistantChat(
    List conversation, {
    bool isArchived = true,
    String? title,
  }) async {
    if (conversation.isEmpty) return "";
    final chatID = DateTime.now().millisecondsSinceEpoch.toString();
    final box = Hive.box('paios_storage');

    int tokensCount = 0;
    for (var line in conversation) {
      if (line is Map && line["message"] != null) {
        tokensCount += line["message"].toString().split(' ').length;
      }
    }

    String chatTitle = title ?? "";
    if (chatTitle.isEmpty) {
      final firstMsg = conversation.firstWhere(
        (m) => m is Map && m["user"] == "User",
        orElse: () => conversation.first,
      );
      final rawText = (firstMsg is Map ? firstMsg["message"] : null)?.toString() ?? "Assistant Session";
      chatTitle = rawText.length > 36 ? "${rawText.substring(0, 36)}..." : rawText;
    }

    chats[chatID] = {
      "name": chatTitle,
      "tokens": tokensCount.toString(),
      "pinned": false,
      "isArchived": isArchived,
      "promptId": getDefaultPromptId(),
      "history": jsonEncode(conversation).toString(),
      "created": DateTime.now().millisecondsSinceEpoch.toString(),
      "updated": DateTime.now().millisecondsSinceEpoch.toString(),
    };

    await box.put("chats", jsonEncode(chats));
    notifyEngine();
    await logEvent("application", "info", "Imported assistant chat $chatID (archived=$isArchived)");

    if (title == null) {
      unawaited(() async {
        try {
          String composeConversation = "";
          for (var line in conversation) {
            composeConversation = "$composeConversation\n - ${line["message"]}";
          }
          final generatedTitle = await requestTitle(composeConversation);
          if (generatedTitle.isNotEmpty && chats.containsKey(chatID)) {
            chats[chatID]!["name"] = generatedTitle;
            await box.put("chats", jsonEncode(chats));
            notifyEngine();
          }
        } catch (_) {}
      }());
    }

    return chatID;
  }

  Future<void> clearContext() async {
    final box = Hive.box('paios_storage');
    await _purgeChatImages(currentChat, context);
    context.clear();
    contextSize = 0;
    lastPrompt = "";
    lastImagePath = null;
    chats.remove(currentChat);
    await box.put("chats", jsonEncode(chats));
    await box.put("context", jsonEncode(context));
    await box.put("contextSize", contextSize);
    notifyEngine();
  }
}
