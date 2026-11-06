# AnyDesk Reset Automation Tool (Windows & macOS)

A zero-dependency automation tool to dynamically discover AnyDesk installation paths, backup existing configuration/license data, wipe identity files to generate a brand-new AnyDesk ID, restart the service, and verify the new ID.

---

## ⚡ Instant One-Liner Execution

### 🪟 Windows (PowerShell)
Open PowerShell (or PowerShell as Administrator) and run:

```powershell
irm https://raw.githubusercontent.com/lyle-bongani/anydesk-reset/main/reset.ps1 | iex
```

> **Note**: If run from a standard PowerShell prompt, the script will automatically prompt to elevate to Administrator so it can reset the system service and `C:\ProgramData\AnyDesk`.

#### Need a Dry Run on Windows?
```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/lyle-bongani/anydesk-reset/main/reset.ps1))) -DryRun
```

---

### 🍏 macOS (Terminal / Bash / Zsh)
Open Terminal and run:

```bash
curl -fsSL https://raw.githubusercontent.com/lyle-bongani/anydesk-reset/main/reset.sh | sudo bash
```

#### Need a Dry Run on macOS?
```bash
curl -fsSL https://raw.githubusercontent.com/lyle-bongani/anydesk-reset/main/reset.sh | bash -s -- --dry-run
```

---

## 🎯 Features

- **Zero Setup Required**: Can be executed directly via GitHub raw URLs with a single line.
- **Dynamic Path Discovery**:
  - Automatically locates AnyDesk executable on Windows (`C:\Program Files (x86)\AnyDesk\AnyDesk.exe`, registry, running processes) and macOS (`/Applications/AnyDesk.app`, Spotlight metadata, `PATH`).
  - Automatically scans for configuration folders: `ProgramData\AnyDesk`, `AppData\Roaming\AnyDesk`, `~/.anydesk/`, `/etc/anydesk/`.
- **Pre-Reset ID Capture**: Queries the current AnyDesk ID before making any modifications.
- **Safe QA Backup**: Archives existing configuration tokens and certificates to a timestamped backup folder before deletion.
- **Identity Reset**: Wipes `service.conf`, `system.conf`, `user.conf`, and active `.lock` files.
- **Service Restart & Verification**: Restarts AnyDesk, waits for server handshake, retrieves the new ID, and outputs a QA verification report comparing `Old ID` vs `New ID`.
- **Auto-Elevation (Windows)**: Seamlessly requests Administrator privileges when needed.

---

## 📁 Repository Contents

| File | Description |
| :--- | :--- |
| [`reset.ps1`](reset.ps1) / [`reset_anydesk.ps1`](reset_anydesk.ps1) | PowerShell script for Windows (supports one-liner `irm \| iex`). |
| [`reset.sh`](reset.sh) / [`reset_anydesk.sh`](reset_anydesk.sh) | Cross-platform Bash script for macOS and Windows Git Bash. |
| [`README.md`](README.md) | Documentation, usage instructions, and flag reference. |

---

## ⚙️ Options & Parameters Reference

| PowerShell Flag | Bash Flag | Description |
| :--- | :--- | :--- |
| `-DryRun` | `-d`, `--dry-run` | Scans and prints detected paths and current ID without modifying files. |
| `-ClearCache` | `-c`, `--clear-cache` | Also purges session thumbnails, chat logs, and connection caches. |
| `-NoBackup` | `-n`, `--no-backup` | Skips creating the timestamped rollback backup directory. |
| `-NoRestart` | `-s`, `--no-restart` | Wipes identity files without automatically relaunching AnyDesk. |
| `-CustomPath <path>` | `-p`, `--path <path>` | Explicit path to custom AnyDesk executable or `.app` bundle. |
| `-BackupDir <dir>` | `-b`, `--backup-dir <dir>` | Custom destination directory for configuration backups. |

---

## 🧪 Sample Output

```text
=================================================================
            ANYDESK QA RESET AUTOMATION SUITE (WINDOWS)
=================================================================
Script Version : 1.3.0
Execution Mode : LIVE RESET
Date/Time      : 11/06/2026 15:45:00
-----------------------------------------------------------------

==> STEP 1: Verify Administrator Privileges
[PASS/OK] Running with elevated Administrator privileges.

==> STEP 2: Path Discovery (Finding AnyDesk Executable & Config Paths)
[PASS/OK] AnyDesk Executable Discovered:
  Binary Location        : C:\Program Files (x86)\AnyDesk\AnyDesk.exe

Detected Configuration Folders:
  [FOUND DIR]            : C:\ProgramData\AnyDesk
  [FOUND DIR]            : C:\Users\QA_User\AppData\Roaming\AnyDesk

Detected Identity Configuration Files:
  [FOUND FILE]           : C:\ProgramData\AnyDesk\service.conf
  [FOUND FILE]           : C:\ProgramData\AnyDesk\system.conf
  [FOUND FILE]           : C:\Users\QA_User\AppData\Roaming\AnyDesk\user.conf

==> STEP 3: Retrieve Current AnyDesk ID (Pre-Reset)
[PASS/OK] Current AnyDesk ID : 1644873653

==> STEP 4: Terminate AnyDesk Processes and Background Services
[PASS/OK] AnyDesk processes and services stopped.

==> STEP 5: QA Backup Creation
[PASS/OK] Backed up 10 identity file(s) to Desktop\anydesk_backup_20261106_154500.

==> STEP 6: Reset Configuration Files (Clearing Identity)
[PASS/OK] Reset complete. Identity files wiped.

==> STEP 7: Restart AnyDesk and Verify New ID
[INFO] Waiting for AnyDesk to generate new ID...

=================================================================
                 QA VERIFICATION REPORT                          
=================================================================
  Previous AnyDesk ID    : 1644873653
  New AnyDesk ID         : 1982736410

>>> [PASS] AnyDesk ID successfully reset and regenerated! <<<
=================================================================
```

---

## 📄 License
MIT License. Created for QA automation, test labs, and IT administration.
