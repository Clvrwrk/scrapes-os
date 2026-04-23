#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# Agentic OS — Safe Update Script
# Pulls upstream changes without overwriting user data.
#
# Usage: bash scripts/update.sh
# ==========================================================

# ---------- Colors ----------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

info()  { printf "  ${CYAN}%b${NC}\n" "$1"; }
ok()    { printf "  ${GREEN}✓ %b${NC}\n" "$1"; }
warn()  { printf "  ${YELLOW}→ %b${NC}\n" "$1"; }
bullet(){ printf "    ${DIM}•${NC} %b\n" "$1"; }

ask_yes_no() {
    local prompt="$1"
    local default_answer="${2:-Y}"
    local reply=""

    if [[ "$default_answer" == "N" ]]; then
        printf "  ${BOLD}%s${NC} [y/N] " "$prompt"
    else
        printf "  ${BOLD}%s${NC} [Y/n] " "$prompt"
    fi

    if ! read -r reply < /dev/tty; then
        reply="$default_answer"
    fi

    reply="${reply:-$default_answer}"
    [[ "$reply" =~ ^[Yy]$ ]]
}

print_warning_box_start() {
    local title="$1"
    echo ""
    printf "${YELLOW}${BOLD}═══════════════════════════════════════════════${NC}\n"
    printf "${YELLOW}${BOLD}  %s${NC}\n" "$title"
    printf "${YELLOW}${BOLD}═══════════════════════════════════════════════${NC}\n"
    echo ""
}

print_warning_box_line() {
    printf "  %s\n" "$1"
}

print_warning_box_path() {
    printf "  ${BOLD}%-18s${NC} %s\n" "$1" "$2"
}

print_warning_box_end() {
    echo ""
}

# ---------- Repo root from script location ----------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) REPO_ROOT="$(cygpath -m "$REPO_ROOT")" ;; esac
source "$SCRIPT_DIR/lib/python.sh"
if ! resolve_python_cmd; then
    printf "  ${RED}Python 3 is required for update.sh.${NC}\n"
    exit 1
fi
cd "$REPO_ROOT"

CATALOG="$REPO_ROOT/.claude/skills/_catalog/catalog.json"
INSTALLED="$REPO_ROOT/.claude/skills/_catalog/installed.json"
BACKUP_DIR="$REPO_ROOT/.backup"
REVIEWED_STATE="$BACKUP_DIR/.update-reviewed"

# ---------- Reviewed-state helpers ----------
# Stores md5 checksums of files the user already reviewed.
# If the file hasn't changed since last review, skip it.
file_md5() {
    md5 -q "$1" 2>/dev/null || md5sum "$1" 2>/dev/null | awk '{print $1}' || echo ""
}

was_already_reviewed() {
    local file="$1"
    [[ ! -f "$REVIEWED_STATE" ]] && return 1
    local current_md5
    current_md5=$(file_md5 "$REPO_ROOT/$file")
    [[ -z "$current_md5" ]] && return 1
    grep -qx "${file}:${current_md5}" "$REVIEWED_STATE" 2>/dev/null
}

mark_reviewed() {
    local file="$1"
    local current_md5
    current_md5=$(file_md5 "$REPO_ROOT/$file")
    [[ -z "$current_md5" ]] && return
    mkdir -p "$BACKUP_DIR"
    # Remove old entry for this file, add new one
    if [[ -f "$REVIEWED_STATE" ]]; then
        grep -v "^${file}:" "$REVIEWED_STATE" > "${REVIEWED_STATE}.tmp" 2>/dev/null || true
        mv "${REVIEWED_STATE}.tmp" "$REVIEWED_STATE"
    fi
    echo "${file}:${current_md5}" >> "$REVIEWED_STATE"
}

CENTRE_SHORTCUT_HELPER_LOADED="false"
CENTRE_SHORTCUT_MISMATCH="false"
CENTRE_SHORTCUT_CURRENT_PATH=""
CENTRE_SHORTCUT_EXPECTED_PATH=""
CENTRE_SHORTCUT_LEGACY_LAYOUT="false"

load_centre_shortcut_helper() {
    local helper_path="$SCRIPT_DIR/lib/centre-shortcut.sh"

    if [[ "$CENTRE_SHORTCUT_HELPER_LOADED" == "true" ]]; then
        return 0
    fi

    [[ -f "$helper_path" ]] || return 1

    # shellcheck disable=SC1090
    source "$helper_path"
    CENTRE_SHORTCUT_HELPER_LOADED="true"
}

get_powershell_shortcut_status() {
    local ps_script="$SCRIPT_DIR/install-centre-alias.ps1"

    [[ -f "$ps_script" ]] || return 1
    command -v powershell.exe >/dev/null 2>&1 || return 1

    if command -v cygpath >/dev/null 2>&1; then
        ps_script="$(cygpath -w "$ps_script")"
    fi

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$ps_script" -Status 2>/dev/null | tr -d '\r'
}

parse_powershell_shortcut_status() {
    local status_json="$1"
    local parsed_output=""

    parsed_output="$(
        printf '%s' "$status_json" | "${PYTHON_CMD[@]}" -c 'import json, sys
data = json.loads(sys.stdin.read() or "{}")
print("true" if data.get("shortcuts_detected") else "false")
print("true" if data.get("mismatch_detected") else "false")
print(data.get("current_shortcut_path", ""))
print(data.get("expected_shortcut_path", ""))
print("true" if data.get("is_legacy_projects_layout") else "false")'
    )"

    POWERSHELL_SHORTCUT_DETECTED="$(printf '%s\n' "$parsed_output" | sed -n '1p')"
    POWERSHELL_SHORTCUT_MISMATCH="$(printf '%s\n' "$parsed_output" | sed -n '2p')"
    POWERSHELL_SHORTCUT_CURRENT_PATH="$(printf '%s\n' "$parsed_output" | sed -n '3p')"
    POWERSHELL_SHORTCUT_EXPECTED_PATH="$(printf '%s\n' "$parsed_output" | sed -n '4p')"
    POWERSHELL_SHORTCUT_LEGACY_LAYOUT="$(printf '%s\n' "$parsed_output" | sed -n '5p')"

    POWERSHELL_SHORTCUT_DETECTED="${POWERSHELL_SHORTCUT_DETECTED:-false}"
    POWERSHELL_SHORTCUT_MISMATCH="${POWERSHELL_SHORTCUT_MISMATCH:-false}"
    POWERSHELL_SHORTCUT_LEGACY_LAYOUT="${POWERSHELL_SHORTCUT_LEGACY_LAYOUT:-false}"
}

check_centre_shortcut_mismatch() {
    local unix_centre_script="$SCRIPT_DIR/centre.sh"
    local ps_status_json=""
    local i=0

    CENTRE_SHORTCUT_MISMATCH="false"
    CENTRE_SHORTCUT_CURRENT_PATH=""
    CENTRE_SHORTCUT_EXPECTED_PATH=""
    CENTRE_SHORTCUT_LEGACY_LAYOUT="false"

    if load_centre_shortcut_helper; then
        agentic_os_centre_scan_unix_shortcuts "$unix_centre_script"
        for i in "${!AGENTIC_OS_CENTRE_SCAN_FILES[@]}"; do
            if [[ "${AGENTIC_OS_CENTRE_SCAN_MATCHES[$i]}" == "true" ]]; then
                continue
            fi

            CENTRE_SHORTCUT_MISMATCH="true"
            CENTRE_SHORTCUT_CURRENT_PATH="${AGENTIC_OS_CENTRE_SCAN_CURRENT[$i]}"
            CENTRE_SHORTCUT_EXPECTED_PATH="$unix_centre_script"
            CENTRE_SHORTCUT_LEGACY_LAYOUT="${AGENTIC_OS_CENTRE_SCAN_LEGACY_LAYOUT[$i]}"
            break
        done
    fi

    if ps_status_json="$(get_powershell_shortcut_status)"; then
        parse_powershell_shortcut_status "$ps_status_json"
        if [[ "$POWERSHELL_SHORTCUT_MISMATCH" == "true" ]]; then
            if [[ "$CENTRE_SHORTCUT_MISMATCH" != "true" ]]; then
                CENTRE_SHORTCUT_CURRENT_PATH="$POWERSHELL_SHORTCUT_CURRENT_PATH"
                CENTRE_SHORTCUT_EXPECTED_PATH="$POWERSHELL_SHORTCUT_EXPECTED_PATH"
                CENTRE_SHORTCUT_LEGACY_LAYOUT="$POWERSHELL_SHORTCUT_LEGACY_LAYOUT"
            elif [[ "$POWERSHELL_SHORTCUT_LEGACY_LAYOUT" == "true" ]]; then
                CENTRE_SHORTCUT_LEGACY_LAYOUT="true"
            fi

            CENTRE_SHORTCUT_MISMATCH="true"
        fi
    fi
}

