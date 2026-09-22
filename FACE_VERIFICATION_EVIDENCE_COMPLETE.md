# Face Verification & Evidence Saving - Complete Implementation

## ✅ What Was Implemented

### 1. **New Direct-Save API: `mobile/save_clocking_evidence.php`**

**Purpose:** Save clocking evidence (signatures, photos, GPS) directly to MySQL when online, **without using sync mechanism**.

**Features:**
- ✅ Accepts clock-in or clock-out evidence
- ✅ Saves signature to `clocking/signatures/` folder
- ✅ Saves face photo to `clocking/face_photos/` folder  
- ✅ Saves GPS coordinates (latitude, longitude, accuracy)
- ✅ Saves verification method (face/signature/security_question)
- ✅ Saves face_log_id (from face verification API)
- ✅ **UPSERTS** to `learner_clocking_evidence` table (UPDATE if exists, INSERT if new)
- ✅ No duplicate records for same learner+date

**Endpoint:**
```
POST /mobile/save_clocking_evidence.php
Content-Type: application/json

{
  "learner_id": 11443,
  "clock_date": "2026-09-21",
  "event_type": "clock_in",  // or "clock_out"
  "signature": "data:image/png;base64,...",
  "photo": "data:image/jpeg;base64,...",
  "latitude": -26.123456,
  "longitude": 27.123456,
  "accuracy": 15.5,
  "verification_method": "face",
  "face_log_id": 123
}
```

**Response:**
```json
{
  "success": true,
  "message": "Clock_in evidence saved successfully",
  "action": "updated",
  "learner_id": 11443,
  "clock_date": "2026-09-21",
  "signature_saved": true,
  "photo_saved": true
}
```

---

### 2. **Flutter Changes: Smart Online/Offline Handling**

**Modified File:** `lib/backup_clock_in_page.dart`

#### **Clock-In Flow:**

1. Learner verifies face → captures `_capturedFacePhotoBase64` and `_faceLogId`
2. Learner signs → captures signature
3. GPS captured → lat/lng/accuracy
4. **Check connectivity:**
   - **If ONLINE:** Call `save_clocking_evidence.php` directly ✅
   - **If OFFLINE or API fails:** Save to SQLite, sync later ✅

#### **Clock-Out Flow:**

1. Learner verifies face again → must match clock-in person
2. If face doesn't match → **BLOCKED** with error message ✅
3. Learner signs → captures signature
4. GPS captured
5. **Check connectivity:**
   - **If ONLINE:** Call `save_clocking_evidence.php` directly ✅
   - **If OFFLINE or API fails:** Save to SQLite, sync later ✅

#### **New Helper Method:**
```dart
Future<void> _saveEvidenceLocally({
  required String learnerId,
  required String date,
  required String eventType,
  required String signatureData,
  required double? latitude,
  required double? longitude,
  required double? accuracy,
  required String verificationMethod,
}) async {
  // Saves to SQLite for offline scenarios
  // Will be synced via sync_clocking_evidence.php when online
}
```

---

### 3. **Data Flow**

#### **When ONLINE:**
```
Clock-In/Out
    ↓
Verify Face → Capture Photo
    ↓
Sign → Capture Signature
    ↓
Get GPS Coordinates
    ↓
✅ ONLINE → Call save_clocking_evidence.php DIRECTLY
    ↓
Signature → clocking/signatures/learner{ID}_{event}_{timestamp}.png
Photo → clocking/face_photos/learner{ID}_{event}_{timestamp}.jpg
GPS + Method + face_log_id → learner_clocking_evidence table
    ↓
✅ DONE (No sync needed)
```

#### **When OFFLINE:**
```
Clock-In/Out
    ↓
Verify Face → Capture Photo
    ↓
Sign → Capture Signature
    ↓
Get GPS Coordinates
    ↓
❌ OFFLINE → Save to SQLite
    ↓
learner_clocking_evidence table (phone database)
    ↓
⏳ SYNC LATER via sync_clocking_evidence.php
    ↓
✅ DONE when back online
```

---

## 📊 Database Tables

### **MySQL: `learner_clocking_evidence`**

| Column | Type | Description |
|--------|------|-------------|
| `id` | INT | Primary key |
| `LearnerID` | INT | Learner ID |
| `clock_date` | DATE | Clock date (YYYY-MM-DD) |
| `clock_in_signature` | LONGTEXT | Signature filename |
| `clock_in_photo` | LONGTEXT | Photo filename |
| `clock_in_latitude` | DECIMAL(10,8) | GPS latitude |
| `clock_in_longitude` | DECIMAL(11,8) | GPS longitude |
| `clock_in_accuracy` | DECIMAL(6,2) | GPS accuracy (meters) |
| `clock_in_verification_method` | VARCHAR(50) | face/signature/etc |
| `clock_in_face_log_id` | INT | Face verification log ID |
| `clock_in_timestamp` | DATETIME | Timestamp |
| `clock_out_signature` | LONGTEXT | Signature filename |
| `clock_out_photo` | LONGTEXT | Photo filename |
| `clock_out_latitude` | DECIMAL(10,8) | GPS latitude |
| `clock_out_longitude` | DECIMAL(11,8) | GPS longitude |
| `clock_out_accuracy` | DECIMAL(6,2) | GPS accuracy (meters) |
| `clock_out_verification_method` | VARCHAR(50) | face/signature/etc |
| `clock_out_face_log_id` | INT | Face verification log ID |
| `clock_out_timestamp` | DATETIME | Timestamp |
| `created_at` | TIMESTAMP | Created timestamp |
| `updated_at` | TIMESTAMP | Updated timestamp |

