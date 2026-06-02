#!/usr/bin/env bash
set -euo pipefail

REAL_REPO="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="${TMPDIR:-/tmp}/agentic-os-memory-setup-test"
trap 'rm -rf "$TEST_ROOT"' EXIT

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

ok() { printf "${GREEN}  ✓ %s${NC}\n" "$1"; }
fail() { printf "${RED}  ✗ %s${NC}\n" "$1" >&2; exit 1; }
info() { printf "${CYAN}%s${NC}\n" "$1"; }

make_fake_repo() {
    rm -rf "$TEST_ROOT"
    mkdir -p "$TEST_ROOT/repo/scripts" "$TEST_ROOT/repo/context/memory" "$TEST_ROOT/repo/brand_context"
    cp "$REAL_REPO/scripts/setup-memory.sh" "$TEST_ROOT/repo/scripts/setup-memory.sh"
    printf "ZILLIZ_URI=https://example.zillizcloud.com\nZILLIZ_TOKEN=test-token\n" > "$TEST_ROOT/repo/.env"
    printf "# Learnings\n" > "$TEST_ROOT/repo/context/learnings.md"
}

make_fake_path() {
    local mode="$1"
    local fake_bin="$TEST_ROOT/bin-$mode"
    mkdir -p "$fake_bin"

    cat > "$fake_bin/uv" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then
  echo "uv 0.0.0-test"
  exit 0
fi
exit 0
EOF

    cat > "$fake_bin/memsearch" <<'EOF'
#!/usr/bin/env bash
LOG_FILE="${MEMSEARCH_LOG:?}"
if [[ "$1" == "--version" ]]; then
  echo "memsearch 0.0.0-test"
  exit 0
fi
printf 'memsearch %s\n' "$*" >> "$LOG_FILE"
exit 0
EOF

    cat > "$fake_bin/claude" <<'EOF'
#!/usr/bin/env bash
LOG_FILE="${CLAUDE_LOG:?}"
if [[ "$1" == "plugin" && "$2" == "list" ]]; then
  if [[ "${CLAUDE_HAS_MEMSEARCH:-0}" == "1" ]]; then
    echo "  > memsearch@zilliztech"
  fi
  exit 0
fi
printf 'claude %s\n' "$*" >> "$LOG_FILE"
exit 0
EOF

    chmod +x "$fake_bin/uv" "$fake_bin/memsearch" "$fake_bin/claude"
    printf '%s\n' "$fake_bin"
}

assert_contains() {
    local file="$1"
    local expected="$2"
    grep -Fq "$expected" "$file" || fail "Expected '$expected' in $file"
}

assert_not_contains() {
    local file="$1"
    local unexpected="$2"
    if grep -Fq "$unexpected" "$file"; then
        fail "Did not expect '$unexpected' in $file"
    fi
}

test_check_mode_no_mutation() {
    make_fake_repo
    local fake_bin
    fake_bin="$(make_fake_path check)"
    local before after
    before="$(cat "$TEST_ROOT/repo/.env")"

    (
        cd "$TEST_ROOT/repo"
        export HOME="$TEST_ROOT/home-check"
        export PATH="$fake_bin:$PATH"
        export MEMSEARCH_LOG="$TEST_ROOT/memsearch-check.log"
        export CLAUDE_LOG="$TEST_ROOT/claude-check.log"
        export CLAUDE_HAS_MEMSEARCH=1
        bash scripts/setup-memory.sh --check >/dev/null
    )

    after="$(cat "$TEST_ROOT/repo/.env")"
    [[ "$before" == "$after" ]] || fail "--check changed .env"
    [[ ! -f "$TEST_ROOT/memsearch-check.log" ]] || fail "--check should not call memsearch config or index"
    ok "--check reports status without mutation"
}

test_initial_index_is_scoped() {
    make_fake_repo
    local fake_bin
    fake_bin="$(make_fake_path index)"

    (
        cd "$TEST_ROOT/repo"
        export HOME="$TEST_ROOT/home-index"
        export PATH="$fake_bin:$PATH"
        export MEMSEARCH_LOG="$TEST_ROOT/memsearch-index.log"
        export CLAUDE_LOG="$TEST_ROOT/claude-index.log"
        printf 'y\n' | bash scripts/setup-memory.sh --target claude >/dev/null
    )

    assert_contains "$TEST_ROOT/memsearch-index.log" "memsearch config set embedding.provider onnx"
    assert_contains "$TEST_ROOT/memsearch-index.log" "memsearch index context/memory/ context/learnings.md brand_context/"
    assert_not_contains "$TEST_ROOT/memsearch-index.log" "memsearch index ."
    assert_contains "$TEST_ROOT/claude-index.log" "claude plugin marketplace add zilliztech/memsearch --scope user"
    assert_contains "$TEST_ROOT/claude-index.log" "claude plugin install memsearch --scope user"
    ok "initial index is limited to memory paths"
}

info "Running memory setup tests..."
test_check_mode_no_mutation
test_initial_index_is_scoped
ok "memory setup tests passed"
