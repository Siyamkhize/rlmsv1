# Production Build Script
# Builds production APK with proper Java environment

Write-Host "Building Production APK" -ForegroundColor Cyan
Write-Host "======================`n" -ForegroundColor Cyan

# Set Java Home
$env:JAVA_HOME = "C:\Program Files\Java\jdk-17.0.12"
Write-Host "Java Home: $env:JAVA_HOME" -ForegroundColor Green

# Clean Gradle cache (prevents Java home errors)
Write-Host "Cleaning Gradle cache..." -ForegroundColor Yellow
Remove-Item -Recurse -Force android\.gradle -ErrorAction SilentlyContinue
Write-Host "Cache cleaned`n" -ForegroundColor Green

# Build production APK
Write-Host "Building production APK..." -ForegroundColor Yellow
Write-Host "   Flavor: production" -ForegroundColor Gray
Write-Host "   Mode: release" -ForegroundColor Gray
Write-Host "   Entry: lib/main.dart`n" -ForegroundColor Gray

$startTime = Get-Date
flutter build apk --release --flavor production -t lib/main.dart
$endTime = Get-Date
$duration = $endTime - $startTime

Write-Host "`n"
if ($LASTEXITCODE -eq 0 -or (Test-Path "build\app\outputs\flutter-apk\app-productionRelease.apk")) {
    Write-Host "Build completed!" -ForegroundColor Green
    Write-Host "Duration: $($duration.ToString('mm\:ss'))" -ForegroundColor Cyan
    
    if (Test-Path "build\app\outputs\flutter-apk\app-productionRelease.apk") {
        $apk = Get-Item "build\app\outputs\flutter-apk\app-productionRelease.apk"
        $sizeMB = [math]::Round($apk.Length/1MB, 2)
        
        Write-Host "`nAPK Details:" -ForegroundColor Cyan
        Write-Host "   File: app-productionRelease.apk" -ForegroundColor White
        Write-Host "   Size: $sizeMB MB" -ForegroundColor White
        Write-Host "   Location: build\app\outputs\flutter-apk\" -ForegroundColor White
        Write-Host "   Package: com.example.rlmss" -ForegroundColor White
        Write-Host "   Version: 1.0.6+8" -ForegroundColor White
        
        Write-Host "`nProduction APK ready for deployment!" -ForegroundColor Green
    }
} else {
    Write-Host "Build failed!" -ForegroundColor Red
    Write-Host "Check the output above for errors." -ForegroundColor Yellow
    exit 1
}
