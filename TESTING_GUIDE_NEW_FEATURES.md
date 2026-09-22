# Testing Guide - New Features

## 📱 Testing on Your Phone

**APK Installed:** ✅ September 15, 2026  
**Version:** 126.2 MB Release APK  
**Server:** http://192.168.0.84:8080

---

## Pre-Test Checklist

Before testing, ensure:

- [ ] Phone is on same Wi-Fi network as PC (192.168.0.84)
- [ ] PC server is running on port 8080
- [ ] Phone has internet/Wi-Fi enabled
- [ ] App has all permissions granted (Location, Storage, Camera)
- [ ] You have test login credentials ready

---

## Test 1: Backup Clock-In Access (Dashboard)

**Goal:** Verify dialog appears when clicking "Clock In"

### Steps:
1. Open the app on your phone
2. Login with your credentials
3. Select a class from the list
4. Look for "Clock In" button (with fingerprint icon)
5. **Tap "Clock In"**

### ✅ Expected Result:
- **Dialog should appear** with title: "Choose Clock-In Method"
- Two buttons should be visible:
  - **"Fingerprint Scanner"** (blue fingerprint icon)
  - **"Signature (Backup)"** (orange pen icon)
  - **"Cancel"** button

### ❌ If Dialog Doesn't Appear:
- The change didn't apply properly
- Try restarting the app
- Check if APK was installed correctly

---

## Test 2: Backup Mode Entry (From Dashboard)

**Goal:** Open backup clock-in page

### Steps:
1. Follow Test 1 steps 1-5
2. **Tap "Signature (Backup)"** button

### ✅ Expected Result:
- New page opens with orange header
- Title: "Backup Clock-In (Signature Mode)"
- Orange badge showing: "Using backup signature mode - no fingerprint scanner required"
- List of learners appears
- Search box at top

### ❌ If App Crashes:
- Note the error message
- Check phone logs
- Report back the error

---

## Test 3: Backup Mode Entry (From Clock-In Page)

**Goal:** Switch to backup mode from fingerprint page

### Steps:
1. From dashboard, tap "Clock In"
2. Select "Fingerprint Scanner"
3. Normal clock-in page opens
4. **Look at top-right corner** of screen
5. Should see multiple icons: sync, documents, download, refresh, info, **and orange pen icon**
6. **Tap the orange pen icon** (last one)

### ✅ Expected Result:
- Switches to backup clock-in page (signature mode)
- Orange header appears
- Learner list preserved
- No data loss

---

## Test 4: Signature Capture Flow

**Goal:** Test full signature-based clock-in

### Steps:
1. Open backup mode (either method)
2. Search for a test learner
3. **Tap "Clock In"** button next to learner name
4. Follow the flow:
   - Profile check → Should pass or show skip option
   - Document check → Should verify required docs
   - ID confirmation → Enter learner's ID number
   - **Signature pad appears**
5. **Draw a signature** on the screen
6. **Tap "Save"** button
7. GPS verification runs
8. Clock-in should complete

### ✅ Expected Result:
- Each step completes successfully
- Signature captures smoothly
- GPS location verified
- Success message appears
- Learner shows "Clocked In" status
- Green check mark next to learner name

### ❌ Common Issues:
- **GPS fails:** Check location permissions
- **Signature doesn't capture:** Try drawing slower
- **Profile incomplete:** Can skip if allowed
- **Documents missing:** Upload required docs first

---

## Test 5: Signature Clock-Out

**Goal:** Clock out using signature

### Steps:
1. Find learner who is already clocked in
2. **Tap "Clock Out"** button
3. **Draw signature again**
4. GPS verification
5. Clock-out completes

### ✅ Expected Result:
- Only ONE signature required (at clock-out)
- Clock-out recorded
- Learner shows "Completed" status (green)
- Both clock-in and clock-out times saved

---

## Test 6: Offline Mode

**Goal:** Verify backup works offline

### Steps:
1. **Turn off Wi-Fi** on phone (or use airplane mode with GPS on)
2. Open backup clock-in mode
3. Search for learner
4. Clock in using signature
5. Should work offline
6. **Turn Wi-Fi back on**
7. Signatures should sync automatically

### ✅ Expected Result:
- Works completely offline
- Signatures saved locally
- Auto-syncs when online
- No data loss

---

## Test 7: Query Queuing (Background)

**Goal:** Verify multiple requests don't overwhelm server

### Steps:
1. With Wi-Fi ON and connected to local server
2. Open multiple pages quickly:
   - Learners list
   - Attendance page
   - POE page
   - Refresh each page multiple times rapidly
3. App should stay responsive

### ✅ Expected Result:
- App doesn't freeze
- Max 3 requests running at once
- Pages load smoothly
- No crashes or errors

---

