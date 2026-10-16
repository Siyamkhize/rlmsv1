# Signature Geofence Navigation Issue - Root Cause & Fix

**Date:** October 15, 2026  
**Issue:** Clicking "Clock In" in `signature_geofence_clock_in_page.dart` redirects to wrong page (`clock_in_page.dart`)  
**Status:** Root cause identified

## Problem Analysis

### Navigation Stack Problem

When you click "Clock In" in `signature_geofence_clock_in_page.dart`:

```
1. User is on: signature_geofence_clock_in_page.dart
2. Clicks "Clock In" button
3. → ensureLearnerProfileCompleteForClockIn() runs (from mixin)
4. → If profile incomplete: Navigator.push → LearnerDetailsPage
5. → User completes profile, closes LearnerDetailsPage
6. → Navigator.pop() takes user BACK through stack
7. → Ends up on clock_in_page.dart instead of signature_geofence_clock_in_page.dart
```

### The Root Cause

**File:** `lib/mixins/learner_clockin_gates_mixin.dart` (Lines 87-92)

```dart
await Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => LearnerDetailsPage(
      learnerID: learnerId,
      missingProfileOnlyMode: true,
      missingProfileFields: missingFieldKeys,
    ),
  ),
);
```

When the mixin pushes `LearnerDetailsPage` onto the navigation stack:
- The stack becomes: [clock_in_page, signature_geofence_page, learner_details_page]
- When you close learner_details_page, you go back to signature_geofence_page
- BUT if you then close/navigate from there, you go back to clock_in_page

### Why It Feels Like Wrong Redirect

The issue happens because:
1. Profile check opens LearnerDetailsPage
2. You update Province/District/Municipality
3. You close LearnerDetailsPage (Navigator.pop)
4. You think you're back on signature page ready to clock in
5. But the app might auto-navigate or you might hit back
6. Suddenly you're on clock_in_page.dart

## Solution Options

### Option 1: Don't Allow Profile Editing from Clock-In (Recommended)

Instead of opening LearnerDetailsPage, just show an error and block clock-in:

```dart
// In learner_clockin_gates_mixin.dart (Line ~87)
// REMOVE Navigator.push to LearnerDetailsPage

// INSTEAD:
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text(
      'Profile incomplete: ${missingFieldLabels.join(', ')}. '
      'Please complete profile before clock-in.',
    ),
    backgroundColor: Colors.red,
    duration: const Duration(seconds: 5),
    action: SnackBarAction(
      label: 'Exit',
      onPressed: () {
        Navigator.of(context).pop(); // Go back to previous screen
      },
    ),
  ),
);
return false;
```

**Pro:** Keeps navigation simple, forces users to complete profiles BEFORE coming to clock-in page  
**Con:** Less convenient - user has to go back, edit profile, then return

### Option 2: Use pushReplacement Instead of push

Replace the current signature page with LearnerDetailsPage:

```dart
// In learner_clockin_gates_mixin.dart (Line ~87)
await Navigator.pushReplacement(
  context,
  MaterialPageRoute(
    builder: (context) => LearnerDetailsPage(
      learnerID: learnerId,
      missingProfileOnlyMode: true,
      missingProfileFields: missingFieldKeys,
      returnToSignaturePage: true, // Add this flag
    ),
  ),
);
```

**Pro:** Keeps single-page navigation  
**Con:** Loses state on signature page (captured photos, etc.)

### Option 3: Fix Server Data First (Already Done!)

We already updated the server database with correct location data for learners 6246 and 11443. When they restart the app and sync, they won't see the profile completion prompt anymore.

**This is why the immediate issue is solved** - but the navigation bug still exists for OTHER learners with incomplete profiles.

## Recommended Fix

**SHORT TERM (Already Done):**
✅ Server database updated for learners 6246, 11443
✅ They can clock in after app restart/sync

**LONG TERM (Implement This):**
1. **Prevent profile editing from clock-in page** - Show error instead
2. **Add profile completion check at app startup** - Block access to clock-in until profile complete
3. **Or use a dedicated "Profile Setup" wizard** before allowing clock-in features

## Implementation

### Fix the Mixin (Option 1 - Simplest)

**File:** `lib/mixins/learner_clockin_gates_mixin.dart`

```dart
// Around line 82-102, REPLACE the Navigator.push block:

if (shouldOpenProfile != true) {
  return false;
}

// REMOVED: Navigator.push to LearnerDetailsPage
// NEW: Just show error and block clock-in

ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Profile incomplete. Missing:'),
        ...missingFieldLabels.map((f) => Text('  • $f')),
        SizedBox(height: 8),
        Text('Please complete your profile before clock-in.'),
      ],
    ),
    backgroundColor: Colors.orange[700],
    duration: const Duration(seconds: 6),
  ),
);

return false;
```

## Testing

After applying the fix:

1. **Test with incomplete profile:**
   - Create new learner with missing Province/District
   - Try to clock in from signature_geofence_clock_in_page
   - **Expected:** Shows error, stays on signature page, blocks clock-in

2. **Test with complete profile:**
   - Learner 6246 or 11443 (now have location data)
   - Try to clock in from signature_geofence_clock_in_page
   - **Expected:** Proceeds directly to face capture → signature → clock-in

## Summary

**Root Cause:** Mixin opens LearnerDetailsPage via Navigator.push, creating deep navigation stack  
**Why It Happens:** Profile validation opens editor page, document validation opens scanner, creates 4-5 level deep stack  
**When User Navigates Back:** Pops through multiple pages, ends up on wrong page  

**Immediate Fix:** Server data updated (learners 6246, 11443 have location data)  
**Permanent Fix:** Block clock-in if profile incomplete instead of opening editor  

---

**Next Step:** Implement Option 1 (block clock-in) or wait to see if server data fix solves issue for all users.
