#!/usr/bin/env bash
# ==============================================================================
# AnyDesk QA Reset Tool (macOS & Windows)
# ==============================================================================
# Description : Cross-platform QA automation script to discover AnyDesk paths,
#               backup existing configs, wipe identity files to generate a brand
#               new AnyDesk ID, and verify the new ID generation.
# Supported OS: macOS (Darwin) & Windows (Git Bash / MSYS2 / WSL / Cygwin)
# ==============================================================================

set -euo pipefail

SCRIPT_VERSION="1.2.0"
TIMESTAMP="$(date +'%Y%m%d_%H%M%S')"

# --- Color Formatting ---
if [[ -t 1 ]]; then
    C_RESET="\033[0m"
    C_BOLD="\033[1m"
    C_RED="\033[31m"
    C_GREEN="\033[32m"
    C_YELLOW="\033[33m"
    C_BLUE="\033[34m"
    C_MAGENTA="\033[35m"
    C_CYAN="\033[36m"
else
    C_RESET=""
    C_BOLD=""
    C_RED=""
    C_GREEN=""
    C_YELLOW=""
    C_BLUE=""
    C_MAGENTA=""
    C_CYAN=""
fi

# --- Logging Helpers ---
log_info()    { echo -e "${C_CYAN}[INFO]${C_RESET} $*"; }
log_step()    { echo -e "\n${C_BOLD}${C_BLUE}==>${C_RESET} ${C_BOLD}$*${C_RESET}"; }
log_ok()      { echo -e "${C_GREEN}[PASS/OK]${C_RESET} $*"; }
log_warn()    { echo -e "${C_YELLOW}[WARN]${C_RESET} $*"; }
log_error()   { echo -e "${C_RED}[ERROR]${C_RESET} $*" >&2; }
log_path()    { printf "  %-20s : %s\n" "$1" "$2"; }

# --- Script Flags & Defaults ---
DRY_RUN=false
DO_BACKUP=true
DO_RESTART=true
CLEAR_CACHE=false
CUSTOM_EXE=""
CUSTOM_BACKUP_DIR=""
OLD_ID=""
NEW_ID=""

usage() {
    cat <<EOF
${C_BOLD}AnyDesk QA Reset Script v${SCRIPT_VERSION}${C_RESET}

Usage:
  ./reset_anydesk.sh [OPTIONS]

Options:
  -d, --dry-run          Scan paths and report detected settings without modifying anything.
  -n, --no-backup        Skip creating a timestamped backup of AnyDesk configurations.
  -s, --no-restart       Do not restart AnyDesk after resetting configuration files.
  -c, --clear-cache      Also clear AnyDesk session thumbnails, chat logs, and cache directories.
  -p, --path <path>      Explicitly provide the path to the AnyDesk executable or .app bundle.
  -b, --backup-dir <dir> Specify a custom directory to store configuration backups.
  -h, --help             Show this help message and exit.

Examples:
  # Normal QA Reset (Auto-detects paths, backs up, resets ID, restarts, verifies new ID)
  ./reset_anydesk.sh

  # Dry Run: Find and inspect paths and current AnyDesk ID without changing anything
  ./reset_anydesk.sh --dry-run

  # Full Reset including cache and chat logs with no automatic restart
  ./reset_anydesk.sh --clear-cache --no-restart
EOF
}

# --- Parse Arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -n|--no-backup)
            DO_BACKUP=false
            shift
            ;;
        -s|--no-restart)
            DO_RESTART=false
            shift
            ;;
        -c|--clear-cache)
            CLEAR_CACHE=true
            shift
            ;;
        -p|--path)
            CUSTOM_EXE="$2"
            shift 2
            ;;
        -b|--backup-dir)
            CUSTOM_BACKUP_DIR="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# --- Banner ---
echo -e "${C_BOLD}${C_MAGENTA}=================================================================${C_RESET}"
echo -e "${C_BOLD}${C_MAGENTA}            ANYDESK QA RESET AUTOMATION SUITE                   ${C_RESET}"
echo -e "${C_BOLD}${C_MAGENTA}=================================================================${C_RESET}"
echo -e "Script Version : ${SCRIPT_VERSION}"
echo -e "Execution Mode : $([[ "$DRY_RUN" == true ]] && echo "${C_YELLOW}DRY RUN (Read Only)${C_RESET}" || echo "${C_GREEN}LIVE RESET${C_RESET}")"
echo -e "Date/Time      : $(date)"
echo -e "-----------------------------------------------------------------"

