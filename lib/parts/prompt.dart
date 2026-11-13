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
    final info = await PackageInfo.fromPlatform();
    final output = {
      "version": info.version,
      "name": info.appName
    };
    return output;
  }

  initialize() async {
    appInfo = await getAppData();
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
  }) async {
    // Used only for title generation — skip everything
    if (ignoreContext) return "";

    // ignoreInstructions: bare conversation wrapper only (no system prompt)
    if (ignoreInstructions) {
      if (chatlog.isEmpty) return "";
      String bare = "You are having a conversation with the User.\n"
          "Don't prepend \"Gemini\" or a timestamp before your answer. Only reply with your answer.\n\n"
          "### [CHAT HISTORY]";
      for (var line in chatlog) {
        bare += "\n - ${line["user"]} (${DateFormat('dd/MM/yyyy, HH:mm').format(DateTime.fromMillisecondsSinceEpoch(int.parse(line["time"])))}) : ${line["message"]}";
      }
      return bare;
    }

    // ── 1. System instructions block ─────────────────────────────────────────
    String output = "## [SYSTEM INSTRUCTIONS]\n$userprompt";

    // Replace static values that may appear in any prompt (e.g. system_default.md)
    output = output
        .replaceAll("%modelversion%", modelInfo["version"] ?? "Unknown")
        .replaceAll("%devname%", "Puzzak")
        .replaceAll("%appname%", appInfo["name"] ?? "PAIOS")
        .replaceAll("%appversion%", appInfo["version"] ?? "")
        .replaceAll("%ghrepolink%", ghUrl);

    // Strip any leftover legacy placeholders so they don't confuse the model
    output = output.replaceAll(RegExp(r'%\w+%'), '');


    if (addTime || shareLocale) {
      String contextData = "\n\n### [CONTEXTUAL DATA]";
      if (addTime) {
        contextData += "\n - Current Time: ${DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now())}";
      }
      if (shareLocale) {
        contextData += "\n - Language: $currentLocale";
      }
      output += contextData;
    }

    // ── 4. Data & instruction rules ───────────────────────────────────────────
    List<String> rules = [];
    if (shareLocale) {
      rules.add("You MUST respond ONLY in the $currentLocale language unless the user asks you to switch.");
    }
    if (addTime) {
      rules.add("You MUST use the \"Current Time\" from [CONTEXTUAL DATA] as your knowledge of the current date and time. Do not volunteer the time unless the user asks.");
      rules.add("You MUST NOT use Current Time as the date for factual or historical questions.");
      rules.add("Current Time is only for direct user convenience, e.g. telling the time or answering \"how long ago was...?\".");
    }
    if (rules.isNotEmpty) {
      output += "\n\n## [DATA & INSTRUCTION RULES]";
      for (var rule in rules) {
        output += "\n - $rule";
      }
    }

    // ── 4b. Available tools ───────────────────────────────────────────────────
    if (includeTools && tools != null && tools.isNotEmpty) {
      output += "\n\n### [AVAILABLE TOOLS]"
          "\nYou have access to external agentic tools provided by connected applications in the M3x mesh."
          "\n\nCRITICAL TOOL INVOCATION RULES:"
          "\n1. ONLY invoke a tool when the user's latest message explicitly asks for information, status, or an action that REQUIRES that specific tool."
          '\n2. NEVER invoke a tool for general knowledge, conceptual questions about AI models, Gemini Nano, your own identity, greetings (e.g. "hi", "hello", "who are you"), pleasantries, or casual conversation. Answer all conceptual, identity, and general knowledge questions directly from your own training without calling any tool.'
          "\n3. NEVER guess or invoke a tool speculatively. If unsure, respond conversationally."
          "\n4. NEVER invoke a tool when the user is asking about visual contents, images, photos, UI widgets, screenshots, or apps visible on the screen, or when no tool exists for the requested data. There is NO tool for reading screen apps or images; inspect the attached image directly or answer honestly that no such tool exists."
          "\n\nWhen a tool is genuinely required by the user's explicit request, respond ONLY with a valid JSON tool call block using double quotes:"
          '\n```json'
          '\n{"action": "tool_call", "app": "<app>", "tool": "<tool>", "description": "Checking live data", "arguments": {}}'
          '\n```'
          '\nDo not add any text before or after the JSON block.'
          '\nMake description very short, for example for tool "alerts_get_summary" description can be "Getting Air Raid Alerts".'
          '\n\nAvailable tool schemas:';
      for (final tool in tools) {
        final appStr = tool.app != null ? ' (app: "${tool.app}")' : '';
        output += "\n - ${tool.name}$appStr: ${tool.description}"
            "\n   arguments schema: ${jsonEncode(tool.parameters)}";
      }
    }

    // ── 5. Chat history ───────────────────────────────────────────────────────
    if (chatlog.isNotEmpty) {
      output += "\n\n### [CHAT HISTORY]"
          "\n - Do NOT quote the \"User:\" or \"Gemini:\" markers — they are context markers for you only."
          "\n - Focus on the user's LATEST message, using the history only for context.";
      for (var line in chatlog) {
        output += "\n - ${line["user"]} (${DateFormat('dd/MM/yyyy, HH:mm').format(DateTime.fromMillisecondsSinceEpoch(int.parse(line["time"])))}) : ${line["message"]}";
      }
    }

    return output;
  }

  /// Builds a system prompt for silent continuation of a truncated response.
  ///
  /// There is NO user turn — the model gets a [CONTINUATION] system directive
  /// with the original question AND the partial text it already wrote, so it
  /// can tell when its answer is semantically complete and stop on its own.
  Future<String> generateContinuation(
    String userprompt,
    Map modelInfo,
    String partialText,
    String originalQuestion, {
    bool addTime = false,
    bool shareLocale = false,
    String currentLocale = "en",
  }) async {
    // Same system persona
    String output = "## [SYSTEM INSTRUCTIONS]\n$userprompt";
    output = output
        .replaceAll("%modelversion%", modelInfo["version"] ?? "Unknown")
        .replaceAll("%devname%", "Puzzak")
        .replaceAll("%appname%", appInfo["name"] ?? "PAIOS")
        .replaceAll("%appversion%", appInfo["version"] ?? "")
        .replaceAll("%ghrepolink%", ghUrl);
    output = output.replaceAll(RegExp(r'%\w+%'), '');

    if (addTime || shareLocale) {
      String contextData = "\n\n### [CONTEXTUAL DATA]";
      if (addTime) {
        contextData += "\n - Current Time: ${DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now())}";
      }
      if (shareLocale) {
        contextData += "\n - Language: $currentLocale";
      }
      output += contextData;
    }

    List<String> rules = [];
    if (shareLocale) {
      rules.add("You MUST respond ONLY in the $currentLocale language unless the user asks you to switch.");
    }
    if (addTime) {
      rules.add("You MUST use the \"Current Time\" from [CONTEXTUAL DATA] as your knowledge of the current date and time. Do not volunteer the time unless the user asks.");
    }
    if (rules.isNotEmpty) {
      output += "\n\n## [DATA & INSTRUCTION RULES]";
      for (var rule in rules) {
        output += "\n - $rule";
      }
    }

    // System-level continuation — includes the original question so the model
    // knows WHAT it's answering and can recognise when the answer is complete.
    final trimmedPartial = partialText.trimLeft();
    final isJsonDraft = trimmedPartial.startsWith('{') ||
        trimmedPartial.startsWith('```json') ||
        trimmedPartial.contains('"action"') && trimmedPartial.contains('"tool"');
    output += "\n\n## [CONTINUATION]\n"
        "The user's original question was: \"$originalQuestion\"\n"
        "Your response was interrupted before completion.\n"
        "Rules:\n"
        " - Output ONLY the exact remaining characters/tokens to complete the partial text below.\n"
        " - Do NOT restart, summarise, or repeat content already in the partial text.\n"
        " - Do NOT add any preamble, greeting, or acknowledgment.\n"
        " - Pick up EXACTLY at the final character of the partial text — continue mid-word or mid-JSON if needed.\n"
        "${isJsonDraft ? ' - The partial text is an incomplete JSON tool call: output ONLY the remaining valid JSON characters (and closing ``` if opened) to complete it, with NO prose.\n' : ' - Once your answer to the original question is complete, STOP. Do not pad or extend.\n'}"
        "--- PARTIAL TEXT (continue from here) ---\n"
        "$partialText\n"
        "--- END OF PARTIAL TEXT ---";

    return output;
  }
}