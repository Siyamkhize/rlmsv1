# Signature Geofence Clock-In Table Fix

## Issue
The `signature_geofence_clock_in_page.dart` was querying the wrong table for manual clocking data. It was using `learner_clocking` but should use `manual_clocking` to match the PHP endpoint.

## Root Cause
- **PHP endpoint** (`mobile/get_manual_clocking_status.php`) queries `manual_clocking` table
- **Flutter app** was querying `learner_clocking` table
- This mismatch caused the app to not find clocking records saved through the signature+geofence flow

## Investigation
Checked `mobile/get_manual_clocking_status.php`:
```sql
SELECT 
    ld.LearnerID,
    ld.Name,
    ld.Surname,
    mc.clock_in_time,
    mc.clock_out_time,
    mc.contact_time
FROM learnerdetails ld
LEFT JOIN manual_clocking mc ON ld.LearnerID = mc.LearnerID 
    AND mc.clock_date = ? 
    AND mc.is_manual_attendance = 1
WHERE ld.classID = ?
```

The endpoint clearly uses **`manual_clocking`** table with the join alias `mc`.

## Tables in Database

### `manual_clocking` (CORRECT - used by signature+geofence flow)
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

### `learner_clocking` (WRONG - used by fingerprint flow)
This table is for the regular fingerprint-based clocking, NOT manual signature+geofence clocking.

## Fix Applied

Changed all references from `learner_clocking` to `manual_clocking` in `lib/signature_geofence_clock_in_page.dart`:

### Change 1: Sync offline records query
**Before:**
```dart
final offlineRecords = await db.query(
  'learner_clocking',
  where: 'synced = ?',
  whereArgs: [0],
);
```

**After:**
```dart
final offlineRecords = await db.query(
  'manual_clocking',
  where: 'synced = ?',
  whereArgs: [0],
);
```

### Change 2: Mark record as synced
**Before:**
```dart
await db.update(
  'learner_clocking',
  {'synced': 1},
  where: 'LearnerID = ? AND clock_date = ?',
```

**After:**
```dart
await db.update(
  'manual_clocking',
  {'synced': 1},
  where: 'LearnerID = ? AND clock_date = ?',
```

### Change 3: Check existing records for offline clock-in
**Before:**
```dart
final existingRecords = await db.query(
  'learner_clocking',
  where: 'LearnerID = ? AND clock_date = ?',
  whereArgs: [learnerID, clockDate],
```

**After:**
```dart
final existingRecords = await db.query(
  'manual_clocking',
  where: 'LearnerID = ? AND clock_date = ?',
  whereArgs: [learnerID, clockDate],
```

### Change 4: Update existing record
**Before:**
```dart
await db.update(
  'learner_clocking',
  updatedData,
  where: 'LearnerID = ? AND clock_date = ?',
```

**After:**
```dart
await db.update(
  'manual_clocking',
  updatedData,
  where: 'LearnerID = ? AND clock_date = ?',
```

## Files Modified
1. ✅ `lib/signature_geofence_clock_in_page.dart` - All 4 queries updated to use `manual_clocking`

## Testing Required
1. Clock in using signature+geofence flow
2. Verify record appears immediately in the UI
3. Go offline and clock in again
4. Come back online and verify offline sync works
5. Clock out and verify contact time is calculated correctly

## Impact
- **Before**: App saved to `manual_clocking` but queried `learner_clocking`, so records appeared missing
- **After**: App consistently uses `manual_clocking` table throughout, matching the server endpoint

## Related
- This is separate from the `device_epoch` and `is_offline_sync` keys that were just added to clock-in/clock-out payloads
- Those changes are in the HTTP request payloads, while this fix is about which SQLite table to query locally

## Status
✅ **Fixed** - All table references corrected
⚠️ **Needs Testing** - APK rebuild required to verify
