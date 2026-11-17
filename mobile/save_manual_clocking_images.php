<?php
/**
 * Save Manual Clocking Images (Face Photo + Signature)
 *
 * Saves face photo with watermark and signature image to server
 * Returns filenames to be stored in database
 *
 * ALL-OR-NOTHING: both the face photo and the signature are required.
 * Everything is decoded and validated BEFORE anything is written, and any
 * file written is deleted again if a later step fails.
 * 
 * LAST UPDATED: 2026/11/03 - Added better error handling for HTTP 500 diagnosis
 */

header('Content-Type: application/json');

// Enable comprehensive error logging
error_reporting(E_ALL);
ini_set('display_errors', 0);
ini_set('log_errors', 1);
ini_set('error_log', __DIR__ . '/../../logs/php_errors.log');

// Catch ALL errors and return them as JSON
set_error_handler(function($errno, $errstr, $errfile, $errline) {
    throw new ErrorException($errstr, 0, $errno, $errfile, $errline);
});

// Log the request
error_log("[SAVE_CLOCKING_IMAGES] ========== NEW REQUEST ==========");
error_log("[SAVE_CLOCKING_IMAGES] Time: " . date('Y-m-d H:i:s'));
error_log("[SAVE_CLOCKING_IMAGES] Method: " . ($_SERVER['REQUEST_METHOD'] ?? 'UNKNOWN'));
error_log("[SAVE_CLOCKING_IMAGES] Content-Length: " . ($_SERVER['CONTENT_LENGTH'] ?? '0'));

try {
    error_log("[SAVE_CLOCKING_IMAGES] Including connection.php");
    require_once 'connection.php';
    error_log("[SAVE_CLOCKING_IMAGES] ✅ connection.php loaded");
    
    error_log("[SAVE_CLOCKING_IMAGES] Including require_auth.php");
    require_once 'require_auth.php';
    error_log("[SAVE_CLOCKING_IMAGES] ✅ require_auth.php loaded");
    
    error_log("[SAVE_CLOCKING_IMAGES] Including security_functions.php");
    require_once 'security_functions.php';
    error_log("[SAVE_CLOCKING_IMAGES] ✅ security_functions.php loaded");
} catch (Throwable $e) {
    error_log("[SAVE_CLOCKING_IMAGES] ❌ FATAL: Failed to load required files: " . $e->getMessage());
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'error' => 'Server configuration error',
        'debug' => 'Failed to load: ' . $e->getMessage()
    ]);
    exit;
}

// SECURITY: Require authentication
try {
    error_log("[SAVE_CLOCKING_IMAGES] Calling requireAuth()");
    $user = requireAuth($conn);
    error_log("[SAVE_CLOCKING_IMAGES] ✅ Authentication successful - User ID: " . $user['user_id']);
} catch (Exception $e) {
    error_log("[SAVE_CLOCKING_IMAGES] ❌ Authentication failed: " . $e->getMessage());
    error_log("[SAVE_CLOCKING_IMAGES] ❌ Stack trace: " . $e->getTraceAsString());
    
    // Return HTTP 401 for authentication failures (not 500)
    http_response_code(401);
    echo json_encode([
        'success' => false,
        'error' => 'Authentication required',
        'message' => 'Your session has expired. Please log in again.',
        'auth_error' => true
    ]);
    
    if (isset($conn)) {
        $conn->close();
    }
    exit;
}

// SECURITY: Apply rate limiting (10 image uploads per minute)
try {
    error_log("[SAVE_CLOCKING_IMAGES] Calling applyRateLimit()");
    if (function_exists('applyRateLimit')) {
        applyRateLimit($conn, 'save_clocking_images', 10);
        error_log("[SAVE_CLOCKING_IMAGES] ✅ Rate limit check passed");
    } else {
        error_log("[SAVE_CLOCKING_IMAGES] ⚠️  applyRateLimit() not available, skipping");
    }
} catch (Exception $e) {
    error_log("[SAVE_CLOCKING_IMAGES] ❌ Rate limit exceeded: " . $e->getMessage());
    
    // Return HTTP 429 for rate limit errors (not 500)
    http_response_code(429);
    echo json_encode([
        'success' => false,
        'error' => 'Rate limit exceeded',
        'message' => 'Too many requests. Please wait a moment and try again.',
        'rate_limit_error' => true
    ]);
    
    if (isset($conn)) {
        $conn->close();
    }
    exit;
}

