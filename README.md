# PowerShell & AI Tools Collection

A curated collection of PowerShell utilities for Windows administration and system automation, co-authored with AI assistants.

---

## 🛠️ Included Scripts

### 1. Active Directory User Exporter (`Export-ADUsers.ps1`)
* **Description**: Queries Active Directory for all user accounts, parses their organizational unit (OU) hierarchy, formats group memberships, and exports the dataset to a structured CSV file (`ADUsersExport.csv`).
* **Exported Fields**: `FirstName`, `LastName`, `UPN`, `OU` (root-to-leaf path), `Groups` (semicolon-separated list), and `Enabled` status.

### 2. Drive Update Utility (`Update-MappedDrives.ps1`)
* **Description**: Automates the management, updating, and remediation of network drive mappings for Windows user sessions.

---

## ⚡ Prerequisites & Setup

### Requirements
* **PowerShell Version**: PowerShell 5.1 or PowerShell 7+.
* **RSAT (Active Directory Module)**: Required for the AD export script. Verify installation with:
  ```powershell
  Get-Module -ListAvailable ActiveDirectory