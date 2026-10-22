# ⚡ PowerShell & AI Tools Collection

Welcome to the **PowerShell & AI Tools** repository! This is a curated collection of PowerShell scripts tailored for Windows power users and Microsoft system administrators. 

These tools cover day-to-day Windows lifehacks, system optimization, and Active Directory (AD) administration—co-authored in collaboration with AI assistants.

---

## 📂 Categories & Focus Areas

| Category | Description | Target Audience |
| :--- | :--- | :--- |
| **`/ActiveDirectory`** | User management, group membership audits, account lockouts, and domain reporting | SysAdmins / IT Support |
| **`/SysAdmin`** | Windows service tweaks, disk cleanup, event log analysis, and network diagnostics | IT Admins |
| **`/PowerUser`** | File Explorer enhancements, OS telemetry tweaks, shortcuts, and workflow automation | Power Users |

---

## 🛠️ Featured Tools

### Active Directory (`/ActiveDirectory`)
* **`Get-ADUserAudit.ps1`**: Audits Active Directory for inactive accounts, expired passwords, and misconfigured flags.
* **`Reset-ADUserSession.ps1`**: Rapidly unlocks locked AD users and resets passwords with forced change at next logon.

### System Administration (`/SysAdmin`)
* **`Clean-WinDiskSpace.ps1`**: Safely purges temporary files, Windows update caches, and old log archives.
* **`Get-ServerHealthReport.ps1`**: Compiles a quick HTML/console summary of system metrics, disk usage, and service health.

### Windows Lifehacks (`/PowerUser`)
* **`Optimize-WinPerformance.ps1`**: Disables non-essential background telemetry services and optimizes startup tasks.
* **`Set-PowerUserContextMenu.ps1`**: Adds custom utilities (e.g., "Copy Path", "Open PowerShell Here as Admin") to the context menu.

---

## ⚡ Prerequisites & Setup

### Requirements
1. **PowerShell Version**: PowerShell 5.1 or PowerShell 7+ (Recommended).
2. **RSAT (Remote Server Administration Tools)**: Required for Active Directory scripts.
   ```powershell
   Get-Module -ListAvailable ActiveDirectory
   ```
3. **Admin Privileges**: Run PowerShell with elevated rights (`Run as Administrator`) for system-level or AD operations.

### Execution Policy
To allow local script execution, open PowerShell as an Administrator and run:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

## 🚀 Getting Started

1. **Clone the repository:**
   ```powershell
   git clone https://github.com/your-username/your-repo-name.git
   cd your-repo-name
   ```

2. **Unblock downloaded scripts:**
   ```powershell
   Get-ChildItem -Path .\ -Recurse -Filter *.ps1 | Unblock-File
   ```

3. **Run a script:**
   ```powershell
   .\ActiveDirectory\Get-ADUserAudit.ps1
   ```

---

## 🤖 AI Co-Authoring & Safety Disclaimer

> [!IMPORTANT]  
> Scripts in this repository are developed in collaboration with AI assistants/agents. 

* **Test First:** Always review and test scripts in a test lab or sandbox environment before running them against production systems or Active Directory domain controllers.
* **Safety First (`-WhatIf`):** Modification scripts support standard PowerShell risk mitigation parameters (`-WhatIf` and `-Confirm`).

```powershell
# Preview changes safely before executing:
.\Clean-WinDiskSpace.ps1 -WhatIf
```

---

## 🤝 Contributing

Feel free to open an issue or submit a pull request if you have ideas for new PowerShell lifehacks, sysadmin automation scripts, or AI-generated improvements!