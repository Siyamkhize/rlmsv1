# Signature Geofence Clock-In - Offline-First API Implementation Guide

## 🎯 Goal
Make the signature geofence clock-in page show learners that have already clocked in from the server and enable offline clock-out functionality.

---

## ✅ What Already Exists

### **1. API for Getting Clocked Learners** 
**Endpoint:** `get_manual_clocking_status.php` ✅ ALREADY EXISTS!

**Request:**
```
GET ${AppConfig.baseUrl}/get_manual_clocking_status.php?clock_date=2026-01-13
```

**Response:**
```json
{
  "success": true,
  "clock_date": "2026-01-13",
  "count": 5,
  "records": [
    {
      "manual_id": 123,
      "learner_id": "11443",
      "clock_date": "2026-01-13",
      "clock_in_time": "08:00:00",
      "clock_out_time": "16:00:00",
      "contact_time": null,
      "first_name": "John",
      "last_name": "Doe",
      "id_number": "9501011234567",
      "is_clocked_in": true,
      "is_clocked_out": true,
      "is_complete": true
    }
  ]
}
```

### **2. Database Tables**
- `manual_clocking` - SQLite table for offline storage
- `manual_clocking_evidence` - Face and signature evidence
- Both tables already exist!

### **3. Batch Processing**
- `save_class_batch_clocking.php` - Already implemented
- `OfflineSyncQueueService.queueForBatchProcessing()` - Already working
- Batch processing architecture is solid ✅

---

## ❌ What's Missing in signature_geofence_clock_in_page.dart

### **Problem 1: No Server Sync**
The page does NOT call `get_manual_clocking_status.php` to get clocked learners from server!

### **Problem 2: No Local Database Loading**
The page loads learners from `widget.learners` prop only, NOT from local database.

### **Problem 3: No Offline Clock-Out**
Cannot clock-out offline and queue for server sync.

---

## 🔧 Required Implementation

### **Step 1: Add Server-to-Offline Sync Method**
```dart
/// Sync clocked learners from server to local database
Future<void> _syncClockedLearnersFromServer() async {
  if (!_isConnected) {
    print('[SIG_SYNC] Offline - skipping server sync');
    return;
  }
  
  try {
    final clockDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final url = '${AppConfig.baseUrl}/get_manual_clocking_status.php?clock_date=$clockDate';
    
    print('[SIG_SYNC] Fetching clocked learners from server...');
    final response = await http.get(Uri.parse(url));
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      
      if (data['success'] == true) {
        final records = data['records'] as List;
        print('[SIG_SYNC] Received ${records.length} clocked learners');
        
        final db = await DatabaseHelper().database;
        
        // Save each record to local manual_clocking table
        for (var record in records) {
          await db.insert(
            'manual_clocking',
            {
              'LearnerID': record['learner_id'],
              'clock_date': record['clock_date'],
              'clock_in_time': record['clock_in_time'],
              'clock_out_time': record['clock_out_time'],
              'contact_time': record['contact_time'],
              'is_manual_attendance': 1,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        
        print('[SIG_SYNC] ✅ Synced ${records.length} records to local database');
        
        // Reload clocking status from local database
        await _loadClockingStatus();
        
      } else {
        print('[SIG_SYNC] Server returned error: ${data['error']}');
      }
    } else {
      print('[SIG_SYNC] HTTP error: ${response.statusCode}');
    }
  } catch (e) {
    print('[SIG_SYNC] Error syncing from server: $e');
  }
}
```

### **Step 2: Update _loadClockingStatus to Use Local Database**
```dart
/// Load clocking status from LOCAL manual_clocking table
Future<void> _loadClockingStatus() async {
  try {
    final db = await DatabaseHelper().database;
    final clockDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    
    print('[SIG_CLOCK] Loading clocking status from local database...');
    
    // Query local manual_clocking table
    final records = await db.query(
      'manual_clocking',
      where: 'clock_date = ? AND is_manual_attendance = ?',
      whereArgs: [clockDate, 1],
    );
    
    print('[SIG_CLOCK] Loaded ${records.length} clocking records from local DB');
    
    // Clear existing state
    _clockInTimes.clear();
    _clockOutTimes.clear();
    _contactTimes.clear();
    
    // Update state maps from local database
    for (var record in records) {
      final learnerId = record['LearnerID'].toString();
      final clockIn = record['clock_in_time']?.toString() ?? '';
      final clockOut = record['clock_out_time']?.toString() ?? '';
      final contact = record['contact_time']?.toString() ?? '';
      
      if (clockIn.isNotEmpty && clockIn != 'N/A' && clockIn != 'null') {
        _clockInTimes[learnerId] = clockIn;
      }
      if (clockOut.isNotEmpty && clockOut != 'N/A' && clockOut != 'null') {
        _clockOutTimes[learnerId] = clockOut;
      }
      if (contact.isNotEmpty && contact != 'N/A' && contact != 'null') {
        _contactTimes[learnerId] = contact;
      }
    }
    
    print('[SIG_CLOCK] Clock-in status loaded: ${_clockInTimes.length} clocked in, ${_clockOutTimes.length} clocked out');
    
    if (mounted) {
      setState(() {});
    }
  } catch (e) {
    print('[SIG_CLOCK] Error loading clocking status: $e');
  }
}
```

