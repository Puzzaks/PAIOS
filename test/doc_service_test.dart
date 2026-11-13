import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:geminilocal/services/doc_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:m3x_mesh/m3x_mesh.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DocService 3-Tier SWR & Multi-Page Documentation Tests', () {
    late DocService service;

    setUp(() async {
      service = DocService();
      service.customCacheDirectory = null;
      service.customHttpClient = null;
      await service.initialize(null, true);
    });

    test('Loads 23 manifest pages and defaults to Supported Devices', () {
      expect(service.isLoaded, isTrue);
      expect(service.pages.length, equals(23));

      final pageIds = service.pages.map((p) => p.id).toList();
      expect(pageIds, containsAll([
        'devices',
        'direct_model_overview',
        'get_started',
        'prompt_design',
        'structured_output',
        'speech_recognition',
        'summarization',
        'tts_api',
      ]));

      expect(service.selectedPageId, equals('devices'));
      expect(service.currentPage, isNotNull);
      expect(service.currentPage!.id, equals('devices'));
      expect(service.currentPage!.isOfflineFallback, isTrue);
      expect(service.sections.length, greaterThanOrEqualTo(4));

      final titles = service.sections.map((s) => s.title).toList();
      expect(titles.any((t) => t.contains('Qualified Device Families')), isTrue);
      expect(titles.any((t) => t.contains('System Prerequisites')), isTrue);
      expect(titles.any((t) => t.contains('Developer Options')), isTrue);
      expect(titles.any((t) => t.contains('Error Taxonomy')), isTrue);
    });

    test('Searches by device name (Pixel 9 / S24)', () async {
      final res = await service.searchDoc('Pixel 9');
      expect(res.found, isTrue);
      expect(res.pageId, equals('devices'));
      expect(res.title, contains('Qualified Device Families'));
      expect(res.content, contains('Tensor G4'));
    });

    test('Searches by error code (-101)', () async {
      final res = await service.searchDoc('-101');
      expect(res.found, isTrue);
      expect(res.pageId, equals('devices'));
      expect(res.title, contains('Error Taxonomy'));
      expect(res.content, contains('MODEL_BUSY'));
    });

    test('Searches by context overflow token limits in devices', () async {
      final res = await service.searchDoc('CONTEXT_OVERFLOW');
      expect(res.found, isTrue);
      expect(res.pageId, equals('devices'));
      expect(res.content, contains('4,096'));
    });

    test('Searches by multimodal image description', () async {
      final res = await service.searchDoc('ImageDescriber');
      expect(res.found, isTrue);
      expect(res.pageId, equals('image_description'));
      expect(res.content, contains('ImageDescriber'));
    });

    test('Switches active page smoothly and updates sections', () {
      service.selectPage('agent_overview');
      expect(service.selectedPageId, equals('agent_overview'));
      expect(service.currentPage!.id, equals('agent_overview'));
      expect(service.sections.isNotEmpty, isTrue);

      service.selectPage('structured_output');
      expect(service.selectedPageId, equals('structured_output'));
      expect(service.currentPage!.title, contains('Structured'));
    });

    test('Cross-page global search finds topics across non-active pages', () async {
      service.selectPage('devices');

      // Search for agent workflow topics located on agent_overview page
      final resAgent = await service.searchDoc('Common agentic patterns');
      expect(resAgent.found, isTrue);
      expect(resAgent.pageId, equals('agent_overview'));

      // Search for Generable target class located on structured_output page
      final resSchema = await service.searchDoc('Generable');
      expect(resSchema.found, isTrue);
      expect(resSchema.pageId, equals('structured_output'));

      // Search for speech translation located on speech_translation page
      final resSpeech = await service.searchDoc('speech translation');
      expect(resSpeech.found, isTrue);
      expect(resSpeech.pageId, equals('speech_translation'));
    });

    test('Tier 2: Loads cached content from disk if present', () async {
      final tempDir = await Directory.systemTemp.createTemp('paios_doc_cache_test_');
      try {
        final cacheFile = File('${tempDir.path}/devices.md.txt');
        await cacheFile.writeAsString('''
# Supported Devices & Architecture

## Cached Custom Devices
This content was loaded directly from the Tier 2 disk cache.
''');

        service.customCacheDirectory = tempDir;
        await service.initialize(null, true);

        final devicesPage = service.pages.firstWhere((p) => p.id == 'devices');
        expect(devicesPage.isOfflineFallback, isFalse);
        expect(devicesPage.content, contains('Tier 2 disk cache'));
        expect(devicesPage.sections.any((s) => s.title == 'Cached Custom Devices'), isTrue);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('Tier 3: SWR background synchronization updates in-memory pages and disk cache', () async {
      final tempDir = await Directory.systemTemp.createTemp('paios_doc_swr_test_');
      try {
        service.customCacheDirectory = tempDir;
        service.customHttpClient = MockClient((request) async {
          if (request.url.path.endsWith('prompt/android.md.txt')) {
            return http.Response('''
## AICore Live Beta Spec
Updated via Tier 3 SWR background synchronization!
''', 200);
          }
          return http.Response('Not Found', 404);
        });

        await service.syncRemoteDocs(force: true);

        final previewPage = service.pages.firstWhere((p) => p.id == 'direct_model_overview');
        expect(previewPage.isOfflineFallback, isFalse);
        expect(previewPage.content, contains('Updated via Tier 3 SWR'));
        expect(previewPage.sections.any((s) => s.title == 'AICore Live Beta Spec'), isTrue);

        // Verify disk cache file was created
        final cachedDiskFile = File('${tempDir.path}/direct_model_overview.md.txt');
        expect(await cachedDiskFile.exists(), isTrue);
        expect(await cachedDiskFile.readAsString(), contains('Updated via Tier 3 SWR'));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('Tier 3 SWR Resiliency: Rejects HTML error responses and handles network failures gracefully', () async {
      final tempDir = await Directory.systemTemp.createTemp('paios_doc_resilience_test_');
      try {
        service.customCacheDirectory = tempDir;
        final initialContent = service.currentPage!.content;

        service.customHttpClient = MockClient((request) async {
          if (request.url.path.contains('devices.md.txt')) {
            // Returns 200 with HTML portal error instead of markdown
            return http.Response('<!DOCTYPE html><html><body>404 Portal Error</body></html>', 200);
          }
          throw const SocketException('Connection refused / offline');
        });

        // Run SWR sync; must not throw and must reject HTML
        await service.syncRemoteDocs(force: true);

        final devicesPage = service.pages.firstWhere((p) => p.id == 'devices');
        expect(devicesPage.content, equals(initialContent));
        expect(devicesPage.content.contains('<!DOCTYPE html>'), isFalse);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('refreshDoc reloads from Google .md.txt endpoint directly and updates disk cache', () async {
      final tempDir = await Directory.systemTemp.createTemp('paios_doc_refresh_test_');
      try {
        service.customCacheDirectory = tempDir;
        service.customHttpClient = MockClient((request) async {
          if (request.url.toString().contains('manage-sessions.md.txt')) {
            return http.Response('''
## Multi-turn sessions
Live sync from Google Developers pure markdown endpoint.
''', 200);
          }
          return http.Response('Not Found', 404);
        });

        final success = await service.refreshDoc('agent_lifecycle');
        expect(success, isTrue);

        final page = service.pages.firstWhere((p) => p.id == 'agent_lifecycle');
        expect(page.isOfflineFallback, isFalse);
        expect(page.content, contains('Live sync from Google Developers pure markdown endpoint.'));
        expect(page.sections.any((s) => s.title == 'Multi-turn sessions'), isTrue);

        // Check disk cache
        final cacheFile = File('${tempDir.path}/agent_lifecycle.md.txt');
        expect(await cacheFile.exists(), isTrue);
        expect(await cacheFile.readAsString(), contains('Live sync from Google Developers pure markdown endpoint.'));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('Registers M3xTool on M3xToolRegistry and executes query', () async {
      final registry = M3xToolRegistry();
      service.registerMeshTool(registry);

      final tool = registry.get('query_aicore_documentation');
      expect(tool, isNotNull);
      expect(tool!.name, 'query_aicore_documentation');
      expect(tool.app, 'paios');

      final executionResult = await tool.handler!({'query': 'error -100'});
      expect(executionResult['found'], isTrue);
      expect(executionResult['title'], contains('Error Taxonomy'));
      expect(executionResult['sectionTitle'], contains('Error Taxonomy'));
      expect(executionResult['pageId'], equals('devices'));
      expect(executionResult['content'], contains('CONTEXT_OVERFLOW'));
    });
  });
}
