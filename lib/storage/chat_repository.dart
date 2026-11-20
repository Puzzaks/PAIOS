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
  String? lastImageDescription;
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
    if (!Hive.isBoxOpen('paios_storage')) return;
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

  Future<void> addToContext(
    String responseText, {
    String? userImagePath,
    String? userImageDescription,
    String? thoughtProcess,
    String? author,
    DateTime? userTime,
    DateTime? aiTime,
  }) async {
    final box = Hive.box('paios_storage');
    final effectiveImagePath = userImagePath ?? lastImagePath;
    final effectiveImageDescription =
        (userImageDescription ?? lastImageDescription)?.trim();
    final trimmedThought = thoughtProcess?.trim();
    final trimmedAuthor = author?.trim();
    final userTimestamp = (userTime ?? DateTime.now()).millisecondsSinceEpoch.toString();
    final aiTimestamp = (aiTime ?? DateTime.now()).millisecondsSinceEpoch.toString();

    contextSize = contextSize + responseText.split(' ').length + lastPrompt.split(' ').length;
    context.add({
      "user": "User",
      "time": userTimestamp,
      "message": lastPrompt,
      if (effectiveImagePath != null && effectiveImagePath.isNotEmpty)
        "imagePath": effectiveImagePath,
      if (effectiveImageDescription != null &&
          effectiveImageDescription.isNotEmpty)
        "imageDescription": effectiveImageDescription,
    });
    context.add({
      "user": "Gemini",
      if (trimmedAuthor != null && trimmedAuthor.isNotEmpty)
        "author": trimmedAuthor,
      "time": aiTimestamp,
      "message": responseText,
      if (trimmedThought != null && trimmedThought.isNotEmpty)
        "thoughtProcess": trimmedThought,
    });

    lastPrompt = "";
    lastImagePath = null;
    lastImageDescription = null;

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

  /// Appends a single message to context and persists to Hive.
  Future<void> appendMessage({
    required String user,
    required String message,
    String? author,
    DateTime? time,
    String? imagePath,
    String? imageDescription,
    String? thoughtProcess,
  }) async {
    final box = Hive.box('paios_storage');
    final trimmedAuthor = author?.trim();
    final trimmedDescription = imageDescription?.trim();
    final trimmedThought = thoughtProcess?.trim();
    final timestamp = (time ?? DateTime.now()).millisecondsSinceEpoch.toString();
    contextSize += message.split(' ').length;
    context.add({
      "user": user,
      if (trimmedAuthor != null && trimmedAuthor.isNotEmpty)
        "author": trimmedAuthor,
      "time": timestamp,
      "message": message,
      if (imagePath != null && imagePath.isNotEmpty) "imagePath": imagePath,
      if (trimmedDescription != null && trimmedDescription.isNotEmpty)
        "imageDescription": trimmedDescription,
      if (trimmedThought != null && trimmedThought.isNotEmpty)
        "thoughtProcess": trimmedThought,
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
        chats[chatID]!["messageCount"] = conversation.length;
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
          "messageCount": conversation.length,
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

  /// Saves an archived chat entry (convenience wrapper over [importAssistantChat]).
  Future<String> saveArchivedChat(
    List conversation, {
    String? title,
    String? defaultAssistantAuthor,
  }) =>
      importAssistantChat(
        conversation,
        isArchived: true,
        title: title,
        defaultAssistantAuthor: defaultAssistantAuthor,
      );

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
    String? defaultAssistantAuthor,
  }) async {
    if (conversation.isEmpty) return "";
    final chatID = DateTime.now().millisecondsSinceEpoch.toString();
    final box = Hive.box('paios_storage');
    final fallbackAuthor =
        (defaultAssistantAuthor != null && defaultAssistantAuthor.trim().isNotEmpty)
            ? defaultAssistantAuthor.trim()
            : "Gemini Nano";

    final normalizedConversation = <Map<String, dynamic>>[];
    int tokensCount = 0;
    for (var line in conversation) {
      if (line is Map) {
        final copy = Map<String, dynamic>.from(line);
        final rawTime = copy["time"]?.toString().trim() ?? "";
        if (rawTime.isEmpty) {
          copy["time"] = DateTime.now().millisecondsSinceEpoch.toString();
        }
        if (copy["user"] == "Gemini") {
          final rawAuthor = copy["author"]?.toString().trim() ?? "";
          if (rawAuthor.isEmpty) {
            copy["author"] = fallbackAuthor;
          }
        }
        if (copy["message"] != null) {
          tokensCount += copy["message"].toString().split(' ').length;
        }
        normalizedConversation.add(copy);
      }
    }
    if (normalizedConversation.isEmpty) return "";

    String chatTitle = title ?? "";
    if (chatTitle.isEmpty) {
      final firstMsg = normalizedConversation.firstWhere(
        (m) => m["user"] == "User",
        orElse: () => normalizedConversation.first,
      );
      final rawText = firstMsg["message"]?.toString() ?? "Assistant Session";
      chatTitle = rawText.length > 36 ? "${rawText.substring(0, 36)}..." : rawText;
    }

    chats[chatID] = {
      "name": chatTitle,
      "tokens": tokensCount.toString(),
      "messageCount": normalizedConversation.length,
      "pinned": false,
      "isArchived": isArchived,
      "promptId": getDefaultPromptId(),
      "history": jsonEncode(normalizedConversation).toString(),
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
          for (var line in normalizedConversation) {
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

  /// Updates `imageDescription` on an existing persisted message in [chatId]
  /// (and in [context] when [chatId] matches [currentChat]).
  ///
  /// Matches by [messageIndex] when provided and within range, otherwise falls
  /// back to matching [imagePath] (searching newest-first). Returns `true` if
  /// any message entry was updated.
  Future<bool> updateMessageImageDescription(
    String chatId,
    String description, {
    int? messageIndex,
    String? imagePath,
  }) async {
    final trimmed = description.trim();
    if (trimmed.isEmpty) return false;

    bool updated = false;

    bool applyToList(List messages) {
      int targetIdx = -1;
      if (messageIndex != null &&
          messageIndex >= 0 &&
          messageIndex < messages.length) {
        targetIdx = messageIndex;
      } else if (imagePath != null && imagePath.isNotEmpty) {
        for (int i = messages.length - 1; i >= 0; i--) {
          final item = messages[i];
          if (item is Map && item["imagePath"]?.toString() == imagePath) {
            targetIdx = i;
            break;
          }
        }
      }
      if (targetIdx == -1) return false;
      final entry = messages[targetIdx];
      if (entry is! Map) return false;
      entry["imageDescription"] = trimmed;
      return true;
    }

    final box = Hive.box('paios_storage');

    if (chatId == currentChat && applyToList(context)) {
      updated = true;
      if (currentChat != "testing") {
        await box.put("context", jsonEncode(context));
      }
    }

    if (chatId != "testing" && chats.containsKey(chatId)) {
      final rawHistory = chats[chatId]?["history"];
      if (rawHistory is String && rawHistory.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawHistory);
          if (decoded is List && applyToList(decoded)) {
            chats[chatId]!["history"] = jsonEncode(decoded);
            await box.put("chats", jsonEncode(chats));
            updated = true;
          }
        } catch (_) {}
      } else if (rawHistory is List && applyToList(rawHistory)) {
        await box.put("chats", jsonEncode(chats));
        updated = true;
      }
    }

    if (updated) {
      notifyEngine();
    }
    return updated;
  }

  Future<void> clearContext() async {
    final box = Hive.box('paios_storage');
    await _purgeChatImages(currentChat, context);
    context.clear();
    contextSize = 0;
    lastPrompt = "";
    lastImagePath = null;
    lastImageDescription = null;
    chats.remove(currentChat);
    await box.put("chats", jsonEncode(chats));
    await box.put("context", jsonEncode(context));
    await box.put("contextSize", contextSize);
    notifyEngine();
  }

  /// Removes an uncommitted image file [imagePath] (and its `chat_<chatId>`
  /// directory when empty and not present in saved [chats]) if generation is
  /// cancelled or fails before committing.
  Future<void> purgeOrphanedTurnImage(
    String? imagePath, {
    String? chatId,
  }) async {
    try {
      final path = imagePath?.trim() ?? '';
      if (path.isNotEmpty) {
        final referencedInContext = context.any(
          (m) => m is Map && m["imagePath"]?.toString() == path,
        );
        if (!referencedInContext) {
          final f = File(path);
          if (await f.exists()) {
            await f.delete();
          }
        }
      }
      final effectiveChatId = chatId?.trim() ?? '';
      if (effectiveChatId.isNotEmpty &&
          effectiveChatId != "0" &&
          effectiveChatId != "testing" &&
          !chats.containsKey(effectiveChatId)) {
        final baseDir = _resolveBaseStorageDir();
        final chatImgDir = Directory(
          '$baseDir${Platform.pathSeparator}chat_images${Platform.pathSeparator}chat_$effectiveChatId',
        );
        if (await chatImgDir.exists()) {
          final entries = await chatImgDir.list().toList();
          if (entries.isEmpty) {
            await chatImgDir.delete();
          }
        }
      }
    } catch (_) {}
  }

  /// Scans `<appDataDir>/chat_images/chat_<id>` post-boot and removes folders
  /// whose chat ID no longer exists in saved [chats] or active [currentChat].
  Future<void> cleanupOrphanedChatImages() async {
    try {
      final baseDir = _resolveBaseStorageDir();
      final imagesRoot = Directory(
        '$baseDir${Platform.pathSeparator}chat_images',
      );
      if (!await imagesRoot.exists()) return;

      final Set<String> activeIds = <String>{
        for (final key in chats.keys) key.toString(),
        if (currentChat.isNotEmpty &&
            currentChat != "0" &&
            currentChat != "testing")
          currentChat,
      };

      await for (final entity in imagesRoot.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final folderName = entity.uri.pathSegments
            .where((s) => s.isNotEmpty)
            .lastOrNull;
        if (folderName == null || !folderName.startsWith('chat_')) continue;
        final chatId = folderName.substring('chat_'.length);
        if (chatId.isEmpty || activeIds.contains(chatId)) continue;
        try {
          await entity.delete(recursive: true);
        } catch (_) {}
      }
    } catch (_) {}
  }
}
