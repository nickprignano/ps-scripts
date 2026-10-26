# Blueprint — Windows Security Health Check and Repair

- **Loop:** `2026-10-25-windows-security-health-check`
- **Status:** Dispatch complete (`WSH-001` through `WSH-003`); pending final verification
- **Spec:** [Locked Windows Security Health Check and Repair](../specs/2026-10-25-windows-security-health-check.md)
- **Target repository:** `nickprignano/ps-scripts`
- **Package count:** 3; issue-ready text only; no tracker tickets created

## Dispatch rules

- Follow the locked spec; it is the source of truth for behavior and safety.
- Execute packages sequentially because they extend the same standalone script
  and Pester test file. Do not parallelize implementation.
- Apply the `tdd` skill in each implementation session: one failing behavior
  test, minimal implementation, then refactor only after the slice passes.
- Do not write tests until the user confirms the test seams proposed in this
  Blueprint. Once confirmed, test through the script's public parameter
  interface and mock external Windows/network/side-effect adapters.
- Never run a real MAPS test, WUA live search, Defender signature update, or any
  other security mutation on the user's machine. Unit and CI tests use mocks.
- After each package, run its focused checks and obtain an independent Red Team
  code review/smell test. Resolve findings and rerun affected checks before the
  next package.
- Preserve current untracked Windows Update work. It owns
  `windows/Test-WindowsUpdateHealth.ps1`,
  `windows/tests/Test-WindowsUpdateHealth.Tests.ps1`, and currently has an
  untracked `windows/README.md`. Do not overwrite those files. The Security
  test uses a separate filename. Package WSH-003 must wait until the Windows
  Update README work is complete, then append a Security section to the shared
  README without rewriting existing content. Do not edit shared
  `docs/tracking/BUILD_LOG.md` until loop close.
- Do not create GitHub issues, commit, push, publish, or release without
  separate authorization.

## Confirmed test seams (user-confirmed 2026-10-25)

1. **Public script entry point and parameters:** invoke the script with default
   and opt-in parameters; verify status/report behavior and generated files.
2. **Read-only OS adapters:** Pester mocks for Defender cmdlets, WSC product
   data, firewall profile query, SmartScreen/policy reads, Secure Boot, TPM,
   BitLocker, DeviceGuard, UAC, OS/lifecycle data, and local update history.
3. **External action adapters:** mockable wrappers around MAPS process
   invocation and WUA COM search; tests prove no real network operation and no
   source override.
4. **Repair gate:** mock elevation, provider state, and `Update-MpSignature`;
   test the complete fail-closed predicate and prove `-WhatIf` never invokes
   the update cmdlet.
5. **Output safety:** real temporary local test directory for HTML/TXT output;
   prove redaction, unique-folder collision handling, network-path rejection,
   and the printed-but-not-executed Explorer command. Tests clean only their own
   temporary files.

## WSH-001 status

- 2026-10-25: user confirmed all five proposed seams. Package may now begin
  with TDD. No implementation or tests have been written yet.

1. **Public script entry point and parameters:** invoke the script with default
   and opt-in parameters; verify status/report behavior and generated files.
2. **Read-only OS adapters:** Pester mocks for Defender cmdlets, WSC product
   data, firewall profile query, SmartScreen/policy reads, Secure Boot, TPM,
   BitLocker, DeviceGuard, UAC, OS/lifecycle data, and local update history.
3. **External action adapters:** mockable wrappers around MAPS process
   invocation and WUA COM search; tests prove no real network operation and no
   source override.
4. **Repair gate:** mock elevation, provider state, and `Update-MpSignature`;
   test the complete fail-closed predicate and prove `-WhatIf` never invokes
   the update cmdlet.
5. **Output safety:** real temporary local test directory for HTML/TXT output;
   prove redaction, unique-folder collision handling, network-path rejection,
   and the printed-but-not-executed Explorer command. Tests clean only their own
   temporary files.

## Package WSH-001 — Read-only assessment and local report

### Goal

Implement the default offline, report-only script path: read-only assessment,
bounded status classification, lifecycle lookup, privacy-minimal local HTML/TXT
reports, console summary, and safe output-folder creation.

### Context

- Read the locked spec sections **Assessment coverage**, **Acceptance
  criteria**, **Limitations and risks**, and **Test seams**.
- Follow existing PowerShell style in `windows/`; do not modify the Windows
  Update script, its tests, or the shared README during this package.
- No output artifacts may contain unredacted usernames/device/organization
  details, raw policy data, WSC provider names, update titles, or source hosts.

### Scope and owned files

- Add `windows/Test-WindowsSecurityHealth.ps1` with comment-based help and the
  read-only assessment path.
- Add `windows/tests/Test-WindowsSecurityHealth.Tests.ps1` with Pester tests for
  report-only behavior, status mapping, privacy, lifecycle cases, and output
  folder behavior.
- Keep this package's output/network/report path isolated from the concurrent
  Windows Update work.

### Acceptance criteria

1. Default invocation is compatible with Windows PowerShell 5.1 and PowerShell
   7 on Windows and makes no network or system-changing call.
2. Collect the specified Defender/WSC, Firewall, SmartScreen/policy, platform
   protection, and local OS/update-history signals. Missing, unsupported,
   denied, malformed, and contradictory data is bounded as Unknown/Not
   applicable without aborting unrelated checks.
