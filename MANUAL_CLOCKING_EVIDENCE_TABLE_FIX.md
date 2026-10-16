# Manual Clocking Evidence Table Migration Fix

**Date**: October 16, 2026  
**APK**: `app-release-v20-manual-evidence-table.apk` (71.5MB)  
**Database Version**: 19 → 20  
**Device**: RZ8X306F7TZ

## Problem Identified

**Symptom**: Offline clock-in with signature + face photo crashed with error:
```
DatabaseException: no such table: manual_clocking_evidence
```

**Root Cause**: 
- The `manual_clocking_evidence` table was defined in the database `onCreate` block (for new installs)
- BUT it was NOT added to the `onUpgrade` migration path
- This meant:
  - ✅ **New installs**: Got the table automatically
  - ❌ **Existing installs**: Never got the table when upgrading from old versions

Device RZ8X306F7TZ had an old database (version < 20) and never received the table migration.

## Solution Implemented

### 1. Added Version 20 Migration

**File**: `lib/database_helper.dart`

**Changes**:
```dart
// Bumped database version from 19 to 20
version: 20,

// Added new migration block
if (oldVersion < 20) {
  // v20: Create manual_clocking_evidence table for signature + face photo evidence
  debugPrint('[DB] ✅ v20 migration: Creating manual_clocking_evidence table');

  try {
    // Check if table already exists (defensive)
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='manual_clocking_evidence'");

    if (tables.isEmpty) {
      await db.execute('''
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
      ''');
      debugPrint('[DB] ✅ Created manual_clocking_evidence table');
    } else {
      debugPrint('[DB] ℹ️ manual_clocking_evidence table already exists');
    }
  } catch (e) {
    debugPrint('[DB] ❌ Error creating manual_clocking_evidence table: $e');
  }
}
```

### 2. Table Schema

```sql
CREATE TABLE manual_clocking_evidence (
  evidence_id INTEGER PRIMARY KEY AUTOINCREMENT,
  LearnerID INTEGER NOT NULL,
  clock_date TEXT NOT NULL,
  signature_in TEXT,          -- Base64 signature for clock-in
  signature_out TEXT,         -- Base64 signature for clock-out
  face_in TEXT,               -- Base64 face photo for clock-in
  face_out TEXT,              -- Base64 face photo for clock-out
  created_at TEXT DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
  synced INTEGER DEFAULT 0,   -- 0 = unsynced, 1 = synced to server
  UNIQUE(LearnerID, clock_date),
  FOREIGN KEY (LearnerID) REFERENCES learnerdetails(LearnerID)
)
```

## How It Works

### Migration Process (Automatic on App Launch)

1. **User opens app** after installing new APK
2. **Database helper detects**: Current version (19) < New version (20)
3. **Triggers upgrade**: Runs `onUpgrade(db, 19, 20)`
4. **Checks table existence**: Prevents duplicate creation
5. **Creates table**: With full schema including indexes and foreign keys
6. **App ready**: Offline manual clocking now works

### Offline Manual Clocking Flow

**Clock-In**:
```dart
// 1. Save to manual_clocking table
await db.insert('manual_clocking', {
  'LearnerID': learnerID,
  'clock_date': '2026-10-16',
  'clock_in_time': '08:30:00',
  'manual_reason': 'Signature + Geofence',
  'status': 'Pending',
  'synced': 0
});

// 2. Save to manual_clocking_evidence table (NOW WORKS!)
await db.insert('manual_clocking_evidence', {
  'LearnerID': learnerID,
  'clock_date': '2026-10-16',
  'signature_in': base64SignatureString,
  'face_in': base64FacePhotoString,
  'synced': 0
});
```

**Clock-Out**:
```dart
// 1. Update manual_clocking table
await db.update('manual_clocking', {...}, 
  where: 'LearnerID = ? AND clock_date = ?');

// 2. Update manual_clocking_evidence table (NOW WORKS!)
await db.update('manual_clocking_evidence', {
  'signature_out': base64SignatureString,
  'face_out': base64FacePhotoString,
}, where: 'LearnerID = ? AND clock_date = ?');
```

## Testing Instructions

### 1. Verify Table Creation

