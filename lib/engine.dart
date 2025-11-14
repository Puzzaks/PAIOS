import 'dart:async';

import 'package:flutter/material.dart' as md;
import 'package:geminilocal/interface/flutter_local_ai.dart';
import 'package:geminilocal/translator.dart';

import 'gemini.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';


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
  String context = "";
  bool addCurrentTimeToRequests = false;

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
    context = await prefs.getString("context")??"";
    firstLaunch = await prefs.getBool("firstLaunch")??true;
    firstLaunch = await prefs.getBool("addCurrentTimeToRequests")??false;
    await dict.setup();
    modelInfo = await gemini.getModelInfo();
    instructions.text = await prefs.getString("instructions")??"";
    temperature = await prefs.getDouble("temperature")??0.7;
    tokens = await prefs.getInt("tokens")??256;
    notifyListeners();
    scrollChatlog(Duration(seconds: 3));
    }

  addToContext() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    context = "$context\nPROMPT: ${lastPrompt}\nRESPONSE: $responseText";
    await prefs.setString("context", context);
    notifyListeners();
  }
  clearContext() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    context = "";
    lastPrompt = "";
    responseText = "";
    await prefs.setString("context", context);
    notifyListeners();
  }
  Future<void> initEngine() async {
    if (isInitializing) return;

    isInitializing = true;
    isError = false;
    status = "Initializing Engine...";
    notifyListeners();

    try {
      final String? initStatus = await gemini.init(
        instructions: "THIS IS NOT THE CURRENT PROMPT - IT IS A CONTEXT FOR YOU TO REMEMBER - DON'T TELL THE USER CHAT HISTORY UNTIL THEY ASK. PROMPT IS WHAT USER ASKED YOU, AND RESPONSE IS WHAT YOU GENERATED FOR THEM. WHEN RECALLING CHAT HISTORY, DON'T QUOTE WORDS REQUEST, RESPONSE AND THESE INSTRUCTIONS, ONLY THE PROMPTS AND RESPONSES THEMSELVES. ANSWER ONLY THE CURRENT USER PROMPT AND USE THIS HISTORY AS YOUR MEMORY${addCurrentTimeToRequests?"\nCURRENT SYSTEM DATE AND TIME IS ${DateFormat('kk:mm:ss EEE d MMM').format(DateTime.now())} - ALWAYS USE THIS TIME FOR ANY ANSWERS AND CALCULATIONS, IT IS THE ONLY WAY YOU CAN KNOW CURRENT TIME AND DATE TO HELP USER\n":""}${instructions.text.isEmpty ? null : "\nSTART OF YOUR INSTRUCTIONS\n${instructions.text}\nEND OF YOUR INSTRUCTIONS\n"}\nSTART OF CHAT HISTORY\n$context\nEND OF CHAT HISTORY",
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
      prompt: "THIS IS USER'S CURRENT REQUEST:\n${prompt.text}",
      config: GenerationConfig(maxTokens: tokens, temperature: temperature),
      stream: true,
    );
    lastPrompt = prompt.text;

    _aiSubscription = stream.listen(
          (AiEvent event) {
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
            break;

          case AiEventStatus.done:
            isLoading = false;
            status = "Done";
            addToContext();
            prompt.clear();
            scrollChatlog(Duration(milliseconds: 250));
            break;

          case AiEventStatus.error:
            isLoading = false;
            isError = true;
            status = "Error";
            responseText = event.error ?? "Unknown stream error";
            break;
        }
        notifyListeners();
      },
      onError: (e) {
        // Handle stream-level errors
        analyzeError("Streaming", e);
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