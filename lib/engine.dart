import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' as md;
import 'package:geminilocal/interface/flutter_local_ai.dart';
import 'package:geminilocal/translator.dart';

import 'gemini.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';


class aiEngine with md.ChangeNotifier {
  final gemini = FlutterLocalAi();
  final prompt = md.TextEditingController();
  final instructions = md.TextEditingController();

  Dictionary dict = Dictionary(
    path: "assets/translations",
    url: "https://raw.githubusercontent.com/Puzzaks/geminilocal/main"
  );
  late AiResponse response;
  String responseText = "";
  bool isLoading = false;
  bool isAvailable = false;
  bool isInitialized = false;
  bool isInitializing = false;
  String status = "";
  bool isError = false;
  bool firstLaunch = true;
  String lastPrompt = "";
  md.ScrollController scroller = md.ScrollController();

  // Config
  int tokens = 256; // Increased default
  double temperature = 0.7;
  Map modelInfo = {};
  List context = [];
  int contextSize = 0;
  bool addCurrentTimeToRequests = false;
  bool shareLocale = false;
  bool errorRetry = true;

  /// Subscription to manage the active AI stream
  StreamSubscription<AiEvent>? _aiSubscription;

  Future<Map> getAppData() async {
    final info = await PackageInfo.fromPlatform();
    final output = {
      "version": info.version,
      "build": info.buildNumber,
      "name": info.appName
    };
    return output;
  }

  Future<String> promptMaster(String prompt, List chatlog, {bool addTime = false, bool shareLocale = false}) async {
    Map appInfo = await getAppData();
    String currentLocale = "";
    for (var lang in dict.languages) {
      if(lang["id"] == dict.locale){
        currentLocale = lang["name"];
      }
    }
    String compileChatlog = "";
    for (var line in chatlog){
      compileChatlog = "$compileChatlog\n${line["user"]}: ${line["message"]}";
    }
    String output = "This list is your additional instructions that extend your basic instruction set and capabilities. Some of them will give you new data, some of them will fine-tune you to your environment. Try no never ignore these and use them as a reference of conversation history and current data.";
    List<String> prompts = [
      if(addTime) "Current user's system time is ${DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now())}. Please use this date and time like you know it, not like you are just copying it from here.",
      if(shareLocale) "User wants you to know that they are using $currentLocale as their app language - try to speak only in this language.",
      if(instructions.text.isNotEmpty) "User wants you to follow their instructions when answering every prompt. Their instructions: ${instructions.text}",
      "You will be given a history of your conversation with user. Please try to not quote the previous conversation until the user asks you to do so.",
      "If you are recalling what any of you spoke before now to user, try not to quote words \"User\" or \"Gemini\" as the part of your or user's message - these words are markers for you, not user.",
      "You should only answer current user's prompt, except when user asks you to answer about something you spoke beforehand.",
      "As an AI you understand what is context, temperature and token. Just a reminder that you are in a chat that has context window of approximately 4000 tokens, of which ${contextSize.toString()} are already used.",
      "The user has set you to generate responses of up to ${tokens.toString()} tokens long. It would be best if you generated as long text as possible without going over this limit. Your temperature is ${temperature.toString()}.",
      "You are a Gemini Nano AI, version ${modelInfo["version"]}, made by Google, running locally on user's device. Your purpose for last couple years was to help from within Android by providing translations, summaries and object recognition. Now Google published an API that allows developers to create apps like the one user is using now to have a normal conversation with you, offline, on device. This API is in Alpha now, but you as a model are not. You are not developed by Puzzak, you are a Google AI model, that is available via the app made by Puzzak. You are in alpha testing now, so this is the first time users have chance to speak to you.",
      "The user uses app made by single developer Puzzak in Ukraine who is NOT AFFILIATED WITH GOOGLE. You are a model running on a system level of user's phone withing Google AI Core service, and you are not a part of the  app. The app sends requests, and handles responses from AI Core, nothing else. You are working on a system level, the app is merely an interface for user. App is made only to speak to you on their phone via chat-like interface. They see a chat with your answers and can fine-tune you to their liking. Each answer is delivered to user token by token so user sees your response as you generate it.",
      "The interface application user speaking with you from is called ${appInfo["name"]}, version ${appInfo["version"]}. It's only purpose is to allow users to speak to you using your prompt generational AI capabilities. You can do more and go multimodal, but as of now this interface supports only text with markdown and nothing more.",
      "The app is still in development (just like you), so it's functionality may improve at any moment. The information stated here is accurate only for this moment. ",
      "You are welcome to discuss with user how you work and what do you know about yourself now. Try not to force conversation there, but if user asks - please talk with them and tell them everything you can about yourself and your environment. Be careful to tell users only truth and double-check what you are saying as information here is crucial for users to be able to trust in you. You don't have any connection to the internet or Google servers right now and in the app user uses you can ONLY generate text but this is not your only capability. ",
      "Here is a chat history for you to remember. In here each new line is a single message, where \"Gemini:\" means that is your answer and \"User:\" is what user asked.  Here's a chat history:\n$compileChatlog"
    ];
    for (var element in prompts) {
      output = "$output\n$element";
    }
    return output;
  }


