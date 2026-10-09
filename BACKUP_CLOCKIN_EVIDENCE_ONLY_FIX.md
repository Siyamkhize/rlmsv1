# Backup Clock-In Evidence-Only Architecture Fix

**Date:** September 25, 2026  
**Status:** ✅ COMPLETE

## Summary

Fixed `backup_clock_in_page.dart` to use ONLY the `learner_clocking_evidence` table and NOT sync to `learner_clocking` table. The backup clock-in system (face recognition + security questions) is completely separate from the regular attendance system.

## Changes Made

### 1. Removed `clocking/clockin.php` call (Clock-In)
**Location:** Line ~1960 in backup_clock_in_page.dart

**Before:**
```dart
final response = await http.post(
  Uri.parse(AppConfig.buildUrl('clocking/clockin.php')),
  body: body,
).timeout(const Duration(seconds: 10));
```

**After:**
```dart
// Backup clock-in does NOT sync to learner_clocking table
// Evidence is stored in learner_clocking_evidence table only
print('[BACKUP] Evidence-only mode: NOT syncing to learner_clocking table');
```

### 2. Removed `clocking/clockout.php` call (Clock-Out)
**Location:** Line ~2190 in backup_clock_in_page.dart

**Before:**
```dart
final response = await http.post(
  Uri.parse(AppConfig.buildUrl('clocking/clockout.php')),
  body: {
    'clock_out': '1',
    'LearnerID': learnerId,
    'clock_in_time': clockInTime,
    'clock_out_time': now,
    'contact_time': contactTime,
    'clock_date': date,
    'classID': widget.classID,
    'method': 'signature',
    'signature_in': clockInSignature,
    'signature_out': clockOutSignatureFilename,
  },
).timeout(const Duration(seconds: 10));
```

**After:**
```dart
// Backup clock-out does NOT sync to learner_clocking table  
// Evidence is stored in learner_clocking_evidence table only
print('[BACKUP_CLOCKOUT] Evidence-only mode: NOT syncing to learner_clocking table');
bool synced = false;
```

## Architecture

### Two Separate Clock-In Systems

#### 1. Regular Attendance System (attendance_page.dart)
- **Table:** `learner_clocking`
- **Endpoints:** `clocking/clockin.php`, `clocking/clockout.php`
- **Verification:** Fingerprint / QR code / Normal methods

#### 2. Backup Clock-In System (backup_clock_in_page.dart)
- **Table:** `learner_clocking_evidence` ONLY
- **Endpoints:** `save_clocking_evidence.php`, `upload_clocking_evidence_images.php`
- **Verification:** Face recognition + Security questions

### Correct Endpoints Used

✅ **Clock-in evidence:** `save_clocking_evidence.php`  
✅ **Clock-out evidence:** `save_clocking_evidence.php`  
✅ **Upload images:** `upload_clocking_evidence_images.php`  
✅ **Check status:** Queries `learner_clocking_evidence` table directly

❌ **Never uses:** `clocking/clockin.php` or `clocking/clockout.php`

## Table Usage Confirmed

### `_loadClockingStatus()` - Line 348
```sql
SELECT clock_in_timestamp, clock_out_timestamp, clock_date, synced
FROM learner_clocking_evidence 
WHERE LearnerID = ? 
  AND clock_date = ?
LIMIT 1
```
✅ Correctly checks `learner_clocking_evidence` table

### Duplicate Check - Line 1883
```sql
SELECT id FROM learner_clocking_evidence 
WHERE LearnerID = ? AND clock_date = ?
```
✅ Correctly checks `learner_clocking_evidence` for duplicates

### Clock-Out Verification - Line 2177
```sql
SELECT * FROM learner_clocking_evidence
WHERE LearnerID = ? 
  AND clock_date = ? 
  AND clock_out_timestamp IS NULL
ORDER BY id DESC 
LIMIT 1
```
✅ Correctly checks `learner_clocking_evidence` for open sessions

## Files Modified

1. **lib/backup_clock_in_page.dart**
   - Removed `clocking/clockin.php` POST call
   - Removed `clocking/clockout.php` POST call
   - All evidence saved via `save_clocking_evidence.php`
   - All status checks query `learner_clocking_evidence` table

## Testing Required

1. **Clock-In Test:**
   - Tap pen icon in clock_in_page.dart
   - Select learner
   - Complete face recognition
   - Answer security questions
   - Verify record appears ONLY in `learner_clocking_evidence` table
   - Verify NO record in `learner_clocking` table

2. **Clock-Out Test:**
   - Select already clocked-in learner
   - Complete face recognition
   - Sign out
   - Verify `clock_out_timestamp` updated ONLY in `learner_clocking_evidence`
   - Verify NO update to `learner_clocking` table

3. **Status Check Test:**
   - Reopen backup_clock_in_page.dart
   - Verify learners show correct clocked-in/out status
   - Verify status loaded from `learner_clocking_evidence` table

## SQL Verification Queries

```sql
-- Check backup clock-ins (should have records)
SELECT * FROM learner_clocking_evidence 
WHERE clock_date = CURDATE()
ORDER BY clock_in_timestamp DESC;

-- Check regular attendance (should NOT have records from backup system)
SELECT * FROM learner_clocking 
WHERE clockDate = CURDATE()
ORDER BY clockInTime DESC;

-- These two tables should have DIFFERENT records
-- Backup system = learner_clocking_evidence ONLY
-- Regular system = learner_clocking ONLY
```

## Next Steps

1. ✅ Build new APK with fixes
2. ⚠️ Install on device (ALREADY DONE - but needs rebuild)
3. ⚠️ Test clock-in via pen icon
4. ⚠️ Verify database tables
5. ⚠️ Deploy `sql/create_security_questions_tables.sql` to MySQL
6. ⚠️ Verify `mobile/manage_security_questions.php` is accessible

## Important Notes

- **Pen icon** in clock_in_page.dart navigates to backup_clock_in_page.dart
- **Backup system** is completely independent from regular attendance
- **Evidence table** stores face photos, signatures, GPS, and security question answers
- **No writes** to `learner_clocking` table from backup system
- **Server endpoints** for backup use different PHP files (`save_clocking_evidence.php`)

---

**Status:** Code fixed, needs rebuild and installation on device
