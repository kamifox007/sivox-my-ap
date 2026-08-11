import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

/// A robust singleton service to persist draft data (form inputs) 
/// across screen navigation AND app restarts/phone shutdowns.
class DraftService {
  static final DraftService _instance = DraftService._internal();
  factory DraftService() => _instance;
  DraftService._internal();

  Map<String, String> _drafts = HashMap<String, String>();
  bool _initialized = false;

  /// Initializes the storage by loading existing drafts from disk.
  /// Should be called at app startup.
  Future<void> init() async {
    if (_initialized) return;
    try {
      final file = await _getDraftFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final rawMap = json.decode(content) as Map<String, dynamic>;
        _drafts = HashMap<String, String>.from(
          rawMap.map((key, value) => MapEntry(key, value.toString()))
        );
      }
      _initialized = true;
    } catch (e) {
      debugPrint('DraftService Init Error: $e');
      _drafts = HashMap<String, String>();
      _initialized = true;
    }
  }

  Future<File> _getDraftFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/Sivox_drafts.json');
  }

  Future<void> _saveToDisk() async {
    try {
      final file = await _getDraftFile();
      await file.writeAsString(json.encode(_drafts));
    } catch (e) {
      debugPrint('DraftService Save Error: $e');
    }
  }

  /// Saves a draft value and persists it to disk immediately.
  void saveDraft(String key, String value) {
    _drafts[key] = value;
    _saveToDisk();
  }

  /// Retrieves a draft value.
  String getDraft(String key) {
    return _drafts[key] ?? '';
  }

  /// Checks if any draft exists for a prefix (e.g., 'event_')
  bool hasDraftForPrefix(String prefix) {
    return _drafts.keys.any((k) => k.startsWith(prefix) && _drafts[k]!.isNotEmpty);
  }

  /// Clears a specific draft.
  void clearDraft(String key) {
    _drafts.remove(key);
    _saveToDisk();
  }

  /// Clears all drafts matching a prefix.
  void clearDraftsByPrefix(String prefix) {
    _drafts.removeWhere((k, v) => k.startsWith(prefix));
    _saveToDisk();
  }

  /// Clears all drafts.
  void clearAll() {
    _drafts.clear();
    _saveToDisk();
  }
}
