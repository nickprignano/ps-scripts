# Windows Security Health Check and Repair

- **Status:** Locked — user-approved, fact-checked, and Red Team findings resolved
- **Loop:** `2026-10-25-windows-security-health-check`
- **Target repository:** `nickprignano/ps-scripts`
- **Target implementation:** `windows/Test-WindowsSecurityHealth.ps1`
- **Spec version:** 1

## Goal

Create a public, standalone Windows PowerShell script that assesses important
local Windows 11 security posture, reports limitations honestly, and provides
only one explicitly approved, narrowly scoped repair. It is a health check, not
a universal compliance scanner or guarantee that a device is secure.

The script must run on Windows 11 client editions in Windows PowerShell 5.1 and
PowerShell 7 on Windows. It must not require an external module at runtime.

## User-approved scope and decisions

1. The default mode is read-only and makes no network request.
2. The report covers the local security areas below. It does not claim CIS/STIG
   compliance, perform an exhaustive registry audit, or assess third-party
   applications or a cloud tenant.
3. Each check is reported as **Pass**, **Finding**, **Unknown**, or
   **Not applicable**. Do not calculate a universal security score. Missing or
   inaccessible evidence is not itself proof of a security failure.
4. The script runs in the current privilege context and never self-elevates.
   Checks requiring administrator privileges are `Unknown` if unavailable.
   The opt-in `-CloudCheck` and `-Fix` modes require an already elevated
   session.
5. Network activity is separately opt-in:
   - `-CloudCheck` validates Microsoft Defender MAPS connectivity only.
   - `-LiveUpdateCheck` searches the currently configured Windows Update
     source, without changing the source or installing updates.
   - Neither option is enabled by default. Both can take time and contact an
     external or organization-managed Microsoft update service as appropriate.
6. `-Fix` is limited to a Microsoft Defender security-intelligence update when
   the report can establish that Defender is the active antivirus provider and
   its signatures are reported out of date. It uses the configured signature
   source/fallback order and does not set a source. `-Fix` requires an already
   elevated session and does not self-elevate. `-WhatIf` previews the operation
   without invoking the update cmdlet.
7. No other repair is authorized in this version. In particular, the script
   must not configure or enable/disable Defender protections, firewall
   profiles, SmartScreen, Windows Security services, registry or centrally
   managed policy, Windows Update settings, or OS updates. It must not stop or
   restart services, run a scan, reboot, or make firewall/network changes.
8. Produce a console report, an HTML report, and a TXT log. The HTML is
   printable; the user may use a browser's print-to-PDF function manually. The
   script does not create a PDF or launch a browser.
9. By default, write the HTML and TXT files into a timestamped folder under the
   current user's LocalAppData. Allow a local output-directory override, used
   as the parent of a unique timestamped report folder. Reject UNC and mapped
   network output paths so the script does not write reports to a network
   share. If the timestamp folder already exists, append a numeric suffix and
   choose a new folder; if no safe unique folder can be created, abort before
   writing. Never overwrite prior reports or automatically delete/rotate them.
   Print a copyable command to open the output folder in Explorer, but do not
   execute it. For the default location, use `$env:LOCALAPPDATA` in the command
   rather than printing its resolved value. If an override is used, its path
   may appear in this console-only command; never persist the command/path in
   HTML or TXT. Document that LocalAppData may be redirected/synchronized by
   the environment even when it is not a network path.
10. The script adds no script-originated telemetry and never uploads
    reports/logs. Opt-in Windows service checks make the explicitly disclosed
    network requests. Saved HTML/TXT reports omit machine, user, and
    organization identifiers; raw policy values/URLs; update titles;
    update-server hostnames; and provider product names. The default
    console-only folder command uses the LocalAppData environment variable
    rather than printing the resolved user path. A custom output path may appear
    only in the console-only folder command and is never persisted in reports.
    Managed-policy results are coarse signals only.
11. Use Pester tests with mocked OS, network, and state-changing operations.
    Do not run real security changes or network checks on the user's machine.
12. Do not push, publish, or release the changes without explicit user
    approval.

## Assessment coverage

Collect only the evidence needed to report these categories:

### Defender Antivirus and Windows Security

- Query Defender status/preferences using read-only built-in Defender cmdlets
  when available. Report key protection state, running mode, signature state,
  tamper-protection signal, and selected protections (behavior monitoring,
  downloaded-file scanning, PUA, cloud-delivered protection, controlled-folder
  access, and attack-surface-reduction configuration) only where the cmdlets
  expose meaningful evidence.