$written = []; // full paths of files written during this request (for cleanup)

try {
    // Get JSON input
    $rawInput = file_get_contents('php://input');
    error_log("[SAVE_CLOCKING_IMAGES] Raw input size: " . strlen($rawInput) . " bytes");
    
    $input = json_decode($rawInput, true);

    if (!$input || !is_array($input)) {
        error_log("[SAVE_CLOCKING_IMAGES] ❌ Invalid JSON input");
        throw new Exception('Invalid JSON input');
    }

    // Required fields
    $learnerID = isset($input['learner_id']) ? intval($input['learner_id']) : 0;
    $clockDate = isset($input['clock_date']) ? $input['clock_date'] : date('Y-m-d');
    $type      = isset($input['type']) ? $input['type'] : ''; // 'in' or 'out'

    // Image data
    $faceImageBase64 = isset($input['face_image']) ? $input['face_image'] : null;
    $signatureBase64 = isset($input['signature_image']) ? $input['signature_image'] : null;

    // Log image sizes
    error_log("[SAVE_CLOCKING_IMAGES] Learner: $learnerID, Date: $clockDate, Type: $type");
    error_log("[SAVE_CLOCKING_IMAGES] Face image length: " . (is_string($faceImageBase64) ? strlen($faceImageBase64) : 'null'));
    error_log("[SAVE_CLOCKING_IMAGES] Signature length: " . (is_string($signatureBase64) ? strlen($signatureBase64) : 'null'));

    // Timestamp for watermark
    $timestamp = isset($input['timestamp']) ? $input['timestamp'] : date('Y-m-d H:i:s');

    // Validation
    if ($learnerID <= 0) {
        throw new Exception('Invalid learner ID');
    }

    if (!in_array($type, ['in', 'out'], true)) {
        throw new Exception('Invalid type. Must be "in" or "out"');
    }

    if (!is_string($clockDate) || !preg_match('/^\d{4}-\d{2}-\d{2}$/', $clockDate)) {
        throw new Exception('Invalid clock date');
    }

    // BOTH images are mandatory
    if (!is_string($faceImageBase64) || trim($faceImageBase64) === '') {
        throw new Exception('Face photo is required');
    }
    if (!is_string($signatureBase64) || trim($signatureBase64) === '') {
        throw new Exception('Signature is required');
    }

    // Define directories BEFORE processing
    $baseDir       = __DIR__; // This is the mobile folder
    $facesDir      = $baseDir . '/manual_clocking_evidence/faces';
    $signaturesDir = $baseDir . '/manual_clocking_evidence/signatures';

    // NOTE: Idempotency check removed - this endpoint is for initial image upload only
    // The clock-in/clock-out endpoints handle idempotency via idempotency_keys table

    // ------------------------------------------------------------------
    // STEP 1: decode and validate BOTH images before writing anything
    // ------------------------------------------------------------------

    // Face
    $faceImageBase64 = preg_replace('/^data:image\/\w+;base64,/', '', $faceImageBase64);
    $faceImageData = base64_decode($faceImageBase64, true); // strict
    if ($faceImageData === false || $faceImageData === '') {
        throw new Exception('Invalid face image data');
    }
    $faceImage = @imagecreatefromstring($faceImageData);
    if ($faceImage === false) {
        throw new Exception('Face image could not be read');
    }

    // Signature
    $signatureBase64 = preg_replace('/^data:image\/\w+;base64,/', '', $signatureBase64);
    $signatureData = base64_decode($signatureBase64, true); // strict
    if ($signatureData === false || $signatureData === '') {
        imagedestroy($faceImage);
        throw new Exception('Invalid signature data');
    }
    $signatureImage = @imagecreatefromstring($signatureData);
    if ($signatureImage === false) {
        imagedestroy($faceImage);
        throw new Exception('Signature image could not be read');
    }

    // ------------------------------------------------------------------
    // STEP 2: prepare folders
    // ------------------------------------------------------------------
    // Directories already defined above before idempotency check

    if (!file_exists($facesDir) && !mkdir($facesDir, 0755, true)) {
        imagedestroy($faceImage);
        imagedestroy($signatureImage);
        throw new Exception('Could not create faces folder');
    }
    if (!file_exists($signaturesDir) && !mkdir($signaturesDir, 0755, true)) {
        imagedestroy($faceImage);
        imagedestroy($signatureImage);
        throw new Exception('Could not create signatures folder');
    }

    $savedFiles = [];
    $stamp = time() . mt_rand(100, 999); // digits only, avoids same-second collisions

    // ------------------------------------------------------------------
    // STEP 3: save face photo with watermark
    // ------------------------------------------------------------------
    $faceImage = addWatermarkToImage($faceImage, $timestamp, $learnerID, $type);

    $faceFilename = "face_{$type}_{$learnerID}_{$clockDate}_{$stamp}.jpg";
    $facePath = $facesDir . '/' . $faceFilename;

    // Save with reduced quality (70%) to reduce file size
    if (!imagejpeg($faceImage, $facePath, 70)) {
        imagedestroy($faceImage);
        imagedestroy($signatureImage);
        throw new Exception('Failed to save face image');
    }
    $written[] = $facePath;
    imagedestroy($faceImage);

    if (!is_file($facePath) || filesize($facePath) === 0) {
        imagedestroy($signatureImage);
        throw new Exception('Face image was not written correctly');
    }
    $savedFiles['face_' . $type] = $faceFilename;

    // ------------------------------------------------------------------
    // STEP 4: save signature (resize if too large)
    // ------------------------------------------------------------------
    $sigWidth  = imagesx($signatureImage);
    $sigHeight = imagesy($signatureImage);

    // Resize signature if wider than 800px
    $maxSigWidth = 800;
    if ($sigWidth > $maxSigWidth) {
        $ratio        = $maxSigWidth / $sigWidth;
        $newSigWidth  = $maxSigWidth;
        $newSigHeight = (int)($sigHeight * $ratio);

        $resizedSig = imagecreatetruecolor($newSigWidth, $newSigHeight);

        // Preserve transparency for PNG
        imagealphablending($resizedSig, false);
        imagesavealpha($resizedSig, true);
        $transparent = imagecolorallocatealpha($resizedSig, 255, 255, 255, 127);
        imagefilledrectangle($resizedSig, 0, 0, $newSigWidth, $newSigHeight, $transparent);

        imagecopyresampled($resizedSig, $signatureImage, 0, 0, 0, 0, $newSigWidth, $newSigHeight, $sigWidth, $sigHeight);
        imagedestroy($signatureImage);
        $signatureImage = $resizedSig;
    }

    $signatureFilename = "signature_{$type}_{$learnerID}_{$clockDate}_{$stamp}.png";
    $signaturePath = $signaturesDir . '/' . $signatureFilename;

    // Save as PNG with compression
    if (!imagepng($signatureImage, $signaturePath, 6)) {
        imagedestroy($signatureImage);
        throw new Exception('Failed to save signature');
    }
    $written[] = $signaturePath;
    imagedestroy($signatureImage);

    if (!is_file($signaturePath) || filesize($signaturePath) === 0) {
        throw new Exception('Signature was not written correctly');
    }
    $savedFiles['signature_' . $type] = $signatureFilename;

    // ------------------------------------------------------------------
    // STEP 5: final guard, both files must be saved
    // ------------------------------------------------------------------
    if (!isset($savedFiles['face_' . $type], $savedFiles['signature_' . $type])) {
        throw new Exception('Both images must be saved');
    }

    // Success response
    echo json_encode([
        'success' => true,
        'message' => 'Images saved successfully',
        'files' => $savedFiles,
        'learner_id' => $learnerID,
        'clock_date' => $clockDate,
        'type' => $type
    ]);

} catch (Exception $e) {
    // Log the error with full details
    error_log("[SAVE_CLOCKING_IMAGES] ❌ Exception: " . $e->getMessage());
    error_log("[SAVE_CLOCKING_IMAGES] ❌ File: " . $e->getFile() . " Line: " . $e->getLine());
    error_log("[SAVE_CLOCKING_IMAGES] ❌ Stack trace: " . $e->getTraceAsString());
    
    // Remove anything already written so no half-saved evidence is left behind
    foreach ($written as $f) {
        @unlink($f);
    }

    http_response_code(400);
    echo json_encode([
        'success' => false,
        'error' => $e->getMessage(),
        'message' => $e->getMessage()
    ]);
}

