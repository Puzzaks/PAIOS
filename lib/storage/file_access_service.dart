import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Flutter-side wrapper for the SAF-based FileAccessPlugin.
/// Provides read/write/list/delete/rename operations on a user-chosen folder.
/// The actual URI is stored on the Android side in SharedPreferences so it
/// survives hot-restart without needing Hive to be open first.
class FileAccessService {
  static const _channel = MethodChannel('page.puzzak.geminilocal/file_access');

  // ── Directory management ──────────────────────────────────────────────────

  /// Opens the SAF directory picker. Returns the human-readable display path
  /// of the chosen directory, or null if the user cancelled.
  static Future<String?> pickDirectory() async {
    try {
      return await _channel.invokeMethod<String>('pickDirectory');
    } catch (e) {
      if (kDebugMode) print('[FileAccessService] pickDirectory error: $e');
      return null;
    }
  }

  /// Returns the display path of the currently saved directory, or null.
  static Future<String?> getDirectoryDisplayPath() async {
    try {
      return await _channel.invokeMethod<String>('getDirectoryDisplayPath');
    } catch (e) {
      return null;
    }
  }

  /// Returns true if a directory has been selected and saved.
  static Future<bool> hasDirectory() async {
    try {
      return await _channel.invokeMethod<bool>('hasDirectory') ?? false;
    } catch (e) {
      return false;
    }
  }

  // ── File operations ───────────────────────────────────────────────────────

  /// Writes [content] to [filename] inside the selected directory.
  /// Creates the file if it doesn't exist, overwrites if it does.
  static Future<bool> writeFile(String filename, String content) async {
    try {
      return await _channel.invokeMethod<bool>('writeFile', {
            'name': filename,
            'content': content,
          }) ??
          false;
    } catch (e) {
      if (kDebugMode) print('[FileAccessService] writeFile error: $e');
      return false;
    }
  }

  /// Reads and returns the content of [filename], or null if not found.
  static Future<String?> readFile(String filename) async {
    try {
      return await _channel.invokeMethod<String>('readFile', {'name': filename});
    } catch (e) {
      if (kDebugMode) print('[FileAccessService] readFile error: $e');
      return null;
    }
  }

  /// Lists all `.md` filenames inside the selected directory.
  static Future<List<String>> listFiles() async {
    try {
      final result = await _channel.invokeMethod<List>('listFiles');
      return result?.cast<String>() ?? [];
    } catch (e) {
      if (kDebugMode) print('[FileAccessService] listFiles error: $e');
      return [];
    }
  }

  /// Deletes [filename] from the selected directory. Returns true on success.
  static Future<bool> deleteFile(String filename) async {
    try {
      return await _channel.invokeMethod<bool>('deleteFile', {'name': filename}) ?? false;
    } catch (e) {
      if (kDebugMode) print('[FileAccessService] deleteFile error: $e');
      return false;
    }
  }

  /// Renames [oldName] to [newName] inside the selected directory.
  static Future<bool> renameFile(String oldName, String newName) async {
    try {
      return await _channel.invokeMethod<bool>('renameFile', {
            'oldName': oldName,
            'newName': newName,
          }) ??
          false;
    } catch (e) {
      if (kDebugMode) print('[FileAccessService] renameFile error: $e');
      return false;
    }
  }

  // ── Filename ↔ Name helpers ───────────────────────────────────────────────

  /// Converts a display name to a safe filename.
  /// e.g. "Pirate Persona" → "pirate_persona.md"
  static String nameToFilename(String name) {
    final base = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s_-]', unicode: true), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'^[_-]+|[_-]+$'), '');
    final stem = base.isEmpty ? 'prompt' : base;
    return '$stem.md';
  }

  /// Converts a filename back to a display name.
  /// e.g. "pirate_persona.md" → "Pirate Persona"
  static String filenameToName(String filename) {
    final base = filename.replaceAll(RegExp(r'\.md$', caseSensitive: false), '');
    return base
        .split('_')
        .map((word) => word.isEmpty ? '' : '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }
}
