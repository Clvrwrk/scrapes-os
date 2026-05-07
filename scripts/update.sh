#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# Agentic OS — Safe Update Script
# Pulls upstream changes without overwriting user data.
#
# Usage: bash scripts/update.sh
#        bash scripts/update.sh --rollback
# ==========================================================

source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

# --rollback mode — delegate to dedicated script
if [[ "${1:-}" == "--rollback" ]]; then
    exec bash "$SCRIPT_DIR/rollback.sh"
fi

# Python is required for the catalog steps — fail fast here
source "$SCRIPT_DIR/lib/python.sh"
if ! resolve_python_cmd; then
    printf "  ${RED}Python 3 is required for update.sh.${NC}\n"
    exit 1
fi

# =========================================================
# Step 1: Verify we're in a git repo
# =========================================================
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo ""
    printf "  ${RED}Not a git repository.${NC} Run this from the Agentic OS root.\n"
    exit 1
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

# Step 2: Read installed.json
[[ -f "$INSTALLED" ]] && HAVE_INSTALLED_JSON=true || HAVE_INSTALLED_JSON=false

# Step 3: Save current HEAD before any pull
OLD_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
OLD_HEAD=$(git rev-parse HEAD)
LAST_UPDATED=$(git log -1 --format="%cd" --date=format:"%d %b %Y at %H:%M" 2>/dev/null || echo "unknown")

# Steps 4–5c: back up modified files + prevent merge conflicts
source "$SCRIPT_DIR/lib/backup.sh"

# Step 6: pull, nuclear fallback, restore, and display Step 1 of 4
source "$SCRIPT_DIR/lib/pull.sh"

# Step 2 of 4: skill review + other file review + restore stash
source "$SCRIPT_DIR/lib/merge.sh"

# Steps 3–4: gate new skills, catalog, GSD, summary, What's New
source "$SCRIPT_DIR/lib/catalog.sh"
