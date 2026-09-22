# Face Recognition Threshold Update & Confirmation Modal Implementation

**Date:** 2026-09-22  
**Status:** ✅ Dart Threshold Updated | ⏳ Server Name Return Needed | ⏳ Confirmation Modal Needed

## Summary

The face recognition threshold has been lowered from **0.95 to 0.80** based on real-world data showing genuine learners scoring between 0.65-0.94 on legitimate clock-ins. Both server and client thresholds now need to match for consistency.

Additionally, we need to add a **confirmation modal** for face verification showing the learner's name before allowing clock-in/out.

---

## Changes Made

### ✅ 1. Server-Side Threshold (PHP)
**File:** `mobile/face_recognition_config.php`  
**Status:** Already updated to 0.80

```php
// Line 25
define('FACE_MATCH_THRESHOLD', 0.80);
```

Comment states: "Must equal FACE_MATCH_THRESHOLD in OfflineFaceVerificationService (Dart)."

### ✅ 2. Client-Side Offline Threshold (Dart)
**File:** `lib/services/offline_face_verification_service.dart`  
**Status:** ✅ UPDATED

**Before:**
```dart
static const double FACE_MATCH_THRESHOLD = 0.95;
```

**After:**
```dart
// Cosine similarity threshold for face matching (RAW score, not remapped)
// Range: -1.0 to 1.0 (raw cosine similarity)
// Lowered from 0.95 to 0.80 on 2026-09-22 to match server-side threshold
// based on real learner_face_verification_log data showing genuine learners
// scoring between 0.65 and 0.94 on legitimate clock-ins.
// Must equal FACE_MATCH_THRESHOLD in face_recognition_config.php (PHP server).
static const double FACE_MATCH_THRESHOLD = 0.80;
```

---

## Changes Needed

### ⏳ 3. Server Returns Learner Name on Successful Verification

**File:** `mobile/verify_learner_face.php`  
**Current Behavior:** Returns only `success`, `verified`, `message`, `log_id`  
**Needed:** Also return `learner_name` and `learner_surname`

**Database Schema:**
- Table: `learnerdetails`
- Name column: `Name` (varchar 50)
- Surname column: `Surname` (varchar 50)

**Implementation:**
```php
// In verify_learner_face.php, after successful verification (around line 180)
// Fetch learner name
$stmt = $conn->prepare("SELECT Name, Surname FROM learnerdetails WHERE learnerID = ? LIMIT 1");
$stmt->bind_param("i", $learnerId);
$stmt->execute();
$result = $stmt->get_result();

if ($result->num_rows > 0) {
    $learnerData = $result->fetch_assoc();
    $response['learner_name'] = $learnerData['Name'];
    $response['learner_surname'] = $learnerData['Surname'];
    $response['full_name'] = trim($learnerData['Name'] . ' ' . $learnerData['Surname']);
}
$stmt->close();
```

**Updated Response Format:**
```json
{
  "success": true,
  "verified": true,
  "learner_id": 11443,
  "learner_name": "Siyabonga",
  "learner_surname": "Mkhize",
  "full_name": "Siyabonga Mkhize",
  "log_id": 12345,
  "message": "Face verification successful"
}
```

---

### ⏳ 4. Add Confirmation Modal in Flutter (Online Verification)

**File:** `lib/backup_clock_in_page.dart`  
**Location:** Around line 2977 where `_faceRepo.verifyFace()` is called  
**Current Flow:** Immediately proceeds after successful verification

**Needed Flow:**
1. Face verified successfully → server returns learner name
2. Show modal: "**[Name] [Surname]** is about to clock in. Is this correct?"
3. Buttons: **Yes** (proceed) | **No** (cancel)
4. Only proceed to clock-in if user confirms "Yes"

**Implementation:**