# --- Helper: Convert Path to POSIX (for MSYS/Git Bash/Cygwin) ---
to_posix() {
    local input_path="$1"
    if [[ -z "$input_path" ]]; then
        echo ""
        return
    fi
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -u "$input_path" 2>/dev/null || echo "$input_path"
    else
        # Fallback manual conversion C:\Foo\Bar -> /c/Foo/Bar
        echo "$input_path" | sed -E 's|^([a-zA-Z]):|/\L\1|; s|\\|/|g'
    fi
}

# --- Helper: Convert Path to Windows (for cmd.exe execution) ---
to_windows() {
    local input_path="$1"
    if [[ -z "$input_path" ]]; then
        echo ""
        return
    fi
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -w "$input_path" 2>/dev/null || echo "$input_path"
    else
        # Fallback manual conversion /c/Foo/Bar -> C:\Foo\Bar
        echo "$input_path" | sed -E 's|^/([a-zA-Z])/|\U\1:\\|; s|/|\\|g'
    fi
}

# ==============================================================================
# STEP 1: DETECT OPERATING SYSTEM
# ==============================================================================
log_step "STEP 1: Detect Operating System Environment"

DETECTED_OS="unknown"
UNAME_OUT="$(uname -s 2>/dev/null || echo "Unknown")"

case "${UNAME_OUT}" in
    Darwin*)
        DETECTED_OS="macos"
        ;;
    CYGWIN*|MINGW*|MSYS*)
        DETECTED_OS="windows"
        ;;
    Linux*)
        if grep -qi "microsoft" /proc/version 2>/dev/null; then
            DETECTED_OS="windows_wsl"
        else
            DETECTED_OS="linux"
        fi
        ;;
    *)
        if [[ -n "${WINDIR:-}" || -n "${COMSPEC:-}" ]]; then
            DETECTED_OS="windows"
        fi
        ;;
esac

log_info "Detected OS: ${C_BOLD}${DETECTED_OS}${C_RESET} (${UNAME_OUT})"

if [[ "$DETECTED_OS" != "macos" && "$DETECTED_OS" != "windows" && "$DETECTED_OS" != "windows_wsl" ]]; then
    log_warn "Unrecognized OS '${DETECTED_OS}'. Attempting standard UNIX file paths..."
fi

# ==============================================================================
# STEP 2: PATH DISCOVERY (EXECUTABLE & CONFIGS)
# ==============================================================================
log_step "STEP 2: Path Discovery (Finding AnyDesk Executable & Config Paths)"

ANYDESK_BIN=""
CONFIG_PATHS=()
CANDIDATE_CONFIG_DIRS=()

# --- 2A. Discover Executable ---
if [[ -n "$CUSTOM_EXE" ]]; then
    POS_CUSTOM="$(to_posix "$CUSTOM_EXE")"
    if [[ -f "$POS_CUSTOM" || -d "$POS_CUSTOM" ]]; then
        if [[ "$POS_CUSTOM" == *".app" ]]; then
            ANYDESK_BIN="${POS_CUSTOM}/Contents/MacOS/AnyDesk"
        else
            ANYDESK_BIN="$POS_CUSTOM"
        fi
        log_info "Using custom AnyDesk path provided: ${ANYDESK_BIN}"
    else
        log_error "Custom path does not exist: $CUSTOM_EXE"
        exit 1
    fi
fi

