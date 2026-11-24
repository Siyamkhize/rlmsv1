# Sync Coordination Audit Report

**Generated:** 2025-01-XX  
**Auditor:** Kiro AI Coding Agent  
**Priority:** HIGH - Production Reliability & Data Integrity  
**Context:** Rural connectivity, offline-first architecture, intermittent network conditions

---

## Executive Summary

This audit identifies **CRITICAL coordination issues** between multiple sync services that could cause:
- **Race conditions** leading to duplicate database writes
- **Excessive retry loops** generating 2-4x server load
- **Uncoordinated batch operations** potentially blocking individual sync operations
- **Missing locks** allowing simultaneous sync operations to corrupt state
- **Partial evidence uploads** when connectivity drops mid-operation

**SEVERITY ASSESSMENT:**
- **HIGH**: Race conditions in persistent_sync_service (lines 96-145)
- **HIGH**: Duplicate retry logic across two services
- **MEDIUM**: Batch mode and individual mode can overlap in signature_geofence_clock_in_page
- **MEDIUM**: Missing coordination between offline queue and evidence sync
- **LOW**: Insufficient timeout protection in sync_service

---

## 1. Service Responsibility Matrix

| Service | Primary Responsibility | Tables Owned | Entry Points | Coordination Mechanism |
|---------|----------------------|--------------|--------------|----------------------|
| **offline_sync_queue_service.dart** | Offline queue management, idempotency keys, batch operations | `pending_actions` (SQLite) | `enqueueAction()`, `queueOrProcessAction()`, `queueForBatchProcessing()` | ❌ **NONE** - Uses internal `_syncing` flag only |
| **persistent_sync_service.dart** | Background sync, connectivity monitoring, learner data sync | `learnerdetails`, `learner_clocking`, `facilitator` | `syncAllData()`, `_triggerBackgroundSync()` | ⚠️ **PARTIAL** - Uses `DatabaseCoordinator` but `_isSyncing` flag NEVER SET |
| **manual_clocking_evidence_sync_service.dart** | Evidence (images/signatures) sync, base64 storage | `manual_clocking_evidence` | `saveEvidenceOffline()`, `syncToServer()`, `autoSyncIfOnline()` | ❌ **NONE** - Uses concurrency counter but no global lock |
| **sync_service.dart** | Main sync orchestrator, full table synchronization | All tables (users, sites, class, etc.) | `syncData()`, `syncSingleClockIn()`, `syncSingleClockOut()` | ❌ **NONE** - No coordination with other services |
| **signature_geofence_clock_in_page.dart** | UI clocking flow, evidence capture, batch collection | None (calls services) | `_handleClockIn()`, `_handleClockOut()`, `_submitBatch()` | ⚠️ **PARTIAL** - Local `_isClockingIn` map per learner |

**KEY FINDING:** NO GLOBAL COORDINATOR exists. Each service operates independently with its own locks/flags.

---

## 2. Race Condition Analysis

### 🔴 HIGH SEVERITY: persistent_sync_service.dart - Unclosed Race Window

**File:** `c:/projects/rlmss/lib/services/persistent_sync_service.dart`

**Issue:** Lines 96-145 in `syncAllData()` check `_isSyncing` flag at line 44 but **NEVER SET IT TO TRUE**, allowing multiple concurrent syncs.

**Code Analysis:**
```dart
// Line 44-52: Check flag but never set it
Future<void> _triggerBackgroundSync() async {
  // Check if enough time has passed since last sync
  if (!_coordinator.shouldAllowSync(
      minInterval: const Duration(minutes: 2))) {
    print('[PERSISTENT_SYNC] Skipping sync - too soon since last sync');
    return;
  }
  // ... calls executeSyncOperation but _isSyncing never updated

// Line 96-145: syncAllData() never sets _isSyncing = true
Future<SyncResult> syncAllData() async {
  print('[PERSISTENT_SYNC] Starting full data sync');
  // NO: _isSyncing = true;  <-- MISSING
  
  final result = SyncResult();
  try {
    // ... performs sync operations
  } catch (e) {
    // ... error handling
  }
  // NO: finally { _isSyncing = false; }  <-- MISSING
  return result;
}
```

