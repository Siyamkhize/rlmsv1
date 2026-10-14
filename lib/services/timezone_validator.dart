import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:app_settings/app_settings.dart';

/// Service to validate device timezone against server and block clock-in if wrong
class TimezoneValidator {
  /// Expected timezone for South Africa
  static const String expectedTimezone = 'Africa/Johannesburg';
  static const String expectedTimezoneAbbr = 'SAST';
  static const int expectedUtcOffsetHours = 2;
  static const int toleranceMinutes = 5; // ±5 minutes allowed difference

  /// Blocking method that ensures device time is correct before allowing clock-in
  /// Returns true if time is correct, false if user cancelled
  /// Loops until time is verified or user cancels
  static Future<bool> ensureCorrectTime(BuildContext context) async {
    while (true) {
      // Verify against server
      final validation = await _verifyTimeWithServer();

      if (validation['isCorrect'] == true) {
        // Time is correct, allow clock-in
        if (kDebugMode) {
          print('✓ Device time verified correct');
        }
        return true;
      }

      // Time is wrong - show blocking dialog
      if (context.mounted) {
        final result = await _showBlockingDialog(context, validation);
        
        if (result == _DialogAction.cancel) {
          // User cancelled, block clock-in
          if (kDebugMode) {
            print('✗ User cancelled clock-in due to wrong time');
          }
          return false;
        } else if (result == _DialogAction.openSettings) {
          // Open device Date & Time settings
          if (kDebugMode) {
            print('→ Opening device Date & Time settings');
          }
          await AppSettings.openAppSettings(type: AppSettingsType.date);
          // Loop continues - will check again
        } else if (result == _DialogAction.checkAgain) {
          // User wants to check again - loop continues
          if (kDebugMode) {
            print('↻ Checking device time again');
          }
        }
      } else {
        // Context not mounted - cannot show dialog, block clock-in
        return false;
      }
    }
  }

