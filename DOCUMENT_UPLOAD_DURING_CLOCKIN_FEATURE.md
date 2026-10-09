# Document Upload During Clock-In Feature

## Date: September 23, 2026

## Feature Overview

Added the ability for learners to upload missing or declined documents directly from the clock-in blocked dialog, without having to exit and navigate to document management.

---

## Problem Solved

**Before:**
- When learners had missing or declined documents, they were blocked from clocking in
- They had to:
  1. Exit clock-in
  2. Navigate to document management
  3. Upload documents
  4. Return to clock-in
  5. Try again

**After:**
- Learners can upload documents **directly from the clock-in dialog**
- Two ways to upload:
  1. Click "Upload" button next to individual documents
  2. Click "Scan Next Document" to upload the first missing document

---

## Features Implemented

### 1. **Individual Document Upload Buttons**

Each document now shows an action button based on its status:

#### Not Uploaded Documents
- **Blue "Upload" button** appears
- Clicking opens upload options (Scan or Gallery)
- Uploads document and re-checks status

#### Declined Documents
- **Orange "Re-upload" button** appears  
- Clicking opens upload options (Scan or Gallery)
- Re-uploads document with new version

#### Pending Documents
- **No button** (waiting for approval)
- Shows status as "Pending"

#### Approved Documents
- **Not shown in dialog** (only problem docs appear)

---

### 2. **"Scan Next Document" Button**

- Appears at bottom of dialog if ANY document is "Not Uploaded"
- Automatically selects the **first missing document**
- Opens scanner/upload flow immediately
- After upload, dialog refreshes to show updated status
- User can continue uploading remaining documents

---

### 3. **Upload Methods**

When user clicks "Upload" or "Re-upload", they can choose:

#### Option 1: Scan Document
- Uses device camera
- Multi-page scanning support
- Auto-enhances and creates PDF
- Best for physical documents

#### Option 2: Choose from Gallery
- Picks existing photo or PDF
- Validates file size (10KB - 5MB)
- Quick for pre-scanned documents

---

## User Flow

### Scenario 1: Missing Documents (Not Uploaded)

```
1. Learner clicks "Clock In"
2. Dialog shows: "Clock-In Blocked"
3. Shows all 3 required documents:
   - ID Document: Not Uploaded [Upload]
   - Qualifications: Not Uploaded [Upload]
   - Proof of Residence: Not Uploaded [Upload]

4. Options:
   A) Click "Upload" on specific document
   B) Click "Scan Next Document" (uploads first missing)

5. Choose upload method (Scan or Gallery)
6. Document uploads → Status changes to "Pending"
7. Dialog refreshes automatically
8. Continue uploading remaining documents
9. When all uploaded → Close dialog → Wait for approval
```

### Scenario 2: Declined Documents

```
1. Learner clicks "Clock In"
2. Dialog shows: "Clock-In Blocked"
3. Shows declined documents:
   - ID Document: Declined [Re-upload]
     Reason: Image unclear

4. Click "Re-upload"
5. Choose upload method (Scan or Gallery)
6. New version uploads → Status changes to "Pending"
7. Dialog refreshes
8. Close dialog → Wait for approval
```

### Scenario 3: Mix of Statuses

```
1. Dialog shows:
   - ID Document: Pending (no button)
   - Qualifications: Declined [Re-upload]
   - Proof of Residence: Not Uploaded [Upload]

2. Can upload/re-upload as needed
3. "Scan Next Document" button appears (for Proof of Residence)
4. Upload missing/declined docs
5. All become "Pending" → Wait for admin approval
```

---

## Technical Implementation

### Files Modified

1. **lib/clock_in_page.dart**
   - Added `_handleDocumentUpload()` method
   - Added `_pickAndUploadDocument()` method
   - Updated clock-in blocked dialog UI
   - Added individual document upload buttons
   - Added "Scan Next Document" button logic

### New Imports Added

```dart
import 'dart:io';
import 'package:image_picker/image_picker.dart';
```

### Key Methods

#### `_handleDocumentUpload(String learnerId, String docName, {bool isReupload})`
- Shows upload method dialog (Scan vs Gallery)
- Handles success/failure feedback
- Re-checks document status after upload

#### `_pickAndUploadDocument(String learnerId, String docName)`
- Picks image from gallery
- Validates file size
- Uploads to server
- Returns success/failure

#### `_scanAndSaveDocument(String learnerId, String documentName)`
- Already existed
- Now reused for document scanner flow
- Handles multi-page scanning

---

## UI Design

### Dialog Title
```
🚫 Clock-In Blocked
```

### Warning Banner
```
⚠️ All 3 required documents must be approved
```

### Document Cards

#### Not Uploaded Example
```
┌─────────────────────────────────────────┐
│ 📄 ID Document                          │
│    Not Uploaded                         │
│                            [Upload →]   │
└─────────────────────────────────────────┘
```

