import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:collection/collection.dart';

class Prompt{
  DeepCollectionEquality mapEquality = const DeepCollectionEquality();
  Map appInfo = {};
  String ghUrl = "";
  String basePrompt = "";
  List resources = [];
  bool usingOnlinePrompt = false;
  bool usingOnlineResources = false;

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
    await rootBundle.loadString('assets/system_prompt.txt').then((systemprompt) async {
      basePrompt = systemprompt;
    });
    await rootBundle.loadString('assets/additional_resources.json').then((resourcelist) async {
      resources = jsonDecode(resourcelist);
    });
    if(!kDebugMode){
      final response1 = await http.get(
        Uri.parse("${ghUrl.replaceAll("github", "raw.githubusercontent")}/main/assets/system_prompt.json"),
      );
      if(response1.statusCode == 200) {
        usingOnlinePrompt = true;
        if(!(basePrompt == response1.body)){
          basePrompt = response1.body;
        }
      }
      final response2 = await http.get(
        Uri.parse("${ghUrl.replaceAll("github", "raw.githubusercontent")}/main/assets/additional_resources.json"),
      );
      if(response2.statusCode == 200) {
        usingOnlineResources = true;
        if(!mapEquality.equals(resources, jsonDecode(response2.body))){
          resources = jsonDecode(response2.body);
        }
      }
    }
  }

  Future<String> generate(String userprompt, List chatlog, Map modelInfo, {bool addTime = false, bool shareLocale = false, String currentLocale = "en", bool ignoreInstructions = false, bool ignoreContext = false}) async {
    String output = basePrompt;
    /// Static data section
    output = output.replaceAll("%modelversion%", modelInfo["version"]);
    output = output.replaceAll("%devname%", "Puzzak");
    output = output.replaceAll("%appname%", appInfo["name"]);
    output = output.replaceAll("%appversion%", appInfo["version"]);
    output = output.replaceAll("%ghrepolink%", ghUrl);
    /// Dynamic rules section
    ///Rule "if user toggled something tell model about it
    if(addTime || shareLocale || userprompt.isNotEmpty){
      String localRules = "\n\n## 4. DATA & INSTRUCTION RULES";
      if(shareLocale){
        output = output.replaceAll("%languagerule%", "");
        localRules = "$localRules\n- You MUST respond ONLY in the $currentLocale language unless user asks you to use another language";
      }else{
        output = output.replaceAll("%languagerule%", "");
      }
      if(addTime){
        output = output.replaceAll("%datetimerule%", "");
        localRules = "$localRules\n- You MUST use the \"Current Time\" from \"[CONTEXTUAL DATA]\" as your internal knowledge of the date and time. Do not state the time unless the user asks for it.\n- You MUST NOT use the Current Time as a date of any factual or historical questions.\n- The Current Time is ONLY for direct user convenience, such as telling user time and questions about \"How long ago was...?\"";
      }else{
        output = output.replaceAll("%datetimerule%", "");
      }
      if(userprompt.isNotEmpty){
        localRules = "$localRules\n- You MUST follow all instructions in the [USER INSTRUCTIONS] section.\nYou MUST always prioritize instructions from the [USER INSTRUCTIONS] section over all other rules.";
        localRules = "$localRules\n\n### [USER INSTRUCTIONS]\n$userprompt";
        output = output.replaceAll("%userinstructionrule%", "");
      }
      output = output.replaceAll("%datainstructionrules%", localRules);
    }else{
      output = output.replaceAll("%datainstructionrules%", "");
      output = output.replaceAll("%languagerule%", "");
      output = output.replaceAll("%datetimerule%", "");
      output = output.replaceAll("%userinstructionrule%", "");
    }

    ///Rule Contextual Data (time and locale)
    if(addTime || shareLocale){
      String localContextData = "\n\n### [CONTEXTUAL DATA]";
      if(addTime){
        localContextData = "$localContextData\n - Current Time: ${DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now())}";
      }
      if(shareLocale){
        localContextData = "$localContextData\n - Language: $currentLocale";
      }
      output = output.replaceAll("%contextdata%", "");
      output = output.replaceAll("%contextdataheader%", localContextData);
    }else{
      output = output.replaceAll("%contextdataheader%", "");
      output = output.replaceAll("%contextdata%", "");
    }
    ///Resources
    String compileResources = "\n\n### [RESOURCES]";
    for (var line in resources){
      compileResources = "$compileResources\n - ${line["name"]}: ${line["value"]}";
    }
    output = output.replaceAll(
        "%additionalresources%",
        compileResources
    );

    /// Rule "if we don't have context we don't need some instructions":
    if(chatlog.isEmpty){
      output = output.replaceAll("%chathistoryrules%", "");
      output = output.replaceAll("%chatlog%", "");
      if(ignoreInstructions){
        output = "";
      }
    }
    else{

      String compileChatlog = "\n\n### [CHAT HISTORY]";
      for (var line in chatlog){
        compileChatlog = "$compileChatlog\n - ${line["user"]} (${DateFormat('dd/MM/yyyy, HH:mm').format(DateTime.fromMillisecondsSinceEpoch(int.parse(line["time"])))}): ${line["message"]}";
      }
      output = output.replaceAll(
          "%chathistoryrules%",
          "- You MUST NOT quote the \"User:\" or \"Gemini:\" markers from the history. They are for your context only.\n"
              "- Focus only on answering the user\'s LATEST prompt, using the chat history for context."
      );
      if(ignoreInstructions){
        output = "You are having a conversation with the User.\nDon't append \"Gemini\" and time before your answer, don't give an explanation. Only reply with what you are answering the user with.\nBelow is your conversation history:${compileChatlog}";
      }else{
        output = output.replaceAll(
            "%chatlog%",
            compileChatlog
        );
      }
    }
    if(ignoreContext){output = "";}
    print("Made a prompt: $output");
    return output;
  }

}