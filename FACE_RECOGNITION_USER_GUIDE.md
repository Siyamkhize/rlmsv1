# Face Recognition User Guide
## Backup Clock-In System

---

## What is Face Recognition Clock-In?

The face recognition system provides secure identity verification during clock-in. Instead of relying only on signatures, the system uses your face to confirm your identity.

### Key Benefits:
- ✅ **More Secure** - Prevents buddy punching
- ✅ **Legal Evidence** - Photo proof of attendance
- ✅ **Fast** - Verify in seconds
- ✅ **Fallback Options** - Security questions if face fails

---

## How It Works

### The Clock-In Flow

```
1. Select Learner
   ↓
2. Complete Profile/Bank/Document Checks
   ↓
3. Enter ID Number
   ↓
4. 🆕 FACE RECOGNITION (New Step)
   ↓
5. Signature Capture
   ↓
6. GPS Verification
   ↓
7. Clock In Complete ✅
```

---

## First Time: Register Your Face

### When You See This:

![Face Registration Dialog]
```
┌─────────────────────────────────────┐
│ 🙂 Face Recognition Setup          │
├─────────────────────────────────────┤
│ No face registered for this learner │
│                                     │
│ Would you like to register your     │
│ face now? This will be used for     │
│ future clock-ins.                   │
│                                     │
│ Tips for best results:              │
│ • Look directly at the camera       │
│ • Ensure good lighting              │
│ • Remove glasses if possible        │
│ • Keep a neutral expression         │
│                                     │
│ [Skip for Now]  [Register Face]    │
└─────────────────────────────────────┘
```

### Steps to Register:

1. **Tap "Register Face"**
2. **Camera opens** - you'll see:
   - Your face in camera preview
   - Oval guide (position face inside)
   - Quality indicator at top
   
3. **Position your face:**
   - Center face in oval
   - Keep 30-40cm from camera
   - Look directly at camera
   - Wait for green "Good" indicator

4. **Quality Indicators:**
   - 🔴 **None** - No face detected
   - 🟠 **Bad (too small)** - Move closer
   - 🟢 **Good** - Perfect! Ready to capture
   - 🟠 **Multiple** - Too many faces, remove others

5. **Tap "Capture Face"**
6. Wait for processing (5-10 seconds)
7. ✅ **Success!** "Face registered successfully!"

**Note:** You only need to register once. After that, verification is automatic.

---

## Every Clock-In: Verify Your Face

### When You See This:

```
┌─────────────────────────────────────┐
│ Verify Your Identity                │
│ Position your face in the oval      │
│ (Attempt 1 of 3)                    │
│                                     │
│ Face Quality: Good ✅               │
│                                     │
│        [ Camera View ]              │
│                                     │
│      [Capture Face Button]          │
└─────────────────────────────────────┘
```

### Steps to Verify:

1. **Camera opens automatically** (no dialog)
2. **Position your face** (same as registration)
3. **Wait for "Good" quality**
4. **Tap "Capture Face"**
5. **Wait 3-5 seconds** for verification
6. ✅ **Success!** "Face verified successfully!"
7. Continue to signature step

---

## If Face Verification Fails

### You Get 3 Attempts

If verification fails, you'll see:
```
⚠️ Verification failed: Face does not match (Attempt 1 of 3)
```

**Try again with:**
- Better lighting
- Face camera directly
- Remove glasses/hat
- Keep neutral expression

### After 3 Failed Attempts

You'll be asked **Security Questions**:

```
┌─────────────────────────────────────┐
│ Security Verification               │
├─────────────────────────────────────┤
│ Face verification failed.           │
│ Please answer security questions:   │
│                                     │
│ Question 1: What is your date       │
│ of birth?                           │
│ Enter first 6 digits of ID number   │
│ (YYMMDD)                            │
│ [______]                            │
│                                     │
│ Question 2: Confirm your full       │
│ ID number                           │
│ [_____________]                     │
│                                     │
│ [Cancel]  [Verify]                  │
└─────────────────────────────────────┘
```

**Example:**
- ID Number: `9512151234088`
- Question 1 Answer: `951215` (first 6 digits)
- Question 2 Answer: `9512151234088` (full ID)

---

## Tips for Success

