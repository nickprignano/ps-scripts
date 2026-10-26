<#
.SYNOPSIS
    Reports Windows Update health and optionally repairs its service/cache state.
.DESCRIPTION
    The default report runs without elevation and searches the configured update
    source unless -SkipNetworkTest is specified. -Fix performs an explicit
    service/cache repair. -RepairSystemFiles additionally runs DISM and SFC.
.PARAMETER Fix
    Stop and restart Windows Update services and rename their local caches.
.PARAMETER RepairSystemFiles
    With -Fix, run DISM RestoreHealth followed by SFC /scannow.
.PARAMETER SkipNetworkTest
    Skip the online Windows Update Agent search against the configured source.
.EXAMPLE
    .\Test-WindowsUpdateHealth.ps1
.EXAMPLE
    .\Test-WindowsUpdateHealth.ps1 -SkipNetworkTest
.EXAMPLE
    .\Test-WindowsUpdateHealth.ps1 -Fix -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [switch] $Fix,
    [switch] $RepairSystemFiles,
    [switch] $SkipNetworkTest
)

$ErrorActionPreference = 'Stop'
$script:ScriptVersion = '1.0.0'
$script:RepairServiceNames = @('BITS', 'wuauserv', 'CryptSvc')
$script:SearchCriteria = 'IsInstalled=0 and IsHidden=0'

function Get-CurrentUserIsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WindowsUpdateSearch {
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $searcher.Online = $true
        $searcher.ServerSelection = 0
        $result = $searcher.Search($script:SearchCriteria)
        $stopwatch.Stop()
        $updates = @($result.Updates)
        $status = if ([int]$result.ResultCode -eq 2) { 'succeeded' } else { 'failed' }
        $errorCode = $null
        if ($status -eq 'failed') {
            if ($null -ne $result.HResult) {
                $bytes = [BitConverter]::GetBytes([int]$result.HResult)
                $errorCode = '0x{0:X8}' -f [BitConverter]::ToUInt32($bytes, 0)
            } else {
                $errorCode = 'WUAResultCode:{0}' -f [int]$result.ResultCode
            }
        }
        return [pscustomobject]@{
            Status = $status
            ErrorCode = $errorCode
            DurationMilliseconds = [int]$stopwatch.ElapsedMilliseconds
            UpdateCount = $updates.Count
        }
    } catch {
        $stopwatch.Stop()
        $code = $null
        try {
            $bytes = [BitConverter]::GetBytes([int]$_.Exception.HResult)
            $code = '0x{0:X8}' -f [BitConverter]::ToUInt32($bytes, 0)
        } catch { $code = $null }
        return [pscustomobject]@{
            Status = 'failed'
            ErrorCode = $code
            DurationMilliseconds = [int]$stopwatch.ElapsedMilliseconds
            UpdateCount = $null
        }
    }
}

function Get-PolicySnapshot {
    $basePath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    $auPath = Join-Path $basePath 'AU'
    $baseExists = $false
    $auExists = $false
    $baseKnown = $true
    $auKnown = $true
    $au = $null
    try {
        $baseExists = Test-Path -LiteralPath $basePath -ErrorAction Stop
        if ($baseExists) { $null = Get-ItemProperty -LiteralPath $basePath -ErrorAction Stop }
    } catch { $baseKnown = $false }
    try {
        $auExists = Test-Path -LiteralPath $auPath -ErrorAction Stop
        if ($auExists) { $au = Get-ItemProperty -LiteralPath $auPath -ErrorAction Stop }
    } catch { $auKnown = $false }
    $readStatus = if ($baseKnown -and $auKnown) { 'available' } else { 'unknown' }
    $managed = ($auExists -and $null -ne $au -and $au.UseWUServer -eq 1)
    $sourceCategory = if ($readStatus -eq 'unknown') { 'unknown' } elseif ($managed) { 'managed' } else { 'default-selection' }
    return [pscustomobject]@{
        ReadStatus = $readStatus
        UpdatePolicyPresent = if ($baseKnown) { [bool]$baseExists } else { $null }
        AutomaticUpdatePolicyPresent = if ($auKnown) { [bool]$auExists } else { $null }
        UpdateSourceCategory = $sourceCategory
    }
}

