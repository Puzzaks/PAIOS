import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:collection/collection.dart';
import 'package:m3x_mesh/m3x_mesh.dart';

class Prompt{
  DeepCollectionEquality mapEquality = const DeepCollectionEquality();
  Map appInfo = {};
  String ghUrl = "";

  Prompt._internal(this.ghUrl,);
  factory Prompt({required String ghUrl}){
    return Prompt._internal(ghUrl);
  }

  Future<Map> getAppData() async {
    try {
      final info = await PackageInfo.fromPlatform()
          .timeout(const Duration(seconds: 3));
      return {
        "version": info.version,
        "name": info.appName,
      };
    } catch (_) {
      return {
        "version": "",
        "name": "PAIOS",
      };
    }
  }

  initialize() async {
    appInfo = await getAppData();
  }

  static const String _attachedImageCue =
      '[An image is attached to the current user message. Answer directly from what you see in the image.]';
  static const int defaultContinuationTailChars = 450;
  static const int defaultContinuationPersonaChars = 240;
  static const int defaultContinuationQuestionChars = 220;

  static String _replacePlaceholders(
    String template,
    Map modelInfo,
    Map appInfo,
    String ghUrl,
  ) {
    return template
        .replaceAll("%modelversion%", modelInfo["version"] ?? "Unknown")
        .replaceAll("%devname%", "Puzzak")
        .replaceAll("%appname%", appInfo["name"] ?? "PAIOS")
        .replaceAll("%appversion%", appInfo["version"] ?? "")
        .replaceAll("%ghrepolink%", ghUrl)
        .replaceAll(RegExp(r'%\w+%'), '');
  }

  static String boundHeadAtBoundary(
    String text,
    int maxChars, {
    bool appendEllipsis = true,
  }) {
    final trimmed = text.trim();
    if (maxChars <= 0 || trimmed.isEmpty) return "";
    if (trimmed.length <= maxChars) return trimmed;
    final cut = trimmed.substring(0, maxChars);
    final lastBreak = cut.lastIndexOf(RegExp(r'[\s\n]'));
    final clean = lastBreak >= (maxChars * 0.6).floor()
        ? cut.substring(0, lastBreak).trimRight()
        : cut.trimRight();
    return appendEllipsis ? "$clean..." : clean;
  }

  /// Bounds [text] to at most [maxChars] from the end, advancing the start to
  /// a nearby line or word boundary while keeping the exact trailing characters intact.
  static String boundTailAtBoundary(
    String text, {
    int maxChars = defaultContinuationTailChars,
  }) {
    if (maxChars <= 0 || text.isEmpty) return "";
    if (text.length <= maxChars) return text;
    final tail = text.substring(text.length - maxChars);
    final searchLimit = tail.length ~/ 3 < 96 ? tail.length ~/ 3 : 96;
    for (int i = 0; i < searchLimit; i++) {
      final ch = tail[i];
      if (ch == '\n' || ch == ' ' || ch == '\t') {
        int nextIdx = i + 1;
        while (nextIdx < tail.length &&
            (tail[nextIdx] == ' ' || tail[nextIdx] == '\t')) {
          nextIdx++;
        }
        if (nextIdx < tail.length) {
          return tail.substring(nextIdx);
        }
      }
    }
    return tail;
  }

  String _formatHistoryLine(dynamic line) {
    final rawTime = line["time"]?.toString() ?? "";
    final epochMs = int.tryParse(rawTime);
    final timeStr = epochMs != null
        ? DateFormat('dd/MM/yyyy, HH:mm')
            .format(DateTime.fromMillisecondsSinceEpoch(epochMs))
        : rawTime;
    final imagePath = line["imagePath"]?.toString();
    final hasImage = imagePath != null && imagePath.trim().isNotEmpty;
    final imageDescription = line["imageDescription"]?.toString().trim();
    final hasDescription =
        imageDescription != null && imageDescription.isNotEmpty;
    final attachmentSuffix = hasDescription
        ? " [image attached: $imageDescription]"
        : (hasImage ? " [image attached]" : "");
    return "\n - ${line["user"]} ($timeStr) : ${line["message"]}$attachmentSuffix";
  }

  String _resolveSystemInstructions(String userprompt, Map modelInfo) {
    final resolved = _replacePlaceholders(userprompt, modelInfo, appInfo, ghUrl);
    return "## [SYSTEM INSTRUCTIONS]\n$resolved";
  }

  String _buildContextualData({
    required bool addTime,
    required bool shareLocale,
    required String currentLocale,
  }) {
    if (!addTime && !shareLocale) return "";
    String contextData = "\n\n### [CONTEXTUAL DATA]";
    if (addTime) {
      contextData +=
          "\n - Current Time: ${DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now())}";
    }
    if (shareLocale) {
      contextData += "\n - Language: $currentLocale";
    }
    return contextData;
  }

