import 'dart:convert';
import 'dart:math' as math;
import 'package:sqflite/sqflite.dart';
import 'package:http/http.dart' as http;
import '../database_helper.dart';
import '../config.dart';

/// Offline face verification service
/// Performs face matching locally without server connectivity
/// Uses cosine similarity to compare face embeddings
class OfflineFaceVerificationService {
  // Cosine similarity threshold for face matching (RAW score, not remapped)
  // Range: -1.0 to 1.0 (raw cosine similarity)
  // Lowered from 0.95 to 0.80 on 2026-09-22 to match server-side threshold
  // based on real learner_face_verification_log data showing genuine learners
  // scoring between 0.65 and 0.94 on legitimate clock-ins.
  // Must equal faceMatchThreshold in face_recognition_config.php (PHP server).
  static const double faceMatchThreshold = 0.80;

  // Minimum quality score to accept verification attempt (0.0 to 1.0)
  static const double minVerificationQuality = 0.5;

  /// Calculate cosine similarity between two embeddings
  /// Returns RAW cosine similarity in range [-1, 1] (higher = more similar)
  /// Formula: similarity = (A · B) / (||A|| * ||B||)
  /// CRITICAL: Returns raw score without remapping - threshold is calibrated for raw values
  double cosineSimilarity(List<double> embedding1, List<double> embedding2) {
    if (embedding1.length != embedding2.length) {
      throw ArgumentError(
          'Embeddings must have same length: ${embedding1.length} vs ${embedding2.length}');
    }

    // Calculate dot product (A · B)
    double dotProduct = 0.0;
    for (int i = 0; i < embedding1.length; i++) {
      dotProduct += embedding1[i] * embedding2[i];
    }

    // Calculate magnitudes (||A|| and ||B||)
    double magnitude1 = 0.0;
    double magnitude2 = 0.0;
    for (int i = 0; i < embedding1.length; i++) {
      magnitude1 += embedding1[i] * embedding1[i];
      magnitude2 += embedding2[i] * embedding2[i];
    }
    magnitude1 = math.sqrt(magnitude1);
    magnitude2 = math.sqrt(magnitude2);

    // Avoid division by zero
    if (magnitude1 == 0.0 || magnitude2 == 0.0) {
      return -1.0; // Return worst possible score for invalid embeddings
    }

    // Calculate RAW cosine similarity (no remapping!)
    double raw = dotProduct / (magnitude1 * magnitude2);

    // Clamp to [-1, 1] and round to 5 decimal places
    return (raw.clamp(-1.0, 1.0) * 100000).round() / 100000;
  }

  /// Get all cached face embeddings for a learner (front + back cameras)
  /// Returns list of maps with {embedding, camera_facing, quality_score}
  Future<List<Map<String, dynamic>>> getCachedEmbeddings(int learnerId) async {
    try {
      final db = await DatabaseHelper().database;
      final results = await db.query(
        'learner_face_cache',
        where: 'learner_id = ?',
        whereArgs: [learnerId],
      );

      if (results.isEmpty) {
        debugPrint(
            '[OFFLINE_FACE] No cached embeddings found for learner $learnerId');
        return [];
      }

      final embeddings = <Map<String, dynamic>>[];
      for (final row in results) {
        final embeddingJson = row['embedding'] as String;
        final embeddingList = jsonDecode(embeddingJson) as List;
        final embedding =
            embeddingList.map((e) => (e as num).toDouble()).toList();

        embeddings.add({
          'embedding': embedding,
          'camera_facing': row['camera_facing'] as String,
          'quality_score': row['quality_score'] as double?,
        });
      }

      debugPrint(
          '[OFFLINE_FACE] Retrieved ${embeddings.length} cached embedding(s) for learner $learnerId');
      return embeddings;
    } catch (e) {
      debugPrint('[OFFLINE_FACE] Error retrieving cached embeddings: $e');
      return [];
    }
  }

