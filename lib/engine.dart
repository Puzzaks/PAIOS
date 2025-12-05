import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as md;
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geminilocal/pages/support/elements.dart';
import 'package:geminilocal/parts/prompt.dart';
import 'package:geminilocal/parts/translator.dart';
import 'parts/gemini.dart';
import 'package:shared_preferences/shared_preferences.dart';


class AIEngine with md.ChangeNotifier {
  final gemini = GeminiNano();
  final prompt = md.TextEditingController();
  final instructions = md.TextEditingController();
  final chatName = md.TextEditingController();

  Dictionary dict = Dictionary(
      path: "assets/translations",
      url: "https://raw.githubusercontent.com/Puzzaks/geminilocal/main"
  );
  Prompt promptEngine = Prompt(ghUrl: "https://github.com/Puzzaks/geminilocal");
  AiResponse response = AiResponse(
    text: "Loading...",
    tokenCount: 1,
    chunk: "Loading...",
    generationTimeMs: 1,
    finishReason: ""
  );
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
  int usualModelSize = 3854827928;
  Map modelInfo = {};
  List context = [];
  int contextSize = 0;
  bool addCurrentTimeToRequests = false;
  bool shareLocale = false;
  bool errorRetry = true;
  bool appStarted = false;
  String testPrompt = "";
  Map resources = {};
  List modelDownloadLog = [];
  bool ignoreInstructions = false;
  bool ignoreContext = false;

  Map chats = {};
  String currentChat = "0";

  /// Subscription to manage the active AI stream
  StreamSubscription<AiEvent>? _aiSubscription;

  late Cards cards;

  /// This junk is to update all pages in case we have a modal that is focused in which case setState will not update content underneath it
  void genericRefresh (){
    notifyListeners();
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
    prefs.setBool("ignoreInstructions", ignoreInstructions);
  }

  scrollChatlog (Duration speed){
    scroller.animateTo(
      scroller.position.maxScrollExtent,
      duration: speed,
      curve: md.Curves.fastOutSlowIn,
    );
  }

  Future<void> start() async {
    await dict.setup();
    await checkEngine();
    await promptEngine.initialize();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if(prefs.containsKey("context")){
      context = jsonDecode(prefs.getString("context")??"[]");
      contextSize = prefs.getInt("contextSize")??0;
    }
    if(prefs.containsKey("chats")){
      chats = jsonDecode(prefs.getString("chats")??"[]");
    }
    addCurrentTimeToRequests = prefs.getBool("addCurrentTimeToRequests")??false;
    shareLocale = prefs.getBool("shareLocale")??false;
    errorRetry = prefs.getBool("errorRetry")??true;
    ignoreInstructions = prefs.getBool("ignoreInstructions")??false;
    instructions.text = prefs.getString("instructions")??"";
    temperature = prefs.getDouble("temperature")??0.7;
    tokens = prefs.getInt("tokens")??256;
    appStarted = true;
    notifyListeners();
    await Future.delayed(Duration(milliseconds: 250));
    scrollChatlog(Duration(seconds: 3));
    await Future.delayed(Duration(seconds: 3));
    scrollChatlog(Duration(milliseconds: 250));
  }

  void addDownloadLog(String log){
    modelDownloadLog.add(
        {
          "status": log.split("=")[0],
          "info": log.split("=")[1],
          "value": log.split("=")[2],
          "time": DateTime.now().millisecondsSinceEpoch
        }
    );
    notifyListeners();

  }

