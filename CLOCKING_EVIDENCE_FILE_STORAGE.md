# Clocking Evidence File Storage Guide

## Overview
Face photos and signatures are saved **LOCALLY on the mobile device** during clock-in/clock-out. Only the **FILENAMES** are sent to the server and stored in the database.

## Storage Architecture

### Mobile Device (Local Storage)
Images are saved to the app's private documents directory:

**Base Path:**
```
/data/data/com.yourapp.rlmss/app_flutter/
```

**Subdirectories:**
1. **Signatures:** `{APP_DOCUMENTS}/signatures/`
2. **Face Photos:** `{APP_DOCUMENTS}/face_photos/`

### Server Database (MySQL)
Only **filenames** are stored in the `learner_clocking_evidence` table:

**Columns (VARCHAR 255):**
- `clock_in_signature` - e.g., `signature_21562_20240915_083045_in.png`
- `clock_in_photo` - e.g., `face_21562_20240915_083045_in.jpg`
- `clock_out_signature` - e.g., `signature_21562_20240915_170215_out.png`
- `clock_out_photo` - e.g., `face_21562_20240915_170215_out.jpg`

## File Naming Convention

### Signatures (PNG format)
```
signature_{LEARNER_ID}_{YYYYMMDD_HHMMSS}_{in|out}.png

Examples:
- signature_21562_20240915_083045_in.png    (clock-in)
- signature_21562_20240915_170215_out.png   (clock-out)
```

### Face Photos (JPEG format)
```
face_{LEARNER_ID}_{YYYYMMDD_HHMMSS}_{in|out}.jpg

Examples:
- face_21562_20240915_083045_in.jpg    (clock-in)
- face_21562_20240915_170215_out.jpg   (clock-out)
```

## Implementation Details

### 1. Signature Saving (`backup_clock_in_page.dart`)

**Function:** `_saveSignatureLocally()`
**Location:** Lines 2600-2635

```dart
Future<String> _saveSignatureLocally(String learnerId, String base64Signature,
    {String suffix = 'out'}) async {
  try {
    // Decode base64
    final bytes = base64Decode(base64Signature);
    
    // Get app documents directory
    final directory = await getApplicationDocumentsDirectory();
    
    // Create signatures folder
    final signaturesDir = Directory('${directory.path}/signatures');
    if (!await signaturesDir.exists()) {
      await signaturesDir.create(recursive: true);
    }
    
    // Generate filename
    final now = DateTime.now();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(now);
    final filename = 'signature_${learnerId}_${timestamp}_$suffix.png';
    final filePath = '${signaturesDir.path}/$filename';
    
    // Write file
    final file = File(filePath);
    await file.writeAsBytes(bytes);
    
    // Return ONLY filename (not full path)
    return filename;
  } catch (e) {
    return ''; // Return empty string on error
  }
}
```

**Called at:**
- **Clock-in:** Line 1767 with `suffix: 'in'`
- **Clock-out:** Line 2021 with `suffix: 'out'`

### 2. Face Photo Saving (`backup_clock_in_page.dart`)

**Function:** `_saveFacePhotoLocally()`
**Location:** Lines 2638-2680

```dart
Future<String?> _saveFacePhotoLocally(String learnerId, String? base64Photo,
    {String suffix = 'in'}) async {
  if (base64Photo == null || base64Photo.isEmpty) {
    return null;
  }
  
  try {
    // Decode base64
    final bytes = base64Decode(base64Photo);
    
    // Get app documents directory
    final directory = await getApplicationDocumentsDirectory();
    
    // Create face_photos folder
    final photosDir = Directory('${directory.path}/face_photos');
    if (!await photosDir.exists()) {
      await photosDir.create(recursive: true);
    }
    
    // Generate filename
    final now = DateTime.now();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(now);
    final filename = 'face_${learnerId}_${timestamp}_$suffix.jpg';
    final filePath = '${photosDir.path}/$filename';
    
    // Write file
    final file = File(filePath);
    await file.writeAsBytes(bytes);
    
    // Return ONLY filename (not full path)
    return filename;
  } catch (e) {
    return null; // Return null on error
  }
}
```

**Called at:**
- **Clock-in:** Line 3187 with `suffix: 'in'`
- **Clock-out:** Similar logic (when face verification enabled for clock-out)

### 3. Server Storage (`save_clocking_evidence.php`)

**What it receives:**
```json
{
  "learner_id": "21562",
  "event_type": "clock_in",
  "signature_filename": "signature_21562_20240915_083045_in.png",
  "photo_filename": "face_21562_20240915_083045_in.jpg",
  "latitude": "25.7479",
  "longitude": "28.2293",
  "accuracy": "15.5",
  "verification_method": "face_recognition",
  "face_log_id": "12345",
  "timestamp": "2024-09-15 08:30:45"
}
```

**What it does:**
1. Receives **filename only** (not the actual image bytes)
2. Validates and escapes the filename string
3. Inserts/updates the filename in the database

