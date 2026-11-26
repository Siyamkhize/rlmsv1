# MTL Session Clock-In - Complete Final Specification

**Date:** 2026-11-16  
**Status:** ✅ READY FOR IMPLEMENTATION  
**Contract:** SessionVerificationContract.md

---

## Architecture Overview

```
┌─────────────────────┐         ┌──────────────────────┐
│   RLMSS App         │         │  MTL Intern APK      │
│   (Facilitator)     │         │  (Biometric Device)  │
│   YOUR APP          │         │  OTHER APP           │
└──────────┬──────────┘         └──────────┬───────────┘
           │                               │
           │  1. Facilitator clicks        │
           │     "Clock In" for learner    │
           │                               │
           │  2. Validate:                 │
           │     ✅ Geofence (50m)?        │
           │     ✅ Token valid?           │
           │     ✅ Online?                │
           │                               │
           │  3. If PASS → Send request    │
           ├──────────────────────────────>│
           │  POST /clock-in-request       │
           │  {learner_id, id_number,      │
           │   facilitator_token}          │
           │                               │
           │                               │  4. MTL Intern APK:
           │                               │     - Captures fingerprint
           │                               │     - Takes photo
           │                               │     - Records GPS
           │                               │     - Saves to local DB
           │                               │
           │  5. Response                  │
           │<──────────────────────────────┤
           │  {success: true/false}        │
           │                               │
           │  6. Update UI                 │
           │                               │
           │  If validation FAILS:         │
           │  ❌ Revoke token via backend  │
           │                               │
           └───────────────────────────────┘
```

---

## Complete Requirements

### 1. ✅ Geofencing: 50 Meters (Not 100m)

Use existing geofencing logic from `clock_in_page.dart`:

```dart
// From clock_in_page.dart line ~2010
final baseRadius = 50.0;
final maxAllowedRadius = 60.0;
final calculatedRadius = baseRadius + userAccuracy;
final effectiveRadius = calculatedRadius > maxAllowedRadius
    ? maxAllowedRadius
    : calculatedRadius;

if (distance > effectiveRadius) {
  // User outside geofence
  _showError('You are ${distance.toStringAsFixed(0)}m away. Must be within ${effectiveRadius.toStringAsFixed(0)}m');
  return false;
}
```

### 2. ✅ Send Both IDNumber and LearnerID

```dart
final clockInRequest = {
  'learner_id': learner['LearnerID'].toString(),
  'id_number': learner['IDnumber'].toString(), // ✅ Both IDs
  'name': learner['Name'].toString(),
  'surname': learner['Surname'].toString(),
  'facilitator_token': _sessionId,
  'facilitator_name': facilitatorName,
  'latitude': _currentPosition?.latitude.toString() ?? '0',
  'longitude': _currentPosition?.longitude.toString() ?? '0',
  'gps_accuracy': _currentGpsAccuracy?.toString() ?? '0',
  'class_id': widget.classID,
  'clock_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
};
```

### 3. ✅ Clock In + Clock Out Buttons

Each learner card shows:
- **Clock In** button (green) - visible if NOT clocked in
- **Clock Out** button (orange) - visible if clocked in
- Status indicators showing times

```dart
// In learner card
Row(
  children: [
    if (!hasClockIn)
      ElevatedButton.icon(
        onPressed: () => _clockInLearner(learner),
        icon: Icon(Icons.login),
        label: Text('Clock In'),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
      ),
    SizedBox(width: 8),
    if (hasClockIn && !hasClockOut)
      ElevatedButton.icon(
        onPressed: () => _clockOutLearner(learner),
        icon: Icon(Icons.logout),
        label: Text('Clock Out'),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
      ),
  ],
)
```

### 4. ✅ Sync Button (Top-Left of AppBar)

```dart
AppBar(
  leading: IconButton(
    icon: _isSyncing 
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(Icons.sync),
    onPressed: _isSyncing ? null : _syncAllLearnersToInternApp,
    tooltip: 'Sync all learners to MTL intern APK',
  ),
  title: const Text('MTL Session Clock-In'),
  ...
)
```

### 5. ✅ Always Send to MTL Intern APK (Online or Offline)

**YOUR APP NEVER STORES CLOCKING DATA LOCALLY**  
Everything goes to MTL Intern APK:

```dart
Future<void> _clockInLearner(dynamic learner) async {
  // Step 1: Validate
  if (!await _validateBeforeClocking(learner)) {
    return; // Validation failed
  }

  // Step 2: Verify facilitator session
  final facilitator = await _verifySessionWithServer();
  if (facilitator == null) {
    await _revokeTokenAndShowError('Session verification failed');
    return;
  }

  // Step 3: Send to MTL Intern APK (always, even offline)
  final response = await http.post(
    Uri.parse('http://mtl-intern-apk-ip:port/clock-in-request'),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $_sessionId',
    },
    body: jsonEncode({
      'learner_id': learner['LearnerID'].toString(),
      'id_number': learner['IDnumber'].toString(),
      'name': learner['Name'].toString(),
      'surname': learner['Surname'].toString(),
      'facilitator_token': _sessionId,
      'facilitator_name': facilitator['name'],
      'class_id': widget.classID,
      'latitude': _currentPosition?.latitude.toString() ?? '0',
      'longitude': _currentPosition?.longitude.toString() ?? '0',
      'gps_accuracy': _currentGpsAccuracy?.toString() ?? '0',
    }),
  );

  // Step 4: Handle response
  if (response.statusCode == 200) {
    final data = jsonDecode(response.body);
    if (data['success']) {
      _showSuccess('✅ Clock-in request sent successfully');
      // Update UI to show clocked in
      setState(() {
        clockInTimes[learner['LearnerID'].toString()] = data['clock_in_time'];
      });
    } else {
      _showError(data['message'] ?? 'Clock-in failed');
    }
  } else if (response.statusCode == 401) {
    await _revokeTokenAndShowError('Session expired');
  } else {
    _showError('Failed to communicate with MTL intern APK');
  }
}
```

### 6. ✅ Token Revocation on Failure

When validation fails, revoke token via backend:

```dart
Future<void> _revokeTokenAndShowError(String message) async {
  _showError(message);
  
  if (_sessionId == null) return;
  
  try {
    // Call backend to revoke token
    final response = await http.post(
      Uri.parse(AppConfig.revokeTokenUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_sessionId',
      },
      body: jsonEncode({
        'reason': 'validation_failed',
      }),
    );
    
    if (response.statusCode == 200) {
      debugPrint('[MTL_SESSION] ✅ Token revoked successfully');
    }
    
    // Clear local session
    setState(() {
      _sessionId = null;
      _sessionUser = null;
      _sessionError = 'Session revoked';
    });
    
    // Clear from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    
  } catch (e) {
    debugPrint('[MTL_SESSION] Error revoking token: $e');
  }
}
```

### 7. ✅ Validation Checks Before Clock-In

```dart
Future<bool> _validateBeforeClocking(dynamic learner) async {
  // 1. Check session exists
  if (_sessionId == null) {
    _showError('No active session. Please login.');
    return false;
  }

  // 2. Check online (required to reach MTL intern APK)
  if (!_isOnline) {
    _showError('Must be online to clock in/out');
    return false;
  }

  // 3. Check geofence (50m radius)
  if (!_isWithinRange) {
    _showError('Not within 50m of site');
    return false;
  }

  // 4. Check GPS accuracy
  if (_currentGpsAccuracy == null || _currentGpsAccuracy! > 20) {
    _showError('GPS accuracy too poor. Please wait...');
    return false;
  }

  return true;
}
```

---

## Sync Button Functionality

Sends all learners from the class to MTL intern APK:

