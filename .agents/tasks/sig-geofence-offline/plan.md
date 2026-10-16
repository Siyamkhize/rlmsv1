# Implementation Plan: Signature Geofence Clock-In Page Offline-First Functionality

## Overview
Transform `signature_geofence_clock_in_page.dart` from a basic batch-only system to a comprehensive offline-first clock-in system. The page currently shows a blue UI and lacks proper server sync for displaying clocked-in learners.

## Root Cause Analysis - CRITICAL UPDATE
- **API EXISTS**: `get_manual_clocking_status.php?clock_date=YYYY-MM-DD` already returns clocked learners
- **Service EXISTS**: `ManualClockingEvidenceSyncService` but only gets ONE learner at a time
- **Problem**: Signature page does NOT call the API to get ALL clocked learners for the day
- **Solution**: Add direct API call in signature page to get all clocked learners and save to local `manual_clocking` table

## Key Requirements Discovered
- API: `get_manual_clocking_status.php` returns learners with `is_clocked_in`, `is_clocked_out`, `is_complete` flags
- Database table: `manual_clocking` (matches server table structure)
- Visual indicators must be: **orange with dash** for clocked-in, **blue** for available, **grey** for clocked-out
- Missing imports: `package:http/http.dart` for direct API calls
- Services to reuse: `OfflineSyncQueueService`, `DatabaseHelper` (but need new API call method)

---

## Implementation Steps

- [ ] 1. **Add required imports for direct API calls**
      - Add `import 'package:http/http.dart' as http;` for GET requests
      - Add `import 'dart:convert';` for JSON parsing 
      - Add `import 'package:connectivity_plus/connectivity_plus.dart';` for connectivity checks
      - Files: `lib/signature_geofence_clock_in_page.dart`
      - Verify: All imports resolve without errors

- [ ] 2. **Add method to call get_manual_clocking_status.php API directly**
      - Add `_fetchManualClockingStatus()` method to call `${AppConfig.baseUrl}/get_manual_clocking_status.php?clock_date=YYYY-MM-DD`
      - Parse JSON response to get learners with `is_clocked_in`, `is_clocked_out`, `is_complete` flags
      - Include error handling for network failures and API errors
      - Use South African timezone (SAST - UTC+2) for clock_date parameter
      - Files: `lib/signature_geofence_clock_in_page.dart`
      - Verify: API call returns learners with clocking status flags

- [ ] 3. **Add method to save server data to local manual_clocking table**
      - Add `_saveManualClockingToLocal()` method using DatabaseHelper
      - Create manual_clocking table if it doesn't exist using proper schema
      - Store learner_id, clock_in_time, clock_out_time, is_clocked_in, is_clocked_out, is_complete
      - Use INSERT OR REPLACE to handle duplicate records
      - Files: `lib/signature_geofence_clock_in_page.dart`
      - Verify: Server data is stored in local manual_clocking table

- [ ] 4. **Replace widget.learners dependency with local database loading**  
      - Replace `_loadClockingStatus()` with `_loadLearnersFromLocalDatabase()` 
      - Use `DatabaseHelper.getLearnersWithClockingData(widget.classID)` for base learner list
      - Query local `manual_clocking` table for clocking status using JOIN or separate queries
      - Update `_clockInTimes`, `_clockOutTimes`, `_contactTimes` maps from local database
      - Files: `lib/signature_geofence_clock_in_page.dart`
      - Verify: Page loads learners and shows proper clocking status from local database

- [ ] 5. **Fix visual indicators to match main clock-in page**
      - Update `_buildLearnerSelection()` method to use proper color scheme:
        - **Orange (`Colors.orange[700]`) with dash icon** for clocked-in learners  
        - **Blue (`Colors.blue[700]`) with learner initial** for available learners
        - **Grey (`Colors.grey[600]`) with check icon** for clocked-out learners
      - Use `_clockInTimes.containsKey(learnerId)` and `_clockOutTimes.containsKey(learnerId)` logic
      - Update status text and enable/disable logic based on local database state
      - Files: `lib/signature_geofence_clock_in_page.dart`
      - Verify: Visual indicators match main clock-in page appearance and behavior