maybe_offer_centre_shortcut_repair() {
    check_centre_shortcut_mismatch

    if [[ "$CENTRE_SHORTCUT_MISMATCH" != "true" ]]; then
        return 0
    fi

    print_warning_box_start "centre shortcut points to another install"
    print_warning_box_line "Your saved 'centre' shortcut is still pointing to an older Agentic OS folder."
    print_warning_box_line "Repairing it will make 'centre' open this repo instead."
    print_warning_box_path "Current shortcut:" "$CENTRE_SHORTCUT_CURRENT_PATH"
    print_warning_box_path "Expected path:" "$CENTRE_SHORTCUT_EXPECTED_PATH"
    if [[ "$CENTRE_SHORTCUT_LEGACY_LAYOUT" == "true" ]]; then
        print_warning_box_line "That old path is inside a projects folder. That was an older layout and should no longer be used."
    fi
    print_warning_box_end

    if ask_yes_no "Repair the shortcut to this repo now?" "Y"; then
        if bash "$SCRIPT_DIR/repair-centre-shortcut.sh" >/dev/null 2>&1; then
            ok "Repaired the saved 'centre' shortcut for this repo."
            info "Open a new terminal window before using 'centre' again."
        else
            warn "Automatic shortcut repair failed."
            info "You can repair it later with:"
            printf "     ${BOLD}bash scripts/repair-centre-shortcut.sh${NC}\n"
        fi
    else
        info "No shortcut files were changed."
        info "If you want to repair it later, run:"
        printf "     ${BOLD}bash scripts/repair-centre-shortcut.sh${NC}\n"
    fi
}

# ---------- Protected paths (never overwritten) ----------
# These are user-specific files. The update script will NEVER touch them.
# Upstream ships .template versions of USER.md and learnings.md — those
# are safe to update. The working copies below belong to the user.
PROTECTED_PATHS=(
    ".env"
    ".mcp.json"
    "context/USER.md"
    "context/SOUL.md"
    "context/learnings.md"
    "context/learnings.md.template"
    "context/memory/"
    "brand_context/"
    "projects/"
    ".claude/skills/_catalog/installed.json"
    ".claude/skills/viz-ugc-heygen/references/avatar-config.md"
)

# =========================================================
# Step 1: Verify we're in a git repo
# =========================================================
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo ""
    printf "  ${RED}Not a git repository.${NC} Run this from the Agentic OS root.\n"
    exit 1
fi

# =========================================================
# Step 0: Self-update — fetch the latest update.sh first
# =========================================================
# Solves the chicken-and-egg problem: this script can't fix bugs in
# itself if the user is running the old version. So before doing
# anything else, pull the latest copy from origin and re-exec.
# The __SELF_UPDATED env var prevents infinite loops.
if [[ -z "${__SELF_UPDATED:-}" ]]; then
    info "Fetching the latest update script..."
    git fetch origin main --quiet 2>/dev/null || true
    REMOTE_HASH=$(git show origin/main:scripts/update.sh 2>/dev/null | md5 -q 2>/dev/null || git show origin/main:scripts/update.sh 2>/dev/null | md5sum 2>/dev/null | awk '{print $1}' || echo "")
    LOCAL_HASH=$(md5 -q "$SCRIPT_DIR/update.sh" 2>/dev/null || md5sum "$SCRIPT_DIR/update.sh" 2>/dev/null | awk '{print $1}' || echo "")
    if [[ -n "$REMOTE_HASH" ]] && [[ -n "$LOCAL_HASH" ]] && [[ "$REMOTE_HASH" != "$LOCAL_HASH" ]]; then
        ok "Update script has changed — reloading with latest version..."
        echo ""
        git checkout origin/main -- scripts/update.sh 2>/dev/null || true
        __SELF_UPDATED=1 exec bash "$SCRIPT_DIR/update.sh" "$@"
    else
        ok "Update script is current"
    fi
else
    ok "Running latest update script"
fi

echo ""
printf "${CYAN}${BOLD}"
cat << 'BANNER'
    ╔══════════════════════════════════════════════╗
    ║                                              ║
    ║            A G E N T I C   O S               ║
    ║                                              ║
    ║               Update Check                   ║
    ║                                              ║
    ╚══════════════════════════════════════════════╝
BANNER
printf "${NC}"
echo ""

# =========================================================
# Step 2: Read installed.json for user's skill choices
# =========================================================
if [[ ! -f "$INSTALLED" ]]; then
    HAVE_INSTALLED_JSON=false
else
    HAVE_INSTALLED_JSON=true
fi

# =========================================================
# Step 3: Save current HEAD
# =========================================================
OLD_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
OLD_HEAD=$(git rev-parse HEAD)
LAST_UPDATED=$(git log -1 --format="%cd" --date=format:"%d %b %Y at %H:%M" 2>/dev/null || echo "unknown")

# =========================================================
# Step 4: Stash local changes to protected paths
# =========================================================
STASHED=false

has_protected_changes() {
    for p in "${PROTECTED_PATHS[@]}"; do
        if git diff --name-only -- "$p" 2>/dev/null | grep -q .; then
            return 0
        fi
        if git diff --cached --name-only -- "$p" 2>/dev/null | grep -q .; then
            return 0
        fi
    done
    return 1
}

if has_protected_changes; then
    git stash push --include-untracked -m "agentic-os-update-$(date +%s)" -- "${PROTECTED_PATHS[@]}" 2>/dev/null && STASHED=true
fi

# =========================================================
# Step 5: Scan local skill modifications before pull
# =========================================================
SKILL_BACKUP_DIR="$BACKUP_DIR/skills-$(date +%s)"
MODIFIED_SKILLS=()
MODIFIED_SKILL_FILES=()  # parallel array: pipe-separated file list per skill
USER_CREATED_SKILLS=()

if [[ -d "$REPO_ROOT/.claude/skills" ]]; then
    for skill_dir in "$REPO_ROOT/.claude/skills"/*/; do
        [[ -d "$skill_dir" ]] || continue
        skill_name=$(basename "$skill_dir")
        [[ "$skill_name" == "_catalog" ]] && continue

        # Untracked = user-created skill
        tracked_files=$(git ls-files -- ".claude/skills/$skill_name/" 2>/dev/null || true)
        if [[ -z "$tracked_files" ]]; then
            USER_CREATED_SKILLS+=("$skill_name")
            continue
        fi

        # Check for local modifications (skip files already reviewed)
        modified_files=$(git diff --name-only -- ".claude/skills/$skill_name/" 2>/dev/null || true)
        if [[ -n "$modified_files" ]]; then
            # Filter out files whose content hasn't changed since last review
            new_modified=""
            while IFS= read -r mf; do
                [[ -z "$mf" ]] && continue
                if ! was_already_reviewed "$mf"; then
                    new_modified="${new_modified}${mf}\n"
                fi
            done <<< "$modified_files"
            new_modified=$(printf '%b' "$new_modified" | sed '/^$/d')

            if [[ -n "$new_modified" ]]; then
                mkdir -p "$SKILL_BACKUP_DIR/$skill_name"
                cp -r "$skill_dir"* "$SKILL_BACKUP_DIR/$skill_name/" 2>/dev/null || true
                MODIFIED_SKILLS+=("$skill_name")
                file_list=$(echo "$new_modified" | while IFS= read -r f; do basename "$f"; done | tr '\n' '|' | sed 's/|$//')
                MODIFIED_SKILL_FILES+=("$file_list")
            fi
        fi
    done
fi

# Reset modified skill files to HEAD so git pull won't conflict.
# User's versions are safe in SKILL_BACKUP_DIR and will be offered
# back during the per-file review step.
if [[ ${#MODIFIED_SKILLS[@]} -gt 0 ]]; then
    for skill_name in "${MODIFIED_SKILLS[@]}"; do
        git checkout HEAD -- ".claude/skills/$skill_name/" 2>/dev/null || true
    done
fi

# =========================================================
# Step 5b: Stash other modified tracked files (not protected, not skills)
# =========================================================
OTHER_BACKUP_DIR="$BACKUP_DIR/other-$(date +%s)"
OTHER_MODIFIED_FILES=()

# Get all modified tracked files
ALL_MODIFIED=$(git diff --name-only 2>/dev/null || true)
ALL_STAGED=$(git diff --cached --name-only 2>/dev/null || true)
ALL_DIRTY=$(printf '%s\n%s' "$ALL_MODIFIED" "$ALL_STAGED" | sort -u | grep -v '^$' || true)

if [[ -n "$ALL_DIRTY" ]]; then
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        # Skip protected paths
        is_protected=false
        for p in "${PROTECTED_PATHS[@]}"; do
            case "$file" in
                $p|$p*) is_protected=true; break ;;
            esac
        done
        $is_protected && continue

        # Skip skill files (handled separately above)
        case "$file" in
            .claude/skills/*) continue ;;
        esac

        # Skip files already reviewed with unchanged content
        if was_already_reviewed "$file"; then
            continue
        fi

        # This is an "other" modified file — back it up and reset
        mkdir -p "$OTHER_BACKUP_DIR/$(dirname "$file")"
        cp "$REPO_ROOT/$file" "$OTHER_BACKUP_DIR/$file" 2>/dev/null || true
        OTHER_MODIFIED_FILES+=("$file")
    done <<< "$ALL_DIRTY"
fi

# Reset other modified files so git pull won't conflict
if [[ ${#OTHER_MODIFIED_FILES[@]} -gt 0 ]]; then
    for file in "${OTHER_MODIFIED_FILES[@]}"; do
        git checkout HEAD -- "$file" 2>/dev/null || true
    done
fi

# =========================================================
# Step 5c: Pre-pull conflict prevention
# =========================================================
# Files that were deleted upstream but may exist locally cause merge conflicts
# that git stash can't prevent (stash saves changes, but the pull still tries
# to delete the file). Back up and remove these before pulling, restore after.
#
# Also handles template files that both sides may have modified.
CONFLICT_BACKUP_DIR="$BACKUP_DIR/conflict-prevention-$(date +%s)"
CONFLICT_BACKED_UP=()

# Fetch first so we can compare against origin/main
git fetch origin 2>/dev/null || true

# --- Handle protected paths that changed upstream ---
for protected in "${PROTECTED_PATHS[@]}"; do
    # Skip directory paths
    [[ "$protected" == */ ]] && continue
    local_file="$REPO_ROOT/$protected"
    [[ ! -f "$local_file" ]] && continue

    # Check if this file was deleted upstream or will conflict
    if ! git cat-file -e "origin/main:${protected}" 2>/dev/null; then
        # File deleted upstream but exists locally — back up and remove to prevent conflict
        mkdir -p "$CONFLICT_BACKUP_DIR/$(dirname "$protected")"
        cp "$local_file" "$CONFLICT_BACKUP_DIR/$protected"
        git rm -f --cached "$protected" 2>/dev/null || true
        CONFLICT_BACKED_UP+=("$protected")
    elif git diff --name-only "HEAD...origin/main" -- "$protected" 2>/dev/null | grep -q .; then
        # File changed upstream AND exists locally (potential merge conflict)
        mkdir -p "$CONFLICT_BACKUP_DIR/$(dirname "$protected")"
        cp "$local_file" "$CONFLICT_BACKUP_DIR/$protected"
        git checkout HEAD -- "$protected" 2>/dev/null || true
        CONFLICT_BACKED_UP+=("$protected")
    fi
