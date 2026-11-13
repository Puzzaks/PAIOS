import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/services.dart';
import 'file_access_service.dart';

class PromptRepository {
  final VoidCallback notifyEngine;
  final Future<void> Function(String, String, String)? logEvent;
  bool newPromptsAvailable = false;
  static const Duration _httpTimeout = Duration(seconds: 5);

  Map<String, dynamic> defaultPrompts = {};
  Map<String, dynamic> userPrompts = {};

  PromptRepository({required this.notifyEngine, this.logEvent});

  Future<void> initFromHive(String url) async {
    final box = Hive.box('paios_storage');

    // ── 1. Load User Prompts from Hive ──────────────────────────────────────
    final String? storedUserPrompts = box.get("user_prompts");
    if (storedUserPrompts != null) {
      try {
        userPrompts = Map<String, dynamic>.from(jsonDecode(storedUserPrompts));
      } catch (_) {}
    }

    // ── 2. Load Default Prompts Immediately: Bundled baseline + Hive Cache ──
    try {
      final String assetIndex =
          await rootBundle.loadString('assets/prompts/prompts_index.json');
      final decoded = jsonDecode(assetIndex);
      if (decoded is List) {
        defaultPrompts = {
          for (var item in decoded)
            item['id'].toString(): Map<String, dynamic>.from(item as Map)
        };
      } else if (decoded is Map) {
        defaultPrompts = Map<String, dynamic>.from(decoded);
      }
    } catch (e) {
      if (kDebugMode) print("Error parsing asset prompts: $e");
    }

    final String? cachedIndex = box.get("cached_prompts_index");
    if (cachedIndex != null && cachedIndex.isNotEmpty) {
      try {
        final decoded = jsonDecode(cachedIndex);
        if (decoded is List) {
          for (var item in decoded) {
            if (item is Map && item['id'] != null) {
              defaultPrompts[item['id'].toString()] =
                  Map<String, dynamic>.from(item);
            }
          }
        } else if (decoded is Map) {
          defaultPrompts.addAll(Map<String, dynamic>.from(decoded));
        }
      } catch (e) {
        if (kDebugMode) print("Error parsing cached prompts: $e");
      }
    }

    // ── 3. Load Local/Cached Content for Default Prompts Immediately ────────
    for (final String key in defaultPrompts.keys) {
      String? content = box.get("cached_prompt_$key");
      if (content == null || content.isEmpty) {
        try {
          content = await rootBundle.loadString('assets/prompts/$key.md');
        } catch (_) {
          content = "";
        }
      }
      defaultPrompts[key]["content"] = content;
    }

    // ── 4. Scan SAF directory for new .md files to import ───────────────────
    await _importFromDirectory();

    // ── 5. Non-Blocking Background GitHub Refresh (Release Mode) ────────────
    if (!kDebugMode && url.isNotEmpty) {
      unawaited(_refreshPromptsInBackground(url, box, cachedIndex));
    }
  }

  Future<void> _refreshPromptsInBackground(
    String url,
    Box<dynamic> box,
    String? previousCachedIndex,
  ) async {
    try {
      if (logEvent != null) {
        await logEvent!(
          "prompt_repo",
          "info",
          "Background-fetching prompts from $url/assets/prompts/prompts_index.json",
        );
      }
      final response = await http
          .get(Uri.parse("$url/assets/prompts/prompts_index.json"))
          .timeout(_httpTimeout);
      if (response.statusCode == 200) {
        final onlineData = jsonDecode(response.body);
        final Map<String, dynamic> onlineIndex = {};

        if (onlineData is List) {
          for (var item in onlineData) {
            if (item is Map && item['id'] != null) {
              onlineIndex[item['id'].toString()] =
                  Map<String, dynamic>.from(item);
            }
          }
        } else if (onlineData is Map) {
          onlineIndex.addAll(Map<String, dynamic>.from(onlineData));
        }

        if (previousCachedIndex != response.body) {
          newPromptsAvailable = true;
        }
        await box.put("cached_prompts_index", response.body);

        final List<Future<void>> tasks = <Future<void>>[];
        for (final String key in onlineIndex.keys) {
          // Preserve existing local content until remote .md finishes downloading
          if (defaultPrompts[key] is Map &&
              defaultPrompts[key]["content"] != null) {
            onlineIndex[key]["content"] = defaultPrompts[key]["content"];
          }
          tasks.add(() async {
            try {
              final promptGet = await http
                  .get(Uri.parse("$url/assets/prompts/$key.md"))
                  .timeout(_httpTimeout);
              if (promptGet.statusCode == 200) {
                onlineIndex[key]["content"] = promptGet.body;
                await box.put("cached_prompt_$key", promptGet.body);
              }
            } catch (_) {}
          }());
        }
        await Future.wait(tasks);
        defaultPrompts = onlineIndex;
        notifyEngine();
      }
    } catch (e) {
      if (logEvent != null) {
        await logEvent!(
          "prompt_repo",
          "info",
          "Offline or timeout during background prompt refresh; using cached/bundled prompts ($e)",
        );
      }
    }
  }

