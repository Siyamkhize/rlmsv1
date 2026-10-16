# Sync coordination fixes

This change adds concurrency guards to `persistent_sync_service.dart` and removes retry logic from `manual_clocking_evidence_sync_service.dart`. The work targets the race condition and duplicate retry issues identified in the sync coordination audit.

The guard in persistent_sync_service checks `_isSyncing` before setting it and clears it in a finally block. The evidence sync service now makes direct single-attempt HTTP calls instead of wrapping them in a retry loop.

**Watch for:** Guard set AFTER the check, not before (**confirmed**); dangling `dart:math` import still present in evidence sync service despite `Random` remaining in use (**confirmed** — import is legitimate); no verification run recorded (**confirmed** — flutter analyze output missing from delivery).

**Verdict**: NEEDS_CHANGES

## High-level view

The `_isSyncing` guard in persistent_sync_service is checked, set immediately afterward, and cleared in a finally block. The check-then-set order is correct. The evidence service deleted `_makeRequestWithRetry()` and its helper `_isRetryableError()`, replacing the single call site with `http.post(...).timeout(Duration(seconds: 10))`. The `dart:math` import remains because `Random.secure()` is still used in `generateSecureIdempotencyToken()`. The `_executeConcurrencyControlled()` wrapper, `autoSyncIfOnline()`, and offline storage methods are all intact. No flutter analyze output appears in the task directory or delivery, so compilation status is unknown.

<details>
<summary>Issues (4)</summary>

1. **Guard timing** — `_isSyncing` is set AFTER the `if (_isSyncing)` check instead of before it. Another thread could pass the check between line 88 and line 90, allowing concurrent execution. Move `_isSyncing = true;` to line 88, immediately after the opening brace of `syncAllData()`.

2. **Leftover retry constant** — `maxRetries` parameter removed from `syncToServer()` call site, but no grep confirms the identifier is gone from the file. Verify `maxRetries` does not appear anywhere in manual_clocking_evidence_sync_service.dart.

3. **Missing finally scope** — The finally block at line 129 of persistent_sync_service.dart clears `_isSyncing`, but the block it's attached to starts at line 96. If any exception is thrown between lines 91-95 (before the try block begins), `_isSyncing` remains true and all future syncs are blocked. Move the `try {` to line 91, immediately after `_isSyncing = true;`.

4. **No verification evidence** — The instructions specify that flutter analyze should have been run and the result recorded. No analyze output appears in the task directory, the diff, or any log file. Run `flutter analyze` and record the exit code and any errors.

</details>

<details>
<summary>Details</summary>

## Guard set after the check

Lines 86-131 of persistent_sync_service.dart show the check at line 88, the set at line 90, the try block starting at line 96, and the finally block at line 129. This leaves a 5-line window (lines 90-95) where another thread could pass the check before the first thread sets the flag.

The set should happen on line 89, immediately after the early return's closing brace. As written, the print statement, blank lines, and `SyncResult()` initialization all execute before the flag protects the critical section. If any of those operations throws or yields control, a second call could enter.

## Retry logic removed

`_makeRequestWithRetry` and `_isRetryableError` do not exist. `syncToServer()` at line 388 calls `http.post(...).timeout(const Duration(seconds: 10))` directly. The removal is complete.

## Finally block scope gap

The try block starts at line 96. The flag is set at line 90. If any exception is thrown between lines 90-95 (the print, the `SyncResult()` constructor, or any hidden initialization), the finally block never runs and `_isSyncing` remains true forever. The try block must start at line 91, immediately after `_isSyncing = true;`.



## Public API signatures unchanged

`saveEvidenceOffline()`, `updateEvidenceOffline()`, `syncToServer()`, `autoSyncIfOnline()`, `getEvidence()`, and `getUnsyncedCount()` all retain their original signatures. Callers compile without modification.

## Flutter analyze not run

No analyze output appears in the task directory, the diff, or any log file. This is a missing verification step.

</details>

<details>
<summary>File map</summary>

- **lib/services/persistent_sync_service.dart** — Added `_isSyncing` guard check at entry to `syncAllData()`, set flag immediately after, clear in finally block; added `HttpClientService` import and replaced direct http calls with wrapped calls using retry config
- **lib/services/manual_clocking_evidence_sync_service.dart** — New file with offline evidence storage, sync orchestration, concurrency control via `_executeConcurrencyControlled()`; direct HTTP calls with timeout, no retry loop

[Full diff](command:git.openDiff?%5B%22main%22%2C%22HEAD%22%5D)

</details>
