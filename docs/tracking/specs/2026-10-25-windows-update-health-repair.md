# Windows Update Health and Repair Script

- **Status:** User-approved; final Red Team review passed; ready for Blueprint
- **Loop:** `2026-10-25-windows-update-health-repair`
- **Target repository:** `nickprignano/ps-scripts`
- **Target implementation:** `windows/Test-WindowsUpdateHealth.ps1`

## Goal

Create a standalone PowerShell 5.1 script for Windows 11 that reports
Windows Update health, tests the machine's actual configured update path, and
offers explicit, documented repair operations. The default report should run
without elevation. The script must be suitable for public use and must not
claim to exhaust every possible cause of an update failure.

## User goals and acceptance criteria

1. Run the script without administrator rights to display a useful report and
   write a timestamped local log.
2. Include system/build details and inspect, where available, update-source and
   policy presence, WinHTTP proxy configured/unconfigured state (never its
   endpoint), relevant service state/configuration, system-drive free space,
   pending-reboot indicators, and Windows Update failure codes from the last
   30 days. Report free space as a measurement only; do not invent a universal
   low-space threshold or label it pass/finding without a code-specific
   Microsoft-supported rule. If the disk result or its `FreeSpace` value is
   missing, report unknown, not zero bytes.
3. Run a Windows Update Agent search on every normal report, using the
   computer's configured update source. Set `Online` to true and
   `ServerSelection` to `ssDefault`; do not set a specific `ServiceID` or force
   `ssWindowsUpdate`. Microsoft documents `ssDefault` as the managed server
   when configured, otherwise the first eligible automatic-update service.
   `-SkipNetworkTest` opts out of this online search.
4. Use the explicit search criteria `IsInstalled=0 and IsHidden=0`. Report the
   search outcome, error code, duration, and update count without installing
   updates. Do not log update titles, machine/user identity, raw server
   hostnames, or policy URLs. Clearly disclose that a search contacts the
   configured source and may take time.
   Read only severity-Error (`Level=2`) WindowsUpdateClient events as failure
   codes. If the event log cannot be read, report the state as **unknown**; do
   not treat a code from an informational/warning event as a failure. A
   `NoMatchingEventsFound` result is a successful empty query, not a read error.
5. Distinguish **pass**, **finding**, and **unknown**. Map findings to
   evidence-based Microsoft guidance and include manual checks for issues the
   script cannot verify, such as power, external devices, date/time, driver or
   security-software compatibility, and managed-network conditions. Do not
   claim that every possible cause has been ruled out.
   A pending reboot is reported if any of these indicators exists:
   - `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending`
   - `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired`
   - `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations`
   Report the signal, not its raw registry value. If one or more indicators
   cannot be read and none is positive, report **unknown**, not “not detected”;
   defer DISM/SFC advice until the pending-reboot status is known.
6. `-Fix` is the explicit opt-in for the Windows Update service/cache repair.
   It requires an elevated terminal; if not elevated, stop before mutation and
   tell the user to rerun elevated. Do not self-elevate.
7. The `-Fix` repair operates on exactly `BITS`, `wuauserv`, and `CryptSvc`.
   Capture original service states; stop only services that are running. If
   stopping any service fails, do not rename caches and attempt to restart the
   services that were running before the repair. Rename `SoftwareDistribution`
   and `catroot2` to unique timestamped backups; never delete or overwrite a
   cache or backup. If a rename fails after an earlier rename succeeded, attempt
   to restore the moved folder only when its original path is still free, then
   restore the original running states. After both renames succeed, start all
   three services as the documented repair sequence requires, even if one was
   stopped initially; report any service that cannot start as a partial repair
   failure and include backup paths. Do not alter service startup settings,
   Windows Update policies, ACLs, proxy/network settings, or reboot the
   machine.
8. `-RepairSystemFiles` is a separate opt-in used with `-Fix`. It runs DISM
   `/Online /Cleanup-Image /RestoreHealth`, followed by SFC `/scannow`. The
   default report and ordinary `-Fix` do not run these scans. Apply this
   deterministic recommendation rule to errors from the last 30 days:
   - If the latest Windows Update failure code is `0x80070057` or `0x80080005`,
     the online WUA search completed successfully, and no direct finding exists
     (search failure, a disabled `BITS`/`wuauserv`/`CryptSvc`, or pending reboot),
     recommend `-RepairSystemFiles`, citing Microsoft's SFC guidance.
   - If the latest code is `0x800f0922`, report Microsoft's possible storage or
     other-component causes, show measured free space, and recommend its
     storage/issue-specific checks. Do not recommend DISM/SFC from this code
     alone.
   - Never infer a low-space finding from the free-space number alone; the
     Microsoft free-space examples cover specific upgrade scenarios, not all
     Windows Update activity.
   - If a direct finding exists, recommend addressing it first. If the network
     test is skipped/unavailable or pending-reboot, service, policy, OS,
     disk-space, or event-log data is unknown, mark the system-file recommendation
     **unknown/deferred**. A later report can recommend it if a qualifying code
     remains, the network test succeeds, and no direct finding or unknown
     remains.
   - For other codes, do not recommend system-file repair from the report
     alone. Usage documentation may give conditional manual guidance to consider
     it if the issue persists after addressing findings and Microsoft
     first-line guidance.
   In every case, state that an error code does not prove system-file
   corruption. Managed-source and proxy presence alone are informational. If
   the cache/service repair is partial or a required service fails to start,
   do not run DISM/SFC in that invocation; report that the base repair needs
   attention first.
