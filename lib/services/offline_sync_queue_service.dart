import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import '../config.dart';
import '../database_helper.dart';

/// Proper offline-first sync queue service
/// 
/// Key principles:
/// 1. Generate idempotency keys at TAP TIME and persist them
/// 2. Store complete payload with client timestamp  
/// 3. Replay in order when connectivity returns
/// 4. Never regenerate keys - always reuse stored ones
/// 5. Handle geofence/face verification at tap time, not sync time
class OfflineSyncQueueService {
  static const String _tableName = 'pending_actions';
  late Database _db;
  bool _syncing = false;
  Timer? _syncTimer;
  StreamSubscription? _connectivitySubscription;
  
  // Singleton
  static final OfflineSyncQueueService _instance = OfflineSyncQueueService._internal();
  factory OfflineSyncQueueService() => _instance;
  OfflineSyncQueueService._internal();

  /// Structured logging helper - writes JSON formatted logs
  /// NEVER logs PII, credentials, or sensitive data
  void _log(String level, String event, Map<String, dynamic> data) async {
    try {
      final timestamp = DateTime.now().toUtc().toIso8601String();
      final logEntry = {
        'timestamp': timestamp,
        'level': level,
        'event': event,
        'service': 'offline_sync_queue',
        'data': data,
      };
      
      final logLine = jsonEncode(logEntry);
      
      // Write to debug output (development only)
      debugPrint(logLine);
      
      // Write to log file
      try {
        final appDocDir = await getApplicationDocumentsDirectory();
        final logsDir = Directory('${appDocDir.path}/logs');
        if (!await logsDir.exists()) {
          await logsDir.create(recursive: true);
        }
        
        final now = DateTime.now();
        final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
        final logFile = File('${logsDir.path}/sync_$dateStr.log');
        
        await logFile.writeAsString('$logLine\n', mode: FileMode.append);
        
        // Rotate logs: keep last 7 days
        await _rotateLogs(logsDir);
      } catch (e) {
        // If file logging fails, at least we have debugPrint
        debugPrint('[LOG_ERROR] Failed to write log file: $e');
      }
    } catch (e) {
      // Logging should never crash the app
      debugPrint('[LOG_ERROR] Logging failed: $e');
    }
  }

  /// Rotate log files - keep last 7 days only
  Future<void> _rotateLogs(Directory logsDir) async {
    try {
      final files = logsDir.listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.log'))
        .toList();
      
      if (files.isEmpty) return;
      
      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      
      // Delete files older than 7 days
      for (final file in files.skip(7)) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('[LOG_ERROR] Log rotation failed: $e');
    }
  }

  /// Initialize the service - call once at app startup
  Future<void> initialize() async {
    await _initDatabase();
    _startConnectivityListener();
    _startPeriodicSync();
    
    // Process any pending items immediately
    await syncQueue();
  }

