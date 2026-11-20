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

  Future<Map> getAppData({PackageInfo? packageInfo}) async {
    try {
      final info = packageInfo ??
          await PackageInfo.fromPlatform().timeout(const Duration(seconds: 3));
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

  Future<void> initialize({PackageInfo? packageInfo}) async {
    appInfo = await getAppData(packageInfo: packageInfo);
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

  static const int defaultMaxHistoryChars = 2800;
  static const int defaultMaxToolSchemaChars = 3500;
  static const int _maxHistoricalMessageChars = 700;
  static const int _maxActiveToolResultChars = 1200;
  static const int _maxHistoricalToolSummaryChars = 120;

  static bool _isToolCallJsonMessage(String text) {
    final trimmed = text.trim();
    if (!trimmed.startsWith('{') && !trimmed.startsWith('```')) return false;
    return RegExp(
      r'''["'](?:tool|method)["']\s*:|["']action["']\s*:\s*["']tool(?:_)?call["']''',
      caseSensitive: false,
    ).hasMatch(trimmed);
  }

  static bool _isToolResultMessage(String text) {
    final trimmed = text.trimLeft();
    return trimmed.startsWith('[TOOL RESULT:') ||
        trimmed.startsWith('[TOOL ERROR');
  }

  static String _compactToolSchema(Map<String, dynamic> parameters) {
    final rawProps = parameters['properties'];
    if (rawProps is! Map || rawProps.isEmpty) {
      return '{}';
    }
    final Set<String> requiredSet = <String>{
      if (parameters['required'] is List)
        for (final r in parameters['required'] as List) r.toString(),
    };
    final List<String> parts = <String>[];
    rawProps.forEach((key, value) {
      final propName = key.toString();
      final bool isRequired =
          requiredSet.isEmpty ? false : requiredSet.contains(propName);
      String typeStr = 'any';
      if (value is Map) {
        final rawEnum = value['enum'];
        if (rawEnum is List && rawEnum.isNotEmpty && rawEnum.length <= 4) {
          typeStr = rawEnum.map((e) => e.toString()).join('|');
        } else {
          final rawType = value['type']?.toString() ?? 'any';
          if (rawType == 'array' && value['items'] is Map) {
            final itemType = (value['items'] as Map)['type']?.toString();
            typeStr = itemType != null ? 'array<$itemType>' : 'array';
          } else {
            typeStr = rawType;
          }
        }
      }
      parts.add('$propName${isRequired ? '' : '?'}: $typeStr');
    });
    return '{${parts.join(', ')}}';
  }

  List<String> _buildBoundedHistoryLines(
    List chatlog, {
    required int maxHistoryChars,
    required bool compactHistoryTools,
  }) {
    if (chatlog.isEmpty || maxHistoryChars <= 0) return const <String>[];

    // Identify trailing active tool-turn chain (User -> Gemini tool JSON -> System tool results)
    int activeChainStart = chatlog.length;
    if (compactHistoryTools) {
      final last = chatlog.last;
      final lastUser = last is Map ? last['user']?.toString() ?? '' : '';
      final lastMsg = last is Map ? last['message']?.toString() ?? '' : '';
      final bool hasActiveToolTail = lastUser == 'System' ||
          (lastUser == 'Gemini' && _isToolCallJsonMessage(lastMsg));
      if (hasActiveToolTail) {
        int idx = chatlog.length - 1;
        while (idx >= 0) {
          final item = chatlog[idx];
          if (item is! Map) break;
          final u = item['user']?.toString() ?? '';
          final m = item['message']?.toString() ?? '';
          if (u == 'System' ||
              (u == 'Gemini' && _isToolCallJsonMessage(m))) {
            activeChainStart = idx;
            idx--;
            continue;
          }
          if (u == 'User') {
            activeChainStart = idx;
          }
          break;
        }
      }
    }

    final List<({String user, String formatted})> reversedSelected =
        <({String user, String formatted})>[];
    int usedChars = 0;

    for (int i = chatlog.length - 1; i >= 0; i--) {
      final rawItem = chatlog[i];
      if (rawItem is! Map) continue;
      final String user = rawItem['user']?.toString() ?? '';
      final String rawMsg = rawItem['message']?.toString() ?? '';
      final bool isInActiveChain = i >= activeChainStart;

      String effectiveMsg = rawMsg;
      if (compactHistoryTools && !isInActiveChain) {
        if (user == 'Gemini' && _isToolCallJsonMessage(rawMsg)) {
          continue;
        }
        if (user == 'System' && _isToolResultMessage(rawMsg)) {
          final singleLine = rawMsg.replaceAll(RegExp(r'\s+'), ' ').trim();
          effectiveMsg = boundHeadAtBoundary(
            singleLine,
            _maxHistoricalToolSummaryChars,
          );
        }
      }

      if (isInActiveChain &&
          user == 'System' &&
          effectiveMsg.length > _maxActiveToolResultChars) {
        effectiveMsg = boundHeadAtBoundary(
          effectiveMsg,
          _maxActiveToolResultChars,
        );
      } else if (!(isInActiveChain && user == 'System') &&
          effectiveMsg.length > _maxHistoricalMessageChars) {
        effectiveMsg = boundHeadAtBoundary(
          effectiveMsg,
          _maxHistoricalMessageChars,
        );
      }

      final lineCopy = Map<String, dynamic>.from(rawItem)
        ..['message'] = effectiveMsg;
      String formatted = _formatHistoryLine(lineCopy);

      if (reversedSelected.isEmpty && formatted.length > maxHistoryChars) {
        final overflow = formatted.length - maxHistoryChars;
        final nextLen = effectiveMsg.length - overflow;
        if (nextLen > 40) {
          lineCopy['message'] = boundHeadAtBoundary(effectiveMsg, nextLen);
          formatted = _formatHistoryLine(lineCopy);
        }
      }

      if (reversedSelected.isNotEmpty &&
          usedChars + formatted.length > maxHistoryChars) {
        break;
      }

      reversedSelected.add((user: user, formatted: formatted));
      usedChars += formatted.length;
    }

    // Avoid starting the oldest retained turn with an orphaned Gemini reply if a
    // newer User turn is present.
    while (reversedSelected.length > 1 &&
        reversedSelected.last.user == 'Gemini') {
      final hasNewerUser = reversedSelected
          .take(reversedSelected.length - 1)
          .any((entry) => entry.user == 'User');
      if (!hasNewerUser) break;
      reversedSelected.removeLast();
    }

    return reversedSelected.reversed.map((e) => e.formatted).toList();
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
    int? maxHistoryChars,
    int? maxToolSchemaChars,
    bool compactHistoryTools = true,
  }) async {
    // Used only for title generation — skip everything
    if (ignoreContext) return "";

    final int historyBudget = maxHistoryChars ?? defaultMaxHistoryChars;
    final int schemaBudget = maxToolSchemaChars ?? defaultMaxToolSchemaChars;

    // ignoreInstructions: bare conversation wrapper only (no system prompt)
    if (ignoreInstructions) {
      if (chatlog.isEmpty && !hasAttachedImage) return "";
      String bare = "You are having a conversation with the User.\n"
          "Reply directly with your answer without prepending \"Gemini\" or a timestamp.";
      final historyLines = _buildBoundedHistoryLines(
        chatlog,
        maxHistoryChars: historyBudget,
        compactHistoryTools: compactHistoryTools,
      );
      if (historyLines.isNotEmpty) {
        bare += "\n\n### [CHAT HISTORY]";
        for (final line in historyLines) {
          bare += line;
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
      final hasWikipediaTools = tools.any(
        (t) => t.name == 'wikipedia_summary' || t.name == 'wikipedia_details',
      );
      final toolsBuffer = StringBuffer()
        ..write("\n\n### [AVAILABLE TOOLS]")
        ..write(
          "\nUse a tool only when the user explicitly asks for live data or an app action covered below; otherwise reply directly in plain text.",
        )
        ..write(
          '\nWhen calling a tool, respond with ONLY a JSON object using double quotes:',
        )
        ..write('\n{"tool": "<tool>", "app": "<app>", "args": {}}')
        ..write(
          '\nIf a tool takes no parameters, set "args": {} (never leave "args": empty).',
        )
        ..write(
          '\nAlways fill ALL required arguments in "args" (never leave empty "args": {} when parameters are required).',
        )
        ..write(
          hasWikipediaTools
              ? ' Prefer wikipedia_summary for general "What is X?" explanations; use wikipedia_details only when looking up a specific fact inside a Wikipedia article.'
              : '',
        )
        ..write("\n\nTools:");
      int addedTools = 0;
      for (final tool in tools) {
        final appStr = tool.app != null ? ' (app: "${tool.app}")' : '';
        final compactDesc = boundHeadAtBoundary(tool.description, 160);
        final compactArgs = _compactToolSchema(tool.parameters);
        final entry =
            "\n - ${tool.name}$appStr: $compactDesc\n   args: $compactArgs";
        if (addedTools > 0 && toolsBuffer.length + entry.length > schemaBudget) {
          break;
        }
        toolsBuffer.write(entry);
        addedTools++;
      }
      output += toolsBuffer.toString();
    }

    // ── 5. Chat history ───────────────────────────────────────────────────────
    final historyLines = _buildBoundedHistoryLines(
      chatlog,
      maxHistoryChars: historyBudget,
      compactHistoryTools: compactHistoryTools,
    );
    if (historyLines.isNotEmpty) {
      output += "\n\n### [CHAT HISTORY]"
          "\n - Use history for context and focus on the user's latest message.";
      for (final line in historyLines) {
        output += line;
      }
    }

    if (hasAttachedImage) {
      output += "\n\n$_attachedImageCue";
    }

    return output;
  }

  static final RegExp _trailingWordCharRegex = RegExp(
    r'[\p{L}\p{N}]$',
    unicode: true,
  );

  /// If [text] ends inside a letter/digit sequence (no trailing whitespace or
  /// punctuation) and whitespace appears within [maxTrimChars] from the end,
  /// returns `(completeTail, partialToken)` where `completeTail` ends right
  /// after that whitespace and `partialToken` is the trailing token.
  static ({String completeTail, String partialToken})? splitTrailingPartialWord(
    String text, {
    int maxTrimChars = 28,
  }) {
    if (text.isEmpty || !_trailingWordCharRegex.hasMatch(text)) {
      return null;
    }
    final minIndex = text.length > maxTrimChars ? text.length - maxTrimChars : 0;
    for (int i = text.length - 1; i >= minIndex; i--) {
      final ch = text[i];
      if (ch == ' ' || ch == '\t' || ch == '\n') {
        final splitPos = i + 1;
        if (splitPos < text.length && i > 0) {
          return (
            completeTail: text.substring(0, splitPos),
            partialToken: text.substring(splitPos),
          );
        }
        return null;
      }
    }
    return null;
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
    final partialSplit =
        isJsonDraft ? null : splitTrailingPartialWord(boundedTail);

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
    if (isJsonDraft) {
      buffer.write(
        " Do NOT prepend an ellipsis (...) or repeat words. Complete the trailing thought concisely without starting unrelated new sections.",
      );
      buffer.write(
        " This is an incomplete JSON tool call: output ONLY the remaining valid JSON characters (and closing ``` if opened), with NO prose.",
      );
    } else if (partialSplit != null) {
      final completeTailCue = boundTailAtBoundary(
        partialSplit.completeTail,
        maxChars: 28,
      );
      buffer.write(
        ' No "...", repeats, or duplicate summary. If "${partialSplit.partialToken}" was cut off, finish cleanly after "$completeTailCue".',
      );
    } else {
      buffer.write(
        ' Finish the unfinished sentence naturally from the exact tail word without "...", repeating earlier sentences, or starting a duplicate summary paragraph.',
      );
    }
    return buffer.toString();
  }
}