```dart
// In backup_clock_in_page.dart, around line 2977-3000
result = await _faceRepo.verifyFace(
  learnerId: int.parse(learnerId),
  embedding: embedding,
  qualityScore: qualityScore,
  livenessPassed: livenessPassed,
  verificationType: 'clock_in',
  deviceInfo: await FaceVerificationRepository.getDeviceInfo(),
);

if (result['success'] == true && result['verified'] == true) {
  // NEW: Show confirmation dialog with learner name
  final fullName = result['full_name'] ?? 'Unknown Learner';
  
  if (!mounted) return;
  
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('Confirm Identity'),
      content: Text(
        '$fullName is about to clock in.\n\nIs this correct?',
        style: const TextStyle(fontSize: 16),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('NO', style: TextStyle(color: Colors.red, fontSize: 18)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          child: const Text('YES', style: TextStyle(fontSize: 18)),
        ),
      ],
    ),
  );
  
  if (confirmed != true) {
    print('[FACE] User rejected identity confirmation');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Clock-in cancelled - identity not confirmed'),
          backgroundColor: Colors.orange,
        ),
      );
    }
    return;
  }
  
  // Continue with clock-in ONLY if confirmed
  print('[FACE] ✅ Identity confirmed by user - proceeding with clock-in');
  // ... existing clock-in code ...
}
```

---

## Why These Changes Are Needed

### 1. Threshold Consistency
**Problem:** Online clock-ins use 0.80 (server), but offline clock-ins use 0.95 (Dart). A learner with score 0.85 would be:
- ✅ Accepted when online (server: 0.85 > 0.80)
- ❌ Rejected when offline (Dart: 0.85 < 0.95)

**Solution:** Both must use 0.80 for consistent behavior regardless of connectivity.

### 2. Confirmation Modal (Security Layer)
**Problem:** Face recognition can have false positives (Person A verified as Person B). Without confirmation, wrong-person clock-ins go undetected.

**Solution:** Human-in-the-loop verification:
- Learner sees their own name before confirming
- If system shows wrong name, learner clicks "NO" → prevents fraud
- Adds security layer beyond just facial matching

---

## Testing Plan

### Test 1: Offline Threshold Matches (0.80)
1. Enroll learner with good quality face
2. Turn off internet (airplane mode)
3. Attempt offline verification
4. **Expected:** Face match succeeds at 0.80 threshold (not 0.95)

### Test 2: Online Returns Learner Name
1. Turn on internet
2. Verify face online via `verify_learner_face.php`
3. Check response JSON
4. **Expected:** Contains `learner_name`, `learner_surname`, `full_name`

### Test 3: Confirmation Modal Shown
1. Complete face verification (online)
2. **Expected:** Modal appears showing "**[Name] [Surname]** is about to clock in"
3. Click "NO" → clock-in cancelled
4. Click "YES" → clock-in proceeds

### Test 4: Wrong Person Detection
1. Person A verifies as Person B (if threshold too low / false positive)
2. Modal shows "**Person B Name** is about to clock in"
3. Person A sees wrong name, clicks "NO"
4. **Expected:** Clock-in cancelled, fraud prevented

---

## Deployment Checklist

- [x] Update `offline_face_verification_service.dart` threshold to 0.80
- [ ] Update `verify_learner_face.php` to return learner name fields
- [ ] Add confirmation modal in `backup_clock_in_page.dart`
- [ ] Test offline verification with 0.80 threshold
- [ ] Test online verification returns name
- [ ] Test confirmation modal "YES" path
- [ ] Test confirmation modal "NO" path (cancels clock-in)
- [ ] Rebuild APK with all changes
- [ ] Deploy to devices

---

## Files to Modify

1. ✅ **`lib/services/offline_face_verification_service.dart`** - Threshold updated to 0.80
2. ⏳ **`mobile/verify_learner_face.php`** - Add learner name to response
3. ⏳ **`lib/backup_clock_in_page.dart`** - Add confirmation modal after verification

---

## Impact Analysis

**Positive:**
- ✅ Consistent face matching regardless of online/offline
- ✅ Reduces false rejections (genuine learners at 0.85-0.94 now accepted)
- ✅ Human verification prevents wrong-person clock-ins
- ✅ Learners can self-detect system errors

**Risks:**
- ⚠️ Lower threshold (0.80) may increase false positive risk
- ⚠️ Need to monitor wrong-person verification attempts
- ⚠️ Confirmation modal adds one extra tap (UX tradeoff for security)

**Mitigation:**
- Monitor `learner_face_verification_log` for suspicious patterns
- Collect impostor scores (wrong person attempts) to validate 0.80 is safe
- Consider raising threshold back to 0.85 if false positives increase

---

## Next Steps

1. **Modify verify_learner_face.php** to return name fields
2. **Add confirmation modal** in backup_clock_in_page.dart
3. **Test thoroughly** with multiple learners
4. **Rebuild and deploy** new APK
5. **Monitor verification logs** for 2 weeks to validate threshold

---

**Status:** Ready to implement PHP and Dart changes.