**Database Query (INSERT example):**
```sql
INSERT INTO learner_clocking_evidence (
  LearnerID,
  clock_date,
  clock_in_signature,
  clock_in_photo,
  clock_in_latitude,
  clock_in_longitude,
  clock_in_accuracy,
  clock_in_verification_method,
  clock_in_face_log_id,
  clock_in_timestamp,
  created_at
) VALUES (
  21562,
  '2024-09-15',
  'signature_21562_20240915_083045_in.png',
  'face_21562_20240915_083045_in.jpg',
  25.7479,
  28.2293,
  15.5,
  'face_recognition',
  12345,
  '2024-09-15 08:30:45',
  NOW()
)
```

## File Access Flow

### Clock-In Process
```
1. Learner clocks in with face verification
2. Face photo captured as base64 string
3. _saveFacePhotoLocally() called
   ├─ Creates /face_photos/ directory (if needed)
   ├─ Decodes base64 to bytes
   ├─ Saves as face_21562_20240915_083045_in.jpg
   └─ Returns filename only
4. Signature captured as base64 string
5. _saveSignatureLocally() called
   ├─ Creates /signatures/ directory (if needed)
   ├─ Decodes base64 to bytes
   ├─ Saves as signature_21562_20240915_083045_in.png
   └─ Returns filename only
6. Evidence data sent to server with FILENAMES
7. Server saves filenames to database (NOT the actual images)
```

### Clock-Out Process
Same as clock-in, but with `suffix: 'out'`

## Why Filenames Only?

**Problem with Base64:**
- 5-8 MB payloads per clock-in
- Network timeouts (30+ seconds)
- Server memory issues
- Database bloat

**Solution with Filenames:**
- ~200 bytes per clock-in
- Sub-second response times
- Minimal database storage
- Images stay on device for offline use

## Accessing the Images

### On Mobile Device
Images are accessible via the file system:
```dart
final directory = await getApplicationDocumentsDirectory();
final signaturePath = '${directory.path}/signatures/$filename';
final photoPath = '${directory.path}/face_photos/$filename';

// Read the file
final file = File(signaturePath);
final bytes = await file.readAsBytes();
```

### From Database Query
The database only has filenames, not images:
```sql
SELECT 
  LearnerID,
  clock_in_signature,
  clock_in_photo,
  clock_in_timestamp
FROM learner_clocking_evidence
WHERE LearnerID = 21562;

-- Result:
-- clock_in_signature: signature_21562_20240915_083045_in.png
-- clock_in_photo: face_21562_20240915_083045_in.jpg
```

## Future: Syncing Images to Server

If you want to upload the actual images to the server later:

### Option 1: Separate Upload Endpoint
Create `upload_clocking_images.php` that:
1. Receives image file + filename
2. Saves to server directory (e.g., `/uploads/clocking_evidence/`)
3. Maintains same filename structure

### Option 2: Background Sync
Add background job that:
1. Reads local images from device
2. Uploads to server when connected to WiFi
3. Marks as synced in local database

### Server Directory Structure (if implementing upload)
```
/var/www/html/uploads/clocking_evidence/
  ├── signatures/
  │   ├── signature_21562_20240915_083045_in.png
  │   └── signature_21562_20240915_170215_out.png
  └── face_photos/
      ├── face_21562_20240915_083045_in.jpg
      └── face_21562_20240915_170215_out.jpg
```

## Storage Requirements

### Per Learner Per Day
- 2 signatures (clock-in + clock-out): ~50 KB each = 100 KB
- 2 face photos (clock-in + clock-out): ~200 KB each = 400 KB
- **Total per day:** ~500 KB per learner

### For 100 Learners Over 30 Days
- 100 learners × 30 days × 500 KB = **1.5 GB**

### Mobile Storage Considerations
- Images accumulate over time
- Consider cleanup policy (delete after 30 days?)
- Or upload to server and delete local copy

## Troubleshooting

### Images Not Saving Locally
1. Check permissions in `AndroidManifest.xml`
2. Check `getApplicationDocumentsDirectory()` returns valid path
3. Check device has storage space
4. Look for errors in logs: `[BACKUP] Error saving...`

### Filenames Not in Database
1. Check network connectivity
2. Check `save_clocking_evidence.php` logs at `mobile/view_evidence_log.php`
3. Verify `real_escape_string()` not mangling filenames
4. Check VARCHAR(255) is large enough

### Orphaned Files (files without database records)
- File saved locally but network failed before database insert
- Keep files anyway - they can be recovered manually

## Summary

✅ **Images saved:** Mobile device only (`/signatures/` and `/face_photos/`)  
✅ **Database stores:** Filenames only (VARCHAR 255)  
✅ **Server PHP:** Never receives actual image bytes  
✅ **Benefit:** 99% smaller payload, no timeouts  
✅ **Trade-off:** Images not centrally stored (by design)  

If you need centralized image storage, implement a separate upload mechanism as described above.