#### Declined Example
```
┌─────────────────────────────────────────┐
│ ❌ ID Document                          │
│    Declined                             │
│                         [Re-upload →]   │
│ ┌─────────────────────────────────────┐ │
│ │ Reason: Image too blurry            │ │
│ └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

#### Pending Example
```
┌─────────────────────────────────────────┐
│ ⏳ Qualifications                       │
│    Pending                              │
└─────────────────────────────────────────┘
```

### Error Message
```
❌ You cannot clock in until all documents are approved.
```

### Info Message
```
ℹ️ Please contact your administrator for document approval.
```

### Action Buttons
```
[📄 Scan Next Document]  [Cancel]
```

---

## Error Handling

### File Size Validation
- **Minimum**: 10KB (prevents corrupt/empty files)
- **Maximum**: 5MB (prevents server overload)
- Shows clear error messages for violations

### Upload Failure
- Shows error snackbar with red background
- User can retry immediately
- Dialog stays open for corrections

### No File Selected
- Silently returns to dialog
- No error shown (user cancelled intentionally)

### Network Errors
- Shows "Failed to upload" message
- User can retry when online

---

## Benefits

### For Learners
✅ Upload documents without leaving clock-in screen  
✅ See exactly which documents need attention  
✅ Know why documents were declined  
✅ Quick "Scan Next Document" workflow  
✅ Upload multiple documents in one session

### For Facilitators
✅ Less learner frustration  
✅ Faster document submission  
✅ Fewer support requests  
✅ Clearer learner feedback

### For System
✅ Improved user experience  
✅ Reduced navigation complexity  
✅ Better document completion rates  
✅ Streamlined workflows

---

## Testing Checklist

### Test 1: Upload Missing Document
- [ ] Clock in with missing documents
- [ ] Click "Upload" button
- [ ] Choose "Scan Document"
- [ ] Scan document
- [ ] Verify status changes to "Pending"
- [ ] Dialog refreshes automatically

### Test 2: Scan Next Document
- [ ] Clock in with 2+ missing documents
- [ ] Click "Scan Next Document"
- [ ] Verify first missing document is selected
- [ ] Upload document
- [ ] Verify "Scan Next Document" still shows (for 2nd doc)

### Test 3: Re-upload Declined Document
- [ ] Clock in with declined document
- [ ] See decline reason displayed
- [ ] Click "Re-upload"
- [ ] Choose "Choose from Gallery"
- [ ] Select better image
- [ ] Verify re-upload success

### Test 4: File Size Validation
- [ ] Try uploading file > 5MB
- [ ] Verify error message
- [ ] Try uploading file < 10KB
- [ ] Verify error message

### Test 5: Mixed Document Statuses
- [ ] Have 1 Pending, 1 Declined, 1 Not Uploaded
- [ ] Verify correct buttons show
- [ ] Upload/re-upload as needed
- [ ] Verify all update correctly

### Test 6: Upload Cancellation
- [ ] Click "Upload"
- [ ] Click "Cancel" on method selection
- [ ] Verify dialog remains open
- [ ] Can try again

### Test 7: Network Offline
- [ ] Turn off internet
- [ ] Try to upload document
- [ ] Verify appropriate error
- [ ] Turn on internet
- [ ] Retry successfully

---

## Future Enhancements

### Possible Improvements
1. **Bulk Upload**: Upload all missing documents at once
2. **Camera Preview**: Show document preview before upload
3. **Progress Indicator**: Show upload progress percentage
4. **Local Queue**: Queue uploads for later if offline
5. **Document Templates**: Show examples of acceptable documents
6. **Auto-retry**: Retry failed uploads automatically when online

---

## Status

✅ **COMPLETE** - All features implemented and ready for testing

### Next Steps
1. Test all scenarios above
2. Verify upload endpoints work correctly
3. Check admin approval workflow
4. Build and deploy new APK

---

## Dependencies

- `image_picker` - Already in pubspec.yaml
- `http` - Already in pubspec.yaml
- `flutter_doc_scanner` - Already in pubspec.yaml

No new dependencies required!

---

## Notes

- Upload uses existing `upload_learner_document.php` endpoint
- Document scanning uses existing `_scanAndSaveDocument()` method
- Gallery picker validates files before upload
- Status refresh happens automatically after each upload
- Users can upload multiple documents in one session
- Dialog only closes when user clicks "Cancel"

---

## Success Metrics

After implementation, track:
- Document upload completion rate
- Time to complete clock-in
- Number of clock-in blocks due to documents
- User satisfaction with upload process
- Support tickets related to documents

---

## Documentation

Refer users to:
- This document for feature explanation
- `CLOCK_IN_ONLY_LEARNERS_GUIDE.md` for learner instructions
- `FACILITATOR_USER_MANUAL_AND_TRAINING.md` for approval workflow

---

## Support

If issues occur:
1. Check upload endpoint is accessible
2. Verify file size limits are correct
3. Check server storage capacity
4. Verify admin approval workflow works
5. Test with different document types

**Implementation Date:** September 23, 2026  
**Feature Status:** Ready for Testing  
**Build Required:** Yes - rebuild APK after testing
