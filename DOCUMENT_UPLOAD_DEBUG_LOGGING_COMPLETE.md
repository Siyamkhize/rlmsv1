# Document Upload Debug Logging - COMPLETE ✅

## Date: October 15, 2026
## Issue: Documents showing "uploaded local" but NOT reaching server

## Changes Made

### 1. Flutter App Enhanced Logging (`lib/services/learner_document_clockin_service.dart`)

**Added comprehensive logging that shows:**
- ✅ Network connectivity check
- ✅ Auth token presence
- ✅ Total documents in database
- ✅ Unsynced documents count and names
- ✅ File path validation
- ✅ File existence check
- ✅ File size
- ✅ HTTP request details (URL, fields, file info)
- ✅ **FULL SERVER RESPONSE** (status code, headers, body)
- ✅ Success/failure for each document
- ✅ JSON parsing details

**Added user-visible error messages:**
- ⚠️ No internet - shows orange snackbar
- ⚠️ Auth token missing - shows orange snackbar
- ❌ Upload failed - shows RED snackbar with actual error message
- ✅ Upload success - shows GREEN snackbar

### 2. PHP Server Enhanced Logging (`mobile/upload_learner_document.php`)

**Added error_log() calls for EVERY step:**
- ✅ Request timestamp
- ✅ All POST data (sanitized)
- ✅ All FILES data
- ✅ Request headers (including Authorization)
- ✅ Learner ID validation
- ✅ Input sanitization results
- ✅ Learner existence check
- ✅ File validation (size, type, MIME type)
- ✅ Directory existence and permissions
- ✅ File move operation
- ✅ Database prepare/execute status
- ✅ Inserted document_id
- ✅ Success/failure outcome
- ✅ Exception details and stack traces

## How to Debug Now

### Step 1: Check Flutter Logs (Logcat)
Run this command while the app is running:
```bash
adb logcat -s flutter
```

Look for lines starting with `[DOC_UPLOAD]`

### Step 2: Check PHP Error Log
On your server, check the PHP error log:
```bash
# Windows with XAMPP
tail -f C:\xampp\apache\logs\error.log

# Or check your specific error log location
```

Look for lines starting with `[DOC_UPLOAD]`

## What You'll See

### If Network is the Issue:
```
[DOC_UPLOAD] ❌ NO NETWORK CONNECTIVITY
```
User will see: "⚠️ No internet - Document saved locally, will sync when online"

### If Auth Token Missing:
```
[DOC_UPLOAD] Auth token present: NO
[DOC_UPLOAD] ❌ No auth token available
```
User will see: "⚠️ Auth token missing - Document saved locally only"

### If File Doesn't Exist:
```
[DOC_UPLOAD] ❌ File does not exist on disk
```
User will see: "❌ Upload failed: File not found: Qualifications"

### If Server Rejects File:
```
[DOC_UPLOAD] ========== SERVER RESPONSE ==========
[DOC_UPLOAD] Status code: 400
[DOC_UPLOAD] Response body: {"success":false,"error":"File too large"}
```
User will see: "❌ Upload failed: File too large"

### If Server Database Error:
```
PHP: [DOC_UPLOAD] ❌ Database execute failed: Duplicate entry...
```
User will see: "❌ Upload failed: Database execute failed..."

### If Upload Succeeds:
```
Flutter: [DOC_UPLOAD] ✅ SUCCESS: Qualifications uploaded and marked as synced
PHP: [DOC_UPLOAD] ✅ SUCCESS - Document uploaded successfully
```
User will see: "✅ 1 document(s) uploaded to server"

## Testing Instructions

1. **Clear app data** to force fresh upload attempt
2. **Connect to Wi-Fi** to ensure network is available
3. **Scan a document** (Qualifications or Proof of Residence)
4. **Watch BOTH logs simultaneously:**
   - Terminal 1: `adb logcat -s flutter`
   - Terminal 2: Watch PHP error log
5. **Read the error messages** - they now tell you EXACTLY what failed

## Expected Outcome

You will now see:
- Exact point of failure (network, auth, file, server, database)
- Error message from server if it rejects the upload
- Success confirmation when upload actually works
- User sees clear feedback instead of "uploaded local" lie

## Next Steps After Identifying Issue

### If "Auth token missing":
- Check if AppConfig.getAuthToken() returns null
- May need to re-login or regenerate token

### If "File not found":
- PDF path may be incorrect
- Scanner may not be saving to expected location

### If "Server error 400/500":
- Check PHP error log for detailed server-side error
- May be validation failure, database error, or permissions issue

### If "Network connectivity":
- User actually offline
- Server URL unreachable
- Firewall blocking request

## Files Modified

1. ✅ `lib/services/learner_document_clockin_service.dart` - Added Flutter logging + user feedback
2. ✅ `mobile/upload_learner_document.php` - Added PHP server logging
3. ✅ `DOCUMENT_UPLOAD_SILENT_FAILURE_FIX.md` - Root cause analysis
4. ✅ `DOCUMENT_UPLOAD_DEBUG_LOGGING_COMPLETE.md` - This document

## Status

**READY FOR TESTING** - Please:
1. Build new APK
2. Install on device
3. Clear app data
4. Try to upload documents
5. Share both Flutter logs AND PHP error logs with me
6. We'll see exactly where it's failing now! 🎯