**Race Condition Scenario:**
1. User triggers manual sync → calls `syncAllData()`
2. Connectivity restored event fires → calls `_triggerBackgroundSync()`
3. Periodic timer (30 min) fires → calls `_triggerBackgroundSync()`
4. **ALL THREE** proceed simultaneously because `_isSyncing` is never true
5. Three concurrent database transactions on `learnerdetails` table
6. Potential deadlock or data corruption

**Evidence:**
- `_isSyncing` declared at line 18 as `bool _isSyncing = false;`
- Never set to `true` in entire file
- `DatabaseCoordinator.executeSyncOperation()` has internal lock but returns immediately if locked, doesn't queue
- Line 82-91 in `_triggerBackgroundSync()` wraps call but doesn't update `_isSyncing`

**Recommended Fix:**
```dart
Future<SyncResult> syncAllData() async {
  if (_isSyncing) {
    return SyncResult()
      ..success = false
      ..message = 'Sync already in progress';
  }
  
  _isSyncing = true;  // SET IMMEDIATELY
  print('[PERSISTENT_SYNC] Starting full data sync');
  
  try {
    // ... existing sync logic
  } finally {
    _isSyncing = false;  // ALWAYS CLEAR IN FINALLY
  }
}
```

---

### 🔴 HIGH SEVERITY: Duplicate Retry Logic Across Two Services

**Files:**
- `c:/projects/rlmss/lib/services/offline_sync_queue_service.dart` (lines 216-230)
- `c:/projects/rlmss/lib/services/manual_clocking_evidence_sync_service.dart` (lines 108-165)

**Issue:** Both services implement exponential backoff retry logic. If evidence sync fails, **BOTH** services retry the same request.

**Code Analysis:**

**offline_sync_queue_service.dart:**
```dart
// Lines 427-480: _syncSingleAction with retry logic
Future<bool> _syncSingleAction(Map<String, dynamic> row) async {
  // ... attempts sync with timeout
  // ... exponential backoff on failure
  // ... retries up to maxRetries times
}
```

**manual_clocking_evidence_sync_service.dart:**
```dart
// Lines 108-165: _makeRequestWithRetry
Future<http.Response> _makeRequestWithRetry(
  Future<http.Response> Function() requestFunction, {
  int maxRetries = 5,  // <-- UP TO 5 RETRIES
  int baseDelaySeconds = 2,
  int maxDelaySeconds = 64,
  required String endpoint,
}) async {
  int attempt = 0;
  Duration delay = Duration(seconds: baseDelaySeconds);
  
  while (true) {  // <-- INFINITE LOOP until maxRetries
    try {
      final response = await requestFunction()
          .timeout(const Duration(seconds: 30));
      // ... retry logic with exponential backoff
    } catch (e) {
      if (attempt >= maxRetries) {
        rethrow;
      }
      // ... exponential delay: 2s → 4s → 8s → 16s → 32s → 64s
    }
  }
}
```

**Duplication Scenario:**
1. `signature_geofence_clock_in_page.dart` calls `ManualClockingEvidenceSyncService.saveEvidenceOffline()`
2. Evidence saved locally, then `syncToServer()` called
3. `syncToServer()` calls `_makeRequestWithRetry()` → **5 retries** with exponential backoff
4. If all 5 retries fail, evidence marked as unsynced
5. Later, `OfflineSyncQueueService.syncQueue()` processes same evidence
6. Calls `_syncSingleAction()` which has **its own retry logic**
7. **Result:** Same failed request attempted 10-25 times total (5 + 5 to 25 depending on overlap)

**Server Impact:**
- Rural connection drops: 10-25 retry attempts per learner
- 30-learner class: 300-750 retry requests for single failed evidence upload
- Exponential backoff overlaps: server sees burst after 2s, 4s, 8s, then another burst from second service

**Recommended Fix:**
1. **Consolidate retry logic** into `offline_sync_queue_service.dart` ONLY
2. Make `manual_clocking_evidence_sync_service.dart` **single-attempt only**
3. On failure, enqueue to offline queue: `OfflineSyncQueueService().enqueueAction('sync_evidence', payload)`
4. Remove `_makeRequestWithRetry()` entirely from evidence service

---

### ⚠️ MEDIUM SEVERITY: Batch Mode and Individual Mode Overlap

**File:** `c:/projects/rlmss/lib/signature_geofence_clock_in_page.dart`

**Issue:** Lines 849-900 (`_handleClockIn`) and lines 1055-1127 (`_submitBatch`) can execute simultaneously if user rapidly taps buttons.