if [[ -z "$ANYDESK_BIN" ]]; then
    if [[ "$DETECTED_OS" == "macos" ]]; then
        CANDIDATES=(
            "/Applications/AnyDesk.app/Contents/MacOS/AnyDesk"
            "$HOME/Applications/AnyDesk.app/Contents/MacOS/AnyDesk"
        )
        for cand in "${CANDIDATES[@]}"; do
            if [[ -x "$cand" ]]; then
                ANYDESK_BIN="$cand"
                break
            fi
        done

        # Spotlight fallback
        if [[ -z "$ANYDESK_BIN" ]] && command -v mdfind >/dev/null 2>&1; then
            SPOT_APP="$(mdfind "kMDItemCFBundleIdentifier == 'com.philandro.anydesk'" 2>/dev/null | head -n 1 || true)"
            if [[ -n "$SPOT_APP" && -x "${SPOT_APP}/Contents/MacOS/AnyDesk" ]]; then
                ANYDESK_BIN="${SPOT_APP}/Contents/MacOS/AnyDesk"
            fi
        fi

        # PATH fallback
        if [[ -z "$ANYDESK_BIN" ]] && command -v anydesk >/dev/null 2>&1; then
            ANYDESK_BIN="$(command -v anydesk)"
        fi

    elif [[ "$DETECTED_OS" == "windows" || "$DETECTED_OS" == "windows_wsl" ]]; then
        # Candidate directories in Windows
        PF_X86_WIN="${PROGRAMFILES:-C:\Program Files (x86)}"
        PF_X86_POSIX="$(to_posix "${PROGRAMFILES:-C:\Program Files (x86)}")"
        PF_64_POSIX="$(to_posix "${ProgramW6432:-C:\Program Files}")"
        LOCAL_APP_POSIX="$(to_posix "${LOCALAPPDATA:-$HOME/AppData/Local}")"

        CANDIDATES=(
            "/c/Program Files (x86)/AnyDesk/AnyDesk.exe"
            "/c/Program Files/AnyDesk/AnyDesk.exe"
            "${PF_X86_POSIX}/AnyDesk/AnyDesk.exe"
            "${PF_64_POSIX}/AnyDesk/AnyDesk.exe"
            "${LOCAL_APP_POSIX}/Programs/AnyDesk/AnyDesk.exe"
        )

        for cand in "${CANDIDATES[@]}"; do
            if [[ -f "$cand" ]]; then
                ANYDESK_BIN="$cand"
                break
            fi
        done

        # Windows where.exe fallback
        if [[ -z "$ANYDESK_BIN" ]] && command -v where.exe >/dev/null 2>&1; then
            WHERE_PATH="$(where.exe AnyDesk.exe 2>/dev/null | head -n 1 || true)"
            if [[ -n "$WHERE_PATH" ]]; then
                ANYDESK_BIN="$(to_posix "$WHERE_PATH")"
            fi
        fi

        # Registry Query fallback
        if [[ -z "$ANYDESK_BIN" ]] && command -v reg.exe >/dev/null 2>&1; then
            REG_PATH="$(reg.exe query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\AnyDesk.exe" /ve 2>/dev/null | grep -i "REG_SZ" | awk -F "REG_SZ" '{print $2}' | sed -e 's/^[ \t]*//' || true)"
            if [[ -n "$REG_PATH" && -f "$(to_posix "$REG_PATH")" ]]; then
                ANYDESK_BIN="$(to_posix "$REG_PATH")"
            fi
        fi
    fi
fi

if [[ -n "$ANYDESK_BIN" ]]; then
    log_ok "AnyDesk Executable Discovered:"
    log_path "Binary Location" "${C_BOLD}${ANYDESK_BIN}${C_RESET}"
else
    log_warn "AnyDesk Executable could not be located in standard paths."
    log_warn "Config reset can still proceed via discovered config paths."
fi

# --- 2B. Discover Config Folders & Files ---
if [[ "$DETECTED_OS" == "macos" ]]; then
    CANDIDATE_CONFIG_DIRS=(
        "$HOME/.anydesk"
        "$HOME/Library/Application Support/AnyDesk"
        "/Library/Application Support/AnyDesk"
        "/etc/anydesk"
        "/Library/AnyDesk"
    )
elif [[ "$DETECTED_OS" == "windows" || "$DETECTED_OS" == "windows_wsl" ]]; then
    PROG_DATA_POSIX="$(to_posix "${PROGRAMDATA:-C:\ProgramData}")"
    ROAMING_POSIX="$(to_posix "${APPDATA:-$HOME/AppData/Roaming}")"
    LOCAL_POSIX="$(to_posix "${LOCALAPPDATA:-$HOME/AppData/Local}")"

    CANDIDATE_CONFIG_DIRS=(
        "/c/ProgramData/AnyDesk"
        "${PROG_DATA_POSIX}/AnyDesk"
        "/c/Users/${USER:-$USERNAME}/AppData/Roaming/AnyDesk"
        "${ROAMING_POSIX}/AnyDesk"
        "${LOCAL_POSIX}/AnyDesk"
    )