3. Lifecycle lookup is keyed by recognized edition family, channel, and
   feature version. It covers exactly the locked spec's GA, SE, IoT Enterprise,
   and LTSC rows; unsupported/unmapped rows remain Unknown. The checked-in table
   includes its source/as-of date.
4. Console/HTML/TXT output contains only approved fields; HTML values are
   escaped; no raw policy/provider/update identifiers are emitted.
5. Output defaults to a timestamped folder under LocalAppData; a local output
   directory override is supported. Reject UNC/mapped-network paths. On a
   collision, create a unique numeric suffix or abort before writing. Never
   overwrite an existing report. The default console command uses
   `$env:LOCALAPPDATA`; a custom path appears only in console output and not in
   saved artifacts.
6. No browser is launched. The folder-opening command is printed, not executed.

### Tests and verification

- Use confirmed public seams; mock all Windows queries. Do not call real WSC
  product COM, Defender cmdlets, WUA COM, or security-related APIs against the
  host beyond harmless parser/static analysis.
- Tests cover representative pass/finding/unknown/not-applicable states,
  third-party AV, WSC unavailable/stale, firewall policy-origin unknown,
  SmartScreen policy-only evidence, supported/expired/unknown lifecycle rows,
  privacy sentinel values, HTML escaping, collision preservation, network path
  rejection, and command printing without execution.
- Run the focused Pester file and PSScriptAnalyzer on the new script.

## Package WSH-002 — Opt-in network checks and approved repair

### Goal

Add `-CloudCheck`, `-LiveUpdateCheck`, `-Fix`, and `-WhatIf` after the default
report is complete and tested.

### Dependencies and owned files

- Depends on **WSH-001** and user confirmation of the detailed test seams.
- Extend `windows/Test-WindowsSecurityHealth.ps1` and
  `windows/tests/Test-WindowsSecurityHealth.Tests.ps1` only.

### Acceptance criteria

1. No switch means no WUA/MAPS network action and no repair.
2. `-CloudCheck` requires an already elevated session and calls only the
   documented `MpCmdRun.exe -ValidateMapsConnection` operation. It does not
   download tools or test arbitrary URLs/files.
3. `-LiveUpdateCheck` sets `Online` only on its per-run searcher object, keeps
   configured `ServerSelection`, searches uninstalled/non-hidden software
   updates, installs nothing, and reports only result/status/duration/count.
4. `-Fix` requires elevation and invokes `Update-MpSignature` only when every
   locked predicate is satisfied: stale Boolean true, Defender mode Normal,
   WSC Microsoft Defender ON, and no non-Microsoft AV ON. Unknown, malformed,
   or conflicting data fails closed. No age threshold or update source override
   is introduced.
5. `-WhatIf` produces a clear plan and never calls `Update-MpSignature`. No
   approved repair changes Defender settings, firewall, SmartScreen, services,
   policy, or Windows Update configuration.

### Tests and verification

- Mock the WUA adapter, MAPS process adapter, elevation detection, WSC product
  state, and `Update-MpSignature`.
- Assert default network/action call counts are zero; each explicit switch
  activates only its own adapter; no source selection is changed; update titles,
  URLs, raw COM errors, and hostnames are absent; all incomplete/contradictory
  repair preconditions skip mutation; and `-WhatIf` makes zero update calls.
- Run focused Pester and PSScriptAnalyzer. No live update search or repair.

## Package WSH-003 — Documentation, Windows CI, and integration closeout

### Goal

Document the Security script alongside existing Windows utilities, add Windows
PowerShell 5.1/PowerShell 7 Pester CI, and perform final integration verification.

### Dependencies and owned files

- Depends on **WSH-001** and **WSH-002**.
- Wait until the in-progress Windows Update work no longer owns
  `windows/README.md`. Then append a Security section to that file, preserving
  all existing content and the Windows Update section.
- Add a separate workflow, for example
  `.github/workflows/windows-security-health-tests.yml`, rather than changing
  the existing cross-platform PSScriptAnalyzer workflow unless implementation
  proves a minimal shared change is necessary.
- Update only the new Security test file or workflow as needed; do not change
  Windows Update files.

### Acceptance criteria

1. `windows/README.md` documents invocation, default offline behavior, each
   opt-in's network/elevation contract, the sole approved repair, `-WhatIf`,
   LocalAppData/local-path behavior, the console folder command, manual HTML to
   PDF printing, privacy, lifecycle table coverage/as-of date, limitations, and
   authoritative source links.
2. Windows CI runs Pester on Windows PowerShell 5.1 and PowerShell 7, using
   mocks only. It does not invoke live network checks or security changes.
3. Existing PSScriptAnalyzer workflow remains functional and unrelated
   workflows/files are unchanged.
4. Run the complete Security Pester suite under both engines when available,
   run PSScriptAnalyzer, and verify the script parses and help renders.
5. Review the final diff against the locked spec; report checks and anything
   unavailable. No push or publication.

### Stop conditions

- If Windows Update README work is still in progress, do not edit the shared
  README. Pause this package and ask the user whether to wait or use an
  alternative doc file.
- If PowerShell 5.1/7 behavior differs for an approved adapter or provider
  state, mark that result Unknown and report the compatibility limitation;
  do not add a module dependency or weaken the safety boundary silently.
- If an action cannot be fully mocked, stop before running it against the
  user's machine and ask for a safe test environment.
