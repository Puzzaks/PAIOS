import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Specification for a single internal PAIOS tool exposed to Gemini Nano / M3x Mesh.
class InternalToolSpec {
  final String name;
  final String moduleId;
  final String app;
  final String description;
  final Map<String, dynamic> parameters;
  final bool requiresInternet;

  const InternalToolSpec({
    required this.name,
    required this.moduleId,
    this.app = 'paios',
    required this.description,
    required this.parameters,
    required this.requiresInternet,
  });
}

/// Metadata for a toggleable internal PAIOS extension module in Settings > Extensions.
class InternalExtensionModule {
  final String id;
  final String title;
  final String description;
  final bool defaultEnabled;
  final bool requiresInternet;
  final List<InternalToolSpec> tools;

  const InternalExtensionModule({
    required this.id,
    required this.title,
    required this.description,
    required this.defaultEnabled,
    required this.requiresInternet,
    required this.tools,
  });

  List<String> get toolNames => tools.map((t) => t.name).toList(growable: false);

  String get prefKey => InternalToolsService.prefKeyForModule(id);
  String get flutterPrefKey => InternalToolsService.flutterPrefKeyForModule(id);
}

typedef OnlineCheckFn = Future<bool> Function();
typedef HttpClientFactory = HttpClient Function();
typedef ReaderAgentFn = Future<String> Function(String text, String question);

/// Pure-Dart service providing PAIOS built-in extension metadata, module gating
/// helpers, connectivity checks, and lightweight online lookup tools
/// (Wikipedia, DuckDuckGo Instant Answer, Open-Meteo Weather).
class InternalToolsService {
  static const String userAgent = 'PAIOS/1.7 (https://github.com/Puzzaks/PAIOS)';
  static const Duration defaultTimeout = Duration(seconds: 6);
  static const Duration onlineCheckTimeout = Duration(seconds: 2);
  static const Duration defaultReaderAgentTimeout = Duration(seconds: 25);

  static const String moduleDocs = 'paios.docs';
  static const String moduleDevice = 'paios.device';
  static const String moduleWikipedia = 'paios.wikipedia';
  static const String moduleSearch = 'paios.search';
  static const String moduleWeather = 'paios.weather';

  static String prefKeyForModule(String moduleId) =>
      'mesh_extension_${moduleId}_enabled';

  static String flutterPrefKeyForModule(String moduleId) =>
      'flutter.mesh_extension_${moduleId}_enabled';

  /// All toggleable internal PAIOS extension modules and their tool schemas.
  static const List<InternalExtensionModule> modules = [
    InternalExtensionModule(
      id: moduleDocs,
      title: 'AICore Docs',
      description:
          'Offline & SWR search across Google ML Kit GenAI and AICore documentation.',
      defaultEnabled: true,
      requiresInternet: false,
      tools: [
        InternalToolSpec(
          name: 'query_aicore_documentation',
          moduleId: moduleDocs,
          description:
              'Searches official PAIOS, Google ML Kit GenAI, and AICore documentation for "who are you?", "tell me about yourself", PAIOS features, extensions, system assistant overlay, model variants, supported devices, token limits, system prompt guidelines, error codes (-101, -100, BUSY, BACKGROUND_USE_BLOCKED), and multimodal vision specs.',
          requiresInternet: false,
          parameters: {
            'type': 'object',
            'properties': {
              'query': {
                'type': 'string',
                'description':
                    'Search topic, PAIOS self-info question, device model, or error code (e.g. "who are you", "tell me about yourself", "PAIOS extensions", "token limits", "-101", "Pixel 9")',
              },
            },
            'required': ['query'],
          },
        ),
      ],
    ),
    InternalExtensionModule(
      id: moduleDevice,
      title: 'Device & Battery',
      description: 'On-device battery level, charging state, and power status.',
      defaultEnabled: true,
      requiresInternet: false,
      tools: [
        InternalToolSpec(
          name: 'get_battery_status',
          moduleId: moduleDevice,
          description:
              'Checks device battery level, charging state, and power status. NEVER invoke this tool for questions about images, photos, screen icons, UI widgets, or visible apps.',
          requiresInternet: false,
          parameters: {
            'type': 'object',
            'properties': {},
          },
        ),
      ],
    ),
    InternalExtensionModule(
      id: moduleWikipedia,
      title: 'Wikipedia',
      description:
          'Optional online Wikipedia article summaries and targeted section lookup.',
      defaultEnabled: false,
      requiresInternet: true,
      tools: [
        InternalToolSpec(
          name: 'wikipedia_summary',
          moduleId: moduleWikipedia,
          description:
              'Fetches a concise Wikipedia summary for a topic, person, place, or concept.',
          requiresInternet: true,
          parameters: {
            'type': 'object',
            'properties': {
              'query': {
                'type': 'string',
                'description': 'Article title or topic to look up',
              },
              'lang': {
                'type': 'string',
                'description': 'Two-letter Wikipedia language code (default "en")',
              },
            },
            'required': ['query'],
          },
        ),
        InternalToolSpec(
          name: 'wikipedia_details',
          moduleId: moduleWikipedia,
          description:
              'Searches a Wikipedia article for sections relevant to a specific question and extracts key facts.',
          requiresInternet: true,
          parameters: {
            'type': 'object',
            'properties': {
              'query': {
                'type': 'string',
                'description': 'Wikipedia article title or topic',
              },
              'question': {
                'type': 'string',
                'description': 'Specific question or detail to look for in the article',
              },
              'lang': {
                'type': 'string',
                'description': 'Two-letter Wikipedia language code (default "en")',
              },
            },
            'required': ['query', 'question'],
          },
        ),
      ],
    ),
    InternalExtensionModule(
      id: moduleSearch,
      title: 'Web Search (DuckDuckGo)',
      description:
          'Optional online instant answers and quick definitions via DuckDuckGo.',
      defaultEnabled: false,
      requiresInternet: true,
      tools: [
        InternalToolSpec(
          name: 'duckduckgo_search',
          moduleId: moduleSearch,
          description:
              'Queries DuckDuckGo Instant Answer for quick facts, definitions, and related snippets.',
          requiresInternet: true,
          parameters: {
            'type': 'object',
            'properties': {
              'query': {
                'type': 'string',
                'description': 'Search query for instant answers',
              },
            },
            'required': ['query'],
          },
        ),
      ],
    ),
    InternalExtensionModule(
      id: moduleWeather,
      title: 'Weather (Open-Meteo)',
      description:
          'Optional online current conditions and 2-day forecast via Open-Meteo.',
      defaultEnabled: false,
      requiresInternet: true,
      tools: [
        InternalToolSpec(
          name: 'weather_forecast',
          moduleId: moduleWeather,
          description:
              'Fetches current weather conditions and a 2-day forecast for a city or location.',
          requiresInternet: true,
          parameters: {
            'type': 'object',
            'properties': {
              'location': {
                'type': 'string',
                'description': 'City or place name (e.g. "Kyiv", "London")',
              },
            },
            'required': ['location'],
          },
        ),
      ],
    ),
  ];

