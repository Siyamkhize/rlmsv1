<?php
/**
 * Face Recognition Configuration
 *
 * Centralized configuration for face recognition matching threshold,
 * embedding dimensions, and model version.
 *
 * Include this file in both enrol_learner_face.php and verify_learner_face.php
 * to ensure consistent settings across all endpoints.
 */

// Cosine similarity threshold for face matching (RAW score, not remapped)
// Range: -1.0 to 1.0 (raw cosine similarity)
// STRICT 1-TO-1 VERIFICATION: 0.95 threshold on raw cosine similarity.
// This value was CHOSEN, not measured. It is very strict and will reject some
// genuine learners (poor light, different angle or camera), so a retry limit
// and a logged facilitator override are needed. Tune it from real logged scores.
// Must equal FACE_MATCH_THRESHOLD in OfflineFaceVerificationService (Dart).
define('FACE_MATCH_THRESHOLD', 0.95);

// MobileFaceNet embedding dimensions
// The offline_face_recognition package uses 192-dim embeddings
define('FACE_EMBEDDING_LENGTH', 192);

// Model version for tracking which model produced the embedding
define('FACE_MODEL_VERSION', 'MobileFaceNet_v1');

// Minimum quality score to accept enrollment (0.0 to 1.0)
// Rejects blurry, poorly lit, or off-angle captures
define('MIN_ENROLLMENT_QUALITY', 0.6);

// Minimum quality score to accept verification attempt (0.0 to 1.0)
// Must equal MIN_VERIFICATION_QUALITY in OfflineFaceVerificationService (Dart).
define('MIN_VERIFICATION_QUALITY', 0.5);

// Lockout: max failed verification attempts per learner inside the window
define('FACE_MAX_FAILED_ATTEMPTS', 5);
define('FACE_LOCKOUT_WINDOW_MINUTES', 10);

// Name of the timestamp column in learner_face_verification_log.
// Check with: SHOW COLUMNS FROM learner_face_verification_log;
define('FACE_LOG_TIME_COLUMN', 'created_at');

// When true, verify_learner_face.php also returns the similarity score and
// threshold to the client. Returning scores lets an attacker tune a fake
// embedding until it passes, so keep this FALSE in production.
define('FACE_DEBUG_RESPONSE', false);

/**
 * Compute cosine similarity between two embedding vectors
 *
 * CRITICAL: Returns RAW cosine similarity in range [-1.0, 1.0]
 * DO NOT remap to [0, 1] - the threshold is chosen for raw scores.
 * Any invalid input (zero vector, NaN, INF) returns -1.0, the worst score.
 *
 * @param array $embedding1 First embedding vector (192 floats)
 * @param array $embedding2 Second embedding vector (192 floats)
 * @return float RAW cosine similarity score (-1.0 to 1.0)
 */
function computeCosineSimilarity($embedding1, $embedding2) {
    if (count($embedding1) !== FACE_EMBEDDING_LENGTH || count($embedding2) !== FACE_EMBEDDING_LENGTH) {
        throw new Exception('Embedding vectors must have ' . FACE_EMBEDDING_LENGTH . ' dimensions');
    }

    $dotProduct = 0.0;
    $norm1 = 0.0;
    $norm2 = 0.0;

    for ($i = 0; $i < FACE_EMBEDDING_LENGTH; $i++) {
        $dotProduct += $embedding1[$i] * $embedding2[$i];
        $norm1 += $embedding1[$i] * $embedding1[$i];
        $norm2 += $embedding2[$i] * $embedding2[$i];
    }

    $norm1 = sqrt($norm1);
    $norm2 = sqrt($norm2);

    // Reject non-finite values BEFORE dividing. min()/max() do not handle NAN,
    // and max(-1.0, min(1.0, NAN)) evaluates to 1.0, a perfect score.
    if (!is_finite($dotProduct) || !is_finite($norm1) || !is_finite($norm2)
        || $norm1 == 0 || $norm2 == 0) {
        return -1.0;
    }

    // Cosine similarity formula: dot(A, B) / (||A|| * ||B||)
    $similarity = $dotProduct / ($norm1 * $norm2);

    if (!is_finite($similarity)) {
        return -1.0;
    }

    // Clamp to [-1, 1] (floating-point drift) and return the RAW score
    return round(max(-1.0, min(1.0, $similarity)), 5);
}

/**
 * Check if similarity score passes the matching threshold
 *
 * @param float $similarity RAW cosine similarity score
 * @return bool True if faces match, false otherwise
 */
function isFaceMatch($similarity) {
    $similarity = (float)$similarity;
    return is_finite($similarity) && $similarity >= FACE_MATCH_THRESHOLD;
}

/**
 * Validate embedding vector format and dimensions
 * Use this for BOTH client-supplied and database-stored embeddings.
 *
 * @param mixed $embedding The embedding to validate
 * @return array|false Returns validated embedding array or false if invalid
 */
function validateEmbedding($embedding) {
    // If it's a JSON string, decode it
    if (is_string($embedding)) {
        $embedding = json_decode($embedding, true);
        if (json_last_error() !== JSON_ERROR_NONE) {
            return false;
        }
    }

    // Must be an array
    if (!is_array($embedding)) {
        return false;
    }

    // Must be a plain list of the correct length (keys 0..191)
    if (count($embedding) !== FACE_EMBEDDING_LENGTH
        || array_keys($embedding) !== range(0, FACE_EMBEDDING_LENGTH - 1)) {
        return false;
    }

    // All elements must be finite numbers (rejects INF and NAN from inputs like 1e999)
    foreach ($embedding as $value) {
        if (!is_numeric($value) || !is_finite((float)$value)) {
            return false;
        }
    }

    return array_map('floatval', $embedding);
}
