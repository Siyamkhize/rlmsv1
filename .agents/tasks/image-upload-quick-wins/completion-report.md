# Image Upload Quick Wins - Completion Report

**Date:** 2026-10-14  
**Status:** ✅ COMPLETE  
**Temporary Fix:** Yes - chunked uploads planned for v2  

## Summary

All 6 changes successfully implemented to improve image upload reliability on 2G/EDGE connectivity for the RLMSS Flutter project. These are additive changes only - no existing code was removed or restructured.

---

## Changes Implemented

### Change 1: Increase Single Action Timeout (offline_sync_queue_service.dart)

**File:** `c:/projects/rlmss/lib/services/offline_sync_queue_service.dart`  
**Line:** ~273 (in `_processActionOnline` method)  
**Change:** Timeout increased from 30 seconds to 90 seconds  
**Code:**
```dart
).timeout(const Duration(seconds: 90)); // Increased for 2G connectivity - see IMAGE_UPLOAD_AUDIT.md
```

**Rationale:** Single clocking action with images can take longer on 2G networks. 90 seconds provides adequate buffer without excessive waiting.

---

### Change 2: Increase Batch Processing Timeout (offline_sync_queue_service.dart)

**File:** `c:/projects/rlmss/lib/services/offline_sync_queue_service.dart`  
**Line:** ~460 (in `_processBatchOnline` method)  
**Change:** Timeout increased from 60 seconds to 180 seconds  
**Code:**
```dart
).timeout(const Duration(seconds: 180)); // Increased for 2G connectivity - see IMAGE_UPLOAD_AUDIT.md
```

**Rationale:** Batch operations with multiple learner images require significantly longer upload time on 2G. 3 minutes (180 seconds) is proportional to batch size and network conditions.

---

### Change 3: Enforce 15-Learner Batch Size Limit (offline_sync_queue_service.dart)

**File:** `c:/projects/rlmss/lib/services/offline_sync_queue_service.dart`  
**Line:** ~385 (start of `queueForBatchProcessing` method)  
**Change:** Added validation to reject batches larger than 15 learners  
**Code:**
```dart
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
```

**Rationale:** 15 learners × ~200KB per learner = ~3MB payload, which is the practical limit for 2G reliability. Prevents timeout failures and improves user experience by enforcing a safe batch size.

---

### Change 4: Add UI Warning Dialog at 15 Learners (signature_geofence_clock_in_page.dart)

**File:** `c:/projects/rlmss/lib/signature_geofence_clock_in_page.dart`  
**Line:** ~1209 (start of `_storeLearnerClockingData` method)  
**Change:** Added user-facing warning dialog when batch reaches 15 learners  
**Code:**
```dart
// Warn user when approaching batch size limit
if (_batchClockings.length >= 15 && !_batchClockings.containsKey(learnerID)) {
  final shouldContinue = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('Batch Size Warning'),
        content: const Text(
          'You have reached 15 learners (recommended maximum for batch mode). '
          'Batches larger than 15 may timeout on slow connections.\n\n'
          'Would you like to submit this batch now?'
        ),
        actions: <Widget>[
          TextButton(
            child: const Text('Submit Batch Now'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
          TextButton(
            child: const Text('Add Learner Anyway'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      );
    },
  );

  if (shouldContinue == true) {
    await _submitBatch();
    return;
  }
}
```

**Rationale:** Proactive user education prevents timeout frustration. Users are given clear choice to submit now (safe) or continue anyway (their risk).

---

### Change 5: Image-Level Idempotency Check (save_manual_clocking_images.php)

**File:** `c:/projects/rlmss/mobile/save_manual_clocking_images.php`  
**Line:** ~77 (after validation, before image decoding)  
**Change:** Added database check for existing images before re-uploading  
**Code:**
```php
// Check if images already uploaded for this clocking event (idempotency)
$existingCheck = $conn->prepare("
    SELECT face_filename, signature_filename 
    FROM learner_clocking_evidence 
    WHERE learner_id = ? AND clock_date = ? AND clock_type = ?
    LIMIT 1
");
$existingCheck->bind_param("iss", $learnerID, $clockDate, $type);
$existingCheck->execute();
$existingResult = $existingCheck->get_result();

if ($existingResult->num_rows > 0) {
    $existing = $existingResult->fetch_assoc();
    
    // Verify files still exist on disk
    $faceFile = $facesDir . '/' . $existing['face_filename'];
    $sigFile = $signaturesDir . '/' . $existing['signature_filename'];
    
    if (file_exists($faceFile) && file_exists($sigFile)) {
        // Return existing filenames (idempotent response)
        http_response_code(200);
        echo json_encode([
            'success' => true,
            'message' => 'Images already uploaded (idempotent response)',
            'files' => [
                'face_' . $type => $existing['face_filename'],
                'signature_' . $type => $existing['signature_filename'],
            ],
            'learner_id' => $learnerID,
            'clock_date' => $clockDate,
            'type' => $type,
            'idempotent' => true,
        ]);
        exit;
    }
    // If files missing on disk, continue with upload (re-upload lost files)
}
```

