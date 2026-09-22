# Multi-Camera Face Enrollment Upgrade Complete ✅

## Overview
The existing face enrollment system has been **upgraded** to support multi-camera enrollment while maintaining **full backward compatibility** with the existing system.

---

## Changes Made

### 1. **Database Schema Update**
**File**: `sql/002_add_camera_facing_column.sql`

**Changes**:
- Added `camera_facing` ENUM column ('front', 'back') to `learner_face` table
- Default value: 'back' (for backward compatibility)
- Updated unique constraint to `(learner_id, camera_facing, active)` 
- This allows **one active enrollment per camera** per learner
- Existing records automatically get 'back' as default

**Run this SQL**:
```sql
-- Execute on MySQL server
source sql/002_add_camera_facing_column.sql
```

---

### 2. **PHP Endpoint Upgraded**
**File**: `mobile/enrol_learner_face.php`

**New Features**:
✅ **Multi-camera support** - can enroll front AND back camera simultaneously  
✅ **Backward compatible** - existing single-camera format still works  
✅ **Per-camera validation** - quality score, consent checked per camera  
✅ **Per-camera re-enrollment** - can update front/back independently  
✅ **Detailed results** - returns success/failure per camera  
✅ **All existing features preserved**:
   - Quality score validation
   - Consent tracking
   - Model version tracking
   - Verification logging
   - Re-enrollment logic

---

## API Usage

### Format 1: Single Camera (Backward Compatible)
```json
POST /mobile/enrol_learner_face.php
{
  "learner_id": 12345,
  "embedding": [0.123, -0.456, ...],
  "quality_score": 0.85,
  "consent_given": true,
  "camera_facing": "back"  // optional, defaults to "back"
}
```

**Response**:
```json
{
  "success": true,
  "message": "Face enrolled successfully",
  "enrolled_count": 1,
  "results": [
    {
      "camera": "back",
      "success": true,
      "message": "Face enrolled successfully",
      "enrollment_id": 456,
      "action": "created"
    }
  ]
}
```

---

### Format 2: Multi-Camera (New Format)
```json
POST /mobile/enrol_learner_face.php
{
  "learner_id": 12345,
  "embeddings": [
    {
      "embedding": [0.123, -0.456, ...],
      "quality_score": 0.87,
      "camera_facing": "back"
    },
    {
      "embedding": [0.789, -0.321, ...],
      "quality_score": 0.82,
      "camera_facing": "front"
    }
  ],
  "consent_given": true
}
```

**Response**:
```json
{
  "success": true,
  "message": "2 faces enrolled successfully",
  "enrolled_count": 2,
  "results": [
    {
      "camera": "back",
      "success": true,
      "message": "Face enrolled successfully",
      "enrollment_id": 456,
      "action": "created"
    },
    {
      "camera": "front",
      "success": true,
      "message": "Face enrolled successfully",
      "enrollment_id": 457,
      "action": "created"
    }
  ]
}
```

---

## Validation Rules (Per Camera)

Each embedding is validated independently:

| Validation | Rule |
|------------|------|
| **camera_facing** | Must be 'front' or 'back' |
| **consent_given** | Must be true |
| **embedding** | Must be array of 192 floats (MobileFaceNet) |
| **quality_score** | Must be >= MIN_ENROLLMENT_QUALITY (from config) |
| **unique constraint** | One active enrollment per learner per camera |

---

## Re-enrollment Logic

**Default behavior**: Prevents duplicate enrollment
```json
{
  "learner_id": 12345,
  "embedding": [...],
  "camera_facing": "back"
}
// ERROR: Learner already has active enrollment for back camera
```

**With allow_reenroll flag**:
```json
{
  "learner_id": 12345,
  "embedding": [...],
  "camera_facing": "back",
  "allow_reenroll": true  // Updates existing enrollment
}
```

---

## Database Structure

### Before (Single Camera)
```
learner_face table:
- One row per learner
- UNIQUE KEY (learner_id, active)
```

### After (Multi-Camera)
```
learner_face table:
- Multiple rows per learner (one per camera)
- UNIQUE KEY (learner_id, camera_facing, active)
- camera_facing: ENUM('front', 'back') DEFAULT 'back'
```

**Example data**:
```
id | learner_id | camera_facing | quality_score | active
---|------------|---------------|---------------|-------
1  | 12345      | back          | 0.87          | 1
2  | 12345      | front         | 0.82          | 1
3  | 67890      | back          | 0.91          | 1
```

---

## Migration Path

### Step 1: Run Database Migration
```bash
mysql -u your_user -p your_database < sql/002_add_camera_facing_column.sql
```

### Step 2: Test Backward Compatibility
Test existing single-camera enrollment (should work unchanged):
```bash
curl -X POST https://your-server/mobile/enrol_learner_face.php \
  -H "Content-Type: application/json" \
  -d '{
    "learner_id": 12345,
    "embedding": [0.123, ...],
    "quality_score": 0.85,
    "consent_given": true
  }'
```

### Step 3: Test Multi-Camera Enrollment
```bash
curl -X POST https://your-server/mobile/enrol_learner_face.php \
  -H "Content-Type: application/json" \
  -d '{
    "learner_id": 12345,
    "embeddings": [
      {"embedding": [0.123, ...], "quality_score": 0.87, "camera_facing": "back"},
      {"embedding": [0.789, ...], "quality_score": 0.82, "camera_facing": "front"}
    ],
    "consent_given": true
  }'
```

---

## Benefits

✅ **Future-proof**: Ready for front and back camera enrollment  
✅ **Backward compatible**: Existing code continues to work  
✅ **Flexible**: Enroll one or both cameras as needed  
✅ **Safer matching**: Can compare live capture against multiple stored embeddings  
✅ **Independent updates**: Can re-enroll front/back separately  
✅ **Clean data model**: Clear separation by camera type  

---

## Next Steps

### For Mobile App Integration:
1. Update enrollment flow to capture both cameras (optional)
2. Send both embeddings in single API call
3. Handle per-camera results in response

### For Verification:
- Update `verify_learner_face.php` to:
  - Accept live embedding + camera_facing
  - Compare against **all stored embeddings** for learner
  - Return **best match score** across all cameras
  - This provides **better accuracy** and **flexibility**

---

## Files Modified

| File | Status | Description |
|------|--------|-------------|
| `sql/002_add_camera_facing_column.sql` | ✅ Created | Database migration script |
| `mobile/enrol_learner_face.php` | ✅ Updated | Multi-camera enrollment support |
| `mobile/enroll_face.php` | ❌ Deleted | Duplicate removed |
| `mobile/verify_face.php` | ❌ Deleted | Duplicate removed |

---

## System Maintained

✅ Uses existing `learner_face` table  
✅ Uses existing mysqli connection  
✅ Uses existing `face_recognition_config.php`  
✅ Uses existing validation functions  
✅ Maintains quality score tracking  
✅ Maintains consent tracking  
✅ Maintains model version tracking  
✅ Maintains verification logging  
✅ Maintains re-enrollment logic  

**No breaking changes - fully backward compatible!**
