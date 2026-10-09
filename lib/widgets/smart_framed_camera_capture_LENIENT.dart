// LENIENT VERSION - More forgiving thresholds for diverse conditions
// Copy this file over smart_framed_camera_capture.dart if the default is too strict

// ---------------------------------------------------------------------------
// LENIENT TUNING - Accepts wider range of conditions
// ---------------------------------------------------------------------------
const double _minFrameLum = 25;   // was 35 - accepts darker environments
const double _minFaceLum = 35;    // was 45 - accepts darker skin tones
const double _maxFaceLum = 235;   // was 225 - accepts brighter conditions

// SIZE RATIOS - More lenient (in _evaluate method, around line 410)
// Change from:
//   if (sizeRatio < 0.55) { ... } else if (sizeRatio > 0.92) { ... }
// To:
//   if (sizeRatio < 0.50) { ... } else if (sizeRatio > 0.95) { ... }

// CENTERING TOLERANCE - More lenient (around line 414)
// Change from:
//   off.dx.abs() > _oval.width * 0.12 || off.dy.abs() > _oval.height * 0.12
// To:
//   off.dx.abs() > _oval.width * 0.15 || off.dy.abs() > _oval.height * 0.15

// HEAD ANGLE - More lenient (around line 420)
// Change from:
//   .abs() <= 12
// To:
//   .abs() <= 15

// EYES OPEN - More lenient (around line 425)
// Change from:
//   >= 0.4
// To:
//   >= 0.3

// MOVEMENT TOLERANCE - More lenient (around line 455)
// Change from:
//   > _oval.width * 0.06
// To:
//   > _oval.width * 0.08

// HOLD DURATION - Faster (in SmartFramedCameraCapture class, line 32)
// Change from:
//   this.holdDuration = const Duration(milliseconds: 1000),
// To:
//   this.holdDuration = const Duration(milliseconds: 800),

/* 
 * WHEN TO USE THIS VERSION:
 * 
 * - Testing shows too many false rejections
 * - Users struggle to get "ready" status
 * - Diverse lighting conditions (outdoor + indoor)
 * - Diverse user demographics (skin tones, heights, ages)
 * - You need faster captures (training/enrollment scenarios)
 * 
 * TRADE-OFF:
 * - May accept slightly lower quality photos
 * - May need to rely more on final photo validation
 * 
 * TO APPLY:
 * 1. Copy this file's constants to smart_framed_camera_capture.dart
 * 2. Make the indicated changes in the methods
 * 3. Rebuild and test
 */
