<?php
require_once 'connection.php';

// Get evidence ID from URL
$evidence_id = isset($_GET['id']) ? intval($_GET['id']) : 0;

if ($evidence_id <= 0) {
    die('Invalid evidence ID');
}

// Fetch evidence record with all related information
$query = "
    SELECT 
        mce.*,
        CONCAT(ld.Name, ' ', ld.Surname) as learner_name,
        ld.IDNumber,
        ld.Title,
        ld.Name as learner_first_name,
        ld.Surname as learner_last_name,
        ld.Email as learner_email,
        ld.PhoneNumber as learner_phone,
        p.project_name as ProjectName,
        p.project_id,
        s.siteName as SiteName,
        s.siteID,
        c.className as ClassName,
        c.classID,
        lc.clock_in_time,
        lc.clock_out_time,
        lc.contact_time as actual_contact_time
    FROM manual_clocking_evidence mce
    INNER JOIN learnerdetails ld ON mce.LearnerID = ld.LearnerID
    LEFT JOIN class c ON ld.classID = c.classID
    LEFT JOIN sites s ON c.siteID = s.siteID
    LEFT JOIN project p ON s.project_id = p.project_id
    LEFT JOIN learner_clocking lc ON (
        mce.LearnerID = lc.LearnerID 
        AND mce.clock_date = lc.clock_date
    )
    WHERE mce.evidence_id = ?
";

$stmt = $conn->prepare($query);
$stmt->bind_param("i", $evidence_id);
$stmt->execute();
$result = $stmt->get_result();

if ($result->num_rows === 0) {
    die('Evidence record not found');
}

$evidence = $result->fetch_assoc();

// Determine status
$hasClockIn = ($evidence['signature_in'] || $evidence['face_in']);
$hasClockOut = ($evidence['signature_out'] || $evidence['face_out']);

if ($hasClockIn && $hasClockOut) {
    $status = 'complete';
    $statusText = 'Complete Evidence';
    $statusClass = 'bg-success';
    $statusIcon = 'fa-check-circle';
} elseif ($hasClockIn) {
    $status = 'incomplete';
    $statusText = 'Incomplete - Missing Clock Out';
    $statusClass = 'bg-warning';
    $statusIcon = 'fa-exclamation-triangle';
} else {
    $status = 'no_evidence';
    $statusText = 'No Evidence';
    $statusClass = 'bg-danger';
    $statusIcon = 'fa-times-circle';
}