**Code Analysis:**
```dart
// Line 849-900: _handleClockIn checks per-learner flag only
Future<void> _handleClockIn(String learnerID) async {
  if (_isClockingIn[learnerID] == true) return;  // Per-learner lock
  
  setState(() => _isClockingIn[learnerID] = true);
  
  try {
    // ... clock-in logic
    if (_batchMode) {
      await _storeLearnerClockingData(learnerID, 'in');  // Store in map
    } else {
      // INDIVIDUAL MODE - immediate API call
      if (_isOnline) {
        await _clockInOnline(learnerID, '');  // <-- API CALL
      }
    }
  } finally {
    setState(() => _isClockingIn[learnerID] = false);
  }
}

// Line 1055-1127: _submitBatch has separate flag
Future<void> _submitBatch() async {
  if (_batchClockings.isEmpty) return;
  
  setState(() => _isSubmittingBatch = true);  // Global batch flag
  
  try {
    final syncService = OfflineSyncQueueService();
    final result = await syncService.queueForBatchProcessing(
      widget.classID,
      learnerClockings,
    );
    // ... handle result
  } finally {
    setState(() => _isSubmittingBatch = false);
  }
}
```

**Race Condition Scenario:**
1. User switches to batch mode, collects 10 learners
2. User taps "Submit Batch" → `_submitBatch()` starts API call
3. While batch submitting, user switches to individual mode
4. User taps clock-in for 11th learner → `_handleClockIn()` makes **separate** API call
5. **Both requests** hit server simultaneously:
   - Batch request: 10 learners via `save_class_batch_clocking.php`
   - Individual request: 1 learner via `save_manual_clockin.php`
6. If batch request is slow (rural 2G), individual request might complete first
7. Idempotency keys protect against duplicates BUT unnecessary server load

**Current Protection:**
- Per-learner `_isClockingIn[learnerID]` map prevents duplicate taps on same learner
- Batch `_isSubmittingBatch` flag prevents duplicate batch submissions
- **MISSING:** Global lock preventing batch submit during individual clocking

**Recommended Fix:**
```dart
bool _isAnyOperationInProgress = false;  // Global operation lock

Future<void> _handleClockIn(String learnerID) async {
  if (_isClockingIn[learnerID] == true || _isAnyOperationInProgress) return;
  
  setState(() {
    _isClockingIn[learnerID] = true;
    if (!_batchMode) _isAnyOperationInProgress = true;
  });
  
  try {
    // ... existing logic
  } finally {
    setState(() {
      _isClockingIn[learnerID] = false;
      _isAnyOperationInProgress = false;
    });
  }
}

Future<void> _submitBatch() async {
  if (_batchClockings.isEmpty || _isAnyOperationInProgress) return;
  
  setState(() {
    _isSubmittingBatch = true;
    _isAnyOperationInProgress = true;
  });
  
  try {
    // ... existing logic
  } finally {
    setState(() {
      _isSubmittingBatch = false;
      _isAnyOperationInProgress = false;
    });
  }
}
```

---

### ⚠️ MEDIUM SEVERITY: Evidence Sync and Queue Sync Uncoordinated

**Files:**
- `c:/projects/rlmss/lib/services/manual_clocking_evidence_sync_service.dart`
- `c:/projects/rlmss/lib/services/offline_sync_queue_service.dart`

**Issue:** Evidence sync service has its own concurrency control (lines 23-64 `_executeConcurrencyControlled`) but doesn't coordinate with offline queue service.

**Code Analysis:**

**manual_clocking_evidence_sync_service.dart:**
```dart
// Lines 23-28: Concurrency control variables
static const int MAX_CONCURRENT_SYNCS = 3;
static int _activeSyncs = 0;
static final List<Function()> _syncQueue = [];

// Lines 30-64: Concurrency control wrapper
Future<T> _executeConcurrencyControlled<T>(Future<T> Function() operation) async {
  if (_activeSyncs >= MAX_CONCURRENT_SYNCS) {
    // Queue operation
    _syncQueue.add(() async { ... });
    return completer.future;
  }
  
  _activeSyncs++;
  try {
    final result = await operation();
    return result;
  } finally {
    _activeSyncs--;
    // Process next queued operation
    if (_syncQueue.isNotEmpty && _activeSyncs < MAX_CONCURRENT_SYNCS) {
      final nextOperation = _syncQueue.removeAt(0);
      Future.microtask(nextOperation);
    }
  }
}
```

