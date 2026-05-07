#!/usr/bin/env bash
# Steps 4–5c: Stash protected files, scan and backup modified skills and other
# tracked files, then prevent merge conflicts from files deleted upstream.

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

git fetch origin "$UPSTREAM_BRANCH" --quiet 2>/dev/null || true

# =========================================================
# Step 5: Scan local skill modifications before pull
# =========================================================
SKILL_BACKUP_DIR="$BACKUP_DIR/skills-${UPDATE_TIMESTAMP}"
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

        # Check for local modifications — always backup and reset, regardless of review state
        modified_files=$(git diff --name-only -- ".claude/skills/$skill_name/" 2>/dev/null || true)
        if [[ -n "$modified_files" ]]; then
            mkdir -p "$SKILL_BACKUP_DIR/$skill_name"
            cp -r "$skill_dir"* "$SKILL_BACKUP_DIR/$skill_name/" 2>/dev/null || true
            MODIFIED_SKILLS+=("$skill_name")
            file_list=$(echo "$modified_files" | while IFS= read -r f; do basename "$f"; done | tr '\n' '|' | sed 's/|$//')
            MODIFIED_SKILL_FILES+=("$file_list")

        fi
    done
fi

# Reset modified skill files to HEAD so git pull won't conflict.
# Migration runs AFTER checkout so git can't overwrite the new SKILL.local.md.
if [[ ${#MODIFIED_SKILLS[@]} -gt 0 ]]; then
    for skill_name in "${MODIFIED_SKILLS[@]}"; do
        git checkout HEAD -- ".claude/skills/$skill_name/" 2>/dev/null || true
        local_md="$REPO_ROOT/.claude/skills/$skill_name/SKILL.local.md"
        backup_md="$SKILL_BACKUP_DIR/$skill_name/SKILL.md"
        if [[ ! -f "$local_md" ]] && [[ -f "$backup_md" ]]; then
            cp "$backup_md" "$local_md" 2>/dev/null || true
            _synth="$SCRIPT_DIR/lib/synthesize.py"
            _base="$REPO_ROOT/.claude/skills/$skill_name/SKILL.md"
            [[ -f "$_synth" ]] && [[ -f "$_base" ]] && "${PYTHON_CMD[@]}" "$_synth" "$local_md" "$_base" 2>/dev/null || true
            ok "Migrated $skill_name → SKILL.local.md"
        fi
    done
fi

# =========================================================
# Step 5b: Stash other modified tracked files (not protected, not skills)
# =========================================================
OTHER_BACKUP_DIR="$BACKUP_DIR/other-${UPDATE_TIMESTAMP}"
OTHER_MODIFIED_FILES=()

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

        mkdir -p "$OTHER_BACKUP_DIR/$(dirname "$file")"
        cp "$REPO_ROOT/$file" "$OTHER_BACKUP_DIR/$file" 2>/dev/null || true
        OTHER_MODIFIED_FILES+=("$file")
    done <<< "$ALL_DIRTY"
fi

# Reset other modified files so git pull won't conflict.
# Migration for CLAUDE.md runs AFTER checkout for the same reason.
if [[ ${#OTHER_MODIFIED_FILES[@]} -gt 0 ]]; then
    for file in "${OTHER_MODIFIED_FILES[@]}"; do
        git checkout HEAD -- "$file" 2>/dev/null || true
        if [[ "$(basename "$file")" == "CLAUDE.md" ]]; then
            _local_md="$REPO_ROOT/$(dirname "$file")/CLAUDE.local.md"
            [[ "$(dirname "$file")" == "." ]] && _local_md="$REPO_ROOT/CLAUDE.local.md"
            if [[ ! -f "$_local_md" ]] && [[ -f "$OTHER_BACKUP_DIR/$file" ]]; then
                cp "$OTHER_BACKUP_DIR/$file" "$_local_md" 2>/dev/null || true
                _synth="$SCRIPT_DIR/lib/synthesize.py"
                _base="$REPO_ROOT/$file"
                [[ -f "$_synth" ]] && [[ -f "$_base" ]] && "${PYTHON_CMD[@]}" "$_synth" "$_local_md" "$_base" 2>/dev/null || true
                ok "Migrated CLAUDE.md → CLAUDE.local.md"
            fi
        fi
    done
fi

