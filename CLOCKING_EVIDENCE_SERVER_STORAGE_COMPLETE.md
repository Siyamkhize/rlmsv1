# Clocking Evidence Server Storage - Complete

## ✅ Server Folders Created Successfully

The directory structure for storing clocking evidence images has been created in the `mobile/` directory on the server.

### Directory Structure

```
mobile/
├── clocking_evidence/
│   ├── index.html (security - prevents directory listing)
│   ├── signatures/
│   │   ├── index.html
│   │   └── signature_*.png (stored here)
│   └── face_photos/
│       ├── index.html
│       └── face_*.jpg (stored here)
```

### Server Paths

**Base Directory:** `c:\projects\rlmss\mobile\clocking_evidence\`

**Subdirectories:**
- **Signatures:** `mobile/clocking_evidence/signatures/`
- **Face Photos:** `mobile/clocking_evidence/face_photos/`

### Folder Permissions

- ✅ All folders created with `0755` permissions
- ✅ All folders are writable
- ✅ Security index.html files added to prevent directory browsing
- ✅ Write test successful

### Files Created

1. **`mobile/upload_clocking_evidence_images.php`**
   - Endpoint for uploading signature and face photo files
   - Validates file types (PNG for signatures, JPEG for photos)
   - Validates file sizes (2MB for signatures, 5MB for photos)
   - Requires authentication
   - Rate limited

2. **`mobile/setup_clocking_evidence_folders.php`**
   - One-time setup script
   - Creates folder structure
   - Verifies permissions
   - Adds security index files
   - Can be run again to verify setup

### Current Implementation Status

#### ✅ Complete
- [x] Folder structure created on server
- [x] Upload endpoint created
- [x] Security index files added
- [x] File validation logic implemented
- [x] Filenames stored in database

#### 🔄 Pending
- [ ] Flutter code to upload images after saving locally
- [ ] Test end-to-end flow
- [ ] Background sync for offline uploads

### How It Works Now

**Current Flow (Filename Only):**
```
1. Learner clocks in with face verification
2. Flutter saves images locally on device
   ├── Signature → /signatures/signature_21562_20240915_083045_in.png
   └── Face photo → /face_photos/face_21562_20240915_083045_in.jpg
3. Flutter sends FILENAMES to save_clocking_evidence.php
4. Database stores filenames only
5. ✅ Clock-in recorded
```

**Future Flow (With Server Upload):**
```
1. Learner clocks in with face verification
2. Flutter saves images locally on device
3. Flutter sends FILENAMES to save_clocking_evidence.php
4. Database stores filenames
5. ✅ Clock-in recorded
6. Flutter uploads images to upload_clocking_evidence_images.php
7. Server saves images in mobile/clocking_evidence/
8. ✅ Images available on server
```

### Next Steps to Enable Server Upload

#### 1. Update Flutter Code

Add image upload call after successful clock-in. Add this function to `backup_clock_in_page.dart`:

```dart
Future<bool> _uploadClockingImages({
  required String learnerId,
  required String signatureFilename,
  String? photoFilename,
  required String suffix,
}) async {
  try {
    // Read files from local storage
    final directory = await getApplicationDocumentsDirectory();
    
    // Prepare multipart request
    final url = AppConfig.buildUrl('upload_clocking_evidence_images.php');
    final request = http.MultipartRequest('POST', Uri.parse(url));
    
    // Add signature file
    final signaturePath = '${directory.path}/signatures/$signatureFilename';
    if (await File(signaturePath).exists()) {
      request.files.add(
        await http.MultipartFile.fromPath('signature', signaturePath)
      );
      request.fields['signature_filename'] = signatureFilename;
      request.fields['signature_suffix'] = suffix;
    }
    
    // Add face photo file (if exists)
    if (photoFilename != null) {
      final photoPath = '${directory.path}/face_photos/$photoFilename';
      if (await File(photoPath).exists()) {
        request.files.add(
          await http.MultipartFile.fromPath('face_photo', photoPath)
        );
        request.fields['photo_filename'] = photoFilename;
        request.fields['photo_suffix'] = suffix;
      }
    }
    
    request.fields['learner_id'] = learnerId;
    
    // Send request
    final response = await request.send();
    
    if (response.statusCode == 200) {
      print('[UPLOAD] ✅ Images uploaded successfully');
      return true;
    } else {
      print('[UPLOAD] ❌ Upload failed: ${response.statusCode}');
      return false;
    }
  } catch (e) {
    print('[UPLOAD] ⚠️ Upload error: $e');
    return false; // Don't fail clock-in if upload fails
  }
}
```

Then call it after successful clock-in:

```dart
// After clock-in success
if (isOnline) {
  // Upload images to server (non-blocking)
  _uploadClockingImages(
    learnerId: learnerId,
    signatureFilename: clockInSignatureFilename,
    photoFilename: _capturedFacePhotoFilename,
    suffix: 'in',
  ).catchError((e) {
    print('[UPLOAD] Background upload failed: $e');
    // Continue anyway - images are saved locally
  });
}
```

#### 2. Test the Upload

```bash
# Test upload endpoint manually
curl -X POST https://yoursite.com/mobile/upload_clocking_evidence_images.php \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -F "signature=@signature_test.png" \
  -F "face_photo=@face_test.jpg" \
  -F "learner_id=21562" \
  -F "signature_filename=signature_21562_20240915_083045_in.png" \
  -F "photo_filename=face_21562_20240915_083045_in.jpg"
```

#### 3. Add Background Sync (Optional)

For offline uploads, create a background job that:
1. Checks local images that haven't been uploaded
2. Uploads them when WiFi is available
3. Marks them as synced

### Security Considerations

✅ **Directory Listing Disabled:** index.html files prevent browsing
✅ **File Validation:** Only PNG/JPEG accepted with size limits
✅ **Authentication Required:** Bearer token required for uploads
✅ **Rate Limiting:** Applied to prevent abuse
✅ **Secure Permissions:** Folders set to 0755, files to 0644

### Storage Requirements

**Per Learner Per Day:**
- 2 signatures @ ~50 KB = 100 KB
- 2 face photos @ ~200 KB = 400 KB
- **Total: ~500 KB/day/learner**

**100 Learners × 30 Days:**
- **1.5 GB per month**

### Backup Recommendations

Add to your backup schedule:
```bash
# Backup clocking evidence images
tar -czf clocking_evidence_backup_$(date +%Y%m%d).tar.gz \
  mobile/clocking_evidence/signatures/ \
  mobile/clocking_evidence/face_photos/
```

### Troubleshooting

**Folders not writable?**
```bash
chmod -R 755 mobile/clocking_evidence/
```

**Need to recreate folders?**
Navigate to: `https://yoursite.com/mobile/setup_clocking_evidence_folders.php`

**Check if folders exist:**
```bash
ls -la mobile/clocking_evidence/
```

### Summary

✅ **Server folders created:** `mobile/clocking_evidence/signatures/` and `mobile/clocking_evidence/face_photos/`
✅ **Upload endpoint ready:** `mobile/upload_clocking_evidence_images.php`
✅ **Security implemented:** File validation, auth, rate limiting
✅ **Database stores filenames:** Fast queries, small payload
🔄 **Flutter upload pending:** Need to add HTTP multipart upload code

Images are currently saved locally on devices and filenames stored in database. To enable server storage, implement the Flutter upload function above.
