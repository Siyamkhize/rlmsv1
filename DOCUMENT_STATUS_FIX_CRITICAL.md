# 🔴 CRITICAL FIX: Document Status Validation for Clock-In

**Issue Reported:** Learner 21568 cannot clock in despite having all documents approved  
**Root Cause:** Server endpoint not filtering by document status  
**Fix Applied:** September 22, 2026

---

## 🐛 Problem Description

### Symptom
- Learner 21568 has all 3 required documents approved in the database
- Clock-in still fails with "Missing documents" error
- App validation logic is correct, but server endpoint is broken

### Root Cause
The `check_learner_documents.php` endpoint was returning ALL documents regardless of their status:

```php
// BROKEN CODE (before fix):
$query = "SELECT documentName FROM learner_document WHERE learner_id = ?";
```

This meant:
- ❌ Pending documents were counted as valid
- ❌ Declined documents were counted as valid  
- ❌ Null status documents were counted as valid
- ✅ Only APPROVED documents should be counted

---

## ✅ Solution Applied

### 1. Fixed Server Endpoint

**File:** `mobile/check_learner_documents.php`

**Changes:**
```php
// NEW CODE (after fix):
$query = "SELECT documentName, status 
          FROM learner_document 
          WHERE learner_id = ? 
          AND LOWER(status) = 'approved'";
```

**What This Does:**
1. Only returns documents with status = 'Approved' (case-insensitive)
2. Returns both `documentName` and `status` for transparency
3. Excludes pending, declined, and null status documents

### 2. Response Format

**Before:**
```json
{
  "success": true,
  "documents": [
    "ID Document",
    "Qualifications",
    "Professional Indemnity (Pending)",
    "Proof of Residence"
  ]
}
```

**After:**
```json
{
  "success": true,
  "documents": [
    {
      "documentName": "ID Document",
      "status": "Approved"
    },
    {
      "documentName": "Qualifications",
      "status": "Approved"
    },
    {
      "documentName": "Proof of Residence",
      "status": "Approved"
    }
  ]
}
```

---

## 🧪 Testing the Fix

### Diagnostic Script Created

**File:** `check_learner_21568_documents.php`

Run this to diagnose any learner's document status:

```bash
php check_learner_21568_documents.php
```

**What It Shows:**
- All documents in database
- Their statuses
- What the endpoint returns
- Which documents are approved
- What's missing for clock-in

### Manual Database Check

```sql
-- Check all documents for a learner
SELECT 
    documentName,
    status,
    uploaded_at,
    approved_at
FROM learner_document 
WHERE learner_id = '21568';

-- Check approved documents only
SELECT documentName 
FROM learner_document 
WHERE learner_id = '21568' 
AND LOWER(status) = 'approved';
```

---

## 📋 Document Status Values

The `status` column in `learner_document` table can have these values:

| Status | Meaning | Clock-In Allowed? |
|--------|---------|-------------------|
| `Approved` | Admin approved the document | ✅ YES |
| `Pending` | Waiting for admin review | ❌ NO |
| `Declined` | Admin rejected the document | ❌ NO |
| `NULL` | No status set | ❌ NO |

**Only `Approved` documents count toward clock-in validation.**

---

## 🔄 Document Upload & Approval Workflow

### Step 1: Learner Uploads Document
- Document saved to `learner_document` table
- Status = `Pending` (or NULL)
- Clock-in NOT allowed yet

### Step 2: Admin Reviews Document
- Admin logs into web portal
- Views pending documents
- Approves or Declines

### Step 3: Status Updated
- If approved: Status = `Approved`
- Clock-in NOW allowed

### Step 4: Clock-In Validation
- Mobile app checks with server
- Server returns ONLY approved documents
- If 3 required docs are approved: Clock-in proceeds
- If missing: Upload prompt shown

---

## 📱 Mobile App Logic (Already Correct)

The mobile app in `clock_in_page.dart` was already correct:

```dart
// Line 3817-3818: Filters out non-approved documents
final status = item['status']?.toString()?.toLowerCase() ?? '';
if (status != 'approved') {
  continue; // Skip non-approved documents
}
```