  // ── Import: scan the SAF folder for unknown .md files ────────────────────

  Future<void> _importFromDirectory() async {
    try {
      final hasDir = await FileAccessService.hasDirectory();
      if (!hasDir) return;

      final files = await FileAccessService.listFiles();
      for (final filename in files) {
        final name = FileAccessService.filenameToName(filename);
        final alreadyTracked = userPrompts.values.any(
          (p) => p["filename"] == filename,
        );
        if (!alreadyTracked) {
          final content = await FileAccessService.readFile(filename);
          if (content != null) {
            final id = "user_file_${DateTime.now().millisecondsSinceEpoch}";
            userPrompts[id] = {
              "id": id,
              "name": name,
              "content": content,
              "author": "User",
              "filename": filename,
              "updated": DateTime.now().millisecondsSinceEpoch.toString(),
            };
          }
        }
      }
      await _saveUserPrompts();
    } catch (e) {
      if (kDebugMode) print('[PromptRepository] _importFromDirectory error: $e');
    }
  }

  // ── Getters ───────────────────────────────────────────────────────────────

  String getPromptContent(String id) {
    if (id.isEmpty) return "";
    if (userPrompts.containsKey(id)) return userPrompts[id]["content"] ?? "";
    if (defaultPrompts.containsKey(id)) {
      return defaultPrompts[id]["content"] ?? "";
    }
    return "";
  }

  String getPromptName(String id) {
    if (userPrompts.containsKey(id)) {
      return userPrompts[id]["name"] ?? "Custom Prompt";
    }
    if (defaultPrompts.containsKey(id)) {
      return defaultPrompts[id]["name"] ?? "System Default";
    }
    return "Unknown Prompt";
  }

  // ── Mutations ─────────────────────────────────────────────────────────────

  Future<void> addUserPrompt(
    String id,
    String name,
    String content,
    String author,
  ) async {
    final oldFilename = userPrompts[id]?["filename"] as String?;
    final newFilename = FileAccessService.nameToFilename(name);

    userPrompts[id] = {
      "id": id,
      "name": name,
      "content": content,
      "author": author,
      "filename": newFilename,
      "updated": DateTime.now().millisecondsSinceEpoch.toString(),
    };
    await _saveUserPrompts();

    try {
      final hasDir = await FileAccessService.hasDirectory();
      if (hasDir) {
        if (oldFilename != null && oldFilename != newFilename) {
          await FileAccessService.renameFile(oldFilename, newFilename);
        }
        await FileAccessService.writeFile(newFilename, content);
      }
    } catch (e) {
      if (kDebugMode) print('[PromptRepository] SAF write error: $e');
    }
  }

  Future<void> deleteUserPrompt(String id) async {
    if (!userPrompts.containsKey(id)) return;
    final filename = userPrompts[id]["filename"] as String?;
    userPrompts.remove(id);
    await _saveUserPrompts();

    if (filename != null) {
      try {
        final hasDir = await FileAccessService.hasDirectory();
        if (hasDir) await FileAccessService.deleteFile(filename);
      } catch (e) {
        if (kDebugMode) print('[PromptRepository] SAF delete error: $e');
      }
    }
  }

  Future<void> cloneDefaultPrompt(String defaultId) async {
    if (!defaultPrompts.containsKey(defaultId)) return;
    final newId = "user_${DateTime.now().millisecondsSinceEpoch}";
    final name = "${defaultPrompts[defaultId]["name"]} (Copy)";
    final content = defaultPrompts[defaultId]["content"] ?? "";
    await addUserPrompt(newId, name, content, "User");
  }

  Future<void> _saveUserPrompts() async {
    final box = Hive.box('paios_storage');
    await box.put("user_prompts", jsonEncode(userPrompts));
    notifyEngine();
  }
}