done

# --- Auto-detect ALL files deleted upstream but still tracked locally ---
# Prevents modify/delete merge conflicts for ANY file removed upstream
# (e.g. cron jobs, old scripts), not just protected paths.
MERGE_BASE=$(git merge-base HEAD origin/main 2>/dev/null || echo "")
if [[ -n "$MERGE_BASE" ]]; then
    DELETED_COUNT=0
    while IFS= read -r del_file; do
        [[ -z "$del_file" ]] && continue
        if git ls-files --error-unmatch "$del_file" &>/dev/null 2>&1; then
            git rm --cached "$del_file" 2>/dev/null || true
            DELETED_COUNT=$((DELETED_COUNT + 1))
        fi
    done < <(git diff --name-only --diff-filter=D "$MERGE_BASE" origin/main 2>/dev/null)
    if [[ $DELETED_COUNT -gt 0 ]]; then
        ok "Cleaned up ${DELETED_COUNT} file(s) removed in latest update"
    fi
fi

# =========================================================
# Step 6: Pull upstream changes
# =========================================================
info "Checking for updates..."
echo ""

MERGE_FAILED=false
PULL_OUTPUT=$(git pull origin main 2>&1) || MERGE_FAILED=true

# --- Nuclear fallback: if merge fails for ANY reason, force-reset ---
# Instead of trying to handle every edge case (modify/delete conflicts,
# "would be overwritten", template divergences, etc.), just force the
# repo to match origin/main and restore user data from backups.
if $MERGE_FAILED; then
    # Check for auth failures first — those can't be fixed by force-reset
    if echo "$PULL_OUTPUT" | grep -qi "authentication\|403\|could not read\|repository not found\|invalid credentials"; then
        git merge --abort 2>/dev/null || true
        if $STASHED; then
            git stash pop --quiet 2>/dev/null || true
        fi
        for protected in "${CONFLICT_BACKED_UP[@]:-}"; do
            [[ -z "$protected" ]] && continue
            if [[ -f "$CONFLICT_BACKUP_DIR/$protected" ]]; then
                mkdir -p "$(dirname "$REPO_ROOT/$protected")"
                cp "$CONFLICT_BACKUP_DIR/$protected" "$REPO_ROOT/$protected"
            fi
        done
        for skill_name in "${MODIFIED_SKILLS[@]:-}"; do
            [[ -z "$skill_name" ]] && continue
            cp -r "$SKILL_BACKUP_DIR/$skill_name"/* "$REPO_ROOT/.claude/skills/$skill_name/" 2>/dev/null || true
        done
        for file in "${OTHER_MODIFIED_FILES[@]:-}"; do
            [[ -z "$file" ]] && continue
            cp "$OTHER_BACKUP_DIR/$file" "$REPO_ROOT/$file" 2>/dev/null || true
        done

        echo ""
        printf "${YELLOW}${BOLD}═══════════════════════════════════════════════${NC}\n"
        printf "${YELLOW}${BOLD}  Authentication Failed${NC}\n"
        printf "${YELLOW}${BOLD}═══════════════════════════════════════════════${NC}\n"
        echo ""
        warn "Your access token may have been rotated."
        echo ""
        info "To fix this:"
        echo ""
        echo "  1. Get the latest token from:"
        printf "     ${CYAN}https://www.skool.com/scrapes/classroom/d1cfafed?md=552b0ba753df4c738843913fb3eb8312${NC}\n"
        echo ""
        echo "  2. Update your remote URL:"
        printf "     ${BOLD}git remote set-url origin https://<NEW-TOKEN>@github.com/simonc602/agentic-os.git${NC}\n"
        echo ""
        echo "  3. Run this script again:"
        printf "     ${BOLD}bash scripts/update.sh${NC}\n"
        echo ""
        info "Nothing was changed — your local files are untouched."
        exit 1
    fi

    # Not an auth issue — force-reset to match origin/main
    warn "Merge had conflicts — force-syncing to latest version..."
    git merge --abort 2>/dev/null || true

    # Back up ALL protected paths before reset (reset deletes tracked files
    # that don't exist on origin/main — including user data that was tracked
    # in older versions but is now gitignored)
    RESET_BACKUP="$BACKUP_DIR/pre-reset-$(date +%s)"
    for protected in "${PROTECTED_PATHS[@]}"; do
        local_path="$REPO_ROOT/$protected"
        if [[ "$protected" == */ ]]; then
            # Directory — copy entire tree if it exists and has content
            if [[ -d "$local_path" ]] && [[ -n "$(ls -A "$local_path" 2>/dev/null)" ]]; then
                mkdir -p "$RESET_BACKUP/$protected"
                cp -r "$local_path"* "$RESET_BACKUP/$protected" 2>/dev/null || true
            fi
        else
            # File — copy if it exists
            if [[ -f "$local_path" ]]; then
                mkdir -p "$RESET_BACKUP/$(dirname "$protected")"
                cp "$local_path" "$RESET_BACKUP/$protected"
            fi
        fi
    done

    git reset --hard origin/main 2>/dev/null || true
    ok "Synced to latest version"

    # Restore ALL protected paths from backup
    for protected in "${PROTECTED_PATHS[@]}"; do
        if [[ "$protected" == */ ]]; then
            if [[ -d "$RESET_BACKUP/$protected" ]]; then
                mkdir -p "$REPO_ROOT/$protected"
                cp -r "$RESET_BACKUP/$protected"* "$REPO_ROOT/$protected" 2>/dev/null || true
            fi
        else
            if [[ -f "$RESET_BACKUP/$protected" ]]; then
                mkdir -p "$(dirname "$REPO_ROOT/$protected")"
                cp "$RESET_BACKUP/$protected" "$REPO_ROOT/$protected"
            fi
        fi
    done

    # Restore modified skills and other files from earlier backups
    if $STASHED; then
        git stash pop --quiet 2>/dev/null || true
    fi
    for skill_name in "${MODIFIED_SKILLS[@]:-}"; do
        [[ -z "$skill_name" ]] && continue
        if [[ -d "$SKILL_BACKUP_DIR/$skill_name" ]]; then
            mkdir -p "$REPO_ROOT/.claude/skills/$skill_name"
            cp -r "$SKILL_BACKUP_DIR/$skill_name"/* "$REPO_ROOT/.claude/skills/$skill_name/" 2>/dev/null || true
        fi
    done
    for file in "${OTHER_MODIFIED_FILES[@]:-}"; do
        [[ -z "$file" ]] && continue
        cp "$OTHER_BACKUP_DIR/$file" "$REPO_ROOT/$file" 2>/dev/null || true
    done
    MERGE_FAILED=false
    PULL_OUTPUT="force-synced"
fi

# =========================================================
# Determine if anything changed
# =========================================================
HAS_UPSTREAM_CHANGES=true
if echo "$PULL_OUTPUT" | grep -q "Already up to date"; then
    HAS_UPSTREAM_CHANGES=false
    if $STASHED; then
        git stash pop --quiet 2>/dev/null || true
    fi
fi

NEW_HEAD=$(git rev-parse HEAD)
COMMIT_COUNT=0
if $HAS_UPSTREAM_CHANGES; then
    COMMIT_COUNT=$(git log --oneline "${OLD_HEAD}..${NEW_HEAD}" 2>/dev/null | wc -l | tr -d ' ')
fi

# =========================================================
# Restore conflict-prevented files
# =========================================================
# These were backed up in Step 5c to prevent merge conflicts.
# Restore the user's versions now that the pull is complete.
if [[ ${#CONFLICT_BACKED_UP[@]} -gt 0 ]]; then
    for protected in "${CONFLICT_BACKED_UP[@]}"; do
        if [[ -f "$CONFLICT_BACKUP_DIR/$protected" ]]; then
            mkdir -p "$(dirname "$REPO_ROOT/$protected")"
            cp "$CONFLICT_BACKUP_DIR/$protected" "$REPO_ROOT/$protected"
        fi
    done
fi

# =========================================================
# STEP 1 OF 4: Updates from the Main Repo
# =========================================================
echo ""
printf "${CYAN}${BOLD}═══════════════════════════════════════════════${NC}\n"
printf "${CYAN}${BOLD}  Step 1: Updates from the Main Repo${NC}\n"
printf "${CYAN}${BOLD}═══════════════════════════════════════════════${NC}\n"
echo ""

if ! $HAS_UPSTREAM_CHANGES; then
    ok "No new updates — you're on the latest version."
    info "Last updated: ${BOLD}${LAST_UPDATED}${NC}"
    echo ""
    info "Scripts:              ${GREEN}no changes${NC}"
    info "System files:         ${GREEN}no changes${NC}  ${DIM}(AGENTS.md, CLAUDE.md, README.md, etc.)${NC}"
    info "Skill catalog:        ${GREEN}no changes${NC}"
    info "Skills:               ${GREEN}no changes${NC}"
    echo ""
else
    ok "Pulled ${COMMIT_COUNT} new commit(s) from main."
    echo ""

    CHANGED_FILES=$(git diff --name-only "${OLD_HEAD}..${NEW_HEAD}" 2>/dev/null || true)

    # Categorise into buckets
    CHANGED_SCRIPTS=""
    CHANGED_SYSTEM=""
    CHANGED_CATALOG=""
    CHANGED_SKILL_FILES=""
    CHANGED_OTHER=""
    SCRIPT_COUNT=0; SYSTEM_COUNT=0; CATALOG_COUNT=0; SKILL_COUNT=0; OTHER_COUNT=0

    if [[ -n "$CHANGED_FILES" ]]; then
        while IFS= read -r file; do
            case "$file" in
                scripts/*)
                    CHANGED_SCRIPTS="${CHANGED_SCRIPTS}${file}\n"
                    SCRIPT_COUNT=$((SCRIPT_COUNT + 1))
                    ;;
                AGENTS.md|CLAUDE.md|PRD.md|README.md|.gitignore|.gitattributes)
                    CHANGED_SYSTEM="${CHANGED_SYSTEM}${file}\n"
                    SYSTEM_COUNT=$((SYSTEM_COUNT + 1))
                    ;;
                .claude/skills/_catalog/*)
                    CHANGED_CATALOG="${CHANGED_CATALOG}${file}\n"
                    CATALOG_COUNT=$((CATALOG_COUNT + 1))
                    ;;
                .claude/skills/*)
                    CHANGED_SKILL_FILES="${CHANGED_SKILL_FILES}${file}\n"
                    SKILL_COUNT=$((SKILL_COUNT + 1))
                    ;;
                context/*|brand_context/*|projects/*|.env*)
                    ;; # Protected — skip
                *)
                    CHANGED_OTHER="${CHANGED_OTHER}${file}\n"
                    OTHER_COUNT=$((OTHER_COUNT + 1))
                    ;;
            esac
        done <<< "$CHANGED_FILES"
    fi

    # Always show every category — with "no changes" when empty
    if [[ $SCRIPT_COUNT -gt 0 ]]; then
        printf "  ${BOLD}Scripts${NC} ${DIM}(%d updated)${NC}\n" "$SCRIPT_COUNT"
        printf "$CHANGED_SCRIPTS" | while IFS= read -r f; do [[ -n "$f" ]] && bullet "$f"; done
    else
        info "Scripts:              ${GREEN}no changes${NC}"
    fi

    if [[ $SYSTEM_COUNT -gt 0 ]]; then
        printf "  ${BOLD}System files${NC} ${DIM}(%d updated)${NC}\n" "$SYSTEM_COUNT"
        printf "$CHANGED_SYSTEM" | while IFS= read -r f; do [[ -n "$f" ]] && bullet "$f"; done
    else
        info "System files:         ${GREEN}no changes${NC}  ${DIM}(AGENTS.md, CLAUDE.md, README.md, etc.)${NC}"
    fi

    if [[ $CATALOG_COUNT -gt 0 ]]; then
        printf "  ${BOLD}Skill catalog${NC} ${DIM}(%d updated)${NC}\n" "$CATALOG_COUNT"
        printf "$CHANGED_CATALOG" | while IFS= read -r f; do [[ -n "$f" ]] && bullet "$f"; done
    else
        info "Skill catalog:        ${GREEN}no changes${NC}"
    fi

    if [[ $SKILL_COUNT -gt 0 ]]; then
        printf "  ${BOLD}Skills${NC} ${DIM}(%d file(s) updated)${NC}\n" "$SKILL_COUNT"
        printf "$CHANGED_SKILL_FILES" | while IFS= read -r f; do [[ -n "$f" ]] && bullet "$f"; done
    else
        info "Skills:               ${GREEN}no changes${NC}"
    fi

    if [[ $OTHER_COUNT -gt 0 ]]; then
        printf "  ${BOLD}Other${NC} ${DIM}(%d updated)${NC}\n" "$OTHER_COUNT"
        printf "$CHANGED_OTHER" | while IFS= read -r f; do [[ -n "$f" ]] && bullet "$f"; done
    fi

    echo ""

    # Offer to show full diff for system files
    SYS_FILES_FOR_DIFF=""
    [[ -n "$CHANGED_SCRIPTS" ]] && SYS_FILES_FOR_DIFF="${SYS_FILES_FOR_DIFF}${CHANGED_SCRIPTS}"
    [[ -n "$CHANGED_SYSTEM" ]] && SYS_FILES_FOR_DIFF="${SYS_FILES_FOR_DIFF}${CHANGED_SYSTEM}"
    [[ -n "$CHANGED_CATALOG" ]] && SYS_FILES_FOR_DIFF="${SYS_FILES_FOR_DIFF}${CHANGED_CATALOG}"
    [[ -n "$CHANGED_OTHER" ]] && SYS_FILES_FOR_DIFF="${SYS_FILES_FOR_DIFF}${CHANGED_OTHER}"

    if [[ -n "$SYS_FILES_FOR_DIFF" ]]; then
        if ask_yes_no "Want to see the full diff?" "N"; then
            echo ""
            printf "$SYS_FILES_FOR_DIFF" | while IFS= read -r file; do
                file=$(echo "$file" | sed 's/^[[:space:]]*//')
                [[ -z "$file" ]] && continue
                printf "\n  ${CYAN}${BOLD}── %s ──${NC}\n\n" "$file"
                git diff "${OLD_HEAD}..${NEW_HEAD}" -- "$file" 2>/dev/null | while IFS= read -r line; do
                    case "$line" in
                        +*)   printf "  ${GREEN}%s${NC}\n" "$line" ;;
                        -*)   printf "  ${YELLOW}%s${NC}\n" "$line" ;;
                        @*)   printf "  ${CYAN}%s${NC}\n" "$line" ;;
                        diff*|index*|---*|+++*) ;; # skip noise
                        *)    printf "  %s\n" "$line" ;;
                    esac
                done
            done
            echo ""
        fi
    fi