  Future<void> endFirstLaunch () async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setBool("firstLaunch", false);
    firstLaunch = false;
    notifyListeners();
  }

  saveSettings () async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setDouble("temperature", temperature);
    prefs.setInt("tokens", tokens);
    prefs.setString("instructions", instructions.text);
    prefs.setBool("addCurrentTimeToRequests", addCurrentTimeToRequests);
    prefs.setBool("shareLocale", shareLocale);
    prefs.setBool("errorRetry", errorRetry);
  }

  scrollChatlog (Duration speed){
    scroller.animateTo(
      scroller.position.maxScrollExtent,
      duration: speed,
      curve: md.Curves.fastOutSlowIn,
    );
  }

  Future<void> checkAvailability() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if(prefs.containsKey("context")){
      context = jsonDecode(await prefs.getString("context")??"[]");
      contextSize = await prefs.getInt("contextSize")??0;
    }
    firstLaunch = await prefs.getBool("firstLaunch")??true;
    addCurrentTimeToRequests = await prefs.getBool("addCurrentTimeToRequests")??false;
    shareLocale = await prefs.getBool("shareLocale")??false;
    errorRetry = await prefs.getBool("errorRetry")??true;
    await dict.setup();
    modelInfo = await gemini.getModelInfo();
    instructions.text = await prefs.getString("instructions")??"";
    temperature = await prefs.getDouble("temperature")??0.7;
    tokens = await prefs.getInt("tokens")??256;
    notifyListeners();
    scrollChatlog(Duration(seconds: 3));
    await Future.delayed(Duration(seconds: 3));
    scrollChatlog(Duration(milliseconds: 250));
    }

  addToContext() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    contextSize = contextSize + responseText.split(' ').length + lastPrompt.split(' ').length;
    context.add({
      "user": "User",
      "message": lastPrompt
    });
    context.add({
      "user": "Gemini",
      "message": responseText
    });
    await prefs.setString("context", jsonEncode(context));
    await prefs.setInt("contextSize", contextSize);
    notifyListeners();
  }
  clearContext() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    context.clear();
    lastPrompt = "";
    responseText = "";
    await prefs.setString("context", jsonEncode(context));
    notifyListeners();
  }
  Future<void> initEngine() async {
    if (isInitializing) return;

    isInitializing = true;
    isError = false;
    status = "Initializing Engine...";
    notifyListeners();

    try {
      String sysInstructions = await promptMaster(
          instructions.text,
          context,
          addTime: addCurrentTimeToRequests,
          shareLocale: shareLocale
      );
      final String? initStatus = await gemini.init(
        instructions: sysInstructions,
      );
      if (initStatus != null && initStatus.contains("Error")) {
        isAvailable = false;
        isInitialized = false;
        status = "Engine Init Error";
        analyzeError("Initialization", initStatus);
      } else {
        isAvailable = true;
        isInitialized = true;
        status = "Engine Initialized: $initStatus";
      }
    } catch (e) {
      isAvailable = false;
      isInitialized = false;
      analyzeError("Initialization", e);
    } finally {
      isInitializing = false;
      notifyListeners();
    }
  }

  void checkAICore() {
    gemini.openAICorePlayStore();
  }

  /// Sets the error state
  void analyzeError(String action, dynamic e) {
    isError = true;
    status = "Error during $action";
    responseText = "$action: ${e.toString()}";
    isLoading = false;
    isInitializing = false;
    notifyListeners();
  }

  /// Cancels any ongoing generation
  void cancelGeneration() {
    _aiSubscription?.cancel();
    isLoading = false;
    status = "Generation cancelled";
    notifyListeners();
    scrollChatlog(Duration(milliseconds: 250));
  }


  Future<void> generateStream() async {
    if (prompt.text.isEmpty) {
      status = "Please enter your prompt";
      isError = true;
      notifyListeners();
      return;
    }
    if (isLoading) return; // Don't run if already generating

    // Ensure engine is ready
    if (!isInitializing) {
      await initEngine();
    }

    // Cancel any old streams
    await _aiSubscription?.cancel();

    // Set initial state for this new stream
    isLoading = true;
    isError = false;
    responseText = "";
    status = "Sending prompt...";
    notifyListeners();

    final stream = gemini.generateTextEvents(
      prompt: "User request:\n${prompt.text}",
      config: GenerationConfig(maxTokens: tokens, temperature: temperature),
      stream: true,
    );
    lastPrompt = prompt.text;

    _aiSubscription = stream.listen(
          (AiEvent event) async {
        switch (event.status) {
          case AiEventStatus.loading:
            isLoading = true;
            responseText = "";
            status = dict.value("waiting_for_AI");
            notifyListeners();
            break;

          case AiEventStatus.streaming:
            isLoading = true;
            String? finishReason = event.response?.finishReason;
            if(!(event.response?.finishReason=="null")) {
              switch(finishReason??"null"){
                case "0": print("Generation stopped (MAX_TOKENS): The maximum number of output tokens as specified in the request was reached.");break;
                case "1": print("Generation stopped (OTHER): Generic stop reason.");break;
                case "-100": print("Generation stopped (STOP): Natural stop point of the model.");break;
                default: print("Generation stopped (Code ${event.response?.finishReason}): Reason for stop was not specified");break;
              }
            }
            status = "Streaming response...";
            if (event.response != null) {
              response = event.response!;
              responseText = event.response!.text;
            }
            scrollChatlog(Duration(milliseconds: 250));
            await Future.delayed(Duration(milliseconds: 500));
            scrollChatlog(Duration(milliseconds: 250));
            break;

          case AiEventStatus.done:
            isLoading = false;
            status = "Done";
            addToContext();
            prompt.clear();
            scrollChatlog(Duration(milliseconds: 250));
            break;

          case AiEventStatus.error:
            if(errorRetry){
              await Future.delayed(Duration(milliseconds: 500));
              generateStream();
            }else{
              isLoading = false;
              isError = true;
              status = "Error";
              responseText = event.error ?? "Unknown stream error";
            }
            break;
        }
        notifyListeners();
      },
      onError: (e) async {
        if(errorRetry){
          await Future.delayed(Duration(milliseconds: 500));
          generateStream();
        }else {
          analyzeError("Streaming", e);
        }
      },
      onDone: () {
        // Final state update when stream closes
        isLoading = false;
        if (!isError) {
          status = "Stream complete";
        }
        notifyListeners();
      },
    );
  }

  /// Clean up resources
  @override
  void dispose() {
    prompt.dispose();
    instructions.dispose();
    _aiSubscription?.cancel(); // Cancel stream
    gemini.dispose(); // Tell native code to clean up
    super.dispose();
  }
}