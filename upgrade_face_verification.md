# Quick Upgrade Guide: Face Verification to Enhanced Version

## 🎯 What You Have

**Current Files (Old)**:
- `mobile/verify_learner_face.php` - Basic verification
- `mobile/face_recognition_config.php` - Basic config

**New Files (Enhanced)**:
- `mobile/verify_learner_face_new.php` - Secure verification with lockout
- `mobile/face_recognition_config_new.php` - Enhanced config

---

## ✅ Recommendation: UPGRADE NOW

The new version is **significantly more secure** and prevents:
- Brute-force attacks
- Embedding tuning attacks
- NaN/Infinity exploits
- IP spoofing
- Information leakage

---

## 🚀 Quick Upgrade (PowerShell Commands)

### **Option A: Replace Old with New (Recommended)**

```powershell
# Navigate to project
cd c:\projects\rlmss

# Backup old files
Copy-Item mobile\verify_learner_face.php mobile\verify_learner_face.php.backup
Copy-Item mobile\face_recognition_config.php mobile\face_recognition_config.php.backup

# Replace with new versions
Copy-Item mobile\verify_learner_face_new.php mobile\verify_learner_face.php -Force
Copy-Item mobile\face_recognition_config_new.php mobile\face_recognition_config.php -Force

Write-Host "✅ Upgrade complete! Old files backed up with .backup extension"
```

### **Option B: Keep Both (Use New, Keep Old as Backup)**

No action needed - just update your mobile app to call:
- `mobile/verify_learner_face_new.php` (instead of old)

---

## ⚙️ Configuration Check

After upgrade, verify these settings in `face_recognition_config.php`:

```php
// Security settings
define('FACE_MATCH_THRESHOLD', 0.95);           // ✅ 95% threshold
define('FACE_MAX_FAILED_ATTEMPTS', 5);          // ✅ 5 attempts max
define('FACE_LOCKOUT_WINDOW_MINUTES', 10);      // ✅ 10 minute window
define('FACE_DEBUG_RESPONSE', false);           // ✅ FALSE in production!

// Quality requirements
define('MIN_ENROLLMENT_QUALITY', 0.6);          // ✅ 60% minimum
define('MIN_VERIFICATION_QUALITY', 0.5);        // ✅ 50% minimum

// Database column (check your schema!)
define('FACE_LOG_TIME_COLUMN', 'created_at');   // ⚠️ Verify this matches your table
```

---

## 🧪 Test After Upgrade

### **Test 1: Legitimate User (Should Pass)**
```json
POST /mobile/verify_learner_face.php
{
  "learner_id": 12345,
  "embedding": [0.1, 0.2, ... (your real embedding)],
  "quality_score": 0.85,
  "verification_type": "clock_in"
}

Expected Response:
{
  "success": true,
  "verified": true,
  "log_id": 456,
  "message": "Face verification successful"
}
```

### **Test 2: Low Quality (Should Reject)**
```json
POST /mobile/verify_learner_face.php
{
  "learner_id": 12345,
  "embedding": [0.1, 0.2, ...],
  "quality_score": 0.3,  // ⚠️ Too low!
  "verification_type": "clock_in"
}

Expected Response:
{
  "success": false,
  "verified": false,
  "error": true,
  "code": "quality_too_low",
  "message": "Quality score too low: 0.3 (minimum: 0.5)"
}
HTTP 400
```

### **Test 3: Missing Quality Score (Should Reject)**
```json
POST /mobile/verify_learner_face.php
{
  "learner_id": 12345,
  "embedding": [0.1, 0.2, ...],
  // ⚠️ quality_score missing!
  "verification_type": "clock_in"
}

Expected Response:
{
  "success": false,
  "verified": false,
  "error": true,
  "code": "quality_missing",
  "message": "quality_score is required"
}
HTTP 400
```

### **Test 4: Wrong Person (Should Fail + Count Toward Lockout)**
```json
POST /mobile/verify_learner_face.php
{
  "learner_id": 12345,
  "embedding": [0.9, 0.9, ... (different person)],
  "quality_score": 0.85,
  "verification_type": "clock_in"
}

Expected Response:
{
  "success": true,
  "verified": false,  // ✅ Correctly rejected
  "log_id": 457,
  "message": "Face verification failed"
}
```

