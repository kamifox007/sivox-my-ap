import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart' as p;

class StorageService {
  final _supabase = Supabase.instance.client;

  Future<String?> uploadImage(File file, {String bucket = 'event-images'}) async {
    try {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${p.basename(file.path)}';
      final path = 'public/$fileName';
      
      await _supabase.storage.from(bucket).upload(path, file);
      
      // Get Public URL
      return _supabase.storage.from(bucket).getPublicUrl(path);
    } catch (e) {
// print cleaned
      return null;
    }
  }

  Future<void> deleteImage(String url, {String bucket = 'event-images'}) async {
    try {
      // Extract path from URL (simplified, ideally you store the path)
      final uri = Uri.parse(url);
      final path = uri.pathSegments.last;
      await _supabase.storage.from(bucket).remove(['public/$path']);
    } catch (e) {
// print cleaned
    }
  }

  /// Generates a temporary secure signed URL for private files (e.g., ticket PDFs or receipts)
  Future<String?> getPrivateUrl(String path, {String bucket = 'private-documents', int expiresInSeconds = 300}) async {
    try {
      final signedUrl = await _supabase.storage.from(bucket).createSignedUrl(path, expiresInSeconds);
      return signedUrl;
    } catch (e) {
      return null;
    }
  }
}

