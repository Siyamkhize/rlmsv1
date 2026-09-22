# Location Fields Added to Add Learner Form

## Summary
Added Province, District, and Municipality dropdown fields to the Add Learner form, positioned above Bank Details section.

## Database Changes

### SQL Script: `add_location_columns_to_learnerdetails.sql`
Adds three new columns to `learnerdetails` table:
- `Province VARCHAR(50)`
- `District VARCHAR(50)`  
- `Municipality VARCHAR(50)`

**Run this SQL script on your server database:**
```sql
ALTER TABLE learnerdetails 
ADD COLUMN IF NOT EXISTS Province VARCHAR(50) NULL AFTER KinContact,
ADD COLUMN IF NOT EXISTS District VARCHAR(50) NULL AFTER Province,
ADD COLUMN IF NOT EXISTS Municipality VARCHAR(50) NULL AFTER District;
```

## New PHP Endpoints

### 1. `mobile/fetch_provinces.php`
- Returns list of all provinces
- Requires authentication
- Response format:
```json
{
  "success": true,
  "data": {
    "provinces": [
      {"id": "Eastern Cape", "name": "Eastern Cape"},
      {"id": "Free State", "name": "Free State"},
      ...
    ]
  }
}
```

### 2. `mobile/fetch_districts.php`
- Returns districts for a specific province
- Requires: `?province=Eastern%20Cape` parameter
- Requires authentication
- Response format:
```json
{
  "success": true,
  "data": {
    "districts": [
      {"id": "Alfred Nzo", "name": "Alfred Nzo"},
      {"id": "Amathole", "name": "Amathole"},
      ...
    ]
  }
}
```

### 3. `mobile/fetch_municipalities.php`
- Returns municipalities for a specific district
- Requires: `?district=Alfred%20Nzo` parameter
- Requires authentication
- Response format:
```json
{
  "success": true,
  "data": {
    "municipalities": [
      {"id": "Matatiele", "name": "Matatiele"},
      {"id": "Umzimvubu", "name": "Umzimvubu"},
      ...
    ]
  }
}
```

## App Changes

### `lib/AddLearnerPage.dart`
**New State Variables:**
```dart
String? _selectedProvince;
String? _selectedDistrict;
String? _selectedMunicipality;

List<String> _provinces = [];
List<String> _districts = [];
List<String> _municipalities = [];
```

**New Methods:**
- `_fetchProvinces()` - Loads provinces on page load
- `_fetchDistricts(String province)` - Loads districts when province selected
- `_fetchMunicipalities(String district)` - Loads municipalities when district selected
- `initState()` - Calls `_fetchProvinces()` automatically

**UI Changes:**
Added new section "Location Information" between "Next of Kin Information" and "Bank Details":
- Province dropdown (triggers district fetch)
- District dropdown (triggers municipality fetch)
- Municipality dropdown

**Form Submission:**
Added three new fields to learner data:
```dart
'Province': _selectedProvince ?? '',
'District': _selectedDistrict ?? '',
'Municipality': _selectedMunicipality ?? '',
```

### `lib/database_helper.dart`
Updated `learnerdetails` table creation to include:
```dart
Province VARCHAR(50),
District VARCHAR(50),
Municipality VARCHAR(50),
```

### `mobile/add_learner.php`
Updated to accept and store the new fields in both INSERT and UPDATE operations:
```php
'Province' => $input['Province'] ?? '',
'District' => $input['District'] ?? '',
'Municipality' => $input['Municipality'] ?? '',
```

## Database Tables Required

**You already have these tables!** The PHP endpoints use your existing table structure:

### Your existing `province` table:
```
id
province_name
```

### Your existing `District` table:
```
id
province_name
District_name
```

### Your existing `local_municipality` table:
```
id
province_name
district_name
local_municipality_name
```

## PHP Endpoints - Updated for Your Table Structure

### 1. `mobile/fetch_provinces.php`
```sql
SELECT DISTINCT province_name FROM province ORDER BY province_name ASC
```

### 2. `mobile/fetch_districts.php`
```sql
SELECT DISTINCT District_name FROM District 
WHERE province_name = ? 
ORDER BY District_name ASC
```

### 3. `mobile/fetch_municipalities.php`
```sql
SELECT DISTINCT local_municipality_name FROM local_municipality 
WHERE district_name = ? 
ORDER BY local_municipality_name ASC
```

## Testing Steps

1. **Run SQL script** on server database to add columns to learnerdetails
2. **No need to populate tables** - you already have data!
3. **Build and install APK**
4. **Test Add Learner form:**
   - Select Province → Districts load from your District table
   - Select District → Municipalities load from your local_municipality table
   - Submit form → Verify data saved to learnerdetails table

## Next Steps

1. Run `add_location_columns_to_learnerdetails.sql` on server (adds 3 columns)
2. Build new APK with location fields
3. Test the cascading dropdowns work correctly
4. Verify data is saved to learnerdetails table

## Files Modified

- ✅ `lib/AddLearnerPage.dart` - Added dropdowns and fetch methods
- ✅ `lib/database_helper.dart` - Added columns to local database
- ✅ `mobile/add_learner.php` - Added fields to INSERT/UPDATE
- ✅ `mobile/fetch_provinces.php` - NEW endpoint
- ✅ `mobile/fetch_districts.php` - NEW endpoint
- ✅ `mobile/fetch_municipalities.php` - NEW endpoint
- ✅ `add_location_columns_to_learnerdetails.sql` - NEW SQL script
