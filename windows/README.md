# Windows Update Health and Repair

`Test-WindowsUpdateHealth.ps1` is a dependency-free Windows 11 troubleshooting
script for built-in Windows PowerShell 5.1. The normal report does not require
administrator rights. The script reports evidence; it cannot identify every
possible cause of an update failure.

## Usage

Run from the directory containing the script:

```powershell
.\Test-WindowsUpdateHealth.ps1
```

The default run performs an online Windows Update Agent search against the
machine's configured update source. It searches for available updates but does
not install them. The search is synchronous, contacts that source, and may take
time. To skip it:

```powershell
.\Test-WindowsUpdateHealth.ps1 -SkipNetworkTest
```

The report measures system-drive free space without applying a general
low-space threshold. It also reports update policy/source category, WinHTTP
proxy state without its endpoint, the three repair services, pending-reboot
signals, and recent error-level Windows Update events. Unreadable checks are
marked unknown instead of being reported as clear. It prints manual checks for
power, external devices, date/time, driver and security-software compatibility,
and managed-network conditions that it cannot verify.

The WUA search uses the default source selection. A detected WSUS policy is
reported as `managed`; otherwise a readable policy snapshot is reported as
`default-selection`. An unreadable snapshot is reported as `unknown`. That
selection does not force a public update source; Windows Update Agent chooses
the configured/default service.

## Repair options

`-Fix` is an explicit service/cache repair and requires an already elevated
PowerShell session, including when using `-WhatIf`. The script does not elevate
itself and does not ask for a second confirmation by default; add `-Confirm` if
you want an extra prompt. Preview the plan first:

```powershell
.\Test-WindowsUpdateHealth.ps1 -Fix -WhatIf
```

To perform the repair, open PowerShell as Administrator and run:

```powershell
.\Test-WindowsUpdateHealth.ps1 -Fix
```

It operates only on BITS, Windows Update (`wuauserv`), and Cryptographic
Services (`CryptSvc`). It stops services that were running, renames the
`SoftwareDistribution` and `catroot2` caches to unique backups, and then starts
all three services. Cache backups are retained and can consume disk space; the
script does not delete them. If a cache rename fails, it attempts a safe
rollback and restores the services that were originally running. Review any
partial-repair message and retained backup path before taking manual action.
The script does not change update policies, source selection, service startup
settings, ACLs, proxy/network settings, or reboot the computer.

System-file checks are a separate opt-in and require `-Fix`:

```powershell
.\Test-WindowsUpdateHealth.ps1 -Fix -RepairSystemFiles
```

This runs DISM RestoreHealth followed by SFC `/scannow` and reports their exit
codes. They can take a long time. An update error code is evidence for a next
check, not proof of system-file corruption. The report recommends this option
only for the specified recent codes when the configured-source search succeeds
and no direct finding or unknown required health check remains. For
`0x800f0922`, it reports that insufficient space or other components may be
involved and points to Microsoft's storage/issue-specific checks; free space
alone is never treated as a finding. Skipped or unavailable network searches
leave a qualifying system-file recommendation unknown/deferred.

## Local report log and privacy

