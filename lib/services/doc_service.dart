import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:m3x_mesh/m3x_mesh.dart';
import 'package:path_provider/path_provider.dart';

/// Structured result returned by [DocService.searchDoc] and [DocService.searchAll].
class DocSearchResult {
  final bool found;
  final String title;
  final String sectionTitle;
  final String pageId;
  final String pageTitle;
  final String content;
  final double score;

  const DocSearchResult({
    required this.found,
    required this.title,
    this.sectionTitle = '',
    this.pageId = '',
    this.pageTitle = '',
    required this.content,
    this.score = 0.0,
  });

  Map<String, dynamic> toJson() => {
    'found': found,
    'title': title,
    'sectionTitle': sectionTitle.isNotEmpty ? sectionTitle : title,
    'pageId': pageId,
    'pageTitle': pageTitle,
    'content': content,
    'score': score,
  };
}

/// A parsed markdown section chunked by `## ` heading.
class DocSection {
  final String id;
  final String title;
  final String content;
  final String pageId;

  const DocSection({
    required this.id,
    required this.title,
    required this.content,
    this.pageId = '',
  });
}

/// Model representing a full documentation page in the 3-Tier SWR system.
class DocPage {
  final String id;
  final String title;
  final String icon;
  final String content;
  final List<DocSection> sections;
  final bool isOfflineFallback;
  final DateTime? lastUpdated;
  final String? remoteUrl;
  final String? officialUrl;
  final String? bundledAsset;

  const DocPage({
    required this.id,
    required this.title,
    required this.icon,
    required this.content,
    required this.sections,
    this.isOfflineFallback = false,
    this.lastUpdated,
    this.remoteUrl,
    this.officialUrl,
    this.bundledAsset,
  });

  DocPage copyWith({
    String? id,
    String? title,
    String? icon,
    String? content,
    List<DocSection>? sections,
    bool? isOfflineFallback,
    DateTime? lastUpdated,
    String? remoteUrl,
    String? officialUrl,
    String? bundledAsset,
  }) {
    return DocPage(
      id: id ?? this.id,
      title: title ?? this.title,
      icon: icon ?? this.icon,
      content: content ?? this.content,
      sections: sections ?? this.sections,
      isOfflineFallback: isOfflineFallback ?? this.isOfflineFallback,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      remoteUrl: remoteUrl ?? this.remoteUrl,
      officialUrl: officialUrl ?? this.officialUrl,
      bundledAsset: bundledAsset ?? this.bundledAsset,
    );
  }
}

/// Service providing bundled and remote Google ML Kit GenAI / AICore documentation,
/// 3-Tier SWR caching (Bundled -> Disk Cache -> Background Remote SWR),
/// cross-page global search & term-frequency scoring, and agentic mesh tool registration.
class DocService with ChangeNotifier {
  static final DocService instance = DocService._internal();
  DocService._internal();
  factory DocService() => instance;

  static const String manifestAssetPath = 'assets/docs/docs_manifest.json';
  static const String assetPath = 'assets/docs/genai.md.txt';

  /// Testing injection hooks
  @visibleForTesting
  Directory? customCacheDirectory;
  @visibleForTesting
  http.Client? customHttpClient;

  final Map<String, DocPage> _pages = {};
  String _selectedPageId = 'devices';
  bool _isLoaded = false;
  bool _isSyncing = false;

  bool get isLoaded => _isLoaded;
  bool get isSyncing => _isSyncing;
  List<DocPage> get pages => List.unmodifiable(_pages.values);
  String get selectedPageId => _selectedPageId;

  DocPage? get currentPage =>
      _pages[_selectedPageId] ?? (_pages.isNotEmpty ? _pages.values.first : null);

  /// Backwards-compatible accessors returning active page's content and sections.
  String get rawMarkdown => currentPage?.content ?? '';
  List<DocSection> get sections =>
      currentPage?.sections ?? (_pages.isNotEmpty ? _pages.values.first.sections : const []);
  List<DocSection> get allSections =>
      _pages.values.expand((p) => p.sections).toList();

