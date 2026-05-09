#!/usr/bin/env bash
# Shared setup sourced by update.sh and rollback.sh.
# Uses BASH_SOURCE so it resolves correctly regardless of the caller's CWD.

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

# ---------- Repo root from this file's location ----------
if [[ -n "${AGENTIC_OS_UPDATE_BOOTSTRAP_REPO_ROOT:-}" ]]; then
    REPO_ROOT="$AGENTIC_OS_UPDATE_BOOTSTRAP_REPO_ROOT"
    case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) REPO_ROOT="$(cygpath -m "$REPO_ROOT")" ;; esac
    SCRIPT_DIR="$REPO_ROOT/scripts"
else
    _COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    SCRIPT_DIR="$(dirname "$_COMMON_DIR")"     # scripts/
    REPO_ROOT="$(dirname "$SCRIPT_DIR")"       # repo root
    case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) REPO_ROOT="$(cygpath -m "$REPO_ROOT")" ;; esac
fi
cd "$REPO_ROOT"

# ---------- Upstream branch ----------
UPSTREAM_BRANCH="${AGENTIC_OS_UPSTREAM_BRANCH:-main}"

# ---------- Key paths ----------
BACKUP_DIR="$REPO_ROOT/.backup"
CATALOG="$REPO_ROOT/.claude/skills/_catalog/catalog.json"
INSTALLED="$REPO_ROOT/.claude/skills/_catalog/installed.json"
REVIEWED_STATE="$BACKUP_DIR/.update-reviewed"
UPDATE_TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)

# ---------- Reviewed-state helpers ----------
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
    if [[ -f "$REVIEWED_STATE" ]]; then
        grep -v "^${file}:" "$REVIEWED_STATE" > "${REVIEWED_STATE}.tmp" 2>/dev/null || true
        mv "${REVIEWED_STATE}.tmp" "$REVIEWED_STATE"
    fi
    echo "${file}:${current_md5}" >> "$REVIEWED_STATE"
}

# ---------- Smart Merge helper ----------
# Merges user's SKILL.md Rules entries into the upstream version.
# Strategy: take upstream as base, inject any user dated entries missing from it.
# Pure Python — deterministic, no LLM dependency, works on all platforms.
smart_merge_file() {
    local user_file="$1"
    local upstream_file="$2"
    local ancestor_file="$3"   # signature-compatible; not used
    local file_type="$4"

    if [[ ! -f "$user_file" ]] || [[ ! -s "$user_file" ]]; then
        warn "Smart Merge: user file missing: $user_file"
        return 1
    fi
    if [[ ! -f "$upstream_file" ]]; then
        warn "Smart Merge: upstream file missing: $upstream_file"
        return 1
    fi

    mkdir -p "$BACKUP_DIR"
    local py_script="$BACKUP_DIR/smart_merge_${UPDATE_TIMESTAMP}.py"

    cat > "$py_script" << 'PYEOF'
import re, sys

user_file, upstream_file = sys.argv[1], sys.argv[2]

try:
    with open(user_file, encoding="utf-8", errors="replace") as f:
        user_lines = f.read().splitlines()
    with open(upstream_file, encoding="utf-8", errors="replace") as f:
        upstream_text = f.read()
    upstream_lines = upstream_text.splitlines()
except Exception as e:
    print("read error: " + str(e), file=sys.stderr)
    sys.exit(1)

# Collect user's dated entries from ## Rules section
user_entries = []
in_rules = False
for line in user_lines:
    if line.strip() == "## Rules":
        in_rules = True
    elif in_rules and line.startswith("## ") and line.strip() != "## Rules":
        break
    elif in_rules and re.match(r"^- \d{4}-\d{2}-\d{2}:", line):
        user_entries.append(line)

# Find entries missing from the upstream version
missing = [e for e in user_entries if e not in upstream_text]
if not missing:
    sys.exit(0)

# Locate end of ## Rules section in upstream (first ## heading or bare --- after it)
insert_at = -1
in_rules = False
for i, line in enumerate(upstream_lines):
    if line.strip() == "## Rules":
        in_rules = True
    elif in_rules:
        if line.startswith("## ") or line.rstrip() == "---":
            insert_at = i
            break

if insert_at == -1:
    print("could not locate Rules section end", file=sys.stderr)
    sys.exit(1)

for entry in missing:
    upstream_lines.insert(insert_at, entry)
    insert_at += 1

try:
    with open(upstream_file, "w", encoding="utf-8") as f:
        f.write("\n".join(upstream_lines))
        if upstream_text.endswith("\n"):
            f.write("\n")
except Exception as e:
    print("write error: " + str(e), file=sys.stderr)
    sys.exit(1)

sys.exit(0)
PYEOF

    local merge_output exit_code
    merge_output=$("${PYTHON_CMD[@]}" "$py_script" "$user_file" "$upstream_file" 2>&1)
    exit_code=$?
    rm -f "$py_script"

    if [[ $exit_code -ne 0 ]]; then
        warn "Smart Merge python error: $merge_output"
        return 1
    fi
}

# ---------- Protected paths (never overwritten) ----------
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
