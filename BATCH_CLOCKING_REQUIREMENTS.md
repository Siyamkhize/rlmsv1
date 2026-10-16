# Batch Clocking Requirements - CRITICAL

**Date:** October 13, 2026  
**Status:** ⚠️ IN PROGRESS - DO NOT BREAK EXISTING FUNCTIONALITY

---

## 🚨 CRITICAL RULE: PRESERVE EXISTING FUNCTIONALITY

**The current individual clocking system MUST continue to work EXACTLY as it does now.**

### What MUST NOT Change

**These methods MUST remain unchanged:**
- ✅ `_clockInOnline()` - uploads to `save_manual_clocking_images.php` + `save_manual_clockin.php`
- ✅ `_clockOutOnline()` - uploads to `save_manual_clocking_images.php` + `save_manual_clockout.php`
- ✅ `_clockInOffline()` - saves to local `manual_clocking` table
- ✅ `_clockOutOffline()` - updates local `manual_clocking` table

**These database operations MUST remain unchanged:**
- ✅ Image upload to server filesystem
- ✅ INSERT into `manual_clocking` table (LearnerID, clock_date, clock_in_time, clock_out_time, contact_time, is_manual_attendance, synced)
- ✅ INSERT into `manual_clocking_evidence` table (LearnerID, clock_date, signature_in, face_in, signature_out, face_out, synced)
- ✅ Local SQLite storage for offline mode

**These processes MUST continue:**
- ✅ Face photo capture with watermark
- ✅ Signature capture
- ✅ Geofencing validation (50m radius)
- ✅ GPS accuracy tracking
- ✅ Timestamp recording

---

## 🎯 What We're Adding

### New Feature: Optional Batch Mode

**Purpose:** Reduce network requests in rural areas by batching all learner clockings into ONE request.

**Implementation:** Add a toggle switch that changes the behavior:
- **Individual Mode (default):** Current behavior, unchanged
- **Batch Mode (new):** Collect data, submit in one batch

---

## 📊 Current vs Batch Comparison

### Current Flow (Individual Mode)
```
For each of 30 learners:
1. Capture photo + signature
2. Upload images → save_manual_clocking_images.php
3. Send clock-in → save_manual_clockin.php
4. Send clock-out → save_manual_clockout.php

Total: 30 × 3 = 90 API requests
```

### New Flow (Batch Mode)
```
For 30 learners:
1. Capture photo + signature for each (same as before)
2. Store ALL data in memory
3. Click "Submit Batch" button
4. Send ONE request → save_class_batch_clocking.php

Total: 1 API request
```

---

## 🔧 Implementation Details

### 1. Add Mode Toggle
```dart
// In AppBar actions
Switch(
  value: _batchMode,
  onChanged: (value) => setState(() => _batchMode = value),
),
Text(_batchMode ? 'Batch Mode' : 'Individual Mode'),
```

### 2. State Variables
```dart
bool _batchMode = false; // false = individual, true = batch
Map<String, Map<String, dynamic>> _batchClockings = {}; // Stored data
int get _pendingBatchCount => _batchClockings.length;
```

### 3. Modified Clock-In Handler
```dart
Future<void> _handleClockIn(String learnerID) async {
  // Existing validation (unchanged)
  // Existing photo capture (unchanged)
  // Existing signature capture (unchanged)
  
  if (_batchMode) {
    // NEW: Store data for batch submission
    _storeLearnerClockingData(learnerID, 'in');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added to batch ($_pendingBatchCount pending)')),
    );
  } else {
    // EXISTING: Use current API calls (UNCHANGED)
    if (_isOnline) {
      await _clockInOnline(learnerID, ''); // KEEP THIS EXACTLY AS IS
    } else {
      await _clockInOffline(learnerID, clockInTime); // KEEP THIS EXACTLY AS IS
    }
  }
}
```

### 4. Data Storage Method (NEW)
```dart
void _storeLearnerClockingData(String learnerID, String type) {
  final learnerIdInt = int.parse(learnerID);
  
  // Store all data including base64 images
  _batchClockings[learnerID] = {
    'learner_id': learnerID,
    'type': type, // 'in' or 'out'
    'latitude': _currentPosition?.latitude ?? 0.0,
    'longitude': _currentPosition?.longitude ?? 0.0,
    'accuracy': _currentGpsAccuracy ?? 999.0,
    'face_image': base64Encode(_learnerPhotoBytes[learnerIdInt]!),
    'signature_image': base64Encode(_learnerSignatureBytes[learnerIdInt]!),
    'clock_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
    'clock_time': DateFormat('HH:mm:ss').format(DateTime.now()),
    'device_epoch': DateTime.now().millisecondsSinceEpoch ~/ 1000,
  };
  
  setState(() {});
}
```

### 5. Submit Batch Button (NEW)
```dart
floatingActionButton: _batchMode && _pendingBatchCount > 0
  ? FloatingActionButton.extended(
      onPressed: _submitBatch,
      icon: const Icon(Icons.cloud_upload),
      label: Text('Submit Batch ($_pendingBatchCount)'),
      backgroundColor: Colors.blue,
    )
  : null,
```

