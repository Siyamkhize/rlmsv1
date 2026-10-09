<?php
/**
 * Server-side geofence verification for secure clock-in/out.
 * Receives position audit data from the app and independently verifies
 * the learner is within the allowed radius of the class site.
 */

require_once __DIR__ . '/security_functions.php';
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    echo json_encode(['success' => false, 'error' => 'POST required']);
    exit;
}

$response = ['success' => false, 'error' => 'Unknown error'];

try {
    $input = json_decode(file_get_contents('php://input'), true);
    if (!$input) {
        $response['error'] = 'Invalid JSON body';
        echo json_encode($response);
        exit;
    }

    $userType = $input['user_type'] ?? 'learner'; // Default to learner for backward compatibility
    $userId = $input['user_id'] ?? '';
    $learnerId = $input['learner_id'] ?? '';
    $classId = $input['class_id'] ?? '';
    $action = $input['action'] ?? 'clock_in';
    $auditData = $input['audit_data'] ?? [];

    // For learners: require learner_id and class_id
    // For facilitators: require user_id
    if ($userType === 'facilitator') {
        if (empty($userId)) {
            $response['error'] = 'Missing user_id for facilitator';
            echo json_encode($response);
            exit;
        }
    } else {
        // Default to learner flow - requires learner_id and class_id
        if (empty($learnerId) || empty($classId)) {
            $response['error'] = 'Missing learner_id or class_id';
            echo json_encode($response);
            exit;
        }
    }

    // Reject if mock location was detected
    if (!empty($auditData['is_mocked'])) {
        $response['error'] = 'Mock location detected';
        echo json_encode($response);
        exit;
    }

    // Reject if sanity check failed (impossible movement)
    if (isset($auditData['passed_sanity']) && !$auditData['passed_sanity']) {
        $response['error'] = 'Suspicious movement detected';
        echo json_encode($response);
        exit;
    }

    // Get user's latitude/longitude from audit_data OR from body
    $userLat = floatval($auditData['latitude'] ?? ($input['latitude'] ?? 0));
    $userLon = floatval($auditData['longitude'] ?? ($input['longitude'] ?? 0));
    $userAccuracy = floatval($auditData['accuracy'] ?? ($input['accuracy'] ?? 999));

    // Max 60m accuracy allowed
    if ($userAccuracy > 60) {
        $response['error'] = 'GPS accuracy too low';
        echo json_encode($response);
        exit;
    }

    include __DIR__ . '/connection.php';
    if (!isset($conn)) {
        $response['error'] = 'Database connection failed';
        echo json_encode($response);
        exit;
    }

    // Get site coordinates
    if ($userType === 'facilitator') {
        // For facilitators: look up their site from facilitator table
        $stmt = $conn->prepare(
            "SELECT s.latitude, s.longitude, s.siteName 
             FROM facilitator f
             JOIN sites s ON f.siteID = s.siteID 
             WHERE f.FacilitatorID = ? LIMIT 1"
        );
        $stmt->bind_param("s", $userId);
    } else {
        // For learners: look up site from their class
        $stmt = $conn->prepare(
            "SELECT s.latitude, s.longitude, s.siteName 
             FROM class c 
             JOIN sites s ON c.siteID = s.siteID 
             WHERE c.classID = ? LIMIT 1"
        );
        $stmt->bind_param("s", $classId);
    }
    
    $stmt->execute();
    $result = $stmt->get_result();

    if ($result->num_rows === 0) {
        $response['error'] = $userType === 'facilitator' 
            ? 'Site coordinates not found for facilitator' 
            : 'Site coordinates not found for class';
        echo json_encode($response);
        exit;
    }

    $row = $result->fetch_assoc();
    $siteLat = floatval($row['latitude'] ?? 0);
    $siteLon = floatval($row['longitude'] ?? 0);
    $siteName = $row['siteName'] ?? 'Site';

    $stmt->close();

    if ($siteLat == 0 && $siteLon == 0) {
        $response['error'] = 'Invalid site coordinates';
        echo json_encode($response);
        exit;
    }

    // Haversine distance (meters)
    $earthRadius = 6371000;
    $lat1 = deg2rad($userLat);
    $lat2 = deg2rad($siteLat);
    $deltaLat = deg2rad($siteLat - $userLat);
    $deltaLon = deg2rad($siteLon - $userLon);
    $a = sin($deltaLat / 2) ** 2 + cos($lat1) * cos($lat2) * sin($deltaLon / 2) ** 2;
    $c = 2 * atan2(sqrt($a), sqrt(1 - $a));
    $distance = $earthRadius * $c;

    // Dynamic geofence with 60m cap: min(50m + accuracy, 60m)
    $geofenceRadius = 50.0;
    $maxAllowedRadius = 60.0;
    $calculatedRadius = $geofenceRadius + $userAccuracy;
    $effectiveRadius = min($calculatedRadius, $maxAllowedRadius);

    if ($distance <= $effectiveRadius) {
        $response = [
            'success' => true,
            'distance' => round($distance, 2),
            'site' => $siteName,
            'effective_radius' => round($effectiveRadius, 1),
            'calculated_radius' => round($calculatedRadius, 1),
            'capped' => $calculatedRadius > $maxAllowedRadius,
        ];
    } else {
        $response['error'] = "You are " . round($distance) . "m from $siteName. Must be within " . round($effectiveRadius) . "m.";
        $response['distance'] = round($distance, 2);
        $response['effective_radius'] = round($effectiveRadius, 1);
    }

    echo json_encode($response);
} catch (Exception $e) {
    error_log('verify_geofence.php error: ' . $e->getMessage());
    echo json_encode([
        'success' => false,
        'error' => 'Server error',
    ]);
}
