# Face Recognition UI Implementation Plan

**Target File:** `lib/backup_clock_in_page.dart`  
**Status:** Ready to implement  
**Estimated Time:** 3-4 hours

---

## Overview

We need to add face recognition to the existing backup clock-in flow. The workflow is:

```
1. User clicks "Clock In" button
2. Check if learner has face enrolled
   ├─ NO → Offer face enrollment
   └─ YES → Proceed to face verification
3. Face verification (3 attempts max)
   ├─ SUCCESS → Capture snapshot photo → Signature → GPS → Clock in
   └─ FAIL (3x) → Security questions fallback → Signature → GPS → Clock in
```

---

## Files to Create

### 1. **Simple Face Capture Widget**
**File:** `lib/widgets/simple_face_capture.dart`

**Purpose:** Lightweight camera screen with basic face detection for both enrollment and verification.

**Features:**
- Camera preview (front camera)
- Basic ML Kit face detection overlay
- Manual capture button
- Quality indicator (simple: Good/Bad/None)
- Works for both enrollment (take photo) and verification (take photo + verify)

**Why Simple:** 
- Easier to implement and debug
- Less prone to camera conflicts
- Can be enhanced later

---

### 2. **Security Questions Dialog**
**File:** Already exists in current codebase (can use existing patterns)

**Purpose:** Fallback when face verification fails 3 times

**Features:**
- Show 2-3 security questions from learner profile
- Validate answers
- Allow clock-in if correct

---

## Changes to `backup_clock_in_page.dart`

### **Step 1: Add Imports**

Add at the top of the file:

```dart
import 'services/face_embedding_service.dart';
import 'repositories/face_verification_repository.dart';
import 'widgets/simple_face_capture.dart';
import 'package:camera/camera.dart';
```

---

### **Step 2: Add State Variables**

Add to `_BackupClockInPageState` class:

```dart
// Face recognition state
bool _isFaceEnrolled = false;
int _faceVerificationAttempts = 0;
String? _capturedFacePhoto; // Base64 of verification photo
File? _verificationPhotoFile;

// Services
final FaceEmbeddingService _faceService = FaceEmbeddingService();
final FaceVerificationRepository _faceRepo = FaceVerificationRepository();
```

---

### **Step 3: Modify Clock-In Flow**

**Current flow:**
```dart
_startBackupClockIn(learnerId)
  → _showIdVerificationDialog()
  → _showSignatureDialog()
  → _processBackupClockIn()
```

**New flow:**
```dart
_startBackupClockIn(learnerId)
  → _checkFaceEnrollment(learnerId)  // NEW
     ├─ If NOT enrolled → _offerFaceEnrollment()
     └─ If enrolled → _verifyWithFace()
  → _showIdVerificationDialog()  // Keep as backup if face fails
  → _showSignatureDialog()
  → _processBackupClockIn(withPhoto: _capturedFacePhoto)  // Pass photo
```

---

### **Step 4: Add New Methods**

#### **A. Check Face Enrollment**

```dart
Future<void> _checkFaceEnrollment(String learnerId) async {
  try {
    final result = await _faceRepo.checkEnrollment(int.parse(learnerId));
    
    setState(() {
      _isFaceEnrolled = result['enrolled'] == true;
    });

    if (!_isFaceEnrolled) {
      // Offer to enroll face
      final enroll = await _showEnrollmentDialog();
      if (enroll == true) {
        await _enrollFace(learnerId);
      }
    }
  } catch (e) {
    print('[FACE] Error checking enrollment: $e');
    _isFaceEnrolled = false;
  }
}
```

#### **B. Show Enrollment Dialog**

```dart
Future<bool?> _showEnrollmentDialog() async {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Face Recognition'),
      content: const Text(
        'You haven\'t registered your face yet. '
        'Would you like to register now for faster clock-in?'
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Skip'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Register Face'),
        ),
      ],
    ),
  );
}
```

#### **C. Enroll Face**

```dart
Future<void> _enrollFace(String learnerId) async {
  try {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    // Open camera to capture face
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SimpleFaceCapture(
          title: 'Register Your Face',
          instruction: 'Position your face in the frame',
          isEnrollment: true,
        ),
      ),
    );

    Navigator.pop(context); // Close loading

    if (result != null && result['imageFile'] != null) {
      // Extract embedding
      final embedding = await _faceService.extractEmbedding(result['imageFile']);
      
      if (embedding != null) {
        // Send to server
        final success = await _faceRepo.enrollFace(
          learnerId: int.parse(learnerId),
          embedding: embedding,
          qualityScore: result['quality'] ?? 0.8,
        );

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Face registered successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          setState(() {
            _isFaceEnrolled = true;
          });
        }
      }
    }
  } catch (e) {
    print('[FACE] Enrollment error: $e');
    Navigator.pop(context); // Close loading if still open
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Face registration failed: $e'),
        backgroundColor: Colors.red,
      ),
    );
  }
}
```