fi

# =========================================================
# STEP 2 OF 4: Your Local Skill Changes
# =========================================================
echo ""
printf "${CYAN}${BOLD}═══════════════════════════════════════════════${NC}\n"
printf "${CYAN}${BOLD}  Step 2: Your Local Changes${NC}\n"
printf "${CYAN}${BOLD}═══════════════════════════════════════════════${NC}\n"
echo ""

SKILL_REVIEW_MSG=""

# --- User-created skills (always shown first and prominently) ---
if [[ ${#USER_CREATED_SKILLS[@]} -gt 0 ]]; then
    printf "  ${GREEN}${BOLD}★ ${#USER_CREATED_SKILLS[@]} custom skill(s) detected${NC} ${DIM}(yours — never touched by updates):${NC}\n"
    for uc_skill in "${USER_CREATED_SKILLS[@]}"; do
        printf "    ${GREEN}✓${NC} ${BOLD}%s${NC}\n" "$uc_skill"
    done
    echo ""
fi

# --- Modified upstream skills ---
if [[ ${#MODIFIED_SKILLS[@]} -eq 0 ]] && [[ ${#USER_CREATED_SKILLS[@]} -eq 0 ]]; then
    ok "No local skill modifications detected."
    info "All your installed skills match the upstream versions."
    echo ""
elif [[ ${#MODIFIED_SKILLS[@]} -eq 0 ]]; then
    ok "No modifications to upstream skills."
    echo ""
fi

if [[ ${#MODIFIED_SKILLS[@]} -gt 0 ]]; then
    info "You've modified ${#MODIFIED_SKILLS[@]} skill(s) locally:"
    for i in "${!MODIFIED_SKILLS[@]}"; do
        IFS='|' read -ra files <<< "${MODIFIED_SKILL_FILES[$i]}"
        printf "    ${YELLOW}~${NC} ${BOLD}%s${NC} ${DIM}(%s)${NC}\n" "${MODIFIED_SKILLS[$i]}" "${files[*]}"
    done
    echo ""

    if $HAS_UPSTREAM_CHANGES; then
        info "We'll check if any of these also changed upstream and walk you through"
        info "each file so you can pick what to keep."
        echo ""
    else
        ok "No upstream changes to these skills — your local versions are kept as-is."
        echo ""
    fi

    for skill_name in "${MODIFIED_SKILLS[@]}"; do
        skill_dir="$REPO_ROOT/.claude/skills/$skill_name"
        backup_skill_dir="$SKILL_BACKUP_DIR/$skill_name"

        # Skill removed upstream
        if [[ ! -d "$skill_dir" ]]; then
            warn "$skill_name was removed upstream, but you had local changes."
            mkdir -p "$skill_dir"
            cp -r "$backup_skill_dir"/* "$skill_dir/" 2>/dev/null || true
            ok "Kept your version of $skill_name"
            SKILL_REVIEW_MSG="${SKILL_REVIEW_MSG}\n    ${YELLOW}~${NC} $skill_name: kept (removed upstream)"
            continue
        fi

        echo "  ─────────────────────────────────────────"
        printf "  ${BOLD}%s${NC}\n" "$skill_name"
        echo "  ─────────────────────────────────────────"

        # Find file-level differences
        changed_files=$(diff -rq "$backup_skill_dir" "$skill_dir" 2>/dev/null | grep "^Files " | sed 's/^Files //;s/ and / → /;s/ differ$//' || true)
        new_upstream=$(diff -rq "$backup_skill_dir" "$skill_dir" 2>/dev/null | grep "^Only in $skill_dir" | sed "s|^Only in $skill_dir[/]*: ||" || true)
        removed_upstream=$(diff -rq "$backup_skill_dir" "$skill_dir" 2>/dev/null | grep "^Only in $backup_skill_dir" | sed "s|^Only in $backup_skill_dir[/]*: ||" || true)

        if [[ -z "$changed_files" ]] && [[ -z "$new_upstream" ]] && [[ -z "$removed_upstream" ]]; then
            echo ""
            info "No upstream changes to this skill — keeping your version."
            cp -r "$backup_skill_dir"/* "$skill_dir/" 2>/dev/null || true
            # Mark all modified files in this skill as reviewed
            for rf in $(git diff --name-only -- ".claude/skills/$skill_name/" 2>/dev/null || true); do
                mark_reviewed "$rf"
            done
            SKILL_REVIEW_MSG="${SKILL_REVIEW_MSG}\n    ${GREEN}✓${NC} $skill_name: kept yours (no upstream changes)"
            echo ""
            continue
        fi

        # Track decisions
        file_decisions=""
        accepted_count=0
        kept_count=0

        # --- Per-file review with 3-way analysis ---
        # Compare each changed file against the common ancestor (OLD_HEAD)
        # to show exactly who changed what and offer merge when possible.
        if [[ -n "$changed_files" ]]; then
            while IFS= read -r pair; do
                backup_file=$(echo "$pair" | sed 's/ → .*//')
                upstream_file=$(echo "$pair" | sed 's/.* → //')
                rel_name=$(echo "$upstream_file" | sed "s|$skill_dir/||;s|$skill_dir||")
                [[ -z "$rel_name" ]] && rel_name=$(basename "$upstream_file")

                # Get common ancestor from pre-pull commit
                ANCESTOR_TMP=$(mktemp)
                rel_git_path=".claude/skills/$skill_name/$rel_name"
                git show "${OLD_HEAD}:${rel_git_path}" > "$ANCESTOR_TMP" 2>/dev/null || echo "" > "$ANCESTOR_TMP"

                # Compute who changed what relative to ancestor
                upstream_diff=$(diff -u "$ANCESTOR_TMP" "$upstream_file" 2>/dev/null | tail -n +3 || true)
                your_diff=$(diff -u "$ANCESTOR_TMP" "$backup_file" 2>/dev/null | tail -n +3 || true)

                has_upstream=false; [[ -n "$upstream_diff" ]] && has_upstream=true
                has_yours=false; [[ -n "$your_diff" ]] && has_yours=true

                # Handle bulk decisions from a previous iteration
                if [[ "${ACCEPT_ALL_REMAINING:-false}" == "true" ]]; then
                    ok "Accepted upstream: $rel_name"
                    file_decisions="${file_decisions}\n    ${GREEN}✓${NC} $rel_name (accepted upstream)"
                    accepted_count=$((accepted_count + 1))
                    mark_reviewed "$rel_git_path"
                    rm -f "$ANCESTOR_TMP"
                    continue
                fi
                if [[ "${KEEP_ALL_REMAINING:-false}" == "true" ]]; then
                    cp "$backup_file" "$upstream_file" 2>/dev/null || true
                    ok "Kept yours: $rel_name"
                    file_decisions="${file_decisions}\n    ${YELLOW}○${NC} $rel_name (kept yours)"
                    kept_count=$((kept_count + 1))
                    mark_reviewed "$rel_git_path"
                    rm -f "$ANCESTOR_TMP"
                    continue
                fi

                # If only you changed (upstream didn't touch it), auto-keep yours
                if ! $has_upstream && $has_yours; then
                    cp "$backup_file" "$upstream_file" 2>/dev/null || true
                    ok "Kept yours: $rel_name ${DIM}(upstream didn't change this file)${NC}"
                    file_decisions="${file_decisions}\n    ${YELLOW}○${NC} $rel_name (kept yours — upstream unchanged)"
                    kept_count=$((kept_count + 1))
                    mark_reviewed "$rel_git_path"
                    rm -f "$ANCESTOR_TMP"
                    continue
                fi

                echo ""
                printf "  ${BOLD}File: %s${NC}\n" "$rel_name"
                echo "  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

                # Show upstream changes (labeled)
                if $has_upstream; then
                    printf "\n  ${GREEN}${BOLD}  Upstream changes:${NC}\n"
                    echo "$upstream_diff" | while IFS= read -r line; do
                        case "$line" in
                            @@*)  printf "    ${CYAN}%s${NC}\n" "$line" ;;
                            +*)   printf "    ${GREEN}%s${NC}\n" "$line" ;;
                            -*)   printf "    ${RED}%s${NC}\n" "$line" ;;
                            *)    ;;
                        esac
                    done
                fi

                # Show your changes (labeled)
                if $has_yours; then
                    printf "\n  ${YELLOW}${BOLD}  Your changes:${NC}\n"
                    echo "$your_diff" | while IFS= read -r line; do
                        case "$line" in
                            @@*)  printf "    ${CYAN}%s${NC}\n" "$line" ;;
                            +*)   printf "    ${YELLOW}%s${NC}\n" "$line" ;;
                            -*)   printf "    ${RED}%s${NC}\n" "$line" ;;
                            *)    ;;
                        esac
                    done
                fi

                # Try 3-way merge to see if changes are compatible
                can_merge=false
                MERGED_TMP=$(mktemp)
                if $has_upstream && $has_yours; then
                    cp "$backup_file" "$MERGED_TMP"
                    if git merge-file -q "$MERGED_TMP" "$ANCESTOR_TMP" "$upstream_file" 2>/dev/null; then
                        can_merge=true
                    fi
                fi
                rm -f "$ANCESTOR_TMP"

                # Present options based on what changed and whether merge is possible
                echo ""
                if $has_upstream && $has_yours && $can_merge; then
                    printf "  ${GREEN}✓ No conflict${NC} — both sets of changes can be merged.\n"
                    echo ""
                    printf "  ${BOLD}What to do?${NC}\n"
                    printf "  ${DIM}m = merge both  u = upstream only  y = yours only  a = all upstream  k = keep all yours${NC}\n"
                elif $has_upstream && $has_yours; then
                    printf "  ${YELLOW}⚠ Conflict${NC} — both sides changed the same lines.\n"
                    echo ""
                    printf "  ${BOLD}What to do?${NC}\n"
                    printf "  ${DIM}u = upstream only  y = yours only  a = all upstream  k = keep all yours${NC}\n"
                else
                    # Only upstream changed (user didn't modify this file)
                    printf "  ${DIM}Only upstream changed this file.${NC}\n"
                    echo ""
                    printf "  ${BOLD}Accept upstream change?${NC}\n"
                    printf "  ${DIM}u = accept upstream  y = revert to yours  a = all upstream  k = keep all yours${NC}\n"
                fi

                printf "  > "
                while true; do
                    read -r choice < /dev/tty
                    case "$choice" in
                        [mM])
                            if $can_merge; then
                                cp "$MERGED_TMP" "$upstream_file"
                                ok "Merged both: $rel_name"
                                file_decisions="${file_decisions}\n    ${GREEN}⊕${NC} $rel_name (merged both)"
                                accepted_count=$((accepted_count + 1))
                            else
                                printf "  Can't merge — changes conflict. Pick u or y: "
                                continue
                            fi
                            break ;;
                        [uU])
                            ok "Accepted upstream: $rel_name"
                            file_decisions="${file_decisions}\n    ${GREEN}✓${NC} $rel_name (accepted upstream)"
                            accepted_count=$((accepted_count + 1))
                            break ;;
                        [yY])
                            cp "$backup_file" "$upstream_file" 2>/dev/null || true
                            ok "Kept yours: $rel_name"
                            file_decisions="${file_decisions}\n    ${YELLOW}○${NC} $rel_name (kept yours)"
                            kept_count=$((kept_count + 1))
                            break ;;
                        [aA])
                            ok "Accepted upstream: $rel_name"
                            file_decisions="${file_decisions}\n    ${GREEN}✓${NC} $rel_name (accepted upstream)"
                            accepted_count=$((accepted_count + 1))
                            ACCEPT_ALL_REMAINING=true
                            break ;;
                        [kK])
                            cp "$backup_file" "$upstream_file" 2>/dev/null || true
                            ok "Kept yours: $rel_name"
                            file_decisions="${file_decisions}\n    ${YELLOW}○${NC} $rel_name (kept yours)"
                            kept_count=$((kept_count + 1))
                            KEEP_ALL_REMAINING=true
                            break ;;
                        *)
                            if $can_merge; then
                                printf "  Please enter m, u, y, a, or k: "
                            else
                                printf "  Please enter u, y, a, or k: "
                            fi ;;
                    esac
                done
                mark_reviewed "$rel_git_path"
                rm -f "$MERGED_TMP"
            done <<< "$changed_files"
            ACCEPT_ALL_REMAINING=false
            KEEP_ALL_REMAINING=false
        fi

        # New files added upstream
        if [[ -n "$new_upstream" ]]; then
            while IFS= read -r new_file; do
                [[ -z "$new_file" ]] && continue
                printf "\n  ${GREEN}+${NC} %s ${DIM}(new from upstream)${NC}\n" "$new_file"
                file_decisions="${file_decisions}\n    ${GREEN}+${NC} $new_file (new from upstream)"
                accepted_count=$((accepted_count + 1))
            done <<< "$new_upstream"
        fi

        # Files removed upstream
        if [[ -n "$removed_upstream" ]]; then
            while IFS= read -r rm_file; do
                [[ -z "$rm_file" ]] && continue
                printf "\n  ${YELLOW}−${NC} %s ${DIM}(removed upstream — kept your version)${NC}\n" "$rm_file"
                cp "$backup_skill_dir/$rm_file" "$skill_dir/$rm_file" 2>/dev/null || true
                file_decisions="${file_decisions}\n    ${YELLOW}○${NC} $rm_file (kept yours, removed upstream)"
                kept_count=$((kept_count + 1))
            done <<< "$removed_upstream"
        fi

        echo ""
        SKILL_REVIEW_MSG="${SKILL_REVIEW_MSG}\n    ${BOLD}$skill_name${NC}: $accepted_count accepted, $kept_count kept"
        printf "$file_decisions\n"
    done
    echo ""
