# Smart Face Capture - Testing & Tuning Guide

## Quick Test Procedure

### 1. Access the Feature
- Open the app on device RZ8X10CKD0B
- Navigate to **Manual Clock In** for any learner
- The smart camera should open automatically

### 2. Test Each Validation Rule

#### ✓ Lighting Check (Step 1)
**Test scenarios:**
- [ ] Dark room - Should say "It's too dark"
- [ ] Face away from light - Should say "Your face is too dark"
- [ ] Direct sunlight/lamp - Should say "Too bright"
- [ ] Normal indoor lighting - Should pass ✓

**If fails incorrectly:**
- Too sensitive (rejects good lighting) → Increase thresholds
- Not sensitive enough (accepts bad lighting) → Decrease thresholds

#### ✓ Face Detection (Step 2)
**Test scenarios:**
- [ ] No face in frame - Should say "Position your face in the oval"
- [ ] Face enters frame - Check chip turns green ✓

#### ✓ Single Person (Step 3)
**Test scenarios:**
- [ ] Two people in frame - Should say "Only one person allowed"
- [ ] Someone walks behind you - Should detect and block
- [ ] Alone in frame - Should pass ✓

#### ✓ Size & Position (Step 4)
**Test scenarios:**
- [ ] Too far away - Should say "Move closer"
- [ ] Too close - Should say "Move back a little"
- [ ] Off to the side - Should say "Centre your face"
- [ ] Perfectly centered - Should pass ✓

#### ✓ Looking Straight (Step 5)
**Test scenarios:**
- [ ] Look left/right - Should say "Look straight"
- [ ] Look up/down - Should say "Look straight"
- [ ] Tilt head - Should say "Look straight"
- [ ] Look directly at camera - Should pass ✓

#### ✓ Eyes & Face Visibility (Step 6)
**Test scenarios:**
- [ ] Close eyes - Should say "Open your eyes"
- [ ] Wear mask - Should say "Show your whole face"
- [ ] Hand over face - Should say "Show your whole face"
- [ ] Wear hat/cap low - Should say "Show your whole face"
- [ ] Full face visible, eyes open - Should pass ✓

#### ✓ Hold Still (Step 7)
**Test scenarios:**
- [ ] Keep moving - Progress bar resets
- [ ] Hold perfectly still - Progress bar fills (1 second)
- [ ] Photo captures automatically ✓

### 3. Check Visual Feedback

#### Status Chips (Top of screen)
Watch the 6 chips as you adjust:
- Good light → ✓
- Face found → ✓
- One person → ✓
- In oval → ✓
- Looking straight → ✓
- Eyes open → ✓

#### Oval Border Color
- **White** = Searching for face
- **Orange** = Adjusting (one or more checks failing)
- **Green** = Ready (all checks passed, hold still)

#### Progress Ring
- Green ring around oval fills as you hold still
- Resets if you move

#### Manual Button
- **Gray** = Can't capture (rules not met)
- **Blue** = Ready to capture (tap anytime)

### 4. Photo Quality Check
After capture:
- [ ] Photo should have watermark
- [ ] Timestamp should be visible
- [ ] Learner name/ID should show
- [ ] Face should be clear and well-lit

---

## Common Issues & Solutions

### Issue: "It's too dark" but lighting seems fine
**Likely cause:** Dark skin tone + low threshold
**Solution:** Decrease `_minFrameLum` from 35 to 25

### Issue: "Your face is too dark" but face is visible
**Likely cause:** Dark skin tone + face threshold too high
**Solution:** Decrease `_minFaceLum` from 45 to 35

### Issue: "Too bright" in normal indoor lighting
**Likely cause:** Threshold too low for light skin tones
**Solution:** Increase `_maxFaceLum` from 225 to 235

### Issue: Won't detect face even when visible
**Likely causes:**
1. Camera initialization failed - restart app
2. ML Kit permission issue - check Android permissions
3. Lighting too dark - move to brighter area

### Issue: "Move closer" even when face fills oval
**Solution:** Decrease minimum size ratio from 0.55 to 0.50

### Issue: "Move back" when face is comfortable size
**Solution:** Increase maximum size ratio from 0.92 to 0.95

### Issue: "Centre your face" when face looks centered
**Solution:** Increase centering tolerance from 0.12 to 0.15

### Issue: "Look straight" when looking at camera
**Solution:** Increase head angle tolerance from 12° to 15°

