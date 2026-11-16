import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../config.dart';

/// Signature Sync Service
/// Syncs signature PNG files from local /signatures/ folder to server
class SignatureSyncService {
  static const String _syncedFilesKey = 'synced_signature_files';

  /// Sync all unsynced signature files to server
  /// Returns: number of files successfully synced
  static Future<int> syncAllSignatures() async {
    debugPrint('[SIGNATURE_SYNC] Starting signature sync...');
    
    try {
      // Get signatures directory
      final directory = await getApplicationDocumentsDirectory();
      final signaturesDir = Directory('${directory.path}/signatures');
      
      if (!await signaturesDir.exists()) {
        debugPrint('[SIGNATURE_SYNC] Signatures directory does not exist');
        return 0;
      }

      // Get list of already synced files
      final syncedFiles = await _getSyncedFiles();
      
      // List all PNG files in signatures folder
      final files = signaturesDir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.png'))
          .toList();

      debugPrint('[SIGNATURE_SYNC] Found ${files.length} signature files');
      
      if (files.isEmpty) {
        return 0;
      }

      int successCount = 0;
      
      // Upload each file that hasn't been synced yet
      for (final file in files) {
        final filename = file.path.split('/').last;
        
        // Skip if already synced
        if (syncedFiles.contains(filename)) {
          debugPrint('[SIGNATURE_SYNC] Skipping already synced: $filename');
          continue;
        }
        
        // Upload file
        final success = await _uploadSignatureFile(file, filename);
        
        if (success) {
          successCount++;
          // Mark as synced
          await _markFileSynced(filename);
          debugPrint('[SIGNATURE_SYNC] ✅ Synced: $filename');
        } else {
          debugPrint('[SIGNATURE_SYNC] ❌ Failed: $filename');
        }
        
        // Small delay between uploads to avoid overwhelming server
        await Future.delayed(const Duration(milliseconds: 200));
      }
      
      debugPrint('[SIGNATURE_SYNC] Sync complete: $successCount/${ files.length} files synced');
      return successCount;
      
    } catch (e) {
      debugPrint('[SIGNATURE_SYNC] Error during sync: $e');
      return 0;
    }
  }

  /// Upload a single signature file to server
  static Future<bool> _uploadSignatureFile(File file, String filename) async {
    try {
      // Read file bytes
      final bytes = await file.readAsBytes();
      
      // Create multipart request
      final uri = Uri.parse(AppConfig.buildUrl('sync_attendance_signatures.php'));
      final request = http.MultipartRequest('POST', uri);
      
      // Add authentication token if available
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      
      // Add file and filename
      request.files.add(http.MultipartFile.fromBytes(
        'signature_file',
        bytes,
        filename: filename,
      ));
      request.fields['filename'] = filename;
      
      // Send request
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      
      if (response.statusCode == 200) {
        final decoded = json.decode(responseBody);
        return decoded['success'] == true;
      } else {
        debugPrint('[SIGNATURE_SYNC] Upload failed (${response.statusCode}): $responseBody');
        return false;
      }
      
    } catch (e) {
      debugPrint('[SIGNATURE_SYNC] Upload error for $filename: $e');
      return false;
    }
  }

  /// Get list of already synced files from SharedPreferences
  static Future<Set<String>> _getSyncedFiles() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> synced = prefs.getStringList(_syncedFilesKey) ?? [];
    return synced.toSet();
  }

  /// Mark a file as synced
  static Future<void> _markFileSynced(String filename) async {
    final syncedFiles = await _getSyncedFiles();
    syncedFiles.add(filename);
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_syncedFilesKey, syncedFiles.toList());
  }

  /// Clear sync history (useful for testing or re-sync)
  static Future<void> clearSyncHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_syncedFilesKey);
    debugPrint('[SIGNATURE_SYNC] Sync history cleared');
  }

  /// Get count of unsynced signature files
  static Future<int> getUnsyncedCount() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final signaturesDir = Directory('${directory.path}/signatures');
      
      if (!await signaturesDir.exists()) {
        return 0;
      }

      final syncedFiles = await _getSyncedFiles();
      final files = signaturesDir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.png'))
          .toList();

      final unsyncedCount = files.where((file) {
        final filename = file.path.split('/').last;
        return !syncedFiles.contains(filename);
      }).length;

      return unsyncedCount;
    } catch (e) {
      debugPrint('[SIGNATURE_SYNC] Error getting unsynced count: $e');
      return 0;
    }
  }
}
