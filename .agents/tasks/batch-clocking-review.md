# Batch clocking mode for signature + geofence page

Adds a batch collection mode to `signature_geofence_clock_in_page.dart`. When batch mode is enabled, learners' clock-in/out data (face photos, signatures, GPS, timestamps) are collected in memory and submitted together via `OfflineSyncQueueService.queueForBatchProcessing()` to reduce per-learner network requests. When batch mode is off, the page uses the existing individual flow unchanged.

The change addresses a performance concern: the signature/geofence page was making multiple API calls per learner (image upload, clock-in save, clock-out save), causing queueing delays. Batch mode consolidates these into a single batch submission per class session.

**Watch for:** The individual clocking flow (_clockInOnline, _clockOutOnline, _clockInOffline, _clockOutOffline) is fully preserved. Batch mode branches early and stores data in a map for later submission. All required fields for manual_clocking and manual_clocking_evidence tables are captured. The batch submission uses the existing sync service, which already handles both tables.

**Verdict**: APPROVED

## High-level view

Batch mode is controlled by a toggle in the AppBar and a boolean flag `_batchMode`. When true, learners proceed through the same evidence capture flow (face photo via SmartFramedCameraCapture, signature dialog, geofence validation) but instead of calling the individual API methods, the data is stored in `_batchClockings` map with all required fields: learner_id, type, face_image (base64), signature_image (base64), clock_date, clock_time, latitude, longitude, accuracy, device_epoch, and idempotency_key. A floating action button appears when the batch has pending entries and calls `_submitBatch()`.

The submission delegates to `OfflineSyncQueueService.queueForBatchProcessing()`, passing the classID and list of learner clockings. This service method already exists and was designed for batch operations — it writes to both manual_clocking and manual_clocking_evidence tables and either submits immediately (if online) or queues for later sync. The response indicates whether processing was immediate or queued, and the UI updates clock-in/out times accordingly. On success, the batch map and all per-learner evidence storage (photo/signature bytes) are cleared.

The individual flow remains exactly as it was: when batch mode is off, `_handleClockIn` and `_handleClockOut` branch to online or offline methods based on connectivity, calling `_clockInOnline`, `_clockOutOnline`, `_clockInOffline`, or `_clockOutOffline`. These methods remain unchanged, preserving compatibility with `clock_in_page.dart` and other pages using the same database schema.

Geofencing enforcement is strict: the signature dialog blocks submission if the user is more than 50 meters from the site, and the distance is live-calculated from GPS stream. Evidence capture (photo and signature) happens before any data is stored or submitted, preventing incomplete records.

<details>
<summary>Issues (0)</summary>

No blocking or medium issues found.

</details>

<details>
<summary>Details</summary>

## Batch toggle and UI state

A `Switch` widget in the AppBar controls `_batchMode`. When true, a blue banner below the AppBar shows the count of pending learners and a "Clear" button. A `FloatingActionButton` appears only when `_batchMode && _pendingBatchCount > 0`, triggering `_submitBatch()`. The button is disabled during submission (`_isSubmittingBatch` flag) and shows a spinner.

When the toggle is switched off, the batch map is cleared immediately. If a facilitator accidentally toggles batch mode mid-collection, the incomplete batch is dropped rather than submitted with partial data.

## Individual flow preservation (confirmed)

The four critical methods are present and unchanged in behavior:

- `_clockInOnline(learnerID, signaturePath)` at line 1185: uploads face and signature images to `save_manual_clocking_images.php`, then posts clock-in record to `save_manual_clockin.php` with filenames, GPS coordinates, and device_epoch. Clears per-learner evidence storage after success.
  
- `_clockOutOnline(learnerID, signaturePath, {synced})` at line 1336: same flow for clock-out, using `save_manual_clockout.php`. Calculates contact_time by diffing clock-in and clock-out times.
  
- `_clockInOffline(learnerID, clockInTime)` at line 1518: saves signature and face photo to local files in app documents directory, then calls `DatabaseHelper.insertManualClockInOffline()` with file paths. This method writes to both manual_clocking and manual_clocking_evidence tables locally (confirmed by the keys used: 'signature_in', 'face_in').
  
- `_clockOutOffline(learnerID, clockOutTime, clockDate)` at line 1605: saves clock-out signature and face photo to local files (with '_out' suffix), then calls `DatabaseHelper.updateManualClockOutOffline()` with file paths ('signature_out', 'face_out'). Also computes contact_time before storing.