fi

# =========================================================
# Review other modified files (non-skill, non-protected)
# =========================================================
OTHER_REVIEW_MSG=""

if [[ ${#OTHER_MODIFIED_FILES[@]} -gt 0 ]] && $HAS_UPSTREAM_CHANGES; then
    # Check which of these files also changed upstream
    OTHER_CONFLICT_FILES=()
    OTHER_NOCONFLICT_FILES=()
    for file in "${OTHER_MODIFIED_FILES[@]}"; do
        if echo "$CHANGED_FILES" | grep -qx "$file" 2>/dev/null; then
            OTHER_CONFLICT_FILES+=("$file")
        else
            OTHER_NOCONFLICT_FILES+=("$file")
        fi
    done

    # Auto-restore files that didn't change upstream and mark reviewed
    for file in "${OTHER_NOCONFLICT_FILES[@]}"; do
        cp "$OTHER_BACKUP_DIR/$file" "$REPO_ROOT/$file" 2>/dev/null || true
        mark_reviewed "$file"
    done

    # Review files that changed both locally and upstream
    if [[ ${#OTHER_CONFLICT_FILES[@]} -gt 0 ]]; then
        echo ""
        printf "${CYAN}${BOLD}═══════════════════════════════════════════════${NC}\n"
        printf "${CYAN}${BOLD}  Your Local File Changes${NC}\n"
        printf "${CYAN}${BOLD}═══════════════════════════════════════════════${NC}\n"
        echo ""
        info "${#OTHER_CONFLICT_FILES[@]} file(s) you edited also changed upstream:"
        echo ""

        ACCEPT_ALL_OTHER=false
        KEEP_ALL_OTHER=false

        for file in "${OTHER_CONFLICT_FILES[@]}"; do
            backup_file="$OTHER_BACKUP_DIR/$file"
            upstream_file="$REPO_ROOT/$file"

            # Handle bulk decisions
            if [[ "$ACCEPT_ALL_OTHER" == "true" ]]; then
                ok "Accepted upstream: $file"
                OTHER_REVIEW_MSG="${OTHER_REVIEW_MSG}\n    ${GREEN}✓${NC} $file (accepted upstream)"
                mark_reviewed "$file"
                continue
            fi
            if [[ "$KEEP_ALL_OTHER" == "true" ]]; then
                cp "$backup_file" "$upstream_file" 2>/dev/null || true
                ok "Kept yours: $file"
                OTHER_REVIEW_MSG="${OTHER_REVIEW_MSG}\n    ${YELLOW}○${NC} $file (kept yours)"
                mark_reviewed "$file"
                continue
            fi

            # 3-way diff: ancestor (OLD_HEAD) vs upstream (new) vs yours (backup)
            ANCESTOR_TMP=$(mktemp)
            git show "${OLD_HEAD}:${file}" > "$ANCESTOR_TMP" 2>/dev/null || echo "" > "$ANCESTOR_TMP"

            upstream_diff=$(diff -u "$ANCESTOR_TMP" "$upstream_file" 2>/dev/null | tail -n +3 || true)
            your_diff=$(diff -u "$ANCESTOR_TMP" "$backup_file" 2>/dev/null | tail -n +3 || true)

            has_upstream=false; [[ -n "$upstream_diff" ]] && has_upstream=true
            has_yours=false; [[ -n "$your_diff" ]] && has_yours=true

            echo "  ─────────────────────────────────────────"
            printf "  ${BOLD}%s${NC}\n" "$file"
            echo "  ─────────────────────────────────────────"

            if $has_upstream; then
                printf "\n  ${GREEN}${BOLD}  Upstream changes:${NC}\n"
                echo "$upstream_diff" | while IFS= read -r line; do
                    case "$line" in
                        @@*)  printf "    ${CYAN}%s${NC}\n" "$line" ;;
                        +*)   printf "    ${GREEN}%s${NC}\n" "$line" ;;
                        -*)   printf "    ${RED}%s${NC}\n" "$line" ;;
                        *)    ;;
                    esac
                done
            fi

            if $has_yours; then
                printf "\n  ${YELLOW}${BOLD}  Your changes:${NC}\n"
                echo "$your_diff" | while IFS= read -r line; do
                    case "$line" in
                        @@*)  printf "    ${CYAN}%s${NC}\n" "$line" ;;
                        +*)   printf "    ${YELLOW}%s${NC}\n" "$line" ;;
                        -*)   printf "    ${RED}%s${NC}\n" "$line" ;;
                        *)    ;;
                    esac
                done
            fi

            # Try 3-way merge
            can_merge=false
            MERGED_TMP=$(mktemp)
            if $has_upstream && $has_yours; then
                cp "$backup_file" "$MERGED_TMP"
                if git merge-file -q "$MERGED_TMP" "$ANCESTOR_TMP" "$upstream_file" 2>/dev/null; then
                    can_merge=true
                fi
            fi
            rm -f "$ANCESTOR_TMP"

            echo ""
            if $has_upstream && $has_yours && $can_merge; then
                printf "  ${GREEN}✓ No conflict${NC} — both sets of changes can be merged.\n"
                echo ""
                printf "  ${BOLD}What to do?${NC}\n"
                printf "  ${DIM}m = merge both  u = upstream only  y = yours only  a = all upstream  k = keep all yours${NC}\n"
            elif $has_upstream && $has_yours; then
                printf "  ${YELLOW}⚠ Conflict${NC} — both sides changed the same lines.\n"
                echo ""
                printf "  ${BOLD}What to do?${NC}\n"
                printf "  ${DIM}u = upstream only  y = yours only  a = all upstream  k = keep all yours${NC}\n"
            else
                printf "  ${DIM}Only upstream changed this file.${NC}\n"
                echo ""
                printf "  ${BOLD}Accept upstream change?${NC}\n"
                printf "  ${DIM}u = accept upstream  y = revert to yours  a = all upstream  k = keep all yours${NC}\n"
            fi

            printf "  > "
            while true; do
                read -r choice < /dev/tty
                case "$choice" in
                    [mM])
                        if $can_merge; then
                            cp "$MERGED_TMP" "$upstream_file"
                            ok "Merged both: $file"
                            OTHER_REVIEW_MSG="${OTHER_REVIEW_MSG}\n    ${GREEN}⊕${NC} $file (merged both)"
                        else
                            printf "  Can't merge — changes conflict. Pick u or y: "
                            continue
                        fi
                        break ;;
                    [uU])
                        ok "Accepted upstream: $file"
                        OTHER_REVIEW_MSG="${OTHER_REVIEW_MSG}\n    ${GREEN}✓${NC} $file (accepted upstream)"
                        break ;;
                    [yY])
                        cp "$backup_file" "$upstream_file" 2>/dev/null || true
                        ok "Kept yours: $file"
                        OTHER_REVIEW_MSG="${OTHER_REVIEW_MSG}\n    ${YELLOW}○${NC} $file (kept yours)"
                        break ;;
                    [aA])
                        ok "Accepted upstream: $file"
                        OTHER_REVIEW_MSG="${OTHER_REVIEW_MSG}\n    ${GREEN}✓${NC} $file (accepted upstream)"
                        ACCEPT_ALL_OTHER=true
                        break ;;
                    [kK])
                        cp "$backup_file" "$upstream_file" 2>/dev/null || true
                        ok "Kept yours: $file"
                        OTHER_REVIEW_MSG="${OTHER_REVIEW_MSG}\n    ${YELLOW}○${NC} $file (kept yours)"
                        KEEP_ALL_OTHER=true
                        break ;;
                    *)
                        if $can_merge; then
                            printf "  Please enter m, u, y, a, or k: "
                        else
                            printf "  Please enter u, y, a, or k: "
                        fi ;;
                esac
            done
            mark_reviewed "$file"
            rm -f "$MERGED_TMP"
        done
        echo ""
    fi
