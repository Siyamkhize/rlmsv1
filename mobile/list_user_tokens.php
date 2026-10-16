<?php
/**
 * List All Tokens for User 148
 */

require_once __DIR__ . '/connection.php';

$user_id = 148;

echo "=== TOKENS FOR USER $user_id ===\n\n";

$stmt = $conn->prepare("
    SELECT 
        token_hash,
        user_id,
        user_role,
        created_at,
        expires_at,
        revoked_at,
        last_used_at,
        expires_at > NOW() as is_valid,
        revoked_at IS NULL as is_active
    FROM auth_tokens 
    WHERE user_id = ?
    ORDER BY created_at DESC
");
$stmt->bind_param("i", $user_id);
$stmt->execute();
$result = $stmt->get_result();

if ($result->num_rows === 0) {
    echo "❌ No tokens found for user $user_id\n";
    $stmt->close();
    $conn->close();
    exit(1);
}

echo "Found " . $result->num_rows . " token(s):\n";
echo "─────────────────────────────────────────────────────────────\n\n";

$count = 1;
while ($row = $result->fetch_assoc()) {
    echo "Token #$count:\n";
    echo "  Hash: " . $row['token_hash'] . "\n";
    echo "  User Role: " . $row['user_role'] . "\n";
    echo "  Created: " . $row['created_at'] . "\n";
    echo "  Expires: " . $row['expires_at'] . "\n";
    echo "  Last Used: " . ($row['last_used_at'] ?? 'Never') . "\n";
    echo "  Revoked: " . ($row['revoked_at'] ?? 'No') . "\n";
    echo "  Valid: " . ($row['is_valid'] ? '✅ Yes' : '❌ No (Expired)') . "\n";
    echo "  Active: " . ($row['is_active'] ? '✅ Yes' : '❌ No (Revoked)') . "\n";
    
    if ($row['is_valid'] && $row['is_active']) {
        echo "  Status: ✅ USABLE\n";
    } else {
        echo "  Status: ❌ UNUSABLE\n";
    }
    
    echo "\n";
    $count++;
}

$stmt->close();
$conn->close();
?>
