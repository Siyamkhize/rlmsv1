# Document Validation Fix - Complete

## Issue
Clock-in page was requiring ALL 5 documents to be uploaded before allowing clock-in. The requirements were unclear about which documents must be approved vs. just uploaded.

## Requirements Clarified

### Upload Requirements (When Adding Documents)
**ALL 5 documents must be uploaded:**
1. ID Document ✓
2. Qualifications ✓
3. Bank Confirmation Letter ✓
4. Proof of Residence ✓
5. CV ✓

### Clock-In Requirements (Before Allowing Clock-In)
**Only 3 documents must be APPROVED:**
1. ID Document ✓ (must be APPROVED)
2. Qualifications ✓ (must be APPROVED)
3. Proof of Residence ✓ (must be APPROVED)

**Optional for clock-in:**
- Bank Confirmation Letter (can be pending/missing)
- CV (can be pending/missing)

## Changes Made

### 1. Updated Document Lists (`lib/clock_in_page.dart`)

**Before:**
```dart
final List<String> _requiredDocuments = const [
  'ID Document',
  'Qualifications',
  'Bank Confirmation Letter',
  'Proof of Residence',
  'CV',
];
```

**After:**
```dart
// Documents required for UPLOAD (all 5 must be uploaded)
final List<String> _requiredDocumentsForUpload = const [
  'ID Document',
  'Qualifications',
  'Bank Confirmation Letter',
  'Proof of Residence',
  'CV',
];

// Documents required for CLOCK-IN (must be approved)
final List<String> _requiredDocumentsForClocking = const [
  'ID Document',
  'Qualifications',
  'Proof of Residence',
];
```

### 2. Updated Validation Logic

**Changed `_getMissingRequiredDocuments()` to:**
- Filter to APPROVED documents only (check `status == 'approved'`)
- Only validate the 3 required documents for clocking
- Work both online (check server) and offline (check local database)

**Changed `parseDocsPayload()` in `_fetchServerDocuments()` to:**
- Filter server response to only include documents with `status == 'approved'`
- Skip documents that are pending, declined, or missing status

### 3. Updated User Messages

**Changed dialog message from:**
```
"This learner has missing required documents. Scan all missing document(s) before clock-in."
```

**To:**
```
"Clock-in requires these documents to be APPROVED:
• ID Document
• Qualifications  
• Proof of Residence

Please upload missing documents and wait for admin approval."
```

## Behavior Now

### Scenario 1: New Learner (No Documents)
- ❌ **Cannot clock in** - Missing 3 required approved documents
- **Action**: Upload ID, Qualifications, Proof of Residence → Wait for approval
- **Optional**: Can upload Bank Confirmation & CV later

### Scenario 2: Uploaded but Pending Approval
- ❌ **Cannot clock in** - Documents uploaded but not approved
- **Action**: Wait for admin to approve documents
- **Status displays**: "Pending"

### Scenario 3: All 3 Required Documents Approved
- ✅ **Can clock in** - Has ID, Qualifications, Proof of Residence approved
- **Optional docs**: Bank Confirmation & CV can be missing/pending without blocking

### Scenario 4: One Document Declined
- ❌ **Cannot clock in** - Need to re-upload declined document
- **Action**: Re-upload declined document → Wait for re-approval
- **Status displays**: "Declined - Action Required"

## Database Schema Requirement

The document validation relies on the `status` column in the `learner_document` table:

```sql
-- Expected values
status VARCHAR(50) -- 'approved', 'pending', 'declined', etc.
```

Make sure your `check_learner_documents.php` endpoint returns documents with their status field.

## Testing Checklist

- [ ] New learner cannot clock in without 3 approved documents
- [ ] Learner with only Bank Confirmation & CV approved cannot clock in
- [ ] Learner with ID, Qualifications, Proof of Residence approved CAN clock in
- [ ] Learner with ID, Qualifications, Proof of Residence approved + Bank/CV missing CAN clock in
- [ ] Pending documents don't count as approved
- [ ] Declined documents don't count as approved
- [ ] Dialog shows correct message about 3 required documents
- [ ] Offline mode respects local approved status

## Files Modified

1. `lib/clock_in_page.dart`
   - Lines 108-119: Split document lists into ForUpload and ForClocking
   - Lines 3719-3766: Updated `_getMissingRequiredDocuments()` to filter approved only
   - Lines 3786-3823: Updated `parseDocsPayload()` to filter approved documents
   - Lines 3424-3433: Updated dialog message

## Next Steps

1. Build and deploy new APK
2. Test with learners at different document approval stages
3. Verify admin approval workflow is working
4. Ensure `check_learner_documents.php` returns status field

## Notes

- This change makes the system more flexible - learners can clock in as soon as their critical documents (ID, Qualifications, Proof of Residence) are approved
- Bank Confirmation Letter and CV can be collected over time without blocking daily work
- Document status is checked both online (from server) and offline (from local database)
