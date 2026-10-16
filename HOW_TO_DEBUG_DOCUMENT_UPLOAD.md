# How to Debug Document Upload - Step by Step

## ⚠️ The Problem
Documents showing "uploaded local" but NOT on server. Need to see EXACTLY where it's failing.

## ✅ What I Fixed
Added detailed logging to BOTH Flutter app AND PHP server so you can see:
- Where the upload fails (network, auth, file, server, database)
- Actual error messages instead of silent failures
- User sees clear feedback (success/failure with reason)

---

## 🔧 Option 1: Test Server Endpoint First (Recommended)

Before building new APK, let's verify the server endpoint works:

### Step 1: Run Test Script
```bash
cd C:\projects\rlmss
php test_document_upload.php
```

### Step 2: Check Output
You should see:
```
✅ SUCCESS: Document upload endpoint is working!
Document ID: 123
Filename: doc_xxxxx.pdf
```

If you see errors:
- `❌ CURL ERROR:` - Server unreachable or URL wrong
- `❌ FAILED: Database error` - Check database connection
- `❌ FAILED: File validation` - Check file permissions

### Step 3: Check PHP Error Log
Look for `[DOC_UPLOAD]` lines showing detailed progress

**If server test passes**, proceed to Option 2.
**If server test fails**, fix server issues first before building APK.

---

## 🔧 Option 2: Test From Mobile App

### Step 1: Build New APK
```bash
cd C:\projects\rlmss
flutter clean
flutter build apk --release
```

APK location: `build\app\outputs\flutter-apk\app-release.apk`

### Step 2: Install on Device
```bash
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

### Step 3: Clear App Data
```bash
adb shell pm clear com.example.rlmss
```

### Step 4: Start Watching Logs
**Open 2 terminals:**

**Terminal 1 - Flutter Logs:**
```bash
adb logcat -s flutter | findstr /C:"[DOC_UPLOAD]"
```

**Terminal 2 - PHP Error Logs:**
```bash
# On your server (Windows/XAMPP)
Get-Content C:\xampp\apache\logs\error.log -Wait | Select-String "[DOC_UPLOAD]"
```

### Step 5: Try to Upload Document
1. Open app
2. Login
3. Navigate to signature_geofence_clock_in_page
4. Select learner 6246 or 11443
5. Try to clock in (it will trigger document check)
6. Scan a document when prompted

### Step 6: Read the Logs

**Flutter log will show:**
```
[DOC_UPLOAD] ========================================
[DOC_UPLOAD] Starting sync for learner: 6246
[DOC_UPLOAD] ✓ Network connectivity OK
[DOC_UPLOAD] Auth token present: YES
[DOC_UPLOAD] Unsynced documents: 1
[DOC_UPLOAD]   - Qualifications (ID: 45)
[DOC_UPLOAD] ----------------------------------------
[DOC_UPLOAD] Processing: Qualifications
[DOC_UPLOAD] File path: /data/user/0/com.example.rlmss/...
[DOC_UPLOAD] File exists, size: 123456 bytes
[DOC_UPLOAD] Building multipart request...
[DOC_UPLOAD] Sending request...
[DOC_UPLOAD] ========== SERVER RESPONSE ==========
[DOC_UPLOAD] Status code: 200
[DOC_UPLOAD] Response body: {"success":true,...}
[DOC_UPLOAD] ✅ SUCCESS: Qualifications uploaded
```

**PHP log will show:**
```
[DOC_UPLOAD] ===== NEW UPLOAD REQUEST =====
[DOC_UPLOAD] POST data: {"learner_id":"6246",...}
[DOC_UPLOAD] FILES data: {"name":"doc_xxx.pdf",...}
[DOC_UPLOAD] ✓ learner_id validated: 6246
[DOC_UPLOAD] ✓ Inputs sanitized
[DOC_UPLOAD] ✓ Learner exists: 6246
[DOC_UPLOAD] ✓ File validation passed
[DOC_UPLOAD] ✓ File moved successfully
[DOC_UPLOAD] ✓ Inserted into database, document_id: 156
[DOC_UPLOAD] ✅ SUCCESS
```

---

## 🔍 Common Issues and Solutions

### Issue 1: No network connectivity
**Flutter shows:** `[DOC_UPLOAD] ❌ NO NETWORK CONNECTIVITY`
**Solution:** Device offline or server unreachable. Check Wi-Fi/server.

### Issue 2: No auth token
**Flutter shows:** `[DOC_UPLOAD] Auth token present: NO`
**Solution:** User needs to login again or token expired.

### Issue 3: File not found
**Flutter shows:** `[DOC_UPLOAD] ❌ File does not exist on disk`
**Solution:** Scanner not saving PDF correctly. Check scanner_pdf_resolver.dart.

### Issue 4: Server error 400
**Flutter shows:** `[DOC_UPLOAD] Status code: 400`
**PHP shows:** `[DOC_UPLOAD] ❌ File validation failed: File too large`
**Solution:** File > 5MB or wrong type. User needs to rescan.

### Issue 5: Database error
**PHP shows:** `[DOC_UPLOAD] ❌ Database execute failed: ...`
**Solution:** Check database connection, table structure, permissions.

### Issue 6: Directory permissions
**PHP shows:** `[DOC_UPLOAD] Directory writable: NO`
**Solution:** 
```bash
# On server
mkdir mobile/learner_documents
chmod 755 mobile/learner_documents
```

---

## 📱 What User Will See Now

### Before (Silent Failure):
- "✅ Qualifications scanned and saved"
- Document says "uploaded local"
- Clock-in still blocked with "Not Uploaded"
- User confused 😕

### After (Clear Feedback):
**If upload fails:**
- "❌ Upload failed: File too large"
- "❌ Upload failed: Server error 500"
- "⚠️ No internet - saved locally, will sync when online"

**If upload succeeds:**
- "✅ 1 document(s) uploaded to server"
- Clock-in proceeds normally
- User happy 😊

---

## 🎯 Quick Decision Tree

1. **Run `test_document_upload.php`**
   - ✅ Success → Build APK and test from mobile
   - ❌ Failed → Fix server issues first

2. **Install APK and watch logs**
   - Look for `[DOC_UPLOAD]` in both Flutter and PHP logs
   - Find the FIRST error message
   - Fix that specific issue

3. **Share logs with me**
   - Copy Flutter log section starting with `[DOC_UPLOAD] ========`
   - Copy PHP log section starting with `[DOC_UPLOAD] =====`
   - I'll tell you exactly what's wrong

---

## 📋 Files Changed

1. ✅ `lib/services/learner_document_clockin_service.dart` - Enhanced logging + user feedback
2. ✅ `mobile/upload_learner_document.php` - Detailed server logging
3. ✅ `test_document_upload.php` - Server endpoint test script
4. ✅ This guide

## Status: READY TO TEST 🚀