**offline_sync_queue_service.dart:**
```dart
// Lines 388-395: Single sync lock
bool _syncing = false;

Future<void> syncQueue() async {
  if (_syncing) return;  // Single lock
  _syncing = true;
  
  try {
    // ... process queue
  } finally {
    _syncing = false;
  }
}
```

**Uncoordinated Scenario:**
1. Evidence service starts 3 concurrent uploads (max limit)
2. Offline queue service triggers `syncQueue()` (separate lock)
3. Queue processes items that **also** trigger evidence uploads
4. **Result:** More than 3 concurrent operations despite `MAX_CONCURRENT_SYNCS = 3`
5. Database connection pool exhausted or HTTP client overload

**Evidence Service Call Sites:**
- Line 393: `syncToServer()` called from evidence service
- Line 469: `autoSyncIfOnline()` called periodically
- Offline queue can also enqueue evidence sync actions

**Recommended Fix:**
1. **Remove concurrency control from evidence service** (lines 23-64)
2. **All evidence operations** should enqueue via `OfflineSyncQueueService`
3. Single centralized concurrency control in offline queue service
4. Evidence service becomes **storage-only** (save/retrieve from SQLite)

---

## 3. Retry Loop Issues

### Issue 3.1: Unbounded Retry Attempts in Evidence Sync

**File:** `c:/projects/rlmss/lib/services/manual_clocking_evidence_sync_service.dart`

**Lines:** 108-165 (`_makeRequestWithRetry`)

**Problem:**
- `maxRetries = 5` by default (line 112)
- Exponential backoff: 2s → 4s → 8s → 16s → 32s → 64s
- Total time for 5 retries: ~2 + 4 + 8 + 16 + 32 = **62 seconds minimum**
- With jitter (±30%), could be up to **80+ seconds**
- On unstable rural connection, this blocks UI thread if called synchronously

**Additional Issue:**
- Line 143: `while (true)` loop with attempt counter
- If `attempt` variable isn't properly incremented (bug), could loop infinitely
- No circuit breaker or abort mechanism

**Recommended Fix:**
```dart
// Add circuit breaker state
static int _consecutiveFailures = 0;
static DateTime? _circuitOpenUntil;

Future<http.Response> _makeRequestWithRetry(...) async {
  // Check circuit breaker
  if (_circuitOpenUntil != null && DateTime.now().isBefore(_circuitOpenUntil)) {
    throw Exception('Circuit breaker open until $_circuitOpenUntil');
  }
  
  int attempt = 0;
  const int MAX_ATTEMPTS = 3;  // Reduce from 5 to 3
  
  while (attempt < MAX_ATTEMPTS) {  // Replace while(true)
    try {
      final response = await requestFunction().timeout(const Duration(seconds: 30));
      
      // Reset circuit breaker on success
      _consecutiveFailures = 0;
      _circuitOpenUntil = null;
      
      return response;
    } catch (e) {
      attempt++;
      
      if (attempt >= MAX_ATTEMPTS) {
        _consecutiveFailures++;
        
        // Open circuit breaker after 3 consecutive failures
        if (_consecutiveFailures >= 3) {
          _circuitOpenUntil = DateTime.now().add(const Duration(minutes: 5));
          print('[EVIDENCE_SYNC] Circuit breaker opened until $_circuitOpenUntil');
        }
        
        rethrow;
      }
      
      // Exponential backoff with jitter
      final delay = Duration(seconds: (2 << attempt).clamp(2, 32));
      await Future.delayed(delay);
    }
  }
  
  throw Exception('Max retries exceeded');
}
```

---

### Issue 3.2: No Backoff Coordination Between Services

**Problem:** Each service has independent retry timing:
- `offline_sync_queue_service.dart`: 2s, 4s, 6s intervals (line 470 in `_syncSingleAction`)
- `manual_clocking_evidence_sync_service.dart`: 2s, 4s, 8s, 16s, 32s, 64s (exponential)
- `sync_service.dart`: 2s, 4s delays (lines 49-51 in `syncSingleClockIn`)