fi

# De-duplicate candidate dirs and check existence
FOUND_DIRS=()
for d in "${CANDIDATE_CONFIG_DIRS[@]}"; do
    if [[ -d "$d" ]]; then
        # Check if already added
        already_added=false
        for added in "${FOUND_DIRS[@]}"; do
            if [[ "$added" == "$d" ]]; then
                already_added=true
                break
            fi
        done
        if [[ "$already_added" == false ]]; then
            FOUND_DIRS+=("$d")
        fi
    fi
done

echo -e "\nDetected Configuration Folders:"
if [[ ${#FOUND_DIRS[@]} -eq 0 ]]; then
    log_warn "No existing AnyDesk configuration directories found."
else
    for d in "${FOUND_DIRS[@]}"; do
        log_path "[FOUND DIR]" "$d"
    done
fi

# Collect critical identity files from discovered directories
TARGET_FILES=()
for dir in "${FOUND_DIRS[@]}"; do
    for f in "service.conf" "system.conf" "user.conf" "service.conf.lock" "system.conf.lock" "user.conf.lock"; do
        if [[ -f "${dir}/${f}" ]]; then
            TARGET_FILES+=("${dir}/${f}")
        fi
    done
done

echo -e "\nDetected Identity Configuration Files:"
if [[ ${#TARGET_FILES[@]} -eq 0 ]]; then
    log_warn "No identity files found (service.conf / system.conf / user.conf)."
else
    for f in "${TARGET_FILES[@]}"; do
        log_path "[FOUND FILE]" "$f"
    done
fi

# ==============================================================================
# STEP 3: RETRIEVE CURRENT ANYDESK ID
# ==============================================================================
log_step "STEP 3: Retrieve Current AnyDesk ID (Pre-Reset)"

get_current_id() {
    local retrieved_id=""

    # Attempt 1: Fast & reliable offline parse from existing system.conf or service.conf
    # This avoids GUI subsystem blocking or window popping during automated QA scans
    for f in "${TARGET_FILES[@]}"; do
        if [[ "$f" == *"system.conf" || "$f" == *"service.conf" ]]; then
            if [[ -f "$f" ]]; then
                local val
                val="$(grep -iE "^ad\.anynet\.id=" "$f" 2>/dev/null | head -n 1 | cut -d'=' -f2 | tr -d '\r\n ' || true)"
                if [[ -n "$val" ]]; then
                    retrieved_id="$val"
                    break
                fi
            fi
        fi
    done

    # Attempt 2: If config file parse returned empty, query AnyDesk executable with --get-id
    if [[ -z "$retrieved_id" && -n "$ANYDESK_BIN" ]]; then
        if [[ "$DETECTED_OS" == "macos" ]]; then
            retrieved_id="$("${ANYDESK_BIN}" --get-id 2>/dev/null | tr -d '\r\n ' || true)"
        elif [[ "$DETECTED_OS" == "windows" || "$DETECTED_OS" == "windows_wsl" ]]; then
            local win_bin
            win_bin="$(to_windows "$ANYDESK_BIN")"
            # Use cmd.exe //c with proper escaping to avoid MSYS path mangling
            retrieved_id="$(cmd.exe //c "\"$win_bin\" --get-id" 2>/dev/null | tr -d '\r\n ' || true)"
        fi
    fi

    echo "$retrieved_id"
}

OLD_ID="$(get_current_id)"
if [[ -n "$OLD_ID" ]]; then
    log_ok "Current AnyDesk ID : ${C_BOLD}${C_GREEN}${OLD_ID}${C_RESET}"
else
    log_warn "Current AnyDesk ID could not be queried (AnyDesk may not have established an ID yet)."
fi

# If Dry-Run, exit here cleanly after printing diagnostics
if [[ "$DRY_RUN" == true ]]; then
    echo -e "\n${C_BOLD}${C_YELLOW}-----------------------------------------------------------------${C_RESET}"
    echo -e "${C_BOLD}${C_YELLOW}[DRY RUN SUMMARY] No changes were made.${C_RESET}"
    echo -e "Files that would be backed up and removed:"
    for f in "${TARGET_FILES[@]}"; do
        echo -e "  - $f"
    done
    if [[ "$CLEAR_CACHE" == true ]]; then
        echo -e "Cache directories that would be purged:"
        for d in "${FOUND_DIRS[@]}"; do
            echo -e "  - ${d}/cache (if present)"
            echo -e "  - ${d}/thumbnails (if present)"
            echo -e "  - ${d}/chat (if present)"
        done
    fi
    echo -e "${C_BOLD}${C_YELLOW}-----------------------------------------------------------------${C_RESET}\n"
    exit 0
fi

# ==============================================================================
# STEP 4: TERMINATE RUNNING PROCESSES AND SERVICES
# ==============================================================================
log_step "STEP 4: Terminate AnyDesk Processes and Background Services"

if [[ "$DETECTED_OS" == "macos" ]]; then
    log_info "Gracefully requesting AnyDesk to quit on macOS..."
    osascript -e 'quit app "AnyDesk"' >/dev/null 2>&1 || true

    log_info "Unloading LaunchDaemons & LaunchAgents..."
    sudo launchctl unload /Library/LaunchDaemons/com.philandro.anydesk.Helper.plist >/dev/null 2>&1 || true
    sudo launchctl unload /Library/LaunchDaemons/com.philandro.anydesk.service.plist >/dev/null 2>&1 || true
    launchctl unload "$HOME/Library/LaunchAgents/com.philandro.anydesk.Frontend.plist" >/dev/null 2>&1 || true

    log_info "Terminating any lingering AnyDesk processes..."
    sudo killall -9 AnyDesk >/dev/null 2>&1 || true
    sudo killall -9 anydesk_service >/dev/null 2>&1 || true
    sleep 1

elif [[ "$DETECTED_OS" == "windows" || "$DETECTED_OS" == "windows_wsl" ]]; then
    log_info "Stopping Windows AnyDesk service..."
    cmd.exe /c "net stop AnyDesk" >/dev/null 2>&1 || true
    cmd.exe /c "sc.exe stop AnyDesk" >/dev/null 2>&1 || true

    log_info "Forcefully terminating AnyDesk.exe processes..."
    cmd.exe /c "taskkill /F /IM AnyDesk.exe /T" >/dev/null 2>&1 || true
    cmd.exe /c "taskkill /F /IM AnyDeskService.exe /T" >/dev/null 2>&1 || true
    sleep 1
fi

log_ok "AnyDesk processes and services stopped."

# ==============================================================================
# STEP 5: BACKUP EXISTING CONFIGURATIONS
# ==============================================================================
log_step "STEP 5: QA Backup Creation"

if [[ "$DO_BACKUP" == true ]]; then
    if [[ -n "$CUSTOM_BACKUP_DIR" ]]; then
        BACKUP_DIR="$(to_posix "$CUSTOM_BACKUP_DIR")"
    else
        BACKUP_DIR="$(pwd)/anydesk_backup_${TIMESTAMP}"
    fi

    mkdir -p "$BACKUP_DIR"
    log_info "Backup directory initialized at: ${BACKUP_DIR}"

    # Save metadata
    cat <<META > "${BACKUP_DIR}/qa_reset_meta.txt"
AnyDesk QA Reset Backup
Timestamp: $(date)
Original_ID: ${OLD_ID:-N/A}
OS: ${DETECTED_OS}
Script_Version: ${SCRIPT_VERSION}
META

    backup_count=0
    for file in "${TARGET_FILES[@]}"; do
        if [[ -f "$file" ]]; then
            # Mirror relative path into backup dir
            safe_name="$(echo "$file" | sed -E 's|^/||; s|/|_|g')"
            cp -f "$file" "${BACKUP_DIR}/${safe_name}"
            ((backup_count++)) || true
        fi
    done

    log_ok "Backed up ${backup_count} identity configuration file(s) successfully."
else
    log_warn "Backup skipped by user (--no-backup passed)."
fi

# ==============================================================================
# STEP 6: RESET CONFIGURATION FILES (WIPE IDENTITY)
# ==============================================================================
log_step "STEP 6: Reset Configuration Files (Clearing Identity)"

removed_count=0
for file in "${TARGET_FILES[@]}"; do
    if [[ -f "$file" ]]; then
        rm -f "$file" 2>/dev/null || {
            if [[ "$DETECTED_OS" == "macos" ]]; then
                sudo rm -f "$file"
            else
                cmd.exe /c "del /f /q \"$(to_windows "$file")\"" >/dev/null 2>&1 || true
            fi
        }
        log_info "Removed identity file: $file"
        ((removed_count++)) || true
    fi
done

if [[ "$CLEAR_CACHE" == true ]]; then
    log_info "Purging AnyDesk cache, thumbnails, and chat data..."
    for dir in "${FOUND_DIRS[@]}"; do
        for sub in "cache" "thumbnails" "chat" "global_cache"; do
            if [[ -d "${dir}/${sub}" ]]; then
                rm -rf "${dir}/${sub}"
                log_info "Purged directory: ${dir}/${sub}"
            fi
        done
    done
fi

log_ok "Reset complete. ${removed_count} identity file(s) wiped."

# ==============================================================================
# STEP 7: RESTART ANYDESK & VERIFY NEW ID GENERATION
# ==============================================================================
log_step "STEP 7: Restart AnyDesk and Verify New ID"

if [[ "$DO_RESTART" == true ]]; then
    if [[ "$DETECTED_OS" == "macos" ]]; then
        log_info "Starting AnyDesk on macOS..."
        if [[ -n "$ANYDESK_BIN" ]]; then
            open -a AnyDesk >/dev/null 2>&1 || ("$ANYDESK_BIN" &) >/dev/null 2>&1 || true
        else
            open -a AnyDesk >/dev/null 2>&1 || true
        fi

    elif [[ "$DETECTED_OS" == "windows" || "$DETECTED_OS" == "windows_wsl" ]]; then
        log_info "Starting Windows AnyDesk service and application..."
        cmd.exe /c "net start AnyDesk" >/dev/null 2>&1 || true
        if [[ -n "$ANYDESK_BIN" ]]; then
            WIN_BIN="$(to_windows "$ANYDESK_BIN")"
            cmd.exe /c "start \"\" \"${WIN_BIN}\"" >/dev/null 2>&1 || true
        fi
    fi

    log_info "Waiting for AnyDesk to generate new ID (probing up to 10s)..."
    for i in {1..10}; do
        sleep 1
        NEW_ID="$(get_current_id)"
        if [[ -n "$NEW_ID" && "$NEW_ID" != "$OLD_ID" ]]; then
            break
        fi
    done

    # --- QA Verification Report ---
    echo -e "\n${C_BOLD}${C_MAGENTA}=================================================================${C_RESET}"
    echo -e "${C_BOLD}${C_MAGENTA}                 QA VERIFICATION REPORT                          ${C_RESET}"
    echo -e "${C_BOLD}${C_MAGENTA}=================================================================${C_RESET}"
    log_path "Previous AnyDesk ID" "${OLD_ID:-N/A}"
    log_path "New AnyDesk ID"      "${NEW_ID:-Generating...}"

    if [[ -n "$NEW_ID" && "$NEW_ID" != "$OLD_ID" ]]; then
        echo -e "\n${C_BOLD}${C_GREEN}>>> [PASS] AnyDesk ID successfully reset and regenerated! <<<${C_RESET}"
    elif [[ "$NEW_ID" == "$OLD_ID" && -n "$OLD_ID" ]]; then
        echo -e "\n${C_BOLD}${C_YELLOW}>>> [WARN] ID matches previous ID. AnyDesk service may need a reboot <<<${C_RESET}"
    else
        echo -e "\n${C_BOLD}${C_CYAN}>>> [INFO] AnyDesk is connecting to server. The new ID will populate shortly in the UI. <<<${C_RESET}"
    fi
    echo -e "${C_BOLD}${C_MAGENTA}=================================================================${C_RESET}\n"

else
    log_info "Automatic restart skipped (--no-restart passed)."
    log_ok "Identity reset is staged. Launch AnyDesk manually when ready."
fi
