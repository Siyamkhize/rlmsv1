# Manual Clocking with Photo + Watermark - Implementation Summary

## ✅ Completed

### 1. Database Changes
- Updated `manual_clocking_evidence` table to store **filenames** (VARCHAR) instead of base64
- Fields: `signature_in`, `signature_out`, `face_in`, `face_out`

### 2. PHP Endpoints Created
- `mobile/setup_manual_clocking_folders.php` - Creates folder structure
- `mobile/save_manual_clocking_images.php` - Saves photos with watermarks
- `mobile/save_manual_clockin.php` - Updated to accept filenames
- `mobile/save_manual_clockout.php` - Updated to accept filenames
- `mobile/get_manual_clocking_status.php` - Fetches clocking records

### 3. Folder Structure
```
manual_clocking_evidence/
├── signatures/  (PNG signature images)
└── faces/       (JPG face photos with watermarks)
```

### 4. PHP Watermark Function
The `save_manual_clocking_images.php` endpoint adds:
- Frame border (blue, 8px thick)
- Watermark bar at bottom with:
  - "RLMSS Manual Clock-In" title
  - Learner ID
  - Timestamp (red, prominent)
- Corner timestamp (top-right)

### 5. Flutter Widget Created
- `lib/widgets/framed_camera_capture.dart` - Camera with frame overlay and watermark

### 6. Updated signature_geofence_clock_in_page.dart
- Added import for `framed_camera_capture.dart`
- Added state variables for captured photo
- Updated `_showSignatureDialog` to capture photo FIRST, then signature

## 🔧 TODO: Update Clock-In/Out Methods

You need to update the `_clockInOnline` and `_clockOutOnline` methods to:

1. **Upload images to server first**
2. **Get back filenames**
3. **Pass filenames to clock-in/out endpoints**

### Step-by-Step Implementation:

#### Update `_clockInOnline` method:

```dart
Future<void> _clockInOnline(String learnerID, String signaturePath) async {
  try {
    // Step 1: Prepare signature
    String signatureBase64 = '';
    try {
      final signatureImage = await _signatureController.toPngBytes();
      if (signatureImage != null) {
        signatureBase64 = base64Encode(signatureImage);
      }
    } catch (e) {
      print('[SIGNATURE_GEO] Signature generation failed: $e');
    }

    // Step 2: Upload images and get filenames
    final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    final uploadUrl = Uri.parse(AppConfig.buildUrl('save_manual_clocking_images.php'));
    
    final uploadPayload = {
      'learner_id': learnerID,
      'clock_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
      'type': 'in',
      'face_image': _capturedPhotoBytes != null ? base64Encode(_capturedPhotoBytes!) : null,
      'signature_image': signatureBase64,
      'timestamp': timestamp,
    };

    final uploadResponse = await http.post(
      uploadUrl,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(uploadPayload),
    ).timeout(const Duration(seconds: 30));

    final uploadResult = jsonDecode(uploadResponse.body);
    
    if (uploadResponse.statusCode != 200 || uploadResult['success'] != true) {
      throw Exception('Image upload failed: ${uploadResult['error']}');
    }

    // Get filenames from upload response
    final faceInFilename = uploadResult['files']['face_in'];
    final signatureInFilename = uploadResult['files']['signature_in'];

    // Step 3: Save clock-in with filenames
    final clockInUrl = Uri.parse(AppConfig.buildUrl('save_manual_clockin.php'));
    final clockInTime = DateFormat('HH:mm:ss').format(DateTime.now());
    final currentDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final payload = {
      'learner_id': learnerID,
      'clock_date': currentDate,
      'clock_in_time': clockInTime,
      'signature_in': signatureInFilename,
      'face_in': faceInFilename,
      'latitude': _currentPosition?.latitude ?? 0.0,
      'longitude': _currentPosition?.longitude ?? 0.0,
      'accuracy': _currentGpsAccuracy ?? 999.0,
    };

    final response = await http.post(
      clockInUrl,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    ).timeout(const Duration(seconds: 30));

    final result = jsonDecode(response.body);

    if (response.statusCode == 200 && result['success'] == true) {
      setState(() {
        clockInTimes[learnerID] = result['clock_in_time'] ?? clockInTime;
        clockOutTimes[learnerID] = '';
        contactTimes[learnerID] = '';
      });
      
      // Clear captured photo
      setState(() {
        _capturedPhotoFile = null;
        _capturedPhotoBytes = null;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'] ?? 'Clock-in successful')),
      );
    } else {
      throw Exception(result['error'] ?? 'Server error');
    }
  } catch (e) {
    print('[SIGNATURE_GEO] Online clock-in failed: $e');
    throw Exception('Online clock-in failed: $e');
  }
}
```

#### Update `_clockOutOnline` method similarly:

Change `'type': 'in'` to `'type': 'out'`
Change `face_in` and `signature_in` to `face_out` and `signature_out`
Use `save_manual_clockout.php` endpoint

## 📋 Deployment Checklist

### 1. Deploy Database Table
```bash
php deploy_manual_clocking_evidence.php
```

### 2. Create Folders
```bash
php mobile/setup_manual_clocking_folders.php
```

### 3. Test Image Upload Endpoint
```bash
curl -X POST https://rlms.rlms.co.za/mobile/save_manual_clocking_images.php \
  -H "Content-Type: application/json" \
  -d '{"learner_id":12345,"clock_date":"2026-10-02","type":"in","face_image":"test_base64","signature_image":"test_base64","timestamp":"2026-10-02 08:30:00"}'
```

### 4. Verify Folders Created
Check that these folders exist on server:
- `manual_clocking_evidence/signatures/`
- `manual_clocking_evidence/faces/`

### 5. Build and Install APK
```bash
flutter build apk --release
adb -s RZ8X10CKD0B install -r "build\app\outputs\flutter-apk\app-release.apk"
```

## 🎯 Complete Flow

1. User taps clock-in button
2. **Geofencing check** (must be within 50m)
3. **Camera opens** with frame overlay
4. User captures face photo
5. **Watermark added automatically** (timestamp, learner ID, date)
6. **Signature dialog shows**
7. User signs
8. **Images uploaded** to server (get filenames back)
9. **Clock-in saved** with image filenames
10. Success message shown

## 📸 Watermark Details

The watermark includes:
- Blue frame border (8px)
- Black semi-transparent bar at bottom containing:
  - "RLMSS Manual Clock-In" (white text)
  - "Learner ID: XXXXX" (white text)
  - Full timestamp in red (prominent)
- Corner timestamp (top-right, white text)

## 🔒 Security Features

- ✅ Strict 50m geofencing
- ✅ GPS coordinates logged
- ✅ Photo with tamper-evident watermark
- ✅ Signature capture
- ✅ Timestamps on everything
- ✅ Unique constraint prevents duplicates

## ⚠️ Important Notes

- Images are saved as **files on server**, not in database
- Database only stores **filenames**
- Watermarks are added **server-side** using GD library
- Front camera preferred for face photos
- All images auto-deleted if learner record deleted (CASCADE)

## 📱 Testing Steps

1. Open Signature+Geofence clock-in page
2. Select a learner
3. Tap clock-in
4. Check geofencing validation
5. Capture face photo
6. Check photo shows frame and watermark preview
7. Provide signature
8. Verify success
9. Check server folders for saved files
10. Check database for filenames