**Scenario:** Server under load from multiple facilitators:
1. 50 tablets all detect connectivity restored at same time
2. Each triggers sync across all services
3. All retry timers overlap: spikes at 2s, 4s, 8s after connectivity
4. Server sees 50 × 3 services = **150 concurrent requests** at each spike
5. Server timeouts cause more retries → cascading failure

**Recommended Fix:**
1. **Centralized retry coordinator** with exponential backoff
2. **Jittered startup**: Each device adds random 0-60s delay before first sync
3. **Server-side rate limiting**: Return `429 Too Many Requests` with `Retry-After` header
4. **Client respects Retry-After**: Parse header and delay longer than server suggests

---

## 4. Missing Coordination Mechanisms

### 4.1: No Global Sync Coordinator

**Current State:**
- Each service has independent locks (`_syncing`, `_isSyncing`, `_activeSyncs`)
- No communication between services
- No shared state or coordination

**Required Coordinator Features:**
1. **Global sync state** (idle, syncing_offline_queue, syncing_evidence, syncing_learners)
2. **Shared semaphore** limiting total concurrent operations across all services
3. **Priority queue** (clock-in/clock-out highest priority, bulk sync lowest)
4. **Conflict detection** (prevent batch submit during individual clocking)
5. **Resource tracking** (network bandwidth, database connections, memory)

**Recommended Implementation:**
```dart
// File: lib/services/global_sync_coordinator.dart

class GlobalSyncCoordinator {
  static final GlobalSyncCoordinator _instance = GlobalSyncCoordinator._internal();
  factory GlobalSyncCoordinator() => _instance;
  GlobalSyncCoordinator._internal();
  
  // Global state
  bool _anyOperationInProgress = false;
  String? _currentOperation;
  DateTime? _operationStartTime;
  
  // Semaphore for concurrent operations
  static const int MAX_GLOBAL_CONCURRENT = 3;
  int _activeOperations = 0;
  final List<_QueuedOperation> _operationQueue = [];
  
  // Acquire lock for operation
  Future<bool> tryAcquire(String operationId, {Duration timeout = const Duration(minutes: 5)}) async {
    if (_activeOperations >= MAX_GLOBAL_CONCURRENT) {
      print('[COORDINATOR] Max concurrent operations reached, queueing: $operationId');
      
      final completer = Completer<bool>();
      _operationQueue.add(_QueuedOperation(operationId, completer));
      
      return completer.future.timeout(timeout, onTimeout: () {
        print('[COORDINATOR] Operation $operationId timed out waiting for lock');
        return false;
      });
    }
    
    _activeOperations++;
    _currentOperation = operationId;
    _operationStartTime = DateTime.now();
    
    print('[COORDINATOR] Acquired lock for $operationId (active: $_activeOperations/$MAX_GLOBAL_CONCURRENT)');
    return true;
  }
  
  // Release lock
  void release(String operationId) {
    _activeOperations--;
    
    final duration = DateTime.now().difference(_operationStartTime ?? DateTime.now());
    print('[COORDINATOR] Released lock for $operationId after ${duration.inSeconds}s (active: $_activeOperations/$MAX_GLOBAL_CONCURRENT)');
    
    // Process next queued operation
    if (_operationQueue.isNotEmpty && _activeOperations < MAX_GLOBAL_CONCURRENT) {
      final next = _operationQueue.removeAt(0);
      _activeOperations++;
      _currentOperation = next.operationId;
      _operationStartTime = DateTime.now();
      next.completer.complete(true);
    } else {
      _currentOperation = null;
      _operationStartTime = null;
    }
  }
  
  // Check if specific operation type is allowed
  bool canStart(String operationType) {
    // Priority rules
    if (_currentOperation?.contains('clock_in') == true && operationType == 'bulk_sync') {
      return false;  // Don't bulk sync during active clocking
    }
    
    return _activeOperations < MAX_GLOBAL_CONCURRENT;
  }
}

class _QueuedOperation {
  final String operationId;
  final Completer<bool> completer;
  _QueuedOperation(this.operationId, this.completer);
}
```

---

### 4.2: Database Lock Coordination

**File:** `c:/projects/rlmss/lib/services/persistent_sync_service.dart`

**Issue:** Lines 191-231 use transactions with batch size 10, but no coordination with other services writing to same tables.

**Code Analysis:**
```dart
// Lines 191-231: Batch transaction processing
await db.transaction((txn) async {
  for (var learner in batch) {
    // ... insert/update learner
  }
}).timeout(const Duration(seconds: 5));  // 5-second timeout
```