// Evidence base path - folder is in same directory as this file (inside mobile folder)
$evidenceBasePath = __DIR__ . '/manual_clocking_evidence/';
$evidenceBaseUrl = 'manual_clocking_evidence/';
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Manual Clocking Evidence Details | RLMS</title>
    <link href="css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <style>
        :root {
            --primary-gradient: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            --success-gradient: linear-gradient(135deg, #11998e 0%, #38ef7d 100%);
            --warning-gradient: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);
            --danger-gradient: linear-gradient(135deg, #ff512f 0%, #dd2476 100%);
        }
        
        body {
            background: linear-gradient(120deg, #f8f9fa 0%, #e9ecef 100%);
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            min-height: 100vh;
        }
        
        .navbar {
            background: linear-gradient(135deg, #2c3e50 0%, #34495e 100%) !important;
            box-shadow: 0 4px 20px rgba(0, 0, 0, 0.15);
        }
        
        .page-header {
            background: white;
            padding: 2rem;
            border-radius: 15px;
            box-shadow: 0 4px 15px rgba(0, 0, 0, 0.08);
            margin-bottom: 2rem;
        }
        
        .page-header h2 {
            color: #2c3e50;
            font-weight: 700;
            margin-bottom: 0.5rem;
        }
        
        .status-badge {
            padding: 0.5rem 1.5rem;
            border-radius: 50px;
            font-size: 1rem;
            font-weight: 600;
            color: white;
            display: inline-flex;
            align-items: center;
            gap: 0.5rem;
        }
        
        .status-badge.bg-success {
            background: var(--success-gradient);
            box-shadow: 0 4px 15px rgba(56, 239, 125, 0.3);
        }
        
        .status-badge.bg-warning {
            background: var(--warning-gradient);
            box-shadow: 0 4px 15px rgba(245, 87, 108, 0.3);
        }
        
        .status-badge.bg-danger {
            background: var(--danger-gradient);
            box-shadow: 0 4px 15px rgba(221, 36, 118, 0.3);
        }
        
        .card {
            border: none;
            border-radius: 15px;
            box-shadow: 0 4px 15px rgba(0, 0, 0, 0.08);
            margin-bottom: 2rem;
        }
        
        .card-header {
            background: var(--primary-gradient);
            color: white;
            border-radius: 15px 15px 0 0 !important;
            padding: 1.25rem 1.5rem;
            font-weight: 700;
        }
        
        .info-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 1.5rem;
            margin-bottom: 2rem;
        }
        
        .info-item {
            background: white;
            padding: 1.5rem;
            border-radius: 12px;
            box-shadow: 0 2px 10px rgba(0, 0, 0, 0.05);
        }
        
        .info-item .label {
            color: #6c757d;
            font-size: 0.85rem;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            margin-bottom: 0.5rem;
        }
        
        .info-item .value {
            color: #2c3e50;
            font-size: 1.1rem;
            font-weight: 600;
        }
        
        .evidence-container {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 2rem;
            margin-top: 1.5rem;
        }
        
        .evidence-box {
            background: white;
            border-radius: 12px;
            padding: 1.5rem;
            box-shadow: 0 2px 10px rgba(0, 0, 0, 0.05);
            text-align: center;
        }
        
        .evidence-box h5 {
            color: #2c3e50;
            font-weight: 700;
            margin-bottom: 1rem;
            font-size: 1.1rem;
        }
        
        .evidence-box img {
            max-width: 100%;
            height: auto;
            border-radius: 10px;
            box-shadow: 0 4px 15px rgba(0, 0, 0, 0.1);
            cursor: pointer;
            transition: all 0.3s ease;
            max-height: 400px;
            object-fit: contain;
        }
        
        .evidence-box img:hover {
            transform: scale(1.05);
            box-shadow: 0 6px 20px rgba(0, 0, 0, 0.15);
        }
        
        .no-evidence {
            padding: 3rem;
            color: #6c757d;
            font-size: 1rem;
        }
        
        .no-evidence i {
            font-size: 3rem;
            margin-bottom: 1rem;
            opacity: 0.3;
        }
        
        .btn {
            padding: 0.65rem 1.5rem;
            border-radius: 10px;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            font-size: 0.85rem;
            transition: all 0.3s ease;
            border: none;
        }
        
        .btn-primary {
            background: var(--primary-gradient);
            box-shadow: 0 4px 15px rgba(102, 126, 234, 0.3);
        }
        
        .btn-primary:hover {
            transform: translateY(-2px);
            box-shadow: 0 6px 20px rgba(102, 126, 234, 0.4);
        }
        
        .btn-secondary {
            background: linear-gradient(135deg, #757f9a 0%, #d7dde8 100%);
            color: #2c3e50;
        }
        
        .modal-content {
            border-radius: 15px;
            border: none;
            box-shadow: 0 10px 40px rgba(0, 0, 0, 0.2);
        }
        
        .modal-header {
            background: var(--primary-gradient);
            color: white;
            border-radius: 15px 15px 0 0;
        }
        
        .modal-body img {
            max-width: 100%;
            height: auto;
            border-radius: 10px;
        }
        
        .time-badge {
            display: inline-flex;
            align-items: center;
            gap: 0.5rem;
            padding: 0.5rem 1rem;
            background: #f8f9fa;
            border-radius: 50px;
            font-weight: 600;
            color: #2c3e50;
        }
    </style>
</head>
<body>
    <nav class="navbar navbar-expand-lg navbar-dark">
        <div class="container-fluid">
            <a class="navbar-brand" href="manual_clocking_evidence_dashboard.php">
                <i class="fas fa-camera"></i> Manual Clocking Evidence
            </a>
            <div class="ms-auto">
                <a href="manual_clocking_evidence_dashboard.php" class="btn btn-secondary">
                    <i class="fas fa-arrow-left"></i> Back to Dashboard
                </a>
            </div>
        </div>
    </nav>
    
    <div class="container-fluid mt-4">
        <!-- Page Header -->
        <div class="page-header">
            <div class="d-flex justify-content-between align-items-center">
                <div>
                    <h2><i class="fas fa-file-image"></i> Evidence Record #<?php echo $evidence_id; ?></h2>
                    <p class="text-muted mb-0">Detailed view of manual clocking evidence</p>
                </div>
                <div>
                    <span class="status-badge <?php echo $statusClass; ?>">
                        <i class="fas <?php echo $statusIcon; ?>"></i>
                        <?php echo $statusText; ?>
                    </span>
                </div>
            </div>
        </div>
        
        <!-- Learner Information -->
        <div class="card">
            <div class="card-header">
                <h5 class="mb-0"><i class="fas fa-user"></i> Learner Information</h5>
            </div>
            <div class="card-body">
                <div class="info-grid">
                    <div class="info-item">
                        <div class="label"><i class="fas fa-user"></i> Full Name</div>
                        <div class="value"><?php echo htmlspecialchars($evidence['learner_name']); ?></div>
                    </div>
                    <div class="info-item">
                        <div class="label"><i class="fas fa-id-card"></i> ID Number</div>
                        <div class="value"><?php echo htmlspecialchars($evidence['IDNumber'] ?? 'N/A'); ?></div>
                    </div>
                    <div class="info-item">
                        <div class="label"><i class="fas fa-project-diagram"></i> Project</div>
                        <div class="value"><?php echo htmlspecialchars($evidence['ProjectName'] ?? 'N/A'); ?></div>
                    </div>
                    <div class="info-item">
                        <div class="label"><i class="fas fa-map-marker-alt"></i> Site</div>
                        <div class="value"><?php echo htmlspecialchars($evidence['SiteName'] ?? 'N/A'); ?></div>
                    </div>
                    <div class="info-item">
                        <div class="label"><i class="fas fa-chalkboard"></i> Class</div>
                        <div class="value"><?php echo htmlspecialchars($evidence['ClassName'] ?? 'N/A'); ?></div>
                    </div>
                    <div class="info-item">
                        <div class="label"><i class="fas fa-calendar"></i> Clocking Date</div>
                        <div class="value"><?php echo date('l, d F Y', strtotime($evidence['clock_date'])); ?></div>
                    </div>
                </div>
            </div>
        </div>
        
        <!-- Clocking Times -->
        <div class="card">
            <div class="card-header">
                <h5 class="mb-0"><i class="fas fa-clock"></i> Clocking Times</h5>
            </div>
            <div class="card-body">
                <div class="row text-center">
                    <div class="col-md-4">
                        <div class="info-item">
                            <div class="label"><i class="fas fa-sign-in-alt"></i> Clock In Time</div>
                            <div class="value">
                                <?php if ($evidence['clock_in_time']): ?>
                                    <span class="time-badge">
                                        <i class="fas fa-clock"></i>
                                        <?php echo date('H:i:s', strtotime($evidence['clock_in_time'])); ?>
                                    </span>
                                <?php else: ?>
                                    <span class="text-muted">Not Recorded</span>
                                <?php endif; ?>
                            </div>
                        </div>
                    </div>
                    <div class="col-md-4">
                        <div class="info-item">
                            <div class="label"><i class="fas fa-sign-out-alt"></i> Clock Out Time</div>
                            <div class="value">
                                <?php if ($evidence['clock_out_time']): ?>
                                    <span class="time-badge">
                                        <i class="fas fa-clock"></i>
                                        <?php echo date('H:i:s', strtotime($evidence['clock_out_time'])); ?>
                                    </span>
                                <?php else: ?>
                                    <span class="text-muted">Not Recorded</span>
                                <?php endif; ?>
                            </div>
                        </div>
                    </div>
                    <div class="col-md-4">
                        <div class="info-item">
                            <div class="label"><i class="fas fa-hourglass-half"></i> Contact Time</div>
                            <div class="value">
                                <?php if ($evidence['actual_contact_time']): ?>
                                    <span class="time-badge">
                                        <i class="fas fa-hourglass-half"></i>
                                        <?php echo htmlspecialchars($evidence['actual_contact_time']); ?>
                                    </span>
                                <?php else: ?>
                                    <span class="text-muted">Not Calculated</span>
                                <?php endif; ?>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
        
        <!-- Evidence Photos & Signatures -->
        <div class="card">
            <div class="card-header">
                <h5 class="mb-0"><i class="fas fa-images"></i> Evidence Photos & Signatures</h5>
            </div>
            <div class="card-body">
                <div class="evidence-container">
                    <!-- Signature In -->
                    <div class="evidence-box">
                        <h5><i class="fas fa-signature text-primary"></i> Signature - Clock In</h5>
                        <?php if ($evidence['signature_in'] && file_exists($evidenceBasePath . $evidence['signature_in'])): ?>
                            <img 
                                src="<?php echo $evidenceBaseUrl . htmlspecialchars($evidence['signature_in']); ?>" 
                                alt="Signature Clock In"
                                onclick="showModal(this.src, 'Signature - Clock In')"
                            >
                            <div class="mt-3">
                                <small class="text-muted">
                                    <i class="fas fa-file"></i> 
                                    <?php echo basename($evidence['signature_in']); ?>
                                </small>
                            </div>
                        <?php else: ?>
                            <div class="no-evidence">
                                <i class="fas fa-image-slash"></i>
                                <p class="mb-0">No signature captured for clock in</p>
                            </div>
                        <?php endif; ?>
                    </div>
                    
                    <!-- Face Photo In -->
                    <div class="evidence-box">
                        <h5><i class="fas fa-face-smile text-info"></i> Face Photo - Clock In</h5>
                        <?php if ($evidence['face_in'] && file_exists($evidenceBasePath . $evidence['face_in'])): ?>
                            <img 
                                src="<?php echo $evidenceBaseUrl . htmlspecialchars($evidence['face_in']); ?>" 
                                alt="Face Photo Clock In"
                                onclick="showModal(this.src, 'Face Photo - Clock In')"
                            >
                            <div class="mt-3">
                                <small class="text-muted">
                                    <i class="fas fa-file"></i> 
                                    <?php echo basename($evidence['face_in']); ?>
                                </small>
                            </div>
                        <?php else: ?>
                            <div class="no-evidence">
                                <i class="fas fa-image-slash"></i>
                                <p class="mb-0">No face photo captured for clock in</p>
                            </div>
                        <?php endif; ?>
                    </div>
                    
                    <!-- Signature Out -->
                    <div class="evidence-box">
                        <h5><i class="fas fa-signature text-success"></i> Signature - Clock Out</h5>
                        <?php if ($evidence['signature_out'] && file_exists($evidenceBasePath . $evidence['signature_out'])): ?>
                            <img 
                                src="<?php echo $evidenceBaseUrl . htmlspecialchars($evidence['signature_out']); ?>" 
                                alt="Signature Clock Out"
                                onclick="showModal(this.src, 'Signature - Clock Out')"
                            >
                            <div class="mt-3">
                                <small class="text-muted">
                                    <i class="fas fa-file"></i> 
                                    <?php echo basename($evidence['signature_out']); ?>
                                </small>
                            </div>
                        <?php else: ?>
                            <div class="no-evidence">
                                <i class="fas fa-image-slash"></i>
                                <p class="mb-0">No signature captured for clock out</p>
                            </div>
                        <?php endif; ?>
                    </div>
                    
                    <!-- Face Photo Out -->
                    <div class="evidence-box">
                        <h5><i class="fas fa-face-smile text-warning"></i> Face Photo - Clock Out</h5>
                        <?php if ($evidence['face_out'] && file_exists($evidenceBasePath . $evidence['face_out'])): ?>
                            <img 
                                src="<?php echo $evidenceBaseUrl . htmlspecialchars($evidence['face_out']); ?>" 
                                alt="Face Photo Clock Out"
                                onclick="showModal(this.src, 'Face Photo - Clock Out')"
                            >
                            <div class="mt-3">
                                <small class="text-muted">
                                    <i class="fas fa-file"></i> 
                                    <?php echo basename($evidence['face_out']); ?>
                                </small>
                            </div>
                        <?php else: ?>
                            <div class="no-evidence">
                                <i class="fas fa-image-slash"></i>
                                <p class="mb-0">No face photo captured for clock out</p>
                            </div>
                        <?php endif; ?>
                    </div>
                </div>
            </div>
        </div>
        
        <!-- Record Metadata -->
        <div class="card">
            <div class="card-header">
                <h5 class="mb-0"><i class="fas fa-info-circle"></i> Record Metadata</h5>
            </div>
            <div class="card-body">
                <div class="info-grid">
                    <div class="info-item">
                        <div class="label"><i class="fas fa-hashtag"></i> Evidence ID</div>
                        <div class="value"><?php echo $evidence['evidence_id']; ?></div>
                    </div>
                    <div class="info-item">
                        <div class="label"><i class="fas fa-user-circle"></i> Learner ID</div>
                        <div class="value"><?php echo $evidence['LearnerID']; ?></div>
                    </div>
                    <div class="info-item">
                        <div class="label"><i class="fas fa-clock"></i> Record Created</div>
                        <div class="value"><?php echo date('d M Y H:i:s', strtotime($evidence['created_at'])); ?></div>
                    </div>
                    <div class="info-item">
                        <div class="label"><i class="fas fa-sync"></i> Last Updated</div>
                        <div class="value"><?php echo date('d M Y H:i:s', strtotime($evidence['updated_at'])); ?></div>
                    </div>
                    <div class="info-item">
                        <div class="label"><i class="fas fa-mobile-alt"></i> Device ID</div>
                        <div class="value"><?php echo htmlspecialchars($evidence['device_id'] ?? 'N/A'); ?></div>
                    </div>
                    <div class="info-item">
                        <div class="label"><i class="fas fa-database"></i> Record Status</div>
                        <div class="value">
                            <span class="status-badge <?php echo $statusClass; ?>">
                                <i class="fas <?php echo $statusIcon; ?>"></i>
                                <?php echo $statusText; ?>
                            </span>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <!-- Image Modal -->
    <div class="modal fade" id="imageModal" tabindex="-1">
        <div class="modal-dialog modal-xl modal-dialog-centered">
            <div class="modal-content">
                <div class="modal-header">
                    <h5 class="modal-title" id="modalTitle">Evidence Image</h5>
                    <button type="button" class="btn-close btn-close-white" data-bs-dismiss="modal"></button>
                </div>
                <div class="modal-body text-center">
                    <img id="modalImage" src="" class="img-fluid" alt="Evidence">
                </div>
            </div>
        </div>
    </div>
    
    <script src="js/jquery-3.6.0.min.js"></script>
    <script src="js/bootstrap.bundle.min.js"></script>
    <script>
        function showModal(imageSrc, title) {
            document.getElementById('modalImage').src = imageSrc;
            document.getElementById('modalTitle').textContent = title;
            var modal = new bootstrap.Modal(document.getElementById('imageModal'));
            modal.show();
        }
    </script>
</body>
</html>
