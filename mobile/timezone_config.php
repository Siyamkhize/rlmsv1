<?php
/**
 * Timezone Configuration for RLMSS
 * 
 * This file ensures all PHP scripts use South African Standard Time (SAST)
 * Include this at the top of every PHP endpoint that handles dates/times
 * 
 * Usage: require_once __DIR__ . '/timezone_config.php';
 */

// Set timezone to South Africa (SAST = UTC+2)
date_default_timezone_set('Africa/Johannesburg');

// Optional: Log timezone for debugging (remove in production)
// error_log("Timezone set to: " . date_default_timezone_get() . " - Current time: " . date('Y-m-d H:i:s'));
?>
