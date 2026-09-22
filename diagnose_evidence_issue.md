# Evidence Table Not Populating - Diagnosis Guide

## Problem
The `learner_clocking_evidence` table exists but has **0 records** despite successful clock-ins.

## Root Cause
The mobile app's evidence-saving code is failing silently because errors are caught and marked as "non-critical".

Location: `lib/backup_clock_in_page.dart` around line 1960:
```dart
} catch (e) {
  print('[BACKUP] ⚠️ Error saving evidence (non-critical): $e');
  // Don't fail the clock-in if evidence saving fails
}
```

## Steps to Diagnose

### 1. Check Mobile App Logs
```bash
adb logcat | grep -i "BACKUP\|evidence\|save_clocking_evidence"
```

Look for errors like:
- `ERROR saving evidence to server:`
- `HTTP 400`, `HTTP 500`
- JSON parsing errors
- Network timeouts

### 2. Test the Endpoint Manually

Create `test_manual_evidence.php`:
```php
<?php
require __DIR__ . '/mobile/connection.php';

// Test data
$learner_id = 11443;
$clock_date = date('Y-m-d');
$event_type = 'clock_in';
$signature = 'data:image/png;base64,TEST123';
$latitude = -26.205231;
$longitude = 27.987651;
$accuracy = 15.5;
$verification_method = 'face';
$timestamp = date('Y-m-d H:i:s');

// Insert test record directly
$stmt = $conn->prepare("
    INSERT INTO learner_clocking_evidence (
        LearnerID,
        clock_date,
        clock_in_signature,
        clock_in_latitude,
        clock_in_longitude,
        clock_in_accuracy,
        clock_in_verification_method,
        clock_in_timestamp,
        created_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, NOW())
");

$stmt->bind_param(
    'issddss',
    $learner_id,
    $clock_date,
    $signature,
    $latitude,
    $longitude,
    $accuracy,
    $verification_method,
    $timestamp
);

if ($stmt->execute()) {
    echo "✅ Test record inserted successfully\n";
    echo "Record ID: " . $stmt->insert_id . "\n";
} else {
    echo "❌ Failed to insert: " . $stmt->error . "\n";
}

$stmt->close();

// Verify
$count = $conn->query("SELECT COUNT(*) as count FROM learner_clocking_evidence")->fetch_assoc()['count'];
echo "\nTotal records in table: $count\n";
?>
```

Run: `php test_manual_evidence.php`

### 3. Common Issues

#### Issue A: Photo/Signature Data Too Large
**Symptom:** Timeout or 413 Request Entity Too Large

**Check:**
```dart
print('[BACKUP] Photo captured: ${_capturedFacePhotoBase64 != null ? "YES (${_capturedFacePhotoBase64!.length} bytes)" : "NO"}');
```

**Solution:** The photo might be too large (>1MB base64). The endpoint has a 30-second timeout but might still fail.

#### Issue B: Missing Face Log ID
**Symptom:** NULL foreign key constraint violation

**Check:** Look for `clock_in_face_log_id` in the request. It might be NULL when using signatures instead of face verification.

**Solution:** The FK constraint allows NULL, so this shouldn't be the issue.

#### Issue C: Network Connectivity
**Symptom:** Request never reaches server

**Check:**
```dart
final connectivityResult = await Connectivity().checkConnectivity();
final isOnline = connectivityResult != ConnectivityResult.none;
```

**Solution:** The app checks connectivity but might report "online" even if the server is unreachable.

#### Issue D: Wrong Base URL
**Symptom:** 404 or connection refused

**Check:**
```dart
final url = AppConfig.buildUrl('mobile/save_clocking_evidence.php');
print('[BACKUP] API URL: $url');
```

**Solution:** Verify the URL is correct in the logs.

## Quick Fix: Make Errors Visible

**Option 1:** Show error to user (recommended)
```dart
} catch (e) {
  print('[BACKUP] ❌ ERROR saving evidence to server: $e');
  // Show user warning (non-blocking)
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Warning: Evidence not saved. Please report to admin.'),
      duration: Duration(seconds: 5),
      backgroundColor: Colors.orange,
    ),
  );
}
```

**Option 2:** Retry on failure
```dart
} catch (e) {
  print('[BACKUP] ❌ ERROR saving evidence to server: $e');
  // Retry once
  try {
    await Future.delayed(Duration(seconds: 2));
    // ... repeat the request
  } catch (retryError) {
    print('[BACKUP] ❌ Retry also failed: $retryError');
  }
}
```

## Permanent Fix

### 1. Add Evidence Sync Service
Create a background service that syncs evidence from local SQLite to server MySQL when online.

### 2. Add Admin Dashboard
Show evidence status in admin panel:
- Clock-ins with evidence ✅
- Clock-ins WITHOUT evidence ⚠️
- Failed evidence uploads ❌

### 3. Make Evidence Mandatory
If evidence is critical, fail the clock-in if evidence can't be saved:
```dart
} catch (e) {
  print('[BACKUP] ❌ ERROR saving evidence: $e');
  throw Exception('Failed to save evidence. Clock-in aborted.');
}
```

## Next Steps

1. **Install APK on phone**
2. **Clock in while watching logs**: `adb logcat | grep BACKUP`
3. **Look for the error** in the `save_clocking_evidence` catch block
4. **Report the exact error message** so we can fix it
