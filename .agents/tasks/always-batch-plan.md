# Implementation Plan: Add Optional Batch Clocking Mode to signature_geofence_clock_in_page.dart

## Overview
Add an OPTIONAL batch clocking mode to the signature + geofence clock-in page. The existing individual-mode flow (three PHP endpoints per learner: save_manual_clocking_images.php, save_manual_clockin.php, save_manual_clockout.php) MUST remain completely unchanged and functional. This is an additive enhancement.

## Context
- **Primary file**: `c:/projects/rlmss/lib/signature_geofence_clock_in_page.dart` (1900+ lines)
- **Batch service**: `c:/projects/rlmss/lib/services/offline_sync_queue_service.dart` has `queueForBatchProcessing` method already implemented
- **Batch endpoint**: `c:/projects/rlmss/mobile/save_class_batch_clocking.php` accepts batch data and inserts into `manual_clocking` AND `manual_clocking_evidence` tables
- **Database tables**: 
  - `manual_clocking` - Stores clock-in/clock-out times and metadata
  - `manual_clocking_evidence` - Stores evidence filenames (face photos and signatures)
- **DO NOT MODIFY**: `clock_in_page.dart`, any database schemas, or any PHP files

## Batch Flow Design Decision
**CHOSEN APPROACH**: "Always Batch" mode where the facilitator collects evidence from ALL learners FIRST, then submits everything in one consolidated request.

**Rationale**: 
1. Reduces network requests from 3N to 1 (where N = number of learners)
2. Better UX for rural connectivity scenarios
3. Leverages existing `queueForBatchProcessing` method
4. Matches behavior of batch PHP endpoint which expects all learner data at once
5. Less error-prone than mixed individual/batch processing

## Implementation Plan

- [ ] 1. **Add batch mode state variables at the top of `_SignatureGeofenceClockInPageState` class**
   
   Add these state variables after the existing `Map<int, bool> _learnerHasSignature = {};` line (around line 67):
   
   ```dart
   // Batch mode state
   bool _isBatchMode = false;
   bool _isSubmittingBatch = false;
   Map<String, Map<String, dynamic>> _batchClockings = {}; // Key: learnerID, Value: clocking data
   ```
   
   **What**: Three boolean/map variables to track batch mode state
   - `_isBatchMode`: Toggle for individual vs batch mode
   - `_isSubmittingBatch`: Prevents double-submission during network request
   - `_batchClockings`: Stores collected clocking data per learner
   
   **Data structure for `_batchClockings` values**:
   ```dart
   {
     'learner_id': String,
     'name': String, // For UI display
     'surname': String, // For UI display
     'type': String, // 'in' or 'out'
     'face_image': String, // base64-encoded
     'signature_image': String, // base64-encoded
     'latitude': double,
     'longitude': double,
     'accuracy': double,
     'clock_date': String, // 'yyyy-MM-dd'
     'timestamp': String, // ISO 8601
     'idempotency_key': String // UUID v4 generated at capture time
   }
   ```
   
   Files: `c:/projects/rlmss/lib/signature_geofence_clock_in_page.dart`
   
   Verify: Run `flutter analyze` and confirm no syntax errors in the modified file.

- [ ] 2. **Add batch mode toggle switch to AppBar**
   
   Modify the `build` method's `AppBar` widget (around line 1658) to add a switch BEFORE the connectivity indicator:
   
   ```dart
   actions: [
     // Batch mode toggle
     Row(
       mainAxisSize: MainAxisSize.min,
       children: [
         const Text('Batch', style: TextStyle(fontSize: 12)),
         Switch(
           value: _isBatchMode,
           onChanged: (value) {
             setState(() {
               _isBatchMode = value;
               if (!value) {
                 // Clear batch data when switching back to individual mode
                 _batchClockings.clear();
               }
             });
           },
           activeColor: Colors.white,
         ),
       ],
     ),
     // Connectivity indicator (existing code)
     Padding(
       padding: const EdgeInsets.symmetric(horizontal: 16),
       child: Icon(
         _isOnline ? Icons.cloud_done : Icons.cloud_off,
         color: _isOnline ? Colors.white : Colors.red[200],
       ),
     ),
   ],
   ```
   
   **What**: Add a labeled switch widget to toggle batch mode on/off. When turned off, any collected batch data is cleared.
   
   Files: `c:/projects/rlmss/lib/signature_geofence_clock_in_page.dart`
   
   Verify: Run `flutter analyze` and then `flutter build apk --debug` to confirm the app builds successfully with the new UI.

