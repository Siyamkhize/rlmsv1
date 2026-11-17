import 'package:flutter/foundation.dart';
// Test script for enhanced clocking days functionality
// This is a standalone test to verify the server API works

import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  debugPrint('=== Testing Enhanced Clocking Days Count ===\n');

  // Test configuration
  const String baseUrl = 'https://rlms.rlms.co.za/mobile';
  const String testLearnerId = '1'; // Change this to a valid learner ID

  // Test 1: Get clocking days without including today
  debugPrint('Test 1: Get clocking days (excluding today)');
  await testClockingDaysCount(baseUrl, testLearnerId, false);

  debugPrint('\n${'=' * 50}\n');

  // Test 2: Get clocking days including today
  debugPrint('Test 2: Get clocking days (including today)');
  await testClockingDaysCount(baseUrl, testLearnerId, true);

  debugPrint('\n=== Test Complete ===');
}

Future<void> testClockingDaysCount(
    String baseUrl, String learnerId, bool includeToday) async {
  try {
    final url = '$baseUrl/get_clocking_days_count.php';
    final uri = Uri.parse(url).replace(queryParameters: {
      'learner_id': learnerId,
      'include_today': includeToday.toString(),
    });

    debugPrint('Request URL: $uri');

    final response = await http.get(uri).timeout(const Duration(seconds: 10));

    debugPrint('Status Code: ${response.statusCode}');
    debugPrint('Response Body: ${response.body}');

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true) {
        final clockingDays = data['data']['clocking_days'];
        final workingDays = data['data']['working_days'];
        final month = data['data']['month'];

        debugPrint('✅ SUCCESS:');
        debugPrint('  - Learner ID: $learnerId');
        debugPrint('  - Month: $month');
        debugPrint('  - Clocking Days: $clockingDays');
        debugPrint('  - Working Days: $workingDays');
        debugPrint('  - Include Today: $includeToday');
        debugPrint('  - Message: ${data['message']}');
      } else {
        debugPrint('❌ API Error: ${data['error']}');
      }
    } else {
      debugPrint('❌ HTTP Error: ${response.statusCode}');
      debugPrint('Response: ${response.body}');
    }
  } catch (e) {
    debugPrint('❌ Exception: $e');
  }
}
