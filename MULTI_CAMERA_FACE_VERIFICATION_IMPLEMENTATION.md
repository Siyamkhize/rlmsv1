# Multi-Camera Face Verification Implementation

## Overview
Implement dual-camera face verification where both front and back cameras are enrolled separately, and verification matches against BOTH with the same 0.95 threshold. A learner passes if they match EITHER stored embedding.

## Status: IN PROGRESS

### ✅ COMPLETED

1. **SQLite Schema Migration (v15)**
   - Created migration script: `sql/005_add_camera_facing_multi_embedding.sql`
   - Added `camera_facing` column to `learner_face_cache` table
   - Changed primary key from `learner_id` to `(learner_id, camera_facing)`
   - Added `camera_facing` column to `learner_face_verification_queue` table
   - Migration preserves existing data (marks as 'back' camera)
   - Updated `database_helper.dart` to version 15 with migration logic

2. **Dart Service Updates** (`lib/services/offline_face_verification_service.dart`)
   - ✅ Updated `cacheEmbedding()` - Now accepts `cameraFacing` parameter
   - ✅ Replaced `getCachedEmbedding()` with `getCachedEmbeddings()` - Returns ALL embeddings
   - ✅ Added `hasBothCameras()` - Check if learner has both front+back enrolled
   - ✅ Added `getEnrolledCameras()` - Get list of which cameras are enrolled
   - ✅ Updated `verifyOffline()` - Matches against ALL embeddings, takes BEST score
   - ✅ Updated `_queueVerificationLog()` - Includes `cameraFacing` parameter
   - ✅ Updated `syncVerificationLogs()` - Sends `camera_facing` to server

### 🔨 TODO

3. **MySQL Schema Migration**
   - Run `sql/005_add_camera_facing_multi_embedding.sql` on MySQL server
   - Add `camera_facing` column to `learner_face` table
   - Change unique constraint from `(learner_id, active)` to `(learner_id, camera_facing, active)`
   - Add `camera_facing` column to `learner_face_verification_log` table

4. **PHP Endpoints**
   - Update `mobile/enroll_face.php` or equivalent:
     - Accept `camera_facing` parameter
     - Store with composite key `(learner_id, camera_facing)`
   
   - Update `mobile/verify_face.php` or equivalent:
     - Query ALL embeddings for learner
     - Compare against all, take BEST score
     - Log which camera was used
     - Return matched camera in response
   
   - Update `mobile/sync_face_verification_logs.php`:
     - Accept `camera_facing` in log data
     - Store in `learner_face_verification_log` table

5. **Update Enrollment UI**
   - Modify enrollment flow to capture BOTH cameras sequentially
   - Flow: Back camera first → Front camera second
   - Only show "Enrollment Complete" when `hasBothCameras() == true`
   - Show progress: "Back camera enrolled, now enrolling front camera..."
   
   Files to update:
   - Find enrollment screen (search for `cacheEmbedding` calls)
   - Add sequential capture logic
   - Add UI feedback for which camera is being enrolled

6. **Update Verification Calls**
   - Find all calls to `verifyOffline()`
   - Add `cameraFacing` parameter (detect from camera lens direction)
   - Update to handle new response format with `matchedCamera`
   
   Files likely to update:
   - `lib/backup_clock_in_page.dart` (clock-in/out verification)
   - Any other pages that call face verification

7. **SimpleFaceCapture Widget**
   - Add camera detection or parameter to know which camera is active
   - Pass `cameraFacing` to callback/verification
   - Or detect from `CameraDescription.lensDirection`

## Technical Details

### Database Structure

**SQLite: `learner_face_cache`**
```sql
CREATE TABLE learner_face_cache (
    learner_id INTEGER NOT NULL,
    camera_facing TEXT NOT NULL CHECK(camera_facing IN ('front', 'back')),
    embedding TEXT NOT NULL,
    quality_score REAL DEFAULT NULL,
    enrolled_at TEXT DEFAULT NULL,
    updated_at TEXT DEFAULT NULL,
    synced INTEGER DEFAULT 0,
    PRIMARY KEY (learner_id, camera_facing)
);
```

**MySQL: `learner_face`**
```sql
ALTER TABLE learner_face 
ADD COLUMN camera_facing ENUM('front', 'back') NOT NULL DEFAULT 'back';

ALTER TABLE learner_face 
ADD UNIQUE KEY unique_learner_camera_active (learner_id, camera_facing, active);
```

### Verification Logic

```dart
// 1. Get ALL embeddings for learner
final embeddings = await getCachedEmbeddings(learnerId);

// 2. Compare live capture against each stored embedding
double bestScore = -1.0;
String? matchedCamera;

for (final cached in embeddings) {
  final score = cosineSimilarity(liveEmbedding, cached['embedding']);
  if (score > bestScore) {
    bestScore = score;
    matchedCamera = cached['camera_facing'];
  }
}

// 3. Verify if best score meets threshold
final verified = bestScore >= 0.95;
```

### Enrollment Flow

```
1. User starts enrollment
2. Capture BACK camera embedding
   - Cache with camera_facing='back'
3. Show "Back camera enrolled ✓"
4. Capture FRONT camera embedding
   - Cache with camera_facing='front'
5. Check hasBothCameras()
6. Show "Enrollment complete ✓✓"
```

## Benefits

1. **No camera dependency** - Works with front or back camera at clock-in
2. **Better reliability** - Cross-camera matching naturally scores lower, so having both reduces false rejections
3. **Same threshold** - Both cameras use 0.95, no camera-specific tuning needed
4. **Audit trail** - Logs track which camera was used for analysis

## Testing Checklist

- [ ] Run SQLite migration (automatic on app upgrade to v15)
- [ ] Run MySQL migration script
- [ ] Test enrollment flow (both cameras)
- [ ] Test verification with back camera after back enrollment
- [ ] Test verification with front camera after front enrollment
- [ ] Test verification with opposite camera (cross-camera matching)
- [ ] Verify MySQL tables have camera_facing data
- [ ] Check verification logs include camera_facing
- [ ] Confirm 0.95 threshold applies to both cameras

## Migration Notes

- **Existing data preserved**: All current embeddings marked as 'back' camera
- **Backward compatible**: Service still works with single-camera enrollments
- **No data loss**: Migration copies data before table recreation
- **Automatic**: SQLite migration runs on app startup after code update
- **Manual**: MySQL migration requires running SQL script on server

## Next Steps

1. Run MySQL migration on production database
2. Update PHP endpoints for multi-camera support
3. Update enrollment UI to capture both cameras
4. Update all verification calls to pass `cameraFacing`
5. Test thoroughly before deploying
6. Monitor verification logs to compare front vs back camera scores
