# Facilitator Face Authentication Flow - Updated
**Date**: Current Session  
**Status**: ✅ Complete - APK Built & Installed

## Overview
Facilitators can now enroll **either** fingerprints **OR** face recognition for authentication. When they don't have a fingerprint scanner available, the system automatically uses face enrollment instead.

## Updated Authentication Flow

### First-Time Enrollment Flow
1. **Login with Class ID**
   - Facilitator enters their class ID
   - System checks if they have any authentication method enrolled (fingerprints OR face)

2. **No Authentication Enrolled**
   - System navigates to `FacilitatorFingerprintPage` with `isFirstTimeSetup: true`
   - Page shows dialog: "Do you have a fingerprint scanner available and connected?"

3. **Scanner Dialog Options**

   **Option A: Press "Yes"** (Has Scanner)
   - Initializes fingerprint scanner
   - Enrolls 3 fingerprints
   - Continues to clock-in flow

   **Option B: Press "No"** (No Scanner) ⭐ NEW BEHAVIOR
   - Automatically navigates to `FacilitatorFaceEnrollPage`
   - Captures 3 face images (front, left, right)
   - Extracts embeddings using ML Kit
   - Uploads to server (`mobile/enrol_facilitator_face.php`)
   - On success: Returns to login → proceeds to clock-in
   - On failure/cancel: Shows "Face enrollment required to continue"

### Daily Clock-In Flow

After enrollment, facilitators must clock in daily:

1. **Has Fingerprints Enrolled**
   - Uses fingerprint verification for clock-in
   - Signature capture
   - Geofencing verification
   - Proceeds to dashboard

2. **Has Face Enrolled** ⭐ NEW
   - Uses face verification for clock-in (`_facilitatorFaceClockIn`)
   - Captures face image
   - Verifies against server (`mobile/verify_facilitator_face.php`)
   - Signature capture
   - Geofencing verification
   - Proceeds to dashboard

## Key Changes from Previous Implementation

### ❌ Removed: Choice Dialog
Previously showed dialog:
```
"Choose Authentication Method"
• Fingerprint: Requires scanner hardware
• Face Recognition: Works with your device camera
[Fingerprint] [Face]
```

### ✅ Now: Automatic Flow
Scanner dialog directly triggers appropriate enrollment:
- "Yes" → Fingerprint enrollment
- "No" → Face enrollment (automatic, no choice needed)

## Files Modified

### 1. `lib/main.dart`
**Changes:**
- Removed choice dialog between fingerprint/face
- Now navigates directly to `FacilitatorFingerprintPage` for first-time setup
- Scanner dialog inside that page handles the decision
- After enrollment, re-checks which method was enrolled
- Uses appropriate verification method for daily clock-in

**Key Code:**
```dart
if (!hasFingerprints && !hasFaceEnrolled) {
  // Navigate to fingerprint page which handles scanner dialog
  // If no scanner, it will automatically use face enrollment
  final enrolled = await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => FacilitatorFingerprintPage(
        facilitatorId: facilitatorIdInt,
        facilitatorName: fullName,
        isFirstTimeSetup: true,
      ),
    ),
  ) ?? false;
  
  // Re-check what was enrolled
  if (enrolled) {
    // Check if fingerprints or face was enrolled
  }
}
```

### 2. `lib/facilitator_fingerprint_page.dart`
**Changes:**
- Added import: `import 'facilitator_face_enroll_page.dart';`
- Modified "No" button logic in scanner dialog
- When "No" pressed: automatically navigates to face enrollment
- After face enrollment completes, pops back with success/failure

**Key Code:**
```dart
if (hasScanner == true) {
  // Initialize fingerprint scanner
  await _initializeSensor();
} else {
  // No scanner, use face recognition flow
  setState(() {
    _enrollmentStatus = 'Starting face recognition enrollment...';
  });
  
  final faceEnrolled = await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => FacilitatorFaceEnrollPage(
        facilitatorId: widget.facilitatorId,
        facilitatorName: widget.facilitatorName,
        isFirstTimeSetup: widget.isFirstTimeSetup,
      ),
    ),
  ) ?? false;
  
  if (faceEnrolled) {
    // Success - pop back with true
    Navigator.pop(context, true);
  }
}
```

## User Experience Flow

### Scenario 1: Facilitator with Scanner
```
1. Login with Class ID
2. "Do you have scanner?" → Press "Yes"
3. Place finger 3 times
4. "Please clock in to start your day"
5. Verify fingerprint
6. Sign signature
7. Geofencing check
8. → Dashboard
```

### Scenario 2: Facilitator without Scanner ⭐
```
1. Login with Class ID
2. "Do you have scanner?" → Press "No"
3. Automatic redirect to face enrollment
4. Capture face (front, left, right)
5. Upload embeddings
6. "Please clock in to start your day"
7. Verify face with camera
8. Sign signature
9. Geofencing check
10. → Dashboard
```