**The issue was ONLY in the server endpoint.**

---

## 🚨 Required Documents for Clock-In

Only **3 documents** are required (not 4):

1. ✅ **ID Document**
2. ✅ **Qualifications**  
3. ✅ **Proof of Residence**

~~Professional Indemnity~~ - NOT required for clock-in (facilitators only)

---

## 🔧 Related Files Fixed

### 1. Server Endpoint
- `mobile/check_learner_documents.php` ✅ FIXED
- Now filters by status = 'approved'

### 2. Diagnostic Tools
- `check_learner_21568_documents.php` ✅ CREATED
- Shows full document status breakdown

### 3. Mobile App
- `lib/clock_in_page.dart` ✅ Already correct
- No changes needed

---

## 🎯 Testing Checklist

After deploying this fix, test:

### For Learner 21568
- [ ] Run diagnostic script
- [ ] Verify all 3 required docs show as approved
- [ ] Test clock-in on mobile app
- [ ] Should succeed without document upload prompt

### For Other Learners

#### Scenario 1: All Approved
- [ ] Learner with 3 approved docs
- [ ] Clock-in should succeed immediately

#### Scenario 2: Some Pending
- [ ] Learner with 2 approved, 1 pending
- [ ] Should prompt to upload the missing document
- [ ] Should NOT accept the pending document

#### Scenario 3: Some Declined
- [ ] Learner with declined document
- [ ] Should prompt to re-upload
- [ ] Declined doc should not count as approved

#### Scenario 4: No Documents
- [ ] New learner with no uploads
- [ ] Should prompt to upload all 3 documents

---

## 🐛 If Clock-In Still Fails

### Check Document Names Match

The app normalizes document names. These are equivalent:

```
"ID Document" = "id document" = "ID_Document" = "id document.pdf"
"Qualifications" = "qualifications" = "qualification"
"Proof of Residence" = "proof of residence" = "Proof_of_Residence"
```

### Check Database Values

```sql
-- Check exact document names in database
SELECT DISTINCT documentName 
FROM learner_document 
WHERE LOWER(status) = 'approved';
```

If document names don't match the required list, they won't be recognized.

### Common Name Mismatches

| Database Value | Expected Value | Match? |
|----------------|----------------|--------|
| "ID Copy" | "ID Document" | ❌ NO |
| "Matric Certificate" | "Qualifications" | ❌ NO |
| "Proof of Address" | "Proof of Residence" | ❌ NO |
| "ID Document" | "ID Document" | ✅ YES |
| "Qualifications" | "Qualifications" | ✅ YES |
| "Proof of Residence" | "Proof of Residence" | ✅ YES |

---

## 📊 Database Schema Reference

### learner_document table

```sql
CREATE TABLE learner_document (
    id INT AUTO_INCREMENT PRIMARY KEY,
    learner_id VARCHAR(50),
    documentName VARCHAR(255),
    file_path VARCHAR(255),
    status VARCHAR(50),  -- 'Approved', 'Pending', 'Declined'
    uploaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    approved_at TIMESTAMP NULL,
    approved_by VARCHAR(255) NULL
);
```

---

## 🚀 Deployment Steps

### 1. Upload Fixed File
```bash
# Upload to server
scp mobile/check_learner_documents.php user@server:/path/to/rlmss/mobile/
```

### 2. No App Rebuild Needed
- ✅ This is a server-side fix only
- ✅ Existing mobile app will work immediately
- ✅ No need to rebuild and reinstall APK

### 3. Test Immediately
```bash
# Test the endpoint
curl -X POST https://your-server.com/rlmss/mobile/check_learner_documents.php \
  -d "learner_id=21568"
```

### 4. Verify Response
Should return only approved documents with status field.

---

## ✅ Fix Complete

**Summary:**
- ❌ Before: Endpoint returned ALL documents (any status)
- ✅ After: Endpoint returns ONLY approved documents
- 📱 Mobile app already had correct validation logic
- 🔧 Server was the bottleneck - now fixed
- 🎯 Learner 21568 should be able to clock in now

**Deploy `mobile/check_learner_documents.php` to server and test immediately.**
