# Manual Clocking Evidence - Offline-First Sync INSTALLED ✅

**Date:** October 3, 2026  
**Device:** RZ8X10CKD0B  
**APK Size:** 198.2MB  
**Build Time:** 220 seconds

---

## 🎯 What Was Fixed

### 1. ✅ Learner Name Display Bug
**Before:** Watermark showed "null null" instead of learner name  
**After:** Shows correct "Name Surname" from database

**Root Cause:** Field name mismatch
- Dashboard used: `Name` and `Surname` 
- Clock-in page expected: `FirstName` and `LastName`

**Fix:** Updated `lib/signature_geofence_clock_in_page.dart` line 453-460

---

### 2. ✅ Offline Database Schema
Added `manual_clocking_evidence` table to SQLite for offline storage:

```sql
CREATE TABLE manual_clocking_evidence (
  evidence_id INTEGER PRIMARY KEY AUTOINCREMENT,
  LearnerID INTEGER NOT NULL,
  clock_date TEXT NOT NULL,
  signature_in TEXT,           -- Base64 or filename
  signature_out TEXT,          -- Base64 or filename
  face_in TEXT,               -- Base64 or filename
  face_out TEXT,              -- Base64 or filename
  created_at TEXT DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
  synced INTEGER DEFAULT 0,   -- Sync tracking
  UNIQUE(LearnerID, clock_date)
)
```

---

### 3. ✅ Server-Side Sync Endpoints

**Created 2 new PHP endpoints:**

1. **`mobile/sync_manual_clocking_evidence.php`**
   - Accepts batch uploads of unsynced evidence
   - Receives base64-encoded images
   - Saves images to `mobile/manual_clocking_evidence/faces/` and `/signatures/`
   - Inserts/updates MySQL `manual_clocking_evidence` table
   - Returns success status for each record

2. **`mobile/get_manual_clocking_evidence.php`**
   - Fetches evidence records from server
   - **JOINs with learnerdetails** to get `Name` and `Surname`
   - Returns full learner names for display
   - Supports filtering by date and learner ID

**Updated:**
- `mobile/get_manual_clocking_status.php` - Changed to use `Name`/`Surname`

---

### 4. ✅ Offline-First Sync Service

**Created:** `lib/services/manual_clocking_evidence_sync_service.dart`

**Features:**
- ✅ Save evidence offline with base64 images
- ✅ Update evidence when clock-out happens
- ✅ Track unsynced records (synced=0)
- ✅ Batch sync to server when online
- ✅ Auto-sync on connectivity change
- ✅ Get unsynced count for UI badge
- ✅ Download from server for viewing

---

## 📱 How It Works Now

### Offline Clock-In Flow
```
1. Capture face photo (ML Kit validation)
2. Capture signature
3. Convert images to base64
4. Save to local manual_clocking_evidence table (synced=0)
5. Save to manual_clocking table
6. Show success - NO INTERNET NEEDED ✅
```

### Auto-Sync When Online
```
1. Connection detected
2. Fetch records where synced=0
3. Batch upload to sync_manual_clocking_evidence.php
4. Server saves images as files
5. Server updates MySQL database
6. Mark local records as synced=1
7. Images now viewable on server ✅
```

### Name Display
```
1. Fetch learners with Name and Surname fields
2. Pass to SmartFramedCameraCapture widget
3. Watermark shows: "Learner: John Smith (ID: 11425)"
4. No more "null null" ✅
```

---

## 🧪 Testing Guide

### Test 1: Offline Clock-In
1. Turn OFF WiFi and Mobile Data
2. Open RLMSS app
3. Navigate to class dashboard
4. Select "Manual Clock-In (Signature + Geofence)"
5. Select a learner
6. **Capture face photo** - Check watermark shows correct name
7. Sign signature
8. Verify: "Clock-in successful" message
9. Check: Record saved locally (no sync error)

### Test 2: Verify Learner Name on Watermark
1. During face capture, check bottom watermark
2. Should show: "Learner: [Name] [Surname] (ID: [LearnerID])"
3. Should NOT show: "Learner: null null"
4. Timestamp should show current date/time

### Test 3: Auto-Sync
1. Clock-in 2-3 learners while OFFLINE
2. Turn ON WiFi
3. Wait 10-30 seconds
4. Check logs: Should see "Auto-sync complete: X records synced"
5. Verify: Images uploaded to server
6. Check MySQL: `manual_clocking_evidence` table has new records

### Test 4: View Synced Data
1. Go to server admin panel
2. Call: `get_manual_clocking_evidence.php?clock_date=2026-10-03`
3. Verify: Response includes learner names
4. Check: `learner_full_name` field is NOT null

### Test 5: Clock-Out Offline
1. Turn OFF internet again
2. Clock-out same learner
3. Verify: Clock-out signature and face saved
4. Turn ON internet
5. Check: Clock-out images synced to server

---

## 📁 Server Folder Structure

Ensure these folders exist on your server:

```
mobile/
├── manual_clocking_evidence/
│   ├── faces/
│   │   ├── face_in_11425_2026-10-03_1696348800.jpg
│   │   └── face_out_11425_2026-10-03_1696370400.jpg
│   └── signatures/
│       ├── signature_in_11425_2026-10-03_1696348800.png
│       └── signature_out_11425_2026-10-03_1696370400.png
├── sync_manual_clocking_evidence.php  ← NEW
├── get_manual_clocking_evidence.php   ← NEW
└── get_manual_clocking_status.php     ← UPDATED
```