- Distinguish active Defender, passive/disabled Defender, and a detected
  non-Microsoft active AV provider. Use Defender mode plus the documented WSC
  product-list/state interfaces when those interfaces return usable evidence;
  provider names may be examined only in memory and must never appear in
  output. If active-provider attribution is ambiguous, report **Unknown** and
  skip the signature repair. Do not flag Defender as unhealthy solely because
  another AV is active.
- Report only a coarse Windows Security Center/health-service availability and
  provider-health signal where it can be queried. A disabled/unavailable
  provider or stale Windows Security display yields a limitation/Unknown, not
  an inference about the underlying protection.
- Do not output raw Defender exclusions, threat history, file paths, provider
  product names, or personally identifying event data. If exclusion presence
  is assessed, report a coarse presence/count signal only.

### Windows Firewall

- Read the effective Domain, Private, and Public profile state from the active
  policy store where supported. Report whether each profile is enabled and
  whether data was available.
- Do not enumerate or print individual firewall rules, addresses, ports,
  policy-source hostnames, or raw policy values.
- Report a coarse management signal only when an explicit, documented policy
  signal is present. `ActiveStore` is the effective merged profile state, not
  proof of the policy's origin; do not label a profile centrally managed from
  `ActiveStore` alone. If origin cannot be determined, report management as
  **Unknown**. Never change firewall state or policy.

### SmartScreen and policy signals

- Inspect only documented Windows shell and Microsoft Edge SmartScreen
  configuration/policy signals available locally.
- Distinguish a detected policy value from a claim about effective runtime
  behavior. If management or precedence makes effective state uncertain, say
  so and use **Unknown**.
- Do not make a live SmartScreen URL/file reputation request or submit a test
  file. `-CloudCheck` is a Defender MAPS connectivity test, not a SmartScreen
  reputation test.
- Report policy presence at a coarse level only. Do not print organization
  identifiers, policy URLs, registry paths/values, or raw policy data.

### Platform protections and OS servicing

- Report OS edition, Windows 11 feature version/build, and local update-history
  evidence without identifying the device.
- Determine release support from a checked-in table keyed by recognized Windows
  edition family, servicing channel, and `DisplayVersion`, sourced from
  Microsoft. Cover General Availability Channel editions Home, Pro, Pro
  Education, Pro for Workstations, Education, Enterprise, Enterprise
  multi-session, and IoT Enterprise; cover Windows 11 SE only through its last
  supported feature version; and separately cover Windows 11 Enterprise LTSC
  2024 and Windows 11 IoT Enterprise LTSC 2024. Use each product's Microsoft
  lifecycle data rather than applying GA support lengths to LTSC or SE. Include
  the table's as-of date in help/docs and reports. Unknown/new editions,
  servicing channels, or versions remain **Unknown**; do not infer support from
  build number alone. Do not report IoT Enterprise 26H1 as supported.
- Report lifecycle state as **Supported**, **Extended support** (only where the
  Microsoft product lifecycle explicitly provides it), **End of updates**, or
  **Unknown**. Key rows by edition family, servicing channel, and feature
  version. Do not use monthly build recency as a substitute for lifecycle
  support status.
- Report TPM presence/readiness; Secure Boot state; OS-volume BitLocker
  protection/encryption state; virtualization-based security and Memory
  Integrity state; and UAC enabled state, when available.
- Do not retrieve, log, or display BitLocker recovery information or TPM owner
  authorization data. Elevated-only or unsupported checks are **Unknown** or
  **Not applicable**, with a short reason.
- A current configured-source update search may report the aggregate number of
  available software updates. It must not describe the device as “fully
  patched” based only on local history or a zero-result search: offers can be
  affected by policy, update holds, applicability, and timing, and the query
  is not a compliance assessment.
- Do not install Windows updates or change servicing settings.

## Network and repair behavior

### `-CloudCheck`

- Explicitly opt into Microsoft Defender's documented MAPS connectivity
  validation using the built-in `MpCmdRun.exe -ValidateMapsConnection` tool.
- Require an already elevated process. Do not self-elevate, download a tool,
  change proxy/firewall/policy, run a test-file download, or submit arbitrary
  URLs/files.
- Report pass/failure/unknown, duration, and a sanitized error code where
  available. Do not log raw command output or endpoint details.

### `-LiveUpdateCheck`

