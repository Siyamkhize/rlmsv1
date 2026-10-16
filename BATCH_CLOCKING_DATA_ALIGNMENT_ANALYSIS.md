# Batch Clocking Data Alignment Analysis

**Date:** October 13, 2026  
**Source:** `signature_geofence_clock_in_page.dart` → `save_class_batch_clocking.php`

## Critical Finding: ❌ MISALIGNMENT DETECTED

The Dart code (`signature_geofence_clock_in_page.dart`) does **NOT** use `save_class_batch_clocking.php`. Instead, it uses individual clocking endpoints.

---

## Current Implementation

### What `signature_geofence_clock_in_page.dart` Actually Does

**Clock-In Process:**
1. Calls `save_manual_clocking_images.php` to upload images
2. Then calls `save_manual_clockin.php` to save clock-in record

**Clock-Out Process:**
1. Calls `save_manual_clocking_images.php` to upload images  
2. Then calls `save_manual_clockout.php` to save clock-out record

### Dart Code Evidence

```dart
// CLOCK-IN (Line ~1054)
final uploadUrl = Uri.parse(AppConfig.buildUrl('save_manual_clocking_images.php'));
// ... then ...
final clockInUrl = Uri.parse(AppConfig.buildUrl('save_manual_clockin.php'));

// CLOCK-OUT (Line ~1229)
final uploadUrl = Uri.parse(AppConfig.buildUrl('save_manual_clocking_images.php'));
// ... then ...
final url = Uri.parse(AppConfig.buildUrl('save_manual_clockout.php'));
```

**❌ `save_class_batch_clocking.php` is NEVER called**

---

## What Data is Sent (Individual Clocking)

### From Dart Code

#### Clock-In Payload (`save_manual_clockin.php`)
```dart
final payload = {
  'learner_id': learnerID,
  'clock_date': currentDate,
  'clock_in_time': clockInTime,
  'signature_in': signatureInFilename,  // Filename from previous upload
  'face_in': faceInFilename,           // Filename from previous upload
  'latitude': userLat,
  'longitude': userLon,
  'accuracy': userAccuracy,
  'device_epoch': DateTime.now().millisecondsSinceEpoch ~/ 1000,
  'is_offline_sync': false,
};
```

#### Clock-Out Payload (`save_manual_clockout.php`)
```dart
final payload = {
  'learner_id': learnerID,
  'clock_date': currentDate,
  'clock_out_time': clockOutTime,
  'signature_out': signatureOutFilename,  // Filename from previous upload
  'face_out': faceOutFilename,           // Filename from previous upload
  'latitude': userLat,
  'longitude': userLon,
  'accuracy': userAccuracy,
  'device_epoch': DateTime.now().millisecondsSinceEpoch ~/ 1000,
  'is_offline_sync': false,
};
```

---

## What `save_class_batch_clocking.php` Expects

### Expected Structure
```php
{
  'batch_id': string,
  'class_id': string,
  'total_learners': integer,
  'client_timestamp': string,
  'learner_clockings': [
    {
      'learner_id': string,
      'type': 'in' | 'out',
      'latitude': float,
      'longitude': float,
      'accuracy': float,
      'face_image': base64_string,
      'signature_image': base64_string,
      'clock_date': string,
      'idempotency_key': string
    }
  ]
}
```

### What PHP Saves to Database
```php
INSERT INTO manual_clocking 
(user_id, class_id, learner_id, clock_date, clock_time, type, 
 latitude, longitude, accuracy, batch_id, client_timestamp, created_at) 
VALUES (?, ?, ?, ?, NOW(), ?, ?, ?, ?, ?, ?, NOW())
```

### Evidence Storage
```php
INSERT INTO learner_clocking_evidence 
(clocking_id, learner_id, face_filename, signature_filename, batch_id, created_at) 
VALUES (?, ?, ?, ?, ?, NOW())
```

---

## Database Table Alignment

### Tables Used by Individual Clocking

Assuming `save_manual_clockin.php` and `save_manual_clockout.php` use:

**Table: `manual_clocking`**
| Column | Type | Source |
|--------|------|--------|
| LearnerID | VARCHAR | ✅ `learner_id` |
| clock_date | DATE | ✅ `clock_date` |
| clock_in_time | TIME | ✅ `clock_in_time` |
| clock_out_time | TIME | ✅ `clock_out_time` |
| contact_time | VARCHAR | ⚠️ Calculated by PHP |
| is_manual_attendance | TINYINT | ⚠️ Set by PHP (1) |
| synced | TINYINT | ⚠️ Set by PHP (1 for online) |

**Table: `manual_clocking_evidence`**
| Column | Type | Source |
|--------|------|--------|
| LearnerID | VARCHAR | ✅ `learner_id` |
| clock_date | DATE | ✅ `clock_date` |
| signature_in | TEXT | ✅ `signatureInFilename` |
| face_in | TEXT | ✅ `faceInFilename` |
| signature_out | TEXT | ✅ `signatureOutFilename` |
| face_out | TEXT | ✅ `faceOutFilename` |
| synced | TINYINT | ⚠️ Set by PHP |

