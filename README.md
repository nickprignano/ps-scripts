# PowerShell & AI Tools Collection

A curated collection of PowerShell utilities for Windows power users and system administrators, co-authored in collaboration with AI assistants.

---

## 🛠️ Included Scripts

### 1. Active Directory User Exporter (`Export-ADUsers.ps1`)
* **Category**: Active Directory Administration
* **Description**: Queries Active Directory for all user accounts, parses their full Organizational Unit (OU) path into a clean root-to-leaf string, formats group memberships, and exports the data to `ADUsersExport.csv`.
* **Output Fields**: `FirstName`, `LastName`, `UPN`, `OU`, `Groups`, and `Enabled`.

### 2. NVIDIA Studio Driver Auto-Updater (`AutoUpdate-NvidiaStudioDriver.ps1`)
* **Category**: Windows Lifehacks / System Maintenance
* **Description**: Detects installed NVIDIA GPU driver versions via WMI, queries the official NVIDIA API for the latest Creator Ready / Studio Driver (CRD), and silently downloads and updates the driver if a newer version is available.
* **Key Feature**: Includes a `$DryRun` mode (enabled by default) to preview download links, target installation paths, and silent execution flags before making system changes.

---

## ⚡ Prerequisites & Setup

### System Requirements
* **PowerShell Version**: PowerShell 5.1 or PowerShell 7+
* **Active Directory Module**: Required for `Export-ADUsers.ps1` (part of RSAT).
* **Administrator Rights**: Required for `AutoUpdate-NvidiaStudioDriver.ps1` to inspect hardware drivers and execute silent driver installations.

### Execution Policy
To allow local script execution, open PowerShell as an Administrator and run:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser