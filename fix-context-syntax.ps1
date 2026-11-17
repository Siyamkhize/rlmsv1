# PowerShell script to fix incorrectly placed context.mounted checks
# This script fixes the syntax errors where mounted checks were placed inside function parameter lists

$ErrorActionPreference = "Stop"

# List of all affected files from the review
$affectedFiles = @(
    "lib\ArplAssessorPage.dart",
    "lib\ArplHierarchicalNavigatorPage.dart",
    "lib\ArplPracticalImageCapturePage.dart",
    "lib\ArplToolkitBricklayerPage.dart",
    "lib\ArplToolkitViewerPage.dart",
    "lib\AssessorPage.dart",
    "lib\backup_clock_in_page.dart",
    "lib\complete_database_inspector.dart",
    "lib\contact_less.dart",
    "lib\database_helper_offline_first.dart",
    "lib\DetailsPage.dart",
    "lib\DetailsPage_server.dart",
    "lib\facilitator_fingerprint_page.dart",
    "lib\FacilitatorProfile.dart",
    "lib\finance_attendance_calendar.dart",
    "lib\finance_register_history.dart",
    "lib\finance_register_scanner.dart",
    "lib\fingerprint_induction.dart",
    "lib\induction.dart",
    "lib\learner_induction_page.dart",
    "lib\learner_issue_form_page.dart",
    "lib\learner_list_page.dart",
    "lib\learner_security_questions_setup_page.dart",
    "lib\LearnerDetailsPage - Copy.dart",
    "lib\LearnerListPage.dart",
    "lib\learning_material_form_page.dart",
    "lib\logistics_learning_material_form_page.dart",
    "lib\main.dart",
    "lib\main_ui_updated.dart",
    "lib\mixins\learner_clockin_gates_mixin.dart",
    "lib\models\arpl_toolkit_data.dart",
    "lib\ModeratorPage.dart",
    "lib\persistent_sync_service.dart",
    "lib\poe_document_scanner.dart",
    "lib\poe_submit.dart",
    "lib\POECollectionPage.dart",
    "lib\potholeChecklistpage.dart",
    "lib\repositories\face_verification_repository.dart",
    "lib\repositories\facilitator_face_repository.dart",
    "lib\sdp_unallocated_learners_page.dart",
    "lib\services\camera_resource_manager.dart",
    "lib\services\comprehensive_manual_clocking_sync.dart",
    "lib\services\consolidated_clocking_service.dart",
    "lib\services\database_coordinator.dart",
    "lib\services\face_embedding_service.dart",
    "lib\services\futronic_service.dart",
    "lib\services\http_client_service.dart",
    "lib\services\manual_clocking_evidence_sync_service.dart",
    "lib\services\offline_face_verification_service.dart",
    "lib\services\persistent_sync_service.dart",
    "lib\services\request_deduplication_service.dart",
    "lib\services\secure_location_service.dart",
    "lib\services\signature_sync_service.dart",
    "lib\sick_note_page.dart",
    "lib\sync_service_null_safe.dart",
    "lib\utils\centralized_logger.dart",
    "lib\WorkExperienceForm.dart"
)

$totalFixed = 0
$filesFixed = 0

Write-Host "Starting syntax fix for context.mounted checks..." -ForegroundColor Cyan
Write-Host "Processing $($affectedFiles.Count) files..." -ForegroundColor Cyan
Write-Host ""

foreach ($file in $affectedFiles) {
    $fullPath = Join-Path $PSScriptRoot $file
    
    if (-not (Test-Path $fullPath)) {
        Write-Host "  [SKIP] File not found: $file" -ForegroundColor Yellow
        continue
    }
    
    Write-Host "Processing: $file" -ForegroundColor Gray
    
    $content = Get-Content $fullPath -Raw -Encoding UTF8
    $originalContent = $content
    $fileFixCount = 0
    
    # Pattern 1: Fix TextButton( if (!context.mounted) return;
    $pattern1 = '(TextButton\()\s*\n\s+if \(!context\.mounted\) return;\s*\n'
    $replacement1 = '$1' + "`n"
    if ($content -match $pattern1) {
        $content = $content -replace $pattern1, $replacement1
        $fileFixCount += ([regex]::Matches($originalContent, $pattern1)).Count
    }
    
    # Pattern 2: Fix ElevatedButton( if (!context.mounted) return;
    $pattern2 = '(ElevatedButton\()\s*\n\s+if \(!context\.mounted\) return;\s*\n'
    $replacement2 = '$1' + "`n"
    if ($content -match $pattern2) {
        $content = $content -replace $pattern2, $replacement2
        $fileFixCount += ([regex]::Matches($originalContent, $pattern2)).Count
    }
    
    # Pattern 3: Fix IconButton( if (!context.mounted) return;
    $pattern3 = '(IconButton\()\s*\n\s+if \(!context\.mounted\) return;\s*\n'
    $replacement3 = '$1' + "`n"
    if ($content -match $pattern3) {
        $content = $content -replace $pattern3, $replacement3
        $fileFixCount += ([regex]::Matches($originalContent, $pattern3)).Count
    }
    
    # Pattern 4: Fix OutlinedButton( if (!context.mounted) return;
    $pattern4 = '(OutlinedButton\()\s*\n\s+if \(!context\.mounted\) return;\s*\n'
    $replacement4 = '$1' + "`n"
    if ($content -match $pattern4) {
        $content = $content -replace $pattern4, $replacement4
        $fileFixCount += ([regex]::Matches($originalContent, $pattern4)).Count
    }
    
    # Pattern 5: Fix showDialog( if (!context.mounted) return;
    $pattern5 = '(await showDialog[^(]*\()\s*\n\s+if \(!context\.mounted\) return;\s*\n'
    $replacement5 = '$1' + "`n"
    if ($content -match $pattern5) {
        $content = $content -replace $pattern5, $replacement5
        $fileFixCount += ([regex]::Matches($originalContent, $pattern5)).Count
    }
    
    # Pattern 6: Fix showModalBottomSheet( if (!context.mounted) return;
    $pattern6 = '(await showModalBottomSheet[^(]*\()\s*\n\s+if \(!context\.mounted\) return;\s*\n'
    $replacement6 = '$1' + "`n"
    if ($content -match $pattern6) {
        $content = $content -replace $pattern6, $replacement6
        $fileFixCount += ([regex]::Matches($originalContent, $pattern6)).Count
    }
    
    # Pattern 7: Fix showBottomSheet( if (!context.mounted) return;
    $pattern7 = '(await showBottomSheet[^(]*\()\s*\n\s+if \(!context\.mounted\) return;\s*\n'
    $replacement7 = '$1' + "`n"
    if ($content -match $pattern7) {
        $content = $content -replace $pattern7, $replacement7
        $fileFixCount += ([regex]::Matches($originalContent, $pattern7)).Count
    }
    
    if ($content -ne $originalContent) {
        Set-Content -Path $fullPath -Value $content -Encoding UTF8 -NoNewline
        $filesFixed++
        $totalFixed += $fileFixCount
        Write-Host "  [FIXED] Removed $fileFixCount incorrectly placed mounted checks" -ForegroundColor Green
    } else {
        Write-Host "  [OK] No syntax errors found" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "================================" -ForegroundColor Cyan
Write-Host "Syntax Fix Complete!" -ForegroundColor Green
Write-Host "Files processed: $($affectedFiles.Count)" -ForegroundColor White
Write-Host "Files fixed: $filesFixed" -ForegroundColor White
Write-Host "Total checks removed from parameter lists: $totalFixed" -ForegroundColor White
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next step: Run flutter analyze to verify compilation" -ForegroundColor Yellow
