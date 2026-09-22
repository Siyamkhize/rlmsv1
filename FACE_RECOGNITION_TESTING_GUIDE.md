# Face Recognition Testing Guide

## Overview
This guide covers testing the face recognition system integrated into the backup clock-in flow.

## Prerequisites

### 1. Database Setup (MySQL)
Run these SQL files on your MySQL server via phpMyAdmin:

```sql
-- File: sql/001_create_learner_face_tables.sql
-- Creates: learner_face, learner_face_verification_log tables
```

```sql
-- File: sql/004_create_learner_clocking_evidence_mysql_optional.sql (OPTIONAL)
-- Creates: learner_clocking_evidence table for server-side evidence storage
```

### 2. Mobile App Installation
The APK has been built and installed with face recognition support:
- Location: `C:\projects\rlmss\build\app\outputs\flutter-apk\app-release.apk`
- Database will auto-migrate to version 12 on first launch
- SQLite table `learner_clocking_evidence` will be created automatically

### 3. Server Endpoints
Verify these PHP endpoints are accessible:
- `mobile/face_recognition_config.php` - Configuration
- `mobile/enrol_learner_face.php` - Enrollment
- `mobile/verify_learner_face.php` - Verification
- `mobile/check_face_enrollment.php` - Check enrollment status

---

## Test Scenarios

### Scenario 1: First-Time Face Enrollment

**Steps:**
1. Open the app and navigate to **Backup Clock-In** page
2. Select a learner who has never enrolled their face
3. Tap **Clock In** button
4. Complete profile, bank, and document checks
5. Enter ID number for verification
6. **Expected:** Dialog appears: "No face registered for this learner"
7. Tap **Register Face** button
8. **Expected:** Camera opens with SimpleFaceCapture screen
9. Position your face in the oval guide
10. **Expected:** Face quality indicator shows status (None/Bad/Good/Multiple)
11. Wait for "Good" quality
12. Tap **Capture Face** button
13. **Expected:** Processing dialog appears "Processing face data..."
14. **Expected:** Success message "✅ Face registered successfully!"
15. Continue with clock-in flow

**Verification:**
- Check MySQL `learner_face` table - new record with 192-dim embedding
- Check `created_at` timestamp

---

### Scenario 2: Face Verification Success (1st Attempt)

**Steps:**
1. Use a learner who has already enrolled their face
2. Tap **Clock In** button
3. Complete preliminary checks
4. Enter ID number
5. **Expected:** Camera opens for face verification (no enrollment prompt)
6. Position your face (same person who enrolled)
7. **Expected:** "Face Quality: Good"
8. Tap **Capture Face** button
9. **Expected:** "Verifying face (Attempt 1 of 3)..."
10. **Expected:** "✅ Face verified successfully!"
11. Continue with signature and GPS steps
12. Complete clock-in

**Verification:**
- Check MySQL `learner_face_verification_log` - new record with `verified=1`
- Check SQLite `learner_clocking_evidence` - record has:
  - `clock_in_photo` (Base64 image, ~200-300KB)
  - `clock_in_verification_method = 'face'`
  - `clock_in_face_log_id` (matches MySQL log ID)
  - GPS coordinates

---

### Scenario 3: Face Verification Failure → Security Questions

**Steps:**
1. Use enrolled learner
2. Start clock-in flow
3. **During face verification:** Use a DIFFERENT person's face
4. Attempt 1: **Expected:** "Verification failed... (Attempt 1 of 3)"
5. Attempt 2: **Expected:** "Verification failed... (Attempt 2 of 3)"
6. Attempt 3: **Expected:** "Verification failed... (Attempt 3 of 3)"
7. **Expected:** "Face verification failed after 3 attempts. Please use security questions."
8. **Expected:** Security questions dialog appears
9. Enter **first 6 digits of ID number** (YYMMDD)
10. Enter **full 13-digit ID number**
11. Tap **Verify**
12. **Expected:** "✅ Identity verified via security questions"
13. Continue with clock-in

**Verification:**
- Check MySQL `learner_face_verification_log` - 3 records with `verified=0`
- Check SQLite `learner_clocking_evidence`:
  - `clock_in_photo = NULL` (no photo captured)
  - `clock_in_verification_method = 'security_question'`
  - `clock_in_face_log_id = NULL`

---

### Scenario 4: Skip Face Enrollment

**Steps:**
1. Use a learner with no enrolled face
2. Start clock-in flow
3. **Expected:** "No face registered for this learner" dialog
4. Tap **Skip for Now** button
5. **Expected:** Proceeds to signature step WITHOUT face verification
6. Complete signature and GPS
7. Complete clock-in

**Verification:**
- No entry in `learner_face` table
- No entry in `learner_face_verification_log`
- Check `learner_clocking_evidence`:
  - `clock_in_photo = NULL`
  - `clock_in_verification_method = 'signature'`
  - `clock_in_face_log_id = NULL`

---

### Scenario 5: Security Questions Failure → Clock-In Aborted

**Steps:**
1. Use enrolled learner with different person's face (3 failed attempts)
2. Security questions dialog appears
3. Enter **INCORRECT** date of birth
4. **Expected:** "Incorrect answers. Please try again."
5. Tap **Cancel** on security questions dialog
6. **Expected:** Clock-in process is aborted
7. **Expected:** User returns to learner list

**Verification:**
- No clock-in record created in `learner_clocking`
- No evidence record created in `learner_clocking_evidence`
- 3 failed verification attempts logged in MySQL

---

### Scenario 6: Face Quality Indicators

**Test each quality state:**

