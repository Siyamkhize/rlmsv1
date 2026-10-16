<?php
/**
 * Trusted Proxy Configuration
 * 
 * Only trust X-Forwarded-For and similar headers from these IP addresses.
 * This prevents IP spoofing attacks where clients can fake their IP address.
 */

return [
    'trusted_proxies' => [
        '127.0.0.1',     // localhost
        '10.0.0.0/8',    // Private networks RFC1918
        '172.16.0.0/12', // Private networks RFC1918
        '192.168.0.0/16', // Private networks RFC1918
        // Add your reverse proxy IPs here:
        // '203.0.113.10',    // Example: your load balancer
        // '198.51.100.5',    // Example: your CDN edge server
    ],
    'proxy_headers' => [
        'HTTP_CF_CONNECTING_IP',    // Cloudflare
        'HTTP_X_FORWARDED_FOR',     // Standard reverse proxy header
        'HTTP_CLIENT_IP',           // Some proxies use this
        'HTTP_X_REAL_IP',           // Nginx real_ip module
        'HTTP_X_CLUSTER_CLIENT_IP', // Some cluster setups
    ]
];