## Test 8: Lazy Loading

**Goal:** Verify pagination works

### Steps:
1. Go to page with many learners (30+)
2. **Count initial learners loaded** - should be ~30
3. **Scroll down slowly** to bottom
4. Should see "Loading more..." indicator
5. More learners load automatically
6. Repeat scrolling

### ✅ Expected Result:
- Initial load shows ~30 items
- Smooth scrolling
- Loads more as you reach bottom
- No lag or freezing
- Eventually shows "No more items"

---

## Test 9: Local Server Connection

**Goal:** Verify app connects to local dev server

### Steps:
1. Check PC server is running on 192.168.0.84:8080
2. Check phone and PC on same Wi-Fi
3. Open app
4. Look at top of screen for connection indicator
5. Should show "Online" in green badge

### ✅ Expected Result:
- Shows "Online" status
- Can load data from server
- API calls successful
- No timeout errors

### ❌ If Shows "Offline":
- Check Wi-Fi connection
- Verify PC IP is 192.168.0.84
- Verify server running on port 8080
- Try pinging PC from phone's browser: http://192.168.0.84:8080

---

## Test 10: Signature Storage

**Goal:** Verify signatures are saved

### Steps:
1. Complete several clock-ins/outs using backup mode
2. Use ADB to check if signatures saved:
   ```bash
   adb shell ls -la /data/data/com.rlandc.assessorsreport/app_flutter/signatures/
   ```
3. Should see .png files named: `{learnerId}_{date}_in.png`

### ✅ Expected Result:
- PNG files created for each signature
- Named correctly with learner ID and date
- Files readable and not corrupted

---

## 📊 Test Results Template

Copy this and fill it out:

```
## Test Results - September 15, 2026

✅ Test 1 - Dashboard Dialog: [PASS/FAIL]
   Notes: _______________________________

✅ Test 2 - Backup Mode Entry (Dashboard): [PASS/FAIL]
   Notes: _______________________________

✅ Test 3 - Backup Mode Entry (Clock-In Page): [PASS/FAIL]
   Notes: _______________________________

✅ Test 4 - Signature Capture Flow: [PASS/FAIL]
   Notes: _______________________________

✅ Test 5 - Signature Clock-Out: [PASS/FAIL]
   Notes: _______________________________

✅ Test 6 - Offline Mode: [PASS/FAIL]
   Notes: _______________________________

✅ Test 7 - Query Queuing: [PASS/FAIL]
   Notes: _______________________________

✅ Test 8 - Lazy Loading: [PASS/FAIL]
   Notes: _______________________________

✅ Test 9 - Local Server Connection: [PASS/FAIL]
   Notes: _______________________________

✅ Test 10 - Signature Storage: [PASS/FAIL]
   Notes: _______________________________

## Overall Result: [PASS/FAIL]

## Issues Found:
1. _______________________________
2. _______________________________
3. _______________________________

## Additional Notes:
_______________________________
```

---

## 🔍 Quick Visual Verification

**What to Look For:**

1. **Dashboard "Clock In" button** → Should trigger dialog (not direct navigation)
2. **Dialog has 2 options** → Fingerprint + Signature
3. **Clock-in page top-right** → Should have orange pen icon
4. **Backup page header** → Orange color with badge
5. **Signature pad** → Smooth drawing capability
6. **Connection badge** → Green "Online" indicator
7. **Lazy loading** → "Loading more..." at bottom of lists

---

## ⚠️ Common Issues & Solutions

| Issue | Possible Cause | Solution |
|-------|---------------|----------|
| No dialog appears | Change didn't apply | Restart app, check APK version |
| Orange pen icon missing | Clock-in page not updated | Verify correct APK installed |
| Signature doesn't save | Permissions issue | Grant storage permissions |
| GPS fails | Location off | Enable location services |
| Shows "Offline" | Wrong network | Connect to same Wi-Fi as PC |
| App crashes | Memory issue | Clear app cache, restart phone |
| Slow loading | Server issue | Check PC server is running |

---

## 📞 What to Report Back

After testing, please tell me:

1. **Which tests passed?** (use template above)
2. **Which tests failed?** (specific details)
3. **Any error messages?** (screenshot if possible)
4. **Overall impression** - does it work as expected?
5. **Any unexpected behavior?**

---

## 🎯 Success Criteria

The update is successful if:

- ✅ Clock-In button shows method selection dialog
- ✅ Both entry methods work (dashboard + clock-in page)
- ✅ Signature capture works smoothly
- ✅ Can clock in/out using signatures
- ✅ Works offline with auto-sync
- ✅ App connects to local server (192.168.0.84)
- ✅ Lists load 30 items at a time
- ✅ No crashes or major bugs

---

**Now test it on your phone and let me know the results!** 📱✅