elif [[ ${#OTHER_MODIFIED_FILES[@]} -gt 0 ]]; then
    # No upstream changes — just restore all local modifications and mark reviewed
    for file in "${OTHER_MODIFIED_FILES[@]}"; do
        cp "$OTHER_BACKUP_DIR/$file" "$REPO_ROOT/$file" 2>/dev/null || true
        mark_reviewed "$file"
    done
fi

# =========================================================
# Restore stashed protected files
# =========================================================
if $STASHED; then
    if git stash pop --quiet 2>/dev/null; then
        : # silently restored
    else
        warn "Merge conflicts detected — backing up your versions..."
        mkdir -p "$BACKUP_DIR"

        CONFLICTED=$(git diff --name-only --diff-filter=U 2>/dev/null || true)
        if [[ -n "$CONFLICTED" ]]; then
            while IFS= read -r file; do
                backup_path="$BACKUP_DIR/$file"
                mkdir -p "$(dirname "$backup_path")"
                cp "$REPO_ROOT/$file" "$backup_path.conflicted" 2>/dev/null || true
                git checkout --theirs -- "$file" 2>/dev/null || true
                git add "$file" 2>/dev/null || true
            done <<< "$CONFLICTED"
        fi
        git stash drop 2>/dev/null || true
    fi
fi

# =========================================================
# Gate new skills: remove any that arrived via pull but
# aren't in installed.json — they'll be offered in Step 3
# =========================================================
REMOVED_SKILLS_MSG=""

if $HAVE_INSTALLED_JSON && [[ -f "$INSTALLED" ]] && [[ -f "$CATALOG" ]]; then
    # Python computes which skill folders should be removed:
    # 1. Skills in removed_skills (user previously declined)
    # 2. NEW catalog skills that arrived via pull but aren't in installed_skills
    #    (user hasn't chosen them yet — offer in Step 3 instead)
    SKILLS_TO_REMOVE=$("${PYTHON_CMD[@]}" -c "
import json, sys, os
try:
    with open('$INSTALLED') as f:
        inst = json.load(f)
    with open('$CATALOG') as f:
        cat = json.load(f)

    installed = set(inst.get('installed_skills', []))
    removed = set(inst.get('removed_skills', []))
    core = set(cat.get('core_skills', []))
    catalog_skills = set(cat.get('skills', {}).keys())
    known = installed | removed | core

    # Previously removed — always re-remove
    for s in sorted(removed):
        print(f'{s}|removed')

    # New catalog skills not yet in installed.json — remove from disk so
    # they appear as installable in Step 3 rather than auto-installing
    for s in sorted(catalog_skills - known):
        skill_dir = os.path.join('$REPO_ROOT', '.claude', 'skills', s)
        if os.path.isdir(skill_dir):
            print(f'{s}|new')
except Exception:
    sys.exit(0)
" 2>/dev/null || true)

    if [[ -n "$SKILLS_TO_REMOVE" ]]; then
        while IFS='|' read -r skill reason; do
            [[ -z "$skill" ]] && continue
            skill_dir="$REPO_ROOT/.claude/skills/$skill"
            if [[ -d "$skill_dir" ]]; then
                rm -rf "$skill_dir"
                if [[ "$reason" == "removed" ]]; then
                    REMOVED_SKILLS_MSG="${REMOVED_SKILLS_MSG}\n    ${DIM}✗ $skill (re-removed per your preference)${NC}"
                fi
                # 'new' skills are silently removed — they'll show in Step 3
            fi
        done <<< "$SKILLS_TO_REMOVE"
    fi
elif $HAVE_INSTALLED_JSON && [[ -f "$INSTALLED" ]]; then
    # Fallback: no catalog, just re-remove previously removed skills
    REMOVED_SKILLS=$("${PYTHON_CMD[@]}" -c "
import json, sys
try:
    with open('$INSTALLED') as f:
        data = json.load(f)
    for s in data.get('removed_skills', []):
        print(s)
except Exception:
    sys.exit(0)
" 2>/dev/null || true)

    if [[ -n "$REMOVED_SKILLS" ]]; then
        while IFS= read -r skill; do
            skill_dir="$REPO_ROOT/.claude/skills/$skill"
            if [[ -d "$skill_dir" ]]; then
                rm -rf "$skill_dir"
                REMOVED_SKILLS_MSG="${REMOVED_SKILLS_MSG}\n    ${DIM}✗ $skill (re-removed per your preference)${NC}"
            fi
        done <<< "$REMOVED_SKILLS"
    fi
fi

# =========================================================
# STEP 3 OF 4: Skill Catalog
# =========================================================
echo ""
printf "${CYAN}${BOLD}═══════════════════════════════════════════════${NC}\n"
printf "${CYAN}${BOLD}  Step 3: Skill Catalog${NC}\n"
printf "${CYAN}${BOLD}═══════════════════════════════════════════════${NC}\n"
echo ""

INSTALLED_NEW_SKILLS_MSG=""

if [[ -f "$CATALOG" ]]; then
    # Python outputs two sections separated by "---":
    #   Section 1: NEW skills (never seen before) — name|category|desc|services|deps
    #   Section 2: AVAILABLE skills (previously removed, not installed) — same format
    CATALOG_OUTPUT=$("${PYTHON_CMD[@]}" -c "
import json, sys, os

catalog_path = '$CATALOG'
installed_path = '$INSTALLED'

with open(catalog_path) as f:
    catalog = json.load(f)

catalog_skills = catalog.get('skills', {})
core_skills = set(catalog.get('core_skills', []))

if os.path.exists(installed_path):
    with open(installed_path) as f:
        inst = json.load(f)
    installed = set(inst.get('installed_skills', []))
    removed = set(inst.get('removed_skills', []))
else:
    installed = set()
    removed = set()

known = installed | removed | core_skills
new_skills = set(catalog_skills.keys()) - known
available_skills = removed  # previously removed = available but not installed

order = {'utility': 1, 'strategy': 2, 'execution': 3, 'visual': 4, 'operations': 5}

def format_skill(name):
    info = catalog_skills[name]
    services = ','.join(info.get('requires_services', []))
    deps = ','.join(info.get('dependencies', []))
    return f'{name}|{info[\"category\"]}|{info[\"description\"]}|{services}|{deps}'

# New skills
for s in sorted(new_skills, key=lambda n: (order.get(catalog_skills[n].get('category',''), 99), n)):
    print(format_skill(s))
print('---')
# Available (previously removed)
for s in sorted(available_skills, key=lambda n: (order.get(catalog_skills.get(n,{}).get('category',''), 99), n)):
    if s in catalog_skills:
        print(format_skill(s))
" 2>/dev/null || true)

    # Split into new and available
    NEW_SKILLS=$(echo "$CATALOG_OUTPUT" | sed '/^---$/,$d')
    AVAILABLE_SKILLS=$(echo "$CATALOG_OUTPUT" | sed '1,/^---$/d')

    # --- New skills section ---
    if [[ -n "$NEW_SKILLS" ]] && [[ "$NEW_SKILLS" != "" ]]; then
        ok "New skills added since your last update:"
        echo ""

        declare -a NS_NAMES=()
        declare -a NS_CATEGORIES=()
        declare -a NS_DESCRIPTIONS=()
        declare -a NS_SERVICES=()
        declare -a NS_DEPS=()
        CURRENT_CATEGORY=""

        while IFS='|' read -r name category description services deps; do
            [[ -z "$name" ]] && continue
            NS_NAMES+=("$name")
            NS_CATEGORIES+=("$category")
            NS_DESCRIPTIONS+=("$description")
            NS_SERVICES+=("$services")
            NS_DEPS+=("$deps")
        done <<< "$NEW_SKILLS"

        for i in "${!NS_NAMES[@]}"; do
            NUM=$((i + 1))
            cat="${NS_CATEGORIES[$i]}"

            if [[ "$cat" != "$CURRENT_CATEGORY" ]]; then
                first="$(echo "${cat:0:1}" | tr '[:lower:]' '[:upper:]')"
                printf "\n    ${BOLD}%s${NC}\n" "${first}${cat:1}"
                CURRENT_CATEGORY="$cat"
            fi

            svc_note=""
            [[ -n "${NS_SERVICES[$i]}" ]] && svc_note=" ${DIM}(needs ${NS_SERVICES[$i]})${NC}"
            dep_note=""
            [[ -n "${NS_DEPS[$i]}" ]] && dep_note=" ${DIM}(auto-adds: ${NS_DEPS[$i]})${NC}"

            printf "     ${BOLD}[%2d]${NC} %-26s ${DIM}— %s${NC}%b%b\n" \
                "$NUM" "${NS_NAMES[$i]}" "${NS_DESCRIPTIONS[$i]}" "$svc_note" "$dep_note"
        done
        echo ""

        printf "  Enter numbers to install (e.g. ${BOLD}1 3${NC}), ${BOLD}all${NC}, or press Enter to skip: "
        read -r NS_INPUT < /dev/tty

        if [[ -n "$NS_INPUT" ]]; then
            SELECTED_NS=()
            if echo "$NS_INPUT" | grep -qi "^all$"; then
                SELECTED_NS=("${NS_NAMES[@]}")
            else
                for token in $NS_INPUT; do
                    if [[ "$token" =~ ^[0-9]+$ ]] && [[ "$token" -ge 1 ]] && [[ "$token" -le "${#NS_NAMES[@]}" ]]; then
                        SELECTED_NS+=("${NS_NAMES[$((token - 1))]}")
                    else
                        warn "Ignoring invalid selection: $token"
                    fi
                done
            fi

            if [[ ${#SELECTED_NS[@]} -gt 0 ]]; then
                echo ""
                for ns in "${SELECTED_NS[@]}"; do
                    bash "$REPO_ROOT/scripts/add-skill.sh" "$ns" 2>&1 | sed 's/^/    /'
                    INSTALLED_NEW_SKILLS_MSG="${INSTALLED_NEW_SKILLS_MSG}\n    ${GREEN}✓${NC} $ns"
                done
                echo ""
            fi
        else
            echo ""
        fi
    else
        ok "No new skills since your last update."
        echo ""
    fi

    # --- Available (not installed) skills section ---
    if [[ -n "$AVAILABLE_SKILLS" ]] && [[ "$AVAILABLE_SKILLS" != "" ]]; then
        AVAIL_COUNT=$(echo "$AVAILABLE_SKILLS" | grep -c '|' || true)
        echo ""
        info "You also have ${BOLD}${AVAIL_COUNT} skill(s)${NC} ${CYAN}available that you haven't installed:${NC}"
        echo ""

        declare -a AV_NAMES=()
        declare -a AV_CATEGORIES=()
        declare -a AV_DESCRIPTIONS=()
        declare -a AV_SERVICES=()
        declare -a AV_DEPS=()
        CURRENT_CATEGORY=""

        while IFS='|' read -r name category description services deps; do
            [[ -z "$name" ]] && continue
            AV_NAMES+=("$name")
            AV_CATEGORIES+=("$category")
            AV_DESCRIPTIONS+=("$description")
            AV_SERVICES+=("$services")
            AV_DEPS+=("$deps")
        done <<< "$AVAILABLE_SKILLS"

        for i in "${!AV_NAMES[@]}"; do
            NUM=$((i + 1))
            cat="${AV_CATEGORIES[$i]}"

            if [[ "$cat" != "$CURRENT_CATEGORY" ]]; then
                first="$(echo "${cat:0:1}" | tr '[:lower:]' '[:upper:]')"
                printf "\n    ${BOLD}%s${NC}\n" "${first}${cat:1}"
                CURRENT_CATEGORY="$cat"
            fi

            svc_note=""
            [[ -n "${AV_SERVICES[$i]}" ]] && svc_note=" ${DIM}(needs ${AV_SERVICES[$i]})${NC}"
            dep_note=""
            [[ -n "${AV_DEPS[$i]}" ]] && dep_note=" ${DIM}(auto-adds: ${AV_DEPS[$i]})${NC}"

            printf "     ${DIM}[%2d]${NC} %-26s ${DIM}— %s${NC}%b%b\n" \
                "$NUM" "${AV_NAMES[$i]}" "${AV_DESCRIPTIONS[$i]}" "$svc_note" "$dep_note"
        done
        echo ""

        printf "  Enter numbers to install (e.g. ${BOLD}1 3${NC}), ${BOLD}all${NC}, or press Enter to skip: "
        read -r AV_INPUT < /dev/tty

        if [[ -n "$AV_INPUT" ]]; then
            SELECTED_AV=()
            if echo "$AV_INPUT" | grep -qi "^all$"; then
                SELECTED_AV=("${AV_NAMES[@]}")
            else
                for token in $AV_INPUT; do
                    if [[ "$token" =~ ^[0-9]+$ ]] && [[ "$token" -ge 1 ]] && [[ "$token" -le "${#AV_NAMES[@]}" ]]; then
                        SELECTED_AV+=("${AV_NAMES[$((token - 1))]}")
                    else
                        warn "Ignoring invalid selection: $token"
                    fi
                done
            fi

            if [[ ${#SELECTED_AV[@]} -gt 0 ]]; then
                echo ""
                for av in "${SELECTED_AV[@]}"; do
                    bash "$REPO_ROOT/scripts/add-skill.sh" "$av" 2>&1 | sed 's/^/    /'
                    INSTALLED_NEW_SKILLS_MSG="${INSTALLED_NEW_SKILLS_MSG}\n    ${GREEN}✓${NC} $av"
                done
                echo ""
            fi
        else
            echo ""
        fi
    fi
else
    warn "Skill catalog not found — skipping skill check."
    echo ""
fi

# =========================================================
# GSD Framework Sync
# =========================================================
GSD_GLOBAL="$HOME/.claude/commands/gsd"
GSD_LOCAL="$REPO_ROOT/.claude/commands/gsd"
GSD_STATUS=""

if command -v node &>/dev/null; then
    # Migrate local → global if needed
    if [[ -d "$GSD_LOCAL" ]]; then
        rm -rf "$GSD_LOCAL"
        find "$REPO_ROOT/.claude/agents" -name "gsd-*.md" -delete 2>/dev/null || true
        ok "Cleaned up local GSD files (migrating to global)"
    fi

    if [[ -d "$GSD_GLOBAL" ]] && [[ $(ls -1 "$GSD_GLOBAL"/*.md 2>/dev/null | wc -l) -gt 10 ]]; then
        GSD_STATUS="installed globally"
        # Check for GSD updates silently
        CURRENT_GSD=$(npm view get-shit-done-cc version 2>/dev/null || echo "")
        if [[ -n "$CURRENT_GSD" ]]; then
            GSD_STATUS="installed globally (latest: v${CURRENT_GSD})"
        fi
    else
        info "Installing GSD project framework globally..."
        if npx get-shit-done-cc --global --claude 2>/dev/null; then
            ok "GSD installed globally"
            GSD_STATUS="freshly installed (global)"
        else
            warn "GSD install failed — run manually: npx get-shit-done-cc --global --claude"
            GSD_STATUS="failed"
        fi
    fi
else
    if [[ ! -d "$GSD_GLOBAL" ]]; then
        GSD_STATUS="missing (install Node.js first)"
    else
        GSD_STATUS="installed globally (Node.js not found for updates)"
    fi
fi

# =========================================================
# STEP 4 OF 4: Summary
# =========================================================
echo ""
printf "${CYAN}${BOLD}═══════════════════════════════════════════════${NC}\n"
printf "${CYAN}${BOLD}  Step 4: Summary${NC}\n"
printf "${CYAN}${BOLD}═══════════════════════════════════════════════${NC}\n"
echo ""

# Main repo status
NEW_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
if $HAS_UPSTREAM_CHANGES; then
    if [[ -n "$OLD_TAG" ]] && [[ -n "$NEW_TAG" ]] && [[ "$OLD_TAG" != "$NEW_TAG" ]]; then
        ok "Main repo: updated ${OLD_TAG} → ${NEW_TAG}"
    else
        ok "Main repo: pulled ${COMMIT_COUNT} new commit(s)"
    fi

    # Commit log
    CHANGES=$(git log --oneline "${OLD_HEAD}..${NEW_HEAD}" 2>/dev/null | sed 's/^/      /')
    if [[ -n "$CHANGES" ]]; then
        echo "$CHANGES"
    fi
else
    ok "Main repo: already up to date"
fi

# User-created skills in summary
if [[ ${#USER_CREATED_SKILLS[@]} -gt 0 ]]; then
    printf "\n  ${BOLD}Your custom skills:${NC} %s\n" "${USER_CREATED_SKILLS[*]}"
fi

# Skill review results
if [[ -n "$SKILL_REVIEW_MSG" ]]; then
    printf "\n  ${BOLD}Skill review:${NC}"
    printf "$SKILL_REVIEW_MSG\n"
    info "Backups saved to ${BOLD}.backup/${NC} if you change your mind."
elif [[ ${#MODIFIED_SKILLS[@]} -gt 0 ]]; then
    printf "\n"
    ok "Local skill changes: kept as-is (no upstream conflicts)"
fi

# Other file review results
if [[ -n "$OTHER_REVIEW_MSG" ]]; then
    printf "\n  ${BOLD}File review:${NC}"
    printf "$OTHER_REVIEW_MSG\n"
fi

# Newly installed skills
if [[ -n "$INSTALLED_NEW_SKILLS_MSG" ]]; then
    printf "\n  ${BOLD}Newly installed:${NC}"
    printf "$INSTALLED_NEW_SKILLS_MSG\n"
fi

# Re-removed skills
if [[ -n "$REMOVED_SKILLS_MSG" ]]; then
    printf "$REMOVED_SKILLS_MSG\n"
fi

# GSD status
if [[ -n "$GSD_STATUS" ]]; then
    echo ""
    ok "GSD framework: ${GSD_STATUS}"
fi

# Protected files
echo ""
ok "Your data is safe:"
printf "    brand_context/  ${GREEN}✓${NC}   .env  ${GREEN}✓${NC}   context/  ${GREEN}✓${NC}   projects/  ${GREEN}✓${NC}\n"

# ---------- Auto-sync to client folders ----------
if [[ -d "${REPO_ROOT}/clients" ]]; then
    CLIENT_COUNT=0
    for CLIENT_DIR in "${REPO_ROOT}/clients"/*/; do
        [[ -d "$CLIENT_DIR" ]] || continue
        CLIENT_COUNT=$((CLIENT_COUNT + 1))
    done
    if [[ $CLIENT_COUNT -gt 0 ]]; then
        echo ""
        info "Syncing updates to ${CLIENT_COUNT} client folder(s)..."
        bash "${REPO_ROOT}/scripts/update-clients.sh"
    fi
fi

maybe_offer_centre_shortcut_repair

LEGACY_CENTRE_DIR="${REPO_ROOT}/projects/briefs/command-centre"
if [[ -d "$LEGACY_CENTRE_DIR" ]]; then
    print_warning_box_start "Old Command Centre folder found"
    print_warning_box_line "You still have an older local copy at projects/briefs/command-centre/."
    print_warning_box_line "Agentic OS now uses command-centre/ at the top of this repo."
    print_warning_box_line "Nothing is broken. The old folder is not used anymore."
    print_warning_box_line "You can delete it later after you confirm the new Command Centre works."
    print_warning_box_end
fi

echo ""
printf "${CYAN}${BOLD}═══════════════════════════════════════════════${NC}\n"
echo ""
