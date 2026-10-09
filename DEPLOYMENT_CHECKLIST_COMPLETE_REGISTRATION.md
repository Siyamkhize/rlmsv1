# Deployment Checklist - Complete Registration System

**Feature**: Face Registration + Security Questions Setup  
**Date**: 2026-09-25  
**Status**: Ready for Deployment

---

## Pre-Deployment Checklist

### ✅ Code Complete

- [x] Security questions setup page created (`lib/learner_security_questions_setup_page.dart`)
- [x] Backup clock-in page updated to integrate security questions
- [x] Face enrollment triggers security questions prompt
- [x] API-based security question verification implemented
- [x] All imports added correctly
- [x] Documentation complete

### ⏳ Backend Deployment (To Do)

- [ ] **Deploy SQL Schema**
  ```bash
  # Connect to MySQL server
  mysql -u your_username -p your_database
  
  # Run schema file
  source /path/to/sql/create_security_questions_tables.sql
  # OR
  mysql -u your_username -p your_database < sql/create_security_questions_tables.sql
  
  # Verify tables created
  SHOW TABLES LIKE '%security%';
  # Should show:
  # - security_questions
  # - learner_security_answers
  # - security_question_verification_log
  
  # Verify questions inserted
  SELECT COUNT(*) FROM security_questions;
  # Should return: 15
  ```

- [ ] **Deploy PHP API**
  ```bash
  # Upload to server
  scp mobile/manage_security_questions.php user@yourserver.com:/path/to/mobile/
  
  # Or use FTP/SFTP client
  # Upload to: /path/to/mobile/manage_security_questions.php
  
  # Set permissions
  chmod 644 manage_security_questions.php
  ```

- [ ] **Update Database Connection** (if needed)
  - Edit `mobile/manage_security_questions.php`
  - Verify `$servername`, `$username`, `$password`, `$dbname` match your MySQL config

### ⏳ API Testing (To Do)

Test all endpoints with Postman or curl:

- [ ] **Test 1: Get Questions**
  ```bash
  curl -X POST http://yourserver.com/mobile/manage_security_questions.php \
    -d "action=get_questions"
  
  # Expected: {"success":true,"questions":[...15 questions...]}
  ```

- [ ] **Test 2: Save Answers**
  ```bash
  curl -X POST http://yourserver.com/mobile/manage_security_questions.php \
    -d "action=save_answers" \
    -d "learner_id=TEST123" \
    -d 'answers=[{"question_id":1,"answer":"TestAnswer1"},{"question_id":2,"answer":"TestAnswer2"},{"question_id":3,"answer":"TestAnswer3"}]'
  
  # Expected: {"success":true,"message":"Answers saved successfully"}
  ```

- [ ] **Test 3: Check Setup**
  ```bash
  curl -X POST http://yourserver.com/mobile/manage_security_questions.php \
    -d "action=check_setup" \
    -d "learner_id=TEST123"
  
  # Expected: {"success":true,"questions_count":3}
  ```

- [ ] **Test 4: Get Random Question**
  ```bash
  curl -X POST http://yourserver.com/mobile/manage_security_questions.php \
    -d "action=get_learner_questions" \
    -d "learner_id=TEST123"
  
  # Expected: {"success":true,"question":"What is...","question_id":1}
  ```

- [ ] **Test 5: Verify Answer**
  ```bash
  curl -X POST http://yourserver.com/mobile/manage_security_questions.php \
    -d "action=verify_answer" \
    -d "learner_id=TEST123" \
    -d "question_id=1" \
    -d "answer=TestAnswer1"
  
  # Expected: {"success":true,"verified":true}
  ```

---

## Build & Deploy APK

### 1. Clean Build

```powershell
# Navigate to project
cd c:\projects\rlmss

# Clean previous builds
flutter clean

# Get dependencies
flutter pub get

# Verify no errors
flutter analyze
```

### 2. Build Release APK

```powershell
# Build release APK
flutter build apk --release

# APK location:
# build\app\outputs\flutter-apk\app-release.apk
```

### 3. Test APK Size & Integrity

```powershell
# Check file size (should be ~30-50 MB)
(Get-Item "build\app\outputs\flutter-apk\app-release.apk").Length / 1MB

# Copy to easy location
Copy-Item "build\app\outputs\flutter-apk\app-release.apk" -Destination "C:\apk_builds\rlmss_with_security_questions_$(Get-Date -Format 'yyyyMMdd_HHmm').apk"
```

---

## Testing Procedures

### Test Environment Setup

- [ ] Test device with Android (physical device preferred)
- [ ] Test learner account (not in production use)
- [ ] Server with backend deployed
- [ ] Database with test data

### Test Case 1: New Learner Registration (CRITICAL)

**Objective**: Verify complete registration flow