### 6. Submit Batch Method (NEW)
```dart
Future<void> _submitBatch() async {
  if (_batchClockings.isEmpty) return;
  
  // Show progress dialog
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => const AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Submitting batch...'),
        ],
      ),
    ),
  );
  
  try {
    final syncService = OfflineSyncQueueService();
    await syncService.initialize();
    
    final learnerClockings = _batchClockings.values.toList();
    
    // Use existing batch queue service
    final result = await syncService.queueForBatchProcessing(
      widget.classID,
      learnerClockings,
    );
    
    Navigator.of(context).pop(); // Close progress
    
    if (result['success']) {
      setState(() {
        _batchClockings.clear();
        // Clear photo/signature bytes
        _learnerPhotoBytes.clear();
        _learnerSignatureBytes.clear();
        _learnerHasPhoto.clear();
        _learnerHasSignature.clear();
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Batch submitted: ${result['learners_queued']} learners'),
          backgroundColor: Colors.green,
        ),
      );
    }
  } catch (e) {
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('❌ Batch failed: $e'),
        backgroundColor: Colors.red,
      ),
    );
  }
}
```

---

## 📋 What save_class_batch_clocking.php Does

The PHP batch endpoint processes the batch by:

```php
foreach ($learnerClockings as $clocking) {
  1. Decode base64 images (face + signature)
  2. Save images to /clocking_evidence/ folder
  3. INSERT into manual_clocking table:
     - user_id, class_id, learner_id, clock_date
     - clock_time, type ('in'/'out')
     - latitude, longitude, accuracy
     - batch_id, client_timestamp
  
  4. INSERT into learner_clocking_evidence table:
     - clocking_id, learner_id
     - face_filename, signature_filename
     - batch_id, created_at
}
```

**The batch endpoint reuses the SAME database insert logic that individual endpoints use.**

---

## ✅ Data Preservation Guarantees

### Images
- ✅ **Individual Mode:** Uploaded via `save_manual_clocking_images.php`, saved to `/clocking_evidence/`
- ✅ **Batch Mode:** Sent as base64, decoded by PHP, saved to `/clocking_evidence/`
- ✅ **Result:** Same files in same folder

### manual_clocking Table
- ✅ **Individual Mode:** INSERT via `save_manual_clockin.php`
- ✅ **Batch Mode:** INSERT via batch loop in `save_class_batch_clocking.php`
- ✅ **Result:** Same data structure

### manual_clocking_evidence Table
- ✅ **Individual Mode:** INSERT with image filenames
- ✅ **Batch Mode:** INSERT with image filenames from batch
- ✅ **Result:** Same data structure

### Local SQLite (Offline)
- ✅ **Both Modes:** Offline falls back to local `insertManualClockInOffline()` and `updateManualClockOutOffline()`
- ✅ **Result:** Local data preserved, synced later

---

## 🧪 Testing Requirements

### Test Individual Mode (Must Pass)
1. ✅ Clock in learner → verify 3 API calls
2. ✅ Check server: images in `/clocking_evidence/`
3. ✅ Check MySQL: record in `manual_clocking`
4. ✅ Check MySQL: record in `manual_clocking_evidence`
5. ✅ Clock out learner → verify data updates
6. ✅ Go offline → verify local SQLite storage

### Test Batch Mode (New)
1. ✅ Enable batch mode toggle
2. ✅ Clock in 5 learners → verify no API calls
3. ✅ Verify "Submit Batch (5)" button appears
4. ✅ Click submit → verify 1 API call
5. ✅ Check server: 5×2 images in `/clocking_evidence/`
6. ✅ Check MySQL: 5 records in `manual_clocking`
7. ✅ Check MySQL: 5 records in `learner_clocking_evidence`

### Test Fallback
1. ✅ Batch mode enabled
2. ✅ Collect 3 learners
3. ✅ Submit batch → simulate network error
4. ✅ Verify batch queued in `OfflineSyncQueueService`
5. ✅ Restore network → verify batch syncs

---

## 🚀 Performance Impact

### Before (Individual Mode)
- **30 learners × 3 requests = 90 API calls**
- Time in poor connectivity: ~15-30 minutes
- Battery drain: High (constant radio use)
- Server load: 90 separate PHP processes

### After (Batch Mode)
- **30 learners = 1 API call**
- Time in poor connectivity: ~1-2 minutes
- Battery drain: Low (single radio burst)
- Server load: 1 PHP process (but heavier)

**Improvement: 90× fewer requests!**

---

## 📁 Files Modified

### Dart Files
- `c:\projects\rlmss\lib\signature_geofence_clock_in_page.dart` - Add batch mode

### PHP Files (No Changes)
- `c:\projects\rlmss\mobile\save_manual_clocking_images.php` - UNCHANGED
- `c:\projects\rlmss\mobile\save_manual_clockin.php` - UNCHANGED  
- `c:\projects\rlmss\mobile\save_manual_clockout.php` - UNCHANGED
- `c:\projects\rlmss\mobile\save_class_batch_clocking.php` - ALREADY EXISTS

### Database (No Changes)
- SQLite schema - UNCHANGED
- MySQL schema - UNCHANGED

---

## ⚠️ What NOT to Do

### ❌ DO NOT:
1. Remove existing API call methods
2. Modify `_clockInOnline()` or `_clockOutOnline()` internals
3. Change database schema
4. Break offline mode
5. Remove image upload logic
6. Change existing validation
7. Modify geofencing logic
8. Touch face/signature capture flow

### ✅ DO:
1. Add new batch state variables
2. Add mode toggle switch
3. Add data storage method
4. Add submit batch method
5. Add conditional routing in `_handleClockIn()` / `_handleClockOut()`
6. Keep all existing methods intact

---

## 📝 Summary

**Goal:** Add optional batch mode to reduce network requests

**Method:** Toggle switch + data collection + single batch submission

**Guarantee:** Existing individual mode works EXACTLY as before

**Result:** 90× fewer API requests in batch mode, zero impact on individual mode

**Status:** Implementation in progress via workflow

---

**Last Updated:** October 13, 2026  
**Workflow ID:** wf_85f9bfb8fc64bf4e