- [ ] 6. **Add connectivity handling and initialization sync**
      - Add `_checkConnectivity()` method using Connectivity().checkConnectivity()
      - Call `_fetchManualClockingStatus()` on page initialization when online
      - Add automatic sync trigger when connectivity returns
      - Add error handling for offline scenarios
      - Files: `lib/signature_geofence_clock_in_page.dart`
      - Verify: Page syncs from server when online, works offline with local data

- [ ] 7. **Implement offline clock-out with proper database updates**
      - Modify `_processSignatureClocking()` to handle clock-out operations
      - Update existing `manual_clocking` record with clock_out_time using DatabaseHelper
      - Add sync queue entry using `OfflineSyncQueueService.enqueueAction()` with offline clock-out data
      - Calculate contact time using existing pattern from main clock-in page
      - Files: `lib/signature_geofence_clock_in_page.dart`
      - Verify: Clock-out updates local database and creates sync queue entry

- [ ] 8. **Replace batch processing with individual offline-first operations**
      - Remove always-batch processing timer and batch queue logic
      - Implement immediate local database storage for all clock-in/out operations  
      - Use `OfflineSyncQueueService.enqueueAction()` for offline sync queuing
      - Store signature data as base64 in sync queue payload for server upload
      - Update UI immediately from local database changes
      - Files: `lib/signature_geofence_clock_in_page.dart`
      - Verify: Clock-in/out operations work offline, sync when online, UI updates immediately

- [ ] 9. **Add manual refresh and sync status indicators**  
      - Add refresh button or pull-to-refresh gesture
      - Implement `_refreshData()` method that calls API and reloads from database
      - Show sync status indicators (syncing, offline count, last sync time)
      - Add manual "Sync Now" action when offline records exist
      - Files: `lib/signature_geofence_clock_in_page.dart`
      - Verify: Users can manually refresh data and see sync status

- [ ] 10. **Add proper error handling and logging**
       - Add debugging print statements following existing patterns from main clock-in page
       - Implement proper exception handling for API calls and database operations
       - Add user-friendly error messages for network and database failures
       - Log important state changes for troubleshooting
       - Files: `lib/signature_geofence_clock_in_page.dart`
       - Verify: Errors are handled gracefully and logged for debugging

## Key Methods to Add (The Existing Services Don't Cover This)

### New methods needed in signature_geofence_clock_in_page.dart:
- `_fetchManualClockingStatus()` - Direct API call to get ALL clocked learners for the day
- `_saveManualClockingToLocal()` - Save API results to local `manual_clocking` table  
- `_loadLearnersFromLocalDatabase()` - Load learners with clocking status from local DB
- `_checkConnectivity()` - Check network connectivity for API calls

### Existing methods to reuse:
- `DatabaseHelper.getLearnersWithClockingData(classID)` - Get base learner list
- `OfflineSyncQueueService.enqueueAction()` - Queue offline operations
- Standard database INSERT/UPDATE operations via DatabaseHelper

## Database Schema - UPDATED
- **Primary table**: `manual_clocking` (NOT `learner_clocking`) to match server structure
- **Fields**: learner_id, clock_in_time, clock_out_time, is_clocked_in, is_clocked_out, is_complete
- **Learner table**: `learnerdetails` with fields `LearnerID`, `Name`, `classID`
- **Class table**: `class` with site coordinates `site_lat`, `site_lon`

## Testing Verification
1. **Server Sync Test**: Verify clocked-in learners appear with orange dash icons
2. **Offline Clock-Out Test**: Clock out learners offline, verify grey check icons and sync queue
3. **Network Toggle Test**: Go offline/online, verify automatic sync and UI updates  
4. **Visual Regression Test**: Compare appearance with main clock-in page screenshots
5. **Database Test**: Verify correct table names (`class` not `classes`) and field mappings

## Success Criteria
- Visual appearance matches main clock-in page (orange/blue/grey indicators)  
- Shows learners that already clocked in from server (fixes current regression)
- Works completely offline with local database persistence
- Syncs automatically when network returns
- No more 404 errors on location endpoints (page doesn't depend on them)
- Builds and runs without SQLite "no such table: classes" errors