JSON reports are stored under
`%LOCALAPPDATA%\WindowsUpdateHealth\`. The log contains only a troubleshooting
summary: Windows version/build/architecture, update-source category, policy
presence booleans and read status, proxy configured state, the fixed service
names/status/start types, free-space measurement, pending-reboot state,
policy/event-log read status, error-level event provider/ID/time/error code,
search outcome/error code/duration/update count, and repair-step name/status/
exit code. It excludes user/device identity, update titles, server
hostnames, policy values/URLs, credentials, and free-form exception or process
output. Logs remain local; the script does not upload them or add telemetry.
`-WhatIf` still writes the local report log; it skips repair operations only.
The log records policy/event-log read status so unavailable results aren't
confused with absent settings or no failures.

If a cache/service repair is partial or a required service cannot restart, the
script does not proceed to DISM/SFC in that same run.

## Limitations

- The online search tests the configured source, not every Microsoft endpoint.
  A failed search can have multiple causes and does not establish a root cause.
- A managed update source, policy presence, or proxy presence is informational
  by itself; the script does not change those settings.
- Check organizational approval and managed-network requirements with your IT
  administrator. The report cannot verify power, external hardware, date/time,
  or third-party driver/security compatibility.
- This version targets Windows 11 and built-in Windows PowerShell 5.1. It is not
  a general update-management tool and does not install, hide, or uninstall
  updates.

## Windows Security Health Check

`Test-WindowsSecurityHealth.ps1` is a standalone Windows 11 security health
check for Windows PowerShell 5.1 and PowerShell 7 on Windows. It requires no
external module. By default it performs no network request and changes no
security setting. It reports each check as Pass, Finding, Unknown, or Not
applicable. It does not calculate a universal security score or claim
CIS/STIG compliance.

Run from the directory containing the script:

```powershell
.\Test-WindowsSecurityHealth.ps1
```

Optional opt-ins:

```powershell
# Defender MAPS connectivity validation (elevated session required)
.\Test-WindowsSecurityHealth.ps1 -CloudCheck

# Configured-source Windows Update Agent search (no updates installed)
.\Test-WindowsSecurityHealth.ps1 -LiveUpdateCheck