1. [ ] Install APK on test device
2. [ ] Open app, login as facilitator
3. [ ] Navigate to Backup Clock-In page
4. [ ] Select test learner (never registered before)
5. [ ] Click "Clock In"
6. [ ] **Verify**: "No face registered" prompt appears
7. [ ] Click "Register Face"
8. [ ] **Verify**: Face capture screen opens
9. [ ] Capture face photo (look at camera)
10. [ ] **Verify**: "Processing face data..." appears
11. [ ] **Verify**: "✅ Face registered successfully!" appears
12. [ ] **Verify**: "Set up security questions" prompt appears
13. [ ] Click "Set Up Now"
14. [ ] **Verify**: Security questions page opens
15. [ ] **Verify**: 15 questions load from server
16. [ ] Select 3 questions, provide answers
17. [ ] Click "Save 3 Questions"
18. [ ] **Verify**: "✅ Security questions saved successfully!" appears
19. [ ] **Verify**: Returns to clock-in page
20. [ ] **Verify**: Learner can now proceed with clock-in

**Expected Result**: ✅ Complete registration successful

**Fail Criteria**:
- Face capture fails
- Security questions page doesn't load
- Answers don't save
- Cannot clock in after registration

---

### Test Case 2: Face Verification Success

**Objective**: Verify face recognition works

1. [ ] Use previously registered learner
2. [ ] Click "Clock In"
3. [ ] **Verify**: Face verification starts (no registration prompt)
4. [ ] Look at camera
5. [ ] **Verify**: Face matches successfully
6. [ ] **Verify**: Clock-in proceeds without security questions

**Expected Result**: ✅ Clock-in via face recognition

---

### Test Case 3: Face Fails → Security Questions

**Objective**: Verify fallback to security questions

1. [ ] Use previously registered learner
2. [ ] Click "Clock In"
3. [ ] **Cover camera lens** (force face verification to fail)
4. [ ] Let it fail 3 times
5. [ ] **Verify**: "Face verification failed. Please answer your security question:" appears
6. [ ] **Verify**: Random question from learner's registered questions shown
7. [ ] Enter correct answer
8. [ ] **Verify**: "✅ Identity verified via security questions" appears
9. [ ] **Verify**: Clock-in proceeds

**Expected Result**: ✅ Clock-in via security question

---

### Test Case 4: Wrong Security Answer

**Objective**: Verify wrong answer blocks clock-in

1. [ ] Use previously registered learner
2. [ ] Click "Clock In"
3. [ ] Cover camera (fail face 3 times)
4. [ ] Security question appears
5. [ ] Enter **wrong answer**
6. [ ] **Verify**: "❌ Incorrect answer. Please try again." appears
7. [ ] **Verify**: Dialog closes
8. [ ] **Verify**: Clock-in blocked (returns false)
9. [ ] Try again from beginning
10. [ ] **Verify**: Gets different random question

**Expected Result**: ✅ Wrong answer blocks clock-in

---

### Test Case 5: Skip Security Questions Setup

**Objective**: Verify skipping security questions

1. [ ] Register new learner face
2. [ ] When security questions prompt appears, click "Skip for Now"
3. [ ] **Verify**: Setup page doesn't open
4. [ ] Proceed to clock in
5. [ ] Face verification works normally
6. [ ] Cover camera (fail face 3 times)
7. [ ] **Verify**: "Security questions not set up" error appears
8. [ ] **Verify**: Cannot clock in

**Expected Result**: ✅ Learner blocked if face fails and no security questions

---

### Test Case 6: Database Audit Trail

**Objective**: Verify logging works

1. [ ] Complete Test Case 3 (security question verification)
2. [ ] Check database:
  ```sql
  SELECT * FROM security_question_verification_log 
  WHERE learner_id = 'TEST_LEARNER_ID'
  ORDER BY timestamp DESC;
  ```
3. [ ] **Verify**: Record exists with:
   - `verification_successful = 1` (for correct answer)
   - `timestamp` matches test time
   - `question_id` matches question shown

**Expected Result**: ✅ Audit log created

---

## Post-Deployment Monitoring

### Week 1: Monitor for Issues

- [ ] Check error logs for API failures
- [ ] Monitor database for hash verification issues
- [ ] Collect user feedback on registration flow
- [ ] Track how many learners complete security questions setup
- [ ] Check audit logs for verification patterns

### Database Queries for Monitoring

