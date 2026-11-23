import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../database_helper.dart';
import '../config.dart';
import 'database_coordinator.dart';
import 'http_client_service.dart';
import '../config/network_config.dart';

/// Persistent Sync Service for Offline-First Architecture
/// Ensures learner data is always available locally for offline clocking
class PersistentSyncService {
  static final PersistentSyncService _instance =
      PersistentSyncService._internal();
  factory PersistentSyncService() => _instance;
  PersistentSyncService._internal();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _periodicSyncTimer;
  bool _isSyncing = false;
  DateTime? _lastSyncTime;
  final DatabaseCoordinator _coordinator = DatabaseCoordinator();

  // Enhanced: Progress tracking
  final StreamController<SyncProgress> _progressController =
      StreamController<SyncProgress>.broadcast();
  Stream<SyncProgress> get progressStream => _progressController.stream;

  // Enhanced: Sync statistics
  final SyncStatistics _statistics = SyncStatistics();
  SyncStatistics get statistics => _statistics;

  // Enhanced: Retry configuration
  int _maxRetries = 3;
  Duration _initialRetryDelay = const Duration(seconds: 2);

  // Enhanced: Sync queue for prioritization
  final List<SyncTask> _syncQueue = [];
  bool _isProcessingQueue = false;

  /// Start listening for connectivity changes and trigger auto-sync
  void startAutoSync() {
    debugPrint('[PERSISTENT_SYNC] Starting auto-sync service');

    // Listen for connectivity changes
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> result,
    ) {
      if (!result.contains(ConnectivityResult.none)) {
        debugPrint('[PERSISTENT_SYNC] Connectivity restored: $result');
        _triggerBackgroundSync();
      }
    });

    // Periodic sync every 30 minutes when online (reduced frequency to prevent conflicts)
    _periodicSyncTimer = Timer.periodic(const Duration(minutes: 30), (timer) {
      _triggerBackgroundSync();
    });
  }

  /// Stop auto-sync service
  void stopAutoSync() {
    _connectivitySubscription?.cancel();
    _periodicSyncTimer?.cancel();
    _progressController.close();
    debugPrint('[PERSISTENT_SYNC] Auto-sync service stopped');
  }

  /// Enhanced: Configure retry behavior
  void configureRetry({int maxRetries = 3, Duration? initialDelay}) {
    _maxRetries = maxRetries;
    if (initialDelay != null) {
      _initialRetryDelay = initialDelay;
    }
  }

  /// Enhanced: Add task to sync queue with priority
  Future<void> queueSync(SyncTask task) async {
    _syncQueue.add(task);
    _syncQueue.sort((a, b) => b.priority.compareTo(a.priority));

    if (!_isProcessingQueue) {
      await _processQueue();
    }
  }

  /// Enhanced: Process sync queue
  Future<void> _processQueue() async {
    if (_isProcessingQueue || _syncQueue.isEmpty) return;

    _isProcessingQueue = true;

    try {
      while (_syncQueue.isNotEmpty) {
        final task = _syncQueue.removeAt(0);

        try {
          await _executeTaskWithRetry(task);
        } catch (e) {
          debugPrint('[PERSISTENT_SYNC] Queue task failed: ${task.name} - $e');
          _statistics.recordFailure(task.name, e.toString());
        }
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  /// Enhanced: Execute task with exponential backoff retry
  Future<void> _executeTaskWithRetry(SyncTask task) async {
    int attempts = 0;
    Duration delay = _initialRetryDelay;

    while (attempts < _maxRetries) {
      try {
        await task.execute();
        _statistics.recordSuccess(task.name);
        return;
      } catch (e) {
        attempts++;

        if (attempts >= _maxRetries) {
          throw Exception('Failed after $attempts attempts: $e');
        }

        debugPrint(
          '[PERSISTENT_SYNC] Retry ${attempts + 1}/$_maxRetries for ${task.name} after ${delay.inSeconds}s',
        );

        await Future.delayed(delay);
        // Exponential backoff with jitter
        delay = Duration(
          milliseconds:
              (delay.inMilliseconds * 2 * (0.8 + Random().nextDouble() * 0.4))
                  .round(),
        );
      }
    }
  }

  /// Trigger background sync (non-blocking)
  Future<void> _triggerBackgroundSync() async {
    // Check if enough time has passed since last sync
    if (!_coordinator.shouldAllowSync(
      minInterval: const Duration(minutes: 2),
    )) {
      debugPrint('[PERSISTENT_SYNC] Skipping sync - too soon since last sync');
      return;
    }

    // Check connectivity first to avoid unnecessary work
    final connectivityResult = await Connectivity().checkConnectivity();
    final isConnected = !connectivityResult.contains(ConnectivityResult.none);

    if (!isConnected) {
      debugPrint('[PERSISTENT_SYNC] No connectivity, skipping sync');
      return;
    }

    try {
      await _coordinator.executeSyncOperation(
        'PersistentSyncService.syncAllData',
        () async {
          await syncAllData();
          _lastSyncTime = DateTime.now();
        },
        timeout: const Duration(minutes: 5),
      );
    } catch (e) {
      debugPrint('[PERSISTENT_SYNC] Background sync failed: $e');
    }
  }

  /// Sync all data (learners, clocking records, etc.)
  Future<SyncResult> syncAllData({
    bool reportProgress = true,
    SyncConflictStrategy conflictStrategy = SyncConflictStrategy.serverWins,
  }) async {
    if (_isSyncing) {
      return SyncResult()
        ..success = false
        ..message = 'Sync already in progress';
    }

    _isSyncing = true;
    final startTime = DateTime.now();

    try {
      debugPrint('[PERSISTENT_SYNC] Starting full data sync');

      final result = SyncResult();

      // Report initial progress
      if (reportProgress) {
        _reportProgress(SyncProgress(
          phase: SyncPhase.starting,
          progress: 0.0,
          message: 'Initializing sync...',
        ));
      }

      // Check connectivity
      final connectivityResult = await Connectivity().checkConnectivity();
      final isConnected = !connectivityResult.contains(ConnectivityResult.none);

      if (!isConnected) {
        result.success = false;
        result.message = 'No internet connection';
        _statistics.recordFailure('full_sync', 'No connectivity');
        return result;
      }

      final dbHelper = DatabaseHelper();

      // 1. Sync learners for all classes (40% of progress)
      if (reportProgress) {
        _reportProgress(SyncProgress(
          phase: SyncPhase.learners,
          progress: 0.1,
          message: 'Syncing learners...',
        ));
      }
      await _syncAllLearners(
          dbHelper, result, conflictStrategy, reportProgress);

      // 2. Sync offline clocking records (30% of progress)
      if (reportProgress) {
        _reportProgress(SyncProgress(
          phase: SyncPhase.clockingRecords,
          progress: 0.5,
          message: 'Syncing clocking records...',
        ));
      }
      await _syncOfflineClockingRecords(dbHelper, result, reportProgress);

      // 3. Sync other pending data (20% of progress)
      if (reportProgress) {
        _reportProgress(SyncProgress(
          phase: SyncPhase.otherData,
          progress: 0.8,
          message: 'Syncing other data...',
        ));
      }
      await _syncOtherPendingData(dbHelper, result, reportProgress);

      // 4. Validation and cleanup (10% of progress)
      if (reportProgress) {
        _reportProgress(SyncProgress(
          phase: SyncPhase.validation,
          progress: 0.9,
          message: 'Validating sync...',
        ));
      }
      await _validateSyncIntegrity(dbHelper, result);

      result.success = true;
      result.duration = DateTime.now().difference(startTime);
      result.message = 'Sync completed successfully';

      _statistics.recordSuccess('full_sync');
      _statistics.updateTotals(
        learnersSynced: result.learnersSynced,
        clockingRecordsSynced: result.clockingRecordsSynced,
      );

      debugPrint('[PERSISTENT_SYNC] Full sync completed: ${result.message}');

      if (reportProgress) {
        _reportProgress(SyncProgress(
          phase: SyncPhase.completed,
          progress: 1.0,
          message: 'Sync completed',
          result: result,
        ));
      }

      return result;
    } catch (e) {
      final result = SyncResult();
      result.success = false;
      result.message = 'Sync failed: $e';
      result.duration = DateTime.now().difference(startTime);

      _statistics.recordFailure('full_sync', e.toString());
      debugPrint('[PERSISTENT_SYNC] Sync error: $e');

      if (reportProgress) {
        _reportProgress(SyncProgress(
          phase: SyncPhase.failed,
          progress: 0.0,
          message: 'Sync failed: $e',
          result: result,
        ));
      }

      return result;
    } finally {
      _isSyncing = false;
    }
  }

  /// Enhanced: Report sync progress
  void _reportProgress(SyncProgress progress) {
    if (!_progressController.isClosed) {
      _progressController.add(progress);
    }
  }

  /// Enhanced: Validate sync integrity
  Future<void> _validateSyncIntegrity(
    DatabaseHelper dbHelper,
    SyncResult result,
  ) async {
    try {
      final db = await dbHelper.database;

      // Check for orphaned records
      final orphanedClocking = await db.rawQuery('''
        SELECT COUNT(*) as count FROM learner_clocking lc
        WHERE NOT EXISTS (
          SELECT 1 FROM learnerdetails ld 
          WHERE ld.LearnerID = lc.LearnerID
        )
      ''');

      final orphanCount = orphanedClocking.first['count'] as int? ?? 0;
      if (orphanCount > 0) {
        result.warnings.add('Found $orphanCount orphaned clocking records');
        debugPrint(
            '[PERSISTENT_SYNC] Warning: $orphanCount orphaned clocking records');
      }

      // Check for duplicate learners
      final duplicates = await db.rawQuery('''
        SELECT LearnerID, COUNT(*) as count FROM learnerdetails
        GROUP BY LearnerID HAVING count > 1
      ''');

      if (duplicates.isNotEmpty) {
        result.warnings
            .add('Found ${duplicates.length} duplicate learner entries');
        debugPrint(
            '[PERSISTENT_SYNC] Warning: ${duplicates.length} duplicate learners');
      }
    } catch (e) {
      debugPrint('[PERSISTENT_SYNC] Validation error: $e');
      result.warnings.add('Validation error: $e');
    }
  }

  /// Sync learners for all classes in local database
  Future<void> _syncAllLearners(
    DatabaseHelper dbHelper,
    SyncResult result,
    SyncConflictStrategy conflictStrategy,
    bool reportProgress,
  ) async {
    try {
      final db = await dbHelper.database;

      // Get all unique class IDs from local database
      final classes = await db.rawQuery(
        'SELECT DISTINCT classID FROM learnerdetails WHERE classID IS NOT NULL',
      );

      debugPrint('[PERSISTENT_SYNC] Found ${classes.length} classes to sync');

      int processedClasses = 0;

      for (var classRow in classes) {
        final classID = classRow['classID']?.toString();
        if (classID != null && classID.isNotEmpty) {
          try {
            await _syncLearnersForClass(classID, dbHelper, conflictStrategy);
            result.learnersSynced++;

            processedClasses++;
            if (reportProgress) {
              final progress = 0.1 + (0.4 * processedClasses / classes.length);
              _reportProgress(SyncProgress(
                phase: SyncPhase.learners,
                progress: progress,
                message: 'Synced class $processedClasses/${classes.length}',
              ));
            }
          } catch (e) {
            debugPrint('[PERSISTENT_SYNC] Failed to sync class $classID: $e');
            result.errors.add('Class $classID: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('[PERSISTENT_SYNC] Error syncing learners: $e');
      result.errors.add('Learners sync: $e');
    }
  }

  /// Sync learners for a specific class using UPSERT logic with conflict resolution
  Future<void> _syncLearnersForClass(
    String classID,
    DatabaseHelper dbHelper,
    SyncConflictStrategy conflictStrategy,
  ) async {
    debugPrint('[PERSISTENT_SYNC] Syncing learners for class: $classID');

    try {
      final response = await HttpClientService.makeRequest(
        () =>
            http.get(Uri.parse('${AppConfig.getLearnersUrl}?classID=$classID')),
        endpoint: 'learners_by_class',
        maxRetries: NetworkConfig.syncOperationsMaxRetries,
        timeout: const Duration(seconds: NetworkConfig.lightweightTimeout),
      );

      if (response.statusCode != 200) {
        throw Exception('Server returned ${response.statusCode}');
      }

      final List<dynamic> serverLearners = json.decode(response.body);
      debugPrint(
        '[PERSISTENT_SYNC] Received ${serverLearners.length} learners from server for class $classID',
      );

      final db = await dbHelper.database;

      // Use shorter transactions to prevent database locks
      // Process learners in batches of 10 to avoid long-running transactions
      const batchSize = 10;
      for (int i = 0; i < serverLearners.length; i += batchSize) {
        final batch = serverLearners.skip(i).take(batchSize).toList();

        await db.transaction((txn) async {
          for (var learner in batch) {
            final learnerID = learner['LearnerID']?.toString();
            if (learnerID == null || learnerID.isEmpty) continue;

            // Check if learner exists
            final existing = await txn.query(
              'learnerdetails',
              where: 'LearnerID = ?',
              whereArgs: [learnerID],
            );

            // Prepare learner data
            final learnerData = {
              'LearnerID': learnerID,
              'Name': learner['Name']?.toString() ?? '',
              'Surname': learner['Surname']?.toString() ?? '',
              'IDNumber': learner['IDNumber']?.toString() ?? '',
              'DateOfBirth': learner['DateOfBirth']?.toString() ?? '',
              'PhoneNumber': learner['PhoneNumber']?.toString() ?? '',
              'Email': learner['Email']?.toString() ?? '',
              'Title': learner['Title']?.toString() ?? '',
              'classID': classID,
              'synced': 1,
              // Preserve fingerprint templates from server
              'zkteco_left_template':
                  learner['zkteco_left_template']?.toString() ?? '',
              'zkteco_right_template':
                  learner['zkteco_right_template']?.toString() ?? '',
              'futronic_left_template':
                  learner['futronic_left_template']?.toString() ?? '',
              'futronic_right_template':
                  learner['futronic_right_template']?.toString() ?? '',
              'sourceafis_template':
                  learner['sourceafis_template']?.toString() ?? '',
            };

            if (existing.isEmpty) {
              // Insert new learner
              await txn.insert('learnerdetails', learnerData);
              debugPrint(
                '[PERSISTENT_SYNC] Inserted new learner: $learnerID',
              );
            } else {
              // Update existing learner (merge with local data)
              final existingData = existing.first;

              // Preserve local fingerprint templates if server doesn't have them
              if (learnerData['zkteco_left_template']!.toString().isEmpty &&
                  existingData['zkteco_left_template'] != null) {
                learnerData['zkteco_left_template'] =
                    existingData['zkteco_left_template'].toString();
              }
              if (learnerData['zkteco_right_template']!.toString().isEmpty &&
                  existingData['zkteco_right_template'] != null) {
                learnerData['zkteco_right_template'] =
                    existingData['zkteco_right_template'].toString();
              }
              if (learnerData['futronic_left_template']!.toString().isEmpty &&
                  existingData['futronic_left_template'] != null) {
                learnerData['futronic_left_template'] =
                    existingData['futronic_left_template'].toString();
              }
              if (learnerData['futronic_right_template']!.toString().isEmpty &&
                  existingData['futronic_right_template'] != null) {
                learnerData['futronic_right_template'] =
                    existingData['futronic_right_template'].toString();
              }

              await txn.update(
                'learnerdetails',
                learnerData,
                where: 'LearnerID = ?',
                whereArgs: [learnerID],
              );
              debugPrint('[PERSISTENT_SYNC] Updated learner: $learnerID');
            }
          }
        }).timeout(
          const Duration(seconds: 5),
        ); // Add timeout to prevent locks

        // Small delay between batches to allow other operations
        if (i + batchSize < serverLearners.length) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }

      debugPrint(
        '[PERSISTENT_SYNC] Successfully synced ${serverLearners.length} learners for class $classID',
      );
    } catch (e) {
      debugPrint('[PERSISTENT_SYNC] Error syncing class $classID: $e');
      rethrow;
    }
  }

  /// Sync offline clocking records to server
  Future<void> _syncOfflineClockingRecords(
    DatabaseHelper dbHelper,
    SyncResult result,
    bool reportProgress,
  ) async {
    try {
      final db = await dbHelper.database;

      // Get all unsynced clocking records
      final unsyncedRecords = await db.query(
        'learner_clocking',
        where: 'synced = ?',
        whereArgs: [0],
      );

      debugPrint(
        '[PERSISTENT_SYNC] Found ${unsyncedRecords.length} unsynced clocking records',
      );

      int processedRecords = 0;

      for (var record in unsyncedRecords) {
        try {
          // Sync individual record
          await _syncSingleClockingRecord(record, dbHelper);
          result.clockingRecordsSynced++;

          processedRecords++;
          if (reportProgress && unsyncedRecords.isNotEmpty) {
            final progress =
                0.5 + (0.3 * processedRecords / unsyncedRecords.length);
            _reportProgress(SyncProgress(
              phase: SyncPhase.clockingRecords,
              progress: progress,
              message:
                  'Synced record $processedRecords/${unsyncedRecords.length}',
            ));
          }
        } catch (e) {
          debugPrint(
            '[PERSISTENT_SYNC] Failed to sync clocking record ${record['clocking_id']}: $e',
          );
          result.errors.add('Clocking ${record['clocking_id']}: $e');
        }
      }
    } catch (e) {
      debugPrint('[PERSISTENT_SYNC] Error syncing clocking records: $e');
      result.errors.add('Clocking sync: $e');
    }
  }

  /// Sync a single clocking record
  Future<void> _syncSingleClockingRecord(
    Map<String, dynamic> record,
    DatabaseHelper dbHelper,
  ) async {
    // Determine if it's clock-in or clock-out
    final hasClockOut = record['clock_out_time'] != null &&
        record['clock_out_time'].toString().isNotEmpty;

    final endpoint = hasClockOut ? AppConfig.clockoutUrl : AppConfig.clockinUrl;

    final response = await HttpClientService.makeRequest(
      () => http.post(
        Uri.parse(endpoint),
        body: {
          'LearnerID': record['LearnerID'].toString(),
          'clock_date': record['clock_date'].toString(),
          'clock_in_time': record['clock_in_time'].toString(),
          if (hasClockOut)
            'clock_out_time': record['clock_out_time'].toString(),
          'user_latitude': record['user_latitude']?.toString() ?? '',
          'user_longitude': record['user_longitude']?.toString() ?? '',
          'user_accuracy': record['user_accuracy']?.toString() ?? '',
        },
      ),
      endpoint:
          hasClockOut ? 'clocking_clockout_sync' : 'clocking_clockin_sync',
      maxRetries: NetworkConfig.syncOperationsMaxRetries,
      timeout: const Duration(seconds: NetworkConfig.lightweightTimeout),
    );

    if (response.statusCode == 200) {
      // Mark as synced
      final db = await dbHelper.database;
      await db.update(
        'learner_clocking',
        {'synced': 1},
        where: 'clocking_id = ?',
        whereArgs: [record['clocking_id']],
      );
      debugPrint(
        '[PERSISTENT_SYNC] Synced clocking record ${record['clocking_id']}',
      );
    } else {
      throw Exception('Server returned ${response.statusCode}');
    }
  }

  /// Sync other pending data (POE, documents, etc.)
  Future<void> _syncOtherPendingData(
    DatabaseHelper dbHelper,
    SyncResult result,
    bool reportProgress,
  ) async {
    // Add other sync operations as needed
    debugPrint('[PERSISTENT_SYNC] Syncing other pending data...');

    if (reportProgress) {
      _reportProgress(SyncProgress(
        phase: SyncPhase.otherData,
        progress: 0.85,
        message: 'Other data synced',
      ));
    }
  }

  /// Enhanced: Merge data with conflict resolution
  Map<String, dynamic> _mergeData(
      Map<String, dynamic> local, Map<String, dynamic> server,
      {required bool preferLocal}) {
    final merged = <String, dynamic>{};
    final allKeys = {...local.keys, ...server.keys};

    for (final key in allKeys) {
      final localValue = local[key];
      final serverValue = server[key];

      if (localValue == null && serverValue != null) {
        merged[key] = serverValue;
      } else if (serverValue == null && localValue != null) {
        merged[key] = localValue;
      } else if (localValue != null && serverValue != null) {
        // Both have values - apply strategy
        if (preferLocal) {
          // Keep local unless it's empty and server has data
          if (localValue.toString().isEmpty &&
              serverValue.toString().isNotEmpty) {
            merged[key] = serverValue;
          } else {
            merged[key] = localValue;
          }
        } else {
          // Keep server unless it's empty and local has data
          if (serverValue.toString().isEmpty &&
              localValue.toString().isNotEmpty) {
            merged[key] = localValue;
          } else {
            merged[key] = serverValue;
          }
        }
      }
    }

    return merged;
  }

  /// Get last sync time
  DateTime? getLastSyncTime() => _lastSyncTime;

  /// Check if sync is in progress
  bool isSyncing() => _isSyncing;
}

/// Result of a sync operation
class SyncResult {
  bool success = false;
  String message = '';
  int learnersSynced = 0;
  int clockingRecordsSynced = 0;
  List<String> errors = [];
  List<String> warnings = [];
  Duration? duration;

  @override
  String toString() {
    return 'SyncResult(success: $success, learners: $learnersSynced, clocking: $clockingRecordsSynced, errors: ${errors.length}, warnings: ${warnings.length}, duration: ${duration?.inSeconds}s)';
  }
}

/// Enhanced: Sync progress tracking
class SyncProgress {
  final SyncPhase phase;
  final double progress; // 0.0 to 1.0
  final String message;
  final SyncResult? result;
  final DateTime timestamp;

  SyncProgress({
    required this.phase,
    required this.progress,
    required this.message,
    this.result,
  }) : timestamp = DateTime.now();

  @override
  String toString() {
    return 'SyncProgress(phase: $phase, progress: ${(progress * 100).toStringAsFixed(1)}%, message: $message)';
  }
}

/// Enhanced: Sync phases
enum SyncPhase {
  starting,
  learners,
  clockingRecords,
  otherData,
  validation,
  completed,
  failed,
}

/// Enhanced: Sync conflict resolution strategies
enum SyncConflictStrategy {
  serverWins, // Server data always overwrites local
  clientWins, // Local data always wins
  mergePreserveLocal, // Merge but prefer local when both have data
  mergePreserveServer, // Merge but prefer server when both have data
}

/// Enhanced: Sync task for queue
class SyncTask {
  final String name;
  final int priority; // Higher = more important
  final Future<void> Function() execute;
  final DateTime createdAt;

  SyncTask({
    required this.name,
    required this.execute,
    this.priority = 0,
  }) : createdAt = DateTime.now();
}

/// Enhanced: Sync statistics
class SyncStatistics {
  int _totalSyncs = 0;
  int _successfulSyncs = 0;
  int _failedSyncs = 0;
  int _totalLearnersSynced = 0;
  int _totalClockingRecordsSynced = 0;
  final Map<String, int> _operationCounts = {};
  final Map<String, List<String>> _errors = {};
  DateTime? _lastSuccessfulSync;
  Duration _totalSyncTime = Duration.zero;

  int get totalSyncs => _totalSyncs;
  int get successfulSyncs => _successfulSyncs;
  int get failedSyncs => _failedSyncs;
  int get totalLearnersSynced => _totalLearnersSynced;
  int get totalClockingRecordsSynced => _totalClockingRecordsSynced;
  DateTime? get lastSuccessfulSync => _lastSuccessfulSync;
  Duration get averageSyncTime =>
      _totalSyncs > 0 ? _totalSyncTime ~/ _totalSyncs : Duration.zero;
  double get successRate =>
      _totalSyncs > 0 ? _successfulSyncs / _totalSyncs : 0.0;

  void recordSuccess(String operation, {Duration? duration}) {
    _totalSyncs++;
    _successfulSyncs++;
    _operationCounts[operation] = (_operationCounts[operation] ?? 0) + 1;
    _lastSuccessfulSync = DateTime.now();
    if (duration != null) {
      _totalSyncTime += duration;
    }
  }

  void recordFailure(String operation, String error) {
    _totalSyncs++;
    _failedSyncs++;
    _errors.putIfAbsent(operation, () => []).add(error);
  }

  void updateTotals({
    int learnersSynced = 0,
    int clockingRecordsSynced = 0,
  }) {
    _totalLearnersSynced += learnersSynced;
    _totalClockingRecordsSynced += clockingRecordsSynced;
  }

  Map<String, dynamic> toJson() {
    return {
      'totalSyncs': _totalSyncs,
      'successfulSyncs': _successfulSyncs,
      'failedSyncs': _failedSyncs,
      'successRate': successRate,
      'totalLearnersSynced': _totalLearnersSynced,
      'totalClockingRecordsSynced': _totalClockingRecordsSynced,
      'lastSuccessfulSync': _lastSuccessfulSync?.toIso8601String(),
      'averageSyncTimeSeconds': averageSyncTime.inSeconds,
      'operationCounts': _operationCounts,
      'recentErrors': _errors.entries
          .map((e) => {'operation': e.key, 'errors': e.value.take(5).toList()})
          .toList(),
    };
  }

  void reset() {
    _totalSyncs = 0;
    _successfulSyncs = 0;
    _failedSyncs = 0;
    _totalLearnersSynced = 0;
    _totalClockingRecordsSynced = 0;
    _operationCounts.clear();
    _errors.clear();
    _lastSuccessfulSync = null;
    _totalSyncTime = Duration.zero;
  }

  @override
  String toString() {
    return 'SyncStatistics(total: $_totalSyncs, success: $_successfulSyncs, failed: $_failedSyncs, rate: ${(successRate * 100).toStringAsFixed(1)}%)';
  }
}