**Problem:**
- `manual_clocking` table updated by multiple sources simultaneously:
  - `signature_geofence_clock_in_page.dart` → `_clockInOffline()` → INSERT
  - `offline_sync_queue_service.dart` → `_syncSingleAction()` → INSERT
  - `persistent_sync_service.dart` → `_syncOfflineClockingRecords()` → UPDATE
- SQLite database locking: **one writer at a time**
- Transaction timeout (5s) might conflict with another service's transaction
- No retry logic if database is locked

**Recommended Fix:**
```dart
// Add database operation wrapper with retry
Future<T> _executeDatabaseOperation<T>(
  Future<T> Function(Database db) operation,
  {int maxRetries = 3}
) async {
  int attempt = 0;
  
  while (attempt < maxRetries) {
    try {
      final db = await DatabaseHelper().database;
      return await operation(db);
    } on DatabaseException catch (e) {
      if (e.toString().contains('database is locked') && attempt < maxRetries - 1) {
        attempt++;
        final delay = Duration(milliseconds: 100 * (1 << attempt));  // 100ms, 200ms, 400ms
        print('[PERSISTENT_SYNC] Database locked, retry $attempt after ${delay.inMilliseconds}ms');
        await Future.delayed(delay);
      } else {
        rethrow;
      }
    }
  }
  
  throw DatabaseException('Database operation failed after $maxRetries attempts');
}
```

---

## 5. Connectivity Drop Mid-Sync Handling

### Issue 5.1: Evidence Upload Partial Completion

**File:** `c:/projects/rlmss/lib/signature_geofence_clock_in_page.dart`

**Lines:** 1180-1240 (`_clockInOnline`)

**Scenario:**
1. User clocks in learner
2. `_clockInOnline()` uploads face image (base64 ~200KB)
3. Rural 2G connection drops after 150KB uploaded
4. Image upload fails with timeout exception
5. **Problem:** No record of partial upload, full 200KB will be re-uploaded on retry

**Code Analysis:**
```dart
// Line 1192-1210: Upload images
final uploadResponse = await _makeAuthenticatedRequest(
  () => http.post(
    uploadUrl,
    headers: {...},
    body: jsonEncode(uploadPayload),  // Contains both face + signature
  ),
  maxRetries: 2,
);

// If this fails, entire clock-in aborts
if (uploadResponse.statusCode != 200 || uploadResult['success'] != true) {
  throw Exception('Image upload failed: ${uploadResult['error'] ?? 'Unknown error'}');
}
```

**Missing Features:**
- No chunked upload for large images
- No resume capability if connection drops
- No server-side check for already-uploaded images
- Full base64 payload sent every retry

**Recommended Fix:**

**Client-side (Dart):**
```dart
// Split large images into chunks
Future<String?> uploadImageInChunks(
  String imageBase64,
  String imageType,  // 'face' or 'signature'
  String learnerId,
  String clockDate
) async {
  const int CHUNK_SIZE = 50000;  // 50KB chunks
  final chunks = <String>[];
  
  for (int i = 0; i < imageBase64.length; i += CHUNK_SIZE) {
    final end = (i + CHUNK_SIZE < imageBase64.length) 
      ? i + CHUNK_SIZE 
      : imageBase64.length;
    chunks.add(imageBase64.substring(i, end));
  }
  
  final uploadId = const Uuid().v4();
  
  for (int i = 0; i < chunks.length; i++) {
    try {
      final response = await http.post(
        Uri.parse(AppConfig.buildUrl('upload_image_chunk.php')),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'upload_id': uploadId,
          'learner_id': learnerId,
          'clock_date': clockDate,
          'image_type': imageType,
          'chunk_index': i,
          'total_chunks': chunks.length,
          'chunk_data': chunks[i]
        }),
      ).timeout(const Duration(seconds: 10));  // Shorter timeout per chunk
      
      if (response.statusCode != 200) {
        throw Exception('Chunk $i upload failed');
      }
      
    } catch (e) {
      print('[CHUNK_UPLOAD] Failed at chunk $i/$chunks.length: $e');
      
      // Check server-side which chunks were received
      final resumeInfo = await _checkUploadProgress(uploadId);
      if (resumeInfo['chunks_received'] >= i) {
        print('[CHUNK_UPLOAD] Server has chunk $i, continuing');
        continue;  // Skip already-uploaded chunk
      }
      
      rethrow;
    }
  }
  
  // Finalize upload on server
  final finalizeResponse = await http.post(
    Uri.parse(AppConfig.buildUrl('finalize_image_upload.php')),
    body: jsonEncode({
      'upload_id': uploadId,
      'learner_id': learnerId,
      'clock_date': clockDate,
      'image_type': imageType
    }),
  );
  
  final result = jsonDecode(finalizeResponse.body);
  return result['filename'];
}
```

