# Signature Geofence Navigation Fix - Double Pop Issue

**Date:** October 15, 2026  
**Issue:** After taking picture in SmartFramedCameraCapture, returns to clock_in_page.dart instead of signature_geofence_clock_in_page.dart  
**Root Cause:** Double Navigator.pop() - one from callback, one from camera widget  
**Status:** ✅ FIXED

## Problem Description

When you click "Clock In" in `signature_geofence_clock_in_page.dart`:
1. Opens SmartFramedCameraCapture for face photo
2. Take picture
3. **BUG**: Returns to `clock_in_page.dart` instead of `signature_geofence_clock_in_page.dart`

## Root Cause

### The Double Pop Bug

**In signature_geofence_clock_in_page.dart (Line ~929):**
```dart
onCapture: (file, bytes) {
  _learnerPhotoBytes[int.parse(learnerID)] = bytes;
  Navigator.pop(context, {'success': true, 'bytes': bytes});  // ❌ POP #1
},
```

**In smart_framed_camera_capture.dart (Line ~505):**
```dart
widget.onCapture(tempFile, watermarkedBytes);  // Calls the callback above
Navigator.of(context).pop();  // ❌ POP #2 (happens right after)
```

### What Happened

1. User on: **signature_geofence_clock_in_page**
2. Navigator.push → **SmartFramedCameraCapture**
3. Take photo → onCapture callback runs
4. **POP #1**: Navigator.pop from callback (line 929)
5. **POP #2**: Navigator.pop from camera widget (line 505)
6. Result: **Popped TWICE** - went back 2 pages instead of 1
7. Ended up on: **clock_in_page.dart** (the page before signature page)

### Navigation Stack Before Fix

```
[DashboardPage or ClockInPage]  ← Ends up here after DOUBLE POP!
  └─ [SignatureGeofenceClockInPage]  ← Should return here
       └─ [SmartFramedCameraCapture]  ← Takes photo here
```

## Solution

Remove the `Navigator.pop()` call from the `onCapture` callback. Let `SmartFramedCameraCapture` handle navigation internally.

### Changes Made

**File:** `lib/signature_geofence_clock_in_page.dart`

**Before (Clock-In - Line ~927-931):**
```dart
onCapture: (file, bytes) {
  _learnerPhotoBytes[int.parse(learnerID)] = bytes;
  Navigator.pop(context, {'success': true, 'bytes': bytes});  // ❌ REMOVED
},
```

**After (Clock-In):**
```dart
onCapture: (file, bytes) {
  _learnerPhotoBytes[int.parse(learnerID)] = bytes;
  // Don't call Navigator.pop here - SmartFramedCameraCapture handles it
},
```

**Before (Clock-Out - Line ~1048):**
```dart
onCapture: (file, bytes) {
  _learnerPhotoBytes[int.parse(learnerID)] = bytes;
  Navigator.pop(context, {'success': true, 'bytes': bytes});  // ❌ REMOVED
},
```

**After (Clock-Out):**
```dart
onCapture: (file, bytes) {
  _learnerPhotoBytes[int.parse(learnerID)] = bytes;
  // Don't call Navigator.pop here - SmartFramedCameraCapture handles it
},
```

**Also Updated Result Checking:**

**Before:**
```dart
if (faceResult?['success'] != true) {
  print('[SIGNATURE_GEO] Face capture failed or cancelled');
  return;
}
```

**After:**
```dart
// Check if camera was closed without capturing (user cancelled)
if (!_learnerPhotoBytes.containsKey(int.parse(learnerID))) {
  print('[SIGNATURE_GEO] Face capture failed or cancelled');
  return;
}
```

## Why This Works

Now when taking a photo:
1. onCapture callback stores the photo bytes in `_learnerPhotoBytes`
2. **NO pop from callback** - just stores data
3. SmartFramedCameraCapture calls `Navigator.pop()` once (line 505)
4. **Returns to signature_geofence_clock_in_page** (correct!)
5. Flow continues: signature dialog → clock-in/clock-out

### Navigation Stack After Fix

```
[DashboardPage or ClockInPage]
  └─ [SignatureGeofenceClockInPage]  ← Returns here after SINGLE POP ✓
       └─ [SmartFramedCameraCapture]  ← Takes photo here
```

## Testing

After rebuild:

1. **Open signature_geofence_clock_in_page** from dashboard or clock_in_page
2. **Click "Clock In"** on a learner
3. **Take face photo** in SmartFramedCameraCapture
4. **Expected:** Returns to signature_geofence_clock_in_page ✓
5. **Capture signature**
6. **Complete clock-in** (stays on signature page)

## Related Fixes

This fix also applies to:
- ✅ Clock-out flow (same double pop issue)
- ✅ Both online and offline clock-in modes
- ✅ Batch mode and individual mode

## Files Modified

1. `lib/signature_geofence_clock_in_page.dart`
   - Line ~927-931: Removed Navigator.pop from clock-in onCapture
   - Line ~934-937: Updated result checking
   - Line ~1047-1050: Removed Navigator.pop from clock-out onCapture
   - Line ~1053-1056: Updated result checking

## Summary

**Problem:** Double `Navigator.pop()` caused navigation to go back 2 pages  
**Solution:** Removed redundant `Navigator.pop()` from callback  
**Result:** User stays on `signature_geofence_clock_in_page.dart` through entire clock-in flow  

---

**Status:** ✅ Fixed - Ready to rebuild and test
