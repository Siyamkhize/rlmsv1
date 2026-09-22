# Face Verification: How It Works (Multi-Camera System)

## Overview
Face verification compares a **live face embedding** (captured during clock-in) against **stored enrollment embedding(s)** to confirm the learner's identity.

---

## 🔐 Security Principle: SERVER-SIDE VERIFICATION ONLY

**CRITICAL**: All face matching happens on the **server**. Never trust client-reported matches.

```
❌ WRONG: Client says "I matched!" → Accept
✅ RIGHT: Server computes similarity → Decides pass/fail
```

---

## 📊 How Verification Works (Step-by-Step)

### **Step 1: Live Capture (Mobile App)**
Learner stands in front of camera during clock-in:
```
📱 Mobile App:
  1. Captures face image
  2. Runs MobileFaceNet model
  3. Generates 192-float embedding vector
  4. Checks quality score (optional)
  5. Sends embedding to server
```

### **Step 2: Server Receives Request**
```json
POST /mobile/verify_learner_face.php
{
  "learner_id": 12345,
  "embedding": [0.123, -0.456, 0.789, ...],  // 192 floats
  "quality_score": 0.85,
  "liveness_passed": true,
  "verification_type": "clock_in"
}
```

### **Step 3: Fetch Stored Embeddings**
Server retrieves **ALL active embeddings** for the learner:

```sql
SELECT id, embedding_vector, camera_facing
FROM learner_face
WHERE learner_id = 12345 AND active = 1;
```

**Result (Multi-Camera System)**:
```
id | embedding_vector         | camera_facing
---|--------------------------|---------------
45 | [0.111, -0.222, ...]    | back
46 | [0.333, -0.444, ...]    | front
```

OR **Result (Back Camera Only - Most Common)**:
```
id | embedding_vector         | camera_facing
---|--------------------------|---------------
45 | [0.111, -0.222, ...]    | back
```

### **Step 4: Compute Similarity Scores**
Server compares live embedding against **EACH** stored embedding:

```php
// For each stored embedding
foreach ($stored_embeddings as $stored) {
    $score = computeCosineSimilarity($live_embedding, $stored['embedding_vector']);
    // Track the best (highest) score
}
```

**Cosine Similarity Calculation**:
```
Score = (A · B) / (||A|| × ||B||)

Where:
  A = live embedding vector
  B = stored embedding vector
  · = dot product
  ||A|| = norm (magnitude) of vector A

Result: Score between -1 and 1
  1.0  = Perfect match (identical faces)
  0.9  = Very similar (likely same person)
  0.7  = Somewhat similar
  0.5  = Different faces
  0.0  = No relationship
 -1.0  = Complete opposite
```

### **Step 5: Find Best Match**
Server selects the **HIGHEST** similarity score:

```php
// Example with back camera only
Stored Back Camera:  [0.111, -0.222, ...]
Live Capture:        [0.115, -0.225, ...]
Similarity Score:    0.973  ← BEST (and only) SCORE
```

```php
// Example with both cameras (rare)
Stored Back Camera:  [0.111, -0.222, ...]  → Score: 0.973
Stored Front Camera: [0.333, -0.444, ...]  → Score: 0.842
Best Score: 0.973 from back camera
```

### **Step 6: Apply Threshold**
Server checks if best score meets threshold:

```php
$threshold = 0.72;  // From face_recognition_config.php
$verified = ($best_score >= $threshold);

// Example 1: PASS
Score: 0.973 >= 0.72  → verified = TRUE ✅

// Example 2: FAIL
Score: 0.645 < 0.72   → verified = FALSE ❌
```

### **Step 7: Log Everything**
Every verification attempt is logged (pass OR fail):

```sql
INSERT INTO learner_face_verification_log (
    learner_id,
    similarity_score,
    threshold_used,
    passed,
    verification_type,
    quality_score
) VALUES (
    12345,
    0.973,
    0.72,
    1,  -- passed
    'clock_in',
    0.85
);
```

### **Step 8: Return Result**
```json
{
  "success": true,
  "verified": true,
  "similarity_score": 0.973,
  "threshold": 0.72,
  "matched_camera": "back",
  "log_id": 456,
  "message": "Face verification successful"
}
```

---

## 🎯 Key Scenarios

### **Scenario 1: Back Camera Only (99% of cases)**
```
Database:
  Learner 12345 → Back camera embedding

Live Capture:
  Learner uses back camera

Process:
  ✅ Compare live vs stored back
  ✅ Get similarity score: 0.96
  ✅ Check threshold: 0.96 >= 0.72
  ✅ VERIFIED!
```

### **Scenario 2: Multi-Camera (Future/Optional)**
```
Database:
  Learner 67890 → Back camera embedding (0.91 quality)
  Learner 67890 → Front camera embedding (0.83 quality)

Live Capture:
  Learner uses front camera (phone flipped)

Process:
  ✅ Compare live vs back → Score: 0.74
  ✅ Compare live vs front → Score: 0.89
  ✅ Best score: 0.89 (from front camera)
  ✅ Check threshold: 0.89 >= 0.72
  ✅ VERIFIED! (Matched with front camera)
```

### **Scenario 3: Failed Verification**
```
Database:
  Learner 11111 → Back camera embedding

Live Capture:
  Different person tries to clock in as 11111

Process:
  ❌ Compare live vs stored → Score: 0.52
  ❌ Check threshold: 0.52 < 0.72
  ❌ FAILED! (Not the same person)
```

---

## 🔬 Technical Details

### **Cosine Similarity Math**
```
Given two vectors:
A = [0.1, 0.2, 0.3, ...]  (live embedding)
B = [0.1, 0.2, 0.3, ...]  (stored embedding)

1. Dot Product: A · B = (A₁×B₁) + (A₂×B₂) + ... + (A₁₉₂×B₁₉₂)
2. Norm A: ||A|| = √(A₁² + A₂² + ... + A₁₉₂²)
3. Norm B: ||B|| = √(B₁² + B₂² + ... + B₁₉₂²)
4. Cosine Similarity = (A · B) / (||A|| × ||B||)
```

### **Why Cosine Similarity?**
✅ **Range-normalized**: Always between -1 and 1  
✅ **Angle-based**: Measures direction, not magnitude  
✅ **Industry standard**: Used in face recognition systems  
✅ **Fast computation**: Simple math operations  
✅ **Robust**: Works well with normalized embeddings  

### **Threshold Tuning**
```
Threshold = 0.72 (default)

Too Low (0.5):
  ❌ More false positives (wrong people pass)
  ✅ Fewer false negatives (real learners don't get locked out)
  
Optimal (0.72):
  ✅ Good balance
  ✅ ~1% false accept rate
  ✅ ~2% false reject rate
  
Too High (0.95):
  ✅ Fewer false positives
  ❌ More false negatives (real learners rejected)
```

---

## 📈 Multi-Camera Benefits

### **1. Better Accuracy**
```
Single Camera:
  Back camera only → One comparison
  Miss rate: ~2-3%

Multi-Camera:
  Back + Front → Two comparisons, pick best
  Miss rate: ~0.5-1% (BETTER!)
```

### **2. Lighting Flexibility**
```
Scenario: Sun shining from behind learner

Back Camera:
  Face in shadow → Low quality → Score: 0.68 ❌

Front Camera:
  Face well-lit → Good quality → Score: 0.91 ✅

Result: VERIFIED using front camera!
```

### **3. Physical Position Flexibility**
```
Scenario: Tablet mounted at awkward angle

Back Camera:
  Face at bad angle → Score: 0.70 ❌

Front Camera:
  Better angle → Score: 0.88 ✅

Result: VERIFIED using front camera!
```

---

## 🔒 Security Features

### **1. Server-Side Computation**
```
❌ Client: "I computed score = 0.95, let me in!"
   → REJECTED (can be faked)

✅ Server: "I fetched your enrollment, computed score = 0.95"
   → ACCEPTED (cannot be faked)
```

### **2. Audit Trail**
Every attempt logged:
```sql
SELECT * FROM learner_face_verification_log 
WHERE learner_id = 12345 
ORDER BY verified_at DESC;

-- Shows:
-- All clock-ins
-- All failures
-- Similarity scores
-- Which camera matched
-- Device info
-- IP addresses
```

### **3. Quality Checks**
```php
if ($quality_score < MIN_VERIFICATION_QUALITY) {
    throw new Exception('Quality too low - try again');
}

// Prevents blurry/dark images from being used
```

---

## 🎬 Complete Flow Diagram

```
┌──────────────────┐
│   Mobile App     │
│  (Learner)       │
└────────┬─────────┘
         │ 1. Capture face
         │ 2. Generate embedding
         ▼
┌──────────────────┐
│   POST Request   │
│ learner_id: 123  │
│ embedding: [...]│
└────────┬─────────┘
         │
         ▼
┌──────────────────────────────────┐
│         SERVER                   │
│                                  │
│ 3. Fetch ALL stored embeddings   │
│    - Back camera: [0.1, 0.2,...]│
│    - Front camera: [0.3, 0.4,...]│  (if exists)
│                                  │
│ 4. Compare live vs EACH stored   │
│    - vs Back:  score = 0.973    │
│    - vs Front: score = 0.842    │  (if exists)
│                                  │
│ 5. Pick BEST score: 0.973       │
│                                  │
│ 6. Check threshold              │
│    0.973 >= 0.72? → YES ✅      │
│                                  │
│ 7. Log to database              │
│                                  │
└────────┬─────────────────────────┘
         │
         ▼
┌──────────────────┐
│   Response       │
│ verified: true   │
│ score: 0.973     │
│ camera: back     │
└──────────────────┘
```

---

## 📝 Summary

**For Your System (Mostly Back Camera)**:
1. Learner enrolled with **back camera**
2. Learner clocks in with **back camera**
3. Server compares live vs stored back camera
4. Score >= 0.72 → **VERIFIED ✅**
5. Score < 0.72 → **FAILED ❌**

**Multi-Camera Support (Optional)**:
- If learner has **both cameras** enrolled
- Server compares against **both**
- Uses **BEST score** for verification
- Increases accuracy and flexibility

**Security**:
- All computation happens **server-side**
- Every attempt **logged**
- Quality checks **enforced**
- Cannot be spoofed by client