```dart
Future<void> _syncAllLearnersToInternApp() async {
  if (_isSyncing) return;
  
  setState(() => _isSyncing = true);
  
  try {
    // Verify facilitator
    final facilitator = await _verifySessionWithServer();
    if (facilitator == null) {
      await _revokeTokenAndShowError('Session verification failed');
      return;
    }

    // Prepare all learners data
    final learnersData = widget.learners.map((learner) {
      final learnerId = learner['LearnerID'].toString();
      return {
        'learner_id': learnerId,
        'id_number': learner['IDnumber'].toString(),
        'name': learner['Name'].toString(),
        'surname': learner['Surname'].toString(),
        'clocked_in': clockInTimes.containsKey(learnerId),
        'clocked_out': clockOutTimes.containsKey(learnerId),
        'clock_in_time': clockInTimes[learnerId],
        'clock_out_time': clockOutTimes[learnerId],
      };
    }).toList();

    // Send to MTL intern APK
    final response = await http.post(
      Uri.parse('http://mtl-intern-apk-ip:port/sync-learners'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_sessionId',
      },
      body: jsonEncode({
        'facilitator_token': _sessionId,
        'facilitator_name': facilitator['name'],
        'facilitator_role': facilitator['role'],
        'class_id': widget.classID,
        'learners': learnersData,
        'total_learners': learnersData.length,
      }),
    );

    if (response.statusCode == 200) {
      _showSuccess('✅ Synced ${learnersData.length} learners to MTL intern APK');
    } else {
      _showError('Sync failed');
    }
    
  } catch (e) {
    debugPrint('[MTL_SESSION] Sync error: $e');
    _showError('Sync failed: $e');
  } finally {
    setState(() => _isSyncing = false);
  }
}
```

---

## UI Layout

### AppBar
```
┌──────────────────────────────────────────────┐
│ [🔄]  MTL Session Clock-In      [✅][☁️]    │
│ Sync                          Status  Online │
└──────────────────────────────────────────────┘
```

### Session Banner (if valid)
```
┌──────────────────────────────────────────────┐
│ ✅ MTL Session Active              [Refresh] │
│ User: Thabo Mokoena (Facilitator)            │
└──────────────────────────────────────────────┘
```

### Geofence Banner
```
┌──────────────────────────────────────────────┐
│ 📍 Within site boundary (50m)                │
└──────────────────────────────────────────────┘
```

### Learner Card Example
```
┌──────────────────────────────────────────────┐
│  [S]  Sipho Dlamini                          │
│       ID: 9512155432087                      │
│       Clock In: 08:30:00 ✅                  │
│       Clock Out: --:--:-- ⏳                 │
│                                              │
│       [Clock In 🟢]  [Clock Out 🟠]         │
└──────────────────────────────────────────────┘
```

---

## Backend Endpoints Needed

### 1. ✅ Already Created: `/mobile/verify_session.php`
```php
POST /mobile/verify_session.php
Authorization: Bearer <token>

Response:
{
  "valid": true,
  "user": {
    "id": "123",
    "name": "Thabo Mokoena",
    "role": "facilitator"
  }
}
```

### 2. ✅ Already Created: `/mobile/revoke_token.php`
```php
POST /mobile/revoke_token.php
Authorization: Bearer <token>
Body: { "reason": "validation_failed" }

Response:
{
  "success": true,
  "message": "Token revoked successfully",
  "reason": "validation_failed"
}
```

### 3. ⏳ TODO: MTL Intern APK Endpoints

The MTL intern APK needs to implement:

#### Clock-In Request
```
POST http://mtl-intern-apk-ip:port/clock-in-request
Authorization: Bearer <facilitator_token>

Body:
{
  "learner_id": "12345",
  "id_number": "9512155432087",
  "name": "Sipho",
  "surname": "Dlamini",
  "facilitator_token": "<token>",
  "facilitator_name": "Thabo Mokoena",
  "class_id": "CLS001",
  "latitude": "-26.1234",
  "longitude": "28.5678",
  "gps_accuracy": "5.2",
  "clock_date": "2026-11-16"
}

Response:
{
  "success": true,
  "clock_in_time": "08:30:00",
  "message": "Clock-in captured successfully"
}
```

#### Clock-Out Request
```
POST http://mtl-intern-apk-ip:port/clock-out-request
Authorization: Bearer <facilitator_token>

Body: (same as clock-in)

Response:
{
  "success": true,
  "clock_out_time": "16:30:00",
  "contact_time": "08:00",
  "message": "Clock-out captured successfully"
}
```

