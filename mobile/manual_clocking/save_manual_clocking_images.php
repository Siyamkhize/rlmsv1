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
 */

header('Content-Type: application/json');
require_once 'connection.php';

// Do not print PHP warnings into the JSON response
error_reporting(E_ALL);
ini_set('display_errors', 0);
ini_set('log_errors', 1);

$written = []; // full paths of files written during this request (for cleanup)

try {
    // Get JSON input
    $input = json_decode(file_get_contents('php://input'), true);

    if (!$input || !is_array($input)) {
        throw new Exception('Invalid JSON input');
    }

    // Required fields
    $learnerID = isset($input['learner_id']) ? intval($input['learner_id']) : 0;
    $clockDate = isset($input['clock_date']) ? $input['clock_date'] : date('Y-m-d');
    $type      = isset($input['type']) ? $input['type'] : ''; // 'in' or 'out'

    // Image data
    $faceImageBase64 = isset($input['face_image']) ? $input['face_image'] : null;
    $signatureBase64 = isset($input['signature_image']) ? $input['signature_image'] : null;

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
    $baseDir       = __DIR__; // This is the mobile folder
    $facesDir      = $baseDir . '/manual_clocking_evidence/faces';
    $signaturesDir = $baseDir . '/manual_clocking_evidence/signatures';

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
