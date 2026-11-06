<#
.SYNOPSIS
    AnyDesk QA Reset Automation Script for Windows (PowerShell)
.DESCRIPTION
    Dynamically discovers AnyDesk executable and configuration paths,
    captures current AnyDesk ID, stops background services, archives
    existing configs to a timestamped backup folder, wipes identity
    files (service.conf, system.conf, user.conf), and restarts AnyDesk
    to verify new ID generation.
.PARAMETER DryRun
    Scans and reports detected paths and current ID without modifying files or services.
.PARAMETER NoBackup
    Skips creating the timestamped QA backup archive.
.PARAMETER NoRestart
    Does not automatically start AnyDesk service/application after file deletion.
.PARAMETER ClearCache
    Also cleans cache, session thumbnails, and chat logs.
.PARAMETER CustomPath
    Manually specifies the path to AnyDesk.exe or installation directory.
.PARAMETER BackupDir
    Specifies a custom backup directory.
.EXAMPLE
    # One-liner execution in PowerShell:
    irm https://raw.githubusercontent.com/lyle-bongani/anydesk-reset/main/reset.ps1 | iex
.EXAMPLE
    .\reset_anydesk.ps1 -DryRun
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$NoBackup,
    [switch]$NoRestart,
    [switch]$ClearCache,
    [string]$CustomPath,
    [string]$BackupDir
)

$ErrorActionPreference = "Stop"
$ScriptVersion = "1.3.0"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# --- Output Formatting Helpers ---
function Write-Header {
    param([string]$Text)
    Write-Host "`n=================================================================" -ForegroundColor Magenta
    Write-Host "            $Text" -ForegroundColor Magenta
    Write-Host "=================================================================" -ForegroundColor Magenta
}

function Write-Step {
    param([string]$Text)
    Write-Host "`n==> $Text" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Text)
    Write-Host "[PASS/OK] $Text" -ForegroundColor Green
}

function Write-InfoMsg {
    param([string]$Text)
    Write-Host "[INFO] $Text" -ForegroundColor Gray
}

function Write-WarnMsg {
    param([string]$Text)
    Write-Host "[WARN] $Text" -ForegroundColor Yellow
}

function Write-ErrMsg {
    param([string]$Text)
    Write-Host "[ERROR] $Text" -ForegroundColor Red
}

function Write-ReportPath {
    param([string]$Label, [string]$PathVal)
    Write-Host ("  {0,-22} : {1}" -f $Label, $PathVal)
}

Write-Header "ANYDESK QA RESET AUTOMATION SUITE (WINDOWS)"
Write-Host "Script Version : $ScriptVersion"
Write-Host "Execution Mode : $(if ($DryRun) { 'DRY RUN (Read Only)' } else { 'LIVE RESET' })" -ForegroundColor $(if ($DryRun) { 'Yellow' } else { 'Green' })
Write-Host "Date/Time      : $(Get-Date)"
Write-Host "-----------------------------------------------------------------"

# ==============================================================================
# STEP 1: PRIVILEGE CHECK & AUTO-ELEVATION
# ==============================================================================
Write-Step "STEP 1: Verify Administrator Privileges"

$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($IsAdmin) {
    Write-Ok "Running with elevated Administrator privileges."
} else {
    Write-WarnMsg "Script is running WITHOUT Administrator privileges."
    Write-WarnMsg "Stopping the AnyDesk Windows service or modifying %ProgramData%\AnyDesk requires elevation."
    
    if (-not $DryRun) {
        Write-Host "`n[ELEVATION] Attempting to relaunch with Administrator privileges..." -ForegroundColor Cyan
        try {
            if ($PSCommandPath -and (Test-Path $PSCommandPath)) {
                Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
            } else {
                $remoteCmd = "& { [scriptblock]::Create((Invoke-RestMethod 'https://raw.githubusercontent.com/lyle-bongani/anydesk-reset/main/reset.ps1')) }"
                Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"$remoteCmd`""
            }
            Write-Ok "Elevated PowerShell window requested. Please accept the Windows UAC prompt."
            return
        } catch {
            Write-WarnMsg "Auto-elevation failed: $($_.Exception.Message)"
            Write-WarnMsg "Please right-click PowerShell -> 'Run as Administrator', then run the command again."
        }
    }
}

# ==============================================================================
# STEP 2: PATH DISCOVERY (EXECUTABLE & CONFIGS)
# ==============================================================================
Write-Step "STEP 2: Path Discovery (Finding AnyDesk Executable & Config Paths)"

$AnyDeskExe = $null

# 2A. Check custom path
if ($CustomPath) {
    if (Test-Path -Path $CustomPath -PathType Leaf) {
        $AnyDeskExe = (Resolve-Path $CustomPath).Path
    } elseif (Test-Path -Path (Join-Path $CustomPath "AnyDesk.exe") -PathType Leaf) {
        $AnyDeskExe = (Resolve-Path (Join-Path $CustomPath "AnyDesk.exe")).Path
    } else {
        Write-ErrMsg "Custom path specified does not exist: $CustomPath"
        exit 1
    }
}

# 2B. Check standard install paths
if (-not $AnyDeskExe) {
    $Candidates = @(
        "$env:ProgramFiles (x86)\AnyDesk\AnyDesk.exe",
        "$env:ProgramFiles\AnyDesk\AnyDesk.exe",
        "$env:LOCALAPPDATA\Programs\AnyDesk\AnyDesk.exe",
        "C:\Program Files (x86)\AnyDesk\AnyDesk.exe",
        "C:\Program Files\AnyDesk\AnyDesk.exe"
    )

    foreach ($Cand in $Candidates) {
        if (Test-Path -Path $Cand -PathType Leaf) {
            $AnyDeskExe = $Cand
            break
        }
    }
}

# 2C. Check Registry
if (-not $AnyDeskExe) {
    try {
        $RegVal = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\AnyDesk.exe" -Name "(Default)" -ErrorAction SilentlyContinue
        if ($RegVal.'(Default)' -and (Test-Path $RegVal.'(Default)')) {
            $AnyDeskExe = $RegVal.'(Default)'
        }
    } catch {}
}

# 2D. Check Running Process
if (-not $AnyDeskExe) {
    $Proc = Get-Process AnyDesk -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($Proc -and $Proc.Path -and (Test-Path $Proc.Path)) {
        $AnyDeskExe = $Proc.Path
    }
}

if ($AnyDeskExe) {
    Write-Ok "AnyDesk Executable Discovered:"
    Write-ReportPath "Binary Location" $AnyDeskExe
} else {
    Write-WarnMsg "AnyDesk Executable could not be located in standard paths."
    Write-WarnMsg "Configuration reset can still proceed via discovered config folders."
}

# 2E. Discover Configuration Folders
$CandidateConfigDirs = @(
    "$env:ProgramData\AnyDesk",
    "$env:APPDATA\AnyDesk",
    "$env:LOCALAPPDATA\AnyDesk",
    "C:\ProgramData\AnyDesk"
)

$FoundDirs = @()
foreach ($Dir in $CandidateConfigDirs) {
    if ((Test-Path -Path $Dir -PathType Container) -and ($FoundDirs -notcontains (Resolve-Path $Dir).Path)) {
        $FoundDirs += (Resolve-Path $Dir).Path
    }
}

Write-Host "`nDetected Configuration Folders:"
if ($FoundDirs.Count -eq 0) {
    Write-WarnMsg "No existing AnyDesk configuration directories found."
} else {
    foreach ($Dir in $FoundDirs) {
        Write-ReportPath "[FOUND DIR]" $Dir
    }
}

# 2F. Locate Target Identity Files
$TargetFiles = @()
$FileNames = @("service.conf", "system.conf", "user.conf", "service.conf.lock", "system.conf.lock", "user.conf.lock")
foreach ($Dir in $FoundDirs) {
    foreach ($fn in $FileNames) {
        $FullFile = Join-Path $Dir $fn
        if (Test-Path -Path $FullFile -PathType Leaf) {
            $TargetFiles += $FullFile
        }
    }
}

