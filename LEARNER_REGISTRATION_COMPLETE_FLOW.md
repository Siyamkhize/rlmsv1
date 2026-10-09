# Learner Registration Complete Flow

**Date**: 2026-09-25  
**Status**: ✅ Complete Implementation

## Overview

New learners must complete **TWO setup steps** before they can use the backup clock-in system:

1. **Face Registration** - Capture and enroll face embedding
2. **Security Questions Setup** - Select 3-5 questions and provide answers

Both are required for the complete backup authentication system.

---

## Complete Registration Flow

### Step 1: Face Registration

**When**: First time learner attempts to clock in/out via backup page

**Process**:
1. System checks if face is enrolled: `_checkFaceEnrollment(learnerId)`
2. If not enrolled, shows dialog explaining face registration
3. User clicks "Register Face"
4. `SimpleFaceCapture` widget captures photo with guidance overlay
5. `FaceEmbeddingService` extracts 128-dimension embedding
6. Embedding saved to:
   - **Server**: `learner_face_enrollments` table (MySQL)
   - **Local**: SQLite offline cache for offline verification
7. Success message: "✅ Face registered successfully!"

**Code Location**: `lib/backup_clock_in_page.dart` → `_enrollFace()` (line ~2956)

---

### Step 2: Security Questions Setup (NEW)

**When**: Immediately after successful face registration

**Process**:
1. System checks if security questions are already set up
2. If not set up, shows dialog explaining security questions
3. User clicks "Set Up Now"
4. Navigates to `LearnerSecurityQuestionsSetupPage`
5. Loads 15 predefined questions from server
6. User selects 3-5 questions
7. User provides answers for each selected question
8. Answers are SHA256 hashed and saved to:
   - **Server**: `learner_security_answers` table (MySQL)
9. Success message: "✅ Security questions saved successfully!"

**Code Location**: 
- `lib/backup_clock_in_page.dart` → `_promptSecurityQuestionsSetup()` (line ~3119)
- `lib/learner_security_questions_setup_page.dart` (new file)

---

## User Journey Diagram

```
┌─────────────────────────────────────┐
│ Learner attempts to clock in       │
│ (first time)                        │
└─────────────────┬───────────────────┘
                  │
                  ▼
┌─────────────────────────────────────┐
│ Check: Is face enrolled?            │
└─────────────────┬───────────────────┘
                  │
         ┌────────┴────────┐
         │ NO              │ YES (skip to verification)
         ▼                 │
┌─────────────────────┐    │
│ Show face           │    │
│ registration dialog │    │
└─────────┬───────────┘    │
          │                │
   ┌──────┴──────┐        │
   │ Skip │ Register      │
   │      │               │
   │      ▼               │
   │ ┌──────────────┐    │
   │ │ Capture face │    │
   │ │ photo with   │    │
   │ │ guidance     │    │
   │ └──────┬───────┘    │
   │        │             │
   │        ▼             │
   │ ┌──────────────┐    │
   │ │ Extract      │    │
   │ │ embedding    │    │
   │ └──────┬───────┘    │
   │        │             │
   │        ▼             │
   │ ┌──────────────┐    │
   │ │ Save to      │    │
   │ │ server +     │    │
   │ │ local cache  │    │
   │ └──────┬───────┘    │
   │        │             │
   │        ▼             │
   │ ┌──────────────────────────┐
   │ │ Success!                 │
   │ │ "Face registered"        │
   │ └──────┬───────────────────┘
   │        │
   │        ▼
   │ ┌──────────────────────────────┐
   │ │ Check: Security questions    │
   │ │ set up?                      │
   │ └──────┬───────────────────────┘
   │        │
   │   ┌────┴────┐
   │   │ YES     │ NO
   │   │         │
   │   │         ▼
   │   │    ┌────────────────────┐
   │   │    │ Show security      │
   │   │    │ questions prompt   │
   │   │    └────────┬───────────┘
   │   │             │
   │   │      ┌──────┴──────┐
   │   │      │ Skip │ Set Up
   │   │      │      │
   │   │      │      ▼
   │   │      │  ┌───────────────┐
   │   │      │  │ Navigate to   │
   │   │      │  │ setup page    │
   │   │      │  └───────┬───────┘
   │   │      │          │
   │   │      │          ▼
   │   │      │  ┌───────────────┐
   │   │      │  │ Select 3-5    │
   │   │      │  │ questions     │
   │   │      │  └───────┬───────┘
   │   │      │          │
   │   │      │          ▼
   │   │      │  ┌───────────────┐
   │   │      │  │ Provide       │
   │   │      │  │ answers       │
   │   │      │  └───────┬───────┘
   │   │      │          │
   │   │      │          ▼
   │   │      │  ┌───────────────┐
   │   │      │  │ SHA256 hash   │
   │   │      │  │ & save        │
   │   │      │  └───────┬───────┘
   │   │      │          │
   │   │      │          ▼
   │   │      │  ┌───────────────┐
   │   │      │  │ Success!      │
   │   │      │  │ "Questions    │
   │   │      │  │  saved"       │
   │   │      │  └───────────────┘
   │   │      │
   │   └──────┴──────────────┐
   │                         │
   └─────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────┐
│ Registration complete!              │
│ Ready for clock-in verification     │
└─────────────────────────────────────┘
```

