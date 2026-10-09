# Manual Clocking with Signature + Geofence - Implementation Complete

## Overview
Updated `signature_geofence_clock_in_page.dart` to use **new dedicated endpoints** for manual clocking that insert into the `manual_clocking` table and a new `manual_clocking_evidence` table for storing signature and face photos.

## Database Changes

### New Table: `manual_clocking_evidence`
Stores signature and face verification photos for manual clock-in/out records.

**Fields:**
- `evidence_id` - Auto-increment primary key
- `LearnerID` - Foreign key to learnerdetails
- `clock_date` - Date of clocking
- `signature_in` - Base64 signature image for clock-in
- `signature_out` - Base64 signature image for clock-out
- `face_in` - Base64 face photo for clock-in (future use)
- `face_out` - Base64 face photo for clock-out (future use)
- `created_at`, `updated_at` - Timestamps

**Unique Constraint:** `UNIQUE KEY unique_learner_date_evidence (LearnerID, clock_date)`

### Existing Table: `manual_clocking`
The page now inserts into this table with these fields:
- `LearnerID` - Learner ID
- `clock_date` - Date
- `clock_in_time` - Time of clock-in (HH:mm:ss)
- `clock_out_time` - Time of clock-out (HH:mm:ss)
- `contact_time` - Duration (calculated on clock-out)
- `is_manual_attendance` - Set to 1

## New PHP Endpoints

### 1. `mobile/save_manual_clockin.php`
**Purpose:** Save manual clock-in with signature and GPS data

**Request (JSON):**
```json
{
  "learner_id": 12345,
  "clock_date": "2026-10-02",
  "clock_in_time": "08:30:00",
  "signature_in": "base64_encoded_signature",
  "face_in": null,
  "latitude": -26.123456,
  "longitude": 28.123456,
  "accuracy": 5.0
}
```

**Response:**
```json
{
  "success": true,
  "message": "Clock-in saved successfully",
  "manual_id": 123,
  "learner_id": 12345,
  "clock_date": "2026-10-02",
  "clock_in_time": "08:30:00"
}
```

**Logic:**
- INSERTS into `manual_clocking` table (or UPDATES if exists)
- INSERTS into `manual_clocking_evidence` table with signature image
- Uses transaction for data integrity

### 2. `mobile/save_manual_clockout.php`
**Purpose:** Save manual clock-out with signature and GPS data

**Request (JSON):**
```json
{
  "learner_id": 12345,
  "clock_date": "2026-10-02",
  "clock_out_time": "16:30:00",
  "signature_out": "base64_encoded_signature",
  "face_out": null,
  "latitude": -26.123456,
  "longitude": 28.123456,
  "accuracy": 5.0
}
```

**Response:**
```json
{
  "success": true,
  "message": "Clock-out saved successfully",
  "learner_id": 12345,
  "clock_date": "2026-10-02",
  "clock_out_time": "16:30:00"
}
```

**Logic:**
- UPDATES `manual_clocking` table with clock_out_time
- UPDATES `manual_clocking_evidence` table with signature_out image
- Requires existing clock_in_time (validates before updating)

### 3. `mobile/get_manual_clocking_status.php`
**Purpose:** Fetch all manual clocking records for a specific date

**Request (GET):**
```
GET mobile/get_manual_clocking_status.php?clock_date=2026-10-02
```

**Response:**
```json
{
  "success": true,
  "clock_date": "2026-10-02",
  "count": 25,
  "records": [
    {
      "manual_id": 123,
      "learner_id": 12345,
      "clock_date": "2026-10-02",
      "clock_in_time": "08:30:00",
      "clock_out_time": "16:30:00",
      "contact_time": "8h 0m",
      "first_name": "John",
      "last_name": "Doe",
      "id_number": "0001010000000",
      "is_clocked_in": true,
      "is_clocked_out": true,
      "is_complete": true
    }
  ]
}
```

## Flutter Changes

### `signature_geofence_clock_in_page.dart`

**Updated Methods:**

1. **`_clockInOnline()`**
   - Changed from `AppConfig.clockinUrl` to `AppConfig.buildUrl('save_manual_clockin.php')`
   - Sends JSON payload instead of form data
   - Payload includes: `learner_id`, `clock_date`, `clock_in_time`, `signature_in`, GPS coords

