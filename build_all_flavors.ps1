# Build All Flavors Script
# Builds local, staging, and production APKs

Write-Host "Building All Flavor APKs" -ForegroundColor Cyan
Write-Host "========================`n" -ForegroundColor Cyan

# Set Java Home
$env:JAVA_HOME = "C:\Program Files\Java\jdk-17.0.12"
Write-Host "Java Home: $env:JAVA_HOME`n" -ForegroundColor Green

# Clean Gradle cache once
Write-Host "Cleaning Gradle cache..." -ForegroundColor Yellow
Remove-Item -Recurse -Force android\.gradle -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force android\app\build -ErrorAction SilentlyContinue
Write-Host "Cache cleaned`n" -ForegroundColor Green

$flavors = @("local", "staging", "production")
$results = @()

foreach ($flavor in $flavors) {
    Write-Host "=======================================" -ForegroundColor DarkGray
    Write-Host "Building $flavor flavor..." -ForegroundColor Yellow
    Write-Host "=======================================`n" -ForegroundColor DarkGray
    
    $startTime = Get-Date
    flutter build apk --release --flavor $flavor -t lib/main.dart
    $endTime = Get-Date
    $duration = $endTime - $startTime
    
    # Determine APK filename based on flavor
    $apkName = "app-${flavor}Release.apk"
    $apkPath = "build\app\outputs\flutter-apk\$apkName"
    
    if (Test-Path $apkPath) {
        $apk = Get-Item $apkPath
        $sizeMB = [math]::Round($apk.Length/1MB, 2)
        
        $results += [PSCustomObject]@{
            Flavor = $flavor
            Status = "SUCCESS"
            Size = "$sizeMB MB"
            Time = $duration.ToString('mm\:ss')
            APK = $apkName
        }
        
        Write-Host "`n$flavor build completed ($($duration.ToString('mm\:ss')))" -ForegroundColor Green
    } else {
        $results += [PSCustomObject]@{
            Flavor = $flavor
            Status = "FAILED"
            Size = "N/A"
            Time = $duration.ToString('mm\:ss')
            APK = "Not found"
        }
        
        Write-Host "`n$flavor build failed" -ForegroundColor Red
    }
    
    Write-Host ""
}

# Summary
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "Build Summary" -ForegroundColor Cyan
Write-Host "=======================================`n" -ForegroundColor Cyan

$results | Format-Table -AutoSize

$successCount = ($results | Where-Object { $_.Status -eq "SUCCESS" }).Count
Write-Host "`nResults: $successCount/$($flavors.Count) builds succeeded" -ForegroundColor Cyan

if ($successCount -eq $flavors.Count) {
    Write-Host "All flavors built successfully!" -ForegroundColor Green
    Write-Host "`nAPK Location: build\app\outputs\flutter-apk\" -ForegroundColor Cyan
    Write-Host "`nPackage IDs:" -ForegroundColor Cyan
    Write-Host "   Local:      com.example.rlmss.local" -ForegroundColor White
    Write-Host "   Staging:    com.example.rlmss.staging" -ForegroundColor White
    Write-Host "   Production: com.example.rlmss" -ForegroundColor White
} else {
    Write-Host "Some builds failed. Check the output above." -ForegroundColor Yellow
    exit 1
}
