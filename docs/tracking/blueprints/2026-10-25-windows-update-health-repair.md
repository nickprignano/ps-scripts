# Blueprint — Windows Update Health and Repair

- **Loop:** `2026-10-25-windows-update-health-repair`
- **Status:** WUR-001 complete locally; not published
- **Spec:** [Windows Update Health and Repair Script](../specs/2026-10-25-windows-update-health-repair.md)
- **Package count:** 1; no issue tracker ticket created. Package text below is issue-ready.

## Package WUR-001 — Build health and repair script

### Goal

Implement the approved spec as one self-contained PowerShell 5.1 package:
script, usage documentation, Pester tests, and focused verification.

### Context

- Read the approved spec before implementation; it contains user decisions,
  acceptance criteria, authoritative sources, and review dispositions.
- Repository instructions reviewed: root `README.md` and
  `.github/workflows/lint.yml`; no repository `AGENTS.md`, `CLAUDE.md`, or
  OpenCode config was present.
- Prior-art review and Microsoft fact-check are recorded in the session log and
  spec evidence notes. The final independent Red Team spec review passed.
- Preserve existing untracked `docs/tracking/` work belonging to another
  active session. Do not modify the shared `BUILD_LOG.md` until loop close.

### Scope and owned files

- Add `windows/Test-WindowsUpdateHealth.ps1`.
- Add `windows/README.md` with run examples, modes, limitations, and Microsoft
  references.
- Add `windows/tests/Test-WindowsUpdateHealth.Tests.ps1` using Pester.
- Do not modify unrelated scripts, the root README, CI workflows, or managed
  system configuration.

### Interfaces and behavior

- Parameters: `-Fix`, `-RepairSystemFiles`, and `-SkipNetworkTest`; support
  PowerShell common `-WhatIf` for repairs.
- Report by default without requiring elevation. Run a WUA search by default
  using `Online = $true`, `ServerSelection = ssDefault`, no `ServiceID`, and
  criteria `IsInstalled=0 and IsHidden=0`. Do not install updates or force a
  source. `-SkipNetworkTest` skips the online search.
- Log only the spec's allowlisted fields under the current user's local app
  data. Keep WUA/server/policy identifiers and raw error/process output out of
  the log.
- `-Fix` fails closed unless already elevated. Repair exactly `BITS`,
  `wuauserv`, and `CryptSvc`; preserve the spec's success/failure service-state
  rules and cache rollback behavior.
- `-RepairSystemFiles` requires `-Fix`, runs DISM RestoreHealth then SFC, and
  follows the spec's deterministic code/findings recommendation table. Skip
  these scans if the cache/service repair is partial or a required service
  cannot restart.
- Use narrow internal functions to isolate WUA COM, service control,
  filesystem/cache moves, logging, elevation, and external process invocation
  for mocking. Do not add runtime module dependencies.

### Acceptance criteria

All criteria in the approved spec are binding. In particular:

1. Windows 11 / built-in Windows PowerShell 5.1; report mode does not require
   elevation.
2. WUA online search uses the configured default source and is skipped only
   with `-SkipNetworkTest`; no update installation.
3. Output/log distinguish pass, finding, and unknown; log matches the exact
   allowlist and contains no PII, update titles, hostnames, policy values/URLs,
   or free-form command/exception output.
4. `-Fix` refuses unelevated execution before mutation and preserves the exact
   specified service states, cache backups, and rollback behavior.
5. `-RepairSystemFiles` runs only with its separate opt-in and follows the
   approved recommendation rules, including `0x800f0922` and informational-only
   free-space behavior.
6. `-WhatIf` makes no repair changes while displaying the planned operations.
7. Usage docs explain network contact, potential scan duration, elevated fix,
   local logs, retained cache backups, limitations, and manual Microsoft steps.

### Tests and verification

- Pester mocks must cover WUA settings/search results, `-SkipNetworkTest`, log
  allowlisting with sentinel secrets, elevation refusal, all exact repair
  service transitions, each filesystem rollback/error branch, DISM/SFC
  recommendation table branches, unknown/null disk data, and `-WhatIf`.
- Unit tests must not make network calls or mutate the host. Do not run a live
  Windows Update search or a real repair on Nick's machine without a separate
  explicit request.
- Run `Invoke-Pester` against the new test file.
- Run `Invoke-ScriptAnalyzer -EnableExit` on the new script and verify parsing/
  runtime compatibility with Windows PowerShell 5.1 on Windows 11 where
  available.
- Existing GitHub lint workflow analyzes changed PowerShell scripts; CI may be
  observed if changes are later pushed, but no push is authorized in this
  package.

### Risks and stop conditions

- WUA search is synchronous and may be slow; never switch to a static endpoint
  list or force Microsoft Update to hide a configured-source failure.
- If WUA COM behavior cannot be mocked without changing the source-selection
  contract, stop and report rather than weaken the spec.
- If any repair path cannot guarantee rollback/restore attempts, stop and revise
  the design before executing mutation.
- Do not invoke live network or system repair operations during unit testing.

### Agent/model/instructions

- Execute in the orchestrating session with GPT-6 Luna; single package, no
  parallel implementation required.
- Apply the `tdd` skill before writing behavior code/tests. Follow repository
  PowerShell style and the global pre-publication quality check.
- After the package is built, run focused checks and obtain independent Red
  Team code review before closeout. Disposition findings and rerun affected
  checks.