### Issue: Progress bar keeps resetting
**Likely cause:** Device shaking or person moving slightly
**Solutions:**
1. Increase movement tolerance from 0.06 to 0.08
2. Decrease hold duration from 1000ms to 800ms

### Issue: Always says "Open your eyes" 
**Solution:** Decrease eye open threshold from 0.4 to 0.3

---

## Adjustment Instructions

All tunable values are at the **top of the file**:

### File: `lib/widgets/smart_framed_camera_capture.dart`

```dart
// Lines 28-30: LIGHTING THRESHOLDS
const double _minFrameLum = 35;   // whole picture (0-255)
const double _minFaceLum = 45;    // face area minimum
const double _maxFaceLum = 225;   // face area maximum

// Line 410-411: SIZE CHECK
final sizeRatio = r.height / _oval.height;
if (sizeRatio < 0.55) {           // too far
  fitProblem = 'Move closer';
} else if (sizeRatio > 0.92) {    // too close
  fitProblem = 'Move back a little';

// Line 414-415: CENTERING CHECK
} else if (off.dx.abs() > _oval.width * 0.12 ||   // horizontal
    off.dy.abs() > _oval.height * 0.12) {         // vertical
  fitProblem = 'Centre your face in the oval';

// Line 420-422: HEAD ANGLE CHECK
final straight = (face.headEulerAngleY ?? 0).abs() <= 12 &&  // left/right
    (face.headEulerAngleX ?? 0).abs() <= 12 &&                // up/down
    (face.headEulerAngleZ ?? 0).abs() <= 12;                  // tilt

// Line 425-426: EYES OPEN CHECK
final eyesOpen = (face.leftEyeOpenProbability ?? 1) >= 0.4 &&
    (face.rightEyeOpenProbability ?? 1) >= 0.4;

// Line 455-456: MOVEMENT DETECTION
if (_lastCenter != null &&
    (c - _lastCenter!).distance > _oval.width * 0.06) {  // movement threshold

// Line 32: HOLD DURATION
this.holdDuration = const Duration(milliseconds: 1000),
```

---

## Quick Tuning Reference

### Make Lighting MORE LENIENT (accept darker/brighter faces)
```dart
const double _minFrameLum = 25;   // was 35
const double _minFaceLum = 35;    // was 45
const double _maxFaceLum = 235;   // was 225
```

### Make Size/Position MORE LENIENT
```dart
if (sizeRatio < 0.50) {           // was 0.55 - accept further away
} else if (sizeRatio > 0.95) {    // was 0.92 - accept closer

// Centering
off.dx.abs() > _oval.width * 0.15 ||   // was 0.12 - more off-center OK
```

### Make Head Angle MORE LENIENT
```dart
final straight = (face.headEulerAngleY ?? 0).abs() <= 15 &&  // was 12
    (face.headEulerAngleX ?? 0).abs() <= 15 &&
    (face.headEulerAngleZ ?? 0).abs() <= 15;
```

### Make Hold-Still MORE LENIENT
```dart
(c - _lastCenter!).distance > _oval.width * 0.08)  // was 0.06 - more movement OK

// OR reduce hold time
this.holdDuration = const Duration(milliseconds: 800),  // was 1000
```

### Make Eyes Check MORE LENIENT
```dart
final eyesOpen = (face.leftEyeOpenProbability ?? 1) >= 0.3 &&  // was 0.4
    (face.rightEyeOpenProbability ?? 1) >= 0.3;
```

---

## After Making Changes

1. Save the file
2. Rebuild: `flutter build apk --release`
3. Install: `adb -s RZ8X10CKD0B install -r build\app\outputs\flutter-apk\app-release.apk`
4. Test again

---

## Recommended Testing Order

1. **Test in your normal environment first** (typical office/classroom lighting)
2. **Test edge cases** (dark corners, near windows, outdoors)
3. **Test with different people** (different skin tones, ages, heights)
4. **Test deliberate failures** (try to trick the system)

---

## Performance Notes

- **Frame rate:** ~10-15 fps (fast enough for real-time feedback)
- **Capture time:** 1-2 seconds from "ready" to photo saved
- **Battery impact:** Moderate (camera + ML Kit running)
- **Works offline:** Yes, ML Kit is on-device

---

## Need Help?

If you encounter issues not covered here, note:
1. Exact error message shown
2. Lighting conditions
3. Which check chips are green/gray
4. Device behavior (freezing, crashing, etc.)

I can then provide targeted adjustments!