  /// Changes the currently viewed documentation page.
  void selectPage(String id) {
    if (_pages.containsKey(id) && _selectedPageId != id) {
      _selectedPageId = id;
      notifyListeners();
    }
  }

  /// Resolves the local cache directory for documentation pages.
  Future<Directory?> _getCacheDirectory() async {
    if (customCacheDirectory != null) return customCacheDirectory;
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${docDir.path}/docs_cache');
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }
      return cacheDir;
    } catch (_) {
      return null;
    }
  }

  /// Default fallback manifest if asset loading fails.
  static const List<Map<String, dynamic>> _fallbackManifest = [
    {
      "id": "devices",
      "title": "Supported Devices & Hardware",
      "bundledAsset": "assets/docs/genai.md.txt",
      "remoteUrl": "https://raw.githubusercontent.com/Puzzaks/PAIOS/main/assets/docs/genai.md.txt",
      "icon": "devices"
    },
    {
      "id": "aicore_preview",
      "title": "AICore Developer Preview",
      "remoteUrl": "https://developers.google.com/ml-kit/genai/aicore-dev-preview.md.txt",
      "icon": "science"
    },
    {
      "id": "agent_api",
      "title": "ML Kit GenAI Agent Workflows",
      "remoteUrl": "https://developers.google.com/ml-kit/genai/agent/android.md.txt",
      "icon": "smart_toy"
    },
    {
      "id": "tts_api",
      "title": "On-Device Neural Text-to-Speech",
      "remoteUrl": "https://developers.google.com/ml-kit/genai/text-to-speech/android.md.txt",
      "icon": "record_voice_over"
    },
    {
      "id": "direct_model",
      "title": "Direct Model Access & Prompt API",
      "remoteUrl": "https://developers.google.com/ml-kit/genai/prompt-api.md.txt",
      "icon": "terminal"
    },
    {
      "id": "structured_output",
      "title": "Structured Output & Function Calling",
      "remoteUrl": "https://developers.google.com/ml-kit/genai/structured-output.md.txt",
      "icon": "data_object"
    },
    {
      "id": "speech_recognition",
      "title": "Speech Recognition & Translation",
      "remoteUrl": "https://developers.google.com/ml-kit/genai/speech-recognition/android.md.txt",
      "icon": "translate"
    },
    {
      "id": "summarization",
      "title": "On-Device Summarization & Rewriting",
      "remoteUrl": "https://developers.google.com/ml-kit/genai/summarization.md.txt",
      "icon": "auto_stories"
    }
  ];

  /// Loads manifest, checks Tier 2 (Disk Cache), falls back to Tier 1 (Bundled Assets),
  /// and prepares all pages for immediate 0ms offline availability.
  Future<void> initialize([String? customAssetPath, bool force = false]) async {
    if (_isLoaded && customAssetPath == null && !force) return;

    List<Map<String, dynamic>> manifestList = _fallbackManifest;
    try {
      final manifestJson = await rootBundle.loadString(manifestAssetPath);
      final decoded = jsonDecode(manifestJson);
      if (decoded is List) {
        manifestList = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {
      // Use fallback manifest on read error
    }

    final cacheDir = await _getCacheDirectory();
    _pages.clear();

    for (final item in manifestList) {
      final id = item['id'] as String;
      final title = item['title'] as String;
      final icon = (item['icon'] as String?) ?? 'article';
      final bundledAsset = item['bundledAsset'] as String?;
      final remoteUrl = item['remoteUrl'] as String?;
      final officialUrl = item['officialUrl'] as String?;

      String content = '';
      bool isOfflineFallback = false;
      DateTime? lastUpdated;

      // Tier 2: Disk Cache
      if (cacheDir != null) {
        try {
          final cacheFile = File('${cacheDir.path}/$id.md.txt');
          if (await cacheFile.exists()) {
            final diskText = await cacheFile.readAsString();
            if (diskText.trim().isNotEmpty && !_isHtml(diskText)) {
              content = diskText;
              isOfflineFallback = false;
              lastUpdated = await cacheFile.lastModified();
            }
          }
        } catch (_) {}
      }

      // Tier 1: Bundled Asset (if not in disk cache)
      if (content.isEmpty && (bundledAsset != null || (customAssetPath != null && id == 'devices'))) {
        try {
          final loadPath = (id == 'devices' && customAssetPath != null)
              ? customAssetPath
              : (bundledAsset ?? assetPath);
          content = await rootBundle.loadString(loadPath);
          isOfflineFallback = true;
        } catch (_) {}
      }

      // Offline placeholder content if not yet cached
      if (content.isEmpty) {
        content = _getFallbackContent(id, title);
        isOfflineFallback = true;
      }

      final sections = _parseSections(content, pageId: id);
      _pages[id] = DocPage(
        id: id,
        title: title,
        icon: icon,
        content: content,
        sections: sections,
        isOfflineFallback: isOfflineFallback,
        lastUpdated: lastUpdated,
        remoteUrl: remoteUrl,
        officialUrl: officialUrl,
        bundledAsset: bundledAsset,
      );
    }

    if (_pages.containsKey('devices')) {
      _selectedPageId = 'devices';
    } else if (_pages.isNotEmpty) {
      _selectedPageId = _pages.keys.first;
    }

    _isLoaded = true;
    notifyListeners();
  }

  /// Parses markdown into indexed sections split by `## ` headings.
  List<DocSection> _parseSections(String markdown, {String pageId = ''}) {
    final sections = <DocSection>[];
    final headerRegex = RegExp(r'(?:^|\n)##\s+([^\n]+)');
    final matches = headerRegex.allMatches(markdown).toList();

    for (int i = 0; i < matches.length; i++) {
      final match = matches[i];
      final title = match.group(1)?.trim() ?? 'Section ${i + 1}';
      final id = title.toLowerCase().replaceAll(RegExp(r'[^\w]+'), '_');

      final startPos = match.end;
      final endPos = (i + 1 < matches.length) ? matches[i + 1].start : markdown.length;
      final content = markdown.substring(startPos, endPos).trim();

      sections.add(DocSection(
        id: id,
        title: title,
        content: content,
        pageId: pageId,
      ));
    }

    if (sections.isEmpty && markdown.trim().isNotEmpty) {
      sections.add(DocSection(
        id: 'overview',
        title: 'Overview',
        content: markdown.trim(),
        pageId: pageId,
      ));
    }

    return sections;
  }

  /// Tier 3: Asynchronous background SWR documentation synchronization.
  /// Fetches remote pure markdown directly from Google's `.md.txt` endpoints,
  /// saves to disk cache, and updates in-memory pages.
  /// If offline or if the remote endpoint times out or errors, cleanly catches errors
  /// and preserves Tier 1 or Tier 2 content without blocking.
  Future<void> syncRemoteDocs({bool force = false}) async {
    if (_isSyncing && !force) return;
    _isSyncing = true;
    notifyListeners();

    try {
      final cacheDir = await _getCacheDirectory();
      final client = customHttpClient ?? http.Client();

      for (final page in _pages.values.toList()) {
        final url = page.remoteUrl;
        if (url == null || url.isEmpty) continue;

        try {
          final response = await client
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 4));

          if (response.statusCode == 200) {
            final body = response.body.trim();
            if (body.isNotEmpty && !_isHtml(body)) {
              if (cacheDir != null) {
                try {
                  final cacheFile = File('${cacheDir.path}/${page.id}.md.txt');
                  await cacheFile.writeAsString(body);
                } catch (_) {}
              }

              _pages[page.id] = page.copyWith(
                content: body,
                sections: _parseSections(body, pageId: page.id),
                isOfflineFallback: false,
                lastUpdated: DateTime.now(),
              );
              notifyListeners();
            }
          }
        } catch (_) {
          // Silently preserve Tier 1 or Tier 2
        }
      }
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// Manually clears the disk cache and refreshes a specific documentation page from remote.
  /// Fetches Google's pure `.md.txt` endpoint directly.
  /// If remote fetch succeeds, saves to disk cache, marks isOfflineFallback: false,
  /// updates lastUpdated, and notifies listeners.
  /// If remote fetch fails or is offline, reloads from bundled asset, marks isOfflineFallback: true,
  /// updates lastUpdated, and notifies listeners.
  Future<bool> refreshDoc(String id) async {
    final page = _pages[id];
    if (page == null) return false;

    _isSyncing = true;
    notifyListeners();

    bool success = false;
    try {
      final cacheDir = await _getCacheDirectory();
      if (cacheDir != null) {
        try {
          final cacheFile = File('${cacheDir.path}/$id.md.txt');
          if (await cacheFile.exists()) {
            await cacheFile.delete();
          }
        } catch (_) {}
      }

      final client = customHttpClient ?? http.Client();
      final url = page.remoteUrl;

      if (url != null && url.isNotEmpty) {
        try {
          final response = await client
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 4));

          if (response.statusCode == 200) {
            final body = response.body.trim();
            if (body.isNotEmpty && !_isHtml(body)) {
              if (cacheDir != null) {
                try {
                  final cacheFile = File('${cacheDir.path}/$id.md.txt');
                  await cacheFile.writeAsString(body);
                } catch (_) {}
              }

              _pages[id] = page.copyWith(
                content: body,
                sections: _parseSections(body, pageId: id),
                isOfflineFallback: false,
                lastUpdated: DateTime.now(),
              );
              success = true;
            }
          }
        } catch (_) {}
      }

      if (!success) {
        // Fall back to bundled asset cleanly
        String content = '';
        if (page.bundledAsset != null) {
          try {
            content = await rootBundle.loadString(page.bundledAsset!);
          } catch (_) {}
        }
        if (content.isEmpty) {
          content = page.content;
        }

        _pages[id] = page.copyWith(
          content: content,
          sections: _parseSections(content, pageId: id),
          isOfflineFallback: true,
          lastUpdated: DateTime.now(),
        );
      }
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
    return success;
  }

  /// Simple heuristic stemmer for query terms.
  static String _stem(String term) {
    if (term.endsWith('ing') && term.length > 5) return term.substring(0, term.length - 3);
    if (term.endsWith('ed') && term.length > 4) return term.substring(0, term.length - 2);
    if (term.endsWith('es') && term.length > 4) return term.substring(0, term.length - 2);
    if (term.endsWith('s') && term.length > 3 && !term.endsWith('ss')) return term.substring(0, term.length - 1);
    if (term.endsWith('e') && term.length > 4) return term.substring(0, term.length - 1);
    return term;
  }

  /// Validates that a fetched response body is plain markdown and not an HTML error document.
  static bool _isHtml(String body) {
    final lower = body.toLowerCase();
    return lower.startsWith('<!doctype html') ||
        lower.startsWith('<html') ||
        (lower.contains('<head>') && lower.contains('<body>'));
  }

  /// Global Search & Local RAG across all loaded pages and sections.
  Future<DocSearchResult> searchDoc(String query) async {
    if (!_isLoaded) {
      await initialize();
    }

    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const DocSearchResult(
        found: false,
        title: '',
        content: 'Please provide a search query to search AICore documentation.',
      );
    }

    final results = searchAll(trimmed);
    if (results.isNotEmpty && results.first.score >= 4.0) {
      return results.first;
    }

    return DocSearchResult(
      found: false,
      title: '',
      content: 'No relevant documentation found for "$query".',
    );
  }

  /// Returns all matching sections across all pages ranked by term-frequency relevance score.
  List<DocSearchResult> searchAll(String query) {
    if (!_isLoaded) return const [];
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final lowerQuery = trimmed.toLowerCase();
    final rawTerms = lowerQuery
        .replaceAll(RegExp(r'[^\w\s\-]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();

    final results = <DocSearchResult>[];

    for (final page in _pages.values) {
      for (final section in page.sections) {
        double score = 0.0;
        final lowerTitle = section.title.toLowerCase();
        final lowerContent = section.content.toLowerCase();

        // Exact full query match in title (highest confidence)
        if (lowerTitle.contains(lowerQuery)) {
          score += 60.0;
        }
        // Exact full query match in content
        if (lowerContent.contains(lowerQuery)) {
          score += 30.0;
        }

        for (final term in rawTerms) {
          if (term.length < 2 && !term.startsWith('-')) continue;
          final stem = _stem(term);

          // Title keyword match (exact or stemmed)
          if (lowerTitle.contains(term)) {
            score += 30.0;
          } else if (stem.length >= 4 && lowerTitle.contains(stem)) {
            score += 20.0;
          }

          // Content term frequency (exact or stemmed)
          final termMatches = term.allMatches(lowerContent).length;
          final stemMatches = (stem != term && stem.length >= 4)
              ? stem.allMatches(lowerContent).length
              : 0;
          final effectiveMatches = termMatches > 0 ? termMatches : stemMatches;

          if (effectiveMatches > 0) {
            score += 3.0 * (effectiveMatches > 8 ? 8 : effectiveMatches);
          }

          // Specific boost for domain keywords and error codes
          if (term.startsWith('-') ||
              term == 'busy' ||
              term == 'background' ||
              term == 'token' ||
              term == 'quota' ||
              term == 'pixel' ||
              term == 'vision' ||
              term.startsWith('downsampl')) {
            if (lowerTitle.contains(term) || lowerTitle.contains(stem)) {
              score += 25.0;
            } else if (lowerContent.contains(term) || lowerContent.contains(stem)) {
              score += 15.0;
            }
          }
        }

        if (score >= 4.0) {
          results.add(DocSearchResult(
            found: true,
            title: section.title,
            sectionTitle: section.title,
            pageId: page.id,
            pageTitle: page.title,
            content: section.content,
            score: score,
          ));
        }
      }
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    return results;
  }

  /// Fallback markdown content for pages before remote sync completes.
  static String _getFallbackContent(String id, String title) {
    switch (id) {
      case 'aicore_preview':
        return '''
# AICore Developer Preview

> [!NOTE]
> This guide is synchronized dynamically from the Google ML Kit portal. Connect to the Internet to download the latest developer preview specs.

## Overview & Beta Channels
The Android AICore Developer Preview provides early access to next-generation Gemini Nano models, LoRA fine-tuned adapters, and experimental system services.

## Prerequisites & Beta Enrollment
- Android 14+ (API level 34 or higher).
- Google Play Services AICore beta enrollment.
- Supported NPU hardware accelerator (Tensor G3/G4, Snapdragon 8 Gen 3+, Dimensity 9300+).

## Offline Status
To view the full live specification, connect to Wi-Fi or cellular network. The guide will automatically synchronize in the background on app launch.
''';
      case 'agent_api':
        return '''
# ML Kit GenAI Agent Workflows

> [!NOTE]
> This guide is synchronized dynamically from the Google ML Kit portal. Connect to the Internet to download the latest agent workflow specs.

## Overview & Agent Loop
Build autonomous on-device agent pipelines using Gemini Nano tool execution, structured output schemas, and multi-turn function calling.

## Tool Calling & Registration
Register tools via M3xToolRegistry and allow local models to invoke device APIs, sensor queries, and cross-application mesh interactions.

## Offline Status
To view the full live specification, connect to Wi-Fi or cellular network. The guide will automatically synchronize in the background on app launch.
''';
      case 'tts_api':
        return '''
# On-Device Neural Text-to-Speech

> [!NOTE]
> This guide is synchronized dynamically from the Google ML Kit portal. Connect to the Internet to download the latest neural TTS specs.

## Overview & Neural Voice Engine
Low-latency, on-device neural voice synthesis powered by lightweight acoustic models and Android's native text-to-speech engine.

## Synthesizer Configuration
Configure streaming audio buffers, sample rates (24kHz), pitch, speed, and language voices for hands-free local AI conversations.

## Offline Status
To view the full live specification, connect to Wi-Fi or cellular network. The guide will automatically synchronize in the background on app launch.
''';
      case 'direct_model':
        return '''
# Direct Model Access & Prompt API

> [!NOTE]
> This guide is synchronized dynamically from the Google ML Kit portal. Connect to the Internet to download the latest Prompt API specs.

## Direct Model Architecture
Direct execution against on-device Gemini foundation models without network round-trips.

## Context Window & Sampling
Control temperature, topK, candidate counts, and system prompt contexts for deterministic local reasoning.

## Offline Status
To view the full live specification, connect to Wi-Fi or cellular network. The guide will automatically synchronize in the background on app launch.
''';
      case 'structured_output':
        return '''
# Structured Output & Function Calling

> [!NOTE]
> This guide is synchronized dynamically from the Google ML Kit portal. Connect to the Internet to download the latest structured output specs.

## JSON Schema Validation
Guarantee 100% syntactically valid JSON responses from Gemini Nano using grammar-constrained decoding.

## Tool Definitions & Dispatch
Define JSON Schema properties, required fields, and enum restrictions for programmatic tool arguments.

## Offline Status
To view the full live specification, connect to Wi-Fi or cellular network. The guide will automatically synchronize in the background on app launch.
''';
      case 'speech_recognition':
        return '''
# Speech Recognition & Translation

> [!NOTE]
> This guide is synchronized dynamically from the Google ML Kit portal. Connect to the Internet to download the latest speech recognition specs.

## On-Device Speech-to-Text
Offline acoustic transcription and language identification with low latency and zero data leakage.

## Multilingual Translation
Translate transcribed audio segments directly across supported offline language packs.

## Offline Status
To view the full live specification, connect to Wi-Fi or cellular network. The guide will automatically synchronize in the background on app launch.
''';
      case 'summarization':
        return '''
# On-Device Summarization & Rewriting

> [!NOTE]
> This guide is synchronized dynamically from the Google ML Kit portal. Connect to the Internet to download the latest summarization specs.

## Document & Conversation Summarization
Distill long multi-turn chat threads and technical documents into concise bullet points or abstractive summaries.

## Tone & Style Rewriting
Adjust text formality, conciseness, and tone entirely on-device without cloud dependencies.

## Offline Status
To view the full live specification, connect to Wi-Fi or cellular network. The guide will automatically synchronize in the background on app launch.
''';
      default:
        return '''
# $title

> [!NOTE]
> This guide is fetched from the official documentation repository. Connect to the Internet to synchronize the content.

## Overview
Documentation for $title.
''';
    }
  }

  /// Registers `query_aicore_documentation` on the provided [registry].
  void registerMeshTool(M3xToolRegistry registry) {
    registry.register(
      M3xTool(
        name: 'query_aicore_documentation',
        app: 'paios',
        description: "Searches official Google ML Kit GenAI documentation for Gemini Nano architecture, capabilities, supported devices, token limits, system prompts, thinking mode, function calling, and AICore APIs.",
        parameters: {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description': 'Search topic, device model, or error code (e.g. "token limits", "-101", "Pixel 9", "system prompt", "vision downsample")',
            },
          },
          'required': ['query'],
        },
        handler: (args) async {
          final query = args['query']?.toString() ?? '';
          final result = await searchDoc(query);
          return {
            'found': result.found,
            'title': result.title,
            'sectionTitle': result.sectionTitle,
            'pageId': result.pageId,
            'pageTitle': result.pageTitle,
            'content': result.content,
          };
        },
      ),
    );
  }
}
