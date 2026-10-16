# Implementation Plan: Sync Coordination Fixes

## Context
The app has three synchronization services that currently create overlapping requests and excessive retries under unstable rural connectivity:
- `persistent_sync_service.dart` - Background sync for learners and clocking records
- `manual_clocking_evidence_sync_service.dart` - Sync for face photos and signatures
- `offline_sync_queue_service.dart` - Global offline queue with retry logic

**Problem 1**: `persistent_sync_service.dart` declares `_isSyncing` but never sets it to `true`, allowing concurrent `syncAllData()` calls to run simultaneously.

**Problem 2**: `manual_clocking_evidence_sync_service.dart` has its own `_makeRequestWithRetry()` method (5 retries with exponential backoff) that duplicates the retry logic already in `offline_sync_queue_service.dart`, causing 10-25× server load.

## Implementation Steps

- [ ] 1. Fix race condition in persistent_sync_service.dart
      Add proper `_isSyncing` flag management to prevent concurrent sync operations.
      - At line 107, before `if (!isConnected)`, add early return guard: `if (_isSyncing) { result.success = false; result.message = 'Sync already in progress'; return result; }`
      - Immediately after the guard, set `_isSyncing = true;`
      - Wrap lines 107-144 (from connectivity check to return statement) in try/finally block
      - In finally block, set `_isSyncing = false;`
      - Verify that `_triggerBackgroundSync()` at line 72 calls `syncAllData()` through `_coordinator.executeSyncOperation()`, which already provides serialization — no additional changes needed in `_triggerBackgroundSync()`
      Files: `lib/services/persistent_sync_service.dart`
      Verify: `flutter analyze` passes with 0 errors

- [ ] 2. Remove duplicate retry logic from manual_clocking_evidence_sync_service.dart
      Delete the `_makeRequestWithRetry()` and `_isRetryableError()` methods entirely.
      - Delete lines 108-165 (the entire `_makeRequestWithRetry()` method)
      - Delete lines 166-173 (the entire `_isRetryableError()` method — note: actual line numbers may shift after first deletion, so identify by method signature)
      - In `syncToServer()` method (around line 387), locate the call to `_makeRequestWithRetry()` and replace it with a single direct HTTP call:
        ```dart
        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'records': recordsToSync}),
        ).timeout(const Duration(seconds: 10));
        ```
      - After the direct HTTP call, handle failures by returning early with error result instead of retrying internally:
        ```dart
        if (response.statusCode != 200) {
          throw Exception('Server returned status ${response.statusCode}');
        }
        ```
      - The existing try/catch block around line 382-418 will catch this exception and return `{'success': false, 'error': e.toString(), 'synced_count': 0}`, allowing `offline_sync_queue_service` to retry later
      - Keep the `_executeConcurrencyControlled` wrapper intact (no changes to lines 49-69)
      - Verify `autoSyncIfOnline()` at line 545 still calls `syncToServer()` unchanged
      Files: `lib/services/manual_clocking_evidence_sync_service.dart`
      Verify: `flutter analyze` passes with 0 errors

- [ ] 3. Verify no breaking API changes
      Confirm all public method signatures remain unchanged and upstream callers compile.
      - Check that `PersistentSyncService().syncAllData()` still returns `Future<SyncResult>`
      - Check that `ManualClockingEvidenceSyncService().syncToServer()` still returns `Future<Map<String, dynamic>>`
      - Check that `ManualClockingEvidenceSyncService().autoSyncIfOnline()` still returns `Future<void>`
      - Grep for any direct calls to the deleted methods `_makeRequestWithRetry` or `_isRetryableError` outside the service (should find none since they were private)
      Files: `lib/services/persistent_sync_service.dart`, `lib/services/manual_clocking_evidence_sync_service.dart`
      Verify: `flutter analyze && flutter build apk --debug` succeeds with no compilation errors

## Constraints
- Do NOT modify `offline_sync_queue_service.dart` in any way
- Do NOT change public API signatures — upstream callers must compile unchanged
- `flutter analyze` must pass with 0 errors after all changes
- Single retry layer: `offline_sync_queue_service` is the only service that performs retries

## Expected Outcomes
1. No concurrent `syncAllData()` calls — `_isSyncing` flag prevents overlapping background syncs
2. Single retry layer — `manual_clocking_evidence_sync_service` makes one HTTP attempt; `offline_sync_queue_service` handles retries
3. 5-10× reduction in server requests under unstable connectivity (from 10-25× retries down to 2-5× retries)
4. Improved coordination — `DatabaseCoordinator` and `_isSyncing` flag prevent race conditions

## Verification Commands
- Full static analysis: `flutter analyze`
- Compilation check: `flutter build apk --debug`
- Runtime verification: Install debug APK on test device and trigger sync operations under airplane mode → online → airplane mode cycle, monitoring logs for duplicate requests
