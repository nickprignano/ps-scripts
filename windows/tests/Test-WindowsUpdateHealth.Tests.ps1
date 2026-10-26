[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Pester mocks bridge isolated script scope to test external OS boundaries.')]
param()

BeforeAll {
    $script:HealthScript = Join-Path (Split-Path $PSScriptRoot -Parent) 'Test-WindowsUpdateHealth.ps1'

    function Get-FakeSuccessfulWuaSearch {
        $global:WurFakeSearcher = [pscustomobject]@{ Online = $false; ServerSelection = -1; SearchCall = $null }
        Add-Member -InputObject $global:WurFakeSearcher -MemberType ScriptMethod -Name Search -Value {
            param($criteria)
            $this.SearchCall = $criteria
            return [pscustomobject]@{ ResultCode = 2; Updates = @() }
        }
        $global:WurFakeSession = [pscustomobject]@{ Searcher = $global:WurFakeSearcher }
        Add-Member -InputObject $global:WurFakeSession -MemberType ScriptMethod -Name CreateUpdateSearcher -Value {
            return $this.Searcher
        }
    }
}

Describe 'Test-WindowsUpdateHealth public report' {
    BeforeEach {
        $script:LogRoot = Join-Path 'C:\WurTest' ([guid]::NewGuid().ToString('N'))
        $env:LOCALAPPDATA = $script:LogRoot
        $global:WurSoftwareMoved = $false
        $global:WurLogs = @()
        $global:WurEventCode = $null
        $global:WurEvents = @()
        $global:WurPendingReadFails = $false
        $global:WurOriginalOccupied = $false
        $global:WurEventQueryFails = $false
        $global:WurNoEventMatches = $false
        $global:WurServiceQueryFails = $false
        $global:WurDiskQueryFails = $false
        $global:WurNullDiskFree = $false
        $script:SearchCall = [pscustomobject]@{ Count = 0; Criteria = $null; Online = $null; ServerSelection = $null; HasServiceId = $false }

        Mock Get-CimInstance {
            if ($ClassName -eq 'Win32_OperatingSystem') {
                return [pscustomobject]@{ Caption = 'Windows 11 Pro'; Version = '10.0'; BuildNumber = '26100'; OSArchitecture = '64-bit'; SystemDrive = 'C:' }
            }
            if ($ClassName -eq 'Win32_LogicalDisk') {
                if ($global:WurDiskQueryFails) { throw 'PRIVATE_DISK_QUERY_ERROR' }
                if ($global:WurNullDiskFree) { return [pscustomobject]@{ FreeSpace = $null; Size = 500000000000 } }
                return [pscustomobject]@{ FreeSpace = 123456789; Size = 500000000000 }
            }
            if ($ClassName -eq 'Win32_Service') {
                if ($global:WurServiceQueryFails) { throw 'PRIVATE_SERVICE_QUERY_ERROR' }
                return @(
                    [pscustomobject]@{ Name = 'BITS'; State = 'Running'; StartMode = $(if ($global:WurDisabledService -eq 'BITS') { 'Disabled' } else { 'Manual' }) },
                    [pscustomobject]@{ Name = 'wuauserv'; State = 'Stopped'; StartMode = $(if ($global:WurDisabledService -eq 'wuauserv') { 'Disabled' } else { 'Manual' }) },
                    [pscustomobject]@{ Name = 'CryptSvc'; State = 'Running'; StartMode = 'Auto' }
                )
            }
        }
        Mock Get-Service {
            return @(
                [pscustomobject]@{ Name = 'BITS'; Status = 'Running' },
                [pscustomobject]@{ Name = 'wuauserv'; Status = 'Stopped' },
                [pscustomobject]@{ Name = 'CryptSvc'; Status = 'Running' }
            ) | Where-Object { $_.Name -in @($Name) }
        }
        Mock Get-WinEvent {
            if ($global:WurNoEventMatches) {
                $exception = [System.Exception]::new('No matching events')
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'NoMatchingEventsFound,Microsoft.PowerShell.Commands.GetWinEventCommand',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $null
                )
                throw $errorRecord
            }
            if ($global:WurEventQueryFails) { throw 'PRIVATE_EVENT_LOG_ACCESS_ERROR' }
            if ($global:WurEvents.Count -gt 0) { return $global:WurEvents }
            if ($global:WurEventCode) {
                return @([pscustomobject]@{
                    Id = 20
                    Level = 2
                    TimeCreated = [datetime]::UtcNow
                    Message = "Failure details PRIVATE_EVENT_TEXT; HRESULT $global:WurEventCode"
                })
            }
            return @()
        }
        Mock Get-ItemProperty {
            if ($LiteralPath -like '*Session Manager' -and $global:WurPendingSignal -eq 'PendingFileRenameOperations') {
                return [pscustomobject]@{ PendingFileRenameOperations = @('PRIVATE_PENDING_FILE_PATH') }
            }
            return $null
        }
        Mock netsh.exe { return 'Direct access (no proxy server).' }
        Mock Test-Path {
            if ($global:WurPendingReadFails -and $LiteralPath -like '*Component Based Servicing*RebootPending') { throw 'PRIVATE_REGISTRY_READ_ERROR' }
            if ($LiteralPath -like 'HKLM:*') {
                if ($global:WurPendingSignal -and $LiteralPath -like "*\$global:WurPendingSignal") { return $true }
                if ($LiteralPath -like '*\Session Manager') { return $true }
                return $false
            }
            if ($LiteralPath -eq (Join-Path $env:windir 'SoftwareDistribution')) {
                if (-not $global:WurSoftwareMoved) { return $true }
                return [bool]$global:WurOriginalOccupied
            }
            if ($LiteralPath -like (Join-Path $env:windir 'SoftwareDistribution.bak.*')) { return $global:WurSoftwareMoved }
            if ($LiteralPath -eq (Join-Path $env:windir 'System32\catroot2')) { return $true }
            return $false
        }
        Mock New-Item { return $null }
        Mock Set-Content {
            $global:WurLogs += [pscustomobject]@{ FullName = $LiteralPath; Text = [string]$Value }
        }
        Mock Stop-Service { throw 'STOP_MUTATION_DURING_REPORT' }
        Mock Start-Service { throw 'START_MUTATION_DURING_REPORT' }
        Mock Rename-Item { throw 'RENAME_MUTATION_DURING_REPORT' }
        Mock Start-Process { throw 'PROCESS_MUTATION_DURING_REPORT' }
        Mock New-Object { throw 'COM_SEARCH_SHOULD_BE_SKIPPED' } -ParameterFilter { $ComObject -eq 'Microsoft.Update.Session' }
    }

    AfterEach {
        Remove-Variable WurFakeSearcher, WurFakeSession -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable WurEventCode, WurEvents, WurDisabledService, WurPendingSignal, WurPendingReadFails, WurOriginalOccupied, WurRollbackFails, WurEventQueryFails, WurNoEventMatches, WurServiceQueryFails, WurDiskQueryFails, WurNullDiskFree -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable WurFakePrincipal -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable WurSoftwareMoved, WurStopped, WurStarted, WurRenamed, WurProcessCalls -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable WurLogs -Scope Global -ErrorAction SilentlyContinue
    }

    It 'writes an allowlisted local report and does not search when network testing is skipped' {
        $output = & $script:HealthScript -SkipNetworkTest 6>&1 | Out-String

        $output | Should -Match 'Windows Update health report'
        $output | Should -Match 'Network search: skipped'
        $log = $global:WurLogs | Select-Object -First 1
        $log | Should -Not -BeNullOrEmpty
        $record = $log.Text | ConvertFrom-Json
        @($record.PSObject.Properties.Name) | Should -Contain 'timestamp'
        @($record.PSObject.Properties.Name) | Should -Contain 'services'
        @($record.PSObject.Properties.Name) | Should -Not -Contain 'userName'
        @($record.PSObject.Properties.Name) | Should -Not -Contain 'computerName'
        $record.updateSourceCategory | Should -Be 'default-selection'
        $script:SearchCall.Count | Should -Be 0
        Should -Invoke New-Object -Exactly 0 -ParameterFilter { $ComObject -eq 'Microsoft.Update.Session' }
        Should -Invoke Stop-Service -Exactly 0
        Should -Invoke Start-Service -Exactly 0
        Should -Invoke Rename-Item -Exactly 0
        Should -Invoke Start-Process -Exactly 0
    }

    It 'searches the configured source online with the required criteria and without a service ID' {
        $global:WurFakeSearcher = [pscustomobject]@{ Online = $false; ServerSelection = -1; SearchCall = $null }
        Add-Member -InputObject $global:WurFakeSearcher -MemberType ScriptMethod -Name Search -Value {
            param($criteria)
            $this.SearchCall = $criteria
            return [pscustomobject]@{
                ResultCode = 2
                Updates = @(
                    [pscustomobject]@{ Title = 'PRIVATE_UPDATE_TITLE_ONE' },
                    [pscustomobject]@{ Title = 'PRIVATE_UPDATE_TITLE_TWO' }
                )
            }
        }
        $global:WurFakeSession = [pscustomobject]@{ Searcher = $global:WurFakeSearcher }
        Add-Member -InputObject $global:WurFakeSession -MemberType ScriptMethod -Name CreateUpdateSearcher -Value {
            return $this.Searcher
        }
        Mock New-Object { return $global:WurFakeSession } -ParameterFilter { $ComObject -eq 'Microsoft.Update.Session' }

        $output = & $script:HealthScript 6>&1 | Out-String

        $global:WurFakeSearcher.Online | Should -BeTrue
        $global:WurFakeSearcher.ServerSelection | Should -Be 0
        $global:WurFakeSearcher.PSObject.Properties.Name | Should -Not -Contain 'ServiceID'
        $global:WurFakeSearcher.SearchCall | Should -Be 'IsInstalled=0 and IsHidden=0'
        $output | Should -Match 'Network search: succeeded'
        $output | Should -Match 'update count: 2'
        $output | Should -Not -Match 'PRIVATE_UPDATE_TITLE'
        $log = $global:WurLogs | Select-Object -First 1
        $log.Text | Should -Not -Match 'PRIVATE_UPDATE_TITLE'
    }

    It 'refuses an unelevated repair before any service or cache mutation' {
        $global:WurFakePrincipal = [pscustomobject]@{ IsAdmin = $false }
        Add-Member -InputObject $global:WurFakePrincipal -MemberType ScriptMethod -Name IsInRole -Value { return $this.IsAdmin }
        Mock New-Object { return $global:WurFakePrincipal } -ParameterFilter { $TypeName -eq 'Security.Principal.WindowsPrincipal' }
        Mock Stop-Service { throw 'STOP_SHOULD_NOT_BE_CALLED' }
        Mock Start-Service { throw 'START_SHOULD_NOT_BE_CALLED' }
        Mock Rename-Item { throw 'RENAME_SHOULD_NOT_BE_CALLED' }

        { & $script:HealthScript -Fix -SkipNetworkTest } | Should -Throw '*requires an elevated*'

        Should -Invoke Stop-Service -Exactly 0
        Should -Invoke Start-Service -Exactly 0
        Should -Invoke Rename-Item -Exactly 0
    }

    It 'shows the repair plan with WhatIf and makes no service or cache changes' {
        $global:WurFakePrincipal = [pscustomobject]@{ IsAdmin = $true }
        Add-Member -InputObject $global:WurFakePrincipal -MemberType ScriptMethod -Name IsInRole -Value { return $this.IsAdmin }
        Mock New-Object { return $global:WurFakePrincipal } -ParameterFilter { $TypeName -eq 'Security.Principal.WindowsPrincipal' }
        Mock Stop-Service { throw 'STOP_SHOULD_NOT_BE_CALLED' }
        Mock Start-Service { throw 'START_SHOULD_NOT_BE_CALLED' }
        Mock Rename-Item { throw 'RENAME_SHOULD_NOT_BE_CALLED' }

        $output = & $script:HealthScript -Fix -SkipNetworkTest -WhatIf 6>&1 | Out-String

        $output | Should -Match 'Plan only:'
        $output | Should -Match 'Local report log:'
        $global:WurLogs.Count | Should -Be 1
        $reportLog = $global:WurLogs[0].Text | ConvertFrom-Json
        $reportLog.search.status | Should -Be 'skipped'
        @($reportLog.repairSteps).Count | Should -Be 0
        Should -Invoke Stop-Service -Exactly 0
        Should -Invoke Start-Service -Exactly 0
        Should -Invoke Rename-Item -Exactly 0
    }

    It 'recommends DISM/SFC only for a qualifying latest code after a successful search and without direct findings' {
        $global:WurEventCode = '0x80070057'
        Get-FakeSuccessfulWuaSearch
        Mock New-Object { return $global:WurFakeSession } -ParameterFilter { $ComObject -eq 'Microsoft.Update.Session' }

        $output = & $script:HealthScript 6>&1 | Out-String

        $output | Should -Match 'System-file repair recommendation: recommended'
        $output | Should -Match 'error code does not prove system-file corruption|do not prove system-file corruption'
    }

    It 'defers system-file repair when a direct service finding is present' {
        $global:WurEventCode = '0x80080005'
        $global:WurDisabledService = 'BITS'
        Get-FakeSuccessfulWuaSearch
        Mock New-Object { return $global:WurFakeSession } -ParameterFilter { $ComObject -eq 'Microsoft.Update.Session' }

        $output = & $script:HealthScript 6>&1 | Out-String

        $output | Should -Match 'System-file repair recommendation: deferred'
        $output | Should -Match 'Address direct findings first'
    }

    It 'detects each pending-reboot indicator and defers system-file repair without logging registry data' {
        $global:WurEventCode = '0x80070057'
        Get-FakeSuccessfulWuaSearch
        Mock New-Object { return $global:WurFakeSession } -ParameterFilter { $ComObject -eq 'Microsoft.Update.Session' }

        foreach ($signal in @('RebootPending', 'RebootRequired', 'PendingFileRenameOperations')) {
            $global:WurPendingSignal = $signal
            $output = & $script:HealthScript 6>&1 | Out-String
            $output | Should -Match 'Pending reboot: finding'
            $output | Should -Match 'System-file repair recommendation: deferred'
            $log = $global:WurLogs | Select-Object -Last 1
            $record = $log.Text | ConvertFrom-Json
            $record.pendingReboot | Should -Be 'finding'
            $log.Text | Should -Not -Match 'PRIVATE_PENDING_FILE_PATH'
        }
    }

    It 'reports pending-reboot indicator read failures as unknown and defers system-file repair' {
        $global:WurEventCode = '0x80070057'
        $global:WurPendingReadFails = $true
        Get-FakeSuccessfulWuaSearch
        Mock New-Object { return $global:WurFakeSession } -ParameterFilter { $ComObject -eq 'Microsoft.Update.Session' }
        Mock Test-Path {
            if ($LiteralPath -like '*Component Based Servicing*RebootPending') { throw 'PRIVATE_REGISTRY_READ_ERROR' }
            if ($LiteralPath -like 'HKLM:*') { return $false }
            return $false
        }

        $output = & $script:HealthScript 6>&1 | Out-String

        $output | Should -Match 'Pending reboot: unknown'
        $output | Should -Match 'System-file repair recommendation: unknown/deferred'
        $output | Should -Not -Match 'Pending reboot: not detected|Pass: no direct'
        $output | Should -Not -Match 'PRIVATE_REGISTRY_READ_ERROR'
    }

    It 'ignores informational Windows Update events that contain an HRESULT' {
        $global:WurEventCode = $null
        $global:WurEvents = @([pscustomobject]@{
            Id = 19
            Level = 4
            TimeCreated = [datetime]::UtcNow
            Message = 'Update succeeded; diagnostic value 0x80070057'
        })
        Mock Get-WinEvent { return $global:WurEvents }
        Get-FakeSuccessfulWuaSearch
        Mock New-Object { return $global:WurFakeSession } -ParameterFilter { $ComObject -eq 'Microsoft.Update.Session' }

        $output = & $script:HealthScript 6>&1 | Out-String

        $output | Should -Match 'No error-level Windows Update events with a code were found'
        $output | Should -Match 'System-file repair recommendation: not-recommended'
        Should -Invoke Get-WinEvent -Exactly 1 -ParameterFilter { $FilterHashtable.Level -eq 2 }
    }

    It 'reports inaccessible Windows Update error events as unknown rather than no errors or pass' {
        $global:WurEventQueryFails = $true
        $output = & $script:HealthScript -SkipNetworkTest 6>&1 | Out-String

        $output | Should -Match 'Unknown: Windows Update error events could not be read'
        $output | Should -Match 'System-file repair recommendation: unknown/deferred'
        $output | Should -Not -Match 'no Windows Update error code was available|Pass: no direct'
        $output | Should -Not -Match 'PRIVATE_EVENT_LOG_ACCESS_ERROR'
    }

    It 'treats the no-matching-events result as a successful empty error-log query' {
        $global:WurNoEventMatches = $true

        $output = & $script:HealthScript -SkipNetworkTest 6>&1 | Out-String

        $output | Should -Match 'No error-level Windows Update events with a code were found'
        $output | Should -Not -Match 'Unknown: Windows Update error events could not be read'
        $record = ($global:WurLogs | Select-Object -First 1).Text | ConvertFrom-Json
        $record.eventLogStatus | Should -Be 'available'
        @($record.eventErrors).Count | Should -Be 0
    }

    It 'leaves a qualifying code unknown/deferred when the network test is skipped' {
        $global:WurEventCode = '0x80070057'

        $output = & $script:HealthScript -SkipNetworkTest 6>&1 | Out-String

        $output | Should -Match 'System-file repair recommendation: unknown/deferred'
    }

    It 'reports 0x800f0922 and free space without recommending DISM/SFC or inferring low space' {
        $global:WurEventCode = '0x800f0922'

        $output = & $script:HealthScript -SkipNetworkTest 6>&1 | Out-String

        $output | Should -Match 'System-file repair recommendation: not-recommended'
        $output | Should -Match '0x800f0922 can involve insufficient space or other components'
        $output | Should -Match '123456789 bytes \(measurement only\)'
        $output | Should -Not -Match 'low disk space|low-space finding'
    }

    It 'keeps raw event details and identity-like sentinels out of the local log' {
        $global:WurEventCode = '0x80070057'

        $null = & $script:HealthScript -SkipNetworkTest

        $log = $global:WurLogs | Select-Object -First 1
        $text = $log.Text
        $text | Should -Not -Match 'PRIVATE_EVENT_TEXT|PRIVATE_UPDATE_TITLE|nickp|COMPUTERNAME'
        $record = $text | ConvertFrom-Json
        (@($record.PSObject.Properties.Name | Sort-Object) -join ',') | Should -Be 'eventErrors,eventLogStatus,pendingReboot,policies,policyReadStatus,repairSteps,scriptVersion,search,services,systemDriveFreeBytes,timestamp,updateSourceCategory,windows,winHttpProxy'
        @($record.eventErrors[0].PSObject.Properties.Name | Sort-Object) | Should -Be @('errorCode', 'id', 'provider', 'time')
        @($record.search.PSObject.Properties.Name | Sort-Object) | Should -Be @('durationMilliseconds', 'errorCode', 'status', 'updateCount')
    }

    It 'keeps policy URLs and proxy endpoints out of the log while reporting only their categories' {
        Mock Test-Path {
            if ($LiteralPath -like '*Policies\Microsoft\Windows\WindowsUpdate*') { return $true }
            if ($LiteralPath -like 'HKLM:*') { return $false }
            return $false
        }
        Mock Get-ItemProperty {
            if ($LiteralPath -like '*Policies*WindowsUpdate*') {
                return [pscustomobject]@{ WUServer = 'https://PRIVATE_POLICY_HOST/policy'; UseWUServer = 1 }
            }
            return $null
        }
        Mock netsh.exe { return 'Proxy Server(s) : http://PRIVATE_PROXY_HOST:8080' }

        $null = & $script:HealthScript -SkipNetworkTest

        $log = $global:WurLogs | Select-Object -First 1
        $text = $log.Text
        $record = $text | ConvertFrom-Json
        $record.updateSourceCategory | Should -Be 'managed'
        $record.winHttpProxy | Should -Be 'configured'
        $record.policies.updatePolicyPresent | Should -BeTrue
        $text | Should -Not -Match 'PRIVATE_POLICY_HOST|PRIVATE_PROXY_HOST|/policy|:8080'
    }

    It 'reports policy configuration as unknown when registry access fails' {
        $global:WurEventCode = '0x80070057'
        Get-FakeSuccessfulWuaSearch
        Mock New-Object { return $global:WurFakeSession } -ParameterFilter { $ComObject -eq 'Microsoft.Update.Session' }
        Mock Test-Path {
            if ($LiteralPath -like '*Policies\Microsoft\Windows\WindowsUpdate*') { throw 'PRIVATE_POLICY_READ_ERROR' }
            if ($LiteralPath -like 'HKLM:*') { return $false }
            return $false
        }

        $output = & $script:HealthScript -SkipNetworkTest 6>&1 | Out-String

        $output | Should -Match 'Update source: unknown'
        $output | Should -Match 'Unknown: Windows Update policy configuration could not be read'
        $output | Should -Match 'System-file repair recommendation: unknown/deferred'
        $output | Should -Not -Match 'PRIVATE_POLICY_READ_ERROR|Pass: no direct'
        $log = $global:WurLogs | Select-Object -First 1
        $record = $log.Text | ConvertFrom-Json
        $record.policyReadStatus | Should -Be 'unknown'
        $record.policies.updatePolicyPresent | Should -BeNullOrEmpty
    }

    It 'defers system-file repair when service or disk health data is unknown' {
        $global:WurEventCode = '0x80070057'
        $global:WurServiceQueryFails = $true
        $global:WurDiskQueryFails = $true
        Get-FakeSuccessfulWuaSearch
        Mock New-Object { return $global:WurFakeSession } -ParameterFilter { $ComObject -eq 'Microsoft.Update.Session' }

        $output = & $script:HealthScript 6>&1 | Out-String

        $output | Should -Match 'Unknown: one or more repair service states/configurations could not be read'
        $output | Should -Match 'Unknown: system-drive free space could not be read'
        $output | Should -Match 'System-file repair recommendation: unknown/deferred'
        $output | Should -Not -Match 'Pass: no direct'
        $output | Should -Not -Match 'PRIVATE_SERVICE_QUERY_ERROR|PRIVATE_DISK_QUERY_ERROR'
    }

    It 'reports a null free-space property as unknown rather than zero and defers system-file repair' {
        $global:WurEventCode = '0x80070057'
        $global:WurNullDiskFree = $true
        Get-FakeSuccessfulWuaSearch
        Mock New-Object { return $global:WurFakeSession } -ParameterFilter { $ComObject -eq 'Microsoft.Update.Session' }

        $output = & $script:HealthScript 6>&1 | Out-String

        $output | Should -Match 'Unknown: system-drive free space could not be read'
        $output | Should -Match 'System-file repair recommendation: unknown/deferred'
        $output | Should -Not -Match 'System-drive free space: 0 bytes|Pass: no direct'
        $record = ($global:WurLogs | Select-Object -First 1).Text | ConvertFrom-Json
        $record.systemDriveFreeBytes | Should -BeNullOrEmpty
    }

    It 'does not recommend system-file repair from an unrelated update error code' {
        $global:WurEventCode = '0x12345678'

        $output = & $script:HealthScript -SkipNetworkTest 6>&1 | Out-String

        $output | Should -Match 'System-file repair recommendation: not-recommended'
        $output | Should -Match 'does not recommend DISM/SFC'
    }

    It 'defers system-file repair after a failed configured-source search and omits raw search errors' {
        $global:WurEventCode = '0x80070057'
        $global:WurFakeSearcher = [pscustomobject]@{ Online = $false; ServerSelection = -1 }
        Add-Member -InputObject $global:WurFakeSearcher -MemberType ScriptMethod -Name Search -Value {
            throw 'PRIVATE_SERVER_NAME and PRIVATE_SEARCH_EXCEPTION'
        }
        $global:WurFakeSession = [pscustomobject]@{ Searcher = $global:WurFakeSearcher }
        Add-Member -InputObject $global:WurFakeSession -MemberType ScriptMethod -Name CreateUpdateSearcher -Value { return $this.Searcher }
        Mock New-Object { return $global:WurFakeSession } -ParameterFilter { $ComObject -eq 'Microsoft.Update.Session' }

        $output = & $script:HealthScript 6>&1 | Out-String

        $output | Should -Match 'Network search: failed'
        $output | Should -Match 'System-file repair recommendation: unknown/deferred'
        $output | Should -Not -Match 'PRIVATE_SERVER_NAME|PRIVATE_SEARCH_EXCEPTION'
        $log = $global:WurLogs | Select-Object -First 1
        $log.Text | Should -Not -Match 'PRIVATE_SERVER_NAME|PRIVATE_SEARCH_EXCEPTION'
    }

    It 'stops only running repair services and starts all three after successful cache renames' {
        $global:WurFakePrincipal = [pscustomobject]@{ IsAdmin = $true }
        Add-Member -InputObject $global:WurFakePrincipal -MemberType ScriptMethod -Name IsInRole -Value { return $this.IsAdmin }
        Mock New-Object { return $global:WurFakePrincipal } -ParameterFilter { $TypeName -eq 'Security.Principal.WindowsPrincipal' }
        $global:WurStopped = @()
        $global:WurStarted = @()
        $global:WurRenamed = @()
        Mock Stop-Service { $global:WurStopped += $Name }
        Mock Start-Service { $global:WurStarted += $Name }
        Mock Rename-Item {
            $global:WurRenamed += $LiteralPath
            if ($LiteralPath -eq (Join-Path $env:windir 'SoftwareDistribution')) { $global:WurSoftwareMoved = $true }
        }

        $output = & $script:HealthScript -Fix -SkipNetworkTest 6>&1 | Out-String

        (@($global:WurStopped | Sort-Object) -join ',') | Should -Be 'BITS,CryptSvc'
        (@($global:WurStarted | Sort-Object) -join ',') | Should -Be 'BITS,CryptSvc,wuauserv'
        $global:WurRenamed.Count | Should -Be 2
        $global:WurRenamed | Should -Contain (Join-Path $env:windir 'SoftwareDistribution')
        $global:WurRenamed | Should -Contain (Join-Path $env:windir 'System32\catroot2')
        $output | Should -Match 'Windows Update service/cache repair completed'
    }

    It 'rolls back an earlier cache rename and restores only originally running services after a later rename fails' {
        $global:WurFakePrincipal = [pscustomobject]@{ IsAdmin = $true }
        Add-Member -InputObject $global:WurFakePrincipal -MemberType ScriptMethod -Name IsInRole -Value { return $this.IsAdmin }
        Mock New-Object { return $global:WurFakePrincipal } -ParameterFilter { $TypeName -eq 'Security.Principal.WindowsPrincipal' }
        $global:WurStopped = @()
        $global:WurStarted = @()
        $global:WurRenamed = @()
        Mock Stop-Service { $global:WurStopped += $Name }
        Mock Start-Service { $global:WurStarted += $Name }
        Mock Rename-Item {
            $global:WurRenamed += $LiteralPath
            if ($LiteralPath -eq (Join-Path $env:windir 'SoftwareDistribution')) {
                $global:WurSoftwareMoved = $true
                return
            }
            if ($LiteralPath -eq (Join-Path $env:windir 'System32\catroot2')) { throw 'PRIVATE_FILESYSTEM_ERROR' }
            if ($LiteralPath -like (Join-Path $env:windir 'SoftwareDistribution.bak.*')) {
                $global:WurSoftwareMoved = $false
            }
        }

        $output = & $script:HealthScript -Fix -SkipNetworkTest -Confirm:$false 6>&1 | Out-String

        $global:WurRenamed.Count | Should -Be 3
        (@($global:WurStarted | Sort-Object) -join ',') | Should -Be 'BITS,CryptSvc'
        $global:WurSoftwareMoved | Should -BeFalse
        $output | Should -Match 'Cache rename failed'
        $output | Should -Not -Match 'PRIVATE_FILESYSTEM_ERROR'
    }

    It 'preserves and reports a renamed cache when the original path becomes occupied during rollback' {
        $global:WurFakePrincipal = [pscustomobject]@{ IsAdmin = $true }
        Add-Member -InputObject $global:WurFakePrincipal -MemberType ScriptMethod -Name IsInRole -Value { return $this.IsAdmin }
        Mock New-Object { return $global:WurFakePrincipal } -ParameterFilter { $TypeName -eq 'Security.Principal.WindowsPrincipal' }
        $global:WurStarted = @()
        Mock Stop-Service { }
        Mock Start-Service { $global:WurStarted += $Name }
        Mock Rename-Item {
            if ($LiteralPath -eq (Join-Path $env:windir 'SoftwareDistribution')) {
                $global:WurSoftwareMoved = $true
                return
            }
            if ($LiteralPath -eq (Join-Path $env:windir 'System32\catroot2')) {
                $global:WurOriginalOccupied = $true
                throw 'PRIVATE_CACHE_RENAME_ERROR'
            }
            throw 'ROLLBACK_SHOULD_NOT_RUN'
        }
        Mock Test-Path {
            if ($LiteralPath -like 'HKLM:*') { return $false }
            if ($LiteralPath -eq (Join-Path $env:windir 'SoftwareDistribution')) {
                if (-not $global:WurSoftwareMoved) { return $true }
                return [bool]$global:WurOriginalOccupied
            }
            if ($LiteralPath -eq (Join-Path $env:windir 'System32\catroot2')) { return $true }
            if ($LiteralPath -like (Join-Path $env:windir 'SoftwareDistribution.bak.*')) { return $true }
            return $false
        }

        $output = & $script:HealthScript -Fix -SkipNetworkTest -Confirm:$false 6>&1 | Out-String

        $output | Should -Match 'Original cache path is occupied; retained backup:'
        $output | Should -Match 'SoftwareDistribution\.bak\.'
        $output | Should -Not -Match 'PRIVATE_CACHE_RENAME_ERROR|ROLLBACK_SHOULD_NOT_RUN'
        (@($global:WurStarted | Sort-Object) -join ',') | Should -Be 'BITS,CryptSvc'
    }

    It 'preserves and reports a cache backup when rollback itself fails' {
        $global:WurFakePrincipal = [pscustomobject]@{ IsAdmin = $true }
        Add-Member -InputObject $global:WurFakePrincipal -MemberType ScriptMethod -Name IsInRole -Value { return $this.IsAdmin }
        Mock New-Object { return $global:WurFakePrincipal } -ParameterFilter { $TypeName -eq 'Security.Principal.WindowsPrincipal' }
        $global:WurStarted = @()
        Mock Stop-Service { }
        Mock Start-Service { $global:WurStarted += $Name }
        Mock Rename-Item {
            if ($LiteralPath -eq (Join-Path $env:windir 'SoftwareDistribution')) {
                $global:WurSoftwareMoved = $true
                return
            }
            if ($LiteralPath -eq (Join-Path $env:windir 'System32\catroot2')) { throw 'PRIVATE_CACHE_RENAME_ERROR' }
            if ($LiteralPath -like (Join-Path $env:windir 'SoftwareDistribution.bak.*')) { throw 'PRIVATE_ROLLBACK_ERROR' }
        }
        Mock Test-Path {
            if ($LiteralPath -like 'HKLM:*') { return $false }
            if ($LiteralPath -eq (Join-Path $env:windir 'SoftwareDistribution')) { return (-not $global:WurSoftwareMoved) }
            if ($LiteralPath -eq (Join-Path $env:windir 'System32\catroot2')) { return $true }
            if ($LiteralPath -like (Join-Path $env:windir 'SoftwareDistribution.bak.*')) { return $true }
            return $false
        }

        $output = & $script:HealthScript -Fix -SkipNetworkTest -Confirm:$false 6>&1 | Out-String

        $output | Should -Match 'Manual recovery may be required; retained backup:'
        $output | Should -Match 'SoftwareDistribution\.bak\.'
        $output | Should -Not -Match 'PRIVATE_CACHE_RENAME_ERROR|PRIVATE_ROLLBACK_ERROR'
        (@($global:WurStarted | Sort-Object) -join ',') | Should -Be 'BITS,CryptSvc'
    }

    It 'does not rename caches after a service stop fails and restores the original running services' {
        $global:WurFakePrincipal = [pscustomobject]@{ IsAdmin = $true }
        Add-Member -InputObject $global:WurFakePrincipal -MemberType ScriptMethod -Name IsInRole -Value { return $this.IsAdmin }
        Mock New-Object { return $global:WurFakePrincipal } -ParameterFilter { $TypeName -eq 'Security.Principal.WindowsPrincipal' }
        $global:WurStopped = @()
        $global:WurStarted = @()
        Mock Stop-Service {
            $global:WurStopped += $Name
            if ($Name -eq 'CryptSvc') { throw 'PRIVATE_SERVICE_ERROR' }
        }
        Mock Start-Service { $global:WurStarted += $Name }
        Mock Rename-Item { throw 'RENAME_SHOULD_NOT_BE_CALLED' }

        $output = & $script:HealthScript -Fix -SkipNetworkTest -Confirm:$false 6>&1 | Out-String

        (@($global:WurStopped | Sort-Object) -join ',') | Should -Be 'BITS,CryptSvc'
        (@($global:WurStarted | Sort-Object) -join ',') | Should -Be 'BITS,CryptSvc'
        Should -Invoke Rename-Item -Exactly 0
        $output | Should -Match 'Repair stopped before cache changes'
        $output | Should -Not -Match 'PRIVATE_SERVICE_ERROR'
    }

    It 'restores original running services when checking a cache path fails' {
        $global:WurFakePrincipal = [pscustomobject]@{ IsAdmin = $true }
        Add-Member -InputObject $global:WurFakePrincipal -MemberType ScriptMethod -Name IsInRole -Value { return $this.IsAdmin }
        Mock New-Object { return $global:WurFakePrincipal } -ParameterFilter { $TypeName -eq 'Security.Principal.WindowsPrincipal' }
        $global:WurStarted = @()
        Mock Stop-Service { }
        Mock Start-Service { $global:WurStarted += $Name }
        Mock Test-Path {
            if ($LiteralPath -like 'HKLM:*') { return $false }
            if ($LiteralPath -eq (Join-Path $env:windir 'SoftwareDistribution')) { throw 'PRIVATE_PATH_ERROR' }
            return $false
        }
        Mock Rename-Item { throw 'RENAME_SHOULD_NOT_BE_CALLED' }

        $output = & $script:HealthScript -Fix -SkipNetworkTest -Confirm:$false 6>&1 | Out-String

        (@($global:WurStarted | Sort-Object) -join ',') | Should -Be 'BITS,CryptSvc'
        Should -Invoke Rename-Item -Exactly 0
        $output | Should -Match 'Cache rename failed'
        $output | Should -Not -Match 'PRIVATE_PATH_ERROR'
    }

    It 'requires Fix for system-file repair and runs DISM before SFC only with the separate opt-in' {
        { & $script:HealthScript -RepairSystemFiles -SkipNetworkTest } | Should -Throw '*requires -Fix*'

        $global:WurFakePrincipal = [pscustomobject]@{ IsAdmin = $true }
        Add-Member -InputObject $global:WurFakePrincipal -MemberType ScriptMethod -Name IsInRole -Value { return $this.IsAdmin }
        Mock New-Object { return $global:WurFakePrincipal } -ParameterFilter { $TypeName -eq 'Security.Principal.WindowsPrincipal' }
        $global:WurSoftwareMoved = $false
        $global:WurStarted = @()
        $global:WurProcessCalls = @()
        Mock Stop-Service { }
        Mock Start-Service { $global:WurStarted += $Name }
        Mock Rename-Item {
            if ($LiteralPath -eq (Join-Path $env:windir 'SoftwareDistribution')) { $global:WurSoftwareMoved = $true }
        }
        Mock Start-Process {
            $global:WurProcessCalls += [pscustomobject]@{ File = $FilePath; Arguments = @($ArgumentList) }
            return [pscustomobject]@{ ExitCode = $(if ($FilePath -eq 'dism.exe') { 0 } else { 1 }) }
        }

        $output = & $script:HealthScript -Fix -RepairSystemFiles -SkipNetworkTest -Confirm:$false 6>&1 | Out-String

        $global:WurProcessCalls.Count | Should -Be 2
        $global:WurProcessCalls[0].File | Should -Be 'dism.exe'
        ($global:WurProcessCalls[0].Arguments -join ' ') | Should -Be '/Online /Cleanup-Image /RestoreHealth'
        $global:WurProcessCalls[1].File | Should -Be 'sfc.exe'
        ($global:WurProcessCalls[1].Arguments -join ' ') | Should -Be '/scannow'
        $output | Should -Match 'DISM RestoreHealth: exit code 0'
        $output | Should -Match 'SFC scannow: exit code 1'
        $finalLog = $global:WurLogs |
            ForEach-Object { $_.Text | ConvertFrom-Json } |
            Where-Object { $_.repairSteps.Count -gt 0 } | Select-Object -First 1
        $finalLog | Should -Not -BeNullOrEmpty
        @($finalLog.repairSteps | Where-Object { $_.name -like '*RestoreHealth*' -or $_.name -like '*scannow*' }).Count | Should -Be 2
    }

    It 'attempts every service start and reports a partial repair when one cannot start' {
        $global:WurFakePrincipal = [pscustomobject]@{ IsAdmin = $true }
        Add-Member -InputObject $global:WurFakePrincipal -MemberType ScriptMethod -Name IsInRole -Value { return $this.IsAdmin }
        Mock New-Object { return $global:WurFakePrincipal } -ParameterFilter { $TypeName -eq 'Security.Principal.WindowsPrincipal' }
        $global:WurStarted = @()
        Mock Stop-Service { }
        Mock Start-Service {
            $global:WurStarted += $Name
            if ($Name -eq 'wuauserv') { throw 'PRIVATE_START_ERROR' }
        }
        Mock Rename-Item { }

        $output = & $script:HealthScript -Fix -SkipNetworkTest -Confirm:$false 6>&1 | Out-String

        (@($global:WurStarted | Sort-Object) -join ',') | Should -Be 'BITS,CryptSvc,wuauserv'
        $output | Should -Match 'Partial repair failure'
        $output | Should -Not -Match 'PRIVATE_START_ERROR'
    }

    It 'does not run system-file scans when a cache repair service cannot restart' {
        $global:WurFakePrincipal = [pscustomobject]@{ IsAdmin = $true }
        Add-Member -InputObject $global:WurFakePrincipal -MemberType ScriptMethod -Name IsInRole -Value { return $this.IsAdmin }
        Mock New-Object { return $global:WurFakePrincipal } -ParameterFilter { $TypeName -eq 'Security.Principal.WindowsPrincipal' }
        $global:WurProcessCalls = @()
        Mock Stop-Service { }
        Mock Start-Service {
            if ($Name -eq 'wuauserv') { throw 'PRIVATE_START_ERROR' }
        }
        Mock Rename-Item { }
        Mock Start-Process { $global:WurProcessCalls += $FilePath; return [pscustomobject]@{ ExitCode = 0 } }

        $output = & $script:HealthScript -Fix -RepairSystemFiles -SkipNetworkTest -Confirm:$false 6>&1 | Out-String

        $output | Should -Match 'Partial repair failure'
        $output | Should -Match 'DISM/SFC were not run because the service/cache repair did not complete'
        $global:WurProcessCalls.Count | Should -Be 0
    }
}
