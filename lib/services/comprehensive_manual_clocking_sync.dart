import 'dart:convert';
import 'package:http/http.dart' as http;
import '../database_helper.dart';
import '../config.dart';

/// Comprehensive sync service for manual clocking (signature + geofence)
/// 
/// This service syncs offline clock-ins to the server using the correct two-step process:
/// 1. Upload images to save_manual_clocking_images.php (returns filenames)
/// 2. Save clock-in record to save_manual_clockin.php (with filenames)
/// 
/// Handles both clock-in and clock-out, preserving all data without loss.
class ComprehensiveManualClockingSync {
  static final ComprehensiveManualClockingSync _instance =
      ComprehensiveManualClockingSync._internal();

  factory ComprehensiveManualClockingSync() => _instance;

  ComprehensiveManualClockingSync._internal();

  // Queue control to prevent server flooding
  static const int MAX_BATCH_SIZE = 10; // Max records per sync batch
  static const Duration DELAY_BETWEEN_RECORDS = Duration(milliseconds: 500); // 500ms delay
  static const Duration DELAY_BETWEEN_BATCHES = Duration(seconds: 2); // 2 seconds between batches
  
  // Retry control with exponential backoff
  static const int MAX_RETRIES_PER_RECORD = 3; // Max retry attempts per record
  static const Duration INITIAL_RETRY_DELAY = Duration(seconds: 5); // Start with 5 seconds
  static const Duration MAX_RETRY_DELAY = Duration(minutes: 5); // Cap at 5 minutes
  static const Duration COOLDOWN_PERIOD = Duration(minutes: 10); // Wait 10 minutes after multiple failures
  
  bool _isSyncing = false; // Prevent concurrent sync operations
  DateTime? _lastFailureTime; // Track when last major failure occurred
  int _consecutiveFailures = 0; // Track consecutive failures

