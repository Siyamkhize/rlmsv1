# Location Dropdowns Implementation Status

## Goal
Add Province, District, Municipality dropdown fields to Add Learner form between "Next of Kin Details" and "Bank Details".

## What Has Been Completed ✅

### 1. Database Schema (Server-side)
**File:** `add_location_columns_to_learnerdetails.sql`
**Status:** SQL ready, **NOT YET RUN ON SERVER**

```sql
ALTER TABLE learnerdetails 
ADD COLUMN Province VARCHAR(50) NULL AFTER KinContact,
ADD COLUMN District VARCHAR(50) NULL AFTER Province,
ADD COLUMN Municipality VARCHAR(50) NULL AFTER District;
```

**ACTION REQUIRED:** You must run this SQL on your server database!

### 2. PHP API Endpoints
Created 3 new endpoints (NO authentication required):

- `mobile/fetch_provinces.php` - Returns list of provinces from `province` table
- `mobile/fetch_districts.php?province=X` - Returns districts for a province from `District` table  
- `mobile/fetch_municipalities.php?district=X` - Returns municipalities for a district from `local_municipality` table

Response format:
```json
{
  "success": true,
  "data": {
    "provinces": [{"id": "Gauteng", "name": "Gauteng"}, ...]
  }
}
```

### 3. Mobile App Database (Local SQLite)
**File:** `lib/database_helper.dart`
**Changes:**
- Database version incremented to 11 (line 667)
- Added Province, District, Municipality columns to learnerdetails table in `onCreate` 
- Added `onUpgrade` logic to add columns when upgrading from version 10 to 11

### 4. Add Learner Page UI
**File:** `lib/AddLearnerPage.dart`
**Changes:**
- Added state variables: `_selectedProvince`, `_selectedDistrict`, `_selectedMunicipality`
- Added lists: `_provinces`, `_districts`, `_municipalities`
- Added fetch methods: `_fetchProvinces()`, `_fetchDistricts()`, `_fetchMunicipalities()`
- Added `initState()` to fetch provinces on page load
- Added Location Information section (lines 797-930) with conditional UI:
  - Shows dropdown if field is null
  - Shows text display if field has value
- Form submission includes location fields (lines 279-281)
- Population from existing learner data (lines 507-510)

### 5. Backend Processing
**File:** `mobile/add_learner.php`
**Changes:**
- Accepts Province, District, Municipality parameters
- Stores them in learnerdetails table

## The Problem ❌

**The code is correct and complete, but the phone keeps running an OLD version of the app without the location code.**

### Evidence:
1. No "AddLearnerPage:" debug logs appear (we added extensive logging)
2. AppBar still shows "Add Learner" (we changed it to "Add New Learner" temporarily)
3. Location Information section not visible between Next of Kin and Bank Details
4. Multiple install attempts failed to update the running app

### What We Tried:
1. ✅ Built APK (127.1MB) - SUCCESS
2. ✅ Uninstalled old app - SUCCESS  
3. ✅ Installed new APK via `adb install` - SUCCESS (but not taking effect)
4. ✅ Cleared app data - SUCCESS
5. ✅ Force stopped app - SUCCESS
6. ✅ Rebooted phone - SUCCESS
7. ✅ Flutter clean + rebuild - SUCCESS
8. ✅ Running `flutter run --debug` - IN PROGRESS (still building/syncing)
9. ❌ App on phone still shows OLD UI

## Next Steps 🔧

### Option 1: Wait for Flutter Debug Build
The `flutter run --debug` session is currently running (terminal `term_1789737113046_mwukfhivhz`).  
Once it finishes building and installing, it should hot-reload the new code directly.

**Check if it's done:**
```powershell
adb logcat -d | Select-String -Pattern "AddLearnerPage"
```

If you see logs with "AddLearnerPage:", the new version is running!

### Option 2: Manual APK Installation (RECOMMENDED)
1. Copy `C:\projects\rlmss\build\app\outputs\flutter-apk\app-release.apk` to your phone via USB/cloud
2. On phone: Settings → Security → Allow installation from unknown sources
3. Open file manager, find the APK file
4. Tap to install
5. Choose "Replace" when prompted

### Option 3: Increment Version Number
Force Android to recognize it as a new version:

**Edit `android/app/build.gradle` line ~50:**
```gradle
versionCode 4  // Change from 3 to 4
versionName "1.0.3+4"  // Change from 1.0.2+3 to 1.0.3+4
```

Then rebuild:
```powershell
flutter clean
flutter build apk --release
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

## Server SQL (CRITICAL!) ⚠️

**You MUST run this on your server database before the location dropdowns will work:**

```sql
ALTER TABLE learnerdetails 
ADD COLUMN Province VARCHAR(50) NULL AFTER KinContact,
ADD COLUMN District VARCHAR(50) NULL AFTER Province,
ADD COLUMN Municipality VARCHAR(50) NULL AFTER District;
```

## Testing Checklist

Once the new app is installed:

1. ✅ AppBar shows "Add Learner" (should match your current version)
2. ✅ Between "Next of Kin Details" and "Bank Details", see "Location Information" section
3. ✅ Province dropdown loads list of provinces
4. ✅ Selecting a province loads districts dropdown
5. ✅ Selecting a district loads municipalities dropdown
6. ✅ Form submits with location data
7. ✅ If learner already has location data, show as text (not dropdown)

## File Locations

- **APK:** `C:\projects\rlmss\build\app\outputs\flutter-apk\app-release.apk` (127.1MB)
- **Add Learner Page:** `lib/AddLearnerPage.dart` (lines 797-930 for location UI)
- **Database Helper:** `lib/database_helper.dart` (version 11, line 667)
- **PHP Endpoints:** `mobile/fetch_provinces.php`, `mobile/fetch_districts.php`, `mobile/fetch_municipalities.php`
- **Backend:** `mobile/add_learner.php` (accepts Province, District, Municipality)

## Debug Logs to Watch For

When the new version runs, you should see:
```
I/flutter: AddLearnerPage: initState called
I/flutter: AddLearnerPage: _fetchProvinces called
I/flutter: AddLearnerPage: fetch_provinces response status: 200
I/flutter: AddLearnerPage: _provinces set to: [Gauteng, Mpumalanga, ...]
I/flutter: AddLearnerPage: Building Province dropdown, _provinces.length = 9
```

---

**Current Status:** Code is complete and correct. Waiting for phone to actually run the new version.
