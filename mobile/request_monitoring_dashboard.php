<?php
/**
 * Request Monitoring Dashboard
 * 
 * Provides real-time monitoring of:
 * - Request patterns and volume
 * - Rate limiting effectiveness  
 * - Security events and alerts
 * - Performance metrics
 * - Attack pattern detection
 */

require_once 'connection.php';
require_once 'require_auth.php';
require_once 'request_logger.php';

// Require authentication - admin only
try {
    $user = requireAuth($conn);
    if ($user['user_role'] !== 'admin' && $user['user_role'] !== 'moderator') {
        http_response_code(403);
        echo json_encode(['error' => 'Access denied. Admin or moderator role required.']);
        exit;
    }
} catch (Exception $e) {
    http_response_code(401);
    echo json_encode(['error' => 'Authentication required']);
    exit;
}

// Handle AJAX requests
if (isset($_GET['action'])) {
    header('Content-Type: application/json');
    
    switch ($_GET['action']) {
        case 'stats':
            $timeframe = $_GET['timeframe'] ?? '1hour';
            $stats = get_request_statistics($conn, $timeframe);
            echo json_encode($stats);
            exit;
            
        case 'recent_requests':
            $limit = intval($_GET['limit'] ?? 50);
            $stmt = $conn->prepare("
                SELECT id, endpoint, method, ip_address, response_code, status, 
                       execution_time, created_at, completed_at
                FROM request_log 
                ORDER BY created_at DESC 
                LIMIT ?
            ");
            $stmt->bind_param("i", $limit);
            $stmt->execute();
            $result = $stmt->get_result();
            $requests = [];
            while ($row = $result->fetch_assoc()) {
                $requests[] = $row;
            }
            $stmt->close();
            echo json_encode($requests);
            exit;
            
        case 'security_events':
            $limit = intval($_GET['limit'] ?? 20);
            $stmt = $conn->prepare("
                SELECT event_type, description, ip_address, created_at, metadata
                FROM security_log 
                ORDER BY created_at DESC 
                LIMIT ?
            ");
            $stmt->bind_param("i", $limit);
            $stmt->execute();
            $result = $stmt->get_result();
            $events = [];
            while ($row = $result->fetch_assoc()) {
                $events[] = $row;
            }
            $stmt->close();
            echo json_encode($events);
            exit;
            
        case 'cleanup':
            $deleted = cleanup_old_request_logs($conn);
            echo json_encode(['success' => true, 'deleted_count' => $deleted]);
            exit;
    }
}

?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Request Monitoring Dashboard - RLMSS</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.7.2/font/bootstrap-icons.css" rel="stylesheet">
    <style>
        .metric-card {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border-radius: 10px;
            padding: 20px;
            margin-bottom: 20px;
        }
        .metric-value {
            font-size: 2rem;
            font-weight: bold;
        }
        .security-alert {
            border-left: 4px solid #dc3545;
            background-color: #f8d7da;
            border-color: #f5c6cb;
        }
        .performance-good { color: #28a745; }
        .performance-warning { color: #ffc107; }
        .performance-danger { color: #dc3545; }
        .refresh-indicator {
            position: fixed;
            top: 10px;
            right: 10px;
            background: rgba(0,0,0,0.7);
            color: white;
            padding: 5px 10px;
            border-radius: 5px;
            display: none;
        }
    </style>
</head>
<body>
    <div class="container-fluid">
        <div class="refresh-indicator" id="refreshIndicator">
            <i class="bi bi-arrow-clockwise"></i> Refreshing...
        </div>
        
        <div class="row">
            <div class="col-12">
                <h1 class="mb-4">
                    <i class="bi bi-activity"></i> Request Monitoring Dashboard
                    <small class="text-muted">Real-time System Monitoring</small>
                </h1>
            </div>
        </div>

        <!-- Controls -->
        <div class="row mb-4">
            <div class="col-md-6">
                <div class="btn-group" role="group">
                    <button type="button" class="btn btn-primary" onclick="loadStats('1hour')">Last Hour</button>
                    <button type="button" class="btn btn-outline-primary" onclick="loadStats('1day')">Last Day</button>
                    <button type="button" class="btn btn-outline-primary" onclick="loadStats('1week')">Last Week</button>
                </div>
            </div>
            <div class="col-md-6 text-end">
                <button class="btn btn-success" onclick="refreshAll()">
                    <i class="bi bi-arrow-clockwise"></i> Refresh
                </button>
                <button class="btn btn-warning" onclick="cleanupLogs()">
                    <i class="bi bi-trash"></i> Cleanup Old Logs
                </button>
            </div>
        </div>

        <!-- Metrics Cards -->
        <div class="row" id="metricsRow">
            <div class="col-md-3">
                <div class="metric-card">
                    <div class="metric-value" id="totalRequests">-</div>
                    <div>Total Requests</div>
                </div>
            </div>
            <div class="col-md-3">
                <div class="metric-card">
                    <div class="metric-value" id="uniqueIPs">-</div>
                    <div>Unique IPs</div>
                </div>
            </div>
            <div class="col-md-3">
                <div class="metric-card">
                    <div class="metric-value" id="errorRate">-%</div>
                    <div>Error Rate</div>
                </div>
            </div>
            <div class="col-md-3">
                <div class="metric-card">
                    <div class="metric-value" id="avgResponseTime">-ms</div>
                    <div>Avg Response Time</div>
                </div>
            </div>
        </div>

        <!-- Charts and Tables -->
        <div class="row">
            <!-- Top Endpoints -->
            <div class="col-md-6">
                <div class="card">
                    <div class="card-header">
                        <h5><i class="bi bi-bar-chart"></i> Top Endpoints</h5>
                    </div>
                    <div class="card-body">
                        <div class="table-responsive">
                            <table class="table table-sm" id="endpointsTable">
                                <thead>
                                    <tr>
                                        <th>Endpoint</th>
                                        <th>Requests</th>
                                    </tr>
                                </thead>
                                <tbody></tbody>
                            </table>
                        </div>
                    </div>
                </div>
            </div>

            <!-- Top IPs -->
            <div class="col-md-6">
                <div class="card">
                    <div class="card-header">
                        <h5><i class="bi bi-globe"></i> Top IP Addresses</h5>
                    </div>
                    <div class="card-body">
                        <div class="table-responsive">
                            <table class="table table-sm" id="ipsTable">
                                <thead>
                                    <tr>
                                        <th>IP Address</th>
                                        <th>Requests</th>
                                    </tr>
                                </thead>
                                <tbody></tbody>
                            </table>
                        </div>
                    </div>
                </div>
            </div>
        </div>

        <div class="row mt-4">
            <!-- Recent Requests -->
            <div class="col-md-8">
                <div class="card">
                    <div class="card-header">
                        <h5><i class="bi bi-clock-history"></i> Recent Requests</h5>
                    </div>
                    <div class="card-body">
                        <div class="table-responsive">
                            <table class="table table-sm" id="recentRequestsTable">
                                <thead>
                                    <tr>
                                        <th>Time</th>
                                        <th>Endpoint</th>
                                        <th>Method</th>
                                        <th>IP</th>
                                        <th>Status</th>
                                        <th>Response Time</th>
                                    </tr>
                                </thead>
                                <tbody></tbody>
                            </table>
                        </div>
                    </div>
                </div>
            </div>

            <!-- Security Events -->
            <div class="col-md-4">
                <div class="card">
                    <div class="card-header">
                        <h5><i class="bi bi-shield-exclamation"></i> Security Events</h5>
                    </div>
                    <div class="card-body">
                        <div id="securityEvents"></div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js"></script>
    <script>
        let currentTimeframe = '1hour';
        
        function showRefresh() {
            document.getElementById('refreshIndicator').style.display = 'block';
        }
        
        function hideRefresh() {
            document.getElementById('refreshIndicator').style.display = 'none';
        }
        
        async function loadStats(timeframe = '1hour') {
            showRefresh();
            currentTimeframe = timeframe;
            
            try {
                const response = await fetch(`?action=stats&timeframe=${timeframe}`);
                const stats = await response.json();
                
                if (stats.error) {
                    console.error('Stats error:', stats.error);
                    return;
                }
                
                updateMetrics(stats.summary);
                updateEndpoints(stats.top_endpoints);
                updateIPs(stats.top_ips);
                
                // Update active button
                document.querySelectorAll('.btn-group button').forEach(btn => {
                    btn.className = 'btn btn-outline-primary';
                });
                event.target.className = 'btn btn-primary';
                
            } catch (error) {
                console.error('Error loading stats:', error);
            }
            
            hideRefresh();
        }
        
        function updateMetrics(summary) {
            document.getElementById('totalRequests').textContent = summary.total_requests || 0;
            document.getElementById('uniqueIPs').textContent = summary.unique_ips || 0;
            
            const errorRate = summary.total_requests > 0 ? 
                ((summary.error_count / summary.total_requests) * 100).toFixed(1) : 0;
            document.getElementById('errorRate').textContent = errorRate + '%';
            
            const avgTime = summary.avg_execution_time ? 
                (summary.avg_execution_time * 1000).toFixed(0) : 0;
            document.getElementById('avgResponseTime').textContent = avgTime + 'ms';
            
            // Color code performance
            const avgElement = document.getElementById('avgResponseTime');
            if (avgTime < 500) {
                avgElement.className = 'metric-value performance-good';
            } else if (avgTime < 2000) {
                avgElement.className = 'metric-value performance-warning';
            } else {
                avgElement.className = 'metric-value performance-danger';
            }
        }
        
        function updateEndpoints(endpoints) {
            const tbody = document.querySelector('#endpointsTable tbody');
            tbody.innerHTML = '';
            
            endpoints.forEach(endpoint => {
                const row = tbody.insertRow();
                row.innerHTML = `
                    <td><code>${endpoint.endpoint}</code></td>
                    <td><span class="badge bg-primary">${endpoint.request_count}</span></td>
                `;
            });
        }
        
        function updateIPs(ips) {
            const tbody = document.querySelector('#ipsTable tbody');
            tbody.innerHTML = '';
            
            ips.forEach(ip => {
                const row = tbody.insertRow();
                row.innerHTML = `
                    <td><code>${ip.ip_address}</code></td>
                    <td><span class="badge bg-info">${ip.request_count}</span></td>
                `;
            });
        }
        
        async function loadRecentRequests() {
            try {
                const response = await fetch('?action=recent_requests&limit=20');
                const requests = await response.json();
                
                const tbody = document.querySelector('#recentRequestsTable tbody');
                tbody.innerHTML = '';
                
                requests.forEach(req => {
                    const row = tbody.insertRow();
                    const statusClass = req.response_code >= 400 ? 'danger' : 
                                       req.response_code >= 300 ? 'warning' : 'success';
                    const time = new Date(req.created_at).toLocaleTimeString();
                    const responseTime = req.execution_time ? 
                        (req.execution_time * 1000).toFixed(0) + 'ms' : '-';
                    
                    row.innerHTML = `
                        <td>${time}</td>
                        <td><code>${req.endpoint}</code></td>
                        <td><span class="badge bg-secondary">${req.method}</span></td>
                        <td><code>${req.ip_address}</code></td>
                        <td><span class="badge bg-${statusClass}">${req.response_code || 'Pending'}</span></td>
                        <td>${responseTime}</td>
                    `;
                });
            } catch (error) {
                console.error('Error loading recent requests:', error);
            }
        }
        
        async function loadSecurityEvents() {
            try {
                const response = await fetch('?action=security_events&limit=10');
                const events = await response.json();
                
                const container = document.getElementById('securityEvents');
                container.innerHTML = '';
                
                events.forEach(event => {
                    const time = new Date(event.created_at).toLocaleString();
                    const alertClass = event.event_type.includes('ATTACK') || 
                                      event.event_type.includes('BRUTE_FORCE') ? 'security-alert' : '';
                    
                    const eventDiv = document.createElement('div');
                    eventDiv.className = `alert alert-sm mb-2 ${alertClass}`;
                    eventDiv.innerHTML = `
                        <small class="text-muted">${time}</small><br>
                        <strong>${event.event_type}</strong><br>
                        <small>${event.description}</small>
                    `;
                    container.appendChild(eventDiv);
                });
                
                if (events.length === 0) {
                    container.innerHTML = '<p class="text-muted">No recent security events</p>';
                }
            } catch (error) {
                console.error('Error loading security events:', error);
            }
        }
        
        async function cleanupLogs() {
            if (!confirm('This will delete request logs older than 30 days. Continue?')) {
                return;
            }
            
            showRefresh();
            try {
                const response = await fetch('?action=cleanup');
                const result = await response.json();
                
                if (result.success) {
                    alert(`Cleanup completed. ${result.deleted_count} old records deleted.`);
                    refreshAll();
                } else {
                    alert('Cleanup failed: ' + result.error);
                }
            } catch (error) {
                console.error('Cleanup error:', error);
                alert('Cleanup failed: ' + error.message);
            }
            hideRefresh();
        }
        
        function refreshAll() {
            loadStats(currentTimeframe);
            loadRecentRequests();
            loadSecurityEvents();
        }
        
        // Auto-refresh every 30 seconds
        setInterval(refreshAll, 30000);
        
        // Initial load
        document.addEventListener('DOMContentLoaded', function() {
            loadStats('1hour');
            loadRecentRequests();
            loadSecurityEvents();
        });
    </script>
</body>
</html>