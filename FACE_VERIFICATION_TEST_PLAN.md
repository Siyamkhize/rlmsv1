# Face Verification Test Plan - Three Critical Fixes

## Date: September 23, 2026

## ✅ Changes Implemented

### 1. **Reduced Attempts: 10 → 4**
- Learners now get exactly **4 face verification attempts**
- All UI messages updated to show "4 attempts" instead of "10 attempts"

### 2. **Cancel During Enrollment = Exit Clock-in**
- When user clicks "Cancel" during face enrollment, clock-in **stops immediately**
- User returns to learner selection screen (no signature pad shown)

### 3. **No Automatic Re-enrollment**
- After 4 failed attempts, system shows simple error message
- No re-enrollment dialog offered
- Message directs user to contact facilitator

---

## Test Scenarios

### ✅ TEST 1: Cancel During Initial Enrollment

**Setup:**
- Use a learner who has **never enrolled** their face
- Device must be online or offline (works both ways)

**Steps:**
1. Open Backup Clock-In Page
2. Select a learner without face enrollment
3. System prompts: "Register Your Face - This is required for secure clock-in"
4. Click **"Cancel"** button (not "Register Face")

**Expected Results:**
- ✅ Clock-in flow stops immediately
- ✅ User returns to learner selection screen
- ✅ **NO signature pad shown**
- ✅ No error messages (just cancelled)
- ✅ Console log shows: `[BACKUP_CLOCKIN] Face enrollment cancelled - stopping clock-in`

**How to Verify:**
- Check that you're back at the learner list
- Verify the clock-in button is enabled again (not stuck in "processing")
- Console should NOT show signature capture step

---

### ✅ TEST 2: Successful Enrollment → Immediate Verification

**Setup:**
- Use a learner who has never enrolled their face
- Good lighting conditions
- Front-facing camera available

**Steps:**
1. Select learner without face enrollment
2. Click "Register Face" on enrollment prompt
3. Center face in oval, hold still
4. Wait for automatic capture (3 seconds)
5. System processes and saves face data

**Expected Results:**
- ✅ Face captures automatically when centered
- ✅ "Processing face data..." shown briefly
- ✅ Success message: "Face enrolled successfully"
- ✅ System immediately starts verification (Attempt 1 of 4)
- ✅ Verification succeeds on first or second attempt
- ✅ Proceeds to signature pad
- ✅ Clock-in completes successfully

**How to Verify:**
- Look for console messages:
  - `[FACE] Enrollment successful`
  - `[BACKUP_CLOCKIN] Face enrolled - starting verification`
  - `[FACE] Verification attempt 1 of 4`
  - `[FACE] Verification SUCCESS`

---

### ✅ TEST 3: Face Verification with 4 Attempts

**Setup:**
- Use a learner with **already enrolled** face
- Prepare to deliberately fail verification (look away, cover face, etc.)

**Steps:**
1. Select learner with enrolled face
2. System starts face verification
3. **Attempt 1**: Look away or cover face → FAIL
4. System shows: "Verification failed (Attempt 1 of 4)"
5. **Attempt 2**: Look away or cover face → FAIL
6. System shows: "Verification failed (Attempt 2 of 4)"
7. **Attempt 3**: Look away or cover face → FAIL
8. System shows: "Verification failed (Attempt 3 of 4)"
9. **Attempt 4**: Look away or cover face → FAIL
10. System shows: "Verification failed (Attempt 4 of 4)"

**Expected Results:**
- ✅ System tries exactly **4 times** (not 10)
- ✅ Each attempt shows current count: "Attempt X of 4"
- ✅ After 4th failure, system shows error:
  - "Face verification failed after 4 attempts. Please contact your facilitator for assistance."
- ✅ Error message is **red**
- ✅ Clock-in flow stops
- ✅ User returns to learner selection
- ✅ **NO re-enrollment dialog shown**
- ✅ Console log: `[FACE] All 4 verification attempts failed`

**How to Verify:**
- Count the capture attempts (should be exactly 4)
- Verify NO dialog asking to "Re-enroll Face"
- Check error message mentions "facilitator" (not re-enrollment)

---

### ✅ TEST 4: Successful Verification (Normal Flow)

**Setup:**
- Use a learner with enrolled face
- Good lighting, proper face positioning

**Steps:**
1. Select learner with enrolled face
2. System starts verification
3. Look at camera, hold still
4. Wait for automatic verification

**Expected Results:**
- ✅ System shows: "Look at the camera and hold still (Attempt 1 of 4)"
- ✅ Verification succeeds within 1-2 attempts
- ✅ Success message shown
- ✅ Proceeds to signature pad
- ✅ Clock-in completes successfully
- ✅ Console shows: `[FACE] Verification SUCCESS`

**How to Verify:**
- Verification should complete quickly (< 5 seconds)
- No excessive retries needed
- Smooth transition to signature

---

### ✅ TEST 5: Cancel During Re-verification After Partial Failure

**Setup:**
- Learner with enrolled face
- Fail first attempt, then cancel

**Steps:**
1. Select learner with enrolled face
2. System starts verification (Attempt 1)
3. Look away → Fail attempt 1
4. On Attempt 2, click the "Cancel" button in face capture dialog