  Future<void> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = '$databasesPath/offline_sync_queue.db';
    
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableName (
            id TEXT PRIMARY KEY,              -- The idempotency key (UUID v4)
            action TEXT NOT NULL,             -- Action type (clock_in, clock_out, etc.)
            payload TEXT NOT NULL,            -- Complete JSON payload
            client_ts TEXT NOT NULL,          -- ISO 8601 timestamp when action happened
            status TEXT NOT NULL DEFAULT 'pending',  -- pending, synced, failed
            attempts INTEGER NOT NULL DEFAULT 0,
            last_error TEXT,
            created_at TEXT NOT NULL,
            UNIQUE(id)
          )
        ''');
        
        await db.execute('''
          CREATE INDEX idx_status_client_ts ON $_tableName (status, client_ts)
        ''');
      },
    );
  }

  /// Enqueue an action for sync - call this at TAP TIME
  /// 
  /// This is the critical method that must be called immediately when user
  /// performs an action (clock in, upload evidence, etc.)
  Future<String> enqueueAction(
    String action, 
    Map<String, dynamic> payload, {
    Map<String, dynamic>? evidence, // Geofence data, face images, etc.
  }) async {
    final key = const Uuid().v4(); // Generated ONCE at tap time
    final clientTimestamp = DateTime.now().toUtc().toIso8601String();
    
    // Include evidence data in payload if provided
    final fullPayload = {
      ...payload,
      if (evidence != null) 'evidence': evidence,
    };
    
    await _db.insert(_tableName, {
      'id': key,
      'action': action,
      'payload': jsonEncode(fullPayload),
      'client_ts': clientTimestamp,
      'status': 'pending',
      'attempts': 0,
      'created_at': clientTimestamp,
    });
    
    _log('info', 'queue_add', {
      'action': action,
      'idempotency_key': key.substring(0, 8),
      'client_timestamp': clientTimestamp,
      'has_evidence': evidence != null,
    });
    
    // Try to sync immediately if online
    unawaited(syncQueue());
    
    return key;
  }

  /// HYBRID: Queue action for offline processing OR process immediately if online
  /// 
  /// This hybrid approach:
  /// 1. If online: tries immediate processing with idempotency protection
  /// 2. If offline: queues for later sync with tap-time generated keys
  /// 3. Always uses same idempotency key for consistency
  Future<Map<String, dynamic>> queueOrProcessAction(
    String action, 
    Map<String, dynamic> payload, {
    Map<String, dynamic>? evidence,
    bool forceOffline = false, // For testing offline behavior
  }) async {
    
    // Generate idempotency key at TAP TIME (crucial for proper deduplication)
    final key = const Uuid().v4();
    final clientTimestamp = DateTime.now().toUtc().toIso8601String();
    
    // Include evidence data in payload if provided
    final fullPayload = {
      ...payload,
      'idempotency_key': key,
      'client_timestamp': clientTimestamp,
      if (evidence != null) 'evidence': evidence,
    };
    
    // Check connectivity unless forced offline
    final hasConnectivity = !forceOffline && await _hasConnectivity();
    
    if (hasConnectivity) {
      _log('info', 'hybrid_sync_attempt', {
        'action': action,
        'idempotency_key': key.substring(0, 8),
        'mode': 'online',
      });
      
      try {
        // Attempt immediate online processing
        final result = await _processActionOnline(action, fullPayload, key);
        
        _log('info', 'hybrid_sync_success', {
          'action': action,
          'idempotency_key': key.substring(0, 8),
          'processed_immediately': true,
        });
        
        return {
          'success': true,
          'processed_immediately': true,
          'idempotency_key': key,
          'result': result,
        };
        
      } catch (e) {
        _log('warning', 'hybrid_sync_fallback', {
          'action': action,
          'idempotency_key': key.substring(0, 8),
          'error_type': e.runtimeType.toString(),
        });
        
        // Fall back to offline queuing if online processing fails
        // This handles server errors, timeouts, auth issues, etc.
      }
    }
    
    // Queue for offline processing (either no connectivity or online processing failed)
    _log('info', 'queue_add', {
      'action': action,
      'idempotency_key': key.substring(0, 8),
      'mode': hasConnectivity ? 'online_fallback' : 'offline',
    });
    
    await _db.insert(_tableName, {
      'id': key,
      'action': action,
      'payload': jsonEncode(fullPayload),
      'client_ts': clientTimestamp,
      'status': 'pending',
      'attempts': 0,
      'created_at': clientTimestamp,
    });

    // Trigger immediate sync attempt if we have connectivity
    if (hasConnectivity) {
      unawaited(syncQueue());
    }
    
    return {
      'success': true,
      'processed_immediately': false,
      'queued': true,
      'idempotency_key': key,
      'message': hasConnectivity 
        ? 'Online processing failed, queued for retry'
        : 'No connectivity, queued for sync when online',
    };
  }

  /// Process action immediately when online
  Future<Map<String, dynamic>> _processActionOnline(
    String action, 
    Map<String, dynamic> payload, 
    String idempotencyKey
  ) async {
    
    final token = await _getAuthToken();
    final url = _getEndpointUrl(action);
    
    _log('info', 'http_request', {
      'action': action,
      'endpoint': url,
      'idempotency_key': idempotencyKey.substring(0, 8),
    });
    
    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token', // Actual token for request
        'X-Idempotency-Key': idempotencyKey,
      },
      body: jsonEncode(payload),
    ).timeout(const Duration(seconds: 90)); // Increased for 2G connectivity - see IMAGE_UPLOAD_AUDIT.md
    
    _log('info', 'http_response', {
      'action': action,
      'idempotency_key': idempotencyKey.substring(0, 8),
      'http_status': response.statusCode,
    });
    
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final result = jsonDecode(response.body);
      return result;
    } else {
      throw HttpException(
        'Server returned ${response.statusCode}',
        uri: Uri.parse(url),
      );
    }
  }

  /// Get endpoint URL based on action type
  String _getEndpointUrl(String action) {
    switch (action) {
      case 'clock_in':
      case 'clock_out':
        return '${AppConfig.baseUrl}/save_consolidated_clocking.php';
      case 'upload_evidence':
        return '${AppConfig.baseUrl}/upload_clocking_evidence_images.php';
      case 'save_poe':
        return '${AppConfig.baseUrl}/poe.php';
      default:
        return '${AppConfig.baseUrl}/save_consolidated_clocking.php';
    }
  }

  /// BATCH: Always queue for batch processing regardless of connectivity
  /// 
  /// This approach ALWAYS batches for maximum efficiency:
  /// 1. Online: Still batches, then sends consolidated request
  /// 2. Offline: Batches and queues for later sync
  /// 3. Benefits: Reduced server load, better UX, consistent behavior
  Future<Map<String, dynamic>> queueForBatchProcessing(
    String classID,
    List<Map<String, dynamic>> learnerClockings, {
    bool forceBatchEvenOnline = true, // Always batch by default
  }) async {
    // Enforce maximum batch size for rural connectivity
    const int MAX_BATCH_SIZE = 15; // ~2.9 MB payload, manageable on 2G
    if (learnerClockings.length > MAX_BATCH_SIZE) {
      return {
        'success': false,
        'error': 'Batch size exceeds maximum of $MAX_BATCH_SIZE learners. '
                 'Current batch: ${learnerClockings.length} learners. '
                 'Please submit this batch before adding more learners.',
        'batch_size': learnerClockings.length,
        'max_batch_size': MAX_BATCH_SIZE,
      };
    }
    
    // Generate batch idempotency key at TAP TIME
    final batchKey = const Uuid().v4();
    final clientTimestamp = DateTime.now().toUtc().toIso8601String();
    
    // Prepare batch payload
    final batchPayload = {
      'batch_id': batchKey,
      'class_id': classID,
      'batch_type': 'class_clocking',
      'learner_clockings': learnerClockings,
      'total_learners': learnerClockings.length,
      'client_timestamp': clientTimestamp,
    };
    
    // Check connectivity for processing strategy
    final hasConnectivity = await _hasConnectivity();
    
    _log('info', 'batch_queue_add', {
      'class_id': classID,
      'batch_id': batchKey.substring(0, 8),
      'total_learners': learnerClockings.length,
      'has_connectivity': hasConnectivity,
    });
    
    // ALWAYS queue first for consistency and local persistence
    await _db.insert(_tableName, {
      'id': batchKey,
      'action': 'class_batch_clocking',
      'payload': jsonEncode(batchPayload),
      'client_ts': clientTimestamp,
      'status': 'pending',
      'attempts': 0,
      'created_at': clientTimestamp,
    });

    // Store individual learner records for local viewing
    for (final clocking in learnerClockings) {
      final learnerKey = const Uuid().v4();
      await _db.insert(_tableName, {
        'id': learnerKey,
        'action': 'learner_clocking_local',
        'payload': jsonEncode({
          ...clocking,
          'batch_id': batchKey,
          'local_only': true, // Won't be synced individually
        }),
        'client_ts': clientTimestamp,
        'status': 'batched', // Special status for batch members
        'attempts': 0,
        'created_at': clientTimestamp,
      });
    }
    
    if (hasConnectivity && forceBatchEvenOnline) {
      // Even online, we batch for efficiency
      _log('info', 'batch_sync_attempt', {
        'batch_id': batchKey.substring(0, 8),
        'mode': 'online',
      });
      
      try {
        // Process batch immediately while online
        final result = await _processBatchOnline('class_batch_clocking', batchPayload, batchKey);
        
        // Mark batch as completed in local queue
        await _db.update(
          _tableName,
          {'status': 'synced', 'attempts': 1},
          where: 'id = ?',
          whereArgs: [batchKey],
        );
        
        _log('info', 'batch_sync_success', {
          'batch_id': batchKey.substring(0, 8),
          'learners_processed': learnerClockings.length,
        });
        
        return {
          'success': true,
          'processed_immediately': true,
          'batch_id': batchKey,
          'learners_processed': learnerClockings.length,
          'mode': 'online_batch',
          'result': result,
        };
        
      } catch (e) {
        _log('warning', 'batch_sync_failed', {
          'batch_id': batchKey.substring(0, 8),
          'error_type': e.runtimeType.toString(),
          'mode': 'online_retry_scheduled',
        });
        
        // Keep batch in queue for retry
        return {
          'success': true,
          'processed_immediately': false,
          'queued': true,
          'batch_id': batchKey,
          'learners_queued': learnerClockings.length,
          'mode': 'online_batch_failed',
          'message': 'Online batch failed, queued for retry when connection improves',
        };
      }
    }
    
    // Offline or batch-only mode
    _log('info', 'batch_queued', {
      'batch_id': batchKey.substring(0, 8),
      'learners_queued': learnerClockings.length,
      'mode': hasConnectivity ? 'online_queued' : 'offline_queued',
    });
    
    // Trigger sync attempt if we have connectivity (will process when conditions are right)
    if (hasConnectivity) {
      unawaited(syncQueue());
    }
    
    return {
      'success': true,
      'processed_immediately': false,
      'queued': true,
      'batch_id': batchKey,
      'learners_queued': learnerClockings.length,
      'mode': hasConnectivity ? 'online_queued' : 'offline_queued',
      'message': hasConnectivity 
        ? 'Batch queued for immediate processing'
        : 'Batch queued for sync when connectivity returns',
    };
  }

  /// Process batch immediately when online
  Future<Map<String, dynamic>> _processBatchOnline(
    String action,
    Map<String, dynamic> batchPayload,
    String batchKey
  ) async {
    
    final token = await _getAuthToken();
    final url = _getBatchEndpointUrl(action);
    
    _log('info', 'batch_http_request', {
      'action': action,
      'batch_id': batchKey.substring(0, 8),
      'batch_size': batchPayload['total_learners'],
      'endpoint': url,
    });
    
    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
        'X-Batch-Idempotency-Key': batchKey,
        'X-Batch-Size': batchPayload['total_learners'].toString(),
      },
      body: jsonEncode(batchPayload),
    ).timeout(const Duration(seconds: 180)); // Increased for 2G connectivity - see IMAGE_UPLOAD_AUDIT.md
    
    _log('info', 'batch_http_response', {
      'batch_id': batchKey.substring(0, 8),
      'http_status': response.statusCode,
    });
    
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final result = jsonDecode(response.body);
      return result;
    } else {
      throw HttpException(
        'Batch server returned ${response.statusCode}',
        uri: Uri.parse(url),
      );
    }
  }

  /// Get batch endpoint URL based on action type
  String _getBatchEndpointUrl(String action) {
    switch (action) {
      case 'class_batch_clocking':
        return '${AppConfig.baseUrl}/save_class_batch_clocking.php';
      case 'class_batch_evidence':
        return '${AppConfig.baseUrl}/upload_class_batch_evidence.php';
      default:
        return '${AppConfig.baseUrl}/save_consolidated_clocking.php';
    }
  }

  /// Get batched learner records for local viewing
  Future<List<Map<String, dynamic>>> getBatchedLearners(String batchId) async {
    return await _db.query(
      _tableName,
      where: 'JSON_EXTRACT(payload, "\$.batch_id") = ? AND status = ?',
      whereArgs: [batchId, 'batched'],
      orderBy: 'client_ts ASC',
    );
  }

  /// Get pending batch operations
  Future<List<Map<String, dynamic>>> getPendingBatches() async {
    return await _db.query(
      _tableName,
      where: 'action LIKE "%batch%" AND status = ?',
      whereArgs: ['pending'],
      orderBy: 'client_ts ASC',
    );
  }

  /// Check connectivity
  Future<bool> _hasConnectivity() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return !result.contains(ConnectivityResult.none);
    } catch (e) {
      _log('error', 'connectivity_check_failed', {
        'error_type': e.runtimeType.toString(),
      });
      return false;
    }
  }
  
  /// Check if an action is already queued for this user
  /// Use this to prevent double-tapping
  Future<bool> isActionPending(String action, int userId) async {
    final result = await _db.query(
      _tableName,
      where: 'action = ? AND status = ? AND JSON_EXTRACT(payload, "\$.user_id") = ?',
      whereArgs: [action, 'pending', userId.toString()],
      limit: 1,
    );
    return result.isNotEmpty;
  }
  
  /// Get pending actions count for UI display
  Future<int> getPendingCount() async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) as count FROM $_tableName WHERE status = ?',
      ['pending']
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }
  
  /// Get failed actions for admin review
  Future<List<Map<String, dynamic>>> getFailedActions() async {
    return await _db.query(
      _tableName,
      where: 'status = ?',
      whereArgs: ['failed'],
      orderBy: 'client_ts ASC',
    );
  }

  /// Main sync method - processes queue in order
  Future<void> syncQueue() async {
    if (_syncing) return;
    _syncing = true;
    
    try {
      // Get pending items in chronological order - CRITICAL for ordering
      final rows = await _db.query(
        _tableName,
        where: 'status = ?',
        whereArgs: ['pending'],
        orderBy: 'client_ts ASC', // Clock-out must come after clock-in
      );
      
      if (rows.isEmpty) {
        _log('debug', 'sync_queue_empty', {});
        return;
      }
      
      final queueDepth = rows.length;
      _log('info', 'sync_start', {
        'queue_depth': queueDepth,
      });
      
      for (final row in rows) {
        try {
          final success = await _syncSingleAction(row);
          if (!success) {
            // Stop on first failure to maintain order
            _log('warning', 'sync_stopped', {
              'reason': 'first_failure_encountered',
              'remaining_items': rows.length - rows.indexOf(row) - 1,
            });
            break;
          }
        } catch (e) {
          _log('error', 'sync_action_error', {
            'idempotency_key': (row['id'] as String).substring(0, 8),
            'error_type': e.runtimeType.toString(),
          });
          // Stop on error to maintain order
          break;
        }
      }
    } finally {
      _syncing = false;
    }
  }
  
  Future<bool> _syncSingleAction(Map<String, dynamic> row) async {
    final key = row['id'] as String;
    final action = row['action'] as String;
    final payloadJson = row['payload'] as String;
    final clientTimestamp = row['client_ts'] as String;
    final attempts = row['attempts'] as int;
    
    try {
      final payload = jsonDecode(payloadJson) as Map<String, dynamic>;
      
      // Add client timestamp to payload
      final requestBody = {
        ...payload,
        'client_timestamp': clientTimestamp,
      };
      
      _log('info', 'queue_dispatch', {
        'action': action,
        'idempotency_key': key.substring(0, 8),
        'retry_count': attempts,
        'client_timestamp': clientTimestamp,
      });
      
      final response = await http.post(
        Uri.parse(_getEndpointUrl(action)),
        headers: {
          'Idempotency-Key': key, // SAME KEY on every retry
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await _getAuthToken()}',
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 30));
      
      await _updateAttempts(key);
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        // Success - remove from queue
        await _markAsSynced(key);
        _log('info', 'queue_success', {
          'action': action,
          'idempotency_key': key.substring(0, 8),
          'http_status': response.statusCode,
          'retry_count': attempts,
        });
        return true;
        
      } else if (response.statusCode == 409) {
        // Still processing on server - retry later
        _log('warning', 'queue_retry', {
          'action': action,
          'idempotency_key': key.substring(0, 8),
          'reason': 'server_still_processing',
          'http_status': 409,
        });
        return false;
        
      } else if (response.statusCode >= 500) {
        // Server error - retry later
        _log('warning', 'queue_retry', {
          'action': action,
          'idempotency_key': key.substring(0, 8),
          'reason': 'server_error',
          'http_status': response.statusCode,
        });
        return false;
        
      } else {
        // 4xx error - validation failure, don't retry forever
        await _markAsFailed(key, 'HTTP ${response.statusCode}');
        _log('error', 'queue_failed', {
          'action': action,
          'idempotency_key': key.substring(0, 8),
          'reason': 'validation_error',
          'http_status': response.statusCode,
        });
        return true; // Continue with next item
      }
      
    } on SocketException {
      _log('warning', 'queue_retry', {
        'action': action,
        'idempotency_key': key.substring(0, 8),
        'reason': 'network_error',
        'error_type': 'SocketException',
      });
      return false; // Stop processing, retry later
      
    } on TimeoutException {
      _log('warning', 'queue_retry', {
        'action': action,
        'idempotency_key': key.substring(0, 8),
        'reason': 'timeout',
        'error_type': 'TimeoutException',
        'timeout_ms': 30000,
      });
      return false; // Stop processing, retry later
      
    } catch (e) {
      await _markAsFailed(key, e.runtimeType.toString());
      _log('error', 'queue_failed', {
        'action': action,
        'idempotency_key': key.substring(0, 8),
        'reason': 'unexpected_error',
        'error_type': e.runtimeType.toString(),
      });
      return true; // Continue with next item
    }
  }
  
  Future<void> _updateAttempts(String key) async {
    await _db.rawUpdate(
      'UPDATE $_tableName SET attempts = attempts + 1 WHERE id = ?',
      [key]
    );
  }
  
  Future<void> _markAsSynced(String key) async {
    await _db.update(
      _tableName,
      {'status': 'synced'},
      where: 'id = ?',
      whereArgs: [key],
    );
    
    // Clean up old synced records (keep last 100 for debugging)
    await _db.rawDelete('''
      DELETE FROM $_tableName 
      WHERE status = 'synced' 
      AND id NOT IN (
        SELECT id FROM (
          SELECT id FROM $_tableName 
          WHERE status = 'synced' 
          ORDER BY created_at DESC 
          LIMIT 100
        ) t
      )
    ''');
  }
  
  Future<void> _markAsFailed(String key, String error) async {
    await _db.update(
      _tableName,
      {'status': 'failed', 'last_error': error},
      where: 'id = ?',
      whereArgs: [key],
    );
  }
  

  
  Future<String> _getAuthToken() async {
    // Get auth token from shared preferences or secure storage
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    
    if (token != null && token.isNotEmpty) {
      return token;
    }
    
    // Fallback: try to get from database helper if available
    try {
      final dbHelper = DatabaseHelper();
      final facilitator = await dbHelper.getFacilitator('', '');
      if (facilitator != null && facilitator['token'] != null) {
        return facilitator['token'];
      }
    } catch (e) {
      _log('error', 'auth_token_retrieval_failed', {
        'error_type': e.runtimeType.toString(),
      });
    }
    
    throw Exception('No authentication token available');
  }
  
  void _startConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((result) {
      bool isOnline = !result.contains(ConnectivityResult.none);
      
      _log('info', 'connectivity_change', {
        'current_state': result.toString(),
        'status': isOnline ? 'online' : 'offline',
      });
      
      if (isOnline) {
        unawaited(syncQueue());
      }
    });
  }
  
  void _startPeriodicSync() {
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      unawaited(syncQueue());
    });
  }
  
  /// Clean up resources
  void dispose() {
    _syncTimer?.cancel();
    _connectivitySubscription?.cancel();
    _db.close();
  }
  
  /// Clear all failed actions (admin function)
  Future<void> clearFailedActions() async {
    await _db.delete(_tableName, where: 'status = ?', whereArgs: ['failed']);
  }
  
  /// Retry a specific failed action
  Future<void> retryFailedAction(String key) async {
    await _db.update(
      _tableName,
      {'status': 'pending', 'attempts': 0, 'last_error': null},
      where: 'id = ? AND status = ?',
      whereArgs: [key, 'failed'],
    );
    
    unawaited(syncQueue());
  }
}

// Helper to suppress unawaited_futures warnings
void unawaited(Future<void> future) {
  future.then((_) {}, onError: (_) {});
}