- [ ] 3. **Add batch status banner below geofencing status**
   
   In the `build` method's `body: Column` children (around line 1670, after the geofencing banner), add:
   
   ```dart
   // Batch mode status banner
   if (_isBatchMode)
     Container(
       width: double.infinity,
       padding: const EdgeInsets.all(12),
       color: Colors.blue[50],
       child: Row(
         children: [
           const Icon(Icons.playlist_add_check, color: Colors.blue),
           const SizedBox(width: 8),
           Expanded(
             child: Text(
               'Batch Mode: ${_batchClockings.length} learner(s) collected',
               style: TextStyle(
                 color: Colors.blue[900],
                 fontWeight: FontWeight.bold,
               ),
             ),
           ),
           if (_batchClockings.isNotEmpty)
             TextButton.icon(
               onPressed: () {
                 setState(() => _batchClockings.clear());
               },
               icon: const Icon(Icons.clear_all, size: 16),
               label: const Text('Clear'),
               style: TextButton.styleFrom(
                 foregroundColor: Colors.red,
               ),
             ),
         ],
       ),
     ),
   ```
   
   **What**: Blue banner showing how many learners have been collected and a clear button.
   
   Files: `c:/projects/rlmss/lib/signature_geofence_clock_in_page.dart`
   
   Verify: Run `flutter analyze` and visually test by toggling batch mode on/off in the running app.

- [ ] 4. **Modify `_handleClockIn` to store batch data instead of processing immediately**
   
   In the `_handleClockIn` method (starts around line 824), replace the ENTIRE BODY after the preliminary checks (profile/documents validation) with a conditional:
   
   ```dart
   Future<void> _handleClockIn(String learnerID) async {
     if (_isClockingIn[learnerID] == true) return;
   
     // CRITICAL: Verify device time (KEEP EXISTING)
     final timeOk = await TimezoneValidator.ensureCorrectTime(context);
     if (!timeOk) {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(
           content: Text('Clock-in cancelled: Device time must be corrected first'),
           backgroundColor: Colors.red,
           duration: Duration(seconds: 3),
         ),
       );
       return;
     }
   
     // Check if learner already clocked in today (KEEP EXISTING)
     final currentDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
     if (clockInTimes[learnerID]?.isNotEmpty == true) {
       ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(
           content: Text('Learner already clocked in today at ${clockInTimes[learnerID]}'),
           backgroundColor: Colors.orange,
         ),
       );
       return;
     }
   
     setState(() => _isClockingIn[learnerID] = true);
   
     try {
       final profileOk = await ensureLearnerProfileCompleteForClockIn(learnerID);
       if (!profileOk) return;
   
       final docsOk = await ensureLearnerDocumentsCompleteForClockIn(learnerID);
       if (!docsOk) return;
   
       // NEW: Branch based on mode
       if (_isBatchMode) {
         await _storeLearnerClockingData(learnerID, 'in');
       } else {
         // EXISTING INDIVIDUAL MODE - KEEP EXACTLY AS IS
         // (Keep all existing clock-in code for individual mode)
         final clockInTime = DateFormat('HH:mm:ss').format(DateTime.now());
         if (_isOnline) {
           await _clockInOnline(learnerID, '');
         } else {
           await _clockInOffline(learnerID, clockInTime);
         }
         setState(() {
           clockInTimes[learnerID] = clockInTime;
         });
       }
     } catch (e) {
       print('[SIGNATURE_GEO] Clock-in error: $e');
       ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text('Clock-in failed: $e')),
       );
     } finally {
       setState(() => _isClockingIn[learnerID] = false);
     }
   }
   ```
   
   **What**: Add mode check after validation. In batch mode, call `_storeLearnerClockingData`. In individual mode, keep EXACT existing behavior.
   
   **CRITICAL**: The individual mode branch must remain EXACTLY as it currently is (lines 861-917 of existing code). Do NOT modify `_clockInOnline` or `_clockInOffline` methods.
   
   Files: `c:/projects/rlmss/lib/signature_geofence_clock_in_page.dart`
   
   Verify: Run `flutter analyze` and test both modes: individual clock-in should work exactly as before, batch mode should show "stored" message.

