# Evidence Table Not Saving Data - Fix

**Date**: September 21, 2026  
**Issue**: Face enrollment works, but signatures, photos, and GPS are not being saved to `learner_clocking_evidence` table  
**Root Cause**: Old database schema on phone (version < 12) - table doesn't exist yet

---

## Problem

The `learner_clocking_evidence` table was added in database version 12, but your currently installed APK has an older database schema. The app is trying to insert data into a table that doesn't exist on the phone.

### Evidence of Issue

```dart
await DatabaseHelper().saveClockInEvidence(...);
// This succeeds without error, but data goes nowhere because table doesn't exist
```

The code is correct - the table just isn't on the phone yet.

---

## Solution 1: Install New APK (Recommended)

Build and install a fresh APK with the updated database schema:

1. **Restart computer** (to clear Gradle locks)
2. **Build APK**:
   ```powershell
   cd c:\projects\rlmss
   .\fix_gradle_and_build.bat
   ```
3. **Install to phone**:
   ```powershell
   adb install -r android\app\build\outputs\apk\release\app-release.apk
   ```

When the app starts with the new APK:
- Database will upgrade from current version to version 14
- Migration scripts will run
- `learner_clocking_evidence` table will be created automatically

---

## Solution 2: Manual Database Repair (Quick Test)

If you can't build a new APK right now, use the manual repair function:

### Step 1: Add Repair Button to App

Add this to your dashboard or any page for testing:

```dart
ElevatedButton(
  onPressed: () async {
    try {
      await DatabaseHelper().repairEvidenceTable();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Evidence table repaired!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Repair failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  },
  child: Text('Repair Evidence Table'),
)
```

### Step 2: Test the Repair

1. Open the app
2. Tap "Repair Evidence Table" button
3. You should see: "✅ Evidence table repaired!"
4. Try clock-in with face verification again
5. Check database: `SELECT * FROM learner_clocking_evidence`

---

## Solution 3: Manual SQL Repair (Database Tool)

If you have access to the phone's database file directly:

```sql
-- Drop old table if exists
DROP TABLE IF EXISTS learner_clocking_evidence;

-- Create new table with correct schema
CREATE TABLE learner_clocking_evidence (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  LearnerID INTEGER NOT NULL,
  clock_date TEXT NOT NULL,
  
  clock_in_signature TEXT,
  clock_in_photo TEXT,
  clock_in_latitude REAL,
  clock_in_longitude REAL,
  clock_in_accuracy REAL,
  clock_in_verification_method TEXT,
  clock_in_face_log_id INTEGER,
  clock_in_timestamp TEXT,
  
  clock_out_signature TEXT,
  clock_out_photo TEXT,
  clock_out_latitude REAL,
  clock_out_longitude REAL,
  clock_out_accuracy REAL,
  clock_out_verification_method TEXT,
  clock_out_face_log_id INTEGER,
  clock_out_timestamp TEXT,
  
  synced INTEGER DEFAULT 0,
  created_at TEXT DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
  
  UNIQUE(LearnerID, clock_date)
);

-- Create indices
CREATE INDEX idx_evidence_learner ON learner_clocking_evidence(LearnerID);
CREATE INDEX idx_evidence_date ON learner_clocking_evidence(clock_date);
CREATE INDEX idx_evidence_synced ON learner_clocking_evidence(synced);
```

---

## Verification After Fix

### Test Clock-In with Face Verification

1. Open app → Backup Clock-In
2. Select learner
3. Complete profile/bank/document checks
4. Capture face (or use existing enrollment)
5. Capture signature
6. Clock in successfully

### Check Database

```sql
SELECT 
  id,
  LearnerID,
  clock_date,
  LENGTH(clock_in_signature) as sig_length,
  LENGTH(clock_in_photo) as photo_length,
  clock_in_latitude,
  clock_in_longitude,
  clock_in_verification_method,
  clock_in_timestamp
FROM learner_clocking_evidence
WHERE LearnerID = 11443
ORDER BY clock_date DESC
LIMIT 5;
```

