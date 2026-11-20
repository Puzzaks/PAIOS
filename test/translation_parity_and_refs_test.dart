import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geminilocal/parts/translator.dart';

void main() {
  group('Translation parity, key references & locale resolution', () {
    const expectedLocaleIds = <String>[
      'en',
      'uk',
      'zh',
      'zh-Hans',
      'de',
      'tr',
    ];

    test(
      'languages.json and all 6 locale JSON files have 100% identical key sets (469 keys) and non-empty values',
      () {
        final langFile = File('assets/translations/languages.json');
        expect(langFile.existsSync(), isTrue);

        final langList = jsonDecode(langFile.readAsStringSync()) as List<dynamic>;
        final langIds = langList
            .whereType<Map<String, dynamic>>()
            .map((entry) {
              expect(
                (entry['origin'] as String?)?.trim(),
                isNotEmpty,
                reason: 'Every language entry must have a non-empty origin',
              );
              expect(
                (entry['name'] as String?)?.trim(),
                isNotEmpty,
                reason: 'Every language entry must have a non-empty name',
              );
              return entry['id'] as String;
            })
            .toList();

        expect(langIds, equals(expectedLocaleIds));

        final Map<String, Map<String, dynamic>> localeMaps =
            <String, Map<String, dynamic>>{};

        for (final localeId in expectedLocaleIds) {
          final file = File('assets/translations/$localeId.json');
          expect(
            file.existsSync(),
            isTrue,
            reason: 'Missing translation file assets/translations/$localeId.json',
          );
          final raw = file.readAsStringSync();
          expect(
            raw.contains('\uFFFD'),
            isFalse,
            reason: '$localeId.json contains replacement character U+FFFD',
          );
          final decoded = jsonDecode(raw) as Map<String, dynamic>;
          localeMaps[localeId] = decoded;
        }

        final enMap = localeMaps['en']!;
        final enKeys = enMap.keys.toSet();
        expect(
          enKeys.length,
          469,
          reason: 'Expected exactly 469 translation keys in en.json',
        );

        for (final localeId in expectedLocaleIds) {
          final map = localeMaps[localeId]!;
          final keys = map.keys.toSet();
          final missingFromLocale = enKeys.difference(keys);
          final extraInLocale = keys.difference(enKeys);

          expect(
            missingFromLocale,
            isEmpty,
            reason: '$localeId.json is missing keys: $missingFromLocale',
          );
          expect(
            extraInLocale,
            isEmpty,
            reason: '$localeId.json has extra keys not in en.json: $extraInLocale',
          );
          expect(
            keys.length,
            469,
            reason: '$localeId.json key count must equal 469',
          );

          for (final entry in map.entries) {
            expect(
              entry.value,
              isA<String>(),
              reason: '$localeId.json key "${entry.key}" must have a String value',
            );
            final text = (entry.value as String).trim();
            expect(
              text,
              isNotEmpty,
              reason: '$localeId.json key "${entry.key}" has an empty value',
            );
            expect(
              Dictionary.hasMojibake(text),
              isFalse,
              reason: '$localeId.json key "${entry.key}" contains mojibake: $text',
            );
          }
        }
      },
    );

    test(
      'pubspec.yaml declares assets/translations/languages.json and every locale id JSON under flutter.assets',
      () {
        final langFile = File('assets/translations/languages.json');
        expect(langFile.existsSync(), isTrue);
        final langList = jsonDecode(langFile.readAsStringSync()) as List<dynamic>;
        final langIds = langList
            .whereType<Map<String, dynamic>>()
            .map((entry) => entry['id'] as String)
            .toList();
        expect(langIds, isNotEmpty);

        final pubspecFile = File('pubspec.yaml');
        expect(pubspecFile.existsSync(), isTrue);
        final lines = pubspecFile.readAsLinesSync();

        bool inFlutterSection = false;
        bool inAssetsSection = false;
        int? assetsIndent;
        final declaredAssets = <String>{};

        for (final rawLine in lines) {
          final trimmed = rawLine.trim();
          if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
          final indent = rawLine.length - rawLine.trimLeft().length;

          if (indent == 0) {
            inFlutterSection = trimmed == 'flutter:';
            inAssetsSection = false;
            assetsIndent = null;
            continue;
          }
          if (!inFlutterSection) continue;

          if (trimmed == 'assets:' || trimmed.startsWith('assets:')) {
            inAssetsSection = true;
            assetsIndent = indent;
            continue;
          }

          if (inAssetsSection) {
            if (assetsIndent != null &&
                indent <= assetsIndent &&
                !trimmed.startsWith('-')) {
              inAssetsSection = false;
              continue;
            }
            if (trimmed.startsWith('-')) {
              var assetPath = trimmed.substring(1).trim();
              final commentIdx = assetPath.indexOf('#');
              if (commentIdx != -1) {
                assetPath = assetPath.substring(0, commentIdx).trim();
              }
              if ((assetPath.startsWith('"') && assetPath.endsWith('"')) ||
                  (assetPath.startsWith("'") && assetPath.endsWith("'"))) {
                assetPath = assetPath.substring(1, assetPath.length - 1);
              }
              if (assetPath.isNotEmpty) {
                declaredAssets.add(assetPath);
              }
            }
          }
        }

        expect(
          declaredAssets,
          contains('assets/translations/languages.json'),
          reason: 'pubspec.yaml must declare assets/translations/languages.json',
        );
        for (final id in langIds) {
          final expectedAsset = 'assets/translations/$id.json';
          expect(
            declaredAssets,
            contains(expectedAsset),
            reason: 'pubspec.yaml flutter.assets is missing $expectedAsset',
          );
        }
      },
    );

    test(
      'all static dict.value(...) and _dictOrDefault(...) in lib/**/*.dart and tr("...") in android/**/*.kt exist in en.json',
      () {
        final enMap = jsonDecode(
          File('assets/translations/en.json').readAsStringSync(),
        ) as Map<String, dynamic>;
        final enKeys = enMap.keys.toSet();

        final dartDir = Directory('lib');
        expect(dartDir.existsSync(), isTrue);
        final dartFiles = dartDir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .toList();
        expect(dartFiles, isNotEmpty);

        final dictCallRegex = RegExp(
          r'\bdict\.value\(\s*(?:"([^"\\]+)"|' "'" r'([^' "'" r'\\]+)' "'" r')',
        );
        final dictOrDefaultRegex = RegExp(
          r'\b_dictOrDefault\(\s*[^,]+,\s*(?:"([^"\\]+)"|' "'" r'([^' "'" r'\\]+)' "'" r')',
        );
        final missingDartRefs = <String>[];
        int checkedDartRefs = 0;

        for (final file in dartFiles) {
          final content = file.readAsStringSync();
          for (final regex in [dictCallRegex, dictOrDefaultRegex]) {
            for (final match in regex.allMatches(content)) {
              final key = match.group(1) ?? match.group(2) ?? '';
              if (key.isEmpty || key.contains(r'$')) continue;
              checkedDartRefs++;
              if (!enKeys.contains(key)) {
                missingDartRefs.add('${file.path}: $key');
              }
            }
          }
        }

        expect(checkedDartRefs, greaterThan(300));
        expect(
          missingDartRefs,
          isEmpty,
          reason: 'Missing Dart translation keys in en.json: $missingDartRefs',
        );

        final ktDir = Directory('android/app/src/main/kotlin');
        expect(ktDir.existsSync(), isTrue);
        final ktFiles = ktDir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.kt'))
            .toList();
        expect(ktFiles, isNotEmpty);

        final trCallRegex = RegExp(r'\btr\(\s*"([^"\\]+)"');
        final missingKtRefs = <String>[];
        int checkedKtRefs = 0;

        for (final file in ktFiles) {
          final content = file.readAsStringSync();
          for (final match in trCallRegex.allMatches(content)) {
            final key = match.group(1) ?? '';
            if (key.isEmpty || key.contains(r'$')) continue;
            checkedKtRefs++;
            if (!enKeys.contains(key)) {
              missingKtRefs.add('${file.path}: $key');
            }
          }
        }

        expect(checkedKtRefs, greaterThan(20));
        expect(
          missingKtRefs,
          isEmpty,
          reason: 'Missing Kotlin tr() translation keys in en.json: $missingKtRefs',
        );
      },
    );

    test(
      'Dictionary.resolveSystemLocale maps Simplified/Traditional Chinese, European locales, and fallbacks accurately',
      () {
        // Simplified Chinese variants -> zh-Hans
        for (final raw in const <String>[
          'zh_CN',
          'zh-CN',
          'zh_SG',
          'zh_Hans',
          'zh-Hans-CN',
        ]) {
          expect(
            Dictionary.resolveSystemLocale(raw),
            'zh-Hans',
            reason: 'Expected $raw to resolve to zh-Hans',
          );
        }

        // Traditional Chinese & generic zh variants -> zh
        for (final raw in const <String>[
          'zh_TW',
          'zh_HK',
          'zh_MO',
          'zh_Hant',
          'zh',
        ]) {
          expect(
            Dictionary.resolveSystemLocale(raw),
            'zh',
            reason: 'Expected $raw to resolve to zh',
          );
        }

        // Supported European & Turkish locales
        expect(Dictionary.resolveSystemLocale('uk_UA'), 'uk');
        expect(Dictionary.resolveSystemLocale('de_DE'), 'de');
        expect(Dictionary.resolveSystemLocale('tr_TR'), 'tr');

        // Unsupported locale fallback -> en
        expect(Dictionary.resolveSystemLocale('fr_FR'), 'en');
        expect(Dictionary.resolveSystemLocale(''), 'en');
      },
    );
  });
}
