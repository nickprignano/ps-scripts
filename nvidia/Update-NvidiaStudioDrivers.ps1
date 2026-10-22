# ==============================================================================
# Script: AutoUpdate-NvidiaStudioDriver.ps1
# Description: Checks current NVIDIA driver version and updates to the latest
#              NVIDIA Studio Driver (CRD).
# ==============================================================================

# --- CONFIGURATION ---
$DryRun = $true  # Change this to $false to actually download and install the driver
# ---------------------

# 1. Get currently installed NVIDIA driver version
$installedDriver = Get-CimInstance -ClassName Win32_PnPSignedDriver | 
    Where-Object { $_.DeviceName -match "NVIDIA GeForce|NVIDIA RTX|NVIDIA Quadro" } | 
    Select-Object -First 1

if ($installedDriver) {
    # Convert Windows version format (e.g., 32.0.15.5585) to standard NVIDIA format (e.g., 555.85)
    $localVersionRaw = $installedDriver.DriverVersion
    $localVersionStr = ($localVersionRaw -replace '\.', '')[-5..-1] -join ''
    $localVersionStr = $localVersionStr.Insert(3, '.')
    $localVersion = [version]$localVersionStr
    Write-Host "Current NVIDIA GPU: $($installedDriver.DeviceName)" -ForegroundColor Cyan
    Write-Host "Current Studio Driver Version: $localVersion" -ForegroundColor Cyan
} else {
    Write-Host "No NVIDIA GPU driver detected on this system. Assuming fresh install." -ForegroundColor Yellow
    $localVersion = [version]"0.0.0.0"
}

# 2. Fetch the latest Studio Driver version from NVIDIA's API
# psid=120 and pfid=958 represent generic modern RTX Desktop architecture (DCH unified drivers)
# upCRD=1 enforces fetching the Studio Driver (Creator Ready Driver)
$apiUrl = "https://gfwsl.geforce.com/services_toolkit/services/com/nvidia/services/AjaxDriverService.php?func=DriverManualLookup&psid=120&pfid=958&osID=57&languageCode=1033&beta=0&isWHQL=0&dltype=-1&dch=1&upCRD=1&numberOfResults=1"

Write-Host "`nChecking NVIDIA for the latest Studio Driver..."
try {
    $response = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing
    
    if (-not $response.IDS) {
        throw "No driver data returned from NVIDIA API."
    }

    $latestDriver = $response.IDS[0].downloadInfo
    $latestVersion = [version]$latestDriver.Version
    $downloadUrl = $latestDriver.DownloadURL

    Write-Host "Latest Studio Driver Version: $latestVersion" -ForegroundColor Green
} catch {
    Write-Host "Failed to parse NVIDIA API. The endpoint might have changed or is temporarily unreachable." -ForegroundColor Red
    Write-Host "Error details: $_" -ForegroundColor Red
    Exit
}

# 3. Compare versions and execute update
if ($latestVersion -gt $localVersion) {
    Write-Host "`nNew Studio Driver found! (v$latestVersion)" -ForegroundColor Yellow
    
    $installerPath = "$env:TEMP\NVIDIA_Studio_Driver_$latestVersion.exe"
    $installArgs = "-s -n Display.Driver -log:`"C:\NVIDIA_Install_Log.txt`" -loglevel:6"
    
    if ($DryRun) {
        # ---- DRY RUN BEHAVIOR ----
        Write-Host "`n[DRY RUN MODE ENABLED] - No changes will be made to your system." -ForegroundColor Magenta
        Write-Host "Action 1: Would download from:" -ForegroundColor Gray
        Write-Host "  $downloadUrl" -ForegroundColor Gray
        Write-Host "Action 2: Would save file to:" -ForegroundColor Gray
        Write-Host "  $installerPath" -ForegroundColor Gray
        Write-Host "Action 3: Would execute installer with these silent arguments:" -ForegroundColor Gray
        Write-Host "  $installArgs" -ForegroundColor Gray
        Write-Host "`nTo actually update your driver, change `$DryRun = `$true to `$false at the top of the script." -ForegroundColor Yellow
    } else {
        # ---- ACTUAL EXECUTION BEHAVIOR ----
        Write-Host "`nDownloading v$latestVersion..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing
        
        Write-Host "Download complete. Starting silent installation (this may take a few minutes)..." -ForegroundColor Cyan
        
        $process = Start-Process -FilePath $installerPath -ArgumentList $installArgs -Wait -NoNewWindow -PassThru
        
        if ($process.ExitCode -eq 0) {
            Write-Host "NVIDIA Studio Driver updated successfully to v$latestVersion!" -ForegroundColor Green
        } elseif ($process.ExitCode -eq 14 -or $process.ExitCode -eq 3010) {
            Write-Host "Driver installed successfully, but a system reboot is required." -ForegroundColor Yellow
        } else {
            Write-Host "Installation finished with exit code $($process.ExitCode). Check C:\NVIDIA_Install_Log.txt for details." -ForegroundColor Red
        }
        
        # Clean up the 600MB+ installer file to save space
        Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
    }
} else {
    Write-Host "`nYou are already on the latest Studio Driver (v$localVersion). No update needed." -ForegroundColor Green
}