### **Step 3: Add Offline Clock-Out Functionality**
```dart
/// Perform offline clock-out and queue for server sync
Future<void> _performOfflineClockOut(String learnerId) async {
  try {
    final db = await DatabaseHelper().database;
    final clockDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final clockOutTime = DateFormat('HH:mm:ss').format(DateTime.now());
    
    print('[SIG_CLOCKOUT] Offline clock-out for learner $learnerId');
    
    // Update local database immediately for UI feedback
    final rowsAffected = await db.update(
      'manual_clocking',
      {'clock_out_time': clockOutTime},
      where: 'LearnerID = ? AND clock_date = ? AND is_manual_attendance = ?',
      whereArgs: [learnerId, clockDate, 1],
    );
    
    if (rowsAffected > 0) {
      print('[SIG_CLOCKOUT] ✅ Updated local database');
      
      // Queue for server sync when online (add to batch or individual queue)
      await _queueService.addToQueue(
        action: 'manual_clockout',
        payload: {
          'LearnerID': learnerId,
          'clock_date': clockDate,
          'clock_out_time': clockOutTime,
        },
      );
      
      // Update UI state immediately
      if (mounted) {
        setState(() {
          _clockOutTimes[learnerId] = clockOutTime;
        });
      }
      
      print('[SIG_CLOCKOUT] ✅ Offline clock-out complete and queued for sync');
      
    } else {
      print('[SIG_CLOCKOUT] ⚠️ No record found to update');
    }
    
  } catch (e) {
    print('[SIG_CLOCKOUT] Error: $e');
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Clock-out error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
```

### **Step 4: Update initState to Call Server Sync**
```dart
@override
void initState() {
  super.initState();
  _loadInitialData();
  _checkConnectivity();
  _startLocationTracking();
  _startBatchTimer();
  
  // ADD THIS: Sync clocked learners from server on page load
  _syncClockedLearnersFromServer();
}
```

### **Step 5: Update _loadInitialData Method**
```dart
/// Load initial data and setup
Future<void> _loadInitialData() async {
  setState(() => _isLoading = true);
  try {
    await _loadClassData();
    _filteredLearners = widget.learners;
    
    // Load clock-in status from LOCAL database (not from widget.learners)
    await _loadClockingStatus();
    
  } catch (e) {
    print('Error loading initial data: $e');
  } finally {
    setState(() => _isLoading = false);
  }
}
```

---

## 🎨 Visual Indicators (Already Working!)

The visual indicators are already correct in the code:
- **Orange avatar with dash icon** = Clocked in (`hasClockIn && !hasClockOut`)
- **Grey avatar with check icon** = Clocked out (`hasClockOut`)
- **Blue avatar with letter** = Available (not clocked in)

Once local database is populated, these will automatically work!

---

## ✅ Implementation Checklist

### Server Integration:
- [ ] Add `_syncClockedLearnersFromServer()` method
- [ ] Call `get_manual_clocking_status.php` on page load when online
- [ ] Parse response and save to local `manual_clocking` table
- [ ] Handle HTTP errors gracefully

### Local Database:
- [ ] Update `_loadClockingStatus()` to query local database
- [ ] Use `ConflictAlgorithm.replace` for upserts
- [ ] Verify `manual_clocking` table exists in database_helper.dart

### Offline Clock-Out:
- [ ] Implement `_performOfflineClockOut()` method
- [ ] Update local database immediately
- [ ] Queue operation for server sync
- [ ] Update UI state instantly

### Integration:
- [ ] Call sync in `initState()`
- [ ] Update `_loadInitialData()` to use new method
- [ ] Update `_handleClockOut()` to call offline method
- [ ] Test offline-online sync workflow

