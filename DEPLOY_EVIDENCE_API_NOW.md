# Deploy Evidence API - Action Required

## 🎯 What Changed

Created **NEW API** `mobile/save_clocking_evidence.php` that saves evidence **DIRECTLY** to MySQL when online (no sync needed).

**`clockin.php` and `clockout.php` are UNCHANGED** ✅

---

## 📋 Deployment Steps

### **Step 1: Upload API File**

Upload this file to your server:
```
LOCAL:  c:\projects\rlmss\mobile\save_clocking_evidence.php
SERVER: your-domain.com/mobile/save_clocking_evidence.php
```

### **Step 2: Create Server Folders**

SSH into your server and run:
```bash
cd /path/to/your/project/clocking/
mkdir -p signatures
mkdir -p face_photos
chmod 755 signatures
chmod 755 face_photos
```

Or via FTP/cPanel:
- Create folder: `clocking/signatures/`
- Create folder: `clocking/face_photos/`
- Set permissions to `755` for both

### **Step 3: Build APK**

```powershell
cd c:\projects\rlmss
.\fix_gradle_and_build.bat
```

**IMPORTANT:** Restart computer first if Gradle file locks still exist!

### **Step 4: Install APK**

```powershell
adb install -r android\app\build\outputs\apk\release\app-release.apk
```

### **Step 5: Test**

1. **Online Clock-In:**
   - Clock in with face verification + signature
   - Check server → verify files saved:
     - `clocking/signatures/learner{ID}_clock_in_{timestamp}.png`
     - `clocking/face_photos/learner{ID}_clock_in_{timestamp}.jpg`
   - Check MySQL → verify record in `learner_clocking_evidence` table

2. **Online Clock-Out:**
   - Clock out with face verification + signature
   - Verify same record updated (no duplicates)

3. **Offline Mode:**
   - Turn off internet
   - Clock in/out
   - Verify saves to phone SQLite
   - Turn on internet
   - Verify syncs to server

---

## 🔍 Verify Implementation

### Check API Exists:
```bash
curl https://your-domain.com/mobile/save_clocking_evidence.php
```

Should return:
```json
{"success":false,"message":"Method not allowed"}
```

### Check Folders:
```bash
ls -la clocking/signatures/
ls -la clocking/face_photos/
```

Should show folders with 755 permissions.

### Check Database:
```sql
SELECT * FROM learner_clocking_evidence 
WHERE clock_date = CURDATE() 
LIMIT 5;
```

After testing, should show records with signatures and photos.

---

## ✅ Benefits

1. **Online users:** Evidence saves **immediately** to MySQL + files (no sync delay)
2. **Offline users:** Evidence saves to SQLite, syncs when reconnected
3. **No changes** to existing clock-in/out APIs
4. **No duplicates:** UNIQUE constraint prevents duplicate records
5. **Fallback:** If online save fails, automatically falls back to offline mode

---

## 📞 Support

If you see errors after deployment:

1. **Check PHP error log** on server
2. **Check folder permissions** (must be writable)
3. **Check MySQL table** exists: `learner_clocking_evidence`
4. **Check connectivity** on phone

Files uploaded:
- ✅ `mobile/save_clocking_evidence.php`

Files unchanged:
- ✅ `mobile/clocking/clockin.php`
- ✅ `mobile/clocking/clockout.php`
- ✅ `mobile/sync_clocking_evidence.php`

---

**Ready to deploy!** 🚀
