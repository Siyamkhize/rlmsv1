<?php
/**
 * Update learner location data for learners 6246 and 11443
 * Sets Province, District, Municipality to allow clock-in
 */

require 'connection.php';

$learners = ['6246', '11443'];

// First, check available provinces
$provinces_query = "SELECT DISTINCT province_name FROM province ORDER BY province_name LIMIT 5";
$provinces_result = $conn->query($provinces_query);

echo "Available provinces:\n";
if ($provinces_result && $provinces_result->num_rows > 0) {
    while ($prov = $provinces_result->fetch_assoc()) {
        echo "  - " . $prov['province_name'] . "\n";
    }
}

echo "\n";

// Set default location values
$default_province = 'Gauteng';
$default_district = 'Johannesburg';
$default_municipality = 'City of Johannesburg';

foreach ($learners as $learner_id) {
    echo "Updating Learner $learner_id...\n";
    
    $stmt = $conn->prepare("
        UPDATE learnerdetails 
        SET Province = ?, District = ?, Municipality = ?
        WHERE LearnerID = ?
    ");
    
    $stmt->bind_param('ssss', $default_province, $default_district, $default_municipality, $learner_id);
    
    if ($stmt->execute()) {
        echo "  ✓ Updated successfully\n";
        echo "    Province: $default_province\n";
        echo "    District: $default_district\n";
        echo "    Municipality: $default_municipality\n";
    } else {
        echo "  ✗ Failed: " . $stmt->error . "\n";
    }
    
    $stmt->close();
    echo "\n";
}

// Verify the updates
echo "Verification:\n";
foreach ($learners as $learner_id) {
    $stmt = $conn->prepare('SELECT LearnerID, Province, District, Municipality FROM learnerdetails WHERE LearnerID = ?');
    $stmt->bind_param('s', $learner_id);
    $stmt->execute();
    $result = $stmt->get_result();
    
    if ($row = $result->fetch_assoc()) {
        echo "Learner {$row['LearnerID']}:\n";
        echo "  Province: '{$row['Province']}'\n";
        echo "  District: '{$row['District']}'\n";
        echo "  Municipality: '{$row['Municipality']}'\n";
    }
    echo "\n";
}

$conn->close();
echo "Done!\n";