- Explicitly opt into a Windows Update Agent search for uninstalled,
  non-hidden software updates using the searcher's currently configured
  options/source. Set `Online` on the per-run searcher object to request an
  online search, but do not persist settings or set `ServerSelection`; do not
  force Microsoft Update or install/download/hide updates.
- Run in the current privilege context; do not self-elevate. Search failure is
  **Unknown**, not a finding that the system is unpatched.
- Report only success/failure, duration, and aggregate result count. Do not
  record update titles, raw COM output/errors, URLs, or source server names.

### `-Fix` and `-WhatIf`

- The sole repair is `Update-MpSignature` with no `-UpdateSource`. The repair
  trigger requires all of: `Get-MpComputerStatus.DefenderSignaturesOutOfDate`
  is Boolean `$true`; `AMRunningMode` is exactly `Normal`; Windows Security
  Center identifies Microsoft Defender as an `ON` antivirus product; and no
  non-Microsoft antivirus product is reported `ON`. Do not substitute a
  signature-age threshold.
- Require an already elevated process for `-Fix`; never self-elevate. If the
  provider, stale-state Boolean, or cmdlet is unavailable, null, non-Boolean,
  or contradictory; if the mode is not `Normal`; or if any provider is
  ambiguous, unavailable, or conflicting, skip mutation and report **Unknown**
  with the reason. If the stale-state Boolean is `$false`, do not repair. Add
  tests for each fail-closed case.
- Rely on Defender's configured source/fallback order; do not alter source,
  preferences, or policy. Clearly disclose that the update may contact the
  configured update source and changes local security-intelligence files.
- Implement `-WhatIf` through PowerShell `ShouldProcess` semantics so the
  update cmdlet is never invoked in preview mode. Report the planned action.
- The ordinary report and `-LiveUpdateCheck` remain read-only; a search is not
  an installation.

## Acceptance criteria

1. The script has comment-based help and supports Windows 11 clients in
   Windows PowerShell 5.1 and PowerShell 7 on Windows, with no runtime module
   installation or external executable dependency beyond Windows components.
2. A default invocation performs no network request and no security-setting
   change; it produces console, HTML, and TXT outputs in a unique timestamped
   folder and prints (but does not execute) the folder-opening command. A
   timestamp collision chooses a new suffixed folder or aborts before writing;
   existing files are never overwritten. UNC and mapped-network output paths
   are rejected.
3. Every category reports **Pass**, **Finding**, **Unknown**, or
   **Not applicable**. Errors, missing cmdlets, non-UEFI hardware, unsupported
   editions, and access denial are handled as bounded unknown/not-applicable
   results; they do not abort unrelated checks or create false failures.
4. Defender passive mode/third-party AV is not mislabeled as a Defender
   protection failure. WSC staleness/availability and policy uncertainty are
   disclosed.
5. Firewall output includes only effective profile states and no rule detail.
   SmartScreen output does not claim live reputation or effective state from a
   policy signal alone.
6. The lifecycle result follows the bundled, dated Microsoft edition/channel/
   version table for the stated GA, SE, IoT, and LTSC coverage. Local update
   history is described only as local evidence. Test supported, end-of-support,
   unknown edition/channel, and unknown-version cases.
7. `-CloudCheck` is skipped by default, refuses/does not self-elevate when not
   elevated, and invokes only the documented MAPS connectivity validation.
8. `-LiveUpdateCheck` is skipped by default, uses the current configured WUA
   search options/source, does not install updates, and emits no update titles
   or raw source identifiers.
9. `-Fix` is skipped by default and invokes `Update-MpSignature` only when
   `DefenderSignaturesOutOfDate` is Boolean `$true`, `AMRunningMode` is
   `Normal`, WSC reports Microsoft Defender `ON`, and no non-Microsoft AV is
   `ON`. Missing, null, malformed, conflicting, or ambiguous evidence fails
   closed as **Unknown** and skips the update. A false stale Boolean skips the
   update. It requires elevation; `-WhatIf` produces a plan and makes no update
   call.
10. Saved HTML/TXT reports exclude the prohibited identifiers and raw values.
    The default folder command uses `$env:LOCALAPPDATA`, and a custom output
    path appears only in console output, never in saved artifacts. No upload,
    script-originated telemetry, auto-open, auto-cleanup, restart, or unrelated
    mutation occurs.