- [ ] 5. **Modify `_handleClockOut` to store batch data instead of processing immediately**
   
   Similarly, modify `_handleClockOut` method (starts around line 920) with the same conditional pattern:
   
   ```dart
   Future<void> _handleClockOut(String learnerID) async {
     if (_isClockingIn[learnerID] == true) return;
   
     // Check if learner hasn't clocked in yet (KEEP EXISTING)
     if (clockInTimes[learnerID]?.isEmpty != false) {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(
           content: Text('Learner must clock in first before clocking out'),
           backgroundColor: Colors.orange,
         ),
       );
       return;
     }
   
     // Check if learner already clocked out (KEEP EXISTING)
     if (clockOutTimes[learnerID]?.isNotEmpty == true) {
       ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(
           content: Text('Learner already clocked out today at ${clockOutTimes[learnerID]}'),
           backgroundColor: Colors.orange,
         ),
       );
       return;
     }
   
     setState(() => _isClockingIn[learnerID] = true);
   
     try {
       // NEW: Branch based on mode
       if (_isBatchMode) {
         await _storeLearnerClockingData(learnerID, 'out');
       } else {
         // EXISTING INDIVIDUAL MODE - KEEP EXACTLY AS IS
         final clockOutTime = DateFormat('HH:mm:ss').format(DateTime.now());
         final clockDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
         if (_isOnline) {
           await _clockOutOnline(learnerID, '', synced: false);
         } else {
           await _clockOutOffline(learnerID, clockOutTime, clockDate);
         }
         setState(() {
           clockOutTimes[learnerID] = clockOutTime;
         });
       }
     } catch (e) {
       print('[SIGNATURE_GEO] Clock-out error: $e');
       ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text('Clock-out failed: $e')),
       );
     } finally {
       setState(() => _isClockingIn[learnerID] = false);
     }
   }
   ```
   
   **What**: Same pattern as clock-in - batch mode stores data, individual mode processes immediately.
   
   Files: `c:/projects/rlmss/lib/signature_geofence_clock_in_page.dart`
   
   Verify: Run `flutter analyze` and test both modes.