| Face Position | Expected Quality | Can Capture? |
|--------------|-----------------|--------------|
| No face visible | "None" (Red) | ❌ Shows error |
| Face too small/far | "Bad (too small)" (Orange) | ❌ Shows error |
| Face good size | "Good" (Green) | ✅ Captures |
| Multiple faces | "Multiple" (Orange) | ❌ Shows error |

**Steps:**
1. Open face capture screen
2. Test each position above
3. Try capturing in each state
4. Verify error messages appear for invalid states

---

### Scenario 7: Clock-Out (No Face Verification)

**Steps:**
1. Clock out a learner who clocked in earlier
2. **Expected:** No face verification step (only signature)
3. Complete signature and GPS
4. Complete clock-out

**Verification:**
- Check `learner_clocking_evidence`:
  - `clock_out_photo = NULL` (no photo for clock-out)
  - `clock_out_verification_method = 'signature'`
  - `clock_out_face_log_id = NULL`

---

## Edge Cases

### Edge Case 1: Camera Permission Denied
**Expected:** Error message "Camera error: ..." appears

### Edge Case 2: Offline Mode
**Expected:**
- Face enrollment fails (requires server)
- Face verification fails (requires server)
- Falls back to signature-only mode

### Edge Case 3: Poor Lighting
**Expected:**
- Face detection may fail
- "Failed to process face. Please try again with better lighting."
- User can retry

### Edge Case 4: Face Detection Timeout
**Expected:**
- Processing continues for 500ms intervals
- User can cancel and retry

---

## Data Verification Queries

### Check Face Enrollment
```sql
SELECT 
    lf.id,
    lf.learner_id,
    ld.Name,
    ld.Surname,
    lf.created_at
FROM learner_face lf
JOIN learnerdetails ld ON lf.learner_id = ld.LearnerID
WHERE lf.learner_id = ?;
```

### Check Verification Logs
```sql
SELECT 
    id,
    learner_id,
    verified,
    similarity_score,
    verification_method,
    created_at
FROM learner_face_verification_log
WHERE learner_id = ?
ORDER BY created_at DESC
LIMIT 10;
```

### Check Evidence Records (SQLite)
```sql
SELECT 
    id,
    LearnerID,
    clock_date,
    clock_in_verification_method,
    clock_in_face_log_id,
    LENGTH(clock_in_photo) as photo_size_bytes,
    clock_in_latitude,
    clock_in_longitude
FROM learner_clocking_evidence
WHERE LearnerID = ?
ORDER BY clock_date DESC;
```

### Check Evidence Records (MySQL - Optional)
```sql
SELECT 
    id,
    learner_id,
    clock_date,
    clock_in_verification_method,
    clock_in_face_log_id,
    LENGTH(clock_in_photo) as photo_size_bytes,
    clock_in_latitude,
    clock_in_longitude
FROM learner_clocking_evidence
WHERE learner_id = ?
ORDER BY clock_date DESC;
```

---

## Configuration Values

Check `mobile/face_recognition_config.php`:
```php
'FACE_MATCH_THRESHOLD' => 0.72
'FACE_EMBEDDING_LENGTH' => 192
'MIN_ENROLLMENT_QUALITY' => 0.6
'MIN_VERIFICATION_QUALITY' => 0.5
```

These can be adjusted based on testing results:
- **Higher threshold** = stricter matching (fewer false positives, more false negatives)
- **Lower threshold** = looser matching (more false positives, fewer false negatives)

---

## Troubleshooting

### Issue: "No face detected"
**Solution:** Ensure good lighting, face directly at camera, remove glasses

### Issue: "Multiple faces detected"
**Solution:** Ensure only one person is visible in camera frame

### Issue: Camera not opening
**Solution:** Check camera permissions in Android settings

### Issue: Face verification always fails
**Solution:**
1. Check threshold value (may be too strict)
2. Verify enrollment and verification are using same person
3. Check lighting conditions match between enrollment and verification

### Issue: Evidence not saving
**Solution:**
1. Check database migration ran (version 12)
2. Check `learner_clocking_evidence` table exists
3. Check logs for saveClockInEvidence errors

---

## Success Criteria

✅ **Pass Criteria:**
- Face enrollment completes in <10 seconds
- Face verification completes in <5 seconds
- Photos stored are <500KB each
- GPS coordinates captured accurately
- All verification methods logged correctly
- Evidence table populated with all data
- Offline gracefully falls back to signature-only

❌ **Fail Criteria:**
- Camera crashes or freezes
- Face detection never shows "Good" quality
- Verification always fails for same person
- Data not saved to evidence table
- App crashes during face capture

---

## Test Completion Checklist

- [ ] Scenario 1: First-time enrollment completed
- [ ] Scenario 2: Successful verification (1st attempt)
- [ ] Scenario 3: 3 failed attempts → security questions
- [ ] Scenario 4: Skip enrollment works
- [ ] Scenario 5: Failed security questions aborts clock-in
- [ ] Scenario 6: All quality indicators tested
- [ ] Scenario 7: Clock-out has no face verification
- [ ] Edge Case 1: Camera permission denial handled
- [ ] Edge Case 2: Offline mode falls back correctly
- [ ] Edge Case 3: Poor lighting handled gracefully
- [ ] MySQL tables populated correctly
- [ ] SQLite evidence table populated correctly
- [ ] Verification logs created in MySQL
- [ ] GPS coordinates captured
- [ ] Photos stored in Base64 format

---

## Next Steps After Testing

1. **Adjust threshold** if too many false positives/negatives
2. **Monitor photo sizes** - compress if exceeding 500KB
3. **Review verification logs** for patterns
4. **Train users** on proper face positioning
5. **Document any issues** encountered during testing