#### **D. Verify With Face**

```dart
Future<bool> _verifyWithFace(String learnerId) async {
  _faceVerificationAttempts = 0;
  
  while (_faceVerificationAttempts < 3) {
    _faceVerificationAttempts++;
    
    try {
      // Open camera for verification
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SimpleFaceCapture(
            title: 'Verify Your Face',
            instruction: 'Look at the camera (Attempt $_faceVerificationAttempts/3)',
            isEnrollment: false,
          ),
        ),
      );

      if (result == null) {
        // User cancelled
        return false;
      }

      // Show verifying dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Extract embedding from captured image
      final embedding = await _faceService.extractEmbedding(result['imageFile']);
      
      if (embedding != null) {
        // Verify with server
        final verifyResult = await _faceRepo.verifyFace(
          learnerId: int.parse(learnerId),
          embedding: embedding,
        );

        Navigator.pop(context); // Close verifying dialog

        if (verifyResult['success'] == true && verifyResult['match'] == true) {
          // SUCCESS! Capture the photo as evidence
          final imageBytes = await result['imageFile'].readAsBytes();
          setState(() {
            _capturedFacePhoto = base64Encode(imageBytes);
            _verificationPhotoFile = result['imageFile'];
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Face verified successfully!'),
              backgroundColor: Colors.green,
            ),
          );

          return true; // Verification successful
        } else {
          // Failed verification
          final attemptsLeft = 3 - _faceVerificationAttempts;
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                attemptsLeft > 0
                    ? 'Face not recognized. $attemptsLeft attempts left.'
                    : 'Face verification failed. Using security questions.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }

      Navigator.pop(context); // Close verifying dialog if still open
      
    } catch (e) {
      print('[FACE] Verification error: $e');
      Navigator.pop(context); // Close verifying dialog if still open
    }
  }

  // All 3 attempts failed - fall back to security questions
  return _verifyWithSecurityQuestions(learnerId);
}
```

#### **E. Security Questions Fallback**

```dart
Future<bool> _verifyWithSecurityQuestions(String learnerId) async {
  // Show dialog explaining fallback
  await showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Alternative Verification'),
      content: const Text(
        'Face verification was unsuccessful. '
        'Please answer security questions to continue.'
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );

  // TODO: Implement security questions dialog
  // For now, show ID verification (existing flow)
  return await _showIdVerificationDialog(learnerId);
}
```

#### **F. Modify Existing Clock-In Method**

Update `_processBackupClockIn` to include photo:

```dart
Future<void> _processBackupClockIn(String learnerId, {String? facePhoto}) async {
  // ... existing code ...

  // Save clocking with photo evidence
  await DatabaseHelper().saveClockInEvidence(
    learnerId: int.parse(learnerId),
    clockDate: clockDateStr,
    signature: signatureBase64, // existing
    photo: facePhoto, // NEW - face verification photo
    latitude: _currentLat,
    longitude: _currentLng,
    accuracy: _currentAccuracy,
    verificationMethod: facePhoto != null ? 'face' : 'signature',
    faceLogId: facePhoto != null ? _lastFaceLogId : null,
  );

  // ... rest of existing code ...
}
```

---

## Implementation Order

1. ✅ **Create `SimpleFaceCapture` widget first** (separate file)
2. ✅ **Add imports and state variables** to backup_clock_in_page.dart
3. ✅ **Add face enrollment check** at start of clock-in flow
4. ✅ **Add face verification** with 3-attempt logic
5. ✅ **Add security questions fallback** (can use existing ID verification for now)
6. ✅ **Update clock-in method** to save photo evidence
7. ✅ **Test end-to-end** workflow

---

## Testing Checklist

### **Enrollment Flow:**
- [ ] User without face enrolled sees enrollment dialog
- [ ] Camera opens correctly
- [ ] Face is detected and captured
- [ ] Embedding is extracted successfully
- [ ] Face is registered on server
- [ ] Success message is shown

### **Verification Flow:**
- [ ] User with face enrolled goes straight to verification
- [ ] Camera opens for verification
- [ ] Correct face matches successfully
- [ ] Wrong face fails and shows retry
- [ ] After 3 failures, security questions appear
- [ ] Photo is captured and saved with clock-in evidence

### **Fallback Flow:**
- [ ] Security questions work when face fails
- [ ] Can still clock in without face recognition
- [ ] Photo evidence is optional (only if face verified)

---

## Next Steps

**Ready to proceed?** 

I will:
1. Create the `SimpleFaceCapture` widget
2. Show you the exact code changes for `backup_clock_in_page.dart`
3. You review and approve
4. Build and test

**Or would you prefer** me to implement it all directly now?