function Get-WinHttpProxyState {
    try {
        $text = (& netsh.exe winhttp show proxy 2>$null | Out-String)
        if ($text -match '(?i)Direct access \(no proxy server\)') { return 'unconfigured' }
        if ($text -match '(?im)^\s*Proxy Server\(s\)\s*:\s*(?!\(none\)\s*$).+') { return 'configured' }
    } catch { return 'unknown' }
    return 'unknown'
}

function Get-PendingRebootState {
    $signals = @(
        [pscustomobject]@{
            Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
            Property = $null
        },
        [pscustomobject]@{
            Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
            Property = $null
        },
        [pscustomobject]@{
            Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
            Property = 'PendingFileRenameOperations'
        }
    )
    $unknown = $false
    foreach ($signal in $signals) {
        try {
            if (-not (Test-Path -LiteralPath $signal.Path -ErrorAction Stop)) { continue }
            if ($null -eq $signal.Property) { return 'finding' }
            $key = Get-ItemProperty -LiteralPath $signal.Path -ErrorAction Stop
            if ($null -ne $key.($signal.Property)) { return 'finding' }
        } catch {
            $unknown = $true
        }
    }
    if ($unknown) { return 'unknown' }
    return 'not-detected'
}

function Get-ServiceSnapshot {
    $services = @{}
    try {
        $serviceDetails = @(Get-CimInstance -ClassName Win32_Service -Filter "Name='BITS' OR Name='wuauserv' OR Name='CryptSvc'" -ErrorAction Stop)
    } catch {
        foreach ($name in $script:RepairServiceNames) {
            $services[$name] = [pscustomobject]@{ Status = 'unknown'; StartType = 'unknown' }
        }
        return $services
    }
    foreach ($name in $script:RepairServiceNames) {
        $detail = $serviceDetails | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        $services[$name] = [pscustomobject]@{
            Status = if ($null -eq $detail) { 'unknown' } else { [string]$detail.State }
            StartType = if ($null -eq $detail) { 'unknown' } else { [string]$detail.StartMode }
        }
    }
    return $services
}

function Get-RecentUpdateError {
    $since = (Get-Date).AddDays(-30)
    $errors = @()
    try {
        $events = @(Get-WinEvent -FilterHashtable @{
            LogName = 'System'
            ProviderName = 'Microsoft-Windows-WindowsUpdateClient'
            StartTime = $since
            Level = 2
        } -ErrorAction Stop)
    } catch {
        if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound,*') {
            return [pscustomobject]@{ Status = 'available'; Events = @() }
        }
        return [pscustomobject]@{ Status = 'unknown'; Events = @() }
    }
    foreach ($updateEvent in $events) {
        if ($null -eq $updateEvent.Level -or [int]$updateEvent.Level -ne 2) { continue }
        $message = [string]$updateEvent.Message
        $match = [regex]::Match($message, '(?i)\b(?:error(?:\s+code)?|HRESULT)\s*(?:[:=]\s*|\s+)(0x[0-9a-f]{8})\b')
        if ($match.Success) {
            $errors += [pscustomobject]@{
                Provider = 'Microsoft-Windows-WindowsUpdateClient'
                Id = [int]$updateEvent.Id
                Time = ([datetime]$updateEvent.TimeCreated).ToUniversalTime().ToString('o')
                Code = $match.Groups[1].Value.ToLowerInvariant()
            }
        }
    }
    return [pscustomobject]@{
        Status = 'available'
        Events = @($errors | Sort-Object { [datetime]$_.Time } -Descending)
    }
}

function Write-HealthLog {
    param([Parameter(Mandatory)] $Record)
    $root = Join-Path $env:LOCALAPPDATA 'WindowsUpdateHealth'
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $root -Force -WhatIf:$false
    }
    $fileName = 'WindowsUpdateHealth-{0}-{1}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $path = Join-Path $root $fileName
    $json = $Record | ConvertTo-Json -Depth 8
    Set-Content -LiteralPath $path -Value $json -Encoding UTF8 -WhatIf:$false
    return $path
}

function Add-RepairLogStep {
    param(
        [Parameter(Mandatory)] $Record,
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $Status,
        [AllowNull()][Nullable[int]] $ExitCode
    )
    $Record.repairSteps += [pscustomobject]@{ name = $Name; status = $Status; exitCode = $ExitCode }
}

