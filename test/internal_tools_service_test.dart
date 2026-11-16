import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geminilocal/services/internal_tools_service.dart';

typedef FakeRouteHandler = FakeHttpResponse Function(Uri uri, FakeHttpHeaders headers);

class FakeHttpResponseSpec {
  final int statusCode;
  final String body;
  const FakeHttpResponseSpec(this.statusCode, this.body);
}

typedef FakeHttpResponse = FakeHttpResponseSpec;

class FakeHttpHeaders implements HttpHeaders {
  final Map<String, List<String>> values = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = [value.toString()];
  }

  @override
  String? value(String name) => values[name.toLowerCase()]?.first;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  @override
  final int statusCode;
  final List<int> _bytes;

  _FakeHttpClientResponse(this.statusCode, String body)
      : _bytes = utf8.encode(body);

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable([_bytes]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientRequest implements HttpClientRequest {
  @override
  final Uri uri;
  final FakeRouteHandler handler;
  @override
  final FakeHttpHeaders headers = FakeHttpHeaders();

  _FakeHttpClientRequest(this.uri, this.handler);

  @override
  Future<HttpClientResponse> close() async {
    final spec = handler(uri, headers);
    return _FakeHttpClientResponse(spec.statusCode, spec.body);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClient implements HttpClient {
  final Queue<FakeRouteHandler> handlers;
  final List<({Uri uri, Map<String, List<String>> headers})> recordedRequests;

  @override
  Duration? connectionTimeout;

  _FakeHttpClient(this.handlers, this.recordedRequests);

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    if (handlers.isEmpty) {
      throw StateError('Unexpected HTTP GET to $url');
    }
    final handler = handlers.removeFirst();
    return _FakeHttpClientRequest(url, (uri, headers) {
      recordedRequests.add((
        uri: uri,
        headers: Map<String, List<String>>.from(headers.values),
      ));
      return handler(uri, headers);
    });
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('InternalToolsService metadata & module gating', () {
    test('defines all 5 canonical internal modules with expected defaults', () {
      expect(InternalToolsService.modules.length, equals(5));

      final docs = InternalToolsService.moduleById('paios.docs')!;
      expect(docs.defaultEnabled, isTrue);
      expect(docs.requiresInternet, isFalse);
      expect(docs.toolNames, equals(['query_aicore_documentation']));
      expect(docs.prefKey, equals('mesh_extension_paios.docs_enabled'));

      final device = InternalToolsService.moduleById('paios.device')!;
      expect(device.defaultEnabled, isTrue);
      expect(device.requiresInternet, isFalse);
      expect(device.toolNames, equals(['get_battery_status']));

      final wiki = InternalToolsService.moduleById('paios.wikipedia')!;
      expect(wiki.defaultEnabled, isFalse);
      expect(wiki.requiresInternet, isTrue);
      expect(wiki.toolNames, equals(['wikipedia_summary', 'wikipedia_details']));

      final search = InternalToolsService.moduleById('paios.search')!;
      expect(search.defaultEnabled, isFalse);
      expect(search.requiresInternet, isTrue);
      expect(search.toolNames, equals(['duckduckgo_search']));

      final weather = InternalToolsService.moduleById('paios.weather')!;
      expect(weather.defaultEnabled, isFalse);
      expect(weather.requiresInternet, isTrue);
      expect(weather.toolNames, equals(['weather_forecast']));
    });

    test('resolves enabled state from preference overrides and filters tools', () {
      final prefs = <String, bool>{
        'mesh_extension_paios.wikipedia_enabled': true,
        'flutter.mesh_extension_paios.docs_enabled': false,
      };

      bool isEnabled(String moduleId) =>
          InternalToolsService.isModuleEnabledFromLookup(
            moduleId,
            (key) => prefs[key],
          );

      expect(isEnabled('paios.docs'), isFalse);
      expect(isEnabled('paios.device'), isTrue);
      expect(isEnabled('paios.wikipedia'), isTrue);
      expect(isEnabled('paios.search'), isFalse);
      expect(isEnabled('paios.weather'), isFalse);

      final enabledToolNames = InternalToolsService.getEnabledToolSpecs(isEnabled)
          .map((t) => t.name)
          .toList();
      expect(
        enabledToolNames,
        equals(['get_battery_status', 'wikipedia_summary', 'wikipedia_details']),
      );
    });
  });

  group('WMO weather code formatting & Wikipedia section ranking', () {
    test('maps WMO weather codes to concise readable conditions', () {
      expect(InternalToolsService.describeWmoWeatherCode(0), equals('Clear'));
      expect(
        InternalToolsService.describeWmoWeatherCode(1),
        equals('Mainly clear'),
      );
      expect(
        InternalToolsService.describeWmoWeatherCode(2),
        equals('Partly cloudy'),
      );
      expect(InternalToolsService.describeWmoWeatherCode(3), equals('Cloudy'));
      expect(InternalToolsService.describeWmoWeatherCode(45), equals('Fog'));
      expect(InternalToolsService.describeWmoWeatherCode(53), equals('Drizzle'));
      expect(InternalToolsService.describeWmoWeatherCode(61), equals('Rain'));
      expect(InternalToolsService.describeWmoWeatherCode(73), equals('Snow'));
      expect(
        InternalToolsService.describeWmoWeatherCode(81),
        equals('Rain showers'),
      );
      expect(
        InternalToolsService.describeWmoWeatherCode(95),
        equals('Thunderstorm'),
      );
      expect(
        InternalToolsService.describeWmoWeatherCode(99),
        equals('Thunderstorm with hail'),
      );
      expect(InternalToolsService.describeWmoWeatherCode(null), equals('Unknown'));
      expect(InternalToolsService.describeWmoWeatherCode(999), equals('Unknown'));
    });

    test('ranks Wikipedia sections matching question keywords first and ignores References', () {
      const sampleArticle = '''
Kyiv is the capital and most populous city of Ukraine.

== History ==
Kyiv is one of the oldest cities in Eastern Europe and played a pivotal role in medieval trade routes.

== Climate ==
Kyiv has a humid continental climate. Warmest months are June, July, and August, with average temperatures around 20 degrees Celsius.

== Economy ==
Kyiv is a major industrial, scientific, and educational center with strong IT and service sectors.

== References ==
Some citation about climate and economy.
''';

      final ranked = InternalToolsService.rankWikipediaSections(
        sampleArticle,
        'What is the climate in summer?',
        'Kyiv',
        maxChars: 360,
      );

      expect(ranked, contains('Climate'));
      expect(ranked, contains('humid continental climate'));
      expect(ranked, isNot(contains('Some citation')));
      expect(ranked.length, lessThanOrEqualTo(360));
    });
  });

  group('Offline guard', () {
    test('returns device_offline without issuing HTTP requests', () async {
      final handlers = Queue<FakeRouteHandler>();
      final recorded = <({Uri uri, Map<String, List<String>> headers})>[];
      final service = InternalToolsService(
        onlineCheckFn: () async => false,
        httpClientFactory: () => _FakeHttpClient(handlers, recorded),
      );

      final summary = await service.wikipediaSummary('Kyiv');
      final details = await service.wikipediaDetails('Kyiv', 'climate');
      final ddg = await service.duckDuckGoSearch('Dart');
      final weather = await service.weatherForecast('Kyiv');

      for (final res in [summary, details, ddg, weather]) {
        expect(res['error'], equals('device_offline'));
        expect(
          res['message'],
          equals('Device is offline; cannot reach online lookup service right now.'),
        );
      }
      expect(recorded, isEmpty);
    });
  });

  group('Mock HTTP online tool responses', () {
    test('wikipediaSummary fetches search + summary with PAIOS User-Agent and trims extract', () async {
      final longExtract = List.filled(120, 'Sentence about Kyiv history.').join(' ');
      final handlers = Queue<FakeRouteHandler>.from([
        (uri, headers) {
          expect(uri.host, equals('en.wikipedia.org'));
          expect(uri.path, equals('/w/rest.php/v1/search/title'));
          expect(uri.queryParameters['q'], equals('Kyiv'));
          expect(
            headers.value('user-agent'),
            equals(InternalToolsService.userAgent),
          );
          return FakeHttpResponseSpec(
            200,
            jsonEncode({
              'pages': [
                {'key': 'Kyiv', 'title': 'Kyiv'},
              ],
            }),
          );
        },
        (uri, headers) {
          expect(uri.path, equals('/api/rest_v1/page/summary/Kyiv'));
          return FakeHttpResponseSpec(
            200,
            jsonEncode({
              'title': 'Kyiv',
              'description': 'Capital of Ukraine',
              'extract': longExtract,
              'content_urls': {
                'desktop': {'page': 'https://en.wikipedia.org/wiki/Kyiv'},
              },
            }),
          );
        },
      ]);
      final recorded = <({Uri uri, Map<String, List<String>> headers})>[];
      final service = InternalToolsService(
        onlineCheckFn: () async => true,
        httpClientFactory: () => _FakeHttpClient(handlers, recorded),
      );

      final res = await service.wikipediaSummary('Kyiv');
      expect(res['found'], isTrue);
      expect(res['title'], equals('Kyiv'));
      expect(res['description'], equals('Capital of Ukraine'));
      expect(res['url'], equals('https://en.wikipedia.org/wiki/Kyiv'));
      expect((res['extract'] as String).length, lessThanOrEqualTo(800));
      expect(recorded.length, equals(2));
    });

    test('wikipediaSummary handles 404 gracefully', () async {
      final handlers = Queue<FakeRouteHandler>.from([
        (uri, headers) => FakeHttpResponseSpec(
              200,
              jsonEncode({
                'pages': [
                  {'key': 'Missing_Page', 'title': 'Missing Page'},
                ],
              }),
            ),
        (uri, headers) => const FakeHttpResponseSpec(404, '{"title":"Not found."}'),
      ]);
      final service = InternalToolsService(
        onlineCheckFn: () async => true,
        httpClientFactory: () => _FakeHttpClient(handlers, []),
      );

      final res = await service.wikipediaSummary('Missing Page');
      expect(res['found'], isFalse);
      expect(res['message'], contains('not found'));
    });

    test('wikipediaDetails passes substantial ranked text to readerAgent', () async {
      final longClimateParagraph = List.filled(
        25,
        'Summer precipitation and average temperature in Kyiv are moderate and sunny.',
      ).join(' ');
      final extract = '''
Overview text.

== Climate ==
$longClimateParagraph

== Sports ==
Football is very popular in the city.
''';

      final handlers = Queue<FakeRouteHandler>.from([
        (uri, headers) => FakeHttpResponseSpec(
              200,
              jsonEncode({
                'pages': [
                  {'key': 'Kyiv', 'title': 'Kyiv'},
                ],
              }),
            ),
        (uri, headers) => FakeHttpResponseSpec(
              200,
              jsonEncode({
                'query': {
                  'pages': {
                    '16826': {
                      'pageid': 16826,
                      'title': 'Kyiv',
                      'extract': extract,
                    },
                  },
                },
              }),
            ),
      ]);

      final service = InternalToolsService(
        onlineCheckFn: () async => true,
        httpClientFactory: () => _FakeHttpClient(handlers, []),
      );

      String? agentInput;
      final res = await service.wikipediaDetails(
        'Kyiv',
        'What is the summer precipitation like?',
        readerAgent: (text, question) async {
          agentInput = text;
          return 'Kyiv summers have moderate precipitation and sunny weather.';
        },
      );

      expect(res['found'], isTrue);
      expect(res['condensed'], isTrue);
      expect(agentInput, isNotNull);
      expect(agentInput!.length, greaterThan(500));
      expect(
        res['details'],
        equals('Kyiv summers have moderate precipitation and sunny weather.'),
      );
    });

    test('duckDuckGoSearch extracts compact instant answer and handles empty results', () async {
      final handlers = Queue<FakeRouteHandler>.from([
        (uri, headers) {
          expect(uri.host, equals('api.duckduckgo.com'));
          expect(uri.queryParameters['format'], equals('json'));
          expect(
            headers.value('user-agent'),
            equals(InternalToolsService.userAgent),
          );
          return FakeHttpResponseSpec(
            200,
            jsonEncode({
              'Heading': 'Dart (programming language)',
              'AbstractText':
                  'Dart is a programming language designed for client development, such as for the web and mobile apps.',
              'AbstractURL': 'https://en.wikipedia.org/wiki/Dart_(programming_language)',
              'Answer': '',
              'Definition': '',
              'RelatedTopics': [
                {'Text': 'Flutter uses Dart for multi-platform UI.'},
                {
                  'Name': 'Ecosystem',
                  'Topics': [
                    {'Text': 'pub.dev hosts Dart packages.'},
                    {'Text': 'Dart compiles to ARM and x64 machine code.'},
                    {'Text': 'Fourth item should be capped out.'},
                  ],
                },
              ],
            }),
          );
        },
        (uri, headers) => FakeHttpResponseSpec(
              200,
              jsonEncode({
                'Heading': '',
                'AbstractText': '',
                'Answer': '',
                'Definition': '',
                'RelatedTopics': [],
              }),
            ),
      ]);

      final service = InternalToolsService(
        onlineCheckFn: () async => true,
        httpClientFactory: () => _FakeHttpClient(handlers, []),
      );

      final hit = await service.duckDuckGoSearch('Dart language');
      expect(hit['found'], isTrue);
      expect(hit['heading'], equals('Dart (programming language)'));
      expect((hit['related'] as List).length, equals(3));
      expect(jsonEncode(hit).length, lessThanOrEqualTo(900));

      final miss = await service.duckDuckGoSearch('obscure query');
      expect(miss['found'], isFalse);
      expect(
        miss['message'],
        equals('No instant answer found; try wikipedia_summary or rephrase query.'),
      );
    });

    test('weatherForecast geocodes location and formats Open-Meteo forecast', () async {
      final handlers = Queue<FakeRouteHandler>.from([
        (uri, headers) {
          expect(uri.host, equals('geocoding-api.open-meteo.com'));
          expect(uri.queryParameters['name'], equals('Kyiv'));
          return FakeHttpResponseSpec(
            200,
            jsonEncode({
              'results': [
                {
                  'name': 'Kyiv',
                  'admin1': 'Kyiv City',
                  'country': 'Ukraine',
                  'latitude': 50.4547,
                  'longitude': 30.5238,
                },
              ],
            }),
          );
        },
        (uri, headers) {
          expect(uri.host, equals('api.open-meteo.com'));
          expect(uri.queryParameters['latitude'], equals('50.4547'));
          expect(uri.queryParameters['longitude'], equals('30.5238'));
          return FakeHttpResponseSpec(
            200,
            jsonEncode({
              'current': {
                'temperature_2m': 14.5,
                'apparent_temperature': 13.0,
                'weather_code': 2,
                'wind_speed_10m': 11.2,
                'relative_humidity_2m': 64,
              },
              'daily': {
                'time': ['2026-11-15', '2026-11-16'],
                'temperature_2m_max': [16.0, 12.5],
                'temperature_2m_min': [7.0, 5.0],
                'precipitation_probability_max': [10, 45],
              },
            }),
          );
        },
      ]);

      final service = InternalToolsService(
        onlineCheckFn: () async => true,
        httpClientFactory: () => _FakeHttpClient(handlers, []),
      );

      final res = await service.weatherForecast('Kyiv');
      expect(res['found'], isTrue);
      expect((res['location'] as Map)['name'], equals('Kyiv'));
      expect((res['location'] as Map)['country'], equals('Ukraine'));
      expect((res['current'] as Map)['condition'], equals('Partly cloudy'));
      expect((res['current'] as Map)['temperature_c'], equals(14.5));
      expect((res['daily'] as List).length, equals(2));
      expect(
        ((res['daily'] as List)[1] as Map)['precipitation_probability_percent'],
        equals(45),
      );
    });
  });

  group('Synthesis payload formatting', () {
    test('formatResultForSynthesis formats wikipedia_summary cleanly without raw JSON keys', () {
      final formatted = InternalToolsService.formatResultForSynthesis(
        'wikipedia_summary',
        {
          'found': true,
          'title': 'Alphabet Inc.',
          'description': 'American multinational technology conglomerate',
          'extract': 'Alphabet Inc. is an American multinational technology conglomerate holding company.',
          'url': 'https://en.wikipedia.org/wiki/Alphabet_Inc.',
        },
      );

      expect(formatted, contains('Source: Wikipedia — Alphabet Inc.'));
      expect(formatted, contains('American multinational technology conglomerate'));
      expect(formatted, contains('Reference link: https://en.wikipedia.org/wiki/Alphabet_Inc.'));
      expect(formatted, contains('Summary: Alphabet Inc. is an American multinational'));
      expect(formatted.toLowerCase(), isNot(contains('found:')));
      expect(formatted.toLowerCase(), isNot(contains('extract:')));
      expect(formatted.toLowerCase(), isNot(contains('url:')));
    });

    test('formatResultForSynthesis strips boolean found/success noise from generic maps', () {
      final formatted = InternalToolsService.formatResultForSynthesis(
        'custom_tool',
        jsonEncode({
          'found': true,
          'success': true,
          'status': 'Active',
        }),
      );

      expect(formatted, equals('Status: Active'));
    });
  });
}
