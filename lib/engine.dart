import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart' as md;
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geminilocal/interface/flutter_local_ai.dart';
import 'package:geminilocal/parts/prompt.dart';
import 'package:geminilocal/parts/translator.dart';
import 'parts/gemini.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:async/async.dart';


class aiEngine with md.ChangeNotifier {
  final gemini = FlutterLocalAi();
  final prompt = md.TextEditingController();
  final instructions = md.TextEditingController();

  Dictionary dict = Dictionary(
      path: "assets/translations",
      url: "https://raw.githubusercontent.com/Puzzaks/geminilocal/main"
  );
  Prompt promptEngine = Prompt(ghUrl: "https://github.com/Puzzaks/geminilocal");
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

  /// Subscription to manage the active AI stream
  StreamSubscription<AiEvent>? _aiSubscription;





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

  Future<void> start() async {
    await dict.setup();
    await checkEngine();
    await promptEngine.initialize();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if(prefs.containsKey("context")){
      context = jsonDecode(await prefs.getString("context")??"[]");
      contextSize = await prefs.getInt("contextSize")??0;
    }
    addCurrentTimeToRequests = await prefs.getBool("addCurrentTimeToRequests")??false;
    shareLocale = await prefs.getBool("shareLocale")??false;
    errorRetry = await prefs.getBool("errorRetry")??true;
    instructions.text = await prefs.getString("instructions")??"";
    temperature = await prefs.getDouble("temperature")??0.7;
    tokens = await prefs.getInt("tokens")??256;
    appStarted = true;
    notifyListeners();
    await Future.delayed(Duration(milliseconds: 250));
    scrollChatlog(Duration(seconds: 3));
    await Future.delayed(Duration(seconds: 3));
    scrollChatlog(Duration(milliseconds: 250));
  }

  void addDownloadLog(String log){
    print("Adding from ${log.split("=")[0]} (${log.split("=")[1]}, ${log.split("=")[2]})");
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


  Future<void> lateNetCheck(int time) async {
    await Future.delayed(Duration(seconds: 1));
    if(time == modelDownloadLog[modelDownloadLog.length-1]["time"]){
      final connectivityResult = await (Connectivity().checkConnectivity());
      if (!connectivityResult.contains(ConnectivityResult.wifi)) {
        addDownloadLog("Download=waiting_network=${modelDownloadLog[modelDownloadLog.length-1]["value"]}");
      }
    }
  }

  Future<void> checkEngine() async {
    gemini.statusStream = gemini.downloadChannel.receiveBroadcastStream().map((dynamic event) => event.toString());
    gemini.statusStream.listen((String downloadStatus) async {
      switch (downloadStatus.split("=")[0]){
        case "Available":
          modelInfo = await gemini.getModelInfo();
          if(modelInfo["version"]==null){
            checkEngine();
          }else{
            endFirstLaunch();
          }
          addDownloadLog(downloadStatus);
          break;
        case "Download":
          if(modelDownloadLog.isEmpty){
            addDownloadLog(downloadStatus);
          }else{
            if(int.parse(downloadStatus.split("=")[2]) > int.parse(modelDownloadLog[modelDownloadLog.length-1]["value"])){
              addDownloadLog(downloadStatus);
            }
          }
          lateNetCheck(modelDownloadLog[modelDownloadLog.length-1]["time"]);
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
      "time": DateTime.now().millisecondsSinceEpoch,
      "message": lastPrompt
    });
    context.add({
      "user": "Gemini",
      "time": DateTime.now().millisecondsSinceEpoch,
      "message": responseText
    });
    await prefs.setString("context", jsonEncode(context));
    await prefs.setInt("contextSize", contextSize);
    notifyListeners();
  }
  clearContext() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    context.clear();
    contextSize = 0;
    lastPrompt = "";
    responseText = "";
    await prefs.setString("context", jsonEncode(context));
    await prefs.setInt("contextSize", contextSize);
    notifyListeners();
  }

  Future<void> initEngine() async {
    print("Reloading model");
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
      ).then((instruction) async {
        print("RULES");
        print(instruction.split("# 3. CONVERSATION RULES")[0]);
        print("# 3. CONVERSATION RULES${instruction.split("# 3. CONVERSATION RULES")[1]}");
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
      prompt: "User request:\n${prompt.text.trim()}",
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