**Unique Constraint:** `UNIQUE(LearnerID, clock_date)` → No duplicates

---

## 🔄 Existing APIs (Unchanged)

### **`mobile/clocking/clockin.php`**
- Still used for clock-in time recording
- Saves to `learner_clocking` table
- Handles geofencing validation
- **NOT MODIFIED** ✅

### **`mobile/clocking/clockout.php`**
- Still used for clock-out time recording
- Updates `learner_clocking` table
- Calculates contact time
- **NOT MODIFIED** ✅

### **`mobile/sync_clocking_evidence.php`**
- Still used for offline sync
- Syncs multiple evidence records from SQLite → MySQL
- Called automatically when phone reconnects
- **NOT MODIFIED** ✅

---

## 📁 File Structure

```
clocking/
├── signatures/
│   ├── learner11443_clock_in_1705123456.png
│   └── learner11443_clock_out_1705134567.png
└── face_photos/
    ├── learner11443_clock_in_1705123456.jpg
    └── learner11443_clock_out_1705134567.jpg

mobile/
├── clocking/
│   ├── clockin.php (existing - time recording)
│   └── clockout.php (existing - time recording)
├── save_clocking_evidence.php (NEW - direct evidence save)
└── sync_clocking_evidence.php (existing - offline sync)
```

---

## ✅ Verification Steps

### **After APK Installation:**

1. **Test Online Clock-In:**
   - Clock in with face verification
   - Sign
   - Check MySQL `learner_clocking_evidence` table
   - Verify record exists with:
     - `clock_in_signature` = filename
     - `clock_in_photo` = filename
     - `clock_in_latitude/longitude/accuracy` = GPS data
     - `clock_in_verification_method` = 'face'
   - Check `clocking/signatures/` folder → signature file exists
   - Check `clocking/face_photos/` folder → photo file exists

2. **Test Online Clock-Out:**
   - Clock out with face verification
   - Verify face matches (should succeed)
   - Sign
   - Check MySQL `learner_clocking_evidence` table
   - Verify **SAME RECORD** updated with:
     - `clock_out_signature` = filename
     - `clock_out_photo` = filename
     - `clock_out_latitude/longitude/accuracy` = GPS data
     - `clock_out_verification_method` = 'face'
   - No duplicate records created ✅

3. **Test Wrong Person at Clock-Out:**
   - Clock in with Person A
   - Try to clock out with Person B's face
   - Should see error: "Identity verification failed! The face does not match the person who clocked in"
   - Clock-out should be blocked ✅

4. **Test Offline Mode:**
   - Turn off WiFi/data
   - Clock in with face + signature
   - Check SQLite `learner_clocking_evidence` table
   - Verify `synced = 0`
   - Turn on WiFi/data
   - Wait for sync service to run
   - Check MySQL → record should appear
   - Check SQLite → `synced = 1`

5. **Verify No Duplicates:**
   ```sql
   SELECT LearnerID, clock_date, COUNT(*) as records
   FROM learner_clocking_evidence
   GROUP BY LearnerID, clock_date
   HAVING COUNT(*) > 1;
   ```
   Should return 0 rows ✅

---

## 🚀 Deployment Checklist

- [x] Create `mobile/save_clocking_evidence.php`
- [x] Update `lib/backup_clock_in_page.dart`
- [x] Add `_saveEvidenceLocally()` helper method
- [x] Test connectivity check logic
- [ ] **Build new APK**
- [ ] **Upload `save_clocking_evidence.php` to server**
- [ ] **Create folders on server:**
  - `clocking/signatures/` (755 permissions)
  - `clocking/face_photos/` (755 permissions)
- [ ] **Install APK on phone**
- [ ] **Test all scenarios above**

---

## 🎯 Summary

**Problem:** Evidence was being synced instead of saved directly when online.

**Solution:**
1. Created new API `save_clocking_evidence.php` for direct online saves
2. Modified Flutter to check connectivity and use direct API when online
3. Falls back to SQLite + sync only when offline or API fails
4. Signatures and photos save directly to server folders when online
5. No sync overhead for online users ✅

**Result:** 
- **Online users** → Evidence saves immediately to MySQL + files
- **Offline users** → Evidence saves to SQLite, syncs when reconnected
- **Best of both worlds** ✅