- [ ] 6. **Add `_storeLearnerClockingData` method to collect evidence and store in batch map**
   
   Add this new private method after the `_handleClockOut` method (around line 1010):
   
   ```dart
   /// Batch mode: Store learner clocking data for later submission
   Future<void> _storeLearnerClockingData(String learnerID, String type) async {
     // Step 1: Get learner details for display
     final learner = widget.learners.firstWhere(
       (l) => l['LearnerID'].toString() == learnerID,
       orElse: () => {'Name': 'Unknown', 'Surname': 'Learner'},
     );
     final learnerName = '${learner['Name']} ${learner['Surname']}';
   
     // Step 2: Capture face photo
     final learnerIdInt = int.parse(learnerID);
     
     setState(() {
       _currentLearnerForCapture = learnerID;
       _isClockInProcess = (type == 'in');
     });
   
     await Navigator.of(context).push(
       MaterialPageRoute(
         builder: (context) => SmartFramedCameraCapture(
           learnerID: learnerIdInt,
           learnerName: learnerName,
           onCapture: (File imageFile, Uint8List imageBytes) {
             setState(() {
               _learnerPhotoFiles[learnerIdInt] = imageFile;
               _learnerPhotoBytes[learnerIdInt] = imageBytes;
               _learnerHasPhoto[learnerIdInt] = true;
             });
           },
         ),
       ),
     );
   
     // Check if photo was captured
     if (!_learnerHasPhoto.containsKey(learnerIdInt) ||
         !_learnerPhotoBytes.containsKey(learnerIdInt)) {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(
           content: Text('Photo capture cancelled. Batch collection aborted.'),
           backgroundColor: Colors.orange,
         ),
       );
       return;
     }
   
     // Step 3: Capture signature
     _signatureController.clear();
     final signatureResult = await showDialog<bool>(
       context: context,
       barrierDismissible: false,
       builder: (context) => AlertDialog(
         title: Text('Clock ${type == 'in' ? 'In' : 'Out'} - Signature'),
         content: SizedBox(
           height: 350,
           width: 300,
           child: Column(
             children: [
               Container(
                 padding: const EdgeInsets.all(8),
                 margin: const EdgeInsets.only(bottom: 8),
                 decoration: BoxDecoration(
                   color: Colors.purple[50],
                   borderRadius: BorderRadius.circular(8),
                   border: Border.all(color: Colors.purple, width: 2),
                 ),
                 child: const Row(
                   children: [
                     Icon(Icons.photo_camera, color: Colors.purple),
                     SizedBox(width: 8),
                     Expanded(
                       child: Text(
                         'Photo captured ✓',
                         style: TextStyle(
                           color: Colors.purple,
                           fontWeight: FontWeight.bold,
                           fontSize: 12,
                         ),
                       ),
                     ),
                   ],
                 ),
               ),
               Expanded(
                 child: Container(
                   decoration: BoxDecoration(
                     border: Border.all(color: Colors.grey),
                     borderRadius: BorderRadius.circular(8),
                   ),
                   child: Signature(
                     controller: _signatureController,
                     backgroundColor: Colors.white,
                   ),
                 ),
               ),
               const SizedBox(height: 10),
               ElevatedButton(
                 onPressed: () => _signatureController.clear(),
                 child: const Text('Clear Signature'),
               ),
             ],
           ),
         ),
         actions: [
           TextButton(
             onPressed: () => Navigator.of(context).pop(false),
             child: const Text('Cancel'),
           ),
           ElevatedButton(
             onPressed: () async {
               if (_signatureController.isEmpty) {
                 ScaffoldMessenger.of(context).showSnackBar(
                   const SnackBar(content: Text('Please provide a signature')),
                 );
                 return;
               }
               Navigator.of(context).pop(true);
             },
             child: const Text('Confirm'),
           ),
         ],
       ),
     );
   
     if (signatureResult != true) {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(
           content: Text('Signature capture cancelled. Batch collection aborted.'),
           backgroundColor: Colors.orange,
         ),
       );
       return;
     }
   
     // Step 4: Store signature bytes
     try {
       final signatureBytes = await _signatureController.toPngBytes();
       if (signatureBytes != null) {
         _learnerSignatureBytes[learnerIdInt] = signatureBytes;
         _learnerHasSignature[learnerIdInt] = true;
       }
     } catch (e) {
       print('[SIGNATURE_GEO] Error capturing signature: $e');
       return;
     }
   
     // Step 5: Store in batch map
     final uuid = const Uuid();
     final clockDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
     final timestamp = DateTime.now().toUtc().toIso8601String();
   
     _batchClockings[learnerID] = {
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
       'timestamp': timestamp,
       'idempotency_key': uuid.v4(),
     };
   
     setState(() {});
   
     ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(
         content: Text(
           '✓ ${learner['Name']} ${learner['Surname']} - ${type == 'in' ? 'Clock-in' : 'Clock-out'} collected',
         ),
         backgroundColor: Colors.green,
         duration: const Duration(seconds: 2),
       ),
     );
   }
   ```
   
   **What**: Collects face photo + signature, stores in `_batchClockings` map with all required metadata. Does NOT submit to server yet.
   
   **Dependencies**: Requires `package:uuid/uuid.dart` import. Check if already imported; if not, add: `import 'package:uuid/uuid.dart';`
   
   Files: `c:/projects/rlmss/lib/signature_geofence_clock_in_page.dart`
   
   Verify: Run `flutter analyze`. Test batch mode collection - should store data and show confirmation message without network calls.

- [ ] 7. **Add FloatingActionButton to submit batch when data is collected**
   
   In the `build` method's `Scaffold` widget (around line 1900), add a `floatingActionButton` property:
   
   ```dart
   return Scaffold(
     appBar: AppBar(...),
     body: Column(...),
     floatingActionButton: _isBatchMode && _batchClockings.isNotEmpty
       ? FloatingActionButton.extended(
           onPressed: _isSubmittingBatch ? null : _submitBatch,
           icon: _isSubmittingBatch
               ? const SizedBox(
                   width: 20,
                   height: 20,
                   child: CircularProgressIndicator(
                     strokeWidth: 2,
                     valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                   ),
                 )
               : const Icon(Icons.upload),
           label: Text(_isSubmittingBatch
               ? 'Submitting...'
               : 'Submit Batch (${_batchClockings.length})'),
           backgroundColor: _isSubmittingBatch ? Colors.grey : Colors.blue,
         )
       : null,
   );
   ```
   
   **What**: Floating action button appears only in batch mode when data is collected. Shows loading state during submission.
   
   Files: `c:/projects/rlmss/lib/signature_geofence_clock_in_page.dart`
   
   Verify: Run `flutter analyze`. Visually test that FAB appears/disappears based on mode and data state.