2. **`_clockOutOnline()`**
   - Changed from `AppConfig.clockoutUrl` to `AppConfig.buildUrl('save_manual_clockout.php')`
   - Sends JSON payload with: `learner_id`, `clock_date`, `clock_out_time`, `signature_out`, GPS coords
   - Calculates contact_time locally for display

3. **`_fetchClockingDataFromServer()`**
   - Fetches from `get_manual_clocking_status.php` instead of syncing offline records
   - Loads today's manual clocking records and updates UI state

## Deployment Steps

### 1. Deploy Database Table
```bash
php deploy_manual_clocking_evidence.php
```

This script will:
- Create `manual_clocking_evidence` table
- Verify `manual_clocking` table exists
- Display table structures

### 2. Verify Endpoints
Test the endpoints:
```bash
# Test clock-in
curl -X POST https://rlms.rlms.co.za/mobile/save_manual_clockin.php \
  -H "Content-Type: application/json" \
  -d '{"learner_id":12345,"clock_date":"2026-10-02","clock_in_time":"08:30:00","signature_in":"test"}'

# Test clock-out
curl -X POST https://rlms.rlms.co.za/mobile/save_manual_clockout.php \
  -H "Content-Type: application/json" \
  -d '{"learner_id":12345,"clock_date":"2026-10-02","clock_out_time":"16:30:00","signature_out":"test"}'

# Test status fetch
curl https://rlms.rlms.co.za/mobile/get_manual_clocking_status.php?clock_date=2026-10-02
```

### 3. Build and Install APK
```bash
cd c:\projects\rlmss
flutter build apk --release
adb -s RZ8X10CKD0B install -r "build\app\outputs\flutter-apk\app-release.apk"
```

## Files Created/Modified

### Created:
- `sql/create_manual_clocking_evidence_table.sql` - Table creation script
- `mobile/save_manual_clockin.php` - Clock-in endpoint
- `mobile/save_manual_clockout.php` - Clock-out endpoint
- `mobile/get_manual_clocking_status.php` - Status fetch endpoint
- `deploy_manual_clocking_evidence.php` - Deployment script
- `MANUAL_CLOCKING_SIGNATURE_GEOFENCE_COMPLETE.md` - This documentation

### Modified:
- `lib/signature_geofence_clock_in_page.dart` - Updated to use new endpoints

## Features

### Current Implementation:
✅ Signature capture for clock-in
✅ Signature capture for clock-out
✅ Strict 50m geofencing validation
✅ GPS coordinate tracking
✅ Manual clocking table integration
✅ Evidence table for signature storage
✅ Cross-device status sync
✅ Contact time calculation

### Future Enhancements (Ready for Implementation):
- Face photo capture for clock-in (`face_in` field ready)
- Face photo capture for clock-out (`face_out` field ready)
- Offline queue support
- Evidence photo viewing in admin panel

## Key Differences from Regular Clocking

| Feature | Regular Clock-In | Manual Clocking (Signature+Geo) |
|---------|------------------|----------------------------------|
| **Table** | `attendance` or `learner_clocking_evidence` | `manual_clocking` + `manual_clocking_evidence` |
| **Verification** | Fingerprint | Signature + Geofencing |
| **Endpoints** | `clockin.php`, `clockout.php` | `save_manual_clockin.php`, `save_manual_clockout.php` |
| **Evidence Storage** | Fingerprint template | Signature images (base64) |
| **GPS Requirement** | Optional | Mandatory (50m radius) |
| **Status Field** | Various | `is_manual_attendance = 1` |

## Testing Checklist

- [ ] Deploy `manual_clocking_evidence` table
- [ ] Test clock-in endpoint with curl
- [ ] Test clock-out endpoint with curl
- [ ] Build and install APK
- [ ] Test signature capture on device
- [ ] Test geofencing validation (inside/outside 50m)
- [ ] Test clock-in success
- [ ] Test clock-out success
- [ ] Verify data in `manual_clocking` table
- [ ] Verify signatures in `manual_clocking_evidence` table
- [ ] Test cross-device status sync

## Notes

- All signature images are stored as base64 encoded TEXT in the database
- The `face_in` and `face_out` fields are ready for future face recognition implementation
- GPS coordinates are sent with each request but not currently stored in evidence table (can be added if needed)
- Contact time is calculated client-side based on clock_in_time and clock_out_time
- Unique constraint prevents duplicate records per learner per day
- Transactions ensure data consistency between both tables

## Status
✅ **READY FOR DEPLOYMENT**

All code is complete and ready to build and test on device.