  lateNetCheck() async {
    while(firstLaunch){
      final connectivityResult = await (Connectivity().checkConnectivity());
      if (!connectivityResult.contains(ConnectivityResult.wifi)) {
        if(modelDownloadLog.isNotEmpty) {
          if (!(modelDownloadLog[modelDownloadLog.length - 1]["info"] == "waiting_network")) {
            if(modelDownloadLog[modelDownloadLog.length - 1]["info"] == "downloading_model"){
              addDownloadLog("Download=waiting_network=${modelDownloadLog[modelDownloadLog.length - 1]["value"]}");}
          }
        }
      } else {
        if(modelDownloadLog.isNotEmpty){
          if ((modelDownloadLog[modelDownloadLog.length - 1]["info"] == "waiting_network")) {
            addDownloadLog("Download=downloading_model=${modelDownloadLog[modelDownloadLog.length - 1]["value"]}");
          }
        }
      }
      await Future.delayed(Duration(seconds: 2));
    }
  }

  lateProgressCheck() async {
    Map lastUpdate = {};
    while(firstLaunch){
      await Future.delayed(Duration(seconds: 15));
      if(lastUpdate == {}){
        if(modelDownloadLog.isNotEmpty){
          lastUpdate = modelDownloadLog[modelDownloadLog.length - 1];
        }
      }
      if(modelDownloadLog.isNotEmpty){
        if(lastUpdate == modelDownloadLog[modelDownloadLog.length - 1]){ /// Nothing changed in the last 15 seconds, assume we have restarted and are not getting updates; We must restart the checkEngine. So...
          checkEngine();
        }else{
          lastUpdate = modelDownloadLog[modelDownloadLog.length - 1];
        }
      }
    }
  }

  Future<void> checkEngine() async {
    if(modelDownloadLog.isEmpty){
      lateNetCheck();
      lateProgressCheck();
    }
    modelDownloadLog.clear();
    gemini.statusStream = gemini.downloadChannel.receiveBroadcastStream().map((dynamic event) => event.toString());
    gemini.statusStream.listen((String downloadStatus) async {
      switch (downloadStatus.split("=")[0]){
        case "Available":
          modelInfo = await gemini.getModelInfo();
          if(modelInfo["version"]==null){
            await Future.delayed(Duration(seconds: 2));
            checkEngine();
          }else{
            if(modelInfo["status"]=="Available"){
              addDownloadLog("Available=Available=0");
              endFirstLaunch();
            }else{
              if(downloadStatus.split("=")[1] == "Download"){
                if(!(modelDownloadLog[modelDownloadLog.length-1]["info"] == "waiting_network")){
                  addDownloadLog("Download=downloading_model=0");
                }
              }else{
                addDownloadLog(downloadStatus);
              }
            }
          }
          break;
        case "Download":
          if(modelDownloadLog.isEmpty){
            addDownloadLog(downloadStatus);
          }else{
            if(!modelDownloadLog[modelDownloadLog.length-1]["value"].contains("error")){
              if(int.parse(downloadStatus.split("=")[2]) > int.parse(modelDownloadLog[modelDownloadLog.length-1]["value"])){
                addDownloadLog(downloadStatus);
              }
            }
          }
          break;
        case "Error":
          addDownloadLog(downloadStatus);
          if(downloadStatus.split("=")[2].contains("1-DOWNLOAD_ERROR")){
            checkEngine();
          }else{
            Fluttertoast.showToast(
                msg: "Gemini Nano ${dict.value("unavailable")}",
                toastLength: Toast.LENGTH_SHORT,
                fontSize: 16.0
            );
          }
          break;
        default:
          addDownloadLog(downloadStatus);
      }
    },
      onError: (e) async {
        analyzeError("Received new status: ", e);
      },
      onDone: () {
        notifyListeners();
      },
    );
  }
  
