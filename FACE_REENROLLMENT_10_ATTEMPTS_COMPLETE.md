# Face Re-enrollment After 10 Failed Attempts - COMPLETE

**Date**: September 23, 2026  
**Feature**: Automatic face re-enrollment after 10 failed verification attempts in backup clock-in

## Summary

Modified the backup clock-in page to allow **10 verification attempts** (increased from 3) and automatically trigger **face re-enrollment** if all 10 attempts fail. This prevents permanent lockouts when a learner's face template is corrupted or outdated.

---

## Changes Made

### 1. Flutter App Changes

#### `lib/backup_clock_in_page.dart`
- **Line 2564**: Changed verification limit from 3 to 10 attempts
- **Lines 2836-2905**: Added automatic re-enrollment dialog and flow after 10 failed attempts
- **Line 2297**: Added `_deleteOldFaceEnrollment()` helper method
- **Line 2309**: Updated `_enrollFace()` to accept `isReenrollment` parameter with custom dialog text

**New Flow**:
1. Learner attempts face verification (up to 10 times)
2. After 10 failures, system shows re-enrollment dialog
3. If learner agrees, old face data is deleted
4. New face enrollment is triggered
5. System automatically verifies with new enrollment
6. If successful, clock-in proceeds

#### `lib/services/offline_face_verification_service.dart`
- **Added method**: `deleteLocalEmbedding(int learnerId)` - Deletes local cached face embeddings for re-enrollment

#### `lib/repositories/face_verification_repository.dart`
- **Added method**: `deleteFaceEnrollment(int learnerId)` - Deletes server-side face enrollment

### 2. PHP Backend Changes

#### `mobile/delete_face_enrollment.php` (NEW)
- Endpoint to delete learner face enrollment from `learner_faces` table
- Allows clean re-enrollment by removing old data
- Uses mysqli prepared statements with `$conn` connection

**Usage**:
```bash
POST /mobile/delete_face_enrollment.php
Body: {"learner_id": 12345}
```

#### `clear_learner_face_failed_attempts.php` (NEW)
- Utility script to manually clear failed face attempts
- Useful for unlocking learners who hit the 10-attempt limit before re-enrolling
- Uses mysqli prepared statements with `$conn` connection

**Usage**:
```bash
GET /clear_learner_face_failed_attempts.php?learner_id=12345
```

### 3. Database Changes

#### `sql/007_create_learner_face_failed_attempts.sql` (NEW)
- Creates `learner_face_failed_attempts` table to track failed attempts
- Auto-cleanup event removes attempts older than 24 hours
- Prevents permanent lockouts

**Table Structure**:
```sql
CREATE TABLE learner_face_failed_attempts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    learner_id VARCHAR(50) NOT NULL,
    attempt_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    attempt_type ENUM('verification', 'enrollment') DEFAULT 'verification',
    failure_reason VARCHAR(255),
    ip_address VARCHAR(45),
    INDEX idx_learner_timestamp (learner_id, attempt_timestamp)
);
```

---

## User Experience

### Before (3 Attempts)
1. Learner fails verification 3 times
2. Clock-in blocked permanently
3. Manual intervention required (admin must re-enroll learner)

### After (10 Attempts with Auto Re-enrollment)
1. Learner fails verification 10 times
2. System offers automatic re-enrollment
3. Learner accepts and captures new face photo
4. System replaces old face data with new enrollment
5. Verification proceeds automatically with new data
6. Clock-in succeeds

---

## Dialog Messages

### Re-enrollment Prompt (After 10 Failures)
```
Icon: 🔄 (Blue refresh icon)
Title: "Re-enrollment Required"

Message:
"Face verification failed after 10 attempts.

Your face may have changed or the original enrollment 
may be unclear.

Would you like to re-enroll your face now? This will 
replace your existing face data."

Buttons: [Cancel] [Re-enroll Face]
```

### Enrollment Dialog (During Re-enrollment)
```
Icon: 🔄 (Blue refresh icon)  
Title: "Face Re-enrollment"

Message:
"Your previous face enrollment will be replaced with 
a new one.

Please capture a clear face photo. This will replace 
your existing face data."

Tips:
• Look directly at the camera
• Ensure good lighting
• Remove glasses if possible
• Keep a neutral expression

Buttons: [Cancel] [Re-register Face]
```

---

## Technical Details

