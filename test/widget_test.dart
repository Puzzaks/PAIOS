import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geminilocal/storage/resource_repository.dart';

Map<String, dynamic> _readJsonObject(String path) {
  final raw = File(path).readAsStringSync();
  return jsonDecode(raw) as Map<String, dynamic>;
}

List<dynamic> _readJsonList(String path) {
  final raw = File(path).readAsStringSync();
  return jsonDecode(raw) as List<dynamic>;
}

void main() {
  test('Simplified Chinese dictionary matches English keys', () {
    final english = _readJsonObject('assets/translations/en.json');
    final simplifiedChinese = _readJsonObject('assets/translations/zh-Hans.json');

    expect(simplifiedChinese.keys.toSet(), english.keys.toSet());
  });

  test('Simplified Chinese is declared as a bundled translation asset', () {
    final languages = _readJsonList('assets/translations/languages.json');
    final languageIds = languages
        .map((language) => (language as Map<String, dynamic>)['id'])
        .toSet();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(languageIds, contains('zh-Hans'));
    expect(pubspec, contains('assets/translations/zh-Hans.json'));
  });

  test('Google Play resource points at the current application id', () {
    final resources = _readJsonList('assets/additional_resources.json')
        .cast<Map<String, dynamic>>();
    final playStoreResource = resources.singleWhere(
      (resource) => resource['name'] == "Application's Google Store page",
    );

    expect(
      playStoreResource['value'],
      'https://play.google.com/store/apps/details?id=page.puzzak.paios',
    );
  });

  test('Resource titles are localized for bundled languages', () {
    final repository = ResourceRepository(notifyEngine: () {});
    final resource = {
      'name': "Application's Google Store page",
      'value': 'https://play.google.com/store/apps/details?id=page.puzzak.paios',
    };

    expect(repository.getResourceDisplayName(resource, 'zh-Hans'), '应用的 Google Play 页面');
    expect(repository.getResourceDisplayName(resource, 'zh'), '應用程式的 Google Play 頁面');
    expect(repository.getResourceDisplayName(resource, 'uk'), 'Сторінка додатка в Google Play');
    expect(repository.getResourceDisplayName(resource, 'de'), 'Google Play-Seite der App');
    expect(repository.getResourceDisplayName(resource, 'tr'), 'Uygulamanın Google Play sayfası');
  });
}
