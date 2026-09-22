# Face Recognition + Province/District/Municipality Test Guide

## APK Information
- **Build Date**: September 19, 2026
- **APK Size**: 197.2MB
- **APK Location**: `C:\projects\rlmss\build\app\outputs\flutter-apk\app-release.apk`
- **Installation Status**: ✅ Successfully installed on device RZ8X10CKD0B

## What Was Fixed

### 1. Province/District/Municipality Validation
- **Issue**: Field name mismatch between `backup_clock_in_page.dart` and `LearnerDetailsPage.dart`
- **Fix**: Aligned both files to use `['Province']`, `['District']`, `['Municipality']`
- **Created**: `mobile/fetch_provinces.php` endpoint (was empty before)

### 2. Offline Face Recognition (Already Implemented)
- **Database**: SQLite v13 with `learner_face_cache` and `learner_face_verification_queue` tables
- **Service**: `OfflineFaceVerificationService` with cosine similarity (threshold 0.72)
- **Flow**: Try server first → automatic fallback to offline verification
- **Sync**: Auto-sync offline verification logs on page load

## Test Workflow

### Phase 1: Profile Completion Test
**Goal**: Verify Province/District/Municipality dropdowns work when accessed from clock-in page

1. **Open the app** on device RZ8X10CKD0B
2. **Login** with your credentials
3. **Navigate to**: Backup Clock-In page
4. **Find a learner** that is missing Province/District/Municipality fields
   - You can check database beforehand: `SELECT learner_id, Name, Surname, Province, District, Municipality FROM learnerdetails WHERE Province IS NULL OR Province = '' LIMIT 5`
5. **Enter learner ID** or scan their card
6. **Expected**: "Complete Learner Profile" dialog appears
7. **Tap**: "Open Profile" button
8. **Expected**: LearnerDetailsPage opens showing only missing fields
9. **Verify**: Province dropdown appears with options:
   - Eastern Cape
   - Free State
   - Gauteng
   - KwaZulu Natal
   - Limpopo
   - Mpumalanga
   - North West
   - Northern Cape
   - Western Cape
10. **Select Province**: Choose any province (e.g., "Gauteng")
11. **Verify**: District dropdown loads with districts for that province
12. **Select District**: Choose any district
13. **Verify**: Municipality dropdown loads with municipalities for that district
14. **Select Municipality**: Choose any municipality
15. **Tap**: "Update Data" button
16. **Expected**: Success message appears
17. **Expected**: Page closes automatically (returns to clock-in page)
18. **Expected**: Clock-in page now allows proceeding (validation passes)

### Phase 2: Face Enrollment Test
**Goal**: Enroll learner's face for recognition (both server + local cache)

19. **Continue from clock-in page** with the same learner
20. **If not enrolled**: Should see "Enroll Face" button
21. **Tap**: "Enroll Face"
22. **Expected**: Camera opens with face detection overlay
23. **Position face** in the frame:
    - Face centered
    - Good lighting
    - Not too close/far
    - Eyes open
24. **Perform liveness check**: Blink or turn head slightly as instructed
25. **Expected**: Green checkmark when quality is good
26. **Tap**: Capture button
27. **Expected**: "Face enrolled successfully" message
28. **Check logs** in console for:
    - Server enrollment result
    - Local cache save result
    - Should show "enrollment succeeded" for at least one method

### Phase 3: Online Face Verification Test
**Goal**: Verify face recognition works online (server-side)

29. **Return to clock-in page** with the enrolled learner
30. **Tap**: "Verify with Face" (or similar button)
31. **Expected**: Camera opens
32. **Show enrolled face** to camera
33. **Expected**: Face detected and compared
34. **Expected**: "Face verified successfully" message (no "Offline mode" text)
35. **Check logs**: Should show server verification succeeded

### Phase 4: Offline Face Verification Test
**Goal**: Verify offline fallback works when server is unavailable

36. **Disconnect device from internet** (turn off WiFi/mobile data)
37. **Return to clock-in page** with the enrolled learner
38. **Tap**: "Verify with Face"
39. **Expected**: Camera opens
40. **Show enrolled face** to camera
41. **Expected**: Face detected and compared
42. **Expected**: "Face verified successfully (Offline mode)" message
43. **Check logs**: Should show "offline verification" succeeded
44. **Verify**: Verification log queued for sync (check SQLite `learner_face_verification_queue` table)