### **Test 5: Lockout After 5 Failures**
```
Try wrong person 5 times in a row...

6th attempt:
{
  "success": false,
  "verified": false,
  "error": true,
  "code": "locked_out",
  "message": "Too many failed attempts. Try again later."
}
HTTP 429
```

---

## 📊 Key Differences in Response

### **OLD Response (Exposes Secrets)**
```json
{
  "success": true,
  "verified": false,
  "similarity_score": 0.684,      // ❌ Attacker sees score!
  "threshold": 0.95,               // ❌ Attacker sees threshold!
  "matched_camera": null,
  "message": "Face verification failed (score: 0.684 < 0.95)"
}
```

### **NEW Response (Secure)**
```json
{
  "success": true,
  "verified": false,
  "log_id": 458,
  "message": "Face verification failed"  // ✅ No details exposed
}
```

**Scores only shown if `FACE_DEBUG_RESPONSE = true` (development only)**

---

## 🔧 Mobile App Changes (if needed)

### **Old Code (Relied on Score)**
```dart
final response = await verifyFace(...);
if (response['verified'] == true) {
  // Success
} else {
  // Show score to user
  final score = response['similarity_score'];  // ❌ Not available now!
  print('Score: $score');
}
```

### **New Code (Just Use Verified Boolean)**
```dart
final response = await verifyFace(...);
if (response['verified'] == true) {
  // Success!
  showSuccess();
} else {
  // Failed - show generic message
  final message = response['message'] ?? 'Verification failed';
  showError(message);
  
  // Check for lockout
  if (response['code'] == 'locked_out') {
    showLockedOutDialog('Too many attempts. Wait 10 minutes.');
  }
}
```

---

## 🚨 IMPORTANT: Debug Mode

**NEVER enable debug mode in production!**

```php
// Development (shows scores for debugging)
define('FACE_DEBUG_RESPONSE', true);

// Production (hides scores for security)
define('FACE_DEBUG_RESPONSE', false);  // ✅ MUST BE FALSE!
```

---

## 📋 Pre-Deployment Checklist

Before going live:

- [ ] Backed up old files
- [ ] Replaced with new versions
- [ ] Verified `FACE_DEBUG_RESPONSE = false`
- [ ] Tested legitimate user (passes)
- [ ] Tested wrong person (fails)
- [ ] Tested lockout mechanism (works)
- [ ] Checked error logs (no PHP errors)
- [ ] Verified database `created_at` column exists
- [ ] Updated mobile app (if it relied on scores)
- [ ] Informed users about lockout policy

---

## 🔄 Rollback (If Needed)

```powershell
# Restore old files
Copy-Item mobile\verify_learner_face.php.backup mobile\verify_learner_face.php -Force
Copy-Item mobile\face_recognition_config.php.backup mobile\face_recognition_config.php -Force

Write-Host "✅ Rolled back to old version"
```

---

## 📞 Need Help?

**Check logs**:
```bash
# Linux
tail -f /var/log/apache2/error.log

# Windows
# Check: C:\xampp\apache\logs\error.log
```

**Common Issues**:

1. **"Locked out" on first attempt**
   - Check if learner already has 5 recent failures
   - Reset: `DELETE FROM learner_face_verification_log WHERE learner_id = 12345 AND passed = 0`

2. **"quality_missing" error**
   - Mobile app must send `quality_score` field (0.0 to 1.0)

3. **"created_at column not found"**
   - Update `FACE_LOG_TIME_COLUMN` in config to match your schema

---

## ✅ Summary

**Upgrade gives you**:
- 🛡️ Brute-force protection (lockout)
- 🔒 Attack resistance (hidden scores)
- ✅ Input validation (finite values, quality required)
- 🚨 Proper error handling (generic messages)
- 📊 Better logging (reusable function)

**Highly recommended for production use!** 🎯