### Verification Attempt Counter
- **Variable**: `_faceVerificationAttempts` (in `_BackupClockInPageState`)
- **Reset**: At start of each clock-in/clock-out flow
- **Maximum**: 10 attempts
- **Scope**: Per clock-in session (not persistent across app restarts)

### Re-enrollment Process
1. **Delete old data**:
   - Server: `DELETE FROM learner_faces WHERE learner_id = ?`
   - Local cache: `DELETE FROM learner_face_cache WHERE learner_id = ?`
   
2. **Reset flag**:
   - `_isFaceEnrolled = false`

3. **New enrollment**:
   - Calls `_enrollFace(learnerId, isReenrollment: true)`
   - Captures new face photo via `SimpleFaceCapture`
   - Extracts new embedding via `FaceEmbeddingService`
   - Saves to server via `FaceVerificationRepository.enrollFace()`
   - Caches locally via `OfflineFaceVerificationService.cacheEmbedding()`

4. **Auto-verification**:
   - After successful re-enrollment, immediately calls `_verifyWithFace()` again
   - Resets `_faceVerificationAttempts = 0` for fresh start
   - Uses new enrollment for verification

### Offline Support
- Re-enrollment works offline (saves to local cache)
- Deletion methods handle offline gracefully (no errors if server unreachable)
- Failed deletions don't block re-enrollment

---

## Testing Steps

1. **Test Re-enrollment Flow**:
   ```
   a. Start backup clock-in for a learner
   b. Intentionally fail face verification 10 times (cover camera, wrong person, etc.)
   c. Verify re-enrollment dialog appears
   d. Accept re-enrollment
   e. Capture new face photo
   f. Verify automatic verification proceeds
   g. Confirm clock-in completes successfully
   ```

2. **Test Cancellation**:
   ```
   a. Fail verification 10 times
   b. Decline re-enrollment in dialog
   c. Verify clock-in is blocked
   d. Verify error message shown
   ```

3. **Test Manual Unlock** (if needed):
   ```bash
   # If learner needs immediate unlock without re-enrollment
   curl "http://your-server/clear_learner_face_failed_attempts.php?learner_id=12345"
   ```

---

## Files Modified

### Dart/Flutter
- `lib/backup_clock_in_page.dart` - Main clock-in flow with 10-attempt limit and re-enrollment
- `lib/services/offline_face_verification_service.dart` - Added `deleteLocalEmbedding()`
- `lib/repositories/face_verification_repository.dart` - Added `deleteFaceEnrollment()`

### PHP
- `mobile/delete_face_enrollment.php` (NEW) - Delete face enrollment endpoint
- `clear_learner_face_failed_attempts.php` (NEW) - Manual unlock utility

### SQL
- `sql/007_create_learner_face_failed_attempts.sql` (NEW) - Failed attempts tracking table

---

## Configuration

No configuration changes needed - feature is automatic and built into the backup clock-in flow.

### Constants
- **Max Attempts**: 10 (hardcoded in `_verifyWithFace()` method)
- **Auto-cleanup**: 24 hours (in SQL EVENT for failed attempts table)

---

## Benefits

1. **Reduced manual intervention** - Learners can self-recover from face verification issues
2. **Better UX** - More attempts mean legitimate learners aren't locked out by lighting/angle issues
3. **Automatic recovery** - Re-enrollment happens in-flow without admin involvement
4. **Maintains security** - Still requires physical presence for face capture
5. **Offline-compatible** - Works without internet connection

---

## Next Steps

1. **Deploy SQL table**:
   ```bash
   mysql -u your_user -p your_database < sql/007_create_learner_face_failed_attempts.sql
   ```

2. **Upload PHP files**:
   - Upload `mobile/delete_face_enrollment.php` to server
   - Upload `clear_learner_face_failed_attempts.php` to server root

3. **Build and deploy new APK**:
   ```bash
   flutter clean
   flutter build apk --release --split-per-abi
   ```

4. **Test on device** with a learner account

---

## Support

If a learner is locked out and needs immediate access:
- Use the manual unlock script: `clear_learner_face_failed_attempts.php?learner_id=XXXXX`
- Or manually delete from database: `DELETE FROM learner_face_failed_attempts WHERE learner_id = 'XXXXX';`

---

**Status**: ✅ COMPLETE - Ready for testing and deployment