### Scenario 3: Daily Clock-In (Face Enrolled)
```
1. Login with Class ID
2. System detects face enrolled (not fingerprints)
3. "Please clock in to start your day"
4. Capture face for verification
5. Server verifies face
6. Sign signature
7. Geofencing check
8. → Dashboard
```

## Database Tables

### `facilitator_face`
Stores enrolled face embeddings:
```sql
- id (INT, PRIMARY KEY)
- facilitator_id (INT, UNIQUE)
- face_embedding (TEXT) -- JSON array of 128 float values
- enrollment_date (DATETIME)
- last_updated (DATETIME)
```

### `facilitator_face_verification_log`
Logs face verification attempts:
```sql
- id (INT, PRIMARY KEY)
- facilitator_id (INT)
- verification_time (DATETIME)
- success (TINYINT)
- similarity_score (DECIMAL)
- device_info (VARCHAR)
```

## API Endpoints

### `mobile/enrol_facilitator_face.php`
- **Purpose**: Store face embeddings for facilitator
- **Method**: POST
- **Parameters**: 
  - `facilitator_id`
  - `face_embedding` (128-dimension array)
- **Response**: `{success: true, message: "..."}`

### `mobile/verify_facilitator_face.php`
- **Purpose**: Verify facilitator face for clock-in
- **Method**: POST
- **Parameters**:
  - `facilitator_id`
  - `face_embedding` (128-dimension array)
- **Response**: `{verified: true/false, similarity_score: 0.XX, message: "..."}`
- **Threshold**: 0.6 (cosine similarity)

### `mobile/check_facilitator_face_enrollment.php`
- **Purpose**: Check if facilitator has face enrolled
- **Method**: GET
- **Parameters**: `facilitator_id`
- **Response**: `{enrolled: true/false, enrollment_date: "..."}`

## Testing Steps

1. **Clear facilitator auth data** (optional - for testing first-time flow):
   ```sql
   DELETE FROM facilitator_fingerprints WHERE facilitator_id = [ID];
   DELETE FROM facilitator_face WHERE facilitator_id = [ID];
   ```

2. **Test No Scanner Flow**:
   - Login with facilitator class ID
   - Press "No" on scanner dialog
   - Should automatically go to face enrollment
   - Capture 3 face images
   - Verify upload success
   - Return to login
   - Clock in with face verification
   - Sign signature
   - Complete geofencing
   - Reach dashboard

3. **Test Daily Clock-In**:
   - Login next day with same facilitator
   - Should detect face enrolled
   - Prompt for clock-in
   - Use face verification
   - Complete signature + geofencing
   - Reach dashboard

## Technical Details

### Face Embedding Service
Uses `FaceEmbeddingService` from existing learner face recognition:
```dart
final embedding = await FaceEmbeddingService().extractEmbedding(imagePath);
// Returns List<double>? with 128 dimensions
```

### Repository Layer
`FacilitatorFaceRepository` handles all API calls:
- `checkFaceEnrolled(facilitatorId)` 
- `enrollFace(facilitatorId, embedding)`
- `verifyFace(facilitatorId, embedding)`

### Server-Side Verification
PHP endpoint calculates cosine similarity:
```php
function cosineSimilarity($vec1, $vec2) {
    $dot = array_sum(array_map(fn($a, $b) => $a * $b, $vec1, $vec2));
    $mag1 = sqrt(array_sum(array_map(fn($x) => $x * $x, $vec1)));
    $mag2 = sqrt(array_sum(array_map(fn($x) => $x * $x, $vec2)));
    return $dot / ($mag1 * $mag2);
}
```

## APK Information
- **File**: `build/app/outputs/flutter-apk/app-release.apk`
- **Size**: 197.6 MB
- **Build Time**: 4 minutes 1 second
- **Status**: ✅ Installed on device

## Benefits

1. **No Hardware Dependency**: Facilitators without scanners can still use the system
2. **Seamless UX**: No confusing choice dialog, automatic flow based on hardware availability
3. **Consistent Security**: Face verification provides similar security to fingerprints
4. **Flexible**: System supports both authentication methods
5. **Easy Enrollment**: Only 3 face captures needed (vs 3 fingerprint scans)

## Troubleshooting

### Face Enrollment Fails
- Check camera permissions
- Ensure good lighting
- Face should be clearly visible
- Try again with better positioning

### Face Verification Fails
- Similarity score might be too low
- Server threshold is 0.6 (60% match)
- Re-enrollment may be needed
- Check server logs in `facilitator_face_verification_log`

### Scanner Dialog Doesn't Appear
- Only shows on first-time setup
- If facilitator already has auth enrolled, goes straight to clock-in
- Clear data from DB to test first-time flow

---

**Implementation Complete** ✅  
Facilitators can now authenticate with either fingerprints or face recognition based on hardware availability.
