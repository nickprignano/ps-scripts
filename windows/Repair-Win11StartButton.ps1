# Windows Start Menu Diagnostic & Repair Script
# Must be executed in PowerShell as Administrator

Write-Host "=== Starting Start Menu Repair Routine ===" -ForegroundColor Cyan

# Step 1: Restart Windows Explorer
Write-Host "`n[1/4] Restarting Windows Explorer..." -ForegroundColor Yellow
Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Write-Host "Windows Explorer process restarted." -ForegroundColor Green

# Step 2: Restart the Start Menu Host Process
Write-Host "`n[2/4] Resetting Start Menu Host Process..." -ForegroundColor Yellow
Stop-Process -Name "StartMenuExperienceHost" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
Write-Host "Start Menu process reset complete." -ForegroundColor Green

# Step 3: Re-register Start Menu & Shell AppX Packages
Write-Host "`n[3/4] Re-registering Start Menu App Packages..." -ForegroundColor Yellow
try {
    Get-AppxPackage -AllUsers -Name "Microsoft.Windows.StartMenuExperienceHost" | ForEach-Object {
        Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml"
    }
    Get-AppxPackage -AllUsers -Name "Microsoft.Windows.ShellExperienceHost" | ForEach-Object {
        Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml"
    }
    Write-Host "Start Menu packages successfully re-registered." -ForegroundColor Green
} catch {
    Write-Host "Package registration generated warnings or requires a reboot." -ForegroundColor Yellow
}

# Step 4: System File Integrity Check
Write-Host "`n[4/4] Running System File Checker (SFC)..." -ForegroundColor Yellow
sfc /scannow

Write-Host "`n=== Repair Routine Complete ===" -ForegroundColor Cyan
Write-Host "If the issue persists, restart your computer to apply all system fixes." -ForegroundColor White
