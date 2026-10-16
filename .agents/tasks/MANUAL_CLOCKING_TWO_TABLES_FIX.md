# Manual Clocking Two Tables Fix - COMPLETE

## Problem Discovery
You correctly identified that manual clocking (signature + geofence + face) uses **TWO tables**:
1. **`manual_clocking`** - Clock-in/clock-out times, metadata
2. **`manual_clocking_evidence`** - Signature and face photo filenames

The signature_geofence_clock_in_page.dart was calling `insertClockInOffline()` which only saves to `learner_clocking` table (fingerprint method), not the manual clocking tables.

## Root Cause
**Wrong method called:**
```dart
// OLD (WRONG):
await dbHelper.insertClockInOffline(clockInData);
// This saves to learner_clocking table (fingerprint method)
```

**Should use:**
```dart
// NEW (CORRECT):
await dbHelper.insertManualClockInOffline(clockInData);
// This saves to manual_clocking + manual_clocking_evidence tables
```

## PHP Endpoints (Reference)

### save_manual_clockin.php
Saves to BOTH tables:
```php
// 1. INSERT INTO manual_clocking
INSERT INTO manual_clocking
(LearnerID, clock_date, clock_in_time, contact_time, is_manual_attendance)
VALUES (?, ?, ?, ?, 1)

// 2. INSERT INTO manual_clocking_evidence  
INSERT INTO manual_clocking_evidence
(LearnerID, clock_date, signature_in, face_in)
VALUES (?, ?, ?, ?)
```

### save_manual_clockout.php
Updates BOTH tables:
```php
// 1. UPDATE manual_clocking
UPDATE manual_clocking
SET clock_out_time = ?
WHERE LearnerID = ? AND clock_date = ?

// 2. UPDATE manual_clocking_evidence
UPDATE manual_clocking_evidence
SET signature_out = ?, face_out = ?
WHERE LearnerID = ? AND clock_date = ?
```

## Solution Implemented

### 1. Created New Method in database_helper.dart

**`insertManualClockInOffline()`**
- Saves to `manual_clocking` table (times)
- Saves to `manual_clocking_evidence` table (image filenames)
- Handles INSERT or UPDATE based on existing records
- Sets `synced = 0` for later server sync

**`updateManualClockOutOffline()`**
- Updates `manual_clocking.clock_out_time`
- Updates `manual_clocking_evidence.signature_out`, `face_out`
- Sets `synced = 0` for later server sync

### 2. Updated signature_geofence_clock_in_page.dart

Changed method call from:
```dart
await dbHelper.insertClockInOffline(clockInData);
```

To:
```dart
await dbHelper.insertManualClockInOffline(clockInData);
```

## Table Structures

### manual_clocking
```sql
CREATE TABLE manual_clocking (
  manual_id INTEGER PRIMARY KEY AUTOINCREMENT,
  clocking_id INTEGER,
  LearnerID INTEGER NOT NULL,
  clock_date TEXT NOT NULL,
  clock_in_time TEXT,
  clock_out_time TEXT,
  contact_time TEXT,
  manual_reason TEXT,
  fdp_document TEXT,
  status TEXT DEFAULT 'Pending',
  reviewed_by TEXT,
  reviewed_at TEXT,
  rejection_reason TEXT,
  is_manual_attendance INTEGER DEFAULT 1,
  synced INTEGER DEFAULT 0
)
```

### manual_clocking_evidence
```sql
CREATE TABLE manual_clocking_evidence (
  evidence_id INTEGER PRIMARY KEY AUTOINCREMENT,
  LearnerID INTEGER NOT NULL,
  clock_date TEXT NOT NULL,
  signature_in TEXT,
  signature_out TEXT,
  face_in TEXT,
  face_out TEXT,
  created_at TEXT DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
  synced INTEGER DEFAULT 0,
  UNIQUE(LearnerID, clock_date),
  FOREIGN KEY (LearnerID) REFERENCES learnerdetails(LearnerID)
)
```

## Files Modified

1. ✅ `lib/database_helper.dart`
   - Added: `insertManualClockInOffline()` method
   - Added: `updateManualClockOutOffline()` method

2. ✅ `lib/signature_geofence_clock_in_page.dart`
   - Changed: `insertClockInOffline()` → `insertManualClockInOffline()`
   - Already fixed: All queries now use `manual_clocking` table

## Complete Flow Now

### Clock-In Flow (Online):
1. Upload images → `save_manual_clocking_images.php`
2. Save times → `save_manual_clockin.php` → `manual_clocking` + `manual_clocking_evidence`
3. Display from `manual_clocking` JOIN `manual_clocking_evidence`

### Clock-In Flow (Offline):
1. Save locally → `insertManualClockInOffline()` → `manual_clocking` + `manual_clocking_evidence`
2. Display from `manual_clocking` JOIN `manual_clocking_evidence`
3. Later sync → uploads images then times to server

### Clock-Out Flow (Online):
1. Upload images → `save_manual_clocking_images.php`
2. Update times → `save_manual_clockout.php` → `manual_clocking` + `manual_clocking_evidence`
3. Display from `manual_clocking` JOIN `manual_clocking_evidence`

### Clock-Out Flow (Offline):
1. Update locally → `updateManualClockOutOffline()` → `manual_clocking` + `manual_clocking_evidence`
2. Display from `manual_clocking` JOIN `manual_clocking_evidence`
3. Later sync → uploads images then times to server

## Why Two Tables?

**Design pattern: Normalized data**

**`manual_clocking`:**
- Core clocking data (times, status, metadata)
- One row per learner per day
- Can exist without evidence (pending upload)

**`manual_clocking_evidence`:**
- Evidence files (photos, signatures)
- Separate because evidence can be:
  - Uploaded later (offline → online)
  - Resubmitted if rejected
  - Downloaded separately for review
- Unique constraint: One evidence record per learner per day

**Benefits:**
- Can query times without loading large image paths
- Can update times without touching evidence
- Can sync times separately from evidence files
- Can validate evidence separately (file existence checks)

## Testing Required

### Test Offline Clock-In:
1. Go offline
2. Clock in using signature+geofence method
3. Query SQLite:
   ```sql
   SELECT * FROM manual_clocking WHERE synced = 0;
   SELECT * FROM manual_clocking_evidence WHERE synced = 0;
   ```
4. Verify record in BOTH tables
5. Come online and wait for sync
6. Verify both tables show `synced = 1`
7. Verify server has records in both MySQL tables

### Test Offline Clock-Out:
1. Clock in while online
2. Go offline
3. Clock out
4. Query SQLite: verify clock_out_time in `manual_clocking`
5. Query SQLite: verify signature_out in `manual_clocking_evidence`
6. Come online and verify sync

## Status
✅ **FIXED** - Now correctly saves to both tables
✅ **Matches PHP** - Local storage mirrors server structure
✅ **Ready to build** - All table references corrected

## Next Steps
1. Build APK: `flutter build apk --release`
2. Test offline clock-in → verify both tables populated
3. Test offline clock-out → verify both tables updated
4. Test sync → verify both tables marked synced
5. Verify server has records in both MySQL tables
