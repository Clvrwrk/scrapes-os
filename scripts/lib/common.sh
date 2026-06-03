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

read_agentic_os_version() {
    local version_file="${1:-$REPO_ROOT/VERSION}"
    local version=""
    if [[ -f "$version_file" ]]; then
        version=$(head -n 1 "$version_file" 2>/dev/null | tr -d '\r' || true)
    fi
    if [[ -z "$version" ]]; then
        printf "unknown\n"
    else
        printf "%s\n" "$version"
    fi
}

format_agentic_os_version() {
    local version="${1:-unknown}"
    if [[ "$version" == "unknown" || -z "$version" ]]; then
        printf "version unknown\n"
    else
        printf "v%s\n" "$version"
    fi
}

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

# ---------- Canonical upstream ----------
# Updates must ALWAYS come from the canonical Agentic OS repo, never from a
# user's backup fork. In the fork workflow `origin` is the user's private fork
# and the canonical repo lives at `upstream`, so we resolve the update remote by
# URL rather than trusting a fixed remote name.
UPSTREAM_SLUG="${AGENTIC_OS_UPSTREAM_SLUG:-simonc602/agentic-os}"

# Echo the name of the first remote whose URL points at the canonical repo.
# Preference order: upstream, origin, then any other remote. Returns 1 if none.
resolve_update_remote() {
    local preferred="upstream origin" remote url seen=" "
    for remote in $preferred $(git remote 2>/dev/null); do
        case "$seen" in *" $remote "*) continue ;; esac
        seen="$seen$remote "
        git remote get-url "$remote" >/dev/null 2>&1 || continue
        url=$(git remote get-url "$remote" 2>/dev/null)
        case "$url" in *"$UPSTREAM_SLUG"*) printf '%s\n' "$remote"; return 0 ;; esac
    done
    return 1
}

# Print copy-pasteable guidance for pointing a remote at the canonical repo.
# Used both when no canonical remote is configured and when a fetch auth fails.
print_upstream_help() {
    local remote="${1:-upstream}"
    echo ""
    printf "${YELLOW}${BOLD}═══════════════════════════════════════════════${NC}\n"
    printf "${YELLOW}${BOLD}  Can't reach the Agentic OS update repo${NC}\n"
    printf "${YELLOW}${BOLD}═══════════════════════════════════════════════${NC}\n"
    echo ""
    warn "Updates come from ${BOLD}${UPSTREAM_SLUG}${NC}, but no working remote points there."
    warn "Your access token may also have been rotated."
    echo ""
    info "To fix this:"
    echo ""
    echo "  1. Get the latest token from:"
    printf "     ${CYAN}https://www.skool.com/scrapes/classroom/d1cfafed?md=552b0ba753df4c738843913fb3eb8312${NC}\n"
    echo ""
    echo "  2. Point a remote at the update repo:"
    if git remote get-url "$remote" >/dev/null 2>&1; then
        printf "     ${BOLD}git remote set-url %s https://<NEW-TOKEN>@github.com/%s.git${NC}\n" "$remote" "$UPSTREAM_SLUG"
    else
        printf "     ${BOLD}git remote add upstream https://<NEW-TOKEN>@github.com/%s.git${NC}\n" "$UPSTREAM_SLUG"
    fi
    echo ""
    echo "  3. Run this script again:"
    printf "     ${BOLD}bash scripts/update.sh${NC}\n"
    echo ""
    info "Nothing was changed — your local files are untouched."
}

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