#### Sync Learners
```
POST http://mtl-intern-apk-ip:port/sync-learners
Authorization: Bearer <facilitator_token>

Body:
{
  "facilitator_token": "<token>",
  "facilitator_name": "Thabo Mokoena",
  "facilitator_role": "facilitator",
  "class_id": "CLS001",
  "learners": [
    {
      "learner_id": "12345",
      "id_number": "9512155432087",
      "name": "Sipho",
      "surname": "Dlamini",
      "clocked_in": true,
      "clocked_out": false,
      "clock_in_time": "08:30:00",
      "clock_out_time": null
    },
    ...
  ],
  "total_learners": 25
}

Response:
{
  "success": true,
  "synced_count": 25,
  "message": "All learners synced successfully"
}
```

---

## Configuration

Add MTL Intern APK endpoint to `lib/config.dart`:

```dart
// MTL Intern APK endpoints
static const String mtlInternApkBaseUrl = 'http://192.168.0.xxx:xxxx'; // Replace with actual IP
static String get mtlClockInRequestUrl => '$mtlInternApkBaseUrl/clock-in-request';
static String get mtlClockOutRequestUrl => '$mtlInternApkBaseUrl/clock-out-request';
static String get mtlSyncLearnersUrl => '$mtlInternApkBaseUrl/sync-learners';
```

---

## Error Handling

### 1. Validation Fails
```dart
if (!await _validateBeforeClocking(learner)) {
  // Don't revoke token - just show error
  _showError('Validation failed');
  return;
}
```

### 2. Session Verification Fails
```dart
if (facilitator == null) {
  // Revoke token and clear session
  await _revokeTokenAndShowError('Session verification failed');
  return;
}
```

### 3. MTL Intern APK Unreachable
```dart
catch (e) {
  _showError('Cannot reach MTL intern APK. Check connection.');
  // Don't revoke token - might be temporary network issue
}
```

### 4. MTL Intern APK Returns 401
```dart
if (response.statusCode == 401) {
  // Token expired or invalid - revoke it
  await _revokeTokenAndShowError('Session expired');
}
```

---

## Testing Checklist

### ✅ Session Tests
- [ ] Login creates auth_token
- [ ] Token appears in session banner
- [ ] User name/role displayed correctly
- [ ] Refresh button reloads session
- [ ] Invalid token shows error

### ✅ Geofence Tests (50m)
- [ ] Within 50m → allows clock-in
- [ ] 51-60m → allows with warning (accuracy buffer)
- [ ] Beyond 60m → blocks clock-in
- [ ] Shows distance in error message

### ✅ Clock-In Tests
- [ ] Validates before sending to intern APK
- [ ] Sends both learner_id and id_number
- [ ] Sends facilitator token and name
- [ ] Updates UI on success
- [ ] Shows error on failure

### ✅ Clock-Out Tests
- [ ] Only allows if clocked in
- [ ] Calculates contact time
- [ ] Updates UI with times

### ✅ Sync Tests
- [ ] Sends all learners to intern APK
- [ ] Includes facilitator details
- [ ] Shows success message
- [ ] Loading indicator during sync

### ✅ Token Revocation Tests
- [ ] Revokes on session verification failure
- [ ] Revokes on 401 from intern APK
- [ ] Clears local session data
- [ ] Shows appropriate error message

---

## Summary

Your RLMSS app is a **"remote control"** that:
1. ✅ Validates (50m geofence, token, online)
2. ✅ Sends requests to MTL Intern APK
3. ✅ MTL Intern APK does actual biometric capture
4. ✅ Your app updates UI based on response
5. ✅ If validation fails → revoke token

**No local clocking data storage** - everything goes through MTL Intern APK!

---

## Next Steps

1. Get MTL Intern APK IP address and port
2. Update `lib/config.dart` with endpoint URLs
3. Test with one learner first
4. Then test with full class sync
5. Monitor logs for any issues

---

**All backend endpoints created:** ✅  
**Documentation complete:** ✅  
**Ready for implementation:** ✅