Expected output:
```
| id | LearnerID | clock_date | sig_length | photo_length | lat    | lng    | method | timestamp           |
|----|-----------|------------|------------|--------------|--------|--------|--------|---------------------|
| 1  | 11443     | 2026-09-21 | 15234      | 45678       | -26.xx | 27.xx  | face   | 2026-09-21 14:30:00 |
```

---

## What Gets Saved

### Clock-In Evidence
- ✅ `clock_in_signature` - Base64 signature image
- ✅ `clock_in_photo` - Base64 face photo (if face verified)
- ✅ `clock_in_latitude` - GPS latitude
- ✅ `clock_in_longitude` - GPS longitude
- ✅ `clock_in_accuracy` - GPS accuracy in meters
- ✅ `clock_in_verification_method` - 'face', 'signature', or 'security_question'
- ✅ `clock_in_face_log_id` - FK to `learner_face_verification_log` (server-side)
- ✅ `clock_in_timestamp` - Timestamp of clock-in

### Clock-Out Evidence
- ✅ `clock_out_signature` - Base64 signature image
- ✅ `clock_out_latitude` - GPS latitude
- ✅ `clock_out_longitude` - GPS longitude
- ✅ `clock_out_accuracy` - GPS accuracy
- ✅ `clock_out_verification_method` - Usually 'signature'
- ✅ `clock_out_timestamp` - Timestamp of clock-out

---

## Code References

### Where Evidence is Saved

**File**: `lib/backup_clock_in_page.dart`

**Clock-In** (line ~1798):
```dart
await DatabaseHelper().saveClockInEvidence(
  learnerId: int.parse(learnerId),
  clockDate: date,
  signature: signatureData,
  photo: _capturedFacePhotoBase64,
  latitude: latitude,
  longitude: longitude,
  accuracy: accuracy,
  verificationMethod: verificationMethod,
  faceLogId: _faceLogId,
);
```

**Clock-Out** (line ~1922):
```dart
await DatabaseHelper().saveClockOutEvidence(
  learnerId: int.parse(learnerId),
  clockDate: date,
  signature: signatureData,
  photo: null,
  latitude: latitude,
  longitude: longitude,
  accuracy: accuracy,
  verificationMethod: 'signature',
  faceLogId: null,
);
```

### Database Helper Method

**File**: `lib/database_helper.dart`

**Line ~7861**: `Future<void> saveClockInEvidence()`  
**Line ~7932**: `Future<void> saveClockOutEvidence()`  
**Line ~7861** (new): `Future<void> repairEvidenceTable()`

---

## Troubleshooting

### "Table doesn't exist" error

**Symptom**: Error in logs: `no such table: learner_clocking_evidence`

**Solution**: 
1. Run manual repair function
2. Or install new APK with database migration

### Evidence saves but data is null

**Symptom**: Records exist but all fields are NULL

**Solution**: Check that:
- Signature is captured (`signatureData != null`)
- Face photo is captured (`_capturedFacePhotoBase64 != null`)
- GPS is obtained before saving
- Verification method is set correctly

### Face photo not saving

**Symptom**: signature and GPS save, but photo is NULL

**Solution**: 
- Check face verification succeeded
- Check `_capturedFacePhotoBase64` is not null
- Verify face verification happens BEFORE signature capture

---

## Database Migration Timeline

| Version | Feature Added |
|---------|---------------|
| 11 | Basic clocking tables |
| **12** | **`learner_clocking_evidence` table** ✅ |
| 13 | `learner_face_cache` for offline verification |
| 14 | Location sync fields |

Your phone needs to be on **version 12+** for evidence to save.

---

## Summary

**Problem**: Old database schema on phone (< version 12)  
**Table Missing**: `learner_clocking_evidence`  
**Quick Fix**: Run `repairEvidenceTable()` from app  
**Permanent Fix**: Install new APK with database migration  
**After Fix**: All evidence (signature, photo, GPS) will save correctly  

---

**Current Status**: Fix applied to database_helper.dart - ready to test after installing new APK or running manual repair
