# Implementation Plan: Cascading Province → District → Municipality Dropdowns

## Current State Analysis

Based on exploration of the RLMSS codebase:

1. **Backend endpoints already exist**:
   - `c:/projects/rlmss/mobile/fetch_provinces.php` - Returns `{success, data:{provinces:[{id,name}]}}`
   - `c:/projects/rlmss/mobile/fetch_districts.php` - Accepts `province` query param, returns `{success, data:{districts:[{id,name}]}}`
   - `c:/projects/rlmss/mobile/fetch_municipalities.php` - Accepts `district` query param, returns `{success, data:{municipalities:[{id,name}]}}`

2. **Database tables exist**:
   - `province` table with `id`, `province_name` columns
   - `district` table with `District_name`, `province_name` columns  
   - `local_municipality` table with `local_municipality_name`, `district_name` columns

3. **Flutter implementation partially exists**:
   - `LearnerDetailsPage.dart` has `_provinces`, `_districts`, `_municipalities` lists
   - `_fetchProvinces()`, `_fetchDistricts(province)`, `_fetchMunicipalities(district)` methods exist
   - Dropdown `onChanged` handlers exist with cascading logic
   - SQLite offline fallback exists in `database_helper.dart`

4. **The problem**: Districts and municipalities are not being populated because the cascading calls are not being triggered properly on initial load when existing learner data contains location values.

## Implementation Plan

- [ ] 1. Fix the initial cascade loading in `LearnerDetailsPage.dart` by ensuring `_loadLocationCascadesIfNeeded()` is called at the right time and works correctly.
      The method exists but may not be triggering properly when learner data is loaded.
      Files: c:/projects/rlmss/lib/LearnerDetailsPage.dart
      Verify: Load a learner profile with existing Province/District/Municipality values and confirm all three dropdowns populate correctly.

- [ ] 2. Enhance the dropdown `onChanged` handlers to provide visual feedback (loading indicators) when fetching districts/municipalities.
      Currently the dropdowns change but users don't see that a network request is happening.
      Files: c:/projects/rlmss/lib/LearnerDetailsPage.dart
      Verify: Select a province and confirm a loading indicator appears while districts are being fetched.

- [ ] 3. Fix the SQL table name inconsistencies between the PHP endpoints and database schema.
      `fetch_districts.php` queries `district.District_name` but `fetch_municipalities.php` queries `local_municipality.local_municipality_name` - ensure consistent column naming.
      Files: c:/projects/rlmss/mobile/fetch_districts.php, c:/projects/rlmss/mobile/fetch_municipalities.php
      Verify: `curl "https://rlms.rlms.co.za/mobile/fetch_districts.php?province=Gauteng"` returns districts successfully.

- [ ] 4. Add proper error handling and fallback messages when districts/municipalities are not found for a selected province/district.
      Currently empty lists are shown with no user feedback about why dropdowns are empty.
      Files: c:/projects/rlmss/lib/LearnerDetailsPage.dart
      Verify: Select a province with no districts in the database and confirm user sees a helpful message.

- [ ] 5. Ensure offline cache synchronization by calling `DatabaseHelper().syncLocationTables()` during app startup.
      The sync methods exist but may not be called to populate local SQLite tables with server data.
      Files: c:/projects/rlmss/lib/main.dart or c:/projects/rlmss/lib/LearnerDetailsPage.dart
      Verify: With internet, open app, go offline, then verify province/district/municipality dropdowns still work with cached data.

- [ ] 6. Add validation to prevent saving incomplete location data (e.g., Province selected but District/Municipality empty).
      The validation rules exist in `_profileValidationRuleKeys` but need to enforce completeness of the location hierarchy.
      Files: c:/projects/rlmss/lib/LearnerDetailsPage.dart
      Verify: Try to save learner with Province="Gauteng" but empty District - confirm validation prevents save with clear error message.

- [ ] 7. Improve the `_resolveDropdownValue()` method to handle location fields correctly, ensuring case-insensitive matching.
      Current implementation may not properly match existing saved values with dropdown options loaded from server.
      Files: c:/projects/rlmss/lib/LearnerDetailsPage.dart  
      Verify: Load learner with Province="kwazulu natal" (lowercase) and confirm it properly matches "KwaZulu Natal" from server data.

## Current Working Elements (No Changes Needed)

- Base URL configuration in `config.dart` is correct (`https://rlms.rlms.co.za/mobile`)
- Province, District, Municipality are already in `_profileValidationRuleKeys` 
- SQLite schema in `database_helper.dart` has proper location tables with seeded data
- Server-first, local-fallback approach is already implemented correctly
- Dropdown widget building in `_buildDropdownField()` supports dynamic options via `_allDropdownOptions`

## Files to Modify

1. `c:/projects/rlmss/lib/LearnerDetailsPage.dart` - Fix cascade loading, add loading indicators, improve error handling
2. `c:/projects/rlmss/mobile/fetch_districts.php` - Verify column names match database schema  
3. `c:/projects/rlmss/mobile/fetch_municipalities.php` - Verify column names match database schema
4. `c:/projects/rlmss/lib/main.dart` - Add location sync during app startup (if not already present)

## No New Files Needed

All required backend endpoints and database tables already exist. The Flutter offline caching infrastructure is already in place in `database_helper.dart`.