Write-Host "`nDetected Identity Configuration Files:"
if ($TargetFiles.Count -eq 0) {
    Write-WarnMsg "No identity files found (service.conf / system.conf / user.conf)."
} else {
    foreach ($F in $TargetFiles) {
        Write-ReportPath "[FOUND FILE]" $F
    }
}

# ==============================================================================
# STEP 3: RETRIEVE CURRENT ANYDESK ID
# ==============================================================================
Write-Step "STEP 3: Retrieve Current AnyDesk ID (Pre-Reset)"

function Get-AnyDeskId {
    param([string[]]$Files, [string]$ExePath)
    
    # Method 1: Fast & safe file parse
    foreach ($file in $Files) {
        if ($file -match "system\.conf$" -or $file -match "service\.conf$") {
            if (Test-Path $file) {
                $match = Select-String -Path $file -Pattern "^ad\.anynet\.id=(\d+)" | Select-Object -First 1
                if ($match -and $match.Matches.Groups[1].Value) {
                    return $match.Matches.Groups[1].Value
                }
            }
        }
    }

    # Method 2: CLI fallback
    if ($ExePath -and (Test-Path $ExePath)) {
        try {
            $raw = cmd.exe /c "`"$ExePath`" --get-id" 2>$null
            if ($raw) {
                $trimmed = $raw.Trim()
                if ($trimmed -match "^\d+$") {
                    return $trimmed
                }
            }
        } catch {}
    }

    return $null
}

$OldId = Get-AnyDeskId -Files $TargetFiles -ExePath $AnyDeskExe
if ($OldId) {
    Write-Ok "Current AnyDesk ID : $OldId"
} else {
    Write-WarnMsg "Current AnyDesk ID could not be queried."
}

# If Dry-Run, exit safely here
if ($DryRun) {
    Write-Host "`n-----------------------------------------------------------------" -ForegroundColor Yellow
    Write-Host "[DRY RUN SUMMARY] No changes were made." -ForegroundColor Yellow
    Write-Host "Files that would be backed up and removed:"
    foreach ($f in $TargetFiles) {
        Write-Host "  - $f"
    }
    if ($ClearCache) {
        Write-Host "Cache directories that would be purged:"
        foreach ($d in $FoundDirs) {
            Write-Host "  - $(Join-Path $d 'cache')"
            Write-Host "  - $(Join-Path $d 'thumbnails')"
            Write-Host "  - $(Join-Path $d 'chat')"
        }
    }
    Write-Host "-----------------------------------------------------------------`n" -ForegroundColor Yellow
    return
}

# ==============================================================================
# STEP 4: TERMINATE RUNNING PROCESSES AND SERVICES
# ==============================================================================
Write-Step "STEP 4: Terminate AnyDesk Processes and Background Services"

Write-InfoMsg "Stopping AnyDesk Windows service..."
try {
    Stop-Service -Name "AnyDesk" -Force -ErrorAction SilentlyContinue
} catch {}

Write-InfoMsg "Forcefully terminating AnyDesk.exe processes..."
try {
    taskkill.exe /F /IM "AnyDesk.exe" /T 2>$null | Out-Null
    taskkill.exe /F /IM "AnyDeskService.exe" /T 2>$null | Out-Null
} catch {}
Start-Sleep -Seconds 1
Write-Ok "AnyDesk processes and services stopped."

# ==============================================================================
# STEP 5: QA BACKUP CREATION
# ==============================================================================
Write-Step "STEP 5: QA Backup Creation"

if (-not $NoBackup) {
    if (-not $BackupDir) {
        $DesktopPath = [Environment]::GetFolderPath("Desktop")
        if (Test-Path $DesktopPath) {
            $BackupDir = Join-Path $DesktopPath "anydesk_backup_$Timestamp"
        } else {
            $BackupDir = Join-Path (Get-Location) "anydesk_backup_$Timestamp"
        }
    }
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-InfoMsg "Backup directory created at: $BackupDir"

    # Write metadata
    $MetaContent = @"
AnyDesk QA Reset Backup
Timestamp: $(Get-Date)
Original_ID: $(if ($OldId) { $OldId } else { 'N/A' })
OS: Windows
Script_Version: $ScriptVersion
"@
    Set-Content -Path (Join-Path $BackupDir "qa_reset_meta.txt") -Value $MetaContent

    $BackedUpCount = 0
    foreach ($File in $TargetFiles) {
        if (Test-Path $File) {
            $SafeName = ($File -replace "[:\\]", "_").TrimStart("_")
            Copy-Item -Path $File -Destination (Join-Path $BackupDir $SafeName) -Force
            $BackedUpCount++
        }
    }
    Write-Ok "Backed up $BackedUpCount identity file(s) successfully."
} else {
    Write-WarnMsg "Backup skipped by user (-NoBackup passed)."
}

# ==============================================================================
# STEP 6: RESET CONFIGURATION FILES (WIPE IDENTITY)
# ==============================================================================
Write-Step "STEP 6: Reset Configuration Files (Clearing Identity)"

$RemovedCount = 0
foreach ($File in $TargetFiles) {
    if (Test-Path $File) {
        try {
            Remove-Item -Path $File -Force -ErrorAction Stop
            Write-InfoMsg "Removed identity file: $File"
            $RemovedCount++
        } catch {
            Write-WarnMsg "Failed to delete: $File ($($_.Exception.Message))"
        }
    }
}

if ($ClearCache) {
    Write-InfoMsg "Purging AnyDesk cache, thumbnails, and chat data..."
    foreach ($Dir in $FoundDirs) {
        foreach ($sub in @("cache", "thumbnails", "chat", "global_cache")) {
            $SubPath = Join-Path $Dir $sub
            if (Test-Path $SubPath) {
                Remove-Item -Path $SubPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-InfoMsg "Purged folder: $SubPath"
            }
        }
    }
}

Write-Ok "Reset complete. $RemovedCount identity file(s) removed."

# ==============================================================================
# STEP 7: RESTART ANYDESK & VERIFY NEW ID GENERATION
# ==============================================================================
Write-Step "STEP 7: Restart AnyDesk and Verify New ID"

$NewId = $null
if (-not $NoRestart) {
    Write-InfoMsg "Starting Windows AnyDesk service and application..."
    try {
        Start-Service -Name "AnyDesk" -ErrorAction SilentlyContinue
    } catch {}

    if ($AnyDeskExe -and (Test-Path $AnyDeskExe)) {
        Start-Process -FilePath $AnyDeskExe -ErrorAction SilentlyContinue
    }

    Write-InfoMsg "Waiting for AnyDesk to generate new ID (probing up to 10s)..."
    for ($i = 1; $i -le 10; $i++) {
        Start-Sleep -Seconds 1
        $NewId = Get-AnyDeskId -Files $TargetFiles -ExePath $AnyDeskExe
        if ($NewId -and ($NewId -ne $OldId)) {
            break
        }
    }

    # Verification Report
    Write-Host "`n=================================================================" -ForegroundColor Magenta
    Write-Host "                 QA VERIFICATION REPORT                          " -ForegroundColor Magenta
    Write-Host "=================================================================" -ForegroundColor Magenta
    Write-ReportPath "Previous AnyDesk ID" $(if ($OldId) { $OldId } else { "N/A" })
    Write-ReportPath "New AnyDesk ID"      $(if ($NewId) { $NewId } else { "Generating..." })

    if ($NewId -and ($NewId -ne $OldId)) {
        Write-Host "`n>>> [PASS] AnyDesk ID successfully reset and regenerated! <<<" -ForegroundColor Green
    } elseif ($NewId -and ($NewId -eq $OldId)) {
        Write-Host "`n>>> [WARN] ID matches previous ID. AnyDesk service may need a reboot <<<" -ForegroundColor Yellow
    } else {
        Write-Host "`n>>> [INFO] AnyDesk is connecting to server. The new ID will populate shortly in the UI. <<<" -ForegroundColor Cyan
    }
    Write-Host "=================================================================`n" -ForegroundColor Magenta
} else {
    Write-InfoMsg "Automatic restart skipped (-NoRestart passed)."
    Write-Ok "Identity reset is staged. Launch AnyDesk manually when ready."
}
