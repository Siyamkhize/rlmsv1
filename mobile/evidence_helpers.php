<?php
/**
 * Shared helpers for manual clocking evidence (face photo + signature).
 * LAST UPDATED: 2026/11/03
 * 
 * Put this file in the same folder as save_manual_clockin.php,
 * save_manual_clockout.php and save_manual_clocking_images.php.
 */

if (!defined('EVIDENCE_BASE')) {
    define('EVIDENCE_BASE', __DIR__ . '/manual_clocking_evidence');
}

/**
 * Throws unless $clockDate is a real date in Y-m-d format.
 */
function requireValidDate($clockDate) {
    if (!is_string($clockDate) || !preg_match('/^\d{4}-\d{2}-\d{2}$/', $clockDate)) {
        throw new Exception('Invalid clock date');
    }
    $d = DateTime::createFromFormat('Y-m-d', $clockDate);
    if (!$d || $d->format('Y-m-d') !== $clockDate) {
        throw new Exception('Invalid clock date');
    }
}

/**
 * Throws unless $time looks like HH:mm:ss (or HH:mm).
 */
function requireValidTime($time, $label = 'Time') {
    if (!is_string($time) || !preg_match('/^([01]\d|2[0-3]):[0-5]\d(:[0-5]\d)?$/', $time)) {
        throw new Exception("$label is invalid");
    }
}

/**
 * Throws unless $name is a well-formed evidence filename for this learner/date/type
 * AND the file really exists on disk and is not empty.
 *
 * @param mixed  $name       Filename sent by the app
 * @param string $kind       'face' or 'signature'
 * @param string $type       'in' or 'out'
 * @param int    $learnerID
 * @param string $clockDate  Y-m-d
 */
function requireEvidenceFile($name, string $kind, string $type, int $learnerID, string $clockDate): void {
    $ext   = ($kind === 'face') ? 'jpg' : 'png';
    $dir   = ($kind === 'face') ? 'faces' : 'signatures';
    $label = "$kind-$type";

    $pattern = '/^' . $kind . '_' . $type . '_' . $learnerID . '_'
             . preg_quote($clockDate, '/') . '_\d+\.' . $ext . '$/';

    if (!is_string($name) || $name === '' || !preg_match($pattern, $name)) {
        throw new Exception("Missing or invalid $label image");
    }

    $path = EVIDENCE_BASE . "/$dir/$name";
    if (!is_file($path) || filesize($path) === 0) {
        throw new Exception("The $label image was not saved on the server");
    }
}