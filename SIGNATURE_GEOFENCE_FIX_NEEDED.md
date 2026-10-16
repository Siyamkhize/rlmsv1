# Signature Geofence Clock-In Page - Fixes Needed

## Issues Identified

1. **Geofence not working** - "Outside designated area" showing when at correct location
2. **Clocking records not showing** - Learners with clock-in status not displaying  
3. **UI doesn't match screenshot** - Missing green banner with GPS distance, wrong avatar colors

## Root Causes

### 1. Wrong Table Name in SQL Query
The `_loadClassData()` method is querying the wrong table:
- **Wrong**: `LEFT JOIN site s ON c.siteID = s.SiteID`
- **Correct**: `LEFT JOIN sites s ON c.siteID = s.SiteID` (plural)

This causes the site coordinates to be NULL, so geofence check always fails.

### 2. Missing Site Coordinate Loading
The current version doesn't properly load site coordinates from the `sites` table joined with `class` table.

### 3. UI Status Banner Missing
The green/red status banner with GPS distance is not implemented.

### 4. Avatar Colors Wrong
- Screenshot shows: ORANGE avatars for available learners
- Current code shows: GREEN avatars

## Required Fixes

### Fix 1: Update _loadClassData() Method
```dart
Future<void> _loadClassData() async {
  try {
    final db = await DatabaseHelper().database;
    
    // Get site coordinates from class -> sites join (NOTE: 'sites' is PLURAL!)
    final classData = await db.rawQuery('''
      SELECT c.*, s.Latitude as site_lat, s.Longitude as site_lon
      FROM class c
      LEFT JOIN sites s ON c.siteID = s.SiteID
      WHERE c.classID = ?
      LIMIT 1
    ''', [widget.classID]);

    if (classData.isNotEmpty) {
      final classInfo = classData.first;
      final lat = classInfo['site_lat']?.toString() ?? '0';
      final lon = classInfo['site_lon']?.toString() ?? '0';
      
      _siteLat = double.tryParse(lat);
      _siteLon = double.tryParse(lon);
      
      print('[SIG_CLOCK] Loaded site coordinates: lat=$_siteLat, lon=$_siteLon');
      
      // Check geofence immediately after loading coordinates
      if (_currentPosition != null) {
        _checkGeofence();
      }
    } else {
      print('[SIG_CLOCK] No class data found for classID: ${widget.classID}');
    }
  } catch (e) {
    print('[SIG_CLOCK] Error loading class data: $e');
  }
}
```

### Fix 2: Add Debug Logging to _checkGeofence()
```dart
void _checkGeofence() {
  if (_currentPosition != null && _siteLat != null && _siteLon != null) {
    double distance = Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      _siteLat!,
      _siteLon!,
    );
    
    print('[SIG_CLOCK] Geofence check - Distance: ${distance.toStringAsFixed(1)}m from site');
    
    setState(() {
      _isWithinGeofence = distance <= 100; // 100 meter geofence
    });
    
    print('[SIG_CLOCK] Within geofence: $_isWithinGeofence');
  } else {
    print('[SIG_CLOCK] Cannot check geofence - Missing data: position=$_currentPosition, siteLat=$_siteLat, siteLon=$_siteLon');
  }
}
```

### Fix 3: Update UI with Green Status Banner
Replace the simple error banner with an always-visible status banner:
```dart
// Geofence status banner (always show - matching screenshot)
Container(
  width: double.infinity,
  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  color: _isWithinGeofence ? Colors.green[50] : Colors.red[50],
  child: Row(
    children: [
      Icon(
        _isWithinGeofence ? Icons.location_on : Icons.location_off, 
        color: _isWithinGeofence ? Colors.green[700] : Colors.red[700],
        size: 20,
      ),
      SizedBox(width: 8),
      Expanded(
        child: Text(
          _isWithinGeofence 
              ? 'Within site range (${distanceFromSite?.toStringAsFixed(0) ?? 0}m)'
              : 'Outside designated area',
          style: TextStyle(
            color: _isWithinGeofence ? Colors.green[900] : Colors.red[900],
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      if (distanceFromSite != null)
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isWithinGeofence ? Colors.green[300]! : Colors.red[300]!,
            ),
          ),
          child: Text(
            'GPS: ${distanceFromSite.toStringAsFixed(1)}m',
            style: TextStyle(
              color: _isWithinGeofence ? Colors.green[900] : Colors.red[900],
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
    ],
  ),
),
```

### Fix 4: Change Avatar Colors to ORANGE
Change line determining avatar color for available learners:
```dart
// Available - orange (matching screenshot)
avatarColor = Colors.orange[700]!;
```

## Testing Steps After Fix

1. Build and install APK: `flutter build apk --release`
2. Open Signature Geofence Clock-In page
3. **Verify green banner** shows "Within site range (Xm)" with GPS distance
4. **Verify learner list** shows ALL learners with proper colors:
   - 🟠 ORANGE = Available (not clocked in)
   - 🔴 RED = Clocked in (shows time)
   - ⚫ GREY = Completed (clocked in & out)
5. **Test offline**: Enable airplane mode, verify data loads from local database
6. **Test clock-in**: Tap learner, complete signature, verify status updates

## Files to Modify

- `lib/signature_geofence_clock_in_page.dart`

## Status

❌ NOT APPLIED - File was restored to old version, fixes need to be reapplied manually
