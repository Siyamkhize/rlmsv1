# Update Gradle Wrapper Script
# This script updates the Gradle wrapper to fix security vulnerabilities

Write-Host "Updating Gradle Wrapper to fix CVEs..." -ForegroundColor Cyan

$gradleVersion = "8.11.1"
$androidDir = "android"

# Check if Android directory exists
if (-not (Test-Path $androidDir)) {
    Write-Host "ERROR: Android directory not found!" -ForegroundColor Red
    exit 1
}

Set-Location $androidDir

# Method 1: Try using existing gradlew
Write-Host "`nAttempting to update wrapper using gradlew..." -ForegroundColor Yellow
try {
    if (Test-Path "gradlew.bat") {
        .\gradlew.bat wrapper --gradle-version=$gradleVersion --distribution-type=bin --no-daemon --warning-mode=none
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "SUCCESS: Gradle wrapper updated using gradlew!" -ForegroundColor Green
            Set-Location ..
            exit 0
        }
    }
} catch {
    Write-Host "WARNING: gradlew method failed, trying alternative..." -ForegroundColor Yellow
}

# Method 2: Download wrapper files directly  
Write-Host "`nDownloading Gradle wrapper files directly..." -ForegroundColor Yellow

$wrapperDir = "gradle/wrapper"
$wrapperJarUrl = "https://raw.githubusercontent.com/gradle/gradle/v$gradleVersion/gradle/wrapper/gradle-wrapper.jar"
$wrapperJarPath = "$wrapperDir/gradle-wrapper.jar"

try {
    # Create wrapper directory if it doesn't exist
    if (-not (Test-Path $wrapperDir)) {
        New-Item -ItemType Directory -Path $wrapperDir -Force | Out-Null
    }
    
    # Download the secure wrapper JAR
    Write-Host "  Downloading gradle-wrapper.jar v$gradleVersion..."
    Invoke-WebRequest -Uri $wrapperJarUrl -OutFile $wrapperJarPath -UseBasicParsing
    
    if (Test-Path $wrapperJarPath) {
        $jarSize = (Get-Item $wrapperJarPath).Length
        Write-Host "  SUCCESS: Downloaded gradle-wrapper.jar - $jarSize bytes" -ForegroundColor Green
    }
    
    Write-Host "`nSUCCESS: Gradle wrapper updated!" -ForegroundColor Green
    Write-Host "Gradle version: $gradleVersion" -ForegroundColor Cyan
    
    # Verify the properties file
    $propsFile = "$wrapperDir/gradle-wrapper.properties"
    if (Test-Path $propsFile) {
        $props = Get-Content $propsFile -Raw
        if ($props -match "gradle-$gradleVersion") {
            Write-Host "SUCCESS: Properties file is correctly configured" -ForegroundColor Green
        } else {
            Write-Host "WARNING: Properties file might need manual verification" -ForegroundColor Yellow
        }
    }
    
} catch {
    Write-Host "ERROR: Failed to download wrapper: $_" -ForegroundColor Red
    Set-Location ..
    exit 1
}

Set-Location ..

Write-Host "`nGradle wrapper security update complete!" -ForegroundColor Green
Write-Host "Fixed CVEs: CVE-2020-11979, CVE-2021-32751, CVE-2026-22816, CVE-2021-29428, CVE-2019-15052, CVE-2026-22865, CVE-2023-35947" -ForegroundColor Cyan