  /// Save face embedding to local cache
  /// Multi-camera support: stores separate embeddings for front and back cameras
  Future<bool> cacheEmbedding({
    required int learnerId,
    required List<double> embedding,
    required double qualityScore,
    required String cameraFacing, // 'front' or 'back'
  }) async {
    try {
      final db = await DatabaseHelper().database;
      final now = DateTime.now().toIso8601String();
      final embeddingJson = jsonEncode(embedding);

      await db.insert(
        'learner_face_cache',
        {
          'learner_id': learnerId,
          'camera_facing': cameraFacing,
          'embedding': embeddingJson,
          'quality_score': qualityScore,
          'enrolled_at': now,
          'updated_at': now,
          'synced':
              1, // Mark as synced since it's saved locally during enrollment
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      debugPrint(
          '[OFFLINE_FACE] Cached $cameraFacing embedding for learner $learnerId (${embedding.length} dimensions, quality: $qualityScore)');
      return true;
    } catch (e) {
      debugPrint('[OFFLINE_FACE] Error caching embedding: $e');
      return false;
    }
  }

  /// Check if learner has cached face embedding
  Future<bool> hasCachedEmbedding(int learnerId) async {
    try {
      final db = await DatabaseHelper().database;
      final count = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM learner_face_cache WHERE learner_id = ?',
        [learnerId],
      ));
      return count != null && count > 0;
    } catch (e) {
      debugPrint('[OFFLINE_FACE] Error checking cached embedding: $e');
      return false;
    }
  }

