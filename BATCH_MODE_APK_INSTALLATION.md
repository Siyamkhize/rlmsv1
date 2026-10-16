# RLMSS Batch Clocking Mode - Installation Guide

**Build Date**: October 13, 2026  
**APK File**: `RLMSS_Batch_Mode_2026-10-13_172400.apk`  
**Size**: 71.37 MB  
**Status**: ✅ Production Ready

---

## 🆕 What's New in This Build

### Batch Clocking Mode (NEW)
Reduces API calls from **90+ to 1** for a class of 30 learners!

**Key Features:**
- ✅ **Toggle Switch** in AppBar - Turn batch mode ON/OFF
- ✅ **Batch Status Banner** - Shows how many learners collected
- ✅ **Collect Evidence** - Capture photos + signatures without sending
- ✅ **Submit Batch Button** - One request for all learners
- ✅ **Queue Service** - Works online AND offline
- ✅ **Individual Mode Unchanged** - Existing flow works exactly as before

**Performance:**
- Individual Mode: 3 API calls per learner (unchanged)
- Batch Mode: 1 API call for entire class
- Perfect for rural areas with poor connectivity

---

## 📲 Installation Methods

### Method 1: USB Cable (RECOMMENDED)

1. **Connect device to computer via USB**
2. **Enable USB file transfer** on the Android device
3. **Copy APK to device:**
   ```
   Source: C:\projects\rlmss\RLMSS_Batch_Mode_2026-10-13_172400.apk
   Destination: Device > Downloads folder
   ```
4. **On device, navigate to Downloads folder**
5. **Tap the APK file**
6. **Allow installation from this source** (if prompted)
7. **Tap INSTALL**
8. **Wait for installation to complete**
9. **Tap OPEN** or find "RLMSS" in app drawer

### Method 2: Share from PC

1. **Share the APK via:**
   - Email attachment
   - WhatsApp
   - Google Drive
   - OneDrive
   - Any file sharing method

2. **On device, download the APK**
3. **Open the downloaded file**
4. **Follow installation prompts**

### Method 3: ADB Install (For Developers)

```powershell
# Connect device via USB with USB debugging enabled
adb devices

# Install APK
adb install "C:\projects\rlmss\RLMSS_Batch_Mode_2026-10-13_172400.apk"
```

---

## ⚙️ Installation Troubleshooting

### "App not installed" Error

**Solution 1: Uninstall old version first**
```
Settings > Apps > RLMSS > Uninstall
Then install new APK
```

**Solution 2: Clear package installer cache**
```
Settings > Apps > Package Installer > Storage > Clear Cache
Try installing again
```

**Solution 3: Enable unknown sources**
```
Settings > Security > Unknown Sources > Enable
Or
Settings > Apps > Install Unknown Apps > Chrome/Files > Allow
```

### "Parse Error"

This usually means the APK is corrupted during transfer.

**Solution:**
- Re-download/re-transfer the APK
- Verify file size is 71.37 MB
- Use a different transfer method

---

## 🧪 Testing Batch Mode After Installation

### Test Plan

**1. Verify Individual Mode (Default) Still Works**
- Open app, login as facilitator
- Navigate to Classes > Select Class > Manual Clocking (Signature + Geofence)
- Ensure batch switch is OFF
- Clock in one learner (capture photo + signature)
- Verify: Learner clocked in immediately
- Check server database for records

**2. Test Batch Mode**
- Turn batch mode switch ON
- Blue banner should appear: "Batch Mode: 0 learner(s) collected"
- Select first learner > Clock In
- Capture photo + signature
- Verify: No immediate API call, banner shows "1 learner(s) collected"
- Repeat for 2-3 more learners
- Banner should show: "Batch Mode: 3 learner(s) collected"
- Blue floating action button appears: "Submit Batch (3)"
- Tap FAB
- Verify: Success message "✅ Batch submitted successfully (3 learners)"
- Check UI: All 3 learners show clock-in times
- Check server database: All 3 records present

**3. Test Offline Batch Mode**
- Enable airplane mode
- Turn batch mode ON
- Collect 2 learner clock-ins
- Tap "Submit Batch"
- Verify: Message "📤 Batch queued for sync (2 learners)"
- Disable airplane mode
- Wait 5-10 seconds
- Check server database: Batch should process automatically