function Invoke-SystemFileRepair {
    param([Parameter(Mandatory)] $Record)
    foreach ($item in @(
        [pscustomobject]@{ Name = 'DISM RestoreHealth'; File = 'dism.exe'; Arguments = @('/Online', '/Cleanup-Image', '/RestoreHealth') },
        [pscustomobject]@{ Name = 'SFC scannow'; File = 'sfc.exe'; Arguments = @('/scannow') }
    )) {
        try {
            $process = Start-Process -FilePath $item.File -ArgumentList $item.Arguments -Wait -PassThru -NoNewWindow -ErrorAction Stop
            $exitCode = [int]$process.ExitCode
            Add-RepairLogStep -Record $Record -Name $item.Name -Status $(if ($exitCode -eq 0) { 'succeeded' } else { 'failed' }) -ExitCode $exitCode
            Write-Output ('{0}: exit code {1}' -f $item.Name, $exitCode)
        } catch {
            Add-RepairLogStep -Record $Record -Name $item.Name -Status 'failed' -ExitCode $null
            Write-Output ('{0}: failed to start or complete.' -f $item.Name)
        }
    }
}

function Invoke-WindowsUpdateComponentRepair {
    param(
        [Parameter(Mandatory)] $Record,
        [Parameter(Mandatory)][ref] $Ready
    )
    $Ready.Value = $false
    $original = @{}
    foreach ($name in $script:RepairServiceNames) {
        $service = Get-Service -Name $name -ErrorAction Stop
        $original[$name] = ($service.Status -eq 'Running')
    }
    $windows = $env:windir
    $caches = @(
        [pscustomobject]@{ Name = 'SoftwareDistribution'; Original = (Join-Path $windows 'SoftwareDistribution') },
        [pscustomobject]@{ Name = 'catroot2'; Original = (Join-Path $windows 'System32\catroot2') }
    )

    $stopped = $true
    foreach ($name in $script:RepairServiceNames) {
        if (-not $original[$name]) { continue }
        try {
            Stop-Service -Name $name -ErrorAction Stop
            Add-RepairLogStep -Record $Record -Name ("Stop service {0}" -f $name) -Status 'succeeded' -ExitCode 0
        } catch {
            $stopped = $false
            Add-RepairLogStep -Record $Record -Name ("Stop service {0}" -f $name) -Status 'failed' -ExitCode $null
            break
        }
    }

    if (-not $stopped) {
        foreach ($name in $script:RepairServiceNames) {
            if ($original[$name]) {
                try {
                    Start-Service -Name $name -ErrorAction Stop
                    Add-RepairLogStep -Record $Record -Name ("Restore service {0}" -f $name) -Status 'succeeded' -ExitCode 0
                } catch {
                    Add-RepairLogStep -Record $Record -Name ("Restore service {0}" -f $name) -Status 'failed' -ExitCode $null
                }
            }
        }
        Write-Output 'Repair stopped before cache changes; previously running services were restored where possible.'
        return
    }

    $moved = @()
    $renameFailed = $false
    foreach ($cache in $caches) {
        $cacheExists = $false
        try {
            $cacheExists = Test-Path -LiteralPath $cache.Original -PathType Container
        } catch {
            $renameFailed = $true
            Add-RepairLogStep -Record $Record -Name ("Check cache {0}" -f $cache.Name) -Status 'failed' -ExitCode $null
            break
        }
        if (-not $cacheExists) {
            Add-RepairLogStep -Record $Record -Name ("Rename cache {0}" -f $cache.Name) -Status 'not-present' -ExitCode 0
            continue
        }
        $backup = '{0}.bak.{1}.{2}' -f $cache.Original, (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N'))
        try {
            $null = Rename-Item -LiteralPath $cache.Original -NewName (Split-Path -Leaf $backup) -ErrorAction Stop
            $moved += [pscustomobject]@{ Original = $cache.Original; Backup = $backup }
            Add-RepairLogStep -Record $Record -Name ("Rename cache {0}" -f $cache.Name) -Status 'succeeded' -ExitCode 0
        } catch {
            $renameFailed = $true
            Add-RepairLogStep -Record $Record -Name ("Rename cache {0}" -f $cache.Name) -Status 'failed' -ExitCode $null
            break
        }
    }

    if ($renameFailed) {
        for ($moveIndex = $moved.Count - 1; $moveIndex -ge 0; $moveIndex--) {
            $move = $moved[$moveIndex]
            $originalPathOccupied = $true
            try { $originalPathOccupied = Test-Path -LiteralPath $move.Original } catch { $originalPathOccupied = $true }
            if (-not $originalPathOccupied) {
                try {
                    $null = Rename-Item -LiteralPath $move.Backup -NewName (Split-Path -Leaf $move.Original) -ErrorAction Stop
                    Add-RepairLogStep -Record $Record -Name 'Restore renamed cache' -Status 'succeeded' -ExitCode 0
                } catch {
                    Add-RepairLogStep -Record $Record -Name 'Restore renamed cache' -Status 'failed' -ExitCode $null
                    Write-Output ('Manual recovery may be required; retained backup: {0}' -f $move.Backup)
                }
            } else {
                Write-Output ('Original cache path is occupied; retained backup: {0}' -f $move.Backup)
            }
        }
        foreach ($name in $script:RepairServiceNames) {
            if ($original[$name]) {
                try {
                    Start-Service -Name $name -ErrorAction Stop
                    Add-RepairLogStep -Record $Record -Name ("Restore service {0}" -f $name) -Status 'succeeded' -ExitCode 0
                } catch {
                    Add-RepairLogStep -Record $Record -Name ("Restore service {0}" -f $name) -Status 'failed' -ExitCode $null
                }
            }
        }
        Write-Output 'Cache rename failed; no system-file scans were run.'
        return
    }

    $startFailed = $false
    foreach ($name in $script:RepairServiceNames) {
        try {
            Start-Service -Name $name -ErrorAction Stop
            Add-RepairLogStep -Record $Record -Name ("Start service {0}" -f $name) -Status 'succeeded' -ExitCode 0
        } catch {
            $startFailed = $true
            Add-RepairLogStep -Record $Record -Name ("Start service {0}" -f $name) -Status 'failed' -ExitCode $null
        }
    }
    foreach ($move in $moved) { Write-Output ('Cache backup retained: {0}' -f $move.Backup) }
    if ($startFailed) { Write-Output 'Partial repair failure: one or more services could not be started.' }
    else { Write-Output 'Windows Update service/cache repair completed.' }
    $Ready.Value = -not $startFailed
}

if ($RepairSystemFiles -and -not $Fix) {
    throw '-RepairSystemFiles requires -Fix.'
}
if ($Fix -and -not (Get-CurrentUserIsAdministrator)) {
    throw '-Fix requires an elevated PowerShell session. Rerun PowerShell as Administrator.'
}

$policy = Get-PolicySnapshot
$serviceSnapshot = Get-ServiceSnapshot
$os = $null
try { $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop } catch { $os = $null }
$osStatus = if ($null -eq $os) { 'unknown' } else { 'available' }
$osEdition = if ($null -eq $os) { 'unknown' } else { [string]$os.Caption }
$osBuild = if ($null -eq $os) { 'unknown' } else { [string]$os.BuildNumber }
$osArchitecture = if ($null -eq $os) { 'unknown' } else { [string]$os.OSArchitecture }
$currentVersion = $null
try { $currentVersion = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop } catch { $currentVersion = $null }
$displayVersion = if ($null -eq $currentVersion -or [string]::IsNullOrWhiteSpace([string]$currentVersion.DisplayVersion)) { 'unknown' } else { [string]$currentVersion.DisplayVersion }
$systemDrive = if ($null -eq $os -or [string]::IsNullOrWhiteSpace($os.SystemDrive)) { $env:SystemDrive } else { $os.SystemDrive }
$disk = $null
try {
    if (-not [string]::IsNullOrWhiteSpace($systemDrive)) {
        $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$systemDrive'" -ErrorAction Stop | Select-Object -First 1
    }
} catch { $disk = $null }
$freeBytes = $null
if ($null -ne $disk -and $null -ne $disk.PSObject.Properties['FreeSpace'] -and $null -ne $disk.FreeSpace) {
    try { $freeBytes = [int64]$disk.FreeSpace } catch { $freeBytes = $null }
}
$pendingReboot = Get-PendingRebootState
$errorSnapshot = Get-RecentUpdateError
$recentErrors = @($errorSnapshot.Events)
$search = if ($SkipNetworkTest) {
    [pscustomobject]@{ Status = 'skipped'; ErrorCode = $null; DurationMilliseconds = $null; UpdateCount = $null }
} else {
    Get-WindowsUpdateSearch
}

$directFindings = @()
foreach ($name in $script:RepairServiceNames) {
    if ($serviceSnapshot[$name].StartType -eq 'Disabled') { $directFindings += ("{0} is disabled" -f $name) }
}
if ($pendingReboot -eq 'finding') { $directFindings += 'A pending-reboot indicator is present' }
if ($search.Status -eq 'failed') { $directFindings += 'The configured-source Windows Update search failed' }
$unknownServiceNames = @(
    $script:RepairServiceNames | Where-Object {
        $serviceSnapshot[$_].Status -eq 'unknown' -or $serviceSnapshot[$_].StartType -eq 'unknown'
    }
)
$recommendationContextUnknown = $unknownServiceNames.Count -gt 0 -or
    $pendingReboot -eq 'unknown' -or
    $policy.ReadStatus -eq 'unknown' -or
    $osStatus -eq 'unknown' -or
    $null -eq $freeBytes

$latestCode = if ($recentErrors.Count -gt 0) { $recentErrors[0].Code } else { $null }
$nonNetworkDirectFindings = @($directFindings | Where-Object { $_ -ne 'The configured-source Windows Update search failed' })
$systemRepairRecommendation = if ($errorSnapshot.Status -eq 'unknown') { 'unknown/deferred' } else { 'not-recommended' }
$recommendationText = if ($errorSnapshot.Status -eq 'unknown') {
    'System-file repair recommendation is unknown/deferred because Windows Update error events could not be read.'
} else {
    'No report-only evidence recommends DISM/SFC.'
}
if ($latestCode -eq '0x800f0922') {
    $recommendationText = 'Finding: 0x800f0922 can involve insufficient space or other components. Review measured free space and Microsoft storage/issue-specific checks; this code alone does not recommend DISM/SFC.'
} elseif ($latestCode -in @('0x80070057', '0x80080005')) {
    if ($nonNetworkDirectFindings.Count -gt 0) {
        $systemRepairRecommendation = 'deferred'
        $recommendationText = 'Address direct findings first; system-file repair is not recommended in this report.'
    } elseif ($recommendationContextUnknown) {
        $systemRepairRecommendation = 'unknown/deferred'
        $recommendationText = 'System-file repair recommendation is unknown/deferred because one or more health checks could not be completed.'
    } elseif ($search.Status -eq 'succeeded') {
        $systemRepairRecommendation = 'recommended'
        $recommendationText = 'Recommendation: consider -Fix -RepairSystemFiles. These codes can be associated with corrupted files or incorrect configuration; they do not prove system-file corruption.'
    } else {
        $systemRepairRecommendation = 'unknown/deferred'
        $recommendationText = 'System-file repair recommendation is unknown/deferred because the configured-source search was skipped or did not complete successfully.'
    }
} elseif ($null -ne $latestCode) {
    $recommendationText = 'This error code alone does not recommend DISM/SFC. Consider the separate option only if the issue persists after findings and Microsoft first-line guidance.'
}

$record = [pscustomobject][ordered]@{
    timestamp = (Get-Date).ToUniversalTime().ToString('o')
    scriptVersion = $script:ScriptVersion
    windows = [pscustomobject][ordered]@{
        edition = $osEdition
        displayVersion = $displayVersion
        build = $osBuild
        architecture = $osArchitecture
    }
    policyReadStatus = $policy.ReadStatus
    updateSourceCategory = $policy.UpdateSourceCategory
    policies = [pscustomobject][ordered]@{
        updatePolicyPresent = $policy.UpdatePolicyPresent
        automaticUpdatePolicyPresent = $policy.AutomaticUpdatePolicyPresent
    }
    winHttpProxy = Get-WinHttpProxyState
    services = @(
        foreach ($name in $script:RepairServiceNames) {
            [pscustomobject][ordered]@{ name = $name; status = $serviceSnapshot[$name].Status; startType = $serviceSnapshot[$name].StartType }
        }
    )
    systemDriveFreeBytes = $freeBytes
    pendingReboot = $pendingReboot
    eventLogStatus = $errorSnapshot.Status
    eventErrors = @(
        foreach ($errorEvent in $recentErrors) {
            [pscustomobject][ordered]@{ provider = $errorEvent.Provider; id = $errorEvent.Id; time = $errorEvent.Time; errorCode = $errorEvent.Code }
        }
    )
    search = [pscustomobject][ordered]@{
        status = $search.Status
        errorCode = $search.ErrorCode
        durationMilliseconds = $search.DurationMilliseconds
        updateCount = $search.UpdateCount
    }
    repairSteps = @()
}

Write-Output 'Windows Update health report'
Write-Output ('Windows: {0}; display version {1}; build {2}; {3}' -f $osEdition, $displayVersion, $osBuild, $osArchitecture)
Write-Output ('Update source: {0}; policy read status: {1}; policy present: {2}; WinHTTP proxy: {3}' -f $policy.UpdateSourceCategory, $policy.ReadStatus, $policy.UpdatePolicyPresent, $record.winHttpProxy)
foreach ($name in $script:RepairServiceNames) {
    $serviceState = if ($serviceSnapshot[$name].StartType -eq 'Disabled') { 'finding' } elseif ($serviceSnapshot[$name].StartType -eq 'unknown') { 'unknown' } else { 'not disabled' }
    Write-Output ('Service {0}: {1}; start type {2}; {3}' -f $name, $serviceSnapshot[$name].Status, $serviceSnapshot[$name].StartType, $serviceState)
}
if ($null -eq $freeBytes) { Write-Output 'Unknown: system-drive free space could not be read.' }
else { Write-Output ('System-drive free space: {0} bytes (measurement only)' -f $freeBytes) }
switch ($pendingReboot) {
    'finding' { Write-Output 'Pending reboot: finding' }
    'unknown' { Write-Output 'Pending reboot: unknown; one or more indicators could not be read.' }
    default { Write-Output 'Pending reboot: not detected' }
}
Write-Output ('Network search: {0}; error code: {1}; duration ms: {2}; update count: {3}' -f $search.Status, $search.ErrorCode, $search.DurationMilliseconds, $search.UpdateCount)
if ($errorSnapshot.Status -eq 'unknown') {
    Write-Output 'Unknown: Windows Update error events could not be read.'
} elseif ($recentErrors.Count -gt 0) {
    Write-Output ('Latest Windows Update error: {0}' -f $latestCode)
} else {
    Write-Output 'No error-level Windows Update events with a code were found in the last 30 days.'
}
if ($directFindings.Count -gt 0) {
    foreach ($finding in $directFindings) { Write-Output ('Finding: {0}.' -f $finding) }
}
if ($unknownServiceNames.Count -gt 0) { Write-Output 'Unknown: one or more repair service states/configurations could not be read.' }
if ($pendingReboot -eq 'unknown') { Write-Output 'Unknown: pending-reboot indicators could not all be read.' }
if ($policy.ReadStatus -eq 'unknown') { Write-Output 'Unknown: Windows Update policy configuration could not be read.' }
if ($errorSnapshot.Status -eq 'unknown') { Write-Output 'Unknown: Windows Update error events could not be read.' }
if ($osStatus -eq 'unknown') { Write-Output 'Unknown: Windows system information could not be read.' }
if ($directFindings.Count -eq 0 -and $unknownServiceNames.Count -eq 0 -and $pendingReboot -ne 'unknown' -and $policy.ReadStatus -ne 'unknown' -and $errorSnapshot.Status -ne 'unknown' -and $osStatus -ne 'unknown' -and $null -ne $freeBytes) {
    Write-Output 'Pass: no direct service, search, or pending-reboot finding was detected.'
}
foreach ($name in $unknownServiceNames) { Write-Output ('Unknown: service state/configuration for {0} could not be read.' -f $name) }
Write-Output ('System-file repair recommendation: {0}' -f $systemRepairRecommendation)
Write-Output $recommendationText
Write-Output 'Manual checks: power, external devices, date/time, driver and security-software compatibility, and managed-network conditions are not verified.'
$logPath = Write-HealthLog -Record $record
Write-Output ('Local report log: {0}' -f $logPath)

if ($Fix) {
    $planned = if ($RepairSystemFiles) { 'Stop/restart BITS, wuauserv, CryptSvc; rename update caches; then run DISM RestoreHealth and SFC /scannow' } else { 'Stop/restart BITS, wuauserv, CryptSvc and rename update caches' }
    if ($PSCmdlet.ShouldProcess('Windows Update components', $planned)) {
        $cacheRepairReady = $false
        Invoke-WindowsUpdateComponentRepair -Record $record -Ready ([ref]$cacheRepairReady)
        if ($RepairSystemFiles -and $cacheRepairReady) {
            Invoke-SystemFileRepair -Record $record
        } elseif ($RepairSystemFiles) {
            Write-Output 'DISM/SFC were not run because the service/cache repair did not complete.'
        }
        $updatedLogPath = Write-HealthLog -Record $record
        Write-Output ('Updated local report log: {0}' -f $updatedLogPath)
    } else {
        Write-Output ('Plan only: {0}' -f $planned)
    }
}