**Create folders if needed:**
```bash
mkdir -p mobile/manual_clocking_evidence/faces
mkdir -p mobile/manual_clocking_evidence/signatures
chmod -R 755 mobile/manual_clocking_evidence
```

---

## 🗄️ Database Tables

### Server MySQL Table
```sql
CREATE TABLE IF NOT EXISTS manual_clocking_evidence (
    evidence_id INT(11) NOT NULL AUTO_INCREMENT PRIMARY KEY,
    LearnerID INT(11) NOT NULL,
    clock_date DATE NOT NULL,
    signature_in VARCHAR(255) NULL,    -- Filename: signature_in_*.png
    signature_out VARCHAR(255) NULL,   -- Filename: signature_out_*.png
    face_in VARCHAR(255) NULL,         -- Filename: face_in_*.jpg
    face_out VARCHAR(255) NULL,        -- Filename: face_out_*.jpg
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY unique_learner_date_evidence (LearnerID, clock_date),
    FOREIGN KEY (LearnerID) REFERENCES learnerdetails(LearnerID) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

**Deploy table:**
```bash
php deploy_manual_clocking_evidence.php
```

Or manually run:
```bash
mysql -u root -p your_database < sql/create_manual_clocking_evidence_table.sql
```

---

## 📊 Key Methods Available

```dart
import 'package:rlmss/services/manual_clocking_evidence_sync_service.dart';

final syncService = ManualClockingEvidenceSyncService();

// Save evidence offline (clock-in)
await syncService.saveEvidenceOffline(
  learnerID: 11425,
  clockDate: '2026-10-03',
  signatureInBase64: base64String,
  faceInBase64: base64String,
);

// Update evidence (clock-out)
await syncService.updateEvidenceOffline(
  learnerID: 11425,
  clockDate: '2026-10-03',
  signatureOutBase64: base64String,
  faceOutBase64: base64String,
);

// Manual sync all unsynced records
final result = await syncService.syncToServer();
print('Synced: ${result['synced_count']} records');

// Auto-sync (call on connectivity change)
await syncService.autoSyncIfOnline();

// Get unsynced count (for badge)
final count = await syncService.getUnsyncedCount();
print('$count records waiting to sync');

// Get specific evidence
final evidence = await syncService.getEvidence(
  learnerID: 11425,
  clockDate: '2026-10-03',
);
```

---

## 🎯 What to Test First

### Priority 1: Name Display ⭐⭐⭐
1. Clock-in any learner
2. Check watermark during face capture
3. Verify: Shows "Learner: [Real Name] (ID: [ID])"
4. **If still shows "null null":** Check logs, ensure Name/Surname fields are in learners list

### Priority 2: Offline Storage ⭐⭐⭐
1. Turn OFF internet
2. Clock-in a learner
3. Check SQLite database: `manual_clocking_evidence` table
4. Verify: Record exists with `synced=0`

### Priority 3: Sync to Server ⭐⭐
1. Turn ON internet
2. Trigger sync (automatic or manual)
3. Check server: Images in `mobile/manual_clocking_evidence/` folders
4. Check MySQL: `manual_clocking_evidence` table updated
5. Check app: `synced=1` for those records

---

## 🐛 Troubleshooting

### Issue: Still shows "null null"
**Check:**
1. Dashboard learners list has `Name` and `Surname` fields
2. `signature_geofence_clock_in_page.dart` line 453-460 uses correct field names
3. APK was rebuilt after fix

### Issue: Sync fails
**Check:**
1. Server endpoint accessible: `https://your-server.com/mobile/sync_manual_clocking_evidence.php`
2. Folders exist: `mobile/manual_clocking_evidence/faces/` and `/signatures/`
3. Folder permissions: `chmod -R 755`
4. MySQL table exists: `manual_clocking_evidence`

### Issue: Images not showing on server
**Check:**
1. Base64 encoding is correct in app
2. PHP can write to folders (permissions)
3. MySQL records have filenames, not base64 data
4. Files actually exist in folders

---

## 📝 Files Modified/Created

### Modified:
1. ✅ `lib/signature_geofence_clock_in_page.dart` - Fixed Name/Surname fields
2. ✅ `lib/database_helper.dart` - Added manual_clocking_evidence table
3. ✅ `mobile/get_manual_clocking_status.php` - Updated to use Name/Surname

### Created:
1. ✅ `mobile/sync_manual_clocking_evidence.php` - Batch sync endpoint
2. ✅ `mobile/get_manual_clocking_evidence.php` - Fetch evidence with names
3. ✅ `lib/services/manual_clocking_evidence_sync_service.dart` - Sync service

---

## ✅ Installation Complete

**Device:** RZ8X10CKD0B  
**Status:** ✅ Installed successfully  
**Ready to Test:** YES

### Next Steps:
1. ✅ Launch app and login
2. ✅ Test learner name display on watermark
3. ✅ Test offline clock-in (store locally)
4. ✅ Test auto-sync when online
5. ✅ Verify images on server
6. ✅ Check MySQL database records

---

## 🎉 Benefits Summary

✅ **Works Completely Offline** - No internet required for clock-in/out  
✅ **Auto-Sync** - Uploads automatically when connection available  
✅ **Proper Names** - Shows real learner names, not "null null"  
✅ **Efficient Sync** - Batches multiple records in one request  
✅ **No Duplicates** - Unique constraints prevent duplicate evidence  
✅ **Audit Trail** - Timestamps track when records created/updated  
✅ **Image Storage** - Server stores images as files for viewing  
✅ **Sync Status** - Track which records are synced vs pending

---

**Ready for production testing!** 🚀