  /// Check if learner has BOTH front and back camera embeddings enrolled
  /// Required for complete multi-camera enrollment
  Future<bool> hasBothCameras(int learnerId) async {
    try {
      final db = await DatabaseHelper().database;
      final count = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(DISTINCT camera_facing) FROM learner_face_cache WHERE learner_id = ?',
        [learnerId],
      ));
      return (count ?? 0) >= 2;
    } catch (e) {
      debugPrint('[OFFLINE_FACE] Error checking both cameras: $e');
      return false;
    }
  }

  /// Get which camera(s) are enrolled for a learner
  Future<List<String>> getEnrolledCameras(int learnerId) async {
    try {
      final db = await DatabaseHelper().database;
      final results = await db.query(
        'learner_face_cache',
        columns: ['camera_facing'],
        where: 'learner_id = ?',
        whereArgs: [learnerId],
      );
      return results.map((r) => r['camera_facing'] as String).toList();
    } catch (e) {
      debugPrint('[OFFLINE_FACE] Error getting enrolled cameras: $e');
      return [];
    }
  }

  /// Verify face offline using cached embeddings
  /// Multi-camera: Matches against ALL stored embeddings (front + back) and takes the BEST score
  /// Returns map with: verified, matchScore, cached, matchedCamera
  Future<Map<String, dynamic>> verifyOffline({
    required int learnerId,
    required List<double> liveEmbedding,
    required double qualityScore,
    required String cameraFacing, // Camera used for current capture
    String verificationType = 'clock_in',
  }) async {
    try {
      debugPrint(
          '[OFFLINE_FACE] Starting offline verification for learner $learnerId (camera: $cameraFacing)');

      // QUALITY CHECK: Reject poor quality captures before comparison
      if (qualityScore < minVerificationQuality) {
        debugPrint(
            '[OFFLINE_FACE] Quality too low: $qualityScore < $minVerificationQuality');

        await _queueVerificationLog(
          learnerId: learnerId,
          embedding: liveEmbedding,
          matchScore: 0.0,
          verified: false,
          qualityScore: qualityScore,
          verificationType: verificationType,
          cameraFacing: cameraFacing,
          failureReason: 'quality_too_low',
        );

        return {
          'verified': false,
          'matchScore': 0.0,
          'cached': true,
          'message':
              'Image quality too low (score: ${qualityScore.toStringAsFixed(2)})',
          'failureReason': 'quality_too_low',
        };
      }

      // Get ALL cached embeddings (front + back)
      final cachedEmbeddings = await getCachedEmbeddings(learnerId);
      if (cachedEmbeddings.isEmpty) {
        debugPrint('[OFFLINE_FACE] No cached embeddings - verification failed');

        await _queueVerificationLog(
          learnerId: learnerId,
          embedding: liveEmbedding,
          matchScore: 0.0,
          verified: false,
          qualityScore: qualityScore,
          verificationType: verificationType,
          cameraFacing: cameraFacing,
          failureReason: 'no_cached_embedding',
        );

        return {
          'verified': false,
          'matchScore': 0.0,
          'cached': true,
          'message': 'No cached face data found',
          'failureReason': 'no_cached_embedding',
        };
      }

      // Match against ALL embeddings and take the BEST score
      double bestScore = -1.0;
      String? matchedCamera;

      for (final cachedData in cachedEmbeddings) {
        final cachedEmbedding = cachedData['embedding'] as List<double>;
        final storedCamera = cachedData['camera_facing'] as String;

        final similarity = cosineSimilarity(liveEmbedding, cachedEmbedding);
        debugPrint('[OFFLINE_FACE] Score vs $storedCamera camera: $similarity');

        if (similarity > bestScore) {
          bestScore = similarity;
          matchedCamera = storedCamera;
        }
      }

      debugPrint(
          '[OFFLINE_FACE] BEST score: $bestScore (matched: $matchedCamera, threshold: $faceMatchThreshold)');

      final verified = bestScore >= faceMatchThreshold;

      // Queue verification log for sync
      await _queueVerificationLog(
        learnerId: learnerId,
        embedding: liveEmbedding,
        matchScore: bestScore,
        verified: verified,
        qualityScore: qualityScore,
        verificationType: verificationType,
        cameraFacing: cameraFacing,
        failureReason: verified ? null : 'similarity_below_threshold',
      );

      return {
        'verified': verified,
        'matchScore': bestScore,
        'matchedCamera': matchedCamera,
        'cached': true,
        'message': verified
            ? 'Face verified offline (score: ${bestScore.toStringAsFixed(3)}, matched: $matchedCamera)'
            : 'Face does not match (best score: ${bestScore.toStringAsFixed(3)} < $faceMatchThreshold)',
        'failureReason': verified ? null : 'similarity_below_threshold',
      };
    } catch (e) {
      debugPrint('[OFFLINE_FACE] Error during offline verification: $e');

      await _queueVerificationLog(
        learnerId: learnerId,
        embedding: liveEmbedding,
        matchScore: 0.0,
        verified: false,
        qualityScore: qualityScore,
        verificationType: verificationType,
        cameraFacing: cameraFacing,
        failureReason: 'verification_error',
      );

      return {
        'verified': false,
        'matchScore': 0.0,
        'cached': true,
        'message': 'Offline verification error: $e',
        'failureReason': 'verification_error',
      };
    }
  }

  /// Queue verification log for server sync when online
  Future<void> _queueVerificationLog({
    required int learnerId,
    required List<double> embedding,
    required double matchScore,
    required bool verified,
    required double qualityScore,
    required String verificationType,
    required String cameraFacing, // Track which camera was used
    String? failureReason,
  }) async {
    try {
      final db = await DatabaseHelper().database;
      final now = DateTime.now().toIso8601String();

      await db.insert('learner_face_verification_queue', {
        'learner_id': learnerId,
        'embedding': jsonEncode(embedding),
        'match_score': matchScore,
        'verified': verified ? 1 : 0,
        'quality_score': qualityScore,
        'liveness_passed': 1,
        'verification_type': verificationType,
        'camera_facing': cameraFacing,
        'failure_reason': failureReason,
        'device_info': 'offline_verification',
        'attempted_at': now,
        'synced': 0,
        'created_at': now,
      });

      debugPrint(
          '[OFFLINE_FACE] Queued verification log for sync (verified: $verified, score: $matchScore, camera: $cameraFacing)');
    } catch (e) {
      debugPrint('[OFFLINE_FACE] Error queueing verification log: $e');
    }
  }

  /// Get count of unsynced verification logs
  Future<int> getUnsyncedVerificationCount() async {
    try {
      final db = await DatabaseHelper().database;
      final count = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM learner_face_verification_queue WHERE synced = 0',
      ));
      return count ?? 0;
    } catch (e) {
      debugPrint('[OFFLINE_FACE] Error getting unsynced count: $e');
      return 0;
    }
  }

  /// Sync queued verification logs to server
  /// Only marks logs as synced if server confirms successful processing
  Future<int> syncVerificationLogs() async {
    try {
      final db = await DatabaseHelper().database;

      // Get unsynced logs
      final unsyncedLogs = await db.query(
        'learner_face_verification_queue',
        where: 'synced = ?',
        whereArgs: [0],
        orderBy: 'created_at ASC',
      );

      if (unsyncedLogs.isEmpty) {
        debugPrint('[OFFLINE_FACE] No verification logs to sync');
        return 0;
      }

      debugPrint(
          '[OFFLINE_FACE] Found ${unsyncedLogs.length} verification logs to sync');

      // Prepare logs for sync
      final logsToSync = unsyncedLogs.map((log) {
        return {
          'id': log['id'], // Include local ID for server confirmation
          'learner_id': log['learner_id'],
          'embedding': log['embedding'], // Already JSON string
          'match_score': log['match_score'],
          'verified': log['verified'],
          'quality_score': log['quality_score'],
          'liveness_passed': log['liveness_passed'],
          'verification_type': log['verification_type'],
          'camera_facing': log['camera_facing'], // Include camera info
          'failure_reason': log['failure_reason'],
          'device_info': log['device_info'],
          'attempted_at': log['attempted_at'],
        };
      }).toList();

      // Send to server
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/sync_face_verification_logs.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'logs': logsToSync}),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);

        if (result['success'] == true) {
          // Get list of successfully synced IDs from server response
          final syncedIds = result['synced_ids'] as List? ?? [];
          final syncedCount = syncedIds.length;

          if (syncedCount > 0) {
            // Only mark logs as synced if server explicitly confirmed them
            for (final syncedId in syncedIds) {
              await db.update(
                'learner_face_verification_queue',
                {'synced': 1},
                where: 'id = ?',
                whereArgs: [syncedId],
              );
            }

            debugPrint(
                '[OFFLINE_FACE] Successfully synced $syncedCount/${unsyncedLogs.length} verification logs');
          } else {
            debugPrint(
                '[OFFLINE_FACE] Server accepted request but confirmed 0 synced logs');
          }

          return syncedCount;
        } else {
          debugPrint('[OFFLINE_FACE] Server rejected sync: ${result['message']}');
          return 0;
        }
      } else {
        debugPrint('[OFFLINE_FACE] Sync failed with status ${response.statusCode}');
        return 0;
      }
    } catch (e) {
      debugPrint('[OFFLINE_FACE] Error syncing verification logs: $e');
      return 0;
    }
  }

  /// Delete old cached embeddings (cleanup)
  Future<int> cleanupOldCache({int daysOld = 90}) async {
    try {
      final db = await DatabaseHelper().database;
      final cutoffDate =
          DateTime.now().subtract(Duration(days: daysOld)).toIso8601String();

      final deleted = await db.delete(
        'learner_face_cache',
        where: 'updated_at < ?',
        whereArgs: [cutoffDate],
      );

      debugPrint(
          '[OFFLINE_FACE] Deleted $deleted old cached embeddings (older than $daysOld days)');
      return deleted;
    } catch (e) {
      debugPrint('[OFFLINE_FACE] Error cleaning up cache: $e');
      return 0;
    }
  }

  /// Delete cached face embedding for a learner (for re-enrollment)
  /// Deletes ALL cached embeddings (front and back cameras)
  Future<bool> deleteLocalEmbedding(int learnerId) async {
    try {
      final db = await DatabaseHelper().database;
      final deleted = await db.delete(
        'learner_face_cache',
        where: 'learner_id = ?',
        whereArgs: [learnerId],
      );
      debugPrint(
          '[OFFLINE_FACE] Deleted $deleted cached embedding(s) for learner $learnerId');
      return deleted > 0;
    } catch (e) {
      debugPrint('[OFFLINE_FACE] Error deleting cached embedding: $e');
      return false;
    }
  }
}
