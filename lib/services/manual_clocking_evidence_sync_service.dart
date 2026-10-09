import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import '../database_helper.dart';
import '../config.dart';

/// Service to sync manual clocking evidence (face photos + signatures) between offline and online
/// Handles image storage locally and uploads to server when online
class ManualClockingEvidenceSyncService {
  static final ManualClockingEvidenceSyncService _instance =
      ManualClockingEvidenceSyncService._internal();

  factory ManualClockingEvidenceSyncService() => _instance;

  ManualClockingEvidenceSyncService._internal();

  /// Save manual clocking evidence offline
  /// Images are stored as base64 in SQLite temporarily
  Future<bool> saveEvidenceOffline({
    required int learnerID,
    required String clockDate,
    String? signatureInBase64,
    String? signatureOutBase64,
    String? faceInBase64,
    String? faceOutBase64,
  }) async {
    try {
      final db = await DatabaseHelper().database;

      await db.insert(
        'manual_clocking_evidence',
        {
          'LearnerID': learnerID,
          'clock_date': clockDate,
          'signature_in': signatureInBase64,
          'signature_out': signatureOutBase64,
          'face_in': faceInBase64,
          'face_out': faceOutBase64,
          'synced': 0,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      print(
          '[EVIDENCE_SYNC] Saved evidence offline for Learner $learnerID on $clockDate');
      return true;
    } catch (e) {
      print('[EVIDENCE_SYNC] Error saving evidence offline: $e');
      return false;
    }
  }

  /// Update existing evidence record (e.g., add clock-out images)
  Future<bool> updateEvidenceOffline({
    required int learnerID,
    required String clockDate,
    String? signatureOutBase64,
    String? faceOutBase64,
  }) async {
    try {
      final db = await DatabaseHelper().database;

      final Map<String, dynamic> updates = {
        'updated_at': DateTime.now().toIso8601String(),
        'synced': 0, // Mark as unsynced
      };

      if (signatureOutBase64 != null) {
        updates['signature_out'] = signatureOutBase64;
      }
      if (faceOutBase64 != null) {
        updates['face_out'] = faceOutBase64;
      }

      final count = await db.update(
        'manual_clocking_evidence',
        updates,
        where: 'LearnerID = ? AND clock_date = ?',
        whereArgs: [learnerID, clockDate],
      );

      print(
          '[EVIDENCE_SYNC] Updated evidence offline for Learner $learnerID on $clockDate ($count rows)');
      return count > 0;
    } catch (e) {
      print('[EVIDENCE_SYNC] Error updating evidence offline: $e');
      return false;
    }
  }

  /// Simple debug method to inspect database contents - call this manually
  Future<void> debugInspectDatabase() async {
    try {
      final db = await DatabaseHelper().database;

      print('[DEBUG] =====================================');
      print('[DEBUG] === MANUAL CLOCKING EVIDENCE INSPECTION ===');
      print('[DEBUG] =====================================');

      // Check if table exists
      final tableCheck = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='manual_clocking_evidence'");

      if (tableCheck.isEmpty) {
        print('[DEBUG] ❌ manual_clocking_evidence table does NOT exist!');

        // Show all tables that do exist
        final allTables = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name");
        print('[DEBUG] Available tables:');
        for (final table in allTables) {
          print('[DEBUG]   - ${table['name']}');
        }
        return;
      } else {
        print('[DEBUG] ✅ manual_clocking_evidence table exists');
      }

      // Get table schema
      final schema =
          await db.rawQuery("PRAGMA table_info(manual_clocking_evidence)");
      print('[DEBUG] Table Schema:');
      for (final column in schema) {
        print(
            '[DEBUG]   ${column['name']}: ${column['type']} (nullable: ${column['notnull'] == 0})');
      }

      // Get total record count
      final countResult = await db
          .rawQuery('SELECT COUNT(*) as count FROM manual_clocking_evidence');
      final totalCount = countResult.first['count'] as int;
      print('[DEBUG] Total records in table: $totalCount');

      if (totalCount == 0) {
        print('[DEBUG] ⚠️  No data in manual_clocking_evidence table');
        print('[DEBUG] This could mean:');
        print('[DEBUG]   1. No manual clocking has been performed yet');
        print('[DEBUG]   2. Data was not saved properly');
        print('[DEBUG]   3. Table was recently cleared');
      } else {
        // Get all records
        final allRecords = await db.query('manual_clocking_evidence',
            orderBy: 'evidence_id DESC');
        print('[DEBUG] All $totalCount records (newest first):');

        for (int i = 0; i < allRecords.length; i++) {
          final record = allRecords[i];
          print('[DEBUG] ========== Record ${i + 1}/${totalCount} ==========');
          print('[DEBUG]   Evidence ID: ${record['evidence_id']}');
          print('[DEBUG]   Learner ID: ${record['LearnerID']}');
          print('[DEBUG]   Clock Date: ${record['clock_date']}');
          print(
              '[DEBUG]   Signature In: ${record['signature_in'] != null ? 'YES (${record['signature_in'].toString().length} chars)' : 'NO'}');
          print(
              '[DEBUG]   Signature Out: ${record['signature_out'] != null ? 'YES (${record['signature_out'].toString().length} chars)' : 'NO'}');
          print(
              '[DEBUG]   Face In: ${record['face_in'] != null ? 'YES (${record['face_in'].toString().length} chars)' : 'NO'}');
          print(
              '[DEBUG]   Face Out: ${record['face_out'] != null ? 'YES (${record['face_out'].toString().length} chars)' : 'NO'}');
          print('[DEBUG]   Synced: ${record['synced']}');
          print('[DEBUG]   Created: ${record['created_at']}');
          print('[DEBUG]   Updated: ${record['updated_at']}');

          // Sample base64 data (first 100 chars) - for debugging
          if (record['signature_in'] != null) {
            final sig = record['signature_in'].toString();
            final sample =
                sig.length > 100 ? sig.substring(0, 100) + "..." : sig;
            print('[DEBUG]   Signature In Sample: $sample');
          }
          if (record['face_in'] != null) {
            final face = record['face_in'].toString();
            final sample =
                face.length > 100 ? face.substring(0, 100) + "..." : face;
            print('[DEBUG]   Face In Sample: $sample');
          }

          // Also check related learner data
          final learnerQuery = await db.query(
            'learnerDetails',
            where: 'learnerId = ?',
            whereArgs: [record['LearnerID']],
            limit: 1,
          );

          if (learnerQuery.isNotEmpty) {
            final learner = learnerQuery.first;
            print(
                '[DEBUG]   Learner Name: ${learner['name']} ${learner['surname']}');
            print('[DEBUG]   Learner ID Number: ${learner['idNumber']}');
          } else {
            print(
                '[DEBUG]   ⚠️  Learner data not found for ID ${record['LearnerID']}');
          }

          print('[DEBUG]   ================================');

          // Only show first 10 records to avoid overwhelming output
          if (i >= 9) {
            print('[DEBUG] ... (showing only first 10 records)');
            break;
          }
        }
      }

      print('[DEBUG] =====================================');
      print('[DEBUG] === INSPECTION COMPLETE ===');
      print('[DEBUG] =====================================');
    } catch (e, stackTrace) {
      print('[DEBUG] ❌ Error during database inspection: $e');
      print('[DEBUG] Stack trace: $stackTrace');
    }
  }

  Future<List<Map<String, dynamic>>> getUnsyncedEvidence() async {
    try {
      final db = await DatabaseHelper().database;

      // DEBUG: First check what's in the table
      final allRecords = await db.query('manual_clocking_evidence');
      print('[EVIDENCE_SYNC] === DATABASE INSPECTION ===');
      print(
          '[EVIDENCE_SYNC] Total records in manual_clocking_evidence: ${allRecords.length}');

      if (allRecords.isNotEmpty) {
        print('[EVIDENCE_SYNC] Sample records:');
        for (int i = 0; i < allRecords.length && i < 5; i++) {
          final record = allRecords[i];
          print('[EVIDENCE_SYNC] Record ${i + 1}:');
          print('  Evidence ID: ${record['evidence_id']}');
          print('  Learner ID: ${record['LearnerID']}');
          print('  Clock Date: ${record['clock_date']}');
          print(
              '  Signature In: ${record['signature_in'] != null ? 'YES (${record['signature_in'].toString().length} chars)' : 'NO'}');
          print(
              '  Signature Out: ${record['signature_out'] != null ? 'YES (${record['signature_out'].toString().length} chars)' : 'NO'}');
          print(
              '  Face In: ${record['face_in'] != null ? 'YES (${record['face_in'].toString().length} chars)' : 'NO'}');
          print(
              '  Face Out: ${record['face_out'] != null ? 'YES (${record['face_out'].toString().length} chars)' : 'NO'}');
          print('  Synced: ${record['synced']}');
          print('  Created: ${record['created_at']}');
          print('  Updated: ${record['updated_at']}');
          print('  ---');
        }
      }
      print('[EVIDENCE_SYNC] === END DATABASE INSPECTION ===');

      final records = await db.query(
        'manual_clocking_evidence',
        where: 'synced = ?',
        whereArgs: [0],
        orderBy: 'created_at ASC',
      );

      print(
          '[EVIDENCE_SYNC] Found ${records.length} unsynced evidence records');
      return records;
    } catch (e) {
      print('[EVIDENCE_SYNC] Error getting unsynced evidence: $e');
      return [];
    }
  }

  /// Sync unsynced evidence to server
  Future<Map<String, dynamic>> syncToServer() async {
    try {
      // DEBUG: Inspect database contents first
      await debugInspectDatabase();

      final unsyncedRecords = await getUnsyncedEvidence();

      if (unsyncedRecords.isEmpty) {
        return {
          'success': true,
          'message': 'No records to sync',
          'synced_count': 0,
        };
      }

      print(
          '[EVIDENCE_SYNC] Starting sync of ${unsyncedRecords.length} records to server');

      // Prepare records for sync (convert image paths to base64 if needed)
      final recordsToSync = unsyncedRecords.map((record) {
        return {
          'LearnerID': record['LearnerID'],
          'clock_date': record['clock_date'],
          'signature_in_base64': record['signature_in'],
          'signature_out_base64': record['signature_out'],
          'face_in_base64': record['face_in'],
          'face_out_base64': record['face_out'],
        };
      }).toList();

      // Send to server
      final url =
          Uri.parse('${AppConfig.baseUrl}/sync_manual_clocking_evidence.php');

      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'records': recordsToSync}),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final result = json.decode(response.body);

        if (result['success'] == true) {
          // Mark successfully synced records
          await _markRecordsAsSynced(result['results']);

          print(
              '[EVIDENCE_SYNC] ✅ Sync complete: ${result['success_count']} succeeded, ${result['fail_count']} failed');

          return {
            'success': true,
            'message': result['message'],
            'synced_count': result['success_count'],
            'failed_count': result['fail_count'],
            'results': result['results'],
          };
        } else {
          throw Exception(result['error'] ?? 'Unknown server error');
        }
      } else {
        throw Exception('Server returned status ${response.statusCode}');
      }
    } catch (e) {
      print('[EVIDENCE_SYNC] ❌ Sync failed: $e');
      return {
        'success': false,
        'error': e.toString(),
        'synced_count': 0,
      };
    }
  }

  /// Mark successfully synced records in local database
  Future<void> _markRecordsAsSynced(List<dynamic> results) async {
    try {
      final db = await DatabaseHelper().database;

      for (var result in results) {
        if (result['success'] == true) {
          final learnerID = result['learner_id'];
          final clockDate = result['clock_date'];

          await db.update(
            'manual_clocking_evidence',
            {'synced': 1, 'updated_at': DateTime.now().toIso8601String()},
            where: 'LearnerID = ? AND clock_date = ?',
            whereArgs: [learnerID, clockDate],
          );

          print(
              '[EVIDENCE_SYNC] Marked as synced: Learner $learnerID on $clockDate');
        }
      }
    } catch (e) {
      print('[EVIDENCE_SYNC] Error marking records as synced: $e');
    }
  }

  /// Get evidence for a specific learner and date (from local DB)
  Future<Map<String, dynamic>?> getEvidence({
    required int learnerID,
    required String clockDate,
  }) async {
    try {
      final db = await DatabaseHelper().database;

      final records = await db.query(
        'manual_clocking_evidence',
        where: 'LearnerID = ? AND clock_date = ?',
        whereArgs: [learnerID, clockDate],
        limit: 1,
      );

      if (records.isNotEmpty) {
        return records.first;
      }
      return null;
    } catch (e) {
      print('[EVIDENCE_SYNC] Error getting evidence: $e');
      return null;
    }
  }

  /// Get count of unsynced records
  Future<int> getUnsyncedCount() async {
    try {
      final db = await DatabaseHelper().database;

      final result = await db.rawQuery('''
        SELECT COUNT(*) as count
        FROM manual_clocking_evidence
        WHERE synced = 0
      ''');

      if (result.isNotEmpty) {
        return result.first['count'] as int;
      }
      return 0;
    } catch (e) {
      print('[EVIDENCE_SYNC] Error getting unsynced count: $e');
      return 0;
    }
  }

  /// Download evidence from server for a specific learner and date
  /// (for viewing synced records when online)
  Future<Map<String, dynamic>?> downloadFromServer({
    required int learnerID,
    required String clockDate,
  }) async {
    try {
      final url = Uri.parse(
          '${AppConfig.baseUrl}/get_manual_clocking_evidence.php?learner_id=$learnerID&clock_date=$clockDate');

      final response = await http.get(url).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final result = json.decode(response.body);

        if (result['success'] == true && result['records'] != null) {
          final records = result['records'] as List;
          if (records.isNotEmpty) {
            return records.first as Map<String, dynamic>;
          }
        }
      }
      return null;
    } catch (e) {
      print('[EVIDENCE_SYNC] Error downloading from server: $e');
      return null;
    }
  }

  /// Auto-sync when connection is available
  Future<void> autoSyncIfOnline() async {
    try {
      // Check if there are unsynced records
      final unsyncedCount = await getUnsyncedCount();

      if (unsyncedCount > 0) {
        print(
            '[EVIDENCE_SYNC] Auto-sync triggered: $unsyncedCount unsynced records');

        final result = await syncToServer();

        if (result['success'] == true) {
          print(
              '[EVIDENCE_SYNC] ✅ Auto-sync complete: ${result['synced_count']} records synced');
        } else {
          print('[EVIDENCE_SYNC] ⚠️ Auto-sync failed: ${result['error']}');
        }
      }
    } catch (e) {
      print('[EVIDENCE_SYNC] Auto-sync error: $e');
    }
  }
}
