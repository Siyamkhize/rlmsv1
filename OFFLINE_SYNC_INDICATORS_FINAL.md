# Offline Sync Indicators - FINAL IMPLEMENTATION

## Overview
Visual indicators showing sync status for manual clock-ins:
- **🟢 GREEN** = Data synced to server (in MySQL)
- **🟠 ORANGE** = Data offline only (in SQLite, not yet on server)

## How It Works

### Sync Detection Logic
```
1. Page loads → Fetch clocking status from server
2. Server returns all learners with clock-ins (in MySQL)
3. Mark those learners as SYNCED (_unsyncedLearners[id] = false)
4. Query local SQLite manual_clocking table
5. Any learner in local DB but NOT in server response = UNSYNCED (orange)
6. Display icons accordingly
```

### Code Flow
```dart
_fetchClockingDataFromServer() {
  // Fetch from server
  for (record in serverResponse['records']) {
    _unsyncedLearners[learnerID] = false; // GREEN - on server
  }
}

_checkUnsyncedRecords() {
  // Check local DB
  for (record in localRecords) {
    if (!_unsyncedLearners.containsKey(learnerID)) {
      _unsyncedLearners[learnerID] = true; // ORANGE - not on server
    }
  }
}
```

## Visual Indicators

### Avatar Icon
```dart
CircleAvatar(
  backgroundColor: isClockedIn 
    ? (isUnsynced ? Colors.orange : Colors.green)  // Orange if offline
    : Colors.orange,
  child: Icon(
    isClockedIn 
      ? (isUnsynced ? Icons.cloud_off : Icons.cloud_done)  // Different icons
      : Icons.person,
  ),
)
```

### Clock-In Time Badge
```dart
// UNSYNCED (Orange)
Text('In: 10:46:02', color: Colors.orange)
Icon(Icons.sync, color: Colors.orange)
Text('Needs sync', style: italic)

// SYNCED (Green)
Text('In: 10:46:02', color: Colors.green)
Icon(Icons.cloud_done, color: Colors.green)
Text('Synced')
```

## Test Scenarios

### Scenario 1: Online Clock-In
```
1. Learner clocks in while ONLINE
2. Data goes directly to server (MySQL)
3. Server response includes this learner
4. _unsyncedLearners[id] = false
5. Icon: 🟢 GREEN with cloud_done
6. Badge: "Synced"
```

### Scenario 2: Offline Clock-In
```
1. Learner clocks in while OFFLINE
2. Data saved to local SQLite only
3. Server response does NOT include this learner
4. _checkUnsyncedRecords() finds learner in local DB
5. _unsyncedLearners[id] = true
6. Icon: 🟠 ORANGE with cloud_off
7. Badge: "Needs sync"
```

### Scenario 3: After Sync
```
1. Learner was offline (orange indicator)
2. Network restored, sync runs
3. Data uploaded to server
4. Next page refresh/reload
5. Server response now includes learner
6. _unsyncedLearners[id] = false
7. Icon: 🟢 GREEN (changed from orange)
```

## Database Tables

### Local (SQLite)
```sql
-- manual_clocking table
SELECT LearnerID, clock_in_time, clock_date, synced
FROM manual_clocking
WHERE clock_date = '2026-10-16';

-- Unsynced records (will show orange)
SELECT LearnerID FROM manual_clocking 
WHERE clock_date = '2026-10-16' 
  AND LearnerID NOT IN (
    -- Learners returned by server endpoint
  );
```

### Server (MySQL)
```sql
-- Server query (in get_manual_clocking_status.php)
SELECT ld.LearnerID, mc.clock_in_time
FROM learnerdetails ld
LEFT JOIN manual_clocking mc 
  ON ld.LearnerID = mc.LearnerID 
  AND mc.clock_date = ?
WHERE ld.classID = ?;

-- Only learners with clock_in_time are synced (green)
```

## Sync States Explained

| State | Local DB | Server DB | Icon Color | Meaning |
|-------|----------|-----------|------------|---------|
| **Not Clocked In** | ❌ No | ❌ No | Orange | No record |
| **Offline Clock-In** | ✅ Yes | ❌ No | **Orange** 🟠 | Needs sync |
| **Online Clock-In** | ✅ Yes | ✅ Yes | **Green** 🟢 | Synced |
| **After Sync** | ✅ Yes | ✅ Yes | **Green** 🟢 | Synced |

## Key Functions

### 1. Server Fetch
```dart
Future<void> _fetchClockingDataFromServer() {
  // Mark server learners as synced (GREEN)
  for (record in result['records']) {
    if (clockInTime.isNotEmpty) {
      _unsyncedLearners[learnerID] = false; // ← GREEN
    }
  }
}
```

### 2. Local Check
```dart
Future<void> _checkUnsyncedRecords() {
  // Find learners in local DB but not on server
  for (record in localRecords) {
    if (!_unsyncedLearners.containsKey(learnerID)) {
      _unsyncedLearners[learnerID] = true; // ← ORANGE
    }
  }
}
```

### 3. After Successful Online Clock-In
```dart
setState(() {
  clockInTimes[learnerID] = clockInTime;
  _unsyncedLearners.remove(learnerID); // ← Remove = GREEN
});
```

### 4. After Offline Clock-In
```dart
setState(() {
  clockInTimes[learnerID] = clockInTime;
  _unsyncedLearners[learnerID] = true; // ← Mark as ORANGE
});
```

## User Experience

### What User Sees

**Synced Learner (GREEN):**
```
┌─────────────────────────────────────┐
│ 🟢  Siyabonga Mkhize           │
│     ID: 9502195714080              │
│     In: 10:46:02 ☁️✓ Synced       │
└─────────────────────────────────────┘
```

**Unsynced Learner (ORANGE):**
```
┌─────────────────────────────────────┐
│ 🟠  John Doe                   │
│     ID: 9501011234567              │
│     In: 09:30:15 🔄 Needs sync    │
└─────────────────────────────────────┘
```

## Troubleshooting

### All Icons Show Orange
- **Cause**: Device offline OR server endpoint not responding
- **Check**: Network connection, server status
- **Action**: Wait for network, data is safe in local DB

### Some Orange, Some Green (Mixed)
- **Normal**: Some learners clocked in offline, others online
- **Action**: Orange ones will sync when network is stable

### Icon Won't Turn Green After Sync
- **Cause**: Page not refreshed after sync
- **Action**: Pull-to-refresh to reload status from server

## Technical Details

- **Endpoint**: `mobile/get_manual_clocking_status.php`
- **Local Table**: `manual_clocking` (SQLite)
- **Server Table**: `manual_clocking` (MySQL)
- **Sync Service**: `comprehensive_manual_clocking_sync.dart`
- **UI Update**: Automatic via `setState()`

## APK Details
- **File**: app-release.apk (71.5MB)
- **Build Time**: ~190 seconds
- **Device**: RZ8X306F7TZ
- **Status**: Successfully installed

## Status
✅ Server fetch marks learners as synced (green)
✅ Local check identifies offline-only learners (orange)
✅ UI shows correct colors and badges
✅ State updates after clock-in and sync
✅ APK built and installed

---
**Key Point**: Orange means "waiting to sync to server" - data is safe locally
Date: 2026-10-15