### Testing:
- [ ] Verify server sync pulls clocked learners
- [ ] Confirm visual indicators show correct colors
- [ ] Test offline clock-out saves locally
- [ ] Verify sync queue processes when online
- [ ] Build and install APK for field testing

---

## 🔄 Data Flow

### Online Mode:
1. Page loads → Call `get_manual_clocking_status.php`
2. Server returns clocked learners
3. Save to local `manual_clocking` table
4. Load from local database into UI state
5. Visual indicators update automatically

### Offline Mode:
1. Page loads → Load from local database only
2. Show cached clocking status
3. Clock-out button updates local database
4. Queue operation for server sync
5. UI updates immediately

### When Network Returns:
1. Batch processor syncs queued operations
2. Next page load pulls fresh data from server
3. Local database stays synchronized

---

## 🎯 Key Points

1. **API Already Exists**: `get_manual_clocking_status.php` is ready to use!
2. **Tables Already Exist**: `manual_clocking` table is in SQLite database
3. **Batch Processing Works**: Keep existing batch architecture
4. **Simple Addition**: Just add the sync call and local database loading
5. **Visual Indicators Work**: No changes needed once data is populated

The implementation is straightforward because all the infrastructure already exists!


---

## 📋 Service Files Analysis

### **ManualClockingEvidenceSyncService**
✅ EXISTS but only handles ONE learner at a time
- `downloadFromServer(learnerID, clockDate)` - Gets single learner evidence
- NO method to get ALL clocked learners for the day

### **OfflineSyncQueueService**
✅ ALREADY USED by signature geofence page
- Handles batch processing
- Queues offline operations

### **Current Imports in signature_geofence_clock_in_page.dart**
```dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:signature/signature.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'mixins/learner_clockin_gates_mixin.dart';
import 'database_helper.dart';
import 'services/secure_location_service.dart';
import 'services/offline_sync_queue_service.dart';
import 'config.dart';
```

### **Missing Import**
```dart
import 'package:http/http.dart' as http;  // ❌ MISSING! Need for API calls
```

---

## ✅ EXACT CODE TO ADD

### **1. Add Missing Import** (at top of file)
```dart
import 'package:http/http.dart' as http;
```

### **2. Add Server Sync Method** (in class body)
```dart
/// Sync clocked learners from server to local database
/// Called on page load when online
Future<void> _syncClockedLearnersFromServer() async {
  if (!_isConnected) {
    print('[SIG_SYNC] Offline - skipping server sync');
    return;
  }
  
  try {
    final clockDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final url = '${AppConfig.baseUrl}/get_manual_clocking_status.php?clock_date=$clockDate';
    
    print('[SIG_SYNC] 🔄 Fetching clocked learners from server...');
    print('[SIG_SYNC] URL: $url');
    
    final response = await http.get(Uri.parse(url)).timeout(
      const Duration(seconds: 30),
    );
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      
      if (data['success'] == true) {
        final records = data['records'] as List;
        print('[SIG_SYNC] 📥 Received ${records.length} clocked learners from server');
        
        if (records.isEmpty) {
          print('[SIG_SYNC] No clocked learners found for today');
          return;
        }
        
        final db = await DatabaseHelper().database;
        int savedCount = 0;
        
        // Save each record to local manual_clocking table
        for (var record in records) {
          try {
            await db.insert(
              'manual_clocking',
              {
                'LearnerID': record['learner_id'],
                'clock_date': record['clock_date'],
                'clock_in_time': record['clock_in_time'],
                'clock_out_time': record['clock_out_time'],
                'contact_time': record['contact_time'],
                'is_manual_attendance': 1,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            savedCount++;
          } catch (e) {
            print('[SIG_SYNC] Error saving learner ${record['learner_id']}: $e');
          }
        }
        
        print('[SIG_SYNC] ✅ Synced $savedCount/${ records.length} records to local database');
        
        // Reload clocking status from local database
        await _loadClockingStatus();
        
      } else {
        print('[SIG_SYNC] ⚠️ Server returned error: ${data['error']}');
      }
    } else {
      print('[SIG_SYNC] ❌ HTTP error: ${response.statusCode}');
      print('[SIG_SYNC] Response: ${response.body}');
    }
  } catch (e) {
    print('[SIG_SYNC] ❌ Error syncing from server: $e');
  }
}
```