/**
 * Add watermark with frame and timestamp to image
 *
 * @param \GdImage|resource $image GD image resource (PHP 7) or GdImage object (PHP 8+)
 * @param string $timestamp Timestamp to display
 * @param int $learnerID Learner ID
 * @param string $type 'in' or 'out'
 * @return \GdImage|resource Modified image resource
 */
function addWatermarkToImage($image, $timestamp, $learnerID, $type = 'in') {
    $width = imagesx($image);
    $height = imagesy($image);

    // Resize image to reduce file size (max width 1024px)
    $maxWidth = 1024;
    if ($width > $maxWidth) {
        $ratio = $maxWidth / $width;
        $newWidth = $maxWidth;
        $newHeight = (int)($height * $ratio);

        $resizedImage = imagecreatetruecolor($newWidth, $newHeight);
        imagecopyresampled($resizedImage, $image, 0, 0, 0, 0, $newWidth, $newHeight, $width, $height);
        imagedestroy($image);
        $image = $resizedImage;

        $width = $newWidth;
        $height = $newHeight;
    }

    // Colors
    $white = imagecolorallocate($image, 255, 255, 255);
    $black = imagecolorallocate($image, 0, 0, 0);
    $red = imagecolorallocate($image, 220, 53, 69);
    $frameColor = imagecolorallocate($image, 0, 123, 255);

    // Frame thickness
    $frameThickness = 8;

    // Draw frame border
    imagesetthickness($image, $frameThickness);
    imagerectangle($image,
        $frameThickness/2,
        $frameThickness/2,
        $width - $frameThickness/2,
        $height - $frameThickness/2,
        $frameColor
    );

    // Watermark background
    $watermarkHeight = 80;
    $watermarkY = $height - $watermarkHeight - $frameThickness;

    // Draw watermark background
    imagefilledrectangle($image,
        $frameThickness,
        $watermarkY,
        $width - $frameThickness,
        $height - $frameThickness,
        $black
    );

    imagealphablending($image, true);

    // Built-in GD fonts
    $font = 5;      // large
    $fontSmall = 3; // medium

    // Text positioning
    $textX = $frameThickness + 10;
    $textY1 = $watermarkY + 15;
    $textY2 = $watermarkY + 35;
    $textY3 = $watermarkY + 55;

    $label = ($type === 'out') ? 'RLMSS Manual Clock-Out' : 'RLMSS Manual Clock-In';

    // Add text to watermark
    imagestring($image, $font, $textX, $textY1, $label, $white);
    imagestring($image, $fontSmall, $textX, $textY2, "Learner ID: $learnerID", $white);
    imagestring($image, $font, $textX, $textY3, $timestamp, $red);

    // Add corner timestamp
    $cornerText = date('Y-m-d H:i', strtotime($timestamp));
    $cornerX = $width - (strlen($cornerText) * 8) - $frameThickness - 10;
    $cornerY = $frameThickness + 10;
    imagestring($image, $font, $cornerX, $cornerY, $cornerText, $white);

    return $image;
}

if (isset($conn)) {
    $conn->close();
}
?>