  /// Verify device time against server time
  /// SECURITY: Compares UTC timestamps to prevent timezone manipulation
  static Future<Map<String, dynamic>> _verifyTimeWithServer() async {
    try {
      final response = await http.get(
        Uri.parse('https://learnersmanagementsys.co.za/mobile/get_server_time.php'),
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['success'] == true) {
          // IMPORTANT: Compare UTC timestamps only (not local times)
          // This prevents false positives when device timezone differs from server
          final serverTimeUtc = DateTime.parse(data['server_time_utc']);
          final deviceTimeUtc = DateTime.now().toUtc(); // Convert device time to UTC
          final difference = deviceTimeUtc.difference(serverTimeUtc).abs();

          final isCorrect = difference.inMinutes <= toleranceMinutes;

          if (kDebugMode) {
            print('=== TIME VERIFICATION (UTC) ===');
            print('Server Time (UTC): ${serverTimeUtc.toIso8601String()}');
            print('Device Time (UTC): ${deviceTimeUtc.toIso8601String()}');
            print('Device Timezone Offset: ${DateTime.now().timeZoneOffset}');
            print('Difference: ${difference.inMinutes} minutes');
            print('Tolerance: ±$toleranceMinutes minutes');
            print('Is Correct: $isCorrect');
            print('================================');
          }

          return {
            'isCorrect': isCorrect,
            'serverTime': serverTimeUtc, // Store UTC time for display
            'deviceTime': deviceTimeUtc, // Store UTC time for display
            'differenceMinutes': difference.inMinutes,
            'differenceSeconds': difference.inSeconds,
            'timezone': data['timezone_local'] ?? 'UTC',
            'error': null,
          };
        }
      }

      // Server returned error
      return {
        'isCorrect': false,
        'error': 'Server returned invalid response',
        'deviceTime': DateTime.now().toUtc(),
      };

    } catch (e) {
      if (kDebugMode) {
        print('ERROR verifying time with server: $e');
      }
      
      // Fallback to local timezone check if server is unreachable
      return _fallbackLocalTimezoneCheck();
    }
  }

  /// Fallback to local timezone validation if server is unreachable
  static Map<String, dynamic> _fallbackLocalTimezoneCheck() {
    final now = DateTime.now();
    final offsetMinutes = now.timeZoneOffset.inMinutes;
    final offsetHours = offsetMinutes / 60;
    final timezoneName = now.timeZoneName;

    final bool isCorrectOffset = offsetHours == expectedUtcOffsetHours;
    final bool isLikelyCorrectTimezone = 
        timezoneName.contains('SAST') || 
        timezoneName.contains('CAT') ||
        timezoneName.contains('+02');

    final isCorrect = isCorrectOffset && isLikelyCorrectTimezone;

    if (kDebugMode) {
      print('=== FALLBACK TIMEZONE CHECK ===');
      print('Device Time: ${now.toString()}');
      print('Timezone: $timezoneName');
      print('UTC Offset: ${offsetHours > 0 ? "+$offsetHours" : offsetHours} hours');
      print('Expected: $expectedTimezoneAbbr (UTC+$expectedUtcOffsetHours)');
      print('Is Correct: $isCorrect');
      print('==============================');
    }

    return {
      'isCorrect': isCorrect,
      'deviceTime': now,
      'deviceTimezone': timezoneName,
      'utcOffsetHours': offsetHours,
      'error': 'Could not verify with server - using local timezone check',
    };
  }

  /// Show blocking dialog that prevents clock-in until time is fixed
  static Future<_DialogAction?> _showBlockingDialog(
    BuildContext context, 
    Map<String, dynamic> validation,
  ) async {
    return await showDialog<_DialogAction>(
      context: context,
      barrierDismissible: false, // Cannot tap outside to dismiss
      builder: (context) => PopScope(
        canPop: false, // Prevent back button from dismissing
        child: AlertDialog(
          title: Row(
            children: [
              Icon(Icons.block, color: Colors.red[700], size: 28),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Clock-in Blocked',
                  style: TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your device time is incorrect. You must fix it before clocking in.',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.red[900],
                  ),
                ),
                SizedBox(height: 16),
                
                // Show the time difference
                if (validation['serverTime'] != null) ...[
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTimeRow(
                          'Server Time (UTC):',
                          _formatDateTime(validation['serverTime']),
                          Colors.green[700]!,
                        ),
                        SizedBox(height: 8),
                        _buildTimeRow(
                          'Your Device Time (UTC):',
                          _formatDateTime(validation['deviceTime']),
                          Colors.red[700]!,
                        ),
                        SizedBox(height: 8),
                        Divider(),
                        SizedBox(height: 8),
                        Text(
                          'Difference: ${validation['differenceMinutes']} minutes',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange[900],
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (validation['deviceTimezone'] != null) ...[
                  // Fallback display for local timezone check
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTimeRow(
                          'Your Timezone:',
                          validation['deviceTimezone'],
                          Colors.red[700]!,
                        ),
                        SizedBox(height: 8),
                        _buildTimeRow(
                          'Expected Timezone:',
                          'SAST (UTC+2)',
                          Colors.green[700]!,
                        ),
                      ],
                    ),
                  ),
                ],
                
                SizedBox(height: 16),
                
                // Instructions
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, size: 20, color: Colors.blue[700]),
                          SizedBox(width: 8),
                          Text(
                            'How to fix:',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[900],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        '1. Tap "Open Date & Time Settings" below\n'
                        '2. Enable "Automatic date & time"\n'
                        '3. Enable "Automatic time zone"\n'
                        '4. Come back and tap "Check Again"',
                        style: TextStyle(fontSize: 12, color: Colors.blue[900]),
                      ),
                    ],
                  ),
                ),
                
                if (validation['error'] != null) ...[
                  SizedBox(height: 12),
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber, size: 16, color: Colors.orange[700]),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            validation['error'],
                            style: TextStyle(fontSize: 10, color: Colors.orange[900]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            // Cancel button
            TextButton(
              onPressed: () => Navigator.of(context).pop(_DialogAction.cancel),
              child: Text(
                'Cancel Clock-in',
                style: TextStyle(color: Colors.grey[700]),
              ),
            ),
            
            // Open Settings button
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(_DialogAction.openSettings),
              icon: Icon(Icons.settings, size: 18),
              label: Text('Open Date & Time Settings'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[700],
                foregroundColor: Colors.white,
              ),
            ),
            
            // Check Again button
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(_DialogAction.checkAgain),
              icon: Icon(Icons.refresh, size: 18),
              label: Text('Check Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
                foregroundColor: Colors.white,
              ),
            ),
          ],
          actionsAlignment: MainAxisAlignment.spaceBetween,
        ),
      ),
    );
  }

  static Widget _buildTimeRow(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.grey[700],
          ),
        ),
        SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  static String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
           '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }
}

/// Dialog action enum
enum _DialogAction {
  cancel,
  openSettings,
  checkAgain,
}