**Expected Results:**
- ✅ System respects cancel button
- ✅ Clock-in flow stops
- ✅ User returns to learner selection
- ✅ **NO signature pad shown**

**Note:** This tests that cancel works at ANY point during verification, not just initial enrollment

---

## Edge Cases to Test

### EDGE 1: Network Loss During Enrollment
- Start enrollment with internet
- Disconnect during face capture
- Verify: System handles gracefully, shows appropriate error

### EDGE 2: Camera Permission Denied
- Deny camera permission when prompted
- Verify: Clear error message, clock-in stops (no crash)

### EDGE 3: Poor Lighting Conditions
- Try enrollment in very dark room
- Verify: System shows quality warnings, allows retry

### EDGE 4: Multiple Fast Cancels
- Start enrollment → Cancel
- Immediately try again → Cancel
- Try third time → Complete
- Verify: No memory leaks, no stuck states

---

## Console Log Reference

### Successful Flow:
```
[BACKUP_CLOCKIN] ===== STEP 5: FACE RECOGNITION =====
[BACKUP_CLOCKIN] Face enrolled - starting verification
[FACE] Verification attempt 1 of 4
[FACE] Verification SUCCESS - photo captured
[BACKUP_CLOCKIN] Face verification SUCCESS - photo captured
[BACKUP_CLOCKIN] ===== STEP 6: SIGNATURE CAPTURE =====
```

### Cancel During Enrollment:
```
[BACKUP_CLOCKIN] ===== STEP 5: FACE RECOGNITION =====
[BACKUP_CLOCKIN] No face enrolled - offering enrollment
[FACE] Enrollment cancelled by user
[BACKUP_CLOCKIN] Face enrollment cancelled - stopping clock-in
```

### 4 Failed Attempts:
```
[FACE] Verification attempt 1 of 4
[FACE] Verification failed: Face not recognized
[FACE] Verification attempt 2 of 4
[FACE] Verification failed: Face not recognized
[FACE] Verification attempt 3 of 4
[FACE] Verification failed: Face not recognized
[FACE] Verification attempt 4 of 4
[FACE] Verification failed: Face not recognized
[FACE] All 4 verification attempts failed
[BACKUP_CLOCKIN] Face verification failed after 4 attempts - stopping
```

---

## Performance Benchmarks

| Scenario | Expected Duration | Max Acceptable |
|----------|------------------|----------------|
| Single successful verification | 3-5 seconds | 10 seconds |
| 4 failed attempts + exit | 40-60 seconds | 90 seconds |
| Enrollment + verification | 10-15 seconds | 25 seconds |
| Cancel (instant exit) | < 1 second | 2 seconds |

---

## Regression Tests

### Must Still Work:
- ✅ Offline face verification (using cached embeddings)
- ✅ Face enrollment with quality checks
- ✅ Security questions fallback (if implemented)
- ✅ Signature capture after successful verification
- ✅ Clock-out flow (unchanged)
- ✅ Geofencing verification (Step 3)
- ✅ GPS tracking (Step 4)

---

## Success Criteria

All tests pass when:

1. **Cancel exits immediately** (no signature pad)
2. **Exactly 4 attempts** shown for learners
3. **No re-enrollment dialog** after failures
4. **Clear error messages** directing to facilitator
5. **No crashes** or stuck states
6. **Console logs** match expected patterns
7. **Performance** within benchmarks

---

## Next Steps After Testing

1. ✅ Run all 5 test scenarios
2. ✅ Verify console logs match expectations
3. ✅ Check edge cases
4. ✅ Test on both online and offline modes
5. ✅ Build new APK if all tests pass
6. ✅ Deploy to test devices
7. ✅ Get facilitator feedback

---

## Known Limitations

- Facilitators may have different attempt limits (check `facilitator_face_clockin_page.dart`)
- Re-enrollment can still be done manually by facilitator/admin
- Offline verification uses cached embeddings (less strict than online)
- Face quality checks may vary by device camera

---

## Rollback Plan

If issues found:
1. Git revert to commit before these changes
2. Previous behavior: 10 attempts, auto re-enrollment offer
3. Emergency fix: Increase attempts back to 10 in line 2607

---

## Testing Checklist

- [ ] TEST 1: Cancel during enrollment
- [ ] TEST 2: Successful enrollment → verification
- [ ] TEST 3: 4 failed attempts
- [ ] TEST 4: Successful verification (normal)
- [ ] TEST 5: Cancel during re-verification
- [ ] EDGE 1: Network loss
- [ ] EDGE 2: Camera permission denied
- [ ] EDGE 3: Poor lighting
- [ ] EDGE 4: Multiple fast cancels
- [ ] Verify all console logs
- [ ] Check performance benchmarks
- [ ] Test offline mode
- [ ] Test online mode
- [ ] No crashes observed
- [ ] No memory leaks
- [ ] User experience is smooth

---

## Contact

For questions or issues during testing:
- Developer: [Your contact]
- Test Environment: Development
- File: `lib/backup_clock_in_page.dart`
- Last Modified: September 23, 2026
