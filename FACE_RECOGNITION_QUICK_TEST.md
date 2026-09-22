# Face Recognition Quick Test Guide

## ✅ APK Installed Successfully!

**Build:** 197.2MB  
**Device:** RZ8X10CKD0B  
**Database Version:** 13 (with offline face recognition)  
**Date:** September 19, 2026

---

## 🧪 Test Steps

### Test 1: First-Time Enrollment (Online or Offline)

1. **Open the app** on device RZ8X10CKD0B
2. **Login** as facilitator
3. **Navigate to:** Dashboard → Backup Clock In
4. **Enter Learner ID** (use a learner who hasn't enrolled face yet)
5. **Complete checks:** Profile, Bank, Documents
6. **Face Enrollment Dialog appears:**
   ```
   "No face registered for this learner"
   [Skip for Now] [Register Face]
   ```
7. **Tap "Register Face"**
8. **SimpleFaceCapture opens:**
   - Front camera activates
   - Quality indicator shows: Red "None" → Green "Good" when face detected
   - Green bounding box appears around face
   - Center guide oval helps positioning
9. **Position face in oval** until quality shows "Good"
10. **Tap "Capture Face"** button
11. **Processing dialog:** "Processing face data..."
12. **Success message:**
    - Online: "✅ Face registered successfully!"
    - Offline: "✅ Face saved locally (offline mode)"

### Test 2: Face Verification (Online)

1. **Same learner** from Test 1
2. **Navigate to:** Dashboard → Backup Clock In
3. **Enter same Learner ID**
4. **Face verification starts automatically** (no enrollment dialog)
5. **SimpleFaceCapture opens:**
   ```
   "Verify Your Identity (Attempt 1 of 3)"
   ```
6. **Position face → Capture**
7. **Processing:** "Verifying face (Attempt 1 of 3)..."
8. **Success:** "✅ Face verified successfully!"
9. **Proceeds to signature** capture
10. **Complete clock-in**

**Verify Evidence:**
- Signature saved
- Face photo saved (Base64 in evidence table)
- GPS coordinates captured
- Verification method: "face"

### Test 3: Offline Verification

1. **Turn OFF Wi-Fi and Mobile Data** on device
2. **Same learner** (already enrolled in Test 1)
3. **Navigate to:** Backup Clock In
4. **Enter Learner ID**
5. **Face verification starts**
6. **Capture face**
7. **Brief delay** (trying server, will timeout)
8. **Success:** "✅ Face verified successfully! (Offline mode)"
   - Notice the **(Offline mode)** text
9. **Complete clock-in**

**Verify:**
- Verification completed without network
- Log queued for sync (check console for `[OFFLINE_FACE]` messages)

### Test 4: Failed Verification → Security Questions

1. **Enroll Learner A's face**
2. **Try to verify with Learner B** (wrong person)
3. **Attempt 1:** "Verification failed: Face doesn't match (Attempt 1 of 3)"
4. **Attempt 2:** Same
5. **Attempt 3:** Same
6. **Security Questions appear:**
   ```
   Question 1: What is your date of birth? (YYMMDD from ID)
   Question 2: Enter your full ID number
   ```
7. **Answer correctly**
8. **Success:** Proceeds to signature
9. **Complete clock-in**

### Test 5: Automatic Sync

1. **After offline verification** (Test 3)
2. **Close app**
3. **Turn ON Wi-Fi/Data**
4. **Open app** → Navigate to Backup Clock In
5. **Check console logs:**
   ```
   [FACE_SYNC] Found X unsynced verification logs
   [FACE_SYNC] ✅ Successfully synced X verification logs
   ```
6. **Silent sync** (no user notification)

---

## 📊 What to Check

### On Device (SQLite)

**Check Cached Embeddings:**
- Open SQLite database: `local_data.db`
- Query: `SELECT * FROM learner_face_cache WHERE learner_id = [ID]`
- Should show: embedding (JSON array), quality_score, enrolled_at

**Check Verification Queue:**
- Query: `SELECT * FROM learner_face_verification_queue WHERE synced = 0`
- Offline verifications appear here until synced

**Check Evidence:**
- Query: `SELECT * FROM learner_clocking_evidence WHERE LearnerID = [ID]`
- Should show: signature, clock_in_photo (Base64), verification_method

### On Server (MySQL)

**Check Enrollment:**
- Table: `learner_face_data`
- Query: `SELECT * FROM learner_face_data WHERE learner_id = [ID]`
- Should show: embedding, quality_score, enrolled_at

**Check Online Verification Logs:**
- Table: `learner_face_verification_log`
- Query: `SELECT * FROM learner_face_verification_log WHERE learner_id = [ID] ORDER BY attempted_at DESC`
- Shows: match_score, verified, verification_type

**Check Synced Offline Logs:**
- Same table as above
- Look for `device_info = 'offline_verification'`
- These were synced from device

---

## 🎯 Expected Behavior

### Enrollment
- ✅ Works online (saves to server + cache)
- ✅ Works offline (saves to cache only)
- ✅ User sees appropriate message
- ✅ Embedding is 192 elements

### Verification
- ✅ Tries server first (when online)
- ✅ Falls back to offline (when no network)
- ✅ Shows "(Offline mode)" indicator
- ✅ 3 attempts before security questions
- ✅ Security questions work as fallback

### Performance
- Enrollment: 5-8 seconds
- Verification (online): 5-8 seconds
- Verification (offline): 4-6 seconds (FASTER!)

---

## 🐛 Troubleshooting

### Camera doesn't open
- Grant camera permission
- Close other apps using camera
- Restart app

### Face detection not working
- Improve lighting
- Position face in center oval
- Remove glasses/mask if needed

### Offline verification fails
- Check if learner enrolled (needs cached embedding)
- Check database version = 13
- Check console for `[OFFLINE_FACE]` errors

### Sync not happening
- Check Wi-Fi/data connection
- Check console for `[FACE_SYNC]` messages
- Endpoint: `mobile/sync_face_verification_logs.php` must exist on server

---

## 📝 Console Log Messages to Watch

**Enrollment:**
```
[FACE] Checking face enrollment for learner 12345
[FACE] Enrollment status: false
[FACE] Starting face enrollment for learner 12345
[FACE] Enrollment successful (server: true, local: true)
[OFFLINE_FACE] Cached embedding for learner 12345 (192 dimensions, quality: 0.8)
```

**Online Verification:**
```
[FACE] Starting face verification for learner 12345
[FACE] Attempting server verification...
[FACE] Server verification result: true
[FACE] Verification successful! (ONLINE)
```

**Offline Verification:**
```
[FACE] Starting face verification for learner 12345
[FACE] Attempting server verification...
[FACE] Server verification failed: ... - falling back to offline
[OFFLINE_FACE] Starting offline verification for learner 12345
[OFFLINE_FACE] Retrieved cached embedding for learner 12345 (192 dimensions)
[OFFLINE_FACE] Cosine similarity: 0.85 (threshold: 0.72)
[OFFLINE_FACE] Queued verification log for sync (verified: true, score: 0.85)
[FACE] Verification successful! (OFFLINE)
```

**Sync:**
```
[FACE_SYNC] Starting offline face verification log sync...
[FACE_SYNC] Found 3 unsynced verification logs
[OFFLINE_FACE] Found 3 verification logs to sync
[OFFLINE_FACE] Successfully synced 3/3 verification logs
[FACE_SYNC] ✅ Successfully synced 3 verification logs
```

---

## ✅ Success Criteria

- [ ] Camera opens and shows preview
- [ ] Face detection works (bounding box appears)
- [ ] Quality indicator updates (None → Good)
- [ ] Can enroll face (online or offline)
- [ ] Can verify face (online)
- [ ] Can verify face (offline with no network)
- [ ] Shows "(Offline mode)" when offline
- [ ] 3 attempts before security questions
- [ ] Security questions work as fallback
- [ ] Signature capture works
- [ ] Evidence saved with photo
- [ ] Sync happens automatically when online

---

## 🚀 Ready to Test!

1. Open app on device RZ8X10CKD0B
2. Login as facilitator
3. Go to Backup Clock In
4. Follow Test 1 to enroll a face
5. Follow Test 2 to verify online
6. Follow Test 3 to verify offline

**Database is ready!** Version 13 with face cache tables.

**Server endpoint ready!** `sync_face_verification_logs.php` for sync.

**Model ready!** MobileFaceNet (5.2MB) in `assets/models/mobile_face_net.tflite`

---

**Questions?** Check `OFFLINE_FACE_RECOGNITION_COMPLETE.md` for detailed documentation.

**Implementation Date:** September 19, 2026  
**Build Size:** 197.2 MB  
**Database Version:** 13  
**Status:** ✅ READY FOR TESTING