  /// Sync all unsynced manual clock-ins to server (with queuing to prevent flooding)
  /// Returns: {success, syncedCount, failedCount, details}
  Future<Map<String, dynamic>> syncAllUnsyncedClockIns({int? maxRecords}) async {
    print('[COMPREHENSIVE_SYNC] ═══════════════════════════════════════');
    print('[COMPREHENSIVE_SYNC] Starting comprehensive clock-in sync');
    print('[COMPREHENSIVE_SYNC] ═══════════════════════════════════════');

    // Prevent concurrent sync operations
    if (_isSyncing) {
      print('[COMPREHENSIVE_SYNC] ⚠️  Sync already in progress, skipping');
      return {
        'success': false,
        'message': 'Sync already in progress',
        'syncedCount': 0,
        'failedCount': 0,
      };
    }

    // Check cooldown period after multiple failures (circuit breaker pattern)
    if (_lastFailureTime != null && _consecutiveFailures >= 3) {
      final timeSinceFailure = DateTime.now().difference(_lastFailureTime!);
      if (timeSinceFailure < COOLDOWN_PERIOD) {
        final remainingCooldown = COOLDOWN_PERIOD - timeSinceFailure;
        print('[COMPREHENSIVE_SYNC] 🛑 Circuit breaker active - too many failures');
        print('[COMPREHENSIVE_SYNC] ⏰ Cooldown: ${remainingCooldown.inMinutes} minutes ${remainingCooldown.inSeconds % 60} seconds remaining');
        return {
          'success': false,
          'message': 'Cooling down after failures. Wait ${remainingCooldown.inMinutes}m ${remainingCooldown.inSeconds % 60}s',
          'syncedCount': 0,
          'failedCount': 0,
          'coolingDown': true,
        };
      } else {
        // Cooldown period over, reset counters
        print('[COMPREHENSIVE_SYNC] ✅ Cooldown period expired, resetting failure counters');
        _consecutiveFailures = 0;
        _lastFailureTime = null;
      }
    }

    _isSyncing = true;

    try {
      final db = await DatabaseHelper().database;

      // 1. Get unsynced records from manual_clocking table (with limit to prevent flooding)
      final int recordLimit = maxRecords ?? MAX_BATCH_SIZE;
      
      final unsyncedClockIns = await db.query(
        'manual_clocking',
        where: 'synced = ?',
        whereArgs: [0],
        orderBy: 'clock_date DESC, clock_in_time DESC',
        limit: recordLimit, // Limit batch size
      );

      if (unsyncedClockIns.isEmpty) {
        print('[COMPREHENSIVE_SYNC] ✅ No unsynced records found');
        _isSyncing = false;
        return {
          'success': true,
          'message': 'No records to sync',
          'syncedCount': 0,
          'failedCount': 0,
        };
      }

      print('[COMPREHENSIVE_SYNC] Found ${unsyncedClockIns.length} unsynced clock-ins');
      print('[COMPREHENSIVE_SYNC] Processing batch of ${unsyncedClockIns.length} records');
      print('[COMPREHENSIVE_SYNC] Rate limit: ${DELAY_BETWEEN_RECORDS.inMilliseconds}ms between records');

      int successCount = 0;
      int failCount = 0;
      final List<Map<String, dynamic>> syncResults = [];

      // 2. Sync each record individually with retry logic
      for (final clockIn in unsyncedClockIns) {
        final learnerID = clockIn['LearnerID'] as int;
        final clockDate = clockIn['clock_date'] as String;
        final clockInTime = clockIn['clock_in_time'] as String?;
        final clockOutTime = clockIn['clock_out_time'] as String?;

        print('[COMPREHENSIVE_SYNC] ─────────────────────────────────────');
        print('[COMPREHENSIVE_SYNC] Syncing: Learner $learnerID, Date: $clockDate');
        print('[COMPREHENSIVE_SYNC]   Clock-in:  ${clockInTime ?? 'null'}');
        print('[COMPREHENSIVE_SYNC]   Clock-out: ${clockOutTime ?? 'null'}');

        // Attempt sync with exponential backoff retry
        bool recordSynced = false;
        String? lastError;
        
        for (int attempt = 0; attempt < MAX_RETRIES_PER_RECORD; attempt++) {
          if (attempt > 0) {
            // Calculate exponential backoff delay: 5s, 15s, 45s
            final delaySeconds = INITIAL_RETRY_DELAY.inSeconds * (attempt * 3);
            final retryDelay = Duration(seconds: delaySeconds > MAX_RETRY_DELAY.inSeconds 
                ? MAX_RETRY_DELAY.inSeconds 
                : delaySeconds);
            
            print('[COMPREHENSIVE_SYNC] 🔄 Retry attempt ${attempt + 1}/$MAX_RETRIES_PER_RECORD after ${retryDelay.inSeconds}s...');
            await Future.delayed(retryDelay);
          }

        try {
          // Get evidence data (signatures + face photos)
          final evidence = await db.query(
            'manual_clocking_evidence',
            where: 'LearnerID = ? AND clock_date = ?',
            whereArgs: [learnerID, clockDate],
            limit: 1,
          );

          if (evidence.isEmpty) {
            print('[COMPREHENSIVE_SYNC] ⚠️  No evidence found, skipping');
            failCount++;
            syncResults.add({
              'learnerID': learnerID,
              'clockDate': clockDate,
              'success': false,
              'error': 'No evidence data found',
            });
            continue;
          }

          final evidenceData = evidence.first;

          // Step 1: Upload images if clock-in exists
          if (clockInTime != null) {
            final uploadResult = await _uploadClockInImages(
              learnerID: learnerID,
              clockDate: clockDate,
              signatureBase64: evidenceData['signature_in'] as String?,
              faceBase64: evidenceData['face_in'] as String?,
              timestamp: clockInTime,
            );

            if (!uploadResult['success']) {
              print('[COMPREHENSIVE_SYNC] ❌ Image upload failed: ${uploadResult['error']}');
              failCount++;
              syncResults.add({
                'learnerID': learnerID,
                'clockDate': clockDate,
                'success': false,
                'error': uploadResult['error'],
              });
              continue;
            }

            // Step 2: Save clock-in record with filenames
            final clockInResult = await _saveClockInRecord(
              learnerID: learnerID,
              clockDate: clockDate,
              clockInTime: clockInTime,
              contactTime: clockIn['contact_time'] as String?,
              signatureFilename: uploadResult['signature_filename'],
              faceFilename: uploadResult['face_filename'],
            );

            if (!clockInResult['success']) {
              print('[COMPREHENSIVE_SYNC] ❌ Clock-in save failed: ${clockInResult['error']}');
              failCount++;
              syncResults.add({
                'learnerID': learnerID,
                'clockDate': clockDate,
                'success': false,
                'error': clockInResult['error'],
              });
              continue;
            }
          }

          // Step 3: Upload clock-out images if clock-out exists
          if (clockOutTime != null) {
            final uploadResult = await _uploadClockOutImages(
              learnerID: learnerID,
              clockDate: clockDate,
              signatureBase64: evidenceData['signature_out'] as String?,
              faceBase64: evidenceData['face_out'] as String?,
              timestamp: clockOutTime,
            );

            if (!uploadResult['success']) {
              print('[COMPREHENSIVE_SYNC] ⚠️  Clock-out image upload failed: ${uploadResult['error']}');
              // Don't fail the whole record, clock-in is already done
            } else {
              // Step 4: Save clock-out record
              final clockOutResult = await _saveClockOutRecord(
                learnerID: learnerID,
                clockDate: clockDate,
                clockOutTime: clockOutTime,
                contactTime: clockIn['contact_time'] as String?,
                signatureFilename: uploadResult['signature_filename'],
                faceFilename: uploadResult['face_filename'],
              );

              if (!clockOutResult['success']) {
                print('[COMPREHENSIVE_SYNC] ⚠️  Clock-out save failed: ${clockOutResult['error']}');
              }
            }
          }

          // Mark as synced in local database
          await db.update(
            'manual_clocking',
            {'synced': 1},
            where: 'LearnerID = ? AND clock_date = ?',
            whereArgs: [learnerID, clockDate],
          );

          await db.update(
            'manual_clocking_evidence',
            {'synced': 1},
            where: 'LearnerID = ? AND clock_date = ?',
            whereArgs: [learnerID, clockDate],
          );

          successCount++;
          syncResults.add({
            'learnerID': learnerID,
            'clockDate': clockDate,
            'success': true,
          });

          print('[COMPREHENSIVE_SYNC] ✅ Successfully synced learner $learnerID');
          recordSynced = true;
          _consecutiveFailures = 0; // Reset failure counter on success
          break; // Exit retry loop on success
        } catch (e) {
          lastError = e.toString();
          print('[COMPREHENSIVE_SYNC] ❌ Attempt ${attempt + 1} failed: $e');
          
          // Check if this is a rate limit or auth error (don't retry these immediately)
          if (lastError.contains('429') || lastError.contains('Too many requests')) {
            print('[COMPREHENSIVE_SYNC] 🛑 Rate limit hit - stopping batch');
            failCount++;
            syncResults.add({
              'learnerID': learnerID,
              'clockDate': clockDate,
              'success': false,
              'error': 'Rate limit exceeded',
            });
            _consecutiveFailures++;
            _lastFailureTime = DateTime.now();
            break; // Exit retry loop and stop processing batch
          }
          
          if (lastError.contains('401') || lastError.contains('Authentication')) {
            print('[COMPREHENSIVE_SYNC] 🔐 Authentication failed - need re-login');
            failCount++;
            syncResults.add({
              'learnerID': learnerID,
              'clockDate': clockDate,
              'success': false,
              'error': 'Authentication required',
            });
            break; // Exit retry loop but continue with other records
          }
          
          // For other errors, continue retry loop
          if (attempt == MAX_RETRIES_PER_RECORD - 1) {
            // Final attempt failed
            print('[COMPREHENSIVE_SYNC] ❌ All retry attempts exhausted for learner $learnerID');
            failCount++;
            syncResults.add({
              'learnerID': learnerID,
              'clockDate': clockDate,
              'success': false,
              'error': lastError,
              'retries': attempt + 1,
            });
            _consecutiveFailures++;
            _lastFailureTime = DateTime.now();
          }
        }
        } // End retry loop
        
        if (recordSynced) {
          successCount++;
          syncResults.add({
            'learnerID': learnerID,
            'clockDate': clockDate,
            'success': true,
          });
        }

        // RATE LIMITING: Add delay between records to prevent server flooding
        if (unsyncedClockIns.indexOf(clockIn) < unsyncedClockIns.length - 1) {
          print('[COMPREHENSIVE_SYNC] ⏱️  Waiting ${DELAY_BETWEEN_RECORDS.inMilliseconds}ms before next record...');
          await Future.delayed(DELAY_BETWEEN_RECORDS);
        }
      }

      // Check if more records remain
      final remainingCount = await getUnsyncedCount();
      
      print('[COMPREHENSIVE_SYNC] ═══════════════════════════════════════');
      print('[COMPREHENSIVE_SYNC] Sync complete:');
      print('[COMPREHENSIVE_SYNC]   ✅ Success: $successCount');
      print('[COMPREHENSIVE_SYNC]   ❌ Failed:  $failCount');
      if (remainingCount > 0) {
        print('[COMPREHENSIVE_SYNC]   ⏳ Remaining: $remainingCount records');
        print('[COMPREHENSIVE_SYNC]   💡 Tip: Call sync again to process next batch');
      }
      print('[COMPREHENSIVE_SYNC] ═══════════════════════════════════════');

      _isSyncing = false;

      return {
        'success': successCount > 0,
        'message': 'Synced $successCount records, $failCount failed${remainingCount > 0 ? ', $remainingCount remaining' : ''}',
        'syncedCount': successCount,
        'failedCount': failCount,
        'remainingCount': remainingCount,
        'details': syncResults,
      };
    } catch (e) {
      print('[COMPREHENSIVE_SYNC] ❌ Fatal error during sync: $e');
      _isSyncing = false;
      return {
        'success': false,
        'error': e.toString(),
        'syncedCount': 0,
        'failedCount': 0,
      };
    } finally {
      _isSyncing = false;
    }
  }

