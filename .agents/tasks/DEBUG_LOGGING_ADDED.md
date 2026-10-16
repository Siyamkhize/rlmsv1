# Document Check Debug Logging - Implementation Complete

**Date:** 2026-10-15  
**Device:** RZ8X306F7TZ  
**APK Version:** 71.4MB (Release build with debug logging)

## Summary

Added comprehensive debug logging to the document validation process to diagnose why document checks are failing during the clock-in workflow.

## Changes Made

### File Modified
- `lib/mixins/learner_clockin_gates_mixin.dart`
  - Enhanced `getDetailedDocumentStatusesForClockIn()` method with detailed logging

### Debug Logging Added

The document check method now logs:

1. **Start of check**: Learner ID being checked
2. **Network connectivity**: Whether network is available
3. **Authentication**: Whether auth token is present (value hidden for security)
4. **Request details**: 
   - Full URL being called
   - Request body (learner_id parameter)
5. **Response details**:
   - HTTP status code
   - Response body length
   - Full response body
6. **JSON parsing**:
   - Decoded JSON structure type
   - Success field value
   - Error messages if present
7. **Document map**:
   - All document keys returned from server
   - Required documents list
8. **Per-document validation**:
   - Each required document name (original and normalized)
   - Whether document was found in response
   - Document status (Approved/Pending/Declined/Not Uploaded)
   - Rejection reason if declined
9. **Final result**:
   - Count of problem documents
   - Whether all documents approved
10. **Exceptions**: Full exception message and stack trace

### Log Format

All logs are prefixed with `[CLOCKIN_GATES]` for easy filtering:

```
[CLOCKIN_GATES] ===== Starting document check for learner: L12345 =====
[CLOCKIN_GATES] Auth token present: true
[CLOCKIN_GATES] Request URL: http://192.168.0.84:8080/assessorReport2/mobile/get_document_statuses.php
[CLOCKIN_GATES] Response status: 200
[CLOCKIN_GATES] Response body: {"success":true,"documents":{...}}
[CLOCKIN_GATES] Checking required doc: "ID Document" (normalized: "id document")
[CLOCKIN_GATES]   ✓ Found match: id document -> {status: Approved}
[CLOCKIN_GATES] All approved: true
[CLOCKIN_GATES] ===== Document check complete =====
```

## How to View Logs

### Method 1: Real-time Logs (Connected Device)

```powershell
# Filter for document check logs only
adb -s RZ8X306F7TZ logcat | Select-String "CLOCKIN_GATES"

# Or filter for Flutter logs (includes all debug prints)
adb -s RZ8X306F7TZ logcat | Select-String "flutter"
```

### Method 2: Save Logs to File

```powershell
# Capture to file
adb -s RZ8X306F7TZ logcat -d > c:\temp\clockin_logs.txt

# Then search for [CLOCKIN_GATES] in the file
```

### Method 3: Clear Old Logs First

```powershell
# Clear previous logs
adb -s RZ8X306F7TZ logcat -c

# Start app and test clock-in workflow
# Then capture fresh logs
adb -s RZ8X306F7TZ logcat -d | Select-String "CLOCKIN_GATES" > c:\temp\document_check.txt
```

## Testing Steps

1. **Open the app** on device RZ8X306F7TZ
2. **Start monitoring logs** in another terminal:
   ```powershell
   adb -s RZ8X306F7TZ logcat | Select-String "CLOCKIN_GATES"
   ```
3. **Navigate to clock-in page** (Signature + Geofence + Document Check)
4. **Attempt clock-in** - document check will run automatically
5. **Watch logs** appear in real-time showing:
   - API request details
   - Server response
   - Document validation logic
   - Final decision

## What to Look For

### If Documents Fail to Pass

Check the logs for:

1. **Network issues**: 
   - `No network connectivity` message
   - HTTP status != 200

2. **Authentication problems**:
   - `Auth token present: false`
   - Response body containing "Authorization required"

3. **API errors**:
   - `API returned success=false`
   - Error message from server

4. **Document not found**:
   - `Not found - marking as "Not Uploaded"`
   - Check if document names match exactly (case-insensitive)

5. **Document not approved**:
   - `Status: Pending` or `Status: Declined`
   - Rejection reason if declined

6. **JSON parsing errors**:
   - `EXCEPTION in document check`
   - Stack trace showing where parsing failed

## Expected Successful Flow

```
[CLOCKIN_GATES] ===== Starting document check for learner: L12345 =====
[CLOCKIN_GATES] Auth token present: true
[CLOCKIN_GATES] Request URL: http://192.168.0.84:8080/.../get_document_statuses.php
[CLOCKIN_GATES] Request body: learner_id=L12345
[CLOCKIN_GATES] Response status: 200
[CLOCKIN_GATES] Response body: {"success":true,"documents":{"id document":{...},...}}
[CLOCKIN_GATES] Decoded success field: true
[CLOCKIN_GATES] Documents map keys: [id document, proof of residence, bank statement]
[CLOCKIN_GATES] Required documents: [ID Document, Proof of Residence, Bank Statement]
[CLOCKIN_GATES] Checking required doc: "ID Document" (normalized: "id document")
[CLOCKIN_GATES]   ✓ Found match: id document -> {status: Approved, ...}
[CLOCKIN_GATES]   ✓ Approved
[CLOCKIN_GATES] Checking required doc: "Proof of Residence" (normalized: "proof of residence")
[CLOCKIN_GATES]   ✓ Found match: proof of residence -> {status: Approved, ...}
[CLOCKIN_GATES]   ✓ Approved
[CLOCKIN_GATES] Checking required doc: "Bank Statement" (normalized: "bank statement")
[CLOCKIN_GATES]   ✓ Found match: bank statement -> {status: Approved, ...}
[CLOCKIN_GATES]   ✓ Approved
[CLOCKIN_GATES] Problem docs count: 0
[CLOCKIN_GATES] All approved: true
[CLOCKIN_GATES] ===== Document check complete =====
```

## Next Steps

1. **Run the app** on device RZ8X306F7TZ
2. **Test the clock-in workflow** with document check
3. **Capture the logs** using one of the methods above
4. **Share the logs** showing what happens during document validation
5. **Diagnose the issue** based on the detailed logging output

The logs will reveal exactly where and why the document check is failing.