### Phase 5: Sync Test
**Goal**: Verify offline logs sync when back online

45. **Reconnect device to internet**
46. **Navigate away and back** to backup clock-in page (or restart app)
47. **Check logs**: Should show "Starting offline face verification log sync"
48. **Expected**: Queued verification logs uploaded to server
49. **Verify in MySQL**: Check `learner_face_verification_log` table for synced records
50. **Verify in SQLite**: Check `learner_face_verification_queue` table - synced records should have `synced = 1`

## Expected Results

### ✅ Success Criteria
- [ ] Province/District/Municipality dropdowns load and cascade properly
- [ ] Profile updates save successfully (both local + server)
- [ ] Profile validation passes after filling location fields
- [ ] Face enrollment saves to both server AND local cache
- [ ] Online face verification works when connected
- [ ] Offline face verification works without network
- [ ] Offline verification shows "(Offline mode)" message
- [ ] Offline logs sync automatically when online

### ❌ Common Issues to Watch For

**Profile Dropdowns:**
- Dropdowns don't load → Check `mobile/fetch_provinces.php`, `fetch_districts.php`, `fetch_municipalities.php` endpoints
- Province selected but District dropdown empty → Check database `district` table has data
- District selected but Municipality dropdown empty → Check database `local_municipality` table has data

**Face Recognition:**
- "No face detected" → Improve lighting, position face better
- "Face quality too low" → Ensure face is centered, well-lit, eyes open
- Enrollment fails → Check server logs, may need to check `mobile/enroll_learner_face.php`
- Verification always fails → Check cosine similarity threshold (currently 0.72)
- Offline mode not working → Check `learner_face_cache` table has embedding data

**Sync Issues:**
- Offline logs not syncing → Check `mobile/sync_face_verification_logs.php` endpoint
- Sync fails silently → Check network connectivity and server logs

## Database Verification Queries

### Check learner location fields:
```sql
SELECT learner_id, Name, Surname, Province, District, Municipality 
FROM learnerdetails 
WHERE learner_id = 'YOUR_LEARNER_ID';
```

### Check face cache (SQLite):
```sql
SELECT learner_id, quality_score, enrolled_at, synced 
FROM learner_face_cache 
WHERE learner_id = 'YOUR_LEARNER_ID';
```

### Check verification queue (SQLite):
```sql
SELECT learner_id, match_score, verified, synced, verified_at 
FROM learner_face_verification_queue 
WHERE learner_id = 'YOUR_LEARNER_ID' 
ORDER BY verified_at DESC;
```

### Check face enrollment (MySQL server):
```sql
SELECT learner_id, quality_score, enrolled_at 
FROM learner_face 
WHERE learner_id = 'YOUR_LEARNER_ID';
```

### Check verification logs (MySQL server):
```sql
SELECT learner_id, match_score, verified, verified_at, is_offline 
FROM learner_face_verification_log 
WHERE learner_id = 'YOUR_LEARNER_ID' 
ORDER BY verified_at DESC 
LIMIT 10;
```

## Technical Details

### MobileFaceNet Model
- **Architecture**: Lightweight CNN optimized for mobile
- **Output**: 192-dimensional face embedding
- **File**: `assets/mobilefacenet.tflite`
- **Size**: ~4MB
- **On-device**: Fully offline capable

### Cosine Similarity Formula
```
similarity = (A · B) / (||A|| × ||B||)
where A = live embedding, B = cached template
```
- **Threshold**: 0.72 (same as server)
- **Range**: -1.0 to 1.0 (higher = more similar)
- **Match**: similarity ≥ 0.72

### Offline Storage
- **Face embeddings**: Stored as JSON array string in SQLite
- **Verification queue**: Stores match_score, verified (bool), timestamp
- **Sync flag**: `synced` column (0 = pending, 1 = uploaded)

## Support

If issues occur:
1. Check device logs: `adb logcat | findstr "FACE"`
2. Check Flutter logs: `adb logcat | findstr "flutter"`
3. Check server PHP error logs
4. Verify database tables exist and have proper structure
5. Confirm endpoints are accessible: Test URLs in browser/Postman

## Summary

This test guide covers the complete flow from profile completion through face recognition (online/offline) to sync verification. Follow each phase in sequence for a complete end-to-end test of the new features.