  Future<String> generate(
    String userprompt,
    List chatlog,
    Map modelInfo, {
    bool addTime = false,
    bool shareLocale = false,
    String currentLocale = "en",
    bool ignoreInstructions = false,
    bool ignoreContext = false,
    List<M3xTool>? tools,
    bool includeTools = true,
    bool hasAttachedImage = false,
  }) async {
    // Used only for title generation — skip everything
    if (ignoreContext) return "";

    // ignoreInstructions: bare conversation wrapper only (no system prompt)
    if (ignoreInstructions) {
      if (chatlog.isEmpty && !hasAttachedImage) return "";
      String bare = "You are having a conversation with the User.\n"
          "Reply directly with your answer without prepending \"Gemini\" or a timestamp.";
      if (chatlog.isNotEmpty) {
        bare += "\n\n### [CHAT HISTORY]";
        for (var line in chatlog) {
          bare += _formatHistoryLine(line);
        }
      }
      if (hasAttachedImage) {
        bare += "\n\n$_attachedImageCue";
      }
      return bare;
    }

    // ── 1. System instructions block ─────────────────────────────────────────
    String output = _resolveSystemInstructions(userprompt, modelInfo);

    // ── 2. Optional contextual data ──────────────────────────────────────────
    output += _buildContextualData(
      addTime: addTime,
      shareLocale: shareLocale,
      currentLocale: currentLocale,
    );

    // ── 3. Concise positive guidelines ───────────────────────────────────────
    final List<String> guidelines = [
      "Respond naturally and concisely to greetings, casual conversation, and general questions.",
      "Stay truthful and concise; say when you do not know something instead of guessing.",
    ];
    if (hasAttachedImage) {
      guidelines.add("Answer directly using the attached image.");
    }
    if (shareLocale) {
      guidelines.add(
        "Respond in $currentLocale unless the user asks for another language.",
      );
    }
    if (addTime) {
      guidelines.add(
        "Use Current Time from [CONTEXTUAL DATA] when the user asks about the current date or time.",
      );
    }
    output += "\n\n## [GUIDELINES]";
    for (final line in guidelines) {
      output += "\n - $line";
    }

    // ── 4. Available tools (only when enabled and non-empty) ─────────────────
    if (includeTools && tools != null && tools.isNotEmpty) {
      output += "\n\n### [AVAILABLE TOOLS]"
          "\nUse a tool only when the user explicitly asks for live data or an app action covered below; otherwise reply directly in plain text."
          '\nWhen calling a tool, respond with ONLY a JSON object using double quotes:'
          '\n{"tool": "<tool>", "app": "<app>", "args": {}}'
          '\nIf a tool takes no parameters, set "args": {} (never leave "args": empty).'
          '\nAlways fill ALL required arguments in "args" (e.g. for wikipedia_details always include non-empty "query" and "question"). Never call wikipedia_details with empty "args": {}.'
          "\n\nTools:";
      for (final tool in tools) {
        final appStr = tool.app != null ? ' (app: "${tool.app}")' : '';
        output += "\n - ${tool.name}$appStr: ${tool.description}"
            "\n   args schema: ${jsonEncode(tool.parameters)}";
      }
    }

    // ── 5. Chat history ───────────────────────────────────────────────────────
    if (chatlog.isNotEmpty) {
      output += "\n\n### [CHAT HISTORY]"
          "\n - Use history for context and focus on the user's latest message.";
      for (var line in chatlog) {
        output += _formatHistoryLine(line);
      }
    }

    if (hasAttachedImage) {
      output += "\n\n$_attachedImageCue";
    }

    return output;
  }

  /// Builds a compact system prompt for silent continuation of a truncated response.
  ///
  /// Keeps persona, question, and partial response strictly bounded (tail-only)
  /// so tight-budget models like Gemini Nano v3 retain maximum output headroom
  /// across multiple continuation rounds.
  Future<String> generateContinuation(
    String userprompt,
    Map modelInfo,
    String partialText,
    String originalQuestion, {
    bool addTime = false,
    bool shareLocale = false,
    String currentLocale = "en",
    int maxPartialChars = defaultContinuationTailChars,
    int maxPersonaChars = defaultContinuationPersonaChars,
    int maxQuestionChars = defaultContinuationQuestionChars,
  }) async {
    final resolvedPersona = _replacePlaceholders(
      userprompt,
      modelInfo,
      appInfo,
      ghUrl,
    );
    final boundedPersona = boundHeadAtBoundary(
      resolvedPersona,
      maxPersonaChars,
      appendEllipsis: false,
    );
    final boundedQuestion = boundHeadAtBoundary(
      originalQuestion,
      maxQuestionChars,
      appendEllipsis: false,
    );
    final boundedTail = boundTailAtBoundary(
      partialText,
      maxChars: maxPartialChars,
    );

    final trimmedPartial = partialText.trimLeft();
    final isJsonDraft = trimmedPartial.startsWith('{') ||
        trimmedPartial.startsWith('```json') ||
        RegExp(r'^```(?:json)?\s*\{', caseSensitive: false)
            .hasMatch(trimmedPartial) ||
        (trimmedPartial.contains('"tool"') &&
            (trimmedPartial.contains('"args"') ||
                trimmedPartial.contains('"action"')));

    final buffer = StringBuffer("## [CONTINUATION]\n");
    if (boundedPersona.isNotEmpty) {
      buffer.writeln("Persona: $boundedPersona");
    }
    if (shareLocale && currentLocale.trim().isNotEmpty) {
      buffer.writeln("Language: ${currentLocale.trim()}.");
    }
    if (addTime) {
      buffer.writeln(
        "Current Time: ${DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now())}",
      );
    }
    if (boundedQuestion.isNotEmpty) {
      buffer.writeln('Question: "$boundedQuestion"');
    }
    buffer.writeln("Partial answer tail:");
    buffer.writeln(boundedTail);
    buffer.write("Continue seamlessly from the exact end without repeating.");
    buffer.write(
      " Do NOT prepend an ellipsis (...) or repeat words. Complete the trailing thought concisely without starting unrelated new sections.",
    );
    if (isJsonDraft) {
      buffer.write(
        " This is an incomplete JSON tool call: output ONLY the remaining valid JSON characters (and closing ``` if opened), with NO prose.",
      );
    }
    return buffer.toString();
  }
}