import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:my_app/models/event.dart';

/// A tactical service to persist the main feed locally.
/// Enables immediate content appearance (Sivox Instant-Load).
class FeedCacheService {
  static final FeedCacheService _instance = FeedCacheService._internal();
  factory FeedCacheService() => _instance;
  FeedCacheService._internal();

  static const String _fileName = 'Sivox_feed_cache.json';
  static const int _maxItems = 20; // Keep it lightweight

  Future<File> _getCacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Persists a list of events to disk.
  Future<void> saveEvents(List<Event> events) async {
    try {
      final file = await _getCacheFile();
      // We only cache the first batch to keep initial load lightning fast
      final subset = events.take(_maxItems).toList();
      final List<Map<String, dynamic>> data = subset.map((e) => e.toMap()).toList();
      await file.writeAsString(json.encode(data));
    } catch (e) {
      debugPrint('FeedCacheService Save Error: $e');
    }
  }

  /// Retrieves the cached events from disk.
  Future<List<Event>> getCachedEvents() async {
    try {
      final file = await _getCacheFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> data = json.decode(content);
        return data.map((e) => Event.fromMap(e as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      debugPrint('FeedCacheService Load Error: $e');
    }
    return [];
  }
}
