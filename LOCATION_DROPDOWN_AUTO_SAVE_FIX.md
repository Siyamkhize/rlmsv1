# Location Dropdown & SchoolCompletion Auto-Save Fix

**Date:** 2026-10-15  
**Issue:** Province, District, Municipality, and SchoolCompletion fields not syncing to server immediately  
**Device:** RZ8X306F7TZ

## Problem

User reported that location fields (Province, District, Municipality) and SchoolCompletion were:
1. **Present in online MySQL database** ✓
2. **Present in SQLite database helper** ✓  
3. **Being fetched from endpoints** ✓
4. **Dropdown selections working** ✓
5. **BUT not being saved to server automatically** ❌

### Root Cause

When user selected dropdowns, the values were:
- Stored in `learnerData` object locally
- Displayed correctly in UI
- **But NOT sent to `update_learner.php` until user clicked "Update Data" button**

The validation code saw the values in `learnerData` (from local state), so it didn't flag them as missing - but the server never received them.

## Solution Implemented

### Auto-Save on Dropdown Change

Modified `lib/LearnerDetailsPage.dart` dropdown `onChanged` handler to:

**Automatically save these fields to server immediately when selected:**
- Province
- District  
- Municipality
- SchoolCompletion

### Code Change

In the `_buildDropdownField()` method's `onChanged` handler (around line 2082):

```dart
// CRITICAL FIX: Auto-save location fields and SchoolCompletion to server immediately
final autoSaveFields = {
  'Province',
  'District',
  'Municipality',
  'SchoolCompletion'
};
if (autoSaveFields.contains(fieldKey)) {
  print('[DROPDOWN] Auto-saving $fieldKey to server: $newValue');
  try {
    final isConnected = await _checkConnectivity();
    if (isConnected) {
      final response = await http.post(
        Uri.parse(AppConfig.updateLearnerUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'LearnerID': widget.learnerID,
          'data': {fieldKey: newValue},
        }),
      );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        if (jsonResponse['success'] == true) {
          print('[DROPDOWN] ✅ $fieldKey saved to server successfully');
        } else {
          print('[DROPDOWN] ❌ Server rejected $fieldKey: ${jsonResponse['message']}');
        }
      }
    } else {
      // Save locally when offline
      await DatabaseHelper()
          .updateLearnerLocally(widget.learnerID, {fieldKey: newValue});
      print('[DROPDOWN] 💾 $fieldKey saved locally (offline mode)');
    }
  } catch (e) {
    print('[DROPDOWN] ⚠️ Error auto-saving $fieldKey: $e');
  }
}
```

## Benefits

### Before Fix
1. User selects Province → stored locally
2. User selects District → stored locally  
3. User selects Municipality → stored locally
4. User must click "Update Data" button
5. **If user forgets to click, data never reaches server**

### After Fix
1. User selects Province → **instantly saved to server** ✓
2. User selects District → **instantly saved to server** ✓
3. User selects Municipality → **instantly saved to server** ✓
4. User selects SchoolCompletion → **instantly saved to server** ✓
5. **No "Update Data" button required for these fields**

## Behavior

### Online Mode
- Dropdown selection → Immediate HTTP POST to `update_learner.php`
- Success logged: `[DROPDOWN] ✅ Municipality saved to server successfully`
- Failure logged: `[DROPDOWN] ❌ Server rejected Municipality: <reason>`

### Offline Mode
- Dropdown selection → Immediate save to local SQLite
- Logged: `[DROPDOWN] 💾 Municipality saved locally (offline mode)`
- Will sync to server when connection restored

## Testing

### Monitor Logs
```powershell
adb -s RZ8X306F7TZ logcat | Select-String "DROPDOWN"
```

### Expected Log Sequence
```
[DROPDOWN] Province changed to: KwaZulu-Natal
[DROPDOWN] Province changed to: KwaZulu-Natal, fetching districts...
[DROPDOWN] Auto-saving Province to server: KwaZulu-Natal
[DROPDOWN] ✅ Province saved to server successfully
[DROPDOWN] Districts now available: 12

[DROPDOWN] District changed to: eThekwini Metropolitan Municipality
[DROPDOWN] District changed to: eThekwini Metropolitan Municipality, fetching municipalities...
[DROPDOWN] Auto-saving District to server: eThekwini Metropolitan Municipality
[DROPDOWN] ✅ District saved to server successfully
[DROPDOWN] Municipalities now available: 1

[DROPDOWN] Municipality changed to: eThekwini Metropolitan Municipality
[DROPDOWN] Auto-saving Municipality to server: eThekwini Metropolitan Municipality
[DROPDOWN] ✅ Municipality saved to server successfully
```

## Verification

### Check Server Received Data

```sql
SELECT LearnerID, Province, District, Municipality, SchoolCompletion 
FROM learnerdetails 
WHERE LearnerID = '6246';
```

Should show:
- Province: `KwaZulu-Natal`
- District: `eThekwini Metropolitan Municipality`
- Municipality: `eThekwini Metropolitan Municipality`  
- SchoolCompletion: (whatever was selected)

## Related Files

- `lib/LearnerDetailsPage.dart` - Auto-save dropdown logic
- `mobile/update_learner.php` - Server endpoint (already supported these fields)
- `mobile/fetch_provinces.php` - Province dropdown data
- `mobile/fetch_municipalities.php` - Municipality dropdown data
- `lib/utils/learner_profile_validation.dart` - Validation rules

## Notes

- **Existing data is preserved**: If server already has a value, it's NOT cleared
- **Network errors are logged but don't block UX**: User sees selection even if save fails
- **Offline support maintained**: Local SQLite updated immediately in offline mode
- **Cascading clears still work**: Changing Province clears District and Municipality (as designed)

## APK Status

✅ New APK built and installed on device RZ8X306F7TZ  
✅ 71.4MB release build  
✅ Auto-save functionality active

## Migration Guide

### For Other Dropdowns

To add auto-save to other dropdown fields, add them to the `autoSaveFields` set:

```dart
final autoSaveFields = {
  'Province',
  'District',
  'Municipality',
  'SchoolCompletion',
  'YourNewField',  // Add here
};
```

Ensure `mobile/update_learner.php` accepts the field (it already accepts all non-protected fields).