11. Pester tests mock Defender cmdlets, WSC/provider queries, firewall and
    policy reads, lifecycle data, WUA search/history, process invocation,
    elevation, and output operations. Tests prove that no system-changing or
    network operation occurs by default; each repair precondition fails closed;
    `-WhatIf` never invokes the update; network output paths are rejected; and
    a report-folder collision never changes pre-existing files. Opt-in calls
    are gated and sanitized. Tests must not mutate the test host or make real
    network calls.
12. Run Pester and PSScriptAnalyzer. Validate syntax/runtime behavior under
    Windows PowerShell 5.1 and PowerShell 7 on Windows when available. Add a
    Windows CI test job for both engines if the repository's current CI
    supports it without changing unrelated workflow behavior.
13. Add `windows/README.md` with install/run examples, each opt-in's network and
    elevation behavior, output locations/collision behavior, manual HTML-to-PDF
    instructions, privacy notes, lifecycle table coverage/as-of date,
    scope/limitations, and authoritative Microsoft references.

## Limitations and risks

- The report covers selected local operating-system controls; it is not a
  vulnerability scanner, penetration test, CIS/STIG benchmark, enterprise
  compliance determination, or substitute for Windows Security or an
  organization's management console.
- Windows APIs/cmdlets, edition capabilities, hardware, third-party AV, policy
  precedence, and permissions affect visibility. **Unknown** is an expected
  outcome for some checks.
- Windows Security Center aggregates products and can display stale status if
  its services are disabled. Never infer Defender health solely from the app
  shell or a single provider status.
- SmartScreen local policy/configuration does not prove online reputation
  service reachability or guarantee how every application/browser behaves.
- The MAPS connectivity option does not test SmartScreen and may contact
  Microsoft. The WUA option may contact an organization-managed update server
  and may take time. Both are opt-in and produce only aggregate results.
- A WUA search is not equivalent to an installed-patch compliance check. It
  can show available applicable software updates but may include optional or
  non-security updates and is affected by configured policy/source.
- The in-script lifecycle table can become stale. Its as-of date and Microsoft
  source must be visible; maintenance is required when Windows support dates
  change.
- The HTML report is not a generated PDF. Users who need PDF output print the
  local HTML report themselves using a browser.
- The approved signature repair updates local security intelligence but does
  not repair Defender configuration, Windows Security, firewall, or policy.

## Prior art and build/adopt decision

- **Adopt as baseline source, not as runtime dependency:** Microsoft's Security
  Compliance Toolkit offers versioned Microsoft security baselines and
  Policy Analyzer. Those are useful references for administrators but require
  downloaded, versioned content and do not provide this standalone report and
  narrowly approved repair interface.
- **Reuse as research, not code:** HardeningKitty provides broader Windows
  audit/configuration/hardening modes and finding lists. Its write mode and
  baseline breadth do not match this report-only-by-default, tightly scoped
  safety boundary; do not bundle/import it.
- **Do not adopt for PDF:** PSWritePDF is archived and depends on third-party
  PDF libraries/licensing. The user chose printable local HTML with manual
  PDF export instead.
- **Build:** A small standalone script using Windows' built-in query
  interfaces, with isolated/testable wrappers and no runtime module
  dependency, best fits the requested scope and privacy/safety boundaries.

## Test seams

- Wrap all Windows data collection in functions that can be mocked, including
  Defender status/preferences, WSC provider health, firewall ActiveStore,
  registry/policy signals, Secure Boot, TPM, BitLocker, DeviceGuard, UAC,
  lifecycle mapping, and local update history.
- Wrap MAPS validation, WSC product-list access, WUA online search, signature
  update, elevation checks, and report/file output behind mockable functions.
  Unit tests must never call the real WSC/WUA COM interfaces, `MpCmdRun`, or
  `Update-MpSignature`.
- Use deterministic fixtures for missing cmdlets, access denied, unsupported
  hardware, third-party AV, policy present/unknown, out-of-date signatures,
  and zero/nonzero update results.
- Assert default mode performs no network/system-changing invocation; assert
  `-WhatIf` does not invoke the repair; assert sanitization and output-folder
  command behavior.

## Source of truth references

Repository conventions:

- [Repository README](https://github.com/nickprignano/ps-scripts/blob/main/README.md)
- [PSScriptAnalyzer CI workflow](https://github.com/nickprignano/ps-scripts/blob/main/.github/workflows/lint.yml)

Microsoft APIs and product documentation (reviewed 2026-10-25):

- [Get-MpComputerStatus](https://learn.microsoft.com/en-us/powershell/module/defender/get-mpcomputerstatus)
- [Get-MpPreference](https://learn.microsoft.com/en-us/powershell/module/defender/get-mppreference)
- [Update-MpSignature](https://learn.microsoft.com/en-us/powershell/module/defender/update-mpsignature)
- [Microsoft Defender Antivirus compatibility/modes](https://learn.microsoft.com/en-us/defender-endpoint/microsoft-defender-antivirus-compatibility)
- [Windows Security and Windows Security Center services](https://learn.microsoft.com/en-us/windows/security/operating-system-security/system-security/windows-defender-security-center/windows-defender-security-center)
- [Get-NetFirewallProfile](https://learn.microsoft.com/en-us/powershell/module/netsecurity/get-netfirewallprofile)
- [Windows Security Center provider health](https://learn.microsoft.com/en-us/windows/win32/api/wscapi/nf-wscapi-wscgetsecurityproviderhealth)
- [Windows Security Center product list](https://learn.microsoft.com/en-us/windows/win32/api/iwscapi/nn-iwscapi-iwscproductlist), [initialization](https://learn.microsoft.com/en-us/windows/win32/api/iwscapi/nf-iwscapi-iwscproductlist-initialize), [product name](https://learn.microsoft.com/en-us/windows/win32/api/iwscapi/nf-iwscapi-iwscproduct-get_productname), and [product state](https://learn.microsoft.com/en-us/windows/win32/api/iwscapi/nf-iwscapi-iwscproduct-get_productstate)
- [WSC_SECURITY_PRODUCT_STATE values](https://learn.microsoft.com/en-us/windows/win32/api/iwscapi/ne-iwscapi-wsc_security_product_state)
- [Microsoft Defender SmartScreen available settings](https://learn.microsoft.com/en-us/windows/security/operating-system-security/virus-and-threat-protection/microsoft-defender-smartscreen/available-settings)
- [Confirm-SecureBootUEFI](https://learn.microsoft.com/en-us/powershell/module/secureboot/confirm-securebootuefi)
- [Get-Tpm](https://learn.microsoft.com/en-us/powershell/module/trustedplatformmodule/get-tpm)
- [Get-BitLockerVolume](https://learn.microsoft.com/en-us/powershell/module/bitlocker/get-bitlockervolume)
- [Memory integrity and Win32_DeviceGuard](https://learn.microsoft.com/en-us/windows/security/hardware-security/enable-virtualization-based-protection-of-code-integrity)
- [User Account Control](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/user-account-control/)
- [Windows 11 release information](https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information)
- [Windows 11 Home/Pro lifecycle](https://learn.microsoft.com/en-us/lifecycle/products/windows-11-home-and-pro)
- [Windows 11 Enterprise/Education lifecycle](https://learn.microsoft.com/en-us/lifecycle/products/windows-11-enterprise-and-education)
- [Windows 11 IoT Enterprise lifecycle](https://learn.microsoft.com/en-us/lifecycle/products/windows-11-iot-enterprise)
- [Windows 11 Enterprise LTSC 2024 lifecycle](https://learn.microsoft.com/en-us/lifecycle/products/windows-11-enterprise-ltsc-2024)
- [Windows 11 IoT Enterprise LTSC 2024 lifecycle](https://learn.microsoft.com/en-us/lifecycle/products/windows-11-iot-enterprise-ltsc-2024)
- [MpCmdRun MAPS connection validation](https://learn.microsoft.com/en-us/defender-endpoint/configure-network-connections-microsoft-defender-antivirus)
- [IUpdateSearcher::Search](https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iupdatesearcher-search)
- [IUpdateSearcher::Online](https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iupdatesearcher-get_online)
- [IUpdateSearcher server selection](https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iupdatesearcher-get_serverselection)
- [PowerShell Windows PowerShell compatibility](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_windows_powershell_compatibility)
- [Microsoft Security Compliance Toolkit](https://www.microsoft.com/en-us/download/details.aspx?id=55319)

Prior art:

- [HardeningKitty](https://github.com/scipag/HardeningKitty)
- [PSWritePDF (archived)](https://github.com/EvotecIT/PSWritePDF)

## Review gate

This exact draft must receive independent Red Team review against the user's
goals, acceptance criteria, and linked source documentation. Resolve or
explicitly disposition every finding, update this spec if required, and obtain
the final review before creating the Blueprint. Do not begin implementation
packages before that gate passes.