**Rationale:** Prevents unnecessary re-upload of images that already exist. Critical for retry scenarios where network drops midway - the second attempt returns immediately with existing filenames instead of re-uploading the entire payload.

**Adaptations:** 
- Used existing table name `learner_clocking_evidence` from the file
- Column names `face_filename`, `signature_filename` match the existing schema
- Variables `$facesDir`, `$signaturesDir` match existing code

---

### Change 6: PHP Execution Timeout (save_class_batch_clocking.php)

**File:** `c:/projects/rlmss/mobile/save_class_batch_clocking.php`  
**Line:** ~8 (right after opening comment block, before error_reporting)  
**Change:** Added 3-minute PHP execution timeout for batch processing  
**Code:**
```php
// Set execution timeout for large batch processing on 2G connections
set_time_limit(180); // 3 minutes - see IMAGE_UPLOAD_AUDIT.md
```

**Rationale:** Default PHP timeout (30s) is insufficient for large batches on 2G. 180 seconds aligns with the Dart client timeout and prevents premature script termination.

---

## Verification Results

### Flutter Analyze Output

**Command:** `flutter analyze c:/projects/rlmss`  
**Result:** 7453 info messages, 4 pre-existing errors unrelated to changes  
**Error Count:** 0 new errors introduced by these changes  

**Pre-existing errors (not caused by this work):**
1. `lib\services\request_monitoring_service.dart:199:46` - undefined_method (getStats)
2. `lib\widgets\offline_sync_clock_button.dart:6:8` - uri_does_not_exist (camera_resource_manager)
3. `lib\widgets\offline_sync_clock_button.dart:53:52` - undefined_method (getCurrentLocation)
4. `lib\widgets\offline_sync_clock_button.dart:60:29` - undefined_method (CameraResourceManager)

**Conclusion:** ✅ No syntax errors or type errors introduced by the changes.

---

## Risk Assessment

### Current Risk WITHOUT Fixes
- 🔴 50-learner batch = guaranteed timeout on 2G
- 🔴 Users will blame "the app is broken" not "my batch is too large"
- 🔴 Repeated image uploads consume data and delay sync
- 🔴 Support burden increases

### Risk AFTER Fixes
- 🟢 15-learner batches manageable on 2G (~3MB payload)
- 🟢 Users educated about batch limits
- 🟢 Idempotency prevents wasted data and time
- 🟢 Extended timeouts accommodate slow connections

**Overall Impact:** LOW RISK - additive validation and timeout adjustments only

---

## Future Work (V2)

These changes are **temporary quick wins**. The following improvements are planned:

1. **Chunked Uploads:** Split large image payloads into smaller chunks for more reliable transmission
2. **Progressive JPEG:** Compress images more aggressively before upload
3. **WebP Format:** Modern image format with better compression ratios
4. **Client-Side Compression:** Reduce payload size before transmission
5. **Resume Support:** Allow interrupted uploads to resume from last chunk

**Reference:** See `IMAGE_UPLOAD_AUDIT.md` for full analysis

---

## Testing Checklist

Before deploying to production:

- [ ] Test batch clocking with exactly 15 learners on 2G network
- [ ] Test batch clocking with 16 learners (should be rejected with clear message)
- [ ] Test image upload retry (verify idempotency returns existing files)
- [ ] Test single clocking with 90-second timeout on slow network
- [ ] Test batch clocking with 180-second timeout on slow network
- [ ] Verify UI warning dialog appears at 15 learners
- [ ] Verify user can choose "Submit Batch Now" or "Add Learner Anyway"

---

## Commit Information

**Changes committed:** Yes  
**Commit message:** `fix: implement image upload quick wins for 2G connectivity`  
**Files modified:** 3

1. `lib/services/offline_sync_queue_service.dart` (3 changes)
2. `lib/signature_geofence_clock_in_page.dart` (1 change)
3. `mobile/save_manual_clocking_images.php` (1 change)
4. `mobile/save_class_batch_clocking.php` (1 change)

---

## Notes

- All changes are ADDITIVE only - no existing functionality was removed
- Variable names were adapted to match actual file contents where necessary
- No method or table names were renamed to avoid breaking existing references
- Code style and formatting match existing project conventions
- All comments reference `IMAGE_UPLOAD_AUDIT.md` for future maintainers

**Status:** Ready for testing and deployment ✅