# Approved repair preview
.\Test-WindowsSecurityHealth.ps1 -Fix -WhatIf
```

The only approved repair is `Update-MpSignature`, run only when Defender is the
active provider and reports signatures out of date. It requires an already
elevated PowerShell session; the script does not self-elevate. `-WhatIf`
previews the repair without invoking it. No other protection, firewall,
SmartScreen, service, policy, or Windows Update setting is changed.

### Output and privacy

Reports are written as console, HTML, and TXT under a unique timestamped folder
in the current user's LocalAppData by default. Use `-OutputDirectory` for a local
parent directory; UNC and mapped network paths are rejected. The folder-opening
command is printed but not executed. The default command uses `$env:LOCALAPPDATA`
so the resolved user path is not printed; a custom path appears only in console
output and is never persisted in HTML or TXT. Reports exclude machine, user, and
organization identifiers; raw policy values/URLs; provider product names; update
titles; and update-server hostnames. Logs and reports stay local. The script has
no telemetry or upload feature.

To create a PDF, open the generated HTML report in a browser and use its
print-to-PDF function.

### Limitations

- The report covers selected local operating-system controls. It is not a
  vulnerability scanner, penetration test, CIS/STIG benchmark, enterprise
  compliance determination, or substitute for Windows Security or an
  organization's management console.
- Windows APIs, edition capabilities, hardware, third-party AV, policy
  precedence, and permissions affect visibility. Unknown is an expected outcome
  for some checks.
- Windows Security Center can display stale status when its services are
  disabled.
- SmartScreen local policy/configuration does not prove online reputation
  service reachability or guarantee how every application or browser behaves.
- `-CloudCheck` validates Defender MAPS connectivity only. It does not test
  SmartScreen and may contact Microsoft.
- `-LiveUpdateCheck` may contact an organization-managed update server and can
  take time. A search is not proof that the device is fully patched.
- The checked-in Windows 11 edition/channel/version lifecycle table has an
  as-of date and must be maintained when Microsoft support dates change.
- The approved signature repair updates local security intelligence only. It
  does not repair Defender configuration, Windows Security, firewall, or
  policy.

### Microsoft references

- [Get-MpComputerStatus](https://learn.microsoft.com/en-us/powershell/module/defender/get-mpcomputerstatus)
- [Get-MpPreference](https://learn.microsoft.com/en-us/powershell/module/defender/get-mppreference)
- [Update-MpSignature](https://learn.microsoft.com/en-us/powershell/module/defender/update-mpsignature)
- [Microsoft Defender Antivirus compatibility and modes](https://learn.microsoft.com/en-us/defender-endpoint/microsoft-defender-antivirus-compatibility)
- [Windows Security and Windows Security Center services](https://learn.microsoft.com/en-us/windows/security/operating-system-security/system-security/windows-defender-security-center/windows-defender-security-center)
- [Get-NetFirewallProfile](https://learn.microsoft.com/en-us/powershell/module/netsecurity/get-netfirewallprofile)
- [Microsoft Defender SmartScreen available settings](https://learn.microsoft.com/en-us/windows/security/operating-system-security/virus-and-threat-protection/microsoft-defender-smartscreen/available-settings)
- [Confirm-SecureBootUEFI](https://learn.microsoft.com/en-us/powershell/module/secureboot/confirm-securebootuefi)
- [Get-Tpm](https://learn.microsoft.com/en-us/powershell/module/trustedplatformmodule/get-tpm)
- [Get-BitLockerVolume](https://learn.microsoft.com/en-us/powershell/module/bitlocker/get-bitlockervolume)
- [Memory integrity and Win32_DeviceGuard](https://learn.microsoft.com/en-us/windows/security/hardware-security/enable-virtualization-based-protection-of-code-integrity)
- [User Account Control](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/user-account-control/)
- [Windows 11 release information](https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information)
- [Windows 11 Home and Pro lifecycle](https://learn.microsoft.com/en-us/lifecycle/products/windows-11-home-and-pro)
- [Windows 11 Enterprise and Education lifecycle](https://learn.microsoft.com/en-us/lifecycle/products/windows-11-enterprise-and-education)
- [Windows 11 IoT Enterprise lifecycle](https://learn.microsoft.com/en-us/lifecycle/products/windows-11-iot-enterprise)
- [Windows 11 Enterprise LTSC 2024 lifecycle](https://learn.microsoft.com/en-us/lifecycle/products/windows-11-enterprise-ltsc-2024)
- [Windows 11 IoT Enterprise LTSC 2024 lifecycle](https://learn.microsoft.com/en-us/lifecycle/products/windows-11-iot-enterprise-ltsc-2024)
- [MpCmdRun MAPS connection validation](https://learn.microsoft.com/en-us/defender-endpoint/configure-network-connections-microsoft-defender-antivirus)
- [IUpdateSearcher::Search](https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iupdatesearcher-search)
- [IUpdateSearcher::Online](https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iupdatesearcher-get_online)
- [IUpdateSearcher server selection](https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iupdatesearcher-get_serverselection)
- [PowerShell Windows PowerShell compatibility](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_windows_powershell_compatibility)
- [Microsoft Security Compliance Toolkit](https://www.microsoft.com/en-us/download/details.aspx?id=55319)

- [Troubleshoot problems updating Windows](https://support.microsoft.com/en-us/windows/deployment/updates-lifecycle/troubleshoot-problems-updating-windows)
- [Additional resources for Windows Update](https://learn.microsoft.com/en-us/troubleshoot/windows-client/installing-updates-features-roles/additional-resources-for-windows-update)
- [ServerSelection enumeration](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-uamg/07e2bfa4-6795-4189-b007-cc50b476181a)
- [Windows Update Agent: IUpdateSearcher](https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nn-wuapi-iupdatesearcher)
- [Windows Update Agent: IUpdateSearcher::Search](https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iupdatesearcher-search)
- [Windows Update Agent: Online property](https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iupdatesearcher-put_online)
- [Windows Update Agent: ServerSelection property](https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iupdatesearcher-put_serverselection)
- [Get-WinEvent (Windows PowerShell 5.1)](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.diagnostics/get-winevent?view=powershell-5.1)
- [Standard event severity levels](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.eventing.reader.standardeventlevel?view=net-11.0-pp)
- [netsh winhttp command](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/netsh-winhttp)
- [Windows 11 connection endpoints](https://learn.microsoft.com/en-us/windows/privacy/manage-windows-11-endpoints)
- [Windows 11 non-Enterprise connection endpoints](https://learn.microsoft.com/en-us/windows/privacy/windows-11-endpoints-non-enterprise-editions)