**Server-side (PHP):**
```php
// File: mobile/upload_image_chunk.php
<?php
require_once('connection.php');
require_once('require_auth.php');

$user = requireAuth($conn);
$input = json_decode(file_get_contents('php://input'), true);

$uploadId = $input['upload_id'];
$chunkIndex = $input['chunk_index'];
$totalChunks = $input['total_chunks'];
$chunkData = $input['chunk_data'];

// Store chunk in temporary table
$stmt = $conn->prepare("
  INSERT INTO image_upload_chunks 
  (upload_id, chunk_index, total_chunks, chunk_data, user_id, created_at)
  VALUES (?, ?, ?, ?, ?, NOW())
  ON DUPLICATE KEY UPDATE chunk_data = VALUES(chunk_data)
");
$stmt->bind_param("siiis", $uploadId, $chunkIndex, $totalChunks, $chunkData, $user['user_id']);
$stmt->execute();

echo json_encode([
  'success' => true,
  'upload_id' => $uploadId,
  'chunk_index' => $chunkIndex,
  'chunks_received' => getChunksReceived($conn, $uploadId)
]);

function getChunksReceived($conn, $uploadId) {
  $result = $conn->query("SELECT COUNT(*) as count FROM image_upload_chunks WHERE upload_id = '$uploadId'");
  return $result->fetch_assoc()['count'];
}
?>
```

---

## 6. Timeout Configuration Audit

| Service | Operation | Current Timeout | Recommended | Reasoning |
|---------|-----------|----------------|-------------|-----------|
| offline_sync_queue_service | `_processActionOnline()` | 30s (line 206) | **15s** | Faster failure, queue will retry |
| offline_sync_queue_service | `_processBatchOnline()` | 60s (line 358) | **30s** | Rural 2G: 30s is still long enough for 10 learners |
| manual_clocking_evidence_sync_service | `_makeRequestWithRetry()` | 30s (line 128) | **10s per chunk** | With chunked uploads, each chunk should be fast |
| persistent_sync_service | `_syncLearnersForClass()` | 30s (line 181 `lightweightTimeout`) | **20s** | Reduce to fail faster |
| persistent_sync_service | Database transaction | 5s (line 231) | **3s** | Database should be fast, longer timeout masks lock issues |
| sync_service | `syncSingleClockIn()` | 8s × attempts (line 34) | **5s × 2 attempts** | Faster individual failures |
| signature_geofence_clock_in_page | `_clockInOnline()` | None (implicit) | **15s** | User feedback timeout |

---

## 7. Concrete Recommended Fixes

### Priority 1 (Immediate - Data Integrity)

**1. Fix persistent_sync_service race condition**
- **File:** `lib/services/persistent_sync_service.dart`
- **Lines:** 96-145
- **Change:** Add `_isSyncing = true` at line 96, wrap in try-finally with `_isSyncing = false`
- **Test:** Trigger multiple rapid syncs, confirm only one executes

**2. Remove duplicate retry logic**
- **File:** `lib/services/manual_clocking_evidence_sync_service.dart`
- **Lines:** 108-165 (delete `_makeRequestWithRetry` method)
- **Change:** Replace with single-attempt requests, enqueue failures to offline_sync_queue_service
- **Test:** Simulate network failure, confirm single retry sequence

### Priority 2 (High - Performance)

**3. Implement global sync coordinator**
- **File:** Create `lib/services/global_sync_coordinator.dart`
- **Change:** Add semaphore limiting concurrent operations across all services
- **Integration:** Update all services to use `GlobalSyncCoordinator().tryAcquire()` before sync
- **Test:** Trigger syncs from multiple services, confirm max 3 concurrent

**4. Add chunked image upload**
- **Files:** 
  - `lib/signature_geofence_clock_in_page.dart` (add `uploadImageInChunks()`)
  - `mobile/upload_image_chunk.php` (new endpoint)
  - `mobile/finalize_image_upload.php` (new endpoint)
