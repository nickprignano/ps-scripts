<#
.SYNOPSIS
    Windows 11 local security health check and narrowly scoped repair.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Test seams for Pester.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingEmptyCatchBlock', '', Justification = 'Bounded unknown results.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Compatibility parameters reserved by spec.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSupportsShouldProcess', '', Justification = 'WhatIf is passed through from the script.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Folder creation is guarded and testable.')]
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$CloudCheck,
    [switch]$LiveUpdateCheck,
    [switch]$Fix,
    [switch]$RepairSystemFiles,
    [switch]$SkipNetworkTest,
    [string]$OutputDirectory
)

$script:SecurityScriptVersion = '1.0.0'
$script:LifecycleTableAsOf = '2026-10-13'
$script:ScriptName = 'Test-WindowsSecurityHealth'

# ---- Mockable seams (tests may override via $global:SecurityMock_<Name>) ----
function Get-SecurityElevation {
    if ($global:SecurityMock_GetSecurityElevation) { return & $global:SecurityMock_GetSecurityElevation }
    try {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
        return [bool]$principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}
function Test-IsRemoteOutputPath {
    param([string]$Path)
    if ($global:SecurityMock_TestIsRemoteOutputPath) { return & $global:SecurityMock_TestIsRemoteOutputPath $Path }
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try {
        if ($Path -match '^\\\\') { return $true }
    } catch { $null = $_ }
    return $false
}
function New-UniqueReportFolder {
    param([string]$Parent)
    if ($global:SecurityMock_NewUniqueReportFolder) { return & $global:SecurityMock_NewUniqueReportFolder $Parent }
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $base = Join-Path $Parent "$script:ScriptName-$timestamp"
    if (-not (Test-Path -LiteralPath $base)) { return $base }
    for ($i = 1; $i -le 100; $i++) {
        $candidate = "$base-$i"
        if (-not (Test-Path -LiteralPath $candidate)) { return $candidate }
    }
    return $null
}
function Invoke-SecurityMapsValidation {
    if ($global:SecurityMock_InvokeSecurityMapsValidation) { return & $global:SecurityMock_InvokeSecurityMapsValidation }
    $result = [pscustomobject]@{ Status = 'Unknown'; DurationMs = 0; ErrorCode = $null; RawOutput = '' }
    try {
        $start = Get-Date
        $mpcmd = Join-Path $env:ProgramFiles 'Windows Defender\MpCmdRun.exe'
        if (-not (Test-Path -LiteralPath $mpcmd)) {
            $result.DurationMs = [int]((Get-Date) - $start).TotalMilliseconds
            return $result
        }
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $mpcmd
        $psi.Arguments = '-ValidateMapsConnection'
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $p = [System.Diagnostics.Process]::Start($psi)
        $stdout = $p.StandardOutput.ReadToEnd()
        $stderr = $p.StandardError.ReadToEnd()
        $p.WaitForExit()
        $result.DurationMs = [int]((Get-Date) - $start).TotalMilliseconds
        $result.RawOutput = ($stdout + $stderr)
        if ($p.ExitCode -eq 0) { $result.Status = 'Pass' } else { $result.Status = 'Finding' }
        if ($result.RawOutput -match 'hr\s*=\s*(0x[0-9A-Fa-f]+)') { $result.ErrorCode = $matches[1] }
    } catch { $result.Status = 'Unknown' }
    return $result
}
function Get-SecurityDefenderState {
    if ($global:SecurityMock_GetSecurityDefenderState) { return & $global:SecurityMock_GetSecurityDefenderState }
    $out = [pscustomobject]@{
        Available = $false; RunningMode = $null; SignaturesOutOfDate = $null
        AntivirusEnabled = $null; RealTimeProtectionEnabled = $null
        BehaviorMonitorEnabled = $null; IoavProtectionEnabled = $null
        NISEnabled = $null; TamperProtected = $null
        CloudBlockLevel = $null; PUAProtection = $null
        ControlledFolderAccess = $null; AttackSurfaceReduction = $null
        SignatureAgeDays = $null; ExclusionPresence = $null
        WscDefenderOn = $null; WscThirdPartyAvOn = $null; WscAvailable = $false
    }
    try {
        if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
            $s = Get-MpComputerStatus
            $out.Available = $true
            $out.RunningMode = $s.AMRunningMode
            $out.SignaturesOutOfDate = $s.DefenderSignaturesOutOfDate
            $out.AntivirusEnabled = $s.AntivirusEnabled
            $out.RealTimeProtectionEnabled = $s.RealTimeProtectionEnabled
            $out.BehaviorMonitorEnabled = $s.BehaviorMonitorEnabled
            $out.IoavProtectionEnabled = $s.IoavProtectionEnabled
            $out.NISEnabled = $s.NISEnabled
            $out.TamperProtected = $s.IsTamperProtected
            $out.SignatureAgeDays = $s.AntivirusSignatureAge
            try { $out.CloudBlockLevel = (Get-MpPreference).CloudBlockLevel } catch { $null = $_ }
            try { $out.PUAProtection = (Get-MpPreference).PUAProtection } catch { $null = $_ }
            try { $out.ControlledFolderAccess = (Get-MpPreference).EnableControlledFolderAccess } catch { $null = $_ }
            try { $out.AttackSurfaceReduction = (Get-MpPreference).AttackSurfaceReductionRules_Ids } catch { $null = $_ }
            try {
                $excl = (Get-MpPreference).ExclusionPath
                $out.ExclusionPresence = if ($excl) { 'Present' } else { 'None' }
            } catch { $null = $_ }
        }
    } catch { $null = $_ }
    try {
        $wsc = Get-SecurityWscProviderState
        if ($null -ne $wsc) {
            $out.WscAvailable = [bool]$wsc.Available
            $out.WscDefenderOn = $wsc.DefenderOn
            $out.WscThirdPartyAvOn = $wsc.ThirdPartyAvOn
        }
    } catch { $null = $_ }
    return $out
}
function Get-SecurityWscProviderState {
    if ($global:SecurityMock_GetSecurityWscProviderState) { return & $global:SecurityMock_GetSecurityWscProviderState }
    return [pscustomobject]@{ Available = $false; DefenderOn = $null; ThirdPartyAvOn = $null }
}
function Get-SecurityFirewallState {
    if ($global:SecurityMock_GetSecurityFirewallState) { return & $global:SecurityMock_GetSecurityFirewallState }
    $profiles = @()
    try {
        if (Get-Command Get-NetFirewallProfile -ErrorAction SilentlyContinue) {
            $raw = Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction Stop
            foreach ($p in $raw) {
                $profiles += [pscustomobject]@{ Name = $p.Name; Enabled = [bool]$p.Enabled; Available = $true; ManagedSignal = $null }
            }
        }
    } catch { $null = $_ }
    return $profiles
}
function Get-SecuritySmartScreenState {
    if ($global:SecurityMock_GetSecuritySmartScreenState) { return & $global:SecurityMock_GetSecuritySmartScreenState }
    $signals = [pscustomobject]@{ ShellEnabled = $null; ShellPolicyPresent = $false; EdgeEnabled = $null; EdgePolicyPresent = $false; EffectiveKnown = $false }
    try {
        foreach ($rp in @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\System','HKCU:\SOFTWARE\Policies\Microsoft\Windows\System')) {
            if (Test-Path -LiteralPath $rp) {
                $v = (Get-ItemProperty -LiteralPath $rp -Name 'EnableSmartScreen' -ErrorAction SilentlyContinue).EnableSmartScreen
                if ($null -ne $v) { $signals.ShellPolicyPresent = $true; $signals.ShellEnabled = ($v -eq 1) }
            }
        }
        $edgePath = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
        if (Test-Path -LiteralPath $edgePath) {
            $ev = (Get-ItemProperty -LiteralPath $edgePath -Name 'SmartScreenEnabled' -ErrorAction SilentlyContinue).SmartScreenEnabled
            if ($null -ne $ev) { $signals.EdgePolicyPresent = $true; $signals.EdgeEnabled = ($ev -eq 1) }
        }
    } catch { $null = $_ }
    return $signals
}
function Get-SecurityPlatformState {
    if ($global:SecurityMock_GetSecurityPlatformState) { return & $global:SecurityMock_GetSecurityPlatformState }
    $out = [pscustomobject]@{
        OsCaption = $null; OsVersion = $null; OsBuild = $null; OsArchitecture = $null
        EditionFamily = $null; DisplayVersion = $null; SecureBoot = $null
        TpmPresent = $null; TpmReady = $null; BitLockerOsVolume = $null
        VbsStatus = $null; MemoryIntegrityConfigured = $null; MemoryIntegrityRunning = $null
        UacEnabled = $null; LocalUpdateHistoryCount = 0
    }
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $out.OsCaption = $os.Caption; $out.OsVersion = $os.Version
        $out.OsBuild = $os.BuildNumber; $out.OsArchitecture = $os.OSArchitecture
    } catch { $null = $_ }
    try {
        $cv = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        $out.EditionFamily = $cv.EditionID; $out.DisplayVersion = $cv.DisplayVersion
    } catch { $null = $_ }
    try {
        if (Get-Command Confirm-SecureBootUEFI -ErrorAction SilentlyContinue) { $out.SecureBoot = [bool](Confirm-SecureBootUEFI) }
    } catch { $out.SecureBoot = $null }
    try {
        if (Get-Command Get-Tpm -ErrorAction SilentlyContinue) {
            $t = Get-Tpm; $out.TpmPresent = [bool]$t.TpmPresent; $out.TpmReady = [bool]$t.TpmReady
        }
    } catch { $null = $_ }
    try {
        if (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue) {
            $v = Get-BitLockerVolume -MountPoint $env:SystemDrive
            if ($v) { $out.BitLockerOsVolume = [pscustomobject]@{ VolumeStatus = $v.VolumeStatus; ProtectionStatus = $v.ProtectionStatus; EncryptionPercentage = $v.EncryptionPercentage } }
        }
    } catch { $null = $_ }
    try {
        $dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction Stop
        if ($dg) {
            $dg = $dg | Select-Object -First 1
            $out.VbsStatus = $dg.VirtualizationBasedSecurityStatus
            $out.MemoryIntegrityConfigured = ($dg.SecurityServicesConfigured -contains 2)
            $out.MemoryIntegrityRunning = ($dg.SecurityServicesRunning -contains 2)
        }
    } catch { $null = $_ }
    try {
        $uac = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'EnableLUA' -ErrorAction SilentlyContinue).EnableLUA
        if ($null -ne $uac) { $out.UacEnabled = ($uac -eq 1) }
    } catch { $null = $_ }
    try {
        $hist = Get-HotFix -ErrorAction SilentlyContinue
        if ($hist) { $out.LocalUpdateHistoryCount = @($hist).Count }
    } catch { $null = $_ }
    return $out
}
function Get-SecurityLifecycleStatus {
    param([string]$EditionFamily,[string]$Channel,[string]$DisplayVersion)
    if ($global:SecurityMock_GetSecurityLifecycleStatus) { return & $global:SecurityMock_GetSecurityLifecycleStatus $EditionFamily $Channel $DisplayVersion }
    $table = @(
        @{ Edition='Professional'; Channel='GA'; Version='25H2'; Status='Supported'; EndDate='2027-10-12' }
        @{ Edition='Professional'; Channel='GA'; Version='24H2'; Status='End of updates'; EndDate='2026-10-14' }
        @{ Edition='Enterprise'; Channel='GA'; Version='25H2'; Status='Supported'; EndDate='2028-10-10' }
        @{ Edition='Education'; Channel='GA'; Version='25H2'; Status='Supported'; EndDate='2028-10-10' }
    )
    foreach ($row in $table) {
        if ($row.Edition -eq $EditionFamily -and $row.Channel -eq $Channel -and $row.Version -eq $DisplayVersion) {
            return [pscustomobject]@{ Status = $row.Status; EndDate = $row.EndDate; TableAsOf = $script:LifecycleTableAsOf }
        }
    }
    return [pscustomobject]@{ Status = 'Unknown'; EndDate = $null; TableAsOf = $script:LifecycleTableAsOf }
}
function Invoke-SecurityLiveUpdateCheck {
    if ($global:SecurityMock_InvokeSecurityLiveUpdateCheck) { return & $global:SecurityMock_InvokeSecurityLiveUpdateCheck }
    $result = [pscustomobject]@{ Status = 'Unknown'; DurationMs = 0; UpdateCount = 0; ErrorCode = $null }
    try {
        $start = Get-Date
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $searcher.Online = $true
        $sr = $searcher.Search('IsInstalled=0 and IsHidden=0')
        $result.DurationMs = [int]((Get-Date) - $start).TotalMilliseconds
        if ($sr.ResultCode -eq 2) { $result.Status = 'Pass'; $result.UpdateCount = @($sr.Updates).Count }
        else { $result.Status = 'Finding'; $result.UpdateCount = @($sr.Updates).Count }
    } catch { $result.Status = 'Unknown' }
    return $result
}
function Test-SecurityRepairPredicate {
    param($DefenderState)
    if ($global:SecurityMock_TestSecurityRepairPredicate) { return & $global:SecurityMock_TestSecurityRepairPredicate $DefenderState }
    if ($null -eq $DefenderState) { return $false }
    if ($DefenderState.SignaturesOutOfDate -ne $true) { return $false }
    if ($DefenderState.RunningMode -ne 'Normal') { return $false }
    if ($DefenderState.WscDefenderOn -ne $true) { return $false }
    if ($DefenderState.WscThirdPartyAvOn -eq $true) { return $false }
    return $true
}
function Invoke-SecurityRepair {
    param([switch]$WhatIf)
    if ($global:SecurityMock_InvokeSecurityRepair) { return & $global:SecurityMock_InvokeSecurityRepair -WhatIf:$WhatIf }
    $result = [pscustomobject]@{ Status = 'Skipped'; Action = 'Update-MpSignature'; Reason = 'Not eligible' }
    if (-not (Get-SecurityElevation)) {
        $result.Reason = 'Requires an already elevated PowerShell session; script does not self-elevate.'
        return $result
    }
    $ds = Get-SecurityDefenderState
    if (-not (Test-SecurityRepairPredicate -DefenderState $ds)) {
        $result.Reason = 'Defender is not the active provider with confirmed stale signatures.'
        return $result
    }
    if ($WhatIf) {
        $result.Status = 'WhatIf'
        $result.Reason = 'Would run Update-MpSignature using the configured source/fallback order.'
        return $result
    }
    try {
        Update-MpSignature
        $result.Status = 'Pass'
        $result.Reason = 'Update-MpSignature completed.'
    } catch {
        $result.Status = 'Unknown'
        $result.Reason = 'Update-MpSignature failed; no settings were changed.'
    }
    return $result
}
function ConvertTo-SecurityHtml {
    param([hashtable]$Report)
    if ($global:SecurityMock_ConvertToSecurityHtml) { return & $global:SecurityMock_ConvertToSecurityHtml $Report }
    function ConvertTo-HtmlEncoded { param([string]$s) if ($null -eq $s) { return '' }; return $s.Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;').Replace('"','&quot;') }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<!DOCTYPE html><html><head><meta charset="utf-8"><title>Windows Security Health</title></head><body>')
    [void]$sb.AppendLine('<h1>Windows Security Health Check</h1>')
    [void]$sb.AppendLine("<p>Generated: $(ConvertTo-HtmlEncoded $Report.GeneratedAt)</p>")
    [void]$sb.AppendLine("<p>Lifecycle table as-of: $script:LifecycleTableAsOf</p>")
    foreach ($k in $Report.Sections.Keys) {
        [void]$sb.AppendLine("<h2>$(ConvertTo-HtmlEncoded $k)</h2>")
        [void]$sb.AppendLine('<pre>')
        [void]$sb.AppendLine((ConvertTo-HtmlEncoded ($Report.Sections[$k] | Out-String)))
        [void]$sb.AppendLine('</pre>')
    }
    [void]$sb.AppendLine('</body></html>')
    return $sb.ToString()
}
function Write-SecurityReport {
    param([hashtable]$Report,[string]$Parent)
    if ($global:SecurityMock_WriteSecurityReports) { return & $global:SecurityMock_WriteSecurityReports $Report $Parent }
    $folder = New-UniqueReportFolder -Parent $Parent
    if ($null -eq $folder) { throw 'Unable to create a unique report folder.' }
    if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
    $htmlPath = Join-Path $folder "$script:ScriptName.html"
    $txtPath = Join-Path $folder "$script:ScriptName.txt"
    $html = ConvertTo-SecurityHtml -Report $Report
    Set-Content -LiteralPath $htmlPath -Value $html -Encoding UTF8
    $txt = ($Report | Out-String)
    Set-Content -LiteralPath $txtPath -Value $txt -Encoding UTF8
    return [pscustomobject]@{ Folder = $folder; HtmlPath = $htmlPath; TxtPath = $txtPath }
}

# Main execution guard for test loading
if ($global:SecurityTestMode) { return }

# ---- Main ----
$report = @{ GeneratedAt = (Get-Date).ToString('o'); Sections = [ordered]@{} }
$platform = Get-SecurityPlatformState
$report.Sections['Platform'] = $platform
$defender = Get-SecurityDefenderState
$report.Sections['Defender'] = $defender
$fw = Get-SecurityFirewallState
$report.Sections['Firewall'] = $fw
$ss = Get-SecuritySmartScreenState
$report.Sections['SmartScreen'] = $ss
$lc = Get-SecurityLifecycleStatus -EditionFamily $platform.EditionFamily -Channel 'GA' -DisplayVersion $platform.DisplayVersion
$report.Sections['Lifecycle'] = $lc

if ($CloudCheck) {
    if (-not (Get-SecurityElevation)) {
        $report.Sections['CloudCheck'] = [pscustomobject]@{ Status = 'Skipped'; Reason = 'Requires an already elevated session.' }
    } else {
        $report.Sections['CloudCheck'] = Invoke-SecurityMapsValidation
    }
}
if ($LiveUpdateCheck) { $report.Sections['LiveUpdateCheck'] = Invoke-SecurityLiveUpdateCheck }
if ($Fix) { $report.Sections['Repair'] = Invoke-SecurityRepair -WhatIf:($WhatIfPreference -eq $true) }

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $outParent = $env:LOCALAPPDATA }
else {
    $outParent = $OutputDirectory
    if (Test-IsRemoteOutputPath -Path $outParent) { throw 'Output directory must be a local path; UNC and mapped network paths are not allowed.' }
}

$written = Write-SecurityReport -Report $report -Parent $outParent
Write-Output "Report folder: $($written.Folder)"
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { Write-Output "Open folder: explorer.exe `"`$env:LOCALAPPDATA`"" }
else { Write-Output "Open folder: explorer.exe `"$outParent`"" }

Write-Output "=== Windows Security Health Check ==="
foreach ($s in $report.Sections.Keys) {
    Write-Output "[$s]"
    $report.Sections[$s] | Format-Table -AutoSize | Out-String | Write-Output
}