9. `-Fix` itself is the explicit consent to perform the specified repair; do
   not add a default second confirmation prompt. Users may request PowerShell's
   common `-Confirm` behavior. `-WhatIf` previews repair operations without
   executing them and still writes the required report log.
10. The local log is stored under the current user's local application data,
    contains only an allowlisted troubleshooting summary, and is never
    uploaded. Permitted fields: timestamp, script version, Windows edition/
    display version/build/architecture, update-source category, policy-presence
    booleans plus policy-read status, WinHTTP proxy configured/unconfigured
    state, fixed service names/status/start types, system-drive free space,
    pending-reboot state, Windows Update event-log read status, event
    provider/ID/time/error code, search result/error code/duration/update count,
    repair-step name/status/exit code. Never log
    free-form exception or process output, user/device identity, update titles,
    raw server hostnames, policy values/URLs, or credentials. The script adds
    no telemetry.
11. Include comment-based help and a `windows/README.md` with usage examples,
    limitations, and authoritative Microsoft references.
12. Add Pester tests that mock system/network operations and verify report-only
    behavior, WUA search settings/source selection, log allowlisting,
    elevation refusal, exact repair service set/state transitions,
    partial-failure recovery, each recommendation-table branch, and `-WhatIf`.
    Run PSScriptAnalyzer and verify Windows 11 / Windows PowerShell 5.1
    compatibility. Do not run a real repair on the user's machine.

## Decisions

- **Prior art/build choice:** The target repository has no Windows Update
  health/repair script. Microsoft troubleshooting and the `PSWindowsUpdate`
  module already cover portions of the repair problem. Build a narrower,
  dependency-free report/repair tool rather than duplicate general update
  management or add a module dependency.
- **Platform:** Windows 11 first; built-in Windows PowerShell 5.1; other Windows
  versions deferred.
- **Network check:** Use the Windows Update Agent search against the configured
  source rather than hard-coded public endpoint probes, because endpoints and
  managed update sources vary. Set `Online = $true` and
  `ServerSelection = ssDefault`; do not set `ServiceID` or select a specific
  public service. Run by default; `-SkipNetworkTest` opts out.
- **Repair boundaries:** The cache/service reset is the `-Fix` operation;
  system-file repair is a distinct `-RepairSystemFiles` opt-in. Never change
  managed policy or update source.
- **Privilege boundary:** Report mode is unelevated. Any `-Fix` invocation
  requires elevation and fails closed if not elevated.
- **Privacy:** Keep logs local and omit user/device identity, update titles,
  server names, policy values/URLs, and free-form error/process output. Enforce
  the log-field allowlist in tests. A real Windows Update search still contacts
  the configured update source as requested.
- **Publication:** Prepare local repository changes only; do not push or
  publish without Nick's explicit approval.

## Non-goals

- Installing, hiding, or uninstalling updates.
- Changing the update source, WSUS/MDM/Group Policy settings, firewall rules,
  proxy settings, service startup configuration, service ACLs, or network
  configuration.
- Automatically running DISM/SFC as part of the default report or basic
  `-Fix` operation.
- Guaranteeing root-cause identification or testing every Microsoft endpoint.
- Supporting Windows versions other than Windows 11 in this first version.

## Open risks and limitations

- The online Windows Update Agent search is synchronous, contacts the
  configured source, and may take time. A failed search may reflect a managed
  network, policy, proxy, transient service error, or other cause; report the
  observed result without claiming a single root cause.
- Renamed cache folders consume disk space until the user removes them.
- Cache repair can fail partway through. On a partial rename failure, attempt
  safe rollback and restore services that were previously running; if rollback
  fails, report the exact backup/original paths and manual recovery guidance.
- On successful cache reset, the repair starts all three specified services,
  including any that were stopped before the run. On failure, it restores only
  the previously running services. This distinction must be explicit and tested.
- DISM/SFC can take a long time and require elevation; report progress and
  preserve their exit/result codes. Do not automatically reboot.
