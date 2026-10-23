# Vibecoded PowerShell Tools Collection

A curated collection of PowerShell utilities for Windows power users and system administrators, co-authored in collaboration with AI assistants.

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
