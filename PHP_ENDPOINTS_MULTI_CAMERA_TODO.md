# PHP Endpoints - Multi-Camera Face Verification TODO

## ✅ COMPLETED

### 1. `mobile/sync_face_verification_logs.php` 
- ✅ Updated to accept `camera_facing` parameter
- ✅ Stores `camera_facing` in `learner_face_verification_log` table
- ✅ Backward compatible (defaults to 'back' if not provided)

## ❌ STILL NEEDED

### 2. Face Enrollment Endpoint (CRITICAL)
**Status:** Endpoint doesn't exist yet or needs to be found

**Required functionality:**
- Accept `camera_facing` parameter ('front' or 'back')
- Store embedding with composite key: `(learner_id, camera_facing)`
- Allow TWO embeddings per learner (one front, one back)
- Don't overwrite when different camera is enrolled

**Example Implementation:**
```php
<?php
// File: mobile/enroll_face.php

require_once '../connection.php';

$input = json_decode(file_get_contents('php://input'), true);

$learnerId = (int)$input['learner_id'];
$cameraFacing = $input['camera_facing'] ?? 'back'; // 'front' or 'back'
$embeddingVector = json_encode($input['embedding']);
$qualityScore = (float)$input['quality_score'];
$modelVersion = $input['model_version'] ?? 'MobileFaceNet_v1';

// Insert or update embedding for this specific camera
$stmt = $conn->prepare("
    INSERT INTO learner_face (
        learner_id, 
        camera_facing, 
        embedding_vector, 
        quality_score,
        model_version,
        active
    ) VALUES (?, ?, ?, ?, ?, 1)
    ON DUPLICATE KEY UPDATE 
        embedding_vector = VALUES(embedding_vector),
        quality_score = VALUES(quality_score),
        updated_at = NOW()
");

$stmt->bind_param('issds', $learnerId, $cameraFacing, $embeddingVector, $qualityScore, $modelVersion);

if ($stmt->execute()) {
    echo json_encode([
        'success' => true,
        'message' => ucfirst($cameraFacing) . ' camera enrolled successfully',
        'camera_facing' => $cameraFacing
    ]);
} else {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Failed to enroll: ' . $stmt->error
    ]);
}
?>
```

### 3. Face Verification Endpoint (CRITICAL)
**Status:** Endpoint doesn't exist yet or needs to be found

**Required functionality:**
- Query ALL embeddings for learner (both front and back)
- Compare live capture against each stored embedding
- Take the BEST (highest) score across all embeddings
- Return which camera matched
- Use 0.95 threshold on RAW cosine similarity

**Example Implementation:**
```php
<?php
// File: mobile/verify_face.php

require_once '../connection.php';
require_once '../face_verification_functions.php'; // computeCosineSimilarity(), isFaceMatch()

$input = json_decode(file_get_contents('php://input'), true);

$learnerId = (int)$input['learner_id'];
$liveEmbedding = $input['embedding']; // Array of floats
$cameraFacing = $input['camera_facing'] ?? 'back'; // Camera used for capture

// Get ALL active embeddings for this learner
$stmt = $conn->prepare("
    SELECT embedding_vector, camera_facing, quality_score 
    FROM learner_face 
    WHERE learner_id = ? AND active = 1
");

$stmt->bind_param('i', $learnerId);
$stmt->execute();
$result = $stmt->get_result();

if ($result->num_rows === 0) {
    echo json_encode([
        'success' => false,
        'verified' => false,
        'message' => 'No enrolled face found for learner',
        'match_score' => 0.0
    ]);
    exit;
}

// Compare against ALL stored embeddings and take the BEST score
$maxScore = -1.0;
$matchedCamera = null;

while ($row = $result->fetch_assoc()) {
    $storedEmbedding = json_decode($row['embedding_vector'], true);
    $storedCamera = $row['camera_facing'];
    
    $score = computeCosineSimilarity($liveEmbedding, $storedEmbedding);
    
    if ($score > $maxScore) {
        $maxScore = $score;
        $matchedCamera = $storedCamera;
    }
}

// Check if best score meets 0.95 threshold
$verified = isFaceMatch($maxScore); // Uses 0.95 threshold

// Log verification attempt
$logStmt = $conn->prepare("
    INSERT INTO learner_face_verification_log (
        learner_id,
        match_score,
        verified,
        verification_type,
        camera_facing,
        attempted_at
    ) VALUES (?, ?, ?, 'clock_in', ?, NOW())
");

$verifiedInt = $verified ? 1 : 0;
$logStmt->bind_param('idis', $learnerId, $maxScore, $verifiedInt, $cameraFacing);
$logStmt->execute();

echo json_encode([
    'success' => true,
    'verified' => $verified,
    'match_score' => round($maxScore, 5),
    'matched_camera' => $matchedCamera,
    'used_camera' => $cameraFacing,
    'threshold' => 0.95,
    'message' => $verified 
        ? "Face verified (matched: $matchedCamera)" 
        : "Face does not match (score: $maxScore < 0.95)"
]);
?>
```

## 📋 Summary

| Endpoint | Status | Action Required |
|----------|--------|-----------------|
| `sync_face_verification_logs.php` | ✅ **COMPLETE** | None - already updated |
| Face enrollment endpoint | ❌ **MISSING** | Create or update to support `camera_facing` |
| Face verification endpoint | ❌ **MISSING** | Create or update to match against ALL embeddings |

## 🔍 Next Steps

1. **Find existing enrollment/verification endpoints**
   - Search for where face enrollment happens
   - Check if there's an existing `enroll_face.php` or similar
   - Check if verification is done server-side or only offline

2. **Update or create enrollment endpoint**
   - Accept `camera_facing` parameter
   - Store with composite key
   - Test with front and back camera

3. **Update or create verification endpoint**
   - Query ALL embeddings
   - Compare against each
   - Return best score and matched camera

4. **Test multi-camera flow**
   - Enroll back camera
   - Enroll front camera  
   - Verify with back camera (should match back embedding)
   - Verify with front camera (should match front embedding)
   - Cross-camera verification (should still work but with slightly lower scores)

## 💡 Important Notes

- **Backward compatibility:** All changes default to 'back' camera if not specified
- **Threshold:** Same 0.95 threshold applies to both front and back cameras
- **Best score wins:** Verification takes the HIGHEST score across all stored embeddings
- **Logging:** Track which camera was used for each verification attempt