- The report cannot verify physical power, external hardware, third-party
  driver/security compatibility, or organization-side approvals. Present
  Microsoft-backed checks and label these items unknown when not observable.
- Microsoft endpoint and troubleshooting guidance can change. Keep the
  authoritative links in help/docs and re-check them before publication.

## Authoritative sources reviewed

- Target repository and current tree: <https://github.com/nickprignano/ps-scripts>
- Repository README (PowerShell 5.1 or 7+):
  <https://github.com/nickprignano/ps-scripts/blob/main/README.md>
- Repository lint workflow (PSScriptAnalyzer on changed PowerShell scripts):
  <https://github.com/nickprignano/ps-scripts/blob/main/.github/workflows/lint.yml>
- PowerShell Gallery, `PSWindowsUpdate` package and `Reset-WUComponents`:
  <https://www.powershellgallery.com/packages/PSWindowsUpdate>
- Microsoft Windows Update troubleshooting for Windows 10 (updated September
  11, 2026), cited only for related WSUS/WinHTTP proxy behavior; not treated as
  Windows 11-specific guidance:
  <https://learn.microsoft.com/en-us/troubleshoot/windows-client/installing-updates-features-roles/windows-update-issues-troubleshooting>
- Microsoft Windows 11 Enterprise connection endpoints (updated June 16,
  2026): <https://learn.microsoft.com/en-us/windows/privacy/manage-windows-11-endpoints>
- Microsoft Windows 11 non-Enterprise connection endpoints (updated November
  7, 2025):
  <https://learn.microsoft.com/en-us/windows/privacy/windows-11-endpoints-non-enterprise-editions>
- Windows Update Agent `IUpdateSearcher` and `Search` references:
  <https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nn-wuapi-iupdatesearcher>
  and <https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iupdatesearcher-search>
- Microsoft `ServerSelection` reference (the `ssDefault` value uses the
  managed server when configured, otherwise the first eligible service):
  <https://github.com/MicrosoftDocs/sdk-api/blob/docs/sdk-api-src/content/wuapicommon/ne-wuapicommon-serverselection.md>
- Microsoft Windows Update Agent online-search and source-selection property
  references:
  <https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iupdatesearcher-put_online>
  and <https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iupdatesearcher-put_serverselection>
- Windows PowerShell 5.1 `Get-WinEvent` filtering by Level:
  <https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.diagnostics/get-winevent?view=powershell-5.1>
- Microsoft StandardEventLevel severity values (Error=2,
  Informational=4):
  <https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.eventing.reader.standardeventlevel?view=net-11.0-pp>
- Microsoft Windows PowerShell 5.1 `Get-WinEvent` reference (supports filtering
  by event `Level`):
  <https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.diagnostics/get-winevent?view=powershell-5.1>
- Microsoft `StandardEventLevel` reference (Error is 2; Informational is 4,
  updated May 27, 2026):
  <https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.eventing.reader.standardeventlevel?view=net-11.0-pp>
- Microsoft Windows Update troubleshooting/reset guidance:
  <https://support.microsoft.com/en-us/windows/troubleshoot-problems-updating-windows-188c2b0f-10a7-d72f-65b8-32d177eb136c>
  and <https://learn.microsoft.com/en-us/troubleshoot/windows-client/installing-updates-features-roles/additional-resources-for-windows-update>

## Evidence notes for review

- The Microsoft `ServerSelection` reference says `ssDefault` uses the managed
  server when one is configured; otherwise it uses the first service registered
  with Automatic Updates that is not managed. The `IUpdateSearcher::Search`
  reference describes a synchronous search using the searcher's current
  settings and returns a search result/update collection. `Online` controls
  whether the search goes online. `ServiceID` is relevant to a non-Windows
  Update service only when `ServerSelection` is `ssOthers`. These facts support
  setting `Online = $true`, selecting `ssDefault`, and not setting `ServiceID`.
  Source excerpts (Microsoft API references; accessed 2026-10-25):
  - `ssDefault`: “Indicates that the search call should search the default
    server.” If a managed server is configured, it is used; otherwise WUA uses
    the first eligible service registered with Automatic Updates.
  - `IUpdateSearcher::Search`: “Performs a synchronous search for updates.” The
    result contains an operation result and updates matching the criteria.
  - `Online` indicates whether the searcher goes online; `ServiceID` selects a
    non-Windows Update service only with `ssOthers`.
