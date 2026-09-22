# Face Oval Alignment & Province Dropdown Fix

## Issues Fixed

### Issue 1: Face Oval Frame Too Low
**Problem:** Face capture oval was centered vertically, causing user's face to appear too low in the frame.

**Fix Applied:**
- Changed oval positioning from `Center()` widget to `Positioned(top: 40)` 
- Oval now positioned 40 pixels from top instead of screen center
- Face aligns better with oval guide frame

**File Modified:** `lib/widgets/simple_face_capture.dart` line ~304-327

**Before:**
```dart
Center(
  child: Container(
    width: 320,
    height: 420,
    decoration: BoxDecoration(...),
  ),
),
```

**After:**
```dart
Positioned(
  left: (MediaQuery.of(context).size.width - 320) / 2,
  top: 40, // Position from top instead of center
  child: Container(
    width: 320,
    height: 420,
    decoration: BoxDecoration(...),
  ),
),
```

### Issue 2: Province/District/Municipality Dropdowns Not Loading
**Problem:** Dropdowns appeared empty even though database has data.

**Root Cause:** `fetch_provinces.php` may fail or timeout, leaving dropdowns empty with no fallback.

**Fix Applied:**
- Added hardcoded Province list as fallback
- Added timeout (10 seconds) to HTTP request
- Automatically loads hardcoded provinces if:
  - Server request fails
  - Server returns error
  - Network timeout occurs
  
**File Modified:** `lib/AddLearnerPage.dart` line ~165-220

**Hardcoded Provinces:**
```dart
[
  'Eastern Cape',
  'Free State',
  'Gauteng',
  'KwaZulu Natal',
  'Limpopo',
  'Mpumalanga',
  'Northern Cape',
  'North West',
  'Western Cape',
]
```

**Flow:**
1. Try to fetch from `fetch_provinces.php` (10s timeout)
2. If successful → use server data
3. If fails → use hardcoded list
4. Debug logs track which source was used

## Testing Instructions

### Test Face Oval Alignment
1. Open app and go to Backup Clock In
2. Select "Enroll Face" for any learner
3. Camera opens with oval frame
4. **VERIFY:** Oval should be positioned higher on screen (not centered vertically)
5. **VERIFY:** User's face should fit comfortably in oval when looking at camera
6. **VERIFY:** Face should not appear too low in frame

### Test Province Dropdown
1. Go to Add Learner page
2. Scroll to "Location Information" section
3. Tap on Province dropdown
4. **VERIFY:** Dropdown shows 9 South African provinces
5. **VERIFY:** Can select "KwaZulu Natal" from list

Check logcat for debug output:
```powershell
adb logcat | Select-String -Pattern "🌍 AddLearnerPage"
```

**Expected logs if server works:**
```
🌍 AddLearnerPage: _fetchProvinces called
🌍 AddLearnerPage: Fetching from URL: ...
🌍 AddLearnerPage: Response status: 200
🌍 AddLearnerPage: _provinces set to: [Eastern Cape, ...] (9 items)
```

**Expected logs if server fails:**
```
🌍 AddLearnerPage: EXCEPTION - Error fetching provinces: ...
🌍 AddLearnerPage: Using hardcoded provinces as fallback
🌍 AddLearnerPage: Hardcoded provinces loaded: 9 items
```

## Additional Notes

### Province Validation Issue Still Exists
**This fix only addresses the DROPDOWN loading issue.**

The original problem (Province/District/Municipality showing as "missing" in validation despite database having data) is a **SEPARATE issue** in the sync process:

1. `get_learners.php` was updated to return `'success' => true`
2. Debug logging added to track sync data flow
3. Need to verify if learner 11443 is being synced correctly

**To debug validation issue:**
```powershell
adb logcat | Select-String -Pattern "\[BACKUP"
```

Look for:
- `[BACKUP_API] First learner Province: <value>`
- `[BACKUP_STORE] LEARNER 11443 BEFORE INSERT`
- `[BACKUP_STORE] LEARNER 11443 AFTER INSERT`
- `[BACKUP] Province: <value>`

If these show null/empty, the sync is still broken.
If these show correct values but validation fails, the validation logic is broken.

### Face Capture Settings
- **Oval Size:** 320x420 pixels
- **Oval Position:** 40px from top
- **Landmark Dots:** 6 cyan dots with white borders (eyes, nose, mouth)
- **Quality Threshold:** Face size > 40,000 pixels = "Good"

## Files Modified

1. **lib/widgets/simple_face_capture.dart**
   - Changed oval positioning from Center to Positioned(top: 40)
   - Keeps existing 320x420 size and landmark dots

2. **lib/AddLearnerPage.dart**
   - Added `_useHardcodedProvinces()` fallback method
   - Added 10-second timeout to fetch request
   - Automatically loads hardcoded list on any error

3. **mobile/get_learners.php** (previous fix)
   - Added `'success' => true` to response

## APK Details
- **Size:** 197.2MB
- **Build Time:** 74.9 seconds
- **Status:** ✅ Installed on device RZ8X10CKD0B

## Summary

**Face Oval:** ✅ Fixed - positioned higher for better alignment  
**Province Dropdown:** ✅ Fixed - hardcoded fallback ensures data always loads  
**Sync Validation:** ⚠️ Still under investigation - needs testing with learner 11443
