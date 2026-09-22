# Face Recognition Clock-In Workflow

## Overview
Complete workflow for clock-in/out with face recognition as primary verification, falling back to security questions after 3 failed attempts.

---

## User Flow

### Step 1: ID Number Entry
```
┌─────────────────────────────────┐
│  Enter Learner ID Number        │
│  [__________]                   │
│                                 │
│  [Search Learner]               │
└─────────────────────────────────┘
```

**Actions:**
1. User enters ID number
2. App searches for learner (offline-first: local DB → then server)
3. If found, check if face is enrolled

---

### Step 2: Face Enrollment Check

**Backend Check:**
```php
// In verify_learner_face.php or new check_face_enrollment.php
SELECT id, learner_id 
FROM learner_face 
WHERE learner_id = ? AND active = 1
```

**Two Scenarios:**

#### Scenario A: Face NOT Enrolled
```
┌─────────────────────────────────┐
│  ⚠️ No Face Registered          │
│                                 │
│  Please register your face      │
│  for faster clock-in            │
│                                 │
│  [Register Face Now]            │
│  [Skip - Use Security Questions]│
└─────────────────────────────────┘
```

**If "Register Face Now":**
1. Open camera
2. Guide user to position face (ML Kit face detection)
3. Check quality (head pose, eyes open, lighting)
4. Extract 192-dim embedding (MobileFaceNet)
5. Send to `mobile/enrol_learner_face.php`
6. Save to `learner_face` table
7. Continue to Step 3

#### Scenario B: Face IS Enrolled
```
┌─────────────────────────────────┐
│  ✅ Face registered             │
│                                 │
│  [Verify Face to Clock In]      │
└─────────────────────────────────┘
```
Go directly to Step 3.

---

### Step 3: Face Verification (Max 3 Attempts)

```
┌─────────────────────────────────┐
│  📷 Face Verification           │
│                                 │
│  Position your face in frame    │
│                                 │
│  [Camera Preview]               │
│                                 │
│  Attempt 1 of 3                 │
│                                 │
│  [Cancel]                       │
└─────────────────────────────────┘
```

**Process:**
1. Open camera with live preview
2. Detect face using ML Kit
3. Check quality:
   - Head pose within ±15° yaw, ±10° roll
   - Eyes open >80%
   - Face size >15% of frame
4. Extract embedding (192-dim)
5. Send to `mobile/verify_learner_face.php`
6. Server computes cosine similarity with stored embedding
7. Compare against threshold (default: 0.72)

**Outcomes:**

#### ✅ Success (Score ≥ 0.72)
```
┌─────────────────────────────────┐
│  ✅ Face Verified!              │
│  Similarity: 0.87               │
│                                 │
│  Proceeding to signature...     │
└─────────────────────────────────┘
```
→ Go to Step 4 (Signature)

#### ❌ Failed Attempt 1 or 2
```
┌─────────────────────────────────┐
│  ❌ Face Not Recognized         │
│  Similarity: 0.58 (need ≥0.72)  │
│                                 │
│  Please try again               │
│  Attempt 2 of 3                 │
│                                 │
│  [Try Again]  [Cancel]          │
└─────────────────────────────────┘
```
→ Allow retry

#### ❌ Failed All 3 Attempts
```
┌─────────────────────────────────┐
│  ❌ Face verification failed    │
│                                 │
│  Falling back to security       │
│  questions for verification     │
│                                 │
│  [Continue]                     │
└─────────────────────────────────┘
```
→ Go to Step 3B (Security Questions)

---

### Step 3B: Security Questions Fallback

```
┌─────────────────────────────────┐
│  🔐 Security Verification       │
│                                 │
│  Question 1: What is your       │
│  mother's maiden name?          │
│  [________________]             │
│                                 │
│  Question 2: What city were     │
│  you born in?                   │
│  [________________]             │
│                                 │
│  [Verify]                       │
└─────────────────────────────────┘
```

**Implementation:**
- Use existing security questions from learner profile
- Verify answers against stored values (hashed)
- If correct → Go to Step 4
- If wrong → Show error and allow retry (max 3 attempts)
- If 3 failed security question attempts → Block clock-in, notify admin

---

### Step 4: Signature Capture

```
┌─────────────────────────────────┐
│  ✍️ Sign to Confirm Clock-In    │
│                                 │
│  ┌───────────────────────────┐ │
│  │                           │ │
│  │    [Signature Area]       │ │
│  │                           │ │
│  └───────────────────────────┘ │
│                                 │
│  [Clear]  [Submit]              │
└─────────────────────────────────┘
```