---

## Verification Flow (After Registration)

Once both face and security questions are registered:

### Clock-In/Out Attempt

1. **Face Verification** (up to 3 attempts)
   - Capture face photo
   - Extract embedding
   - Compare with enrolled embedding (cosine similarity)
   - Threshold: ≥ 0.60 = match

2. **If face fails 3 times** → Fallback to Security Questions
   - Fetch random question from learner's registered questions
   - Show question in dialog
   - Learner enters answer
   - Server compares SHA256 hash
   - ✅ Correct → Clock-in/out proceeds
   - ❌ Wrong → Show error, return `false`, learner must retry

3. **If wrong security answer**:
   - Learner blocked from clocking in/out
   - Must try again from beginning
   - Gets NEW random question on next attempt

---

## Database Tables

### Face Registration Tables

**MySQL** (`learner_face_enrollments`):
```sql
- id (PK)
- learner_id (FK to learnerdetails)
- face_embedding (TEXT) - JSON array of 128 floats
- quality_score (DECIMAL)
- enrollment_date (DATETIME)
- is_active (TINYINT)
```

**SQLite** (offline cache):
```sql
- Similar structure for offline verification
```

### Security Questions Tables (NEW)

**MySQL**:

1. `security_questions` - 15 predefined questions
```sql
- question_id (PK)
- question_text (VARCHAR)
- category (VARCHAR)
- is_active (TINYINT)
```

2. `learner_security_answers` - Learner answers (SHA256 hashed)
```sql
- answer_id (PK)
- learner_id (FK)
- question_id (FK)
- answer_hash (VARCHAR 64) - SHA256
- created_at (DATETIME)
- updated_at (DATETIME)
```

3. `security_question_verification_log` - Audit trail
```sql
- log_id (PK)
- learner_id (FK)
- question_id (FK)
- verification_successful (TINYINT)
- timestamp (DATETIME)
- ip_address (VARCHAR)
```

---

## API Endpoints

### Face Enrollment
- `POST /mobile/enrol_learner_face.php`
  - Action: Save face embedding to server
  - Params: learner_id, embedding, quality_score, consent_given

### Security Questions
- `POST /mobile/manage_security_questions.php`
  - Actions:
    - `get_questions` - Fetch 15 predefined questions
    - `save_answers` - Save learner's selected questions and hashed answers
    - `check_setup` - Check if learner has questions registered
    - `get_learner_questions` - Get random question for verification
    - `verify_answer` - Verify answer during clock-in (compares hashes)

---

## Files Modified/Created

### Modified
1. `lib/backup_clock_in_page.dart`
   - Added import for `learner_security_questions_setup_page.dart`
   - Updated `_enrollFace()` to call `_promptSecurityQuestionsSetup()` after success
   - Added `_promptSecurityQuestionsSetup()` function (checks setup status, shows dialog, navigates to setup page)
   - Updated `_verifyWithSecurityQuestions()` to use API-based verification (replaces ID number verification)

### Created
1. `lib/learner_security_questions_setup_page.dart` - Complete security questions setup UI
2. `sql/create_security_questions_tables.sql` - MySQL schema for security questions
3. `mobile/manage_security_questions.php` - Backend API for security questions
4. `SECURITY_QUESTIONS_COMPLETE_GUIDE.md` - Backend implementation guide
5. `SECURITY_QUESTIONS_FRONTEND_IMPLEMENTATION.md` - Frontend verification guide
6. `LEARNER_REGISTRATION_COMPLETE_FLOW.md` - This document

---

## Setup UI Features

The `LearnerSecurityQuestionsSetupPage` includes:

✅ **Header card** - Explains purpose and instructions  
✅ **Question counter** - Shows "Selected: X/5 (minimum 3)"  
✅ **15 predefined questions** - Loaded from server  
✅ **Checkbox selection** - Select 3-5 questions  
✅ **Answer fields** - Appear when question is checked  
✅ **Validation**:
- Minimum 3 questions required
- Maximum 5 questions allowed
- No empty answers allowed
✅ **Skip option** - If `isRequired: false` (face already enrolled)  
✅ **Save button** - Shows count "Save X Questions"  
✅ **Loading states** - Shows spinners during API calls  
✅ **Error handling** - Shows retry button on failure  
✅ **Back button protection** - Warns if trying to exit when required

---

## Deployment Checklist

### Backend (Server)

- [ ] Deploy SQL schema: `sql/create_security_questions_tables.sql`
  ```sql
  -- Creates 3 tables: security_questions, learner_security_answers, 
  -- security_question_verification_log
  -- Inserts 15 predefined questions
  ```

- [ ] Deploy PHP API: `mobile/manage_security_questions.php`
  ```
  - Check file permissions (644)
  - Verify $servername, $username, $password, $dbname
  - Test all 5 actions with Postman
  ```

### Frontend (Mobile App)

- [ ] Files already updated:
  - `lib/backup_clock_in_page.dart` ✅
  - `lib/learner_security_questions_setup_page.dart` ✅

- [ ] Build APK:
  ```powershell
  flutter clean
  flutter pub get
  flutter build apk --release
  ```

- [ ] Install and test:
  ```
  - Register new test learner face
  - Verify security questions prompt appears
  - Complete security questions setup
  - Simulate face recognition failure (cover camera)
  - Verify security question verification works
  - Test wrong answer (should block)
  - Test correct answer (should allow clock-in)
  ```

---

## Testing Scenarios

### Scenario 1: New Learner (No Registration)
1. Open backup clock-in page
2. Select new learner
3. System prompts: "No face registered"
4. Click "Register Face"
5. Capture face photo
6. Success: "Face registered successfully!"
7. System prompts: "Set up security questions"
8. Click "Set Up Now"
9. Select 3 questions, provide answers
10. Click "Save 3 Questions"
11. Success: "Security questions saved successfully!"
12. **Result**: Learner fully registered, ready to clock in

### Scenario 2: Face Enrolled, No Security Questions
1. Learner with face already enrolled attempts clock-in
2. Face verification succeeds → Clock-in proceeds (no security questions prompt)
3. Later, face verification fails 3 times
4. System shows: "Security questions not set up"
5. **Result**: Cannot clock in until security questions are registered

### Scenario 3: Face Fails → Security Questions
1. Learner attempts clock-in
2. Face verification fails 3 times
3. System shows random security question: "What is your mother's maiden name?"
4. Learner enters correct answer: "Smith"
5. System verifies SHA256 hash matches
6. Success: "✅ Identity verified via security questions"
7. **Result**: Clock-in proceeds

### Scenario 4: Wrong Security Answer
1. Face fails 3 times → Security question appears
2. Learner enters wrong answer
3. System shows: "❌ Incorrect answer. Please try again."
4. Dialog closes, returns `false`
5. Learner must start clock-in process again
6. Next attempt gets a DIFFERENT random question
7. **Result**: Blocked until correct answer provided

---

## User Training

### For Learners

**Initial Registration**:
1. "First time using backup clock-in? You need to register your face."
2. "Look directly at the camera and hold still."
3. "Next, choose 3-5 security questions and provide answers only you know."
4. "Write down your answers somewhere safe!"

**Face Verification Fails**:
1. "If face recognition doesn't work, you'll be asked a security question."
2. "Answer correctly to clock in/out."
3. "Wrong answer? You'll need to try again."

### For Facilitators

1. "Help learners register face and security questions on first clock-in."
2. "Make sure they choose questions they can remember."
3. "If a learner forgets answers, contact admin to reset security questions."

---

## Security Notes

✅ Answers are **SHA256 hashed** before storage (password-style security)  
✅ Case-insensitive comparison (hashes lowercase version)  
✅ Random question selection prevents pattern prediction  
✅ Full audit trail in `security_question_verification_log`  
✅ No plain-text answers stored anywhere  
✅ 3 face attempts before fallback (prevents easy bypassing of face verification)

---

## Future Enhancements

- [ ] Add "Reset Security Questions" feature (admin/facilitator only)
- [ ] Allow learners to update their security questions (with verification)
- [ ] Add SMS/Email verification as additional fallback
- [ ] Track verification method used in clocking records (face vs. security_question vs. signature_only)
- [ ] Dashboard: Show learners who haven't completed registration

---

**Implementation Status**: ✅ Complete  
**Ready for Deployment**: ✅ Yes  
**Testing Required**: ⏳ Pending  
**Documentation**: ✅ Complete