  static InternalExtensionModule? moduleById(String id) {
    final normalized = id.trim().toLowerCase();
    for (final mod in modules) {
      if (mod.id == normalized) return mod;
    }
    return null;
  }

  static InternalExtensionModule? moduleForTool(String toolName) {
    final normalized = toolName.trim().toLowerCase();
    for (final mod in modules) {
      for (final tool in mod.tools) {
        if (tool.name == normalized) return mod;
      }
    }
    return null;
  }

  static bool isInternalModuleId(String id) => moduleById(id) != null;

  static bool isInternalToolName(String toolName) => moduleForTool(toolName) != null;

  static bool defaultEnabledForModule(String moduleId) =>
      moduleById(moduleId)?.defaultEnabled ?? false;

  /// Resolves module enabled state using a generic boolean preference reader
  /// (compatible with both Hive and Android `FlutterSharedPreferences`).
  static bool isModuleEnabledFromLookup(
    String moduleId,
    bool? Function(String key) readBool,
  ) {
    final direct = readBool(prefKeyForModule(moduleId));
    if (direct != null) return direct;
    final prefixed = readBool(flutterPrefKeyForModule(moduleId));
    if (prefixed != null) return prefixed;
    return defaultEnabledForModule(moduleId);
  }

  static List<InternalToolSpec> getEnabledToolSpecs(
    bool Function(String moduleId) isEnabled,
  ) {
    final enabled = <InternalToolSpec>[];
    for (final mod in modules) {
      if (isEnabled(mod.id)) {
        enabled.addAll(mod.tools);
      }
    }
    return enabled;
  }

  final HttpClientFactory _httpClientFactory;
  final OnlineCheckFn? _onlineCheckFn;
  final Duration timeout;
  final Duration readerAgentTimeout;
  final bool Function(String moduleId)? _isModuleEnabled;

  InternalToolsService({
    HttpClientFactory? httpClientFactory,
    OnlineCheckFn? onlineCheckFn,
    this.timeout = defaultTimeout,
    this.readerAgentTimeout = defaultReaderAgentTimeout,
    bool Function(String moduleId)? isModuleEnabled,
  })  : _httpClientFactory = httpClientFactory ?? (() => HttpClient()),
        _onlineCheckFn = onlineCheckFn,
        _isModuleEnabled = isModuleEnabled;

  bool isModuleEnabled(String moduleId) =>
      _isModuleEnabled?.call(moduleId) ?? true;

  static Map<String, dynamic> offlineErrorMap() => const {
        'error': 'device_offline',
        'message':
            'Device is offline; cannot reach online lookup service right now.',
      };

  /// Non-ICMP reachability check racing DNS lookup and TCP 1.1.1.1:53 in
  /// parallel, returning on first success or bounded by [onlineCheckTimeout].
  Future<bool> checkOnline() async {
    final onlineFn = _onlineCheckFn;
    if (onlineFn != null) {
      try {
        return await onlineFn();
      } catch (_) {
        return false;
      }
    }

    final completer = Completer<bool>();
    int remaining = 2;
    Socket? tcpSocket;

    void finishSuccess() {
      if (!completer.isCompleted) {
        completer.complete(true);
      }
    }

    void finishFailure() {
      remaining--;
      if (remaining <= 0 && !completer.isCompleted) {
        completer.complete(false);
      }
    }

    InternetAddress.lookup('dns.google').timeout(onlineCheckTimeout).then((addrs) {
      if (addrs.isNotEmpty) {
        finishSuccess();
      } else {
        finishFailure();
      }
    }).catchError((_) => finishFailure());

    Socket.connect('1.1.1.1', 53, timeout: onlineCheckTimeout).then((sock) {
      tcpSocket = sock;
      try {
        sock.destroy();
      } catch (_) {}
      finishSuccess();
    }).catchError((_) => finishFailure());

    try {
      return await completer.future.timeout(
        onlineCheckTimeout,
        onTimeout: () => false,
      );
    } finally {
      try {
        tcpSocket?.destroy();
      } catch (_) {}
    }
  }