**Actions:**
1. Capture signature (existing signature widget)
2. Convert to base64
3. Continue to Step 5

---

### Step 5: GPS + Clock-In

```
┌─────────────────────────────────┐
│  📍 Capturing Location...       │
│                                 │
│  GPS: 25.7543°S, 28.1984°E     │
│  Accuracy: 12m                  │
│                                 │
│  ⏰ Clocking in...              │
└─────────────────────────────────┘
```

**Actions:**
1. Get GPS coordinates (existing SecureLocationService)
2. Verify geofence if applicable
3. Save evidence to local SQLite:
   ```dart
   await dbHelper.saveClockInEvidence(
     learnerId: learnerId,
     clockDate: today,
     signature: signatureBase64,
     latitude: lat,
     longitude: lng,
     accuracy: accuracy,
     verificationMethod: 'face', // or 'security_question'
     faceLogId: logId, // from verify_learner_face.php response
     timestamp: DateTime.now().toIso8601String(),
   );
   ```
4. Clock in via existing endpoint
5. Show success message

---

## Database Tables

### MySQL Server Tables

#### 1. `learner_face`
```sql
CREATE TABLE learner_face (
    id INT AUTO_INCREMENT PRIMARY KEY,
    learner_id INT NOT NULL,
    embedding_vector JSON NOT NULL, -- 192 floats
    quality_score DECIMAL(5,3),
    consent_given TINYINT(1) DEFAULT 0,
    enrolled_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    active TINYINT(1) DEFAULT 1
);
```

#### 2. `learner_face_verification_log`
```sql
CREATE TABLE learner_face_verification_log (
    id INT AUTO_INCREMENT PRIMARY KEY,
    learner_id INT NOT NULL,
    similarity_score DECIMAL(7,5) NOT NULL,
    threshold_used DECIMAL(5,3) NOT NULL,
    passed TINYINT(1) NOT NULL,
    verification_type ENUM('clock_in', 'clock_out'),
    verified_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

#### 3. `learner_clocking_evidence` (Optional - for server sync)
```sql
CREATE TABLE learner_clocking_evidence (
    id INT AUTO_INCREMENT PRIMARY KEY,
    LearnerID INT NOT NULL,
    clock_date DATE NOT NULL,
    clock_in_signature LONGTEXT,
    clock_in_latitude DECIMAL(10,6),
    clock_in_longitude DECIMAL(10,6),
    clock_in_verification_method VARCHAR(50), -- 'face' or 'security_question'
    clock_in_face_log_id INT, -- References learner_face_verification_log.id
    clock_in_timestamp DATETIME,
    -- Same for clock_out...
    UNIQUE KEY (LearnerID, clock_date)
);
```

### SQLite Local Table (Auto-created by Flutter)

```dart
// In database_helper.dart version 12 migration
await db.execute('''
  CREATE TABLE learner_clocking_evidence (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    LearnerID INTEGER NOT NULL,
    clock_date TEXT NOT NULL,
    clock_in_signature TEXT,
    clock_in_latitude REAL,
    clock_in_longitude REAL,
    clock_in_verification_method TEXT,
    clock_in_face_log_id INTEGER,
    clock_in_timestamp TEXT,
    synced INTEGER DEFAULT 0,
    UNIQUE(LearnerID, clock_date)
  )
''');
```

---

## PHP Endpoints

### 1. Check Face Enrollment
**File:** `mobile/check_face_enrollment.php`

```php
<?php
require_once '../db.php';

$learner_id = $_POST['learner_id'] ?? null;

if (!$learner_id) {
    echo json_encode(['error' => 'Missing learner_id']);
    exit;
}