- **Change:** Split base64 images into 50KB chunks, support resume
- **Test:** Upload 200KB image, disconnect mid-upload, reconnect, confirm resume

### Priority 3 (Medium - Reliability)

**5. Add circuit breaker to evidence sync**
- **File:** `lib/services/manual_clocking_evidence_sync_service.dart`
- **Lines:** 108-165
- **Change:** Open circuit after 3 consecutive failures, close after 5 min cooldown
- **Test:** Simulate 3 failures, confirm no more attempts for 5 min

**6. Coordinate batch and individual clocking**
- **File:** `lib/signature_geofence_clock_in_page.dart`
- **Lines:** 849-900, 1055-1127
- **Change:** Add global `_isAnyOperationInProgress` flag
- **Test:** Start batch submit, attempt individual clock-in, confirm blocked

**7. Reduce timeouts across all services**
- **Files:** All sync services
- **Change:** Reduce timeouts per table in section 6
- **Test:** Simulate slow server, confirm faster failures and retries

### Priority 4 (Low - Monitoring)

**8. Add structured logging for sync operations**
- **Files:** All sync services
- **Change:** Log operation ID, start/end time, success/failure, retry count
- **Format:** JSON with correlation IDs
- **Test:** Perform sync, check log file contains structured entries

**9. Add sync diagnostics UI**
- **File:** Create `lib/debug/sync_diagnostics_page.dart`
- **Change:** Show pending operations, retry counts, last sync time, coordination state
- **Test:** Manual inspection during sync operations

---

## 8. Testing Requirements

### Unit Tests

```bash
# Test 1: persistent_sync_service race condition
flutter test test/services/persistent_sync_service_test.dart --name "prevents concurrent syncs"

# Test 2: No duplicate retries
flutter test test/services/sync_coordination_test.dart --name "single retry sequence"

# Test 3: Global coordinator semaphore
flutter test test/services/global_sync_coordinator_test.dart --name "concurrent limit"
```

### Integration Tests

```bash
# Test 4: Batch and individual clocking coordination
flutter test integration_test/clocking_coordination_test.dart

# Test 5: Chunked upload with resume
flutter test integration_test/chunked_upload_resume_test.dart
```

### Network Simulation Tests

```bash
# Simulate 2G/EDGE speeds, packet loss, mid-request disconnects
flutter test test/network_simulation/connectivity_drop_test.dart --timeout=10m
```

---

## 9. Success Metrics

After implementing fixes, monitor:

1. **Duplicate Request Rate:** Should be < 1% (idempotency keys prevent data duplicates but we want to reduce wasted requests)
2. **Concurrent Sync Operations:** Never exceed 3 globally
3. **Evidence Upload Success Rate:** > 95% on first attempt (with chunking)
4. **Average Sync Completion Time:** Reduce by 30-50% (due to reduced retries)
5. **Server Load During Connectivity Restoration:** Reduce by 60-70% (coordinated retries with jitter)
6. **Database Lock Errors:** < 0.1% of operations

---

## 10. Risk Assessment

| Fix | Risk Level | Mitigation |
|-----|-----------|------------|
| Global coordinator | HIGH - could break all sync if buggy | Feature flag, gradual rollout, extensive testing |
| Remove duplicate retries | MEDIUM - might miss some failures | Ensure offline queue is robust first |
| Chunked uploads | MEDIUM - new failure modes | Keep fallback to full upload for small images |
| Reduced timeouts | LOW - faster failures are good | Monitor failure rates during rollout |
| Circuit breaker | LOW - improves reliability | Set conservative thresholds |

---

## Conclusion

The RLMSS sync system has **NO CENTRAL COORDINATOR** and relies on independent, uncoordinated services with overlapping responsibilities. This architecture is **NOT SAFE** for production use in rural connectivity scenarios.

**IMMEDIATE ACTIONS REQUIRED:**
1. Fix `persistent_sync_service._isSyncing` race condition (1 hour)
2. Remove duplicate retry logic from evidence service (2 hours)
3. Implement global sync coordinator (1 day)
4. Add chunked image upload with resume (2 days)

**ESTIMATED TOTAL EFFORT:** 4-5 days for Priority 1-2 fixes

---

**End of Audit Report**