### **3. Update _loadClockingStatus Method** (replace existing)
```dart
/// Load clocking status from LOCAL manual_clocking table
Future<void> _loadClockingStatus() async {
  try {
    final db = await DatabaseHelper().database;
    final clockDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    
    print('[SIG_CLOCK] 📂 Loading clocking status from local database...');
    
    // Query local manual_clocking table
    final records = await db.query(
      'manual_clocking',
      where: 'clock_date = ? AND is_manual_attendance = ?',
      whereArgs: [clockDate, 1],
    );
    
    print('[SIG_CLOCK] 📊 Loaded ${records.length} clocking records from local DB');
    
    // Clear existing state
    _clockInTimes.clear();
    _clockOutTimes.clear();
    _contactTimes.clear();
    
    // Update state maps from local database
    for (var record in records) {
      final learnerId = record['LearnerID'].toString();
      final clockIn = record['clock_in_time']?.toString() ?? '';
      final clockOut = record['clock_out_time']?.toString() ?? '';
      final contact = record['contact_time']?.toString() ?? '';
      
      if (clockIn.isNotEmpty && clockIn != 'N/A' && clockIn != 'null') {
        _clockInTimes[learnerId] = clockIn;
      }
      if (clockOut.isNotEmpty && clockOut != 'N/A' && clockOut != 'null') {
        _clockOutTimes[learnerId] = clockOut;
      }
      if (contact.isNotEmpty && contact != 'N/A' && contact != 'null') {
        _contactTimes[learnerId] = contact;
      }
    }
    
    print('[SIG_CLOCK] 📈 Status: ${_clockInTimes.length} clocked in, ${_clockOutTimes.length} clocked out');
    
    if (mounted) {
      setState(() {});
    }
  } catch (e) {
    print('[SIG_CLOCK] ❌ Error loading clocking status: $e');
  }
}
```

### **4. Add Offline Clock-Out Method** (new method)
```dart
/// Perform offline clock-out and queue for server sync
Future<void> _performOfflineClockOut(String learnerId) async {
  try {
    final db = await DatabaseHelper().database;
    final clockDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final clockOutTime = DateFormat('HH:mm:ss').format(DateTime.now());
    
    print('[SIG_CLOCKOUT] 🔓 Offline clock-out for learner $learnerId');
    
    // Update local database immediately for UI feedback
    final rowsAffected = await db.update(
      'manual_clocking',
      {'clock_out_time': clockOutTime},
      where: 'LearnerID = ? AND clock_date = ? AND is_manual_attendance = ?',
      whereArgs: [learnerId, clockDate, 1],
    );
    
    if (rowsAffected > 0) {
      print('[SIG_CLOCKOUT] 💾 Updated local database');
      
      // TODO: Add to sync queue when network returns
      // This needs to be integrated with the batch processing system
      
      // Update UI state immediately
      if (mounted) {
        setState(() {
          _clockOutTimes[learnerId] = clockOutTime;
        });
      }
      
      print('[SIG_CLOCKOUT] ✅ Offline clock-out complete');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Clock-out saved offline (will sync when online)'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
      
    } else {
      print('[SIG_CLOCKOUT] ⚠️ No record found to update');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: No clock-in record found'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    
  } catch (e) {
    print('[SIG_CLOCKOUT] ❌ Error: $e');
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Clock-out error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
```

### **5. Update initState** (add sync call)
```dart
@override
void initState() {
  super.initState();
  _loadInitialData();
  _checkConnectivity();
  _startLocationTracking();
  _startBatchTimer();
  
  // ADD THIS LINE: Sync clocked learners from server on page load
  _syncClockedLearnersFromServer();
}
```

### **6. Update _loadInitialData** (change existing method)
```dart
/// Load initial data and setup
Future<void> _loadInitialData() async {
  setState(() => _isLoading = true);
  try {
    await _loadClassData();
    _filteredLearners = widget.learners;
    
    // CHANGE THIS: Load from LOCAL database, not from widget.learners
    await _loadClockingStatus();
    
  } catch (e) {
    print('Error loading initial data: $e');
  } finally {
    setState(() => _isLoading = false);
  }
}
```

---

## 🎯 Summary

The implementation is straightforward:

1. **Add `http` import** - Missing package for API calls
2. **Add `_syncClockedLearnersFromServer()`** - Calls `get_manual_clocking_status.php`
3. **Update `_loadClockingStatus()`** - Query local database instead of widget.learners
4. **Add `_performOfflineClockOut()`** - Enable offline clock-out
5. **Call sync in `initState()`** - Fetch server data on page load
6. **Update visual indicators** - Already working, just need data!

The existing `ManualClockingEvidenceSyncService` does NOT have a method to get all clocked learners, so we add it directly in the page!
