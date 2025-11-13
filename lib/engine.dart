import 'dart:async';

import 'package:flutter/material.dart' as md;
import 'package:geminilocal/interface/flutter_local_ai.dart';

import 'gemini.dart';


class aiEngine with md.ChangeNotifier {
  final gemini = FlutterLocalAi();
  final prompt = md.TextEditingController();
  final instructions = md.TextEditingController();

  late AiResponse response;
  String responseText = "";
  bool isLoading = false;
  bool isAvailable = false;
  bool isInitialized = false;
  bool isInitializing = false;
  String status = "Engine not initialized";
  bool isError = false;

  // Config
  int tokens = 256; // Increased default
  double temperature = 0.7;

  /// Subscription to manage the active AI stream
  StreamSubscription<AiEvent>? _aiSubscription;

  /// Call this from your UI (e.g., in initState) to start the engine.
  Future<void> initEngine() async {
    if (isInitializing || isInitialized) return;

    isInitializing = true;
    isError = false;
    status = "Initializing Engine...";
    notifyListeners();

    try {
      // The new init method returns a status string.
      final String? initStatus = await gemini.init(
        instructions: instructions.text.isEmpty ? null : instructions.text,
      );

      if (initStatus != null && initStatus.contains("Error")) {
        isAvailable = false;
        isInitialized = false;
        status = "Engine Init Error";
        analyzeError("Initialization", initStatus);
      } else {
        // Any non-error response means it's available
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

  /// Prompts user to install/update AICore
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

  /// Performs a one-shot generation (waits for full response).
  Future<void> generate() async {
    if (prompt.text.isEmpty) {
      status = "Please enter your prompt";
      isError = true;
      notifyListeners();
      return;
    }
    if (isLoading) return; // Don't run if already generating

    // Ensure engine is ready
    if (!isInitialized) {
      await initEngine();
      if (!isInitialized) return; // Init failed
    }

    // Cancel any old streams
    await _aiSubscription?.cancel();

    isLoading = true;
    isError = false;
    responseText = "";
    status = "Generating...";
    notifyListeners();

    try {
      response = await gemini.generateText(
        prompt: prompt.text,
        config: GenerationConfig(maxTokens: tokens, temperature: temperature),
      );
      print("The response was: $response");
      responseText = response.text;
      status = "Done";

    } catch (e) {
      analyzeError("Generation", e);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// --- NEW: Performs a streaming generation ---
  /// This function returns immediately and updates the state via notifyListeners
  /// for each chunk.
  Future<void> generateStream() async {
    if (prompt.text.isEmpty) {
      status = "Please enter your prompt";
      isError = true;
      notifyListeners();
      return;
    }
    if (isLoading) return; // Don't run if already generating

    // Ensure engine is ready
    if (!isInitialized) {
      await initEngine();
      if (!isInitialized) return; // Init failed
    }

    // Cancel any old streams
    await _aiSubscription?.cancel();

    // Set initial state for this new stream
    isLoading = true;
    isError = false;
    responseText = "";
    status = "Sending prompt...";
    notifyListeners();

    // Get the unified event stream
    final stream = gemini.generateTextEvents(
      prompt: prompt.text,
      config: GenerationConfig(maxTokens: tokens, temperature: temperature),
      stream: true, // Make sure we ask for the streaming method
    );

    // Listen to the stream
    _aiSubscription = stream.listen(
          (AiEvent event) {
        // This is your idea in action!
        // We update the state based on the event status.
        switch (event.status) {
          case AiEventStatus.loading:
            isLoading = true;
            status = "Generating...";
            responseText = "";
            break;

          case AiEventStatus.streaming:
            isLoading = true; // Still loading, but receiving data
            status = "Streaming response...";
            if (event.response != null) {
              response = event.response!;
              responseText = event.response!.text; // Update with cumulative text
            }
            break;

          case AiEventStatus.done:
            isLoading = false;
            status = "Done";
            if (event.response != null) {
              responseText = event.response!.text; // Set final text
            }
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