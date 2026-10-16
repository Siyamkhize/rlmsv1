# Location Sync & GPS Fixes
**Date:** October 15, 2026  
**Issues:** Location sync PHP errors + GPS not available on Signature+Geofence page

---

## Issue 1: Location Sync PHP Errors

### Problem
```
[LOCATION_SYNC] ❌ Error syncing provinces: FormatException: Unexpected character (at character 1)
<br />
^
```

### Root Cause
PHP files had `ini_set('display_errors', 1)` which outputs HTML error messages (`<br />` tags) instead of clean JSON, breaking the JSON parser in Flutter.

### Files Fixed
1. `mobile/fetch_provinces.php` - Changed `display_errors` from 1 to 0
2. `mobile/fetch_municipalities.php` - Changed `display_errors` from 1 to 0  
3. `mobile/sync_districts.php` - Fixed to use `connection.php` instead of `../db.php` + disabled error display
4. `mobile/sync_municipalities.php` - Fixed to use `connection.php` instead of `../db.php` + disabled error display

### Status
✅ PHP files fixed - BUT server returns 404

**ACTION REQUIRED:** Deploy mobile folder to server at:
```
http://192.168.0.84:8080/assessorReport2/mobile/
```

Currently getting 404 - folder not deployed on server.

---

## Issue 2: GPS Location Not Available

### Problem
Red banner at bottom of screen:
```
⚠️ GPS location not available. Please wait for GPS signal.
```

This blocks ALL clock-in/clock-out attempts.

### Root Cause
In `lib/signature_geofence_clock_in_page.dart`:

1. `_startLocationMonitoring()` is called in `initState()`
2. It calls `Geolocator.getCurrentPosition()` with 10-second timeout
3. If GPS acquisition fails/times out → catches error → sets `_isLoadingLocation = false`
4. **BUT** `_currentPosition` remains `null`
5. When user clicks Clock In → `_showSignatureDialog()` checks if `_currentPosition == null`
6. If null → shows error and blocks clock-in

**Why GPS might fail to acquire:**
- Device indoors (weak satellite signal)
- GPS cold start (first acquisition takes 30+ seconds)
- Location services disabled
- Permission issues
- Device in power-saving mode limiting GPS

### Solution Options

#### Option A: Increase Timeout & Show Status (RECOMMENDED)
Increase GPS timeout to 30 seconds and show loading indicator with retry option.

#### Option B: Allow Manual Override for Trusted Facilitators
Add an option for facilitators to override GPS requirement with password/fingerprint.

#### Option C: Fallback to Network Location
Use less accurate network-based location if GPS fails.

---

## Recommended Fix

Will implement Option A + C:
1. Increase GPS timeout from 10s to 30s
2. Show GPS acquisition status on the learner list screen
3. Add manual retry button if GPS fails
4. Fallback to network location (less accurate but better than nothing)
5. Show warning if using network location instead of GPS

---

## Testing Notes

**To test GPS acquisition:**
1. Go outside or near window (clear sky view)
2. Enable High Accuracy mode in Location settings
3. Wait 30-60 seconds on first GPS lock
4. Subsequent locks should be faster (5-10 seconds)

**GPS Acquisition Time:**
- Cold start (no recent GPS data): 30-60 seconds
- Warm start (recent GPS data): 5-15 seconds  
- Hot start (GPS recently used): 1-5 seconds

---

## Files to Update

1. `lib/signature_geofence_clock_in_page.dart`
   - Increase timeout to 30 seconds
   - Add network location fallback
   - Show GPS status indicator
   - Add manual retry button

---

## Next Steps

1. ✅ Fix PHP error display
2. ⏳ Deploy mobile folder to server
3. ⏳ Implement GPS improvements
4. ⏳ Test GPS acquisition outdoors
5. ⏳ Test clock-in with GPS lock