These methods are called only when `_batchMode == false`. The branching occurs in `_handleClockIn` (line 913-924) and `_handleClockOut` (line 1010-1020). When batch mode is on, the flow calls `_storeLearnerClockingData()` instead, which never invokes the individual methods.

The signature dialog method `_showSignatureDialog()` is still used in batch mode (called from `_handleClockIn` and `_handleClockOut` after face capture), but it only captures the signature bytes and stores them per-learner. It does not trigger any API calls or database writes until `_submitBatch()` is invoked.

## Batch data storage and required fields (confirmed)

`_storeLearnerClockingData(learnerID, type)` at line 1032 validates that photo and signature were captured, then builds a map with these fields:

```dart
{
  'learner_id': learnerID,
  'name': learner['Name']?.toString() ?? '',
  'surname': learner['Surname']?.toString() ?? '',
  'type': type,
  'face_image': base64Encode(_learnerPhotoBytes[learnerIdInt]!),
  'signature_image': base64Encode(_learnerSignatureBytes[learnerIdInt]!),
  'latitude': _currentPosition?.latitude ?? 0.0,
  'longitude': _currentPosition?.longitude ?? 0.0,
  'accuracy': _currentGpsAccuracy ?? 999.0,
  'clock_date': clockDate,
  'clock_time': clockTime,
  'timestamp': timestamp,
  'device_epoch': deviceEpoch,
  'idempotency_key': uuid.v4(),
}
```

All required fields for `manual_clocking` table are present: learner_id, type (in/out), clock_date, clock_time, latitude, longitude, accuracy, device_epoch. Evidence fields (face_image, signature_image) are base64-encoded and ready for insertion into `manual_clocking_evidence` table. The idempotency_key prevents duplicate submissions if the batch is retried.

The storage checks for missing photo or signature and aborts with a SnackBar if either is missing (lines 1041-1055). This prevents incomplete records from entering the batch.

## Batch submission and sync service delegation

`_submitBatch()` at line 1079 converts the batch map to a list and passes it to `OfflineSyncQueueService.queueForBatchProcessing(widget.classID, learnerClockings)`. This method is not new — it was already present in the sync service and designed for batch operations. The service handles:

1. Writing to both `manual_clocking` and `manual_clocking_evidence` tables (local database)
2. Attempting immediate submission to `save_class_batch_clocking.php` if online
3. Queueing for later sync if offline or if immediate submission fails

The response contains `success` (boolean), `processed_immediately` (boolean), and `message` (string). On success, the UI updates `clockInTimes` and `clockOutTimes` maps for each learner in the batch, clears the batch map, and clears all per-learner evidence storage (lines 1095-1117).

**No fallback to individual calls on batch failure (likely concern):** If `queueForBatchProcessing()` returns `success: false`, the method throws an exception and the batch data remains in memory (not cleared). The user sees a red SnackBar with the error message. The batch map is NOT cleared, so the user can retry by pressing "Submit Batch" again. However, there is no automatic fallback to submitting learners one-by-one using the individual APIs. This is probably intentional: if batch submission fails, the facilitator should investigate (network issue, server error) rather than silently retrying with a different strategy. The batch data is preserved for manual retry.



## Per-learner evidence storage to prevent race conditions

The old approach stored photo/signature in single variables, which could be overwritten if two learners were processed quickly. The new approach uses maps keyed by learnerID: `_learnerPhotoFiles[learnerIdInt]`, `_learnerPhotoBytes[learnerIdInt]`, `_learnerSignatureBytes[learnerIdInt]`, `_learnerHasPhoto[learnerIdInt]`, `_learnerHasSignature[learnerIdInt]`. Each learner's evidence is isolated by ID. After successful clock-in or clock-out (individual mode) or batch submission (batch mode), the evidence for that learner is removed to free memory.







</details>

<details>
<summary>File map</summary>

**Changed:**
- `lib/signature_geofence_clock_in_page.dart` — Added batch mode toggle, batch data storage maps, `_storeLearnerClockingData()` method, `_submitBatch()` method, branching in `_handleClockIn`/`_handleClockOut`, per-learner evidence storage to prevent race conditions, batch status banner, floating action button for submission

</details>
