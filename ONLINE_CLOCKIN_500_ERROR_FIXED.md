# Online Clock-In 500 Error - FIXED

## Issue Summary
Online manual clock-in was failing with HTTP 500 error after authentication succeeded.

## Root Causes

### ✅ Cause #1: Token Authentication (RESOLVED)
- **Initial Diagnosis:** Old token theory was WRONG
- **Actual Situation:** Token was working perfectly
- **Evidence:**
  - New login token: `537b14780009bdc1...02172369eace2354` (64 chars)
  - Token stored correctly ✅
  - Token retrieved correctly ✅
  - Authentication passed ✅

### ❌ Cause #2: Wrong Table Name in PHP (FIXED)
- **File:** `mobile/save_manual_clocking_images.php` line 87-92
- **Error:** `PHP Fatal error: Call to a member function bind_param() on bool`
- **Root Cause:** SQL query using wrong table name
  - Code was querying: `learner_clocking_evidence`  
  - Correct table name: `manual_clocking_evidence`
- **Column Names Also Wrong:**
  - Code was using: `face_filename`, `signature_filename`
  - Correct columns: `face_in`, `signature_in`

## What Was Fixed

### File: `mobile/save_manual_clocking_images.php`

**Changed Line 87-92:**
```php
// BEFORE (BROKEN):
$existingCheck = $conn->prepare("
    SELECT face_filename, signature_filename 
    FROM learner_clocking_evidence 
    WHERE learner_id = ? AND clock_date = ?
    LIMIT 1
");
$existingCheck->bind_param("is", $learnerID, $clockDate);

// AFTER (FIXED):
$existingCheck = $conn->prepare("
    SELECT face_in, signature_in 
    FROM manual_clocking_evidence 
    WHERE LearnerID = ? AND clock_date = ?
    LIMIT 1
");

if (!$existingCheck) {
    error_log("[SAVE_CLOCKING_IMAGES] ❌ Failed to prepare idempotency check: " . $conn->error);
    throw new Exception('Database error: ' . $conn->error);
}

$existingCheck->bind_param("is", $learnerID, $clockDate);
```

**Changed Line 100-101:**
```php
// BEFORE:
$faceFile = $facesDir . '/' . $existing['face_filename'];
$sigFile = $signaturesDir . '/' . $existing['signature_filename'];

// AFTER:
$faceFile = $facesDir . '/' . $existing['face_in'];
$sigFile = $signaturesDir . '/' . $existing['signature_in'];
```

**Changed Line 105-112:**
```php
// BEFORE:
'files' => [
    'face_' . $type => $existing['face_filename'],
    'signature_' . $type => $existing['signature_filename'],
],

// AFTER:
'files' => [
    'face_' . $type => $existing['face_in'],
    'signature_' . $type => $existing['signature_in'],
],
```

## Database Schema

### manual_clocking_evidence Table
```
evidence_id         INT(11)      PRIMARY KEY AUTO_INCREMENT
LearnerID           INT(11)      NOT NULL
clock_date          DATE         NOT NULL
signature_in        VARCHAR(255)
signature_out       VARCHAR(255)
face_in             VARCHAR(255)
face_out            VARCHAR(255)
created_at          TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
updated_at          TIMESTAMP    DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
```

## Testing Required

### Test 1: Online Clock-In
1. Open app on device RZ8X306F7TZ
2. Navigate to learner clock-in page
3. Select a learner (e.g., 11443)
4. Capture face photo and signature
5. Click "Clock In"

**Expected Result:**
- ✅ HTTP 200 response
- ✅ Images save to folders:
  - `mobile/manual_clocking_evidence/faces/`
  - `mobile/manual_clocking_evidence/signatures/`
- ✅ Record inserts to `manual_clocking` table
- ✅ Evidence filenames insert to `manual_clocking_evidence` table
- ✅ Success message shows on device

### Test 2: Idempotency
1. Try to clock in the SAME learner on the SAME day again
2. Should return existing filenames (not create new ones)

**Expected Result:**
- ✅ HTTP 200 response
- ✅ Response contains `"idempotent": true`
- ✅ Returns existing face_in and signature_in filenames
- ❌ Does NOT create duplicate files

## Remaining Issues

###❌ Issue #3: Missing SQLite Table
When online fails, offline fallback crashes with:
```
DatabaseException(no such table: manual_clocking_evidence)
```

**Fix Required:** Create `manual_clocking_evidence` table in SQLite
- Location: Device local SQLite database
- Schema: Same as MySQL table
- SQL file: `sql/003_create_learner_clocking_evidence_sqlite.sql`

This should be handled by database migrations on app startup.

## Files Modified

### Server-Side
- ✅ `mobile/save_manual_clocking_images.php` - Fixed table and column names

### Client-Side  
- ✅ `lib/config.dart` - Added token logging
- ✅ `lib/main.dart` - Added login token logging

## Verification Commands

### Check if fix is deployed:
```bash
# Check line 87-92 in PHP file
grep -A 5 "FROM manual_clocking_evidence" mobile/save_manual_clocking_images.php
```

### Check server logs for errors:
```powershell
Get-Content "C:\xampp\apache\logs\error.log" -Tail 20 | Select-String "500|Fatal"
```

### Check image folders:
```bash
ls -la mobile/manual_clocking_evidence/faces/
ls -la mobile/manual_clocking_evidence/signatures/
```

## Summary

✅ **Authentication Working:** Fresh token from login works perfectly  
✅ **Server Error Fixed:** Wrong table name in SQL query corrected  
❌ **SQLite Table Missing:** Offline fallback needs manual_clocking_evidence table  

**Next Step:** Test online clock-in on device and verify data saves to MySQL!