- [ ] 8. **Add `_submitBatch` method to send batch data using `queueForBatchProcessing`**
   
   Add this new private method after `_storeLearnerClockingData` (around line 1200):
   
   ```dart
   /// Submit collected batch clockings using OfflineSyncQueueService
   Future<void> _submitBatch() async {
     if (_batchClockings.isEmpty) {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(
           content: Text('No learner clockings collected'),
           backgroundColor: Colors.orange,
         ),
       );
       return;
     }
   
     setState(() => _isSubmittingBatch = true);
   
     try {
       // Prepare learner clockings list for batch service
       final learnerClockings = _batchClockings.values.toList();
   
       // Call existing queueForBatchProcessing method
       final syncService = OfflineSyncQueueService();
       final result = await syncService.queueForBatchProcessing(
         widget.classID,
         learnerClockings,
       );
   
       if (result['success'] == true) {
         // Update local state based on submitted data
         for (final clocking in learnerClockings) {
           final learnerID = clocking['learner_id'] as String;
           if (clocking['type'] == 'in') {
             setState(() {
               clockInTimes[learnerID] = DateFormat('HH:mm:ss').format(DateTime.now());
             });
           } else if (clocking['type'] == 'out') {
             setState(() {
               clockOutTimes[learnerID] = DateFormat('HH:mm:ss').format(DateTime.now());
             });
           }
         }
   
         // Clear batch data and evidence maps
         _batchClockings.clear();
         _learnerPhotoFiles.clear();
         _learnerPhotoBytes.clear();
         _learnerSignatureBytes.clear();
         _learnerHasPhoto.clear();
         _learnerHasSignature.clear();
         _signatureController.clear();
   
         setState(() {});
   
         // Show success message
         final wasProcessedImmediately = result['processed_immediately'] == true;
         final message = wasProcessedImmediately
             ? '✅ Batch submitted successfully (${learnerClockings.length} learners)'
             : '📤 Batch queued for sync (${learnerClockings.length} learners)';
   
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(
             content: Text(message),
             backgroundColor: Colors.green,
             duration: const Duration(seconds: 3),
           ),
         );
       } else {
         throw Exception(result['message'] ?? 'Batch submission failed');
       }
     } catch (e) {
       print('[SIGNATURE_GEO] Batch submission error: $e');
       ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(
           content: Text('Batch submission failed: $e'),
           backgroundColor: Colors.red,
           duration: const Duration(seconds: 4),
         ),
       );
     } finally {
       setState(() => _isSubmittingBatch = false);
     }
   }
   ```
   
   **What**: Converts batch map to list, calls `queueForBatchProcessing`, updates local state, clears batch data. Handles both immediate processing and queuing scenarios.
   
   Files: `c:/projects/rlmss/lib/signature_geofence_clock_in_page.dart`
   
   Verify: Run `flutter analyze`. Test batch submission in online and offline modes. Check that learner clock times are updated in the UI after submission.

- [ ] 9. **Add import for uuid package if not already present**
   
   Check the imports section at the top of the file (lines 1-30). If `package:uuid/uuid.dart` is not imported, add it:
   
   ```dart
   import 'package:uuid/uuid.dart';
   ```
   
   The uuid package is required by `_storeLearnerClockingData` to generate idempotency keys.
   
   Files: `c:/projects/rlmss/lib/signature_geofence_clock_in_page.dart`
   
   Verify: Check `pubspec.yaml` dependencies section to confirm uuid package is listed. If not, add `uuid: ^4.5.1` to dependencies and run `flutter pub get`.