### ✅ DO:
- **Find good lighting** - Natural light works best
- **Face camera directly** - Look straight ahead
- **Stay still** - Don't move during capture
- **Remove obstructions** - Take off glasses, hat if needed
- **Keep expression neutral** - Relaxed, natural face
- **Be patient** - Wait for "Good" indicator

### ❌ DON'T:
- Don't use in dark rooms
- Don't tilt head sideways
- Don't move while capturing
- Don't have multiple people in frame
- Don't cover face with hands/objects
- Don't rush - wait for good quality

---

## Clock-Out Process

**Important:** Clock-out does NOT use face recognition.

Clock-out only requires:
1. ID verification
2. Signature capture
3. GPS verification

This is intentional - face verification is only needed once per day at clock-in.

---

## What Gets Stored

### Your Privacy

When you clock in with face verification, the system stores:

✅ **Stored:**
- Mathematical face template (192 numbers) - NOT a photo
- Verification photo (1 per day) - For legal evidence only
- GPS coordinates - To prove location
- Verification method - Face, signature, or security questions
- Timestamp - When you clocked in

❌ **NOT Stored:**
- Video of you
- Continuous photos
- Biometric data that can recreate your face

### Legal Protection

The verification photo provides:
- Proof you were present
- Evidence for disputes
- Audit trail for compliance
- Protection for both learner and employer

---

## Troubleshooting

### Problem: "No face detected"
**Solution:**
- Ensure face is in frame
- Check lighting (not too dark)
- Move camera closer to face
- Remove obstructions

### Problem: "Face too small"
**Solution:**
- Move 5-10cm closer to camera
- Ensure face fills most of oval guide

### Problem: "Multiple faces detected"
**Solution:**
- Ensure only YOU are visible
- Other people must leave frame
- Cover background windows/mirrors

### Problem: Camera won't open
**Solution:**
- Check camera permissions in settings
- Close other apps using camera
- Restart app if needed

### Problem: Verification keeps failing
**Solution:**
- Use same lighting as enrollment
- Check if glasses/hat are different
- Try removing glasses
- Use security questions fallback

### Problem: Processing takes too long
**Solution:**
- Ensure good phone signal (needs server)
- Check internet connection
- Try again in better network area

---

## Frequently Asked Questions

### Q: Is face recognition required?
**A:** No, you can skip registration and use signature-only mode. However, it's recommended for security.

### Q: Can I register again if it's not working?
**A:** Yes, contact your administrator to reset your face registration.

### Q: What if I change my appearance (haircut, beard, etc.)?
**A:** Minor changes are OK. Major changes may require re-registration.

### Q: Can someone else clock in with my photo?
**A:** No, the system detects live faces only, not photos.

### Q: What if my phone has no camera?
**A:** Use signature-only mode by skipping face registration.

### Q: Is my face data secure?
**A:** Yes, only mathematical templates are stored, not photos. Verification photos are encrypted.

### Q: Can I opt out of face recognition?
**A:** Yes, skip registration. You'll use signature-only mode.

### Q: What happens if I refuse security questions?
**A:** Clock-in will be cancelled. You'll need to try again with face verification or contact supervisor.

---

## Support

### Need Help?

1. **Technical Issues:**
   - Contact IT support
   - Provide error message if shown
   - State what step failed

2. **Face Registration Not Working:**
   - Ask supervisor to reset your registration
   - Try different device if available

3. **Privacy Concerns:**
   - Review privacy policy with HR
   - Request data deletion if needed

---

## System Requirements

- **Device:** Android phone/tablet with front camera
- **Camera:** Minimum 2MP front camera
- **Internet:** Required for enrollment and verification
- **Lighting:** Indoor or outdoor with adequate lighting
- **Storage:** ~500KB per clock-in for photo storage

---

## Version Information

- **Face Recognition Version:** 1.0
- **Model:** MobileFaceNet (192-dimension embeddings)
- **Detection:** Google ML Kit Face Detection
- **Threshold:** 0.72 (configurable by admin)

---

## Legal Notice

By using face recognition clock-in:
- You consent to biometric data processing
- You understand photos are stored as evidence
- You agree to identity verification requirements
- You can opt out by using signature-only mode

For full terms, see your employment agreement or contact HR.

---

*Last Updated: 2026-01-19*
*System: RLMS Backup Clock-In with Face Recognition*
