# Security Questions Frontend Implementation

**Date**: 2026-09-25  
**Status**: ✅ Complete - Verification function implemented

## What Changed

Replaced the `_verifyWithSecurityQuestions()` function in `backup_clock_in_page.dart` (line ~3498) from **ID number verification** to **API-based security questions verification**.

---

## Old vs New Comparison

### ❌ OLD (Removed)
```dart
// Asked for date of birth (first 6 digits of ID)
// Asked for full ID number
// Verified locally against learner's stored ID number
```

**Problems:**
- Used ID numbers we removed earlier
- No server-side verification
- No audit trail
- Static questions - same for every verification attempt

---

### ✅ NEW (Implemented)

```dart
// 1. Check if learner has set up security questions (API call)
// 2. Get random security question for this learner (API call)
// 3. Show dialog with the retrieved question
// 4. Verify answer with server (API call with SHA256 hash comparison)
// 5. Log verification attempt to audit table
```

**Benefits:**
- Uses pre-registered personalized security questions
- Random question selection each time
- Server-side verification with SHA256 hashing
- Full audit trail in `security_question_verification_log`
- Wrong answer blocks clock-in until correct answer provided

---

## API Integration Details

### Endpoint
`{baseUrl}/mobile/manage_security_questions.php`

### Step 1: Check Setup
```dart
POST action=check_setup, learner_id=XXX
Response: {"success": true/false, "questions_count": 3}
```

### Step 2: Get Random Question
```dart
POST action=get_learner_questions, learner_id=XXX
Response: {
  "success": true,
  "question": "What is your mother's maiden name?",
  "question_id": 2
}
```

### Step 3: Verify Answer
```dart
POST action=verify_answer, learner_id=XXX, question_id=2, answer="Smith"
Response: {"success": true, "verified": true/false}
```

---

## User Flow

### Scenario: Face Recognition Fails 3 Times

1. **System**: "Face verification failed. Please answer your security question:"
2. **Question displayed**: "What is your mother's maiden name?" (random from learner's registered questions)
3. **Learner enters**: "Smith"
4. **System verifies**: Compares SHA256 hash of "smith" (case-insensitive) against stored hash
5. **Result**:
   - ✅ **Correct**: Clock-in/out proceeds
   - ❌ **Wrong**: "Incorrect answer. Please try again." - returns `false`, blocks clock-in/out
6. **Retry**: If learner tries again, they get a NEW random question

---

## Error Handling

The new implementation handles:

1. **Server unreachable**: Shows error message, returns `false`
2. **Security questions not set up**: Shows "Security questions not set up", returns `false`
3. **Empty answer**: Shows "Please enter an answer", stays in dialog
4. **Wrong answer**: Shows "Incorrect answer. Please try again.", returns `false`
5. **Correct answer**: Shows "✅ Identity verified via security questions", returns `true`

---

## Testing Checklist

Before deploying to production:

- [ ] Deploy `sql/create_security_questions_tables.sql` to MySQL server
- [ ] Deploy `mobile/manage_security_questions.php` to web server
- [ ] Test API endpoint with Postman/curl:
  - `check_setup` action
  - `get_learner_questions` action
  - `verify_answer` action
- [ ] Register test learner with 3-5 security questions
- [ ] Build and install APK on test device
- [ ] Simulate face recognition failure (cover camera)
- [ ] Verify security question appears
- [ ] Test wrong answer (should block clock-in)
- [ ] Test correct answer (should allow clock-in)
- [ ] Verify audit log in `security_question_verification_log` table

---

## Next Steps

1. **Create Security Questions Setup UI** - Learners need a way to register their questions
   - Add to `LearnerDetailsPage.dart` OR
   - Create new dedicated page like `SecurityQuestionsSetupPage.dart`
   - UI should:
     - Show list of available questions from `security_questions` table
     - Let learner select 3-5 questions
     - Collect answers (will be hashed before storage)
     - Call `manage_security_questions.php` with `action=save_answers`

2. **SQLite Migration** - Add security questions tables to mobile database schema in `database_helper.dart` (optional, only if storing locally)

3. **User Training** - Document how to:
   - Set up security questions
   - What happens when face recognition fails
   - How to reset security questions if forgotten

---

## Code Location

**File**: `lib/backup_clock_in_page.dart`  
**Function**: `_verifyWithSecurityQuestions()` (line ~3498)  
**Trigger**: Called after 3 failed face recognition attempts (line ~3212)

---

## Related Documentation

- `SECURITY_QUESTIONS_COMPLETE_GUIDE.md` - Full backend implementation guide
- `SESSION_SUMMARY_COMPLETE_FIXES.md` - Summary of all backup clock-in fixes
- `sql/create_security_questions_tables.sql` - Database schema
- `mobile/manage_security_questions.php` - Backend API

---

**Implementation completed** ✅  
**Backend ready for deployment** ✅  
**Frontend verification function updated** ✅  
**Setup UI needed** ⏳
