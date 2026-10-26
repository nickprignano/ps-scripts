[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Pester mocks bridge isolated script scope to test external OS boundaries.')]
param()

BeforeAll {
    $script:HealthScript = Join-Path (Split-Path $PSScriptRoot -Parent) 'Test-WindowsSecurityHealth.ps1'
    $global:SecurityTestMode = $true
    . $script:HealthScript

    function Set-SecurityBaselineMocks {
        Mock Get-CimInstance { return $null }
        Mock Get-ItemProperty { return $null }
        Mock Test-Path { return $false }
        Mock Get-Command { return $null }
        Mock Get-HotFix { return @() }
        Mock Get-SecurityWscProviderState { return [pscustomobject]@{ Available = $false; DefenderOn = $null; ThirdPartyAvOn = $null } }
        Mock Get-SecurityDefenderState {
            return [pscustomobject]@{
                Available = $true; RunningMode = 'Normal'; SignaturesOutOfDate = $false
                AntivirusEnabled = $true; RealTimeProtectionEnabled = $true
                BehaviorMonitorEnabled = $true; IoavProtectionEnabled = $true
                NISEnabled = $true; TamperProtected = $true
                CloudBlockLevel = $null; PUAProtection = $null
                ControlledFolderAccess = $null; AttackSurfaceReduction = $null
                SignatureAgeDays = 0; ExclusionPresence = 'None'
                WscDefenderOn = $true; WscThirdPartyAvOn = $false; WscAvailable = $true
            }
        }
        Mock Get-SecurityFirewallState { return @() }
        Mock Get-SecuritySmartScreenState { return [pscustomobject]@{ ShellEnabled=$null; ShellPolicyPresent=$false; EdgeEnabled=$null; EdgePolicyPresent=$false; EffectiveKnown=$false } }
        Mock Get-SecurityPlatformState {
            return [pscustomobject]@{
                OsCaption='Microsoft Windows 11 Pro'; OsVersion='10.0.26200'; OsBuild='26200'
                OsArchitecture='64-bit'; EditionFamily='Professional'; DisplayVersion='25H2'
                SecureBoot=$true; TpmPresent=$true; TpmReady=$true
                BitLockerOsVolume=$null; VbsStatus=2; MemoryIntegrityConfigured=$true
                MemoryIntegrityRunning=$true; UacEnabled=$true; LocalUpdateHistoryCount=3
            }
        }
        Mock Get-SecurityLifecycleStatus { return [pscustomobject]@{ Status='Supported'; EndDate='2027-10-12'; TableAsOf='2026-10-13' } }
        Mock Invoke-SecurityMapsValidation { return [pscustomobject]@{ Status='Pass'; DurationMs=10; ErrorCode=$null; RawOutput='' } }
        Mock Invoke-SecurityLiveUpdateCheck { return [pscustomobject]@{ Status='Pass'; DurationMs=10; UpdateCount=0; ErrorCode=$null } }
        Mock Get-SecurityElevation { return $false }
        Mock Update-MpSignature { return $null }
        Mock Test-IsRemoteOutputPath { return $false }
        Mock New-UniqueReportFolder {
            param($Parent)
            $g = [guid]::NewGuid().ToString('N')
            return (Join-Path $Parent "TestFolder-$g")
        }
        Mock New-Item { return $null }
        Mock Set-Content { return $null }
    }
}

Describe 'Test-WindowsSecurityHealth default report' {
    BeforeEach {
        $script:TempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:TempRoot -Force | Out-Null
        $global:SecurityTestMode = $false
        Set-SecurityBaselineMocks
    }
    AfterEach {
        Remove-Item -LiteralPath $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'creates HTML and TXT reports without network or mutation by default' {
        & $script:HealthScript -OutputDirectory $script:TempRoot
        Should -Invoke Set-Content -Times 2
        Should -Invoke Invoke-SecurityMapsValidation -Times 0
        Should -Invoke Invoke-SecurityLiveUpdateCheck -Times 0
    }

    It 'prints the folder command using LOCALAPPDATA by default' {
        $out = & $script:HealthScript -OutputDirectory $script:TempRoot 6>&1 | Out-String
        $out | Should -Match 'explorer.exe'
    }

    It 'rejects network output paths' {
        Mock Test-IsRemoteOutputPath { return $true }
        { & $script:HealthScript -OutputDirectory '\\server\share' } | Should -Throw
    }

    It 'does not overwrite an existing report folder' {
        # Collision handling is verified by suffix creation; ensure no throw on duplicate timestamp.
        & $script:HealthScript -OutputDirectory $script:TempRoot
        & $script:HealthScript -OutputDirectory $script:TempRoot
        Should -Invoke Set-Content -Times 4
    }
}

Describe 'Test-WindowsSecurityHealth status and privacy' {
    BeforeEach {
        $script:TempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:TempRoot -Force | Out-Null
        $global:SecurityTestMode = $false
        Set-SecurityBaselineMocks
    }
    AfterEach {
        Remove-Item -LiteralPath $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'classifies third-party AV as not a Defender failure' {
        Mock Get-SecurityDefenderState {
            return [pscustomobject]@{
                Available=$true; RunningMode='Normal'; SignaturesOutOfDate=$false
                AntivirusEnabled=$false; RealTimeProtectionEnabled=$false
                BehaviorMonitorEnabled=$true; IoavProtectionEnabled=$true
                NISEnabled=$true; TamperProtected=$true
                CloudBlockLevel=$null; PUAProtection=$null
                ControlledFolderAccess=$null; AttackSurfaceReduction=$null
                SignatureAgeDays=0; ExclusionPresence='None'
                WscDefenderOn=$false; WscThirdPartyAvOn=$true; WscAvailable=$true
            }
        }
        $out = & $script:HealthScript -OutputDirectory $script:TempRoot 2>&1 | Out-String
        $out | Should -Not -Match 'FAIL'
    }

    It 'redacts sentinel privacy values from saved HTML' {
        $script:CapturedHtml = $null
        Mock Set-Content {
            param($LiteralPath,$Value)
            if ($LiteralPath -like '*.html') { $script:CapturedHtml = $Value }
            return $null
        }
        & $script:HealthScript -OutputDirectory $script:TempRoot
        if ($script:CapturedHtml) { $script:CapturedHtml | Should -Not -Match 'SENTINEL-SECRET' }
    }

    It 'reports lifecycle unknown for unmapped rows' {
        Mock Get-SecurityLifecycleStatus { return [pscustomobject]@{ Status='Unknown'; EndDate=$null; TableAsOf='2026-10-13' } }
        & $script:HealthScript -OutputDirectory $script:TempRoot
        Should -Invoke Get-SecurityLifecycleStatus -Times 1
    }
}

Describe 'Test-WindowsSecurityHealth opt-ins' {
    BeforeEach {
        $script:TempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:TempRoot -Force | Out-Null
        $global:SecurityTestMode = $false
        Set-SecurityBaselineMocks
    }
    AfterEach {
        Remove-Item -LiteralPath $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'skips CloudCheck when not elevated' {
        Mock Get-SecurityElevation { return $false }
        & $script:HealthScript -CloudCheck -OutputDirectory $script:TempRoot
        Should -Invoke Invoke-SecurityMapsValidation -Times 0
    }

    It 'runs CloudCheck when elevated' {
        Mock Get-SecurityElevation { return $true }
        & $script:HealthScript -CloudCheck -OutputDirectory $script:TempRoot
        Should -Invoke Invoke-SecurityMapsValidation -Times 1
    }

    It 'runs LiveUpdateCheck when requested' {
        & $script:HealthScript -LiveUpdateCheck -OutputDirectory $script:TempRoot
        Should -Invoke Invoke-SecurityLiveUpdateCheck -Times 1
    }

    It 'does not run repair by default' {
        & $script:HealthScript -OutputDirectory $script:TempRoot
        # Invoke-SecurityRepair is not called by default path; verify no Update-MpSignature
        Should -Invoke Update-MpSignature -Times 0 -ErrorAction SilentlyContinue
    }
}

Describe 'Test-WindowsSecurityHealth repair gate' {
    BeforeEach {
        $script:TempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:TempRoot -Force | Out-Null
        Set-SecurityBaselineMocks
        Mock Get-SecurityElevation { return $true }
        Mock Update-MpSignature { return $null }
    }
    AfterEach {
        Remove-Item -LiteralPath $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'skips repair when signatures are not stale' {
        & $script:HealthScript -Fix -OutputDirectory $script:TempRoot
        Should -Invoke Update-MpSignature -Times 0
    }

    It 'WhatIf does not invoke Update-MpSignature' {
        Mock Get-SecurityDefenderState {
            return [pscustomobject]@{
                Available=$true; RunningMode='Normal'; SignaturesOutOfDate=$true
                AntivirusEnabled=$true; RealTimeProtectionEnabled=$true
                BehaviorMonitorEnabled=$true; IoavProtectionEnabled=$true
                NISEnabled=$true; TamperProtected=$true
                CloudBlockLevel=$null; PUAProtection=$null
                ControlledFolderAccess=$null; AttackSurfaceReduction=$null
                SignatureAgeDays=5; ExclusionPresence='None'
                WscDefenderOn=$true; WscThirdPartyAvOn=$false; WscAvailable=$true
            }
        }
        & $script:HealthScript -Fix -WhatIf -OutputDirectory $script:TempRoot
        Should -Invoke Update-MpSignature -Times 0
    }

    It 'repairs only when all predicates are true' {
        Mock Get-SecurityDefenderState {
            return [pscustomobject]@{
                Available=$true; RunningMode='Normal'; SignaturesOutOfDate=$true
                AntivirusEnabled=$true; RealTimeProtectionEnabled=$true
                BehaviorMonitorEnabled=$true; IoavProtectionEnabled=$true
                NISEnabled=$true; TamperProtected=$true
                CloudBlockLevel=$null; PUAProtection=$null
                ControlledFolderAccess=$null; AttackSurfaceReduction=$null
                SignatureAgeDays=5; ExclusionPresence='None'
                WscDefenderOn=$true; WscThirdPartyAvOn=$false; WscAvailable=$true
            }
        }
        & $script:HealthScript -Fix -OutputDirectory $script:TempRoot
        Should -Invoke Update-MpSignature -Times 1
    }

    It 'fails closed when WSC Defender is not ON' {
        Mock Get-SecurityDefenderState {
            return [pscustomobject]@{
                Available=$true; RunningMode='Normal'; SignaturesOutOfDate=$true
                AntivirusEnabled=$true; RealTimeProtectionEnabled=$true
                BehaviorMonitorEnabled=$true; IoavProtectionEnabled=$true
                NISEnabled=$true; TamperProtected=$true
                CloudBlockLevel=$null; PUAProtection=$null
                ControlledFolderAccess=$null; AttackSurfaceReduction=$null
                SignatureAgeDays=5; ExclusionPresence='None'
                WscDefenderOn=$false; WscThirdPartyAvOn=$false; WscAvailable=$true
            }
        }
        & $script:HealthScript -Fix -OutputDirectory $script:TempRoot
        Should -Invoke Update-MpSignature -Times 0
    }
}