After installing the new APK, check the database using the app's debug tools:

```dart
// Open Database Inspector from Dashboard
// Run query:
SELECT name FROM sqlite_master WHERE type='table' AND name='manual_clocking_evidence';

// Should return: manual_clocking_evidence
```

### 2. Test Offline Manual Clock-In

1. **Turn off WiFi** on device
2. **Open Clock-In page**
3. **Select a learner** who needs manual clocking
4. **Capture signature** on signature pad
5. **Capture face photo** using camera
6. **Verify geofence** (within 200m of site)
7. **Click "Clock In"**
8. **Success**: Should save without error
9. **Check logs**: Should show `[SIGNATURE_GEO] Offline clock-in saved for: [LearnerID] to manual_clocking + manual_clocking_evidence`

### 3. Verify Offline Data Storage

```sql
-- Check manual_clocking records
SELECT * FROM manual_clocking WHERE synced = 0;

-- Check manual_clocking_evidence records (NOW SHOULD WORK!)
SELECT evidence_id, LearnerID, clock_date, 
       LENGTH(signature_in) as sig_size, 
       LENGTH(face_in) as face_size, 
       synced 
FROM manual_clocking_evidence 
WHERE synced = 0;
```

### 4. Test Online Sync

1. **Turn WiFi back on**
2. **Open Dashboard**
3. **Click "Sync Now"** or wait for auto-sync
4. **Check server**: Data should sync to MySQL tables:
   - `manual_clocking` table
   - `manual_clocking_evidence` table
5. **Check folders**: Images should appear in:
   - `manual_clocking_evidence/faces/`
   - `manual_clocking_evidence/signatures/`

## Server-Side Status

✅ **Already Fixed** (from previous session):
- `mobile/save_manual_clocking_images.php`: Corrected table name from `learner_clocking_evidence` to `manual_clocking_evidence`
- Folder structure exists: `manual_clocking_evidence/faces/` and `/signatures/`
- MySQL table verified with correct schema

## Database Versions History

| Version | Description | Date |
|---------|-------------|------|
| 1-2 | Initial schema | - |
| 3 | Facilitator fingerprint + clocking | - |
| 4 | Learner pathways cache | - |
| 5 | Pothole checklist documents | - |
| 10 | Material receipt form columns | - |
| 11 | Location columns (Province, District, Municipality) | - |
| 12 | learner_clocking_evidence (face recognition) | - |
| 13 | learner_face_cache (offline face verification) | - |
| 14 | Province/District/Municipality sync fix | - |
| 15 | Multi-camera face verification | - |
| 16 | Facilitator clocking evidence | - |
| 17 | Facilitator clock_in_method column | - |
| 18 | offline_sessions table | - |
| 19 | Location columns fix | - |
| **20** | **manual_clocking_evidence table migration** | **2026-10-16** |

## Why This Happened

This is a common database migration pitfall:

1. **Developer adds table** to `onCreate` block ✅
2. **Developer forgets** to add migration in `onUpgrade` block ❌
3. **New users**: Everything works (onCreate runs)
4. **Existing users**: Table missing (onUpgrade never creates it)

**Lesson**: When adding a new table to `onCreate`, ALWAYS add a corresponding migration to `onUpgrade` for the next version.

## Files Modified

- ✅ `lib/database_helper.dart`: Added version 20 migration
- ✅ `build/app/outputs/flutter-apk/app-release.apk`: Built new APK (71.5MB)
- ✅ `app-release-v20-manual-evidence-table.apk`: Deployed to device RZ8X306F7TZ

## Next Steps

1. ✅ **Install APK** on device RZ8X306F7TZ (DONE)
2. **Launch app** - migration will run automatically
3. **Test offline manual clock-in** with signature + face photo
4. **Verify data saves** to SQLite without errors
5. **Test online sync** to MySQL + folder images
6. **Monitor logs** for any remaining issues

## Expected Outcome

After installing this APK:
- ✅ Offline manual clock-in will work (no more "no such table" error)
- ✅ Signature + face photo will save to SQLite
- ✅ When online, data will sync to MySQL + server folders
- ✅ Both online and offline manual clocking fully functional

---

**Status**: Ready for testing on device RZ8X306F7TZ