  addToContext() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    contextSize = contextSize + responseText.split(' ').length + lastPrompt.split(' ').length;
    context.add({
      "user": "User",
      "time": DateTime.now().millisecondsSinceEpoch.toString(),
      "message": lastPrompt
    });
    context.add({
      "user": "Gemini",
      "time": DateTime.now().millisecondsSinceEpoch.toString(),
      "message": responseText
    });
    await prefs.setString("context", jsonEncode(context));
    await prefs.setInt("contextSize", contextSize);
    if(currentChat == "0") {
      currentChat = DateTime.now().millisecondsSinceEpoch.toString();
    }
    await saveChat(context, chatID: currentChat);
    lastPrompt = "";
    responseText = "";
    notifyListeners();
  }

  deleteChat(String chatID){
    if(chats.containsKey(chatID) && !(chatID == "0")){
      chats.remove(chatID);
      notifyListeners();
    }
  }

  Future generateTitle (String input) async {
    ignoreContext = true;
    String newTitle = "Getting description";
    await gemini.init().then((initStatus) async {
      ignoreContext = false;
      if (initStatus == null) {
        analyzeError("Initialization", "Did not get response from AICore communication attempt");
      }else{
        if (initStatus.contains("Error")) {
          analyzeError("Initialization", initStatus);
        }else{
          await gemini.generateText(
            prompt: "Task: Create a short, 3-5 word title for this conversation.\n"
                "Rules:\n"
                "1. DO NOT use full sentences.\n"
                "2. DO NOT use phrases like \"The conversation is about\" or \"Summary of\".\n"
                "3. Be extremely concise.\n"
                "4. The title MUST be in the same language as the conversation.\n"
                "5. The title MUST be about whole conversation if there is more than one message.\n"
                "6. The title MUST NOT contain ANY name of any conversation party like \"Gemini\", \"Gemini's\", \"User\" or \"User's\".\n"
                "Examples:\n"
                "Conversation: \"Hello, how are you?\"\n"
                "Title: Greeting\n\n"
                "Conversation: \"Привіт, як справи?\"\n"
                "Title: Привітання\n\n"
                "Conversation: \"Write a python script to sort a list\"\n"
                "Title: Python sorting script\n\n"
                "Conversation: \"Why is the sky blue?\"\n"
                "Title: Sky color explanation\n\n"
                "Conversation: \"I need help with my printer\"\n"
                "Title: Printer troubleshooting\n\n"
                "Conversation: \"sdlkfjsdf\"\n"
                "Title: Random characters\n\n"
                "Conversation: \n\"$input\"\n"
                "Title: ",
            config: GenerationConfig(maxTokens: 20  , temperature: 0.7),
          ).then((title){
            newTitle = title.split('\n').first;
            newTitle = newTitle.replaceAll(RegExp(r'[*#_`]'), '').trim();
            if (newTitle.length > 40) {
              newTitle = "${newTitle.substring(0, 40)}...";
            }
          });
        }
      }
    });
    return newTitle.trim().replaceAll(".", "");
  }

  saveChats() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString("chats", jsonEncode(chats));
    genericRefresh();
  }

  saveChat(List conversation, {String chatID = "0"}) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if(chatID == "0") {
      chatID = DateTime.now().millisecondsSinceEpoch.toString();
    }
    if(conversation.isNotEmpty){
      if(chats.containsKey(chatID)){
        if(!chats[chatID]!.containsKey("name")){
          await Future.delayed(Duration(milliseconds: 500)); /// We have to wait some time because summarizing immediately will always result in overflowing the quota for some reason
          await generateTitle(conversation[0]["message"]).then((newTitle){
             chats[chatID]!["name"] =  newTitle;
           });
        }
        chats[chatID]!["history"] = jsonEncode(conversation).toString();
        chats[chatID]!["updated"] =  DateTime.now().millisecondsSinceEpoch.toString();
        chats[chatID]!["tokens"] =  contextSize.toString();
      }else{
        isLoading = true;
        await Future.delayed(Duration(milliseconds: 500)); /// We have to wait some time because summarizing immediately will always result in overflowing the quota for some reason
        String newTitle = "Still loading";
        String composeConversation = "";
        for (var line in conversation){
          composeConversation = "$composeConversation\n - ${line["message"]}";
        }
        await generateTitle(composeConversation).then((result){
          newTitle = result;
        });

        isLoading = false;
        chats[chatID] = {
          "name": newTitle,
          "tokens": contextSize.toString(),
          "pinned": false,
          "history": jsonEncode(conversation).toString(),
          "created": DateTime.now().millisecondsSinceEpoch.toString(),
          "updated": DateTime.now().millisecondsSinceEpoch.toString()
        };
      }
    }
    await prefs.setString("chats", jsonEncode(chats));
    genericRefresh();
  }

  clearContext() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    context.clear();
    contextSize = 0;
    lastPrompt = "";
    responseText = "";
    chats.remove(currentChat);
    await prefs.setString("chats", jsonEncode(chats));
    await prefs.setString("context", jsonEncode(context));
    await prefs.setInt("contextSize", contextSize);
    notifyListeners();
  }

  Future<void> initEngine() async {
    if (isInitializing) return;
    isInitializing = true;
    isError = false;
    notifyListeners();
    try {
      await promptEngine.generate(
          instructions.text,
          context,
          modelInfo,
          currentLocale: dict.value("current_language"),
          addTime: addCurrentTimeToRequests,
          shareLocale: shareLocale,
          ignoreInstructions: ignoreInstructions,
          ignoreContext: ignoreContext
      ).then((instruction) async {
        await gemini.init(instructions: instruction).then((initStatus){
          if (initStatus == null) {
            analyzeError("Initialization", "Did not get response from AICore communication attempt");
          }else{
            if (initStatus.contains("Error")) {
              analyzeError("Initialization", initStatus);
            }else{
              isAvailable = true;
              isInitialized = true;
            }
          }
        });
      });
    } catch (e) {
      analyzeError("Initialization", e);
    } finally {
      isInitializing = false;
      notifyListeners();
    }
  }


  /// Sets the error state
  void analyzeError(String action, dynamic e) {
    isAvailable = false;
    isError = true;
    isInitialized = false;
    isInitializing = false;
    status = "Error during $action: ${e.toString()}";
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
      prompt: "User's request: ${prompt.text.trim()}",
      config: GenerationConfig(maxTokens: tokens, temperature: temperature),
      stream: true,
    );
    lastPrompt = prompt.text.trim();


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
                case "0": if (kDebugMode) {print("Generation stopped (MAX_TOKENS): The maximum number of output tokens as specified in the request was reached.");}break;
                case "1": if (kDebugMode) {print("Generation stopped (OTHER): Generic stop reason.");}break;
                case "-100": if (kDebugMode) {print("Generation stopped (STOP): Natural stop point of the model.");}break;
                default: if (kDebugMode) {print("Generation stopped (Code ${event.response?.finishReason}): Reason for stop was not specified");}break;
              }
            }
            status = "Streaming response...";
            if (event.response != null) {
              response = event.response!;
              responseText = event.response!.text;
            }
            try{
              scrollChatlog(Duration(milliseconds: 250));
              await Future.delayed(Duration(milliseconds: 500));
              scrollChatlog(Duration(milliseconds: 250));
            }catch(e){
              if (kDebugMode) {
                print("Can't scroll: $e");
              }
              await Future.delayed(Duration(milliseconds: 500));
            }
            break;

          case AiEventStatus.done:
            if(responseText == ""){
              if(errorRetry){
                if(event.response?.text == null){
                  isLoading = false;
                  Fluttertoast.showToast(
                      msg: "Unable to generate response.",
                      toastLength: Toast.LENGTH_SHORT,
                      fontSize: 16.0
                  );
                }else{
                  await Future.delayed(Duration(milliseconds: 500));
                  generateStream();
                }
              }else{
                isLoading = false;
                isError = true;
                status = "Error";
                responseText = event.error ?? "Unknown stream error";
              }
            }else{
              isLoading = false;
              status = "Done";
              addToContext();
              prompt.clear();
              try{
                scrollChatlog(Duration(milliseconds: 250));
              }catch(e){
                if (kDebugMode) {
                  print("Can't scroll: $e");
                }
              }
            }
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
        genericRefresh();
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
        genericRefresh();
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