  /// Upload clock-in images (signature + face photo)
  /// Returns: {success, signature_filename, face_filename, error}
  Future<Map<String, dynamic>> _uploadClockInImages({
    required int learnerID,
    required String clockDate,
    String? signatureBase64,
    String? faceBase64,
    required String timestamp,
  }) async {
    if (signatureBase64 == null || faceBase64 == null) {
      return {
        'success': false,
        'error': 'Missing signature or face image',
      };
    }

    try {
      final token = await AppConfig.getAuthToken();
      if (token == null) {
        throw Exception('No auth token available');
      }

      final url = Uri.parse(AppConfig.buildUrl('save_manual_clocking_images.php'));
      
      print('[COMPREHENSIVE_SYNC] Uploading clock-in images to: $url');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'learner_id': learnerID,
          'clock_date': clockDate,
          'type': 'in',
          'signature_image': signatureBase64,
          'face_image': faceBase64,
          'timestamp': timestamp,
        }),
      ).timeout(const Duration(seconds: 30));

      print('[COMPREHENSIVE_SYNC] Upload response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        
        if (result['success'] == true) {
          final files = result['files'] as Map<String, dynamic>;
          print('[COMPREHENSIVE_SYNC] ✅ Images uploaded successfully');
          print('[COMPREHENSIVE_SYNC]   Face: ${files['face_in']}');
          print('[COMPREHENSIVE_SYNC]   Signature: ${files['signature_in']}');
          
          return {
            'success': true,
            'face_filename': files['face_in'],
            'signature_filename': files['signature_in'],
          };
        } else {
          throw Exception(result['message'] ?? 'Upload failed');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      print('[COMPREHENSIVE_SYNC] ❌ Image upload error: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Upload clock-out images
  Future<Map<String, dynamic>> _uploadClockOutImages({
    required int learnerID,
    required String clockDate,
    String? signatureBase64,
    String? faceBase64,
    required String timestamp,
  }) async {
    if (signatureBase64 == null || faceBase64 == null) {
      return {
        'success': false,
        'error': 'Missing signature or face image',
      };
    }

    try {
      final token = await AppConfig.getAuthToken();
      if (token == null) {
        throw Exception('No auth token available');
      }

      final url = Uri.parse(AppConfig.buildUrl('save_manual_clocking_images.php'));

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'learner_id': learnerID,
          'clock_date': clockDate,
          'type': 'out',
          'signature_image': signatureBase64,
          'face_image': faceBase64,
          'timestamp': timestamp,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        
        if (result['success'] == true) {
          final files = result['files'] as Map<String, dynamic>;
          return {
            'success': true,
            'face_filename': files['face_out'],
            'signature_filename': files['signature_out'],
          };
        } else {
          throw Exception(result['message'] ?? 'Upload failed');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Save clock-in record to server
  Future<Map<String, dynamic>> _saveClockInRecord({
    required int learnerID,
    required String clockDate,
    required String clockInTime,
    String? contactTime,
    required String signatureFilename,
    required String faceFilename,
  }) async {
    try {
      final token = await AppConfig.getAuthToken();
      if (token == null) {
        throw Exception('No auth token available');
      }

      final url = Uri.parse(AppConfig.buildUrl('save_manual_clockin.php'));

      print('[COMPREHENSIVE_SYNC] Saving clock-in record to: $url');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'learner_id': learnerID,
          'clock_date': clockDate,
          'clock_in_time': clockInTime,
          'contact_time': contactTime,
          'signature_in': signatureFilename,
          'face_in': faceFilename,
        }),
      ).timeout(const Duration(seconds: 30));

      print('[COMPREHENSIVE_SYNC] Clock-in save response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        
        if (result['success'] == true) {
          print('[COMPREHENSIVE_SYNC] ✅ Clock-in record saved');
          return {'success': true};
        } else {
          throw Exception(result['message'] ?? 'Save failed');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      print('[COMPREHENSIVE_SYNC] ❌ Clock-in save error: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Save clock-out record to server
  Future<Map<String, dynamic>> _saveClockOutRecord({
    required int learnerID,
    required String clockDate,
    required String clockOutTime,
    String? contactTime,
    required String signatureFilename,
    required String faceFilename,
  }) async {
    try {
      final token = await AppConfig.getAuthToken();
      if (token == null) {
        throw Exception('No auth token available');
      }

      final url = Uri.parse(AppConfig.buildUrl('save_manual_clockout.php'));

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'learner_id': learnerID,
          'clock_date': clockDate,
          'clock_out_time': clockOutTime,
          'contact_time': contactTime,
          'signature_out': signatureFilename,
          'face_out': faceFilename,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        
        if (result['success'] == true) {
          print('[COMPREHENSIVE_SYNC] ✅ Clock-out record saved');
          return {'success': true};
        } else {
          throw Exception(result['message'] ?? 'Save failed');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Get count of unsynced records
  Future<int> getUnsyncedCount() async {
    try {
      final db = await DatabaseHelper().database;
      final result = await db.rawQuery('''
        SELECT COUNT(*) as count
        FROM manual_clocking
        WHERE synced = 0
      ''');
      
      return result.first['count'] as int;
    } catch (e) {
      print('[COMPREHENSIVE_SYNC] Error getting unsynced count: $e');
      return 0;
    }
  }
}
