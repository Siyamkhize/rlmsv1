# Mandatory Document Upload Feature - Complete

## Date: September 23, 2026

## Summary

Implemented a **two-stage document upload dialog** during clock-in that helps learners upload missing mandatory documents directly from the clock-in flow.

---

## The 3 Mandatory Documents

For clock-in, these 3 documents **MUST** be approved:

1. ✅ **ID Document**
2. ✅ **Qualifications** 
3. ✅ **Proof of Residence**

---

## Two-Stage Approach

### Stage 1: Missing Documents (Not Uploaded)

**When to show:** If ANY of the 3 mandatory documents are "Not Uploaded"

**Dialog shown:**
```
⚠️ Missing Required Documents

This learner has missing required documents. 
Scan all missing document(s) before clock-in.

• ID Document
• Qualifications  
• Proof of Residence

[Cancel]  [Scan Next Document]
```

**Behavior:**
- Shows list of missing documents
- "Scan Next Document" button uploads first missing document
- After upload, dialog refreshes automatically
- Continues until all 3 are uploaded

---

### Stage 2: Pending/Declined Documents

**When to show:** If all 3 documents are uploaded BUT some are Pending or Declined

**Dialog shown:**
```
🚫 Clock-In Blocked

⚠️ All 3 required documents must be approved

Document statuses:
┌────────────────────────────────┐
│ ⏳ ID Document                 │
│    Pending                     │
└────────────────────────────────┘

┌────────────────────────────────┐
│ ❌ Qualifications              │
│    Declined                    │
│    [Re-upload]                 │
│ Reason: Image too blurry       │
└────────────────────────────────┘

┌────────────────────────────────┐
│ ⏳ Proof of Residence          │
│    Pending                     │
└────────────────────────────────┘

❌ You cannot clock in until all documents are approved.
ℹ️ Please contact your administrator for document approval.

[Cancel]
```

**Behavior:**
- Shows detailed status of each document
- Pending documents: show status (waiting for approval)
- Declined documents: show "Re-upload" button + decline reason
- User can re-upload declined documents
- User must wait for admin approval for pending docs

---

## User Flow

### Scenario 1: Learner has NO documents uploaded

```
1. Click "Clock In"
2. See Stage 1 dialog: "Missing Required Documents"
   - ID Document
   - Qualifications
   - Proof of Residence
3. Click "Scan Next Document"
4. Scans ID Document → Status changes to "Pending"
5. Dialog refreshes, still shows Stage 1 (2 documents still missing)
6. Click "Scan Next Document" again
7. Scans Qualifications → Status changes to "Pending"
8. Dialog refreshes, still shows Stage 1 (1 document still missing)
9. Click "Scan Next Document" again
10. Scans Proof of Residence → Status changes to "Pending"
11. All 3 uploaded! Dialog switches to Stage 2
12. Stage 2 shows all 3 as "Pending"
13. User clicks "Cancel"
14. Waits for admin to approve all 3 documents
```

### Scenario 2: Learner has 1 document missing

```
1. Click "Clock In"
2. See Stage 1 dialog: "Missing Required Documents"
   - Proof of Residence (only one missing)
3. Click "Scan Next Document"
4. Scans Proof of Residence → Status changes to "Pending"
5. All 3 uploaded! Dialog switches to Stage 2
6. Stage 2 shows statuses:
   - ID Document: Pending
   - Qualifications: Pending
   - Proof of Residence: Pending
7. User clicks "Cancel" and waits for approval
```

### Scenario 3: All uploaded, one declined

```
1. Click "Clock In"
2. See Stage 2 dialog: "Clock-In Blocked"
3. Statuses shown:
   - ID Document: Approved ✅ (not shown in dialog)
   - Qualifications: Declined ❌ [Re-upload]
     Reason: Image too blurry
   - Proof of Residence: Pending ⏳
4. Click "Re-upload" on Qualifications
5. Choose scan method → Scans new document
6. Dialog refreshes
7. All now Pending or Approved
8. Wait for final approval
```

---

## Implementation Details

### Method 1: `_showMissingDocumentsDialog()`
- Simple list-based dialog
- Shows which documents are missing
- Single "Scan Next Document" button
- Focuses on getting documents uploaded

### Method 2: `_showPendingDeclinedDialog()`
- Detailed card-based view
- Shows status of each document
- Individual "Re-upload" buttons for declined docs
- Explains why documents were declined

### Logic Flow
```dart
if (any document is "Not Uploaded") {
  showStage1_MissingDocuments();
} else {
  showStage2_PendingDeclined();
}
```

---

## Key Features

✅ **Smart staging:** Automatically switches between Stage 1 and Stage 2  
✅ **Progress tracking:** Shows how many documents uploaded vs remaining  
✅ **Clear feedback:** Users know exactly what to do next  
✅ **Upload from dialog:** No need to exit clock-in  
✅ **Auto-refresh:** Dialog updates after each upload  
✅ **Decline reasons:** Users see why documents were rejected  
✅ **Re-upload support:** Easy to fix declined documents  

---

## Testing Scenarios

### Test 1: All 3 Missing
- [ ] Shows Stage 1 dialog
- [ ] Lists all 3 documents
- [ ] "Scan Next Document" works
- [ ] After first upload, still shows Stage 1
- [ ] After second upload, still shows Stage 1
- [ ] After third upload, switches to Stage 2

### Test 2: 1 Missing
- [ ] Shows Stage 1 with 1 document
- [ ] After upload, switches to Stage 2
- [ ] Stage 2 shows all 3 statuses

### Test 3: All Uploaded, Some Pending
- [ ] Shows Stage 2 directly
- [ ] Pending documents show status
- [ ] No upload buttons (just waiting)
- [ ] Message says "contact administrator"

### Test 4: One Declined
- [ ] Shows Stage 2
- [ ] Declined document has "Re-upload" button
- [ ] Shows decline reason
- [ ] Can re-upload
- [ ] After re-upload, status changes to "Pending"

---

## Files Modified

- `lib/clock_in_page.dart`
  - Added `_showMissingDocumentsDialog()` method
  - Added `_showPendingDeclinedDialog()` method
  - Modified `_ensureLearnerDocumentsComplete()` to use two-stage logic
  - Added `_handleDocumentUpload()` method
  - Added `_pickAndUploadDocument()` method

---

## Success Criteria

✅ Learners can upload missing documents from clock-in  
✅ Clear distinction between "missing" and "pending/declined"  
✅ Simple workflow for uploading multiple documents  
✅ Easy re-upload for declined documents  
✅ Clear feedback on what needs to be done  

---

## Status

✅ **COMPLETE** - Ready for testing and deployment

Build new APK and test!