$stmt = $conn->prepare("
    SELECT id, quality_score, enrolled_at 
    FROM learner_face 
    WHERE learner_id = ? AND active = 1
");
$stmt->bind_param('i', $learner_id);
$stmt->execute();
$result = $stmt->get_result();

if ($row = $result->fetch_assoc()) {
    echo json_encode([
        'enrolled' => true,
        'face_id' => $row['id'],
        'quality_score' => $row['quality_score'],
        'enrolled_at' => $row['enrolled_at']
    ]);
} else {
    echo json_encode(['enrolled' => false]);
}
?>
```

### 2. Enroll Face (Already Created)
**File:** `mobile/enrol_learner_face.php` ✅

### 3. Verify Face (Already Created)
**File:** `mobile/verify_learner_face.php` ✅

---

## Flutter Implementation

### Key Services

#### 1. FaceEmbeddingService (Already Created)
```dart
// lib/services/face_embedding_service.dart
class FaceEmbeddingService {
  Future<Map<String, dynamic>?> extractFaceEmbedding(CameraImage image);
  Future<bool> checkLivenessAcrossFrames(List<CameraImage> frames);
}
```

#### 2. FaceVerificationRepository (Already Created)
```dart
// lib/repositories/face_verification_repository.dart
class FaceVerificationRepository {
  Future<bool> checkFaceEnrolled(int learnerId);
  Future<Map<String, dynamic>> enrollFace(int learnerId, List<double> embedding);
  Future<Map<String, dynamic>> verifyFace(int learnerId, List<double> embedding);
}
```

### Integration into backup_clock_in_page.dart

```dart
// Add face verification flow
Future<bool> _verifyLearnerWithFace(int learnerId) async {
  final repo = FaceVerificationRepository();
  
  // Check if face enrolled
  final enrolled = await repo.checkFaceEnrolled(learnerId);
  
  if (!enrolled) {
    // Show enrollment dialog
    final shouldEnroll = await _showEnrollmentDialog();
    if (shouldEnroll) {
      await _enrollFace(learnerId);
    } else {
      // Skip to security questions
      return await _verifyWithSecurityQuestions(learnerId);
    }
  }
  
  // Try face verification (max 3 attempts)
  for (int attempt = 1; attempt <= 3; attempt++) {
    final result = await _captureFaceAndVerify(learnerId, attempt);
    
    if (result['verified'] == true) {
      // Success - store log_id for evidence
      _faceLogId = result['log_id'];
      return true;
    }
    
    if (attempt < 3) {
      await _showRetryDialog(attempt, result['similarity_score']);
    }
  }
  
  // All 3 attempts failed - fall back to security questions
  return await _verifyWithSecurityQuestions(learnerId);
}

Future<Map<String, dynamic>> _captureFaceAndVerify(
  int learnerId, 
  int attemptNumber
) async {
  // Open camera page
  final embedding = await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => FaceCaptureScreen(
        title: 'Face Verification (Attempt $attemptNumber/3)',
      ),
    ),
  );
  
  if (embedding == null) {
    return {'verified': false, 'similarity_score': 0.0};
  }
  
  // Verify with server
  final repo = FaceVerificationRepository();
  return await repo.verifyFace(learnerId, embedding);
}
```

---

## Configuration

### Tunable Parameters (PHP Config)
```php
// mobile/face_recognition_config.php
define('FACE_MATCH_THRESHOLD', 0.72); // Adjust based on testing
define('MIN_ENROLLMENT_QUALITY', 0.6);
define('MIN_VERIFICATION_QUALITY', 0.5);
define('MAX_FACE_ATTEMPTS', 3);
```

### Flutter Constants
```dart
// lib/services/face_embedding_service.dart
static const int maxVerificationAttempts = 3;
static const double minQualityScore = 0.5;
```

---

## Evidence Storage

All verification attempts are logged with:
- **Verification method:** `'face'` or `'security_question'`
- **Face log ID:** References `learner_face_verification_log.id` (for audit trail)
- **Signature:** Base64 image
- **GPS:** Latitude, longitude, accuracy
- **Timestamp:** ISO8601 format

This allows complete audit trail showing:
- How learner verified identity
- Face similarity scores
- Multiple attempts
- Fallback to security questions

---

## Next Steps

1. ✅ Run SQL migrations (001, 004)
2. ✅ PHP endpoints already created
3. ✅ Flutter services already created
4. ⏳ Create `mobile/check_face_enrollment.php`
5. ⏳ Create `FaceCaptureScreen` widget
6. ⏳ Integrate into `backup_clock_in_page.dart`
7. ⏳ Add security questions verification
8. ⏳ Test end-to-end workflow

---

## Security Considerations

1. **Face embeddings only** — Never store raw photos
2. **Server-side verification** — Similarity computed on server (not client)
3. **Audit logging** — Every attempt logged with score
4. **Threshold tuning** — Adjust based on false positive/negative rates
5. **Liveness detection** — Basic checks for eye movement, head pose
6. **Fallback method** — Security questions if face fails
7. **Attempt limits** — Max 3 face attempts, max 3 security question attempts

---

## Testing Checklist

- [ ] Enroll face for new learner
- [ ] Clock in with face (success)
- [ ] Clock in with face (1 failed attempt, then success)
- [ ] Clock in with face (3 failed attempts → security questions)
- [ ] Clock in with security questions directly
- [ ] Verify evidence stored correctly (signature, GPS, method, log_id)
- [ ] Verify audit log shows all attempts
- [ ] Test offline enrollment (should queue)
- [ ] Test offline verification (should fail gracefully, fall back to security questions)