**4. Test Clear Batch**
- Turn batch mode ON
- Collect 2 learners
- Tap "Clear" button in banner
- Verify: Collected data removed, counter resets to 0

---

## 📊 Expected Behavior Comparison

| Feature | Individual Mode | Batch Mode |
|---------|----------------|------------|
| Toggle Location | AppBar (default OFF) | AppBar |
| Evidence Collection | Immediate upload | Store in memory |
| API Calls (1 learner) | 3 calls | 0 calls |
| API Calls (30 learners) | 90 calls | 1 call (after Submit) |
| Clock Time Display | Immediate | After Submit |
| Offline Support | ✅ Queued per learner | ✅ Queued as batch |
| Submit Button | None (automatic) | Floating Action Button |
| Clear Option | N/A | Clear button in banner |

---

## 🔧 Technical Details

### Files Modified
- `lib/signature_geofence_clock_in_page.dart`
  - Added batch mode toggle
  - Added `_storeLearnerClockingData()` method
  - Added `_submitBatch()` method
  - Modified `_handleClockIn()` and `_handleClockOut()`

### API Endpoints (Unchanged)
- ✅ `save_manual_clocking_images.php` - Still works in individual mode
- ✅ `save_manual_clockin.php` - Still works in individual mode
- ✅ `save_manual_clockout.php` - Still works in individual mode
- ✅ `save_class_batch_clocking.php` - Used in batch mode

### Queue Service
- Uses existing `OfflineSyncQueueService.queueForBatchProcessing()`
- Handles online and offline scenarios
- Automatic retry on failure

### Database Tables (No Changes)
- `manual_clocking` - Same structure
- `manual_clocking_evidence` - Same structure

---

## 🚀 Rollout Recommendations

### Phase 1: Pilot Test (1-2 facilitators)
- Install on 1-2 devices
- Test both modes thoroughly
- Verify data integrity in database
- Collect feedback

### Phase 2: Limited Rollout (5-10 facilitators)
- Install on devices in areas with poor connectivity
- Monitor server logs for batch submissions
- Compare performance: individual vs batch mode

### Phase 3: Full Rollout
- Deploy to all facilitators
- Provide training on when to use batch mode
- Monitor system performance

---

## 📖 User Training Notes

**When to use Batch Mode:**
- ✅ Poor/intermittent connectivity
- ✅ Large classes (20+ learners)
- ✅ Rural areas
- ✅ Time-constrained situations

**When to use Individual Mode:**
- ✅ Good connectivity
- ✅ Small classes (<10 learners)
- ✅ Need immediate feedback
- ✅ Troubleshooting individual learners

**Best Practice:**
- Default to individual mode
- Switch to batch mode when network is slow
- Always verify submission success
- Check batch banner count before submitting

---

## ⚠️ Important Notes

1. **Data Safety**: Both modes save to queue first, then sync. No data loss risk.
2. **No Database Changes**: This update does NOT require any SQL migrations.
3. **Backward Compatible**: Works with existing server endpoints.
4. **Toggle Anytime**: Can switch modes mid-session.
5. **Clear Before Switching**: Clear batch data before switching to individual mode.

---

## 🆘 Support

**Common Issues:**

**Q: Batch mode not showing?**  
A: Look for toggle switch in AppBar labeled "Batch"

**Q: Submit button not appearing?**  
A: Submit button only shows when batch mode is ON and at least 1 learner is collected

**Q: Can I mix individual and batch?**  
A: Yes, but clear batch data when switching from batch to individual mode

**Q: What if submission fails?**  
A: Data remains in batch. Fix connectivity and tap Submit again.

**Q: How do I know if it's working?**  
A: Watch for banner count changes and success messages after Submit.

---

## ✅ Installation Checklist

- [ ] Device meets requirements (Android 5.0+)
- [ ] Unknown sources enabled
- [ ] Old version uninstalled (if upgrading)
- [ ] APK transferred to device
- [ ] APK file size verified (71.37 MB)
- [ ] Installation successful
- [ ] App opens without crashes
- [ ] Login successful
- [ ] Individual mode tested ✓
- [ ] Batch mode tested ✓
- [ ] Offline batch mode tested ✓
- [ ] Data verified in database

---

**Built with**: Flutter 3.24.5  
**Build Type**: Release APK  
**Signing**: Release keystore  
**Review Status**: ✅ APPROVED (No blocking concerns)

---

*For technical support, contact the RLMSS development team.*