- [ ] 10. **Final integration test: Test both individual and batch modes end-to-end**
   
   Perform comprehensive manual testing:
   
   **Individual mode (existing behavior - MUST NOT BREAK)**:
   1. Launch app, navigate to signature geofence clock-in page
   2. Ensure batch mode switch is OFF
   3. Select a learner, capture photo + signature, clock in
   4. Verify data is immediately sent to `save_manual_clocking_images.php`, `save_manual_clockin.php`
   5. Clock out same learner - verify sends to `save_manual_clockout.php`
   6. Check database: records should exist in `manual_clocking` and `manual_clocking_evidence` tables
   
   **Batch mode (new behavior)**:
   1. Toggle batch mode switch ON
   2. Blue banner should appear showing "0 learner(s) collected"
   3. Select first learner, capture photo + signature for clock-in
   4. Verify: NO network requests sent, banner shows "1 learner(s) collected"
   5. Select second learner, capture photo + signature for clock-in
   6. Verify: Banner shows "2 learner(s) collected"
   7. FAB should appear: "Submit Batch (2)"
   8. Click FAB - verify single request to `save_class_batch_clocking.php`
   9. Check database: both records should exist in both tables
   10. Verify UI updates: both learners show clock-in times
   11. Clear batch, toggle batch mode OFF, toggle back ON
   12. Collect clock-out data for both learners, submit batch
   13. Verify clock-out times appear in UI
   
   **Offline batch mode**:
   1. Disable device network
   2. Collect 2 learner clock-ins in batch mode
   3. Submit batch - should show "Batch queued for sync"
   4. Enable network
   5. Verify offline sync queue processes the batch
   6. Check server database for records
   
   Files: All modified files in this plan
   
   Verify: All scenarios pass. Individual mode behavior is UNCHANGED. Batch mode reduces requests from 3N to 1. No errors in console logs.

## Confirmation Checklist

- ✓ **No database columns added**: Plan does not modify any schema
- ✓ **No PHP files modified**: Plan does not touch `save_manual_clocking_images.php`, `save_manual_clockin.php`, `save_manual_clockout.php`, or `save_class_batch_clocking.php`
- ✓ **No changes to clock_in_page.dart**: Plan only modifies `signature_geofence_clock_in_page.dart`
- ✓ **Individual mode unchanged**: Existing `_clockInOnline`, `_clockOutOnline`, `_clockInOffline`, `_clockOutOffline` methods are NOT modified
- ✓ **Uses existing batch service**: Calls `OfflineSyncQueueService.queueForBatchProcessing` which already exists
- ✓ **Matches batch endpoint expectations**: Data structure matches what `save_class_batch_clocking.php` expects
- ✓ **Preserves evidence**: Face photos and signatures are collected and sent in batch payload
- ✓ **Maintains geofencing**: All existing geofencing checks remain active
- ✓ **Backward compatible**: Toggle switch defaults to OFF (individual mode)

## Dependencies

**Required packages** (verify in pubspec.yaml):
- `uuid: ^4.5.1` (or any 4.x version) - for generating idempotency keys
- All other required packages are already present in the project

## Build and Test Commands

**Build command**: `flutter build apk --release` (or `flutter build apk --debug` for testing)

**Analysis command**: `flutter analyze`

**Pub get command**: `flutter pub get` (run if adding uuid dependency)

## Notes

1. **Why "always batch"**: The batch PHP endpoint expects all learner data in one request. Mixing individual + batch would require maintaining two parallel code paths and handling partial failures. The always-batch approach is simpler and more reliable.

2. **Idempotency**: Each learner clocking in the batch gets a unique UUID v4 key generated at capture time. The batch itself also has a batch ID. This ensures deduplication even if the batch is resubmitted.

3. **Error handling**: If batch submission fails (network error, server error), data remains in `_batchClockings` and can be resubmitted. The offline sync queue handles retry logic.

4. **UI feedback**: Batch mode provides clear visual feedback at every step: banner shows count, FAB shows submission progress, snackbars confirm success/failure.

5. **Data preservation**: Photos and signatures are base64-encoded in the batch payload, matching the format expected by `save_class_batch_clocking.php` which decodes and saves them to `manual_clocking_evidence`.

6. **Geofencing enforcement**: The existing geofencing checks in `_showSignatureDialog` remain active. Learners outside the 50m radius cannot have their evidence collected in batch mode either.