- The current Microsoft Windows 11 support guide maps `0x80070057` and
  `0x80080005` to possible corrupted files or incorrect system configuration
  and recommends SFC. Its advanced system-file steps run DISM
  `/Online /Cleanup-Image /RestoreHealth` followed by SFC `/scannow`. These
  codes are indications for a documented next step, not proof of corruption.
  Source excerpt (Microsoft Support, accessed 2026-10-25): for
  `0x80070057`/`0x80080005`, the page says “Corrupted files or incorrect system
  configurations” and instructs users to run System File Checker. Its advanced
  “Restore and repair system files” section runs DISM `/Online
  /Cleanup-image /Restorehealth`, followed by `sfc /scannow`.
  The same guide says `0x800f0922` can reflect insufficient disk space or .NET/
  other component issues. Its free-space examples are specifically framed for
  Windows upgrades, so the spec uses no universal disk-space threshold.
- The same support guide recommends checking network, power, administrator
  access, external hardware, cache, date/time, drivers, disk space, and
  Windows Update errors before advanced repair. It documents renaming the Software
  Distribution and catroot2 folders, rather than requiring deletion of data.
  The separate Microsoft component-reset article explicitly names `BITS`,
  `wuauserv`, and `cryptsvc` in the stop/start sequence. Source excerpt:
  “Stop the BITS service, the Windows Update service and the Cryptographic
  service”; later, “Restart the BITS service, the Windows Update service and
  the Cryptographic service.”
- Microsoft documents different connection endpoint sets for Windows 11
  editions. A separate Windows 10 troubleshooting article covers multiple
  update sources and WinHTTP proxy behavior; it is cited only as related
  background, not as Windows 11-specific guidance. This supports testing the
  configured WUA source instead of treating a fixed public endpoint list as
  exhaustive.
  Source excerpts: the current Windows 11 support page advises checking
  internet/power, external hardware, cache, date/time, drivers, and disk space;
  Windows 11 endpoint pages list different destinations by edition and include
  wildcards. The Windows 10 troubleshooting article covers WSUS and WinHTTP
  proxy configuration; these details are not assumed to be Windows 11-specific.
- Windows PowerShell 5.1 `Get-WinEvent` supports `Level` in its
  `FilterHashtable`. Microsoft defines standard event level 2 as Error and
  level 4 as Informational. The report filters to error-level
  WindowsUpdateClient events before extracting a code, and reports event-log
  read failures as unknown.
- A read-only PowerShell 5.1 query with a valid log/provider but a future start
  time returned `NoMatchingEventsFound`; the implementation treats this
  specific result as a successful empty query. This was tested without reading
  any event content from the machine.
- If a repair service cannot be restarted after the cache operation, the base
  repair is partial and the separate DISM/SFC commands are skipped for that
  invocation.
- The target repository README states PowerShell 5.1 or 7+; its current tree
  contains two unrelated Windows scripts and no Windows Update health/repair
  script. The PowerShell Gallery page lists `Reset-WUComponents`, minimum
  PowerShell 5.1, and `PSWindowsUpdate` 2.2.1.5 as last published 2024-07-20.
  These are the verified prior-art/build-choice inputs.

## Test seams

- Pester must replace/mimic Windows Update Agent COM search, service control,
  filesystem/cache operations, elevation checks, and process invocation.
- Unit tests must not make real network requests or mutate the test host.
- Assert the WUA search uses `ssDefault`, `Online = $true`, the documented
  criteria, and no `ServiceID`; verify `-SkipNetworkTest` prevents the online
  search.
- Inject sentinel PII, update titles, server names, policy URLs, and raw
  exception/process output; assert none are written to the log.
- Test that unreadable pending-reboot indicators, policy configuration, or
  Windows Update error logs produce **unknown**, not “not detected” or pass.
  Only error-level WindowsUpdateClient events may contribute failure codes;
  event-log read status is included in the allowlisted log. Treat the specific
  no-matching-events error as an available empty result, while genuine read
  failures remain unknown.
- Test that a missing disk result or null `FreeSpace` value is unknown and
  defers system-file recommendations; never cast null to zero.
- Test that unavailable service, OS, or disk-space data prevents a system-file
  repair recommendation and prevents an overall pass.
- Mock the exact `BITS`, `wuauserv`, and `CryptSvc` set. On success, assert all
  three are started; on failure, assert only originally running services are
  restarted. Mock stop, rename, rollback, and start failures; verify safe
  rollback, preserved backups, and actionable partial-failure reporting.
- Table-test recommendations: qualifying system-file codes + successful
  network search + no direct finding recommend DISM/SFC; a direct finding
  defers; skipped/unavailable network is unknown/deferred; `0x800f0922` points
  to storage/component checks but not DISM/SFC; other codes do not trigger a
  system-file recommendation. Verify raw free-space values alone are
  informational. Verify `-WhatIf` prevents mutation while producing a plan.
- Run script analysis and a PowerShell 5.1 syntax/runtime check on Windows 11.

## Review gate

This exact spec requires independent Red Team review before Blueprint. Resolve
or explicitly disposition all findings, then wait for the final review before
moving to Blueprint.
