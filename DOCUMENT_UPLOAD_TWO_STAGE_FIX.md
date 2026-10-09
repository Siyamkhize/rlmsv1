# Two-Stage Document Upload Fix - Implementation Plan

## Date: September 23, 2026

## Problem
User reported that the document check shows Stage 2 (detailed status with Pending/Declined) even when documents are "Not Uploaded", instead of showing Stage 1 (simple upload dialog).

## Root Cause
My previous edits broke the file structure by:
1. Leaving orphaned code outside methods after extracting dialogs
2. Incomplete method replacements leaving duplicate code blocks
3. Missing `_handleDocumentUpload` method implementation

## Solution Applied
1. **Restored clock_in_page.dart** from backup (`clock_in_page copy.dart`)
2. **Restored backup_clock_in_page.dart** from git to clean state
3. Files now compile successfully

## Next Steps - Proper Implementation

### For clock_in_page.dart:
The file already has the old document check at line ~3413. Need to:
1. Find the existing `_checkLearnerDocumentCompleteness` or similar method
2. Replace it with two-stage logic:
   - Stage 1: If ANY document is "Not Uploaded" → show simple dialog with "Scan Next Document" button
   - Stage 2: If ALL uploaded but some Pending/Declined → show detailed status dialog
3. Add `_showMissingDocumentsDialog` method
4. Add `_showPendingDeclinedDialog` method
5. Add `_handleDocumentUpload` method (navigates to LearnerDetailsPage)

### For backup_clock_in_page.dart:
Similar implementation needed since it's used as the backup clock-in page.

## Two-Stage Logic Flow

```dart
Future<bool> _ensureLearnerDocumentsComplete(String learnerId) async {
  while (true) {
    final docStatuses = await _getDetailedDocumentStatuses(learnerId);
    
    if (docStatuses['allApproved'] == true) {
      return true;
    }

    final problemDocs = docStatuses['documents'] ?? [];
    
    // KEY LOGIC: Check if ANY documents are "Not Uploaded"
    final hasNotUploaded = problemDocs.any((doc) => doc['status'] == 'Not Uploaded');
    
    Map<String, dynamic>? action;
    
    if (hasNotUploaded) {
      // Stage 1: Simple dialog for missing documents
      action = await _showMissingDocumentsDialog(...);
    } else {
      // Stage 2: Detailed dialog for Pending/Declined
      action = await _showPendingDeclinedDialog(...);
    }
    
    if (action?['action'] == 'upload' || action?['action'] == 'reupload') {
      await _handleDocumentUpload(learnerId, action['document'], ...);
      continue;
    }
    
    return false; // User cancelled
  }
}
```

## Status
- ✅ Files restored and compiling
- ⏳ Two-stage logic needs to be implemented
- ⏳ Testing required after implementation
- ⏳ APK rebuild required

## Files Modified
- `lib/clock_in_page.dart` - Restored from backup
- `lib/backup_clock_in_page.dart` - Restored from git
