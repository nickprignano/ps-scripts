# ==============================================================================
# Script: Update-NvidiaStudioDrivers.ps1
# Description: Checks current NVIDIA driver version and updates to the latest
#              NVIDIA Studio Driver (CRD). Automatically detects Desktop vs Laptop.
# ==============================================================================

# --- CONFIGURATION ---
$DryRun = $true  
# ---------------------

# 1. Determine System Form Factor (Desktop vs Laptop)
$systemType = (Get-CimInstance -ClassName Win32_ComputerSystem).PCSystemType
$isLaptop = ($systemType -eq 2)

if ($isLaptop) {
    Write-Host "System Form Factor: Laptop detected." -ForegroundColor Cyan
    # psid=121 (Notebooks), isWHQL=1 (Studio Drivers must be WHQL)
    $apiUrl = "https://gfwsl.geforce.com/services_toolkit/services/com/nvidia/services/AjaxDriverService.php?func=DriverManualLookup&psid=121&pfid=883&osID=57&languageCode=1033&beta=0&isWHQL=1&dltype=-1&dch=1&upCRD=1&numberOfResults=1"
} else {
    Write-Host "System Form Factor: Desktop detected." -ForegroundColor Cyan
    # psid=120 (Desktops), isWHQL=1 (Studio Drivers must be WHQL)
    $apiUrl = "https://gfwsl.geforce.com/services_toolkit/services/com/nvidia/services/AjaxDriverService.php?func=DriverManualLookup&psid=120&pfid=958&osID=57&languageCode=1033&beta=0&isWHQL=1&dltype=-1&dch=1&upCRD=1&numberOfResults=1"
}

# 2. Get currently installed NVIDIA driver version
$installedDriver = Get-CimInstance -ClassName Win32_PnPSignedDriver | 
    Where-Object { $_.DeviceName -match "NVIDIA GeForce|NVIDIA RTX|NVIDIA Quadro" } | 
    Select-Object -First 1

if ($installedDriver) {
    $localVersionRaw = $installedDriver.DriverVersion
    try {
        $localVersionStr = ($localVersionRaw -replace '\.', '')[-5..-1] -join ''
        $localVersionStr = $localVersionStr.Insert(3, '.')
        $localVersion = [version]$localVersionStr
        
        # Fix for OEM laptop drivers yielding artificially high version numbers
        if ($localVersion.Major -gt 600) {
            $localVersion = [version]"0.0.0.0"
        }
    } catch {
        $localVersion = [version]"0.0.0.0"
    }
    Write-Host "Current NVIDIA GPU: $($installedDriver.DeviceName)" -ForegroundColor Cyan
    Write-Host "Current Studio Driver Version: $localVersion" -ForegroundColor Cyan
} else {
    Write-Host "No NVIDIA GPU driver detected on this system. Assuming fresh install." -ForegroundColor Yellow
    $localVersion = [version]"0.0.0.0"
}

# 3. Fetch the latest Studio Driver version from NVIDIA's API
Write-Host "`nChecking NVIDIA for the latest Studio Driver..."
try {
    $response = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing
    
    if (-not $response.IDS) {
        throw "No driver data returned from NVIDIA API."
    }

    $latestDriver = $response.IDS[0].downloadInfo
    $latestVersionStr = $latestDriver.Version
    
    if (-not $latestVersionStr) {
        throw "NVIDIA API returned an empty version."
    }

    $latestVersion = [version]$latestVersionStr
    $downloadUrl = $latestDriver.DownloadURL

    Write-Host "Latest Studio Driver Version: $latestVersion" -ForegroundColor Green
} catch {
    Write-Host "Failed to parse NVIDIA API: $_" -ForegroundColor Red
    Exit
}

# 4. Compare versions and execute update
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