  Future<({int statusCode, String body})> _get(Uri uri) async {
    final client = _httpClientFactory();
    client.connectionTimeout = timeout;
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(timeout);
      final body = await utf8.decoder.bind(response).join().timeout(timeout);
      return (statusCode: response.statusCode, body: body);
    } finally {
      client.close(force: true);
    }
  }

  static String _sanitizeLang(String lang) {
    final cleaned = lang.trim().toLowerCase();
    if (RegExp(r'^[a-z]{2,3}(-[a-z0-9]{2,8})?$').hasMatch(cleaned)) {
      return cleaned;
    }
    return 'en';
  }

  static String _truncate(String text, int maxChars) {
    final normalized = text.trim();
    if (normalized.length <= maxChars) return normalized;
    if (maxChars <= 3) return normalized.substring(0, maxChars);
    return '${normalized.substring(0, maxChars - 3).trimRight()}...';
  }

  Future<String?> _searchBestWikipediaTitle(
    String query,
    String safeLang,
  ) async {
    final searchUri = Uri.https(
      '$safeLang.wikipedia.org',
      '/w/rest.php/v1/search/title',
      {'q': query, 'limit': '3'},
    );
    final res = await _get(searchUri);
    if (res.statusCode != 200) return null;
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) return null;
    final pages = decoded['pages'];
    if (pages is! List || pages.isEmpty) return null;

    final queryLower = query.toLowerCase();
    String? fallbackTitle;
    for (final item in pages) {
      if (item is! Map) continue;
      final title = item['title']?.toString().trim() ?? '';
      final key = item['key']?.toString().trim() ?? '';
      final candidate = key.isNotEmpty ? key : title;
      if (candidate.isEmpty) continue;
      fallbackTitle ??= candidate;
      if (title.toLowerCase() == queryLower || key.toLowerCase() == queryLower) {
        return candidate;
      }
    }
    return fallbackTitle;
  }

  /// Fetches a concise summary from Wikipedia REST API.
  Future<Map<String, dynamic>> wikipediaSummary(
    String query, {
    String lang = 'en',
  }) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      return {
        'found': false,
        'error': 'invalid_arguments',
        'message': 'Query must not be empty.',
      };
    }
    if (!await checkOnline()) {
      return offlineErrorMap();
    }

    final safeLang = _sanitizeLang(lang);
    try {
      final bestKey = await _searchBestWikipediaTitle(trimmedQuery, safeLang);
      if (bestKey == null) {
        return {
          'found': false,
          'query': trimmedQuery,
          'message': 'No Wikipedia article found for "$trimmedQuery".',
        };
      }

      final summaryUri = Uri(
        scheme: 'https',
        host: '$safeLang.wikipedia.org',
        pathSegments: ['api', 'rest_v1', 'page', 'summary', bestKey],
      );
      final summaryRes = await _get(summaryUri);
      if (summaryRes.statusCode == 404) {
        return {
          'found': false,
          'query': trimmedQuery,
          'message': 'Wikipedia summary not found for "$bestKey".',
        };
      }
      if (summaryRes.statusCode != 200) {
        return {
          'found': false,
          'error': 'http_${summaryRes.statusCode}',
          'message':
              'Wikipedia summary request failed with status ${summaryRes.statusCode}.',
        };
      }

      final decoded = jsonDecode(summaryRes.body);
      if (decoded is! Map<String, dynamic>) {
        return {
          'found': false,
          'error': 'invalid_response',
          'message': 'Unexpected Wikipedia response format.',
        };
      }

      final title = decoded['title']?.toString().trim() ?? bestKey;
      final description = decoded['description']?.toString().trim() ?? '';
      final extract = decoded['extract']?.toString().trim() ?? '';
      if (extract.isEmpty) {
        return {
          'found': false,
          'title': title,
          'message': 'No summary text available for "$title".',
        };
      }

      final contentUrls = decoded['content_urls'];
      String url = 'https://$safeLang.wikipedia.org/wiki/${Uri.encodeComponent(bestKey)}';
      if (contentUrls is Map) {
        final desktop = contentUrls['desktop'];
        final mobile = contentUrls['mobile'];
        if (desktop is Map && desktop['page'] != null) {
          url = desktop['page'].toString();
        } else if (mobile is Map && mobile['page'] != null) {
          url = mobile['page'].toString();
        }
      }

      return {
        'found': true,
        'title': title,
        if (description.isNotEmpty) 'description': description,
        'extract': _truncate(extract, 800),
        'url': url,
      };
    } on TimeoutException {
      return {
        'found': false,
        'error': 'timeout',
        'message': 'Wikipedia request timed out.',
      };
    } catch (e) {
      return {
        'found': false,
        'error': 'request_failed',
        'message': 'Wikipedia lookup failed: $e',
      };
    }
  }

  /// Splits MediaWiki plaintext extract into sections/paragraphs and ranks chunks
  /// matching keywords from [question] and [query], capping total length at [maxChars].
  static String rankWikipediaSections(
    String fullText,
    String question,
    String query, {
    int maxChars = 2200,
  }) {
    final normalized = fullText.trim();
    if (normalized.isEmpty) return '';

    final rawKeywords = '$question $query'
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9\p{L}]+', unicode: true))
        .where((w) => w.length > 2 && !_stopWords.contains(w))
        .toSet()
        .toList();
    final questionPhrase = question.trim().toLowerCase();

    final chunks = <_ScoredChunk>[];
    final headingRegex = RegExp(r'^={2,}\s*(.+?)\s*={2,}$', multiLine: true);
    final matches = headingRegex.allMatches(normalized).toList();

    final rawSections = <({String heading, String body})>[];
    if (matches.isEmpty) {
      rawSections.add((heading: '', body: normalized));
    } else {
      if (matches.first.start > 0) {
        final lead = normalized.substring(0, matches.first.start).trim();
        if (lead.isNotEmpty) {
          rawSections.add((heading: 'Overview', body: lead));
        }
      }
      for (var i = 0; i < matches.length; i++) {
        final m = matches[i];
        final heading = m.group(1)?.trim() ?? '';
        final bodyStart = m.end;
        final bodyEnd =
            (i + 1 < matches.length) ? matches[i + 1].start : normalized.length;
        final body = normalized.substring(bodyStart, bodyEnd).trim();
        if (body.isNotEmpty && !_ignoredSectionHeadings.contains(heading.toLowerCase())) {
          rawSections.add((heading: heading, body: body));
        }
      }
    }

    var order = 0;
    for (final sec in rawSections) {
      final paragraphs = sec.body.split(RegExp(r'\n\s*\n+'));
      for (final para in paragraphs) {
        final trimmed = para.trim();
        if (trimmed.isEmpty) continue;
        final headingLower = sec.heading.toLowerCase();
        final textLower = trimmed.toLowerCase();
        var score = sec.heading == 'Overview' ? 1 : 0;
        if (questionPhrase.length > 4 && textLower.contains(questionPhrase)) {
          score += 8;
        }
        for (final kw in rawKeywords) {
          if (headingLower.contains(kw)) score += 5;
          if (textLower.contains(kw)) score += 2;
        }
        final formatted =
            sec.heading.isNotEmpty ? '## ${sec.heading}\n$trimmed' : trimmed;
        chunks.add(_ScoredChunk(order: order++, score: score, text: formatted));
      }
    }

    if (chunks.isEmpty) return _truncate(normalized, maxChars);

    chunks.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.order.compareTo(b.order);
    });

    final selected = <_ScoredChunk>[];
    var totalLen = 0;
    for (final chunk in chunks) {
      if (selected.isNotEmpty && chunk.score == 0) {
        continue;
      }
      final sepLen = selected.isEmpty ? 0 : 2;
      if (totalLen + sepLen + chunk.text.length <= maxChars) {
        selected.add(chunk);
        totalLen += sepLen + chunk.text.length;
      } else if (selected.isEmpty) {
        selected.add(
          _ScoredChunk(
            order: chunk.order,
            score: chunk.score,
            text: _truncate(chunk.text, maxChars),
          ),
        );
        break;
      }
    }

    if (selected.isEmpty) {
      return _truncate(normalized, maxChars);
    }

    selected.sort((a, b) => a.order.compareTo(b.order));
    return selected.map((c) => c.text).join('\n\n');
  }

  /// Searches a Wikipedia article for sections matching [question], optionally
  /// passing substantial extracts (>500 chars) through [readerAgent].
  Future<Map<String, dynamic>> wikipediaDetails(
    String query,
    String question, {
    String lang = 'en',
    ReaderAgentFn? readerAgent,
  }) async {
    final trimmedQuery = query.trim();
    final trimmedQuestion = question.trim();
    if (trimmedQuery.isEmpty || trimmedQuestion.isEmpty) {
      return {
        'found': false,
        'error': 'invalid_arguments',
        'message': 'Both query and question must not be empty.',
      };
    }
    if (!await checkOnline()) {
      return offlineErrorMap();
    }

    final safeLang = _sanitizeLang(lang);
    try {
      final bestKey = await _searchBestWikipediaTitle(trimmedQuery, safeLang);
      if (bestKey == null) {
        return {
          'found': false,
          'query': trimmedQuery,
          'message': 'No Wikipedia article found for "$trimmedQuery".',
        };
      }

      final extractUri = Uri.https(
        '$safeLang.wikipedia.org',
        '/w/api.php',
        {
          'action': 'query',
          'prop': 'extracts',
          'explaintext': '1',
          'titles': bestKey,
          'format': 'json',
          'redirects': '1',
        },
      );
      final res = await _get(extractUri);
      if (res.statusCode != 200) {
        return {
          'found': false,
          'error': 'http_${res.statusCode}',
          'message':
              'Wikipedia details request failed with status ${res.statusCode}.',
        };
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) {
        return {
          'found': false,
          'error': 'invalid_response',
          'message': 'Unexpected Wikipedia API response.',
        };
      }

      final queryNode = decoded['query'];
      final pagesNode = queryNode is Map ? queryNode['pages'] : null;
      if (pagesNode is! Map || pagesNode.isEmpty) {
        return {
          'found': false,
          'query': trimmedQuery,
          'message': 'No detailed Wikipedia content found for "$trimmedQuery".',
        };
      }

      Map? pageMap;
      for (final entry in pagesNode.entries) {
        if (entry.key.toString() == '-1') continue;
        if (entry.value is Map && (entry.value as Map)['missing'] == null) {
          pageMap = entry.value as Map;
          break;
        }
      }

      final extract = pageMap?['extract']?.toString().trim() ?? '';
      final resolvedTitle = pageMap?['title']?.toString().trim() ?? bestKey;
      if (extract.isEmpty) {
        return {
          'found': false,
          'title': resolvedTitle,
          'message': 'No plaintext extract available for "$resolvedTitle".',
        };
      }

      final rankedText = rankWikipediaSections(
        extract,
        trimmedQuestion,
        trimmedQuery,
        maxChars: 2200,
      );

      final pageUrl =
          'https://$safeLang.wikipedia.org/wiki/${Uri.encodeComponent(resolvedTitle.replaceAll(' ', '_'))}';

      if (readerAgent != null && rankedText.length > 500) {
        try {
          final condensed = (await readerAgent(rankedText, trimmedQuestion)
                  .timeout(readerAgentTimeout))
              .trim();
          if (condensed.isNotEmpty) {
            return {
              'found': true,
              'title': resolvedTitle,
              'question': trimmedQuestion,
              'condensed': true,
              'details': _truncate(condensed, 1200),
              'url': pageUrl,
            };
          }
        } catch (_) {
          // Fall back cleanly to the ranked excerpt if the reader agent times out or fails.
        }
      }

      return {
        'found': true,
        'title': resolvedTitle,
        'question': trimmedQuestion,
        'condensed': false,
        'details': _truncate(rankedText, 1200),
        'url': pageUrl,
      };
    } on TimeoutException {
      return {
        'found': false,
        'error': 'timeout',
        'message': 'Wikipedia details request timed out.',
      };
    } catch (e) {
      return {
        'found': false,
        'error': 'request_failed',
        'message': 'Wikipedia details lookup failed: $e',
      };
    }
  }

  /// Queries DuckDuckGo Instant Answer API and returns compact JSON (~900 chars max).
  Future<Map<String, dynamic>> duckDuckGoSearch(
    String query, {
    bool? wikipediaEnabled,
  }) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      return {
        'found': false,
        'error': 'invalid_arguments',
        'message': 'Query must not be empty.',
      };
    }
    if (!await checkOnline()) {
      return offlineErrorMap();
    }

    try {
      final uri = Uri.https(
        'api.duckduckgo.com',
        '/',
        {
          'q': trimmedQuery,
          'format': 'json',
          'no_html': '1',
          'skip_disambig': '1',
        },
      );
      final res = await _get(uri);
      if (res.statusCode != 200) {
        return {
          'found': false,
          'error': 'http_${res.statusCode}',
          'message': 'DuckDuckGo search failed with status ${res.statusCode}.',
        };
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) {
        return {
          'found': false,
          'error': 'invalid_response',
          'message': 'Unexpected DuckDuckGo response format.',
        };
      }

      final heading = decoded['Heading']?.toString().trim() ?? '';
      final abstractText = decoded['AbstractText']?.toString().trim() ?? '';
      final answer = decoded['Answer']?.toString().trim() ?? '';
      final definition = decoded['Definition']?.toString().trim() ?? '';
      final abstractUrl = decoded['AbstractURL']?.toString().trim() ?? '';

      final related = <String>[];
      void collectRelated(dynamic list) {
        if (list is! List || related.length >= 3) return;
        for (final item in list) {
          if (related.length >= 3) break;
          if (item is! Map) continue;
          final text = item['Text']?.toString().trim() ?? '';
          if (text.isNotEmpty) {
            related.add(_truncate(text, 180));
            continue;
          }
          final nested = item['Topics'];
          if (nested is List) {
            collectRelated(nested);
          }
        }
      }

      collectRelated(decoded['RelatedTopics']);

      if (abstractText.isEmpty &&
          answer.isEmpty &&
          definition.isEmpty &&
          related.isEmpty) {
        final canSuggestWiki = wikipediaEnabled ?? isModuleEnabled(moduleWikipedia);
        return {
          'found': false,
          'query': trimmedQuery,
          'message': canSuggestWiki
              ? 'No instant answer found; try wikipedia_summary or rephrase query.'
              : 'No instant answer found; try rephrasing your query.',
        };
      }

      final result = <String, dynamic>{
        'found': true,
        if (heading.isNotEmpty) 'heading': _truncate(heading, 100),
        if (answer.isNotEmpty) 'answer': _truncate(answer, 220),
        if (abstractText.isNotEmpty) 'abstract': _truncate(abstractText, 420),
        if (definition.isNotEmpty) 'definition': _truncate(definition, 220),
        if (abstractUrl.isNotEmpty) 'url': _truncate(abstractUrl, 160),
        if (related.isNotEmpty) 'related': related,
      };

      // Ensure total serialized payload stays under ~900 characters.
      while (jsonEncode(result).length > 900) {
        if (result.containsKey('related')) {
          final rel = result['related'] as List<String>;
          if (rel.length > 1) {
            rel.removeLast();
          } else {
            result.remove('related');
          }
          continue;
        }
        if (result.containsKey('abstract')) {
          final current = result['abstract'] as String;
          if (current.length > 120) {
            result['abstract'] = _truncate(current, current.length - 80);
            continue;
          }
        }
        if (result.containsKey('url')) {
          result.remove('url');
          continue;
        }
        break;
      }

      return result;
    } on TimeoutException {
      return {
        'found': false,
        'error': 'timeout',
        'message': 'DuckDuckGo search timed out.',
      };
    } catch (e) {
      return {
        'found': false,
        'error': 'request_failed',
        'message': 'DuckDuckGo search failed: $e',
      };
    }
  }

  /// Maps a WMO weather interpretation code to a concise readable condition.
  static String describeWmoWeatherCode(int? code) {
    if (code == null) return 'Unknown';
    switch (code) {
      case 0:
        return 'Clear';
      case 1:
        return 'Mainly clear';
      case 2:
        return 'Partly cloudy';
      case 3:
        return 'Cloudy';
      case 45:
      case 48:
        return 'Fog';
      case 51:
      case 53:
      case 55:
        return 'Drizzle';
      case 56:
      case 57:
        return 'Freezing drizzle';
      case 61:
      case 63:
      case 65:
        return 'Rain';
      case 66:
      case 67:
        return 'Freezing rain';
      case 71:
      case 73:
      case 75:
      case 77:
        return 'Snow';
      case 80:
      case 81:
      case 82:
        return 'Rain showers';
      case 85:
      case 86:
        return 'Snow showers';
      case 95:
        return 'Thunderstorm';
      case 96:
      case 99:
        return 'Thunderstorm with hail';
      default:
        return 'Unknown';
    }
  }

  /// Geocodes [location] and fetches current conditions + 2-day forecast via Open-Meteo.
  Future<Map<String, dynamic>> weatherForecast(String location) async {
    final trimmedLocation = location.trim();
    if (trimmedLocation.isEmpty) {
      return {
        'found': false,
        'error': 'invalid_arguments',
        'message': 'Location must not be empty.',
      };
    }
    if (!await checkOnline()) {
      return offlineErrorMap();
    }

    try {
      final geoUri = Uri.https(
        'geocoding-api.open-meteo.com',
        '/v1/search',
        {
          'name': trimmedLocation,
          'count': '1',
          'language': 'en',
          'format': 'json',
        },
      );
      final geoRes = await _get(geoUri);
      if (geoRes.statusCode != 200) {
        return {
          'found': false,
          'error': 'http_${geoRes.statusCode}',
          'message':
              'Open-Meteo geocoding failed with status ${geoRes.statusCode}.',
        };
      }

      final geoJson = jsonDecode(geoRes.body);
      final results = geoJson is Map ? geoJson['results'] : null;
      if (results is! List || results.isEmpty || results.first is! Map) {
        return {
          'found': false,
          'location': trimmedLocation,
          'message': 'Location "$trimmedLocation" not found.',
        };
      }

      final place = results.first as Map;
      final lat = place['latitude'];
      final lon = place['longitude'];
      if (lat == null || lon == null) {
        return {
          'found': false,
          'location': trimmedLocation,
          'message': 'Missing coordinates for "$trimmedLocation".',
        };
      }

      final forecastUri = Uri.https(
        'api.open-meteo.com',
        '/v1/forecast',
        {
          'latitude': '$lat',
          'longitude': '$lon',
          'current':
              'temperature_2m,apparent_temperature,weather_code,wind_speed_10m,relative_humidity_2m',
          'daily':
              'temperature_2m_max,temperature_2m_min,precipitation_probability_max',
          'forecast_days': '2',
          'timezone': 'auto',
        },
      );
      final forecastRes = await _get(forecastUri);
      if (forecastRes.statusCode != 200) {
        return {
          'found': false,
          'error': 'http_${forecastRes.statusCode}',
          'message':
              'Open-Meteo forecast failed with status ${forecastRes.statusCode}.',
        };
      }

      final forecastJson = jsonDecode(forecastRes.body);
      if (forecastJson is! Map<String, dynamic>) {
        return {
          'found': false,
          'error': 'invalid_response',
          'message': 'Unexpected Open-Meteo response format.',
        };
      }

      final current = forecastJson['current'] is Map
          ? forecastJson['current'] as Map
          : const {};
      final weatherCode = (current['weather_code'] as num?)?.toInt();

      final daily = forecastJson['daily'] is Map
          ? forecastJson['daily'] as Map
          : const {};
      final dates = daily['time'] is List ? daily['time'] as List : const [];
      final maxTemps = daily['temperature_2m_max'] is List
          ? daily['temperature_2m_max'] as List
          : const [];
      final minTemps = daily['temperature_2m_min'] is List
          ? daily['temperature_2m_min'] as List
          : const [];
      final precipProbs = daily['precipitation_probability_max'] is List
          ? daily['precipitation_probability_max'] as List
          : const [];

      final dailyForecast = <Map<String, dynamic>>[];
      for (var i = 0; i < dates.length && i < 2; i++) {
        dailyForecast.add({
          'date': dates[i]?.toString(),
          if (i < maxTemps.length) 'temp_max_c': maxTemps[i],
          if (i < minTemps.length) 'temp_min_c': minTemps[i],
          if (i < precipProbs.length)
            'precipitation_probability_percent': precipProbs[i],
        });
      }

      final placeName = place['name']?.toString() ?? trimmedLocation;
      final admin1 = place['admin1']?.toString();
      final country = place['country']?.toString();

      return {
        'found': true,
        'location': {
          'name': placeName,
          if (admin1 != null && admin1.isNotEmpty) 'region': admin1,
          if (country != null && country.isNotEmpty) 'country': country,
        },
        'current': {
          'temperature_c': current['temperature_2m'],
          'apparent_temperature_c': current['apparent_temperature'],
          'condition': describeWmoWeatherCode(weatherCode),
          if (weatherCode != null) 'weather_code': weatherCode,
          'wind_speed_kmh': current['wind_speed_10m'],
          'humidity_percent': current['relative_humidity_2m'],
        },
        if (dailyForecast.isNotEmpty) 'daily': dailyForecast,
      };
    } on TimeoutException {
      return {
        'found': false,
        'error': 'timeout',
        'message': 'Open-Meteo weather request timed out.',
      };
    } catch (e) {
      return {
        'found': false,
        'error': 'request_failed',
        'message': 'Weather lookup failed: $e',
      };
    }
  }

  /// Normalizes common small-model argument aliases (e.g. `q`/`topic`/`title`/`subject`
  /// -> `query`) and fills missing `wikipedia_details` `question` from [fallbackQuestion].
  static Map<String, dynamic> normalizeToolArgs(
    String toolName,
    Map<String, dynamic> rawArgs, {
    String? fallbackQuestion,
  }) {
    final args = Map<String, dynamic>.from(rawArgs);
    String firstNonEmpty(List<String> keys) {
      for (final k in keys) {
        final v = args[k]?.toString().trim() ?? '';
        if (v.isNotEmpty) return v;
      }
      return '';
    }

    switch (toolName.trim()) {
      case 'query_aicore_documentation':
      case 'about_paios':
      case 'paios_info':
      case 'get_paios_info':
        if ((args['query']?.toString().trim() ?? '').isEmpty) {
          final alias = firstNonEmpty(
            const ['topic', 'q', 'question', 'search', 'subject', 'title', 'term', 'name'],
          );
          if (alias.isNotEmpty) {
            args['query'] = alias;
          } else if (fallbackQuestion != null &&
              fallbackQuestion.trim().isNotEmpty) {
            args['query'] = fallbackQuestion.trim();
          } else {
            args['query'] = 'PAIOS overview features';
          }
        }
        break;
      case 'wikipedia_summary':
      case 'wikipedia_details':
      case 'duckduckgo_search':
        if ((args['query']?.toString().trim() ?? '').isEmpty) {
          final alias = firstNonEmpty(
            const ['q', 'topic', 'title', 'subject', 'search', 'term', 'name'],
          );
          if (alias.isNotEmpty) {
            args['query'] = alias;
          }
        }
        if (toolName.trim() == 'wikipedia_details' &&
            (args['question']?.toString().trim() ?? '').isEmpty) {
          final qAlias = firstNonEmpty(const ['ask', 'detail', 'prompt']);
          if (qAlias.isNotEmpty) {
            args['question'] = qAlias;
          } else if (fallbackQuestion != null &&
              fallbackQuestion.trim().isNotEmpty) {
            args['question'] = fallbackQuestion.trim();
          }
        }
        break;
      case 'weather_forecast':
        if ((args['location']?.toString().trim() ?? '').isEmpty) {
          final locAlias = firstNonEmpty(const ['city', 'place', 'query', 'q']);
          if (locAlias.isNotEmpty) {
            args['location'] = locAlias;
          }
        }
        break;
    }
    return args;
  }

  /// Dispatches an online internal tool by name.
  Future<Map<String, dynamic>> executeOnlineTool(
    String toolName,
    Map<String, dynamic> args, {
    ReaderAgentFn? readerAgent,
    String? fallbackQuestion,
  }) {
    final normalizedName = toolName.trim();
    final normArgs = normalizeToolArgs(
      normalizedName,
      args,
      fallbackQuestion: fallbackQuestion,
    );
    switch (normalizedName) {
      case 'wikipedia_summary':
        return wikipediaSummary(
          normArgs['query']?.toString() ?? '',
          lang: normArgs['lang']?.toString() ?? 'en',
        );
      case 'wikipedia_details':
        final query = normArgs['query']?.toString().trim() ?? '';
        final question = normArgs['question']?.toString().trim() ?? '';
        final lang = normArgs['lang']?.toString() ?? 'en';
        if (query.isNotEmpty && question.isEmpty) {
          return wikipediaSummary(query, lang: lang);
        }
        return wikipediaDetails(
          query,
          question,
          lang: lang,
          readerAgent: readerAgent,
        );
      case 'duckduckgo_search':
        return duckDuckGoSearch(normArgs['query']?.toString() ?? '');
      case 'weather_forecast':
        return weatherForecast(normArgs['location']?.toString() ?? '');
      default:
        return Future.value({
          'found': false,
          'error': 'unsupported_tool',
          'message': 'Unknown internal online tool: $toolName',
        });
    }
  }

  /// Converts a raw tool result (Map or JSON string) into clean, human-readable
  /// notes for synthesis so Gemini Nano does not echo raw JSON keys like
  /// `found`, `title`, `description`, `extract`, or `url`.
  static String formatResultForSynthesis(String toolName, dynamic rawResult) {
    dynamic decoded = rawResult;
    if (rawResult is String) {
      final trimmed = rawResult.trim();
      if (trimmed.isEmpty) return '';
      try {
        decoded = jsonDecode(trimmed);
      } catch (_) {
        return trimmed;
      }
    }
    if (decoded is! Map) {
      return decoded?.toString() ?? '';
    }

    final normalizedTool = toolName.trim().toLowerCase();
    if (decoded['found'] == false) {
      final msg = decoded['message']?.toString().trim();
      if (msg != null && msg.isNotEmpty) return msg;
    }

    if (normalizedTool == 'query_aicore_documentation' ||
        normalizedTool == 'about_paios' ||
        normalizedTool == 'paios_info' ||
        normalizedTool == 'get_paios_info') {
      if (decoded['found'] == false) {
        final content = decoded['content']?.toString().trim() ?? '';
        if (content.isNotEmpty) return content;
      }
      final title = (decoded['sectionTitle']?.toString().trim() ?? '').isNotEmpty
          ? decoded['sectionTitle']!.toString().trim()
          : (decoded['title']?.toString().trim() ?? '');
      final pageTitle = decoded['pageTitle']?.toString().trim() ?? '';
      final content = decoded['content']?.toString().trim() ?? '';
      final lines = <String>[];
      if (title.isNotEmpty) {
        final header = pageTitle.isNotEmpty && pageTitle != title
            ? 'Documentation section: $title ($pageTitle)'
            : 'Documentation section: $title';
        lines.add(header);
      }
      if (content.isNotEmpty) {
        lines.add(content);
      }
      if (lines.isNotEmpty) {
        return lines.join('\n\n');
      }
    }

    if (normalizedTool == 'wikipedia_summary' ||
        normalizedTool == 'wikipedia_details') {
      final title = decoded['title']?.toString().trim() ?? '';
      final description = decoded['description']?.toString().trim() ?? '';
      final extract = decoded['extract']?.toString().trim() ?? '';
      final details = decoded['details']?.toString().trim() ?? '';
      final url = decoded['url']?.toString().trim() ?? '';
      final lines = <String>[];
      if (title.isNotEmpty) {
        final header = description.isNotEmpty
            ? 'Source: Wikipedia — $title ($description)'
            : 'Source: Wikipedia — $title';
        lines.add(header);
      } else {
        lines.add('Source: Wikipedia');
      }
      if (url.isNotEmpty) {
        lines.add('Reference link: $url');
      }
      if (extract.isNotEmpty) {
        lines.add('Summary: $extract');
      }
      if (details.isNotEmpty) {
        lines.add('Details: $details');
      }
      if (lines.isNotEmpty) {
        return lines.join('\n');
      }
    }

    if (normalizedTool == 'duckduckgo_search') {
      final heading = decoded['heading']?.toString().trim() ?? '';
      final answer = decoded['answer']?.toString().trim() ?? '';
      final abstractText = decoded['abstract']?.toString().trim() ?? '';
      final definition = decoded['definition']?.toString().trim() ?? '';
      final url = decoded['url']?.toString().trim() ?? '';
      final related = decoded['related'];
      final lines = <String>[
        heading.isNotEmpty ? 'Source: DuckDuckGo — $heading' : 'Source: DuckDuckGo',
      ];
      if (url.isNotEmpty) lines.add('Reference link: $url');
      if (answer.isNotEmpty) lines.add('Answer: $answer');
      if (abstractText.isNotEmpty) lines.add('Summary: $abstractText');
      if (definition.isNotEmpty) lines.add('Definition: $definition');
      if (related is List && related.isNotEmpty) {
        for (final item in related) {
          final text = item?.toString().trim() ?? '';
          if (text.isNotEmpty) lines.add('• $text');
        }
      }
      if (lines.length > 1) return lines.join('\n');
    }

    if (normalizedTool == 'weather_forecast') {
      final loc = decoded['location'];
      final cur = decoded['current'];
      final daily = decoded['daily'];
      final lines = <String>[];
      if (loc is Map) {
        final locParts = [
          loc['name']?.toString().trim(),
          loc['region']?.toString().trim(),
          loc['country']?.toString().trim(),
        ].whereType<String>().where((s) => s.isNotEmpty).toList();
        if (locParts.isNotEmpty) {
          lines.add('Location: ${locParts.join(', ')}');
        }
      }
      if (cur is Map) {
        final cond = cur['condition']?.toString().trim() ?? '';
        final temp = cur['temperature_c'];
        final feels = cur['apparent_temperature_c'];
        final wind = cur['wind_speed_kmh'];
        final hum = cur['humidity_percent'];
        final parts = <String>[
          if (cond.isNotEmpty) cond,
          if (temp != null) '$temp°C',
          if (feels != null) 'feels like $feels°C',
          if (hum != null) 'humidity $hum%',
          if (wind != null) 'wind $wind km/h',
        ];
        if (parts.isNotEmpty) {
          lines.add('Current conditions: ${parts.join(', ')}');
        }
      }
      if (daily is List && daily.isNotEmpty) {
        for (final day in daily) {
          if (day is Map) {
            final date = day['date']?.toString().trim() ?? '';
            final maxT = day['temp_max_c'];
            final minT = day['temp_min_c'];
            final precip = day['precipitation_probability_percent'];
            final dayParts = <String>[
              if (minT != null && maxT != null) '$minT°C to $maxT°C',
              if (precip != null) 'precipitation chance $precip%',
            ];
            if (date.isNotEmpty && dayParts.isNotEmpty) {
              lines.add('Forecast ($date): ${dayParts.join(', ')}');
            }
          }
        }
      }
      if (lines.isNotEmpty) return lines.join('\n');
    }

    // Generic tool map formatter: omit boolean status noise like `found: true`
    const ignoredStatusKeys = {'found', 'success', 'ok'};
    final lines = <String>[];
    decoded.forEach((rawKey, value) {
      final keyStr = rawKey.toString();
      if (ignoredStatusKeys.contains(keyStr.toLowerCase()) && value == true) {
        return;
      }
      final label = _humanizeFieldName(keyStr);
      if (value is Map) {
        final subParts = value.entries
            .where((e) => e.value != null && e.value.toString().isNotEmpty)
            .map((e) => '${_humanizeFieldName(e.key.toString())}: ${e.value}')
            .join(', ');
        if (subParts.isNotEmpty) lines.add('$label: $subParts');
      } else if (value is List) {
        if (value.isEmpty) {
          lines.add('$label: none');
        } else if (value.first is Map) {
          lines.add('$label (${value.length}):');
          for (final item in value.take(5)) {
            if (item is Map) {
              final summary = item.entries
                  .take(4)
                  .map((e) => '${_humanizeFieldName(e.key.toString())}: ${e.value}')
                  .join(', ');
              lines.add('• $summary');
            }
          }
          if (value.length > 5) {
            lines.add('• ...and ${value.length - 5} more');
          }
        } else {
          lines.add('$label: ${value.join(', ')}');
        }
      } else if (value != null && value.toString().isNotEmpty) {
        lines.add('$label: $value');
      }
    });
    if (lines.isEmpty) {
      return 'Completed ${toolName.isNotEmpty ? toolName : 'tool'} with no additional details.';
    }
    return lines.join('\n');
  }

  static String _humanizeFieldName(String raw) {
    final cleaned = raw.replaceAll('_', ' ').trim();
    if (cleaned.isEmpty) return raw;
    return cleaned[0].toUpperCase() + cleaned.substring(1);
  }

  static const Set<String> _stopWords = {
    'the',
    'and',
    'for',
    'are',
    'but',
    'not',
    'you',
    'all',
    'can',
    'had',
    'her',
    'was',
    'one',
    'our',
    'out',
    'has',
    'his',
    'how',
    'its',
    'may',
    'new',
    'now',
    'old',
    'see',
    'two',
    'way',
    'who',
    'did',
    'get',
    'let',
    'say',
    'she',
    'too',
    'use',
    'what',
    'when',
    'where',
    'which',
    'while',
    'with',
    'from',
    'that',
    'this',
    'they',
    'have',
    'were',
    'been',
    'will',
    'would',
    'could',
    'should',
    'about',
    'into',
    'there',
    'their',
    'them',
    'then',
    'than',
    'does',
  };

  static const Set<String> _ignoredSectionHeadings = {
    'references',
    'external links',
    'see also',
    'further reading',
    'notes',
    'bibliography',
  };
}

class _ScoredChunk {
  final int order;
  final int score;
  final String text;

  const _ScoredChunk({
    required this.order,
    required this.score,
    required this.text,
  });
}
