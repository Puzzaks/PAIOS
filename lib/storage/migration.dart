import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MigrationService {
  static const String boxName = 'paios_storage';
  static const String migrationFlag = 'migration_completed';

  static Future<void> initiateMigration() async {
    if (!Hive.isBoxOpen(boxName)) {
      await Hive.initFlutter();
      await Hive.openBox(boxName);
    }
    final box = Hive.box(boxName);

    // If migration already happened, skip.
    if (box.get(migrationFlag, defaultValue: false) == true) {
      if (kDebugMode) {
        print("[HIVE MIGRATION] Migration already completed. Booting straight from Hive.");
      }
      return;
    }

    if (kDebugMode) {
      print("[HIVE MIGRATION] WARNING: Starting SharedPreferences to Hive migration. Older data will be transferred and validated.");
    }

    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 3));
      final keys = prefs.getKeys();

      if (keys.isEmpty) {
        if (kDebugMode) {
          print("[HIVE MIGRATION] No SharedPreferences data found. Fresh install confirmed. Marking migration complete.");
        }
        await box.put(migrationFlag, true);
        return;
      }

      int migratedCount = 0;

      // Migrate all keys from SharedPreferences to Hive
      for (String key in keys) {
        final value = prefs.get(key);
        if (value != null) {
          await box.put(key, value);
          migratedCount++;
        }
      }

      // Verify migration
      bool verificationPassed = true;
      for (String key in keys) {
        final hiveValue = box.get(key);
        final prefValue = prefs.get(key);

        if (hiveValue == null && prefValue != null) {
          verificationPassed = false;
          if (kDebugMode) print("[HIVE MIGRATION] Verification failed! Key '$key' was not found in Hive.");
          break;
        }

        // We use strings, bools, ints, doubles, etc. Normal equality works here.
        if (hiveValue != prefValue) {
          // Special handle for List<String> which is a bit wonky with equality sometimes
          if (hiveValue is List && prefValue is List) {
            if (hiveValue.length != prefValue.length) {
              verificationPassed = false;
              if (kDebugMode) print("[HIVE MIGRATION] Verification failed for key '$key': List length mismatch.");
              break;
            } else {
              for (int i = 0; i < hiveValue.length; i++) {
                if (hiveValue[i] != prefValue[i]) {
                  verificationPassed = false;
                  if (kDebugMode) print("[HIVE MIGRATION] Verification failed for key '$key': List element mismatch at index $i.");
                  break;
                }
              }
            }
          } else {
            verificationPassed = false;
            if (kDebugMode) print("[HIVE MIGRATION] Verification failed for key '$key': $hiveValue != $prefValue");
            break;
          }
        }
      }

      if (verificationPassed) {
        if (kDebugMode) {
          print("[HIVE MIGRATION] SUCCESS! All ($migratedCount) keys verified exactly. Cleared SharedPreferences legacy payload.");
        }
        // Successfully migrated
        await box.put(migrationFlag, true);
        await prefs.clear(); // Safe to delete legacy data to deprecate SP gracefully.
      } else {
        if (kDebugMode) {
          print("[HIVE MIGRATION] CRITICAL FAILURE. Verification failed. Retaining SharedPreferences for fallback and safety.");
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print("[HIVE MIGRATION] SharedPreferences unavailable or timed out ($e). Continuing with Hive.");
      }
    }
  }
}