```sql
-- Check registration completion rate
SELECT 
  COUNT(DISTINCT lfe.learner_id) as faces_enrolled,
  COUNT(DISTINCT lsa.learner_id) as security_questions_setup,
  COUNT(DISTINCT lfe.learner_id) - COUNT(DISTINCT lsa.learner_id) as incomplete_registrations
FROM learner_face_enrollments lfe
LEFT JOIN learner_security_answers lsa ON lfe.learner_id = lsa.learner_id
WHERE lfe.is_active = 1;

-- Check security question usage
SELECT 
  verification_successful,
  COUNT(*) as count,
  DATE(timestamp) as date
FROM security_question_verification_log
GROUP BY verification_successful, DATE(timestamp)
ORDER BY date DESC;

-- Find learners with face but no security questions
SELECT ld.LearnerID, ld.FirstName, ld.Surname
FROM learnerdetails ld
INNER JOIN learner_face_enrollments lfe ON ld.LearnerID = lfe.learner_id
LEFT JOIN learner_security_answers lsa ON ld.LearnerID = lsa.learner_id
WHERE lfe.is_active = 1 AND lsa.answer_id IS NULL;
```

---

## Rollback Plan (If Issues Found)

### Critical Issues Only

If registration system causes major problems:

1. **Disable security questions requirement**:
   ```dart
   // In backup_clock_in_page.dart
   // Comment out line in _enrollFace():
   // await _promptSecurityQuestionsSetup(learnerId);
   ```

2. **Rebuild APK without security questions**:
   ```powershell
   flutter build apk --release
   ```

3. **Keep face verification** (already working before this update)

### Non-Critical Issues

- API errors → Fix PHP code, redeploy
- Database errors → Fix SQL, update tables
- UI issues → Fix Flutter code, rebuild APK

---

## User Training Materials

### For Facilitators

**Training Points**:
1. "New learners must register face AND security questions"
2. "First clock-in takes 5 minutes (registration)"
3. "Subsequent clock-ins take 10 seconds (face verification)"
4. "If face fails, security question appears"
5. "Help learners choose memorable questions"

**Demo Script**:
```
1. "Let me show you the new registration process"
2. [Open backup clock-in, select test learner]
3. "First, we register the face"
4. [Capture face]
5. "Now, security questions"
6. [Select 3 questions, fill answers]
7. "Done! Now the learner can clock in normally"
```

### For Learners

**Quick Guide** (print or display):
```
📱 FIRST TIME CLOCK-IN

Step 1️⃣: Register Your Face
- Look at the camera
- Stay still for 3 seconds
- ✅ Face saved!

Step 2️⃣: Security Questions
- Choose 3-5 questions
- Provide answers you will remember
- ✅ Questions saved!

✅ You're all set!

---

🔁 NEXT TIME

Just look at the camera → Clock in!

If camera doesn't work:
→ Answer your security question
→ Clock in!
```

---

## Success Criteria

### Must Pass Before Production

- [ ] Backend SQL deployed successfully
- [ ] Backend PHP API responds correctly
- [ ] All 5 API endpoints tested successfully
- [ ] APK built without errors
- [ ] Test Case 1 (new registration) passes ✅
- [ ] Test Case 3 (security question fallback) passes ✅
- [ ] Test Case 4 (wrong answer blocks) passes ✅
- [ ] Audit logs created correctly
- [ ] At least 3 facilitators trained
- [ ] User guide printed/distributed

### Nice to Have (Can Fix Later)

- Test Case 5 (skip behavior) passes
- Database monitoring queries saved
- Rollback plan documented
- Performance monitoring set up

---

## Timeline

### Day 1: Backend Deployment
- Morning: Deploy SQL schema
- Afternoon: Deploy PHP API, test endpoints

### Day 2: APK Build & Testing
- Morning: Build APK, install on test devices
- Afternoon: Run all test cases

### Day 3: User Training
- Morning: Train facilitators
- Afternoon: Print user guides, prepare demo

### Day 4: Production Rollout
- Morning: Install APK on production tablets
- Afternoon: Monitor for issues, provide support

### Week 1: Monitoring
- Daily check error logs
- Collect user feedback
- Address any issues

---

## Contact for Issues

**Technical Issues**:
- Database errors → Check MySQL logs
- API errors → Check PHP error logs at `/mobile/manage_security_questions.php`
- Flutter errors → Check `flutter doctor` output

**User Issues**:
- Cannot register face → Check camera permissions, lighting
- Cannot save security questions → Check server connection
- Wrong answer blocks clock-in → Expected behavior (by design)

---

## Final Sign-Off

Before marking complete:

- [ ] All SQL tables exist and populated with 15 questions
- [ ] All API endpoints return expected responses
- [ ] APK installs successfully on test device
- [ ] Complete registration flow tested end-to-end
- [ ] Security question verification tested (correct + wrong answers)
- [ ] Audit logs verified in database
- [ ] User training complete
- [ ] Documentation distributed

**Deployed By**: _______________  
**Date**: _______________  
**Sign-Off**: _______________

---

**Implementation Status**: ✅ Code Complete  
**Backend Status**: ⏳ Pending Deployment  
**Testing Status**: ⏳ Pending  
**Production Status**: ⏳ Pending Rollout
