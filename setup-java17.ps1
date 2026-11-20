# Setup Java 17 for Flutter/Android builds
# Run this script to configure Java 17 for the current session

Write-Host "Setting up Java 17 for this project..." -ForegroundColor Cyan

# Set for current session
$env:JAVA_HOME = "C:\Program Files\Java\jdk-17.0.12"
$env:PATH = "$env:JAVA_HOME\bin;" + $env:PATH

Write-Host ""
Write-Host "SUCCESS: Java 17 configured for current session" -ForegroundColor Green

# Verify
Write-Host ""
Write-Host "Verification:" -ForegroundColor Yellow
Write-Host "JAVA_HOME: $env:JAVA_HOME"
Write-Host ""
Write-Host "Java version:"
java -version
Write-Host ""
Write-Host "Javac version:"
javac -version

Write-Host ""
Write-Host "Setup complete! You can now build your Flutter app." -ForegroundColor Green
Write-Host "To build APK, run: .\build-apk.bat" -ForegroundColor Cyan