### Tables Used by Batch Clocking

**Table: `manual_clocking`**
| Column | Expected by PHP | Stored? |
|--------|-----------------|---------|
| user_id | ✅ From auth | ✅ Yes |
| class_id | ✅ From payload | ✅ Yes |
| learner_id | ✅ From payload | ✅ Yes |
| clock_date | ✅ From payload | ✅ Yes |
| clock_time | ✅ NOW() | ✅ Yes |
| type | ✅ From payload ('in'/'out') | ✅ Yes |
| latitude | ✅ From payload | ✅ Yes |
| longitude | ✅ From payload | ✅ Yes |
| accuracy | ✅ From payload | ✅ Yes |
| batch_id | ✅ From payload | ✅ Yes |
| client_timestamp | ✅ From payload | ✅ Yes |
| created_at | ✅ NOW() | ✅ Yes |

**⚠️ ISSUE:** Batch clocking uses different column names than individual clocking!

**Table: `learner_clocking_evidence`**
| Column | Expected by PHP | Stored? |
|--------|-----------------|---------|
| clocking_id | ✅ From INSERT ID | ✅ Yes |
| learner_id | ✅ From payload | ✅ Yes |
| face_filename | ✅ Saved file path | ✅ Yes |
| signature_filename | ✅ Saved file path | ✅ Yes |
| batch_id | ✅ From payload | ✅ Yes |
| created_at | ✅ NOW() | ✅ Yes |

---

## Critical Differences

### 1. **Database Schema Mismatch**

**Individual Clocking Schema:**
- Uses `clock_in_time` and `clock_out_time` (separate columns)
- Uses `manual_clocking` and `manual_clocking_evidence` tables

**Batch Clocking Schema:**
- Uses `clock_time` and `type` ('in'/'out') columns
- Uses `manual_clocking` and `learner_clocking_evidence` tables

**❌ These are DIFFERENT table structures!**

### 2. **Evidence Storage Method**

**Individual Clocking:**
1. Upload images first → get filenames
2. Store filenames in database

**Batch Clocking:**
1. Send base64 images in batch payload
2. PHP decodes and saves files
3. PHP stores filenames in database

### 3. **Missing GPS Tracking**

**Neither system stores:**
- `latitude` ❌
- `longitude` ❌
- `accuracy` ❌
- `device_epoch` ❌
- `is_offline_sync` ❌

These values are sent but never persisted (columns don't exist).

---

## Recommendations

### Option 1: Use Batch Clocking (Recommended for Rural Areas)

**Pros:**
- Single request for entire class
- Better for poor connectivity
- Built-in idempotency
- Transactional (all or nothing)

**Cons:**
- Requires Dart code changes
- Need to verify database schema compatibility

**Changes Needed:**
1. Modify `signature_geofence_clock_in_page.dart` to batch learners
2. Send all learners in single request to `save_class_batch_clocking.php`
3. Ensure database schema matches batch expectations

### Option 2: Keep Individual Clocking (Current)

**Pros:**
- No code changes needed
- Works with current endpoints
- Proven in production

**Cons:**
- Multiple network requests per class
- Slower in poor connectivity
- No built-in batching

### Option 3: Hybrid Approach

1. Try batch if online
2. Fall back to individual if batch fails
3. Queue for sync if offline

---

## Database Migration Needed (If Adding GPS Tracking)

```sql
-- SQLite (local database)
ALTER TABLE manual_clocking ADD COLUMN user_latitude TEXT;
ALTER TABLE manual_clocking ADD COLUMN user_longitude TEXT;
ALTER TABLE manual_clocking ADD COLUMN user_accuracy TEXT;
ALTER TABLE manual_clocking ADD COLUMN device_epoch INTEGER;
ALTER TABLE manual_clocking ADD COLUMN is_offline_sync TEXT;

-- MySQL (server database)
ALTER TABLE manual_clocking 
  ADD COLUMN user_latitude VARCHAR(50),
  ADD COLUMN user_longitude VARCHAR(50),
  ADD COLUMN user_accuracy VARCHAR(50),
  ADD COLUMN device_epoch BIGINT,
  ADD COLUMN is_offline_sync TINYINT(1) DEFAULT 0;
```

---

## Conclusion

**Current Status:** ✅ Individual clocking works  
**Batch Clocking:** ❌ NOT being used by Dart code  
**Data Alignment:** ⚠️ Schema mismatch between systems  
**GPS Tracking:** ❌ Data sent but not stored

**Action Required:**
1. Decide: Batch vs Individual clocking
2. If Batch: Update Dart code to use `save_class_batch_clocking.php`
3. If GPS tracking needed: Run database migrations
4. Test alignment between Dart payloads and PHP expectations
