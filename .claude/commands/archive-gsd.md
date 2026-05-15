# /archive-gsd

Mark a GSD project as complete. Each Level 3 project runs as a workstream inside
`.planning/workstreams/{slug}/`. Archiving completes the workstream and flips the
brief's status — the workstream data is moved to `.planning/milestones/` by GSD.

## What This Does

1. Lists active workstreams via `gsd-tools workstream list`.
2. Asks the user which project to archive (if more than one active).
3. Runs `gsd-tools workstream complete {slug}` — GSD moves the workstream to
   `.planning/milestones/ws-{slug}-{date}/`.
4. Updates the corresponding brief's frontmatter from `status: active` to
   `status: complete`.

## Steps

### Step 1: List active workstreams

Run:
```
node ~/.claude/get-shit-done/bin/gsd-tools.cjs workstream list --raw
```

- **No workstreams / flat mode** → tell the user: "No active GSD project found — nothing to archive."
- **One workstream** → continue to Step 2 with that workstream.
- **Multiple workstreams** → ask the user which one to archive.

### Step 2: Find the matching brief

Look for `projects/briefs/*/brief.md` where the folder slug matches the workstream
name and the brief has `level: 3` and `status: active`.

### Step 3: Confirm with the user

> "I'll archive the GSD project **{workstream-name}**:"
> - Run `workstream complete {workstream-name}` → moves planning state to `.planning/milestones/`
> - Update `projects/briefs/{slug}/brief.md` → `status: complete`
>
> "Go ahead?"

Wait for confirmation before proceeding.

### Step 4: Complete the workstream

Run:
```
node ~/.claude/get-shit-done/bin/gsd-tools.cjs workstream complete {slug} --raw
```

### Step 5: Flip the brief status

Edit the brief's YAML frontmatter: change `status: active` to `status: complete`.

### Step 6: Report

> "Done. **{workstream-name}** is archived."
>
> - Planning state: `.planning/milestones/ws-{slug}-{date}/` (moved by GSD)
> - Brief: `projects/briefs/{slug}/brief.md` (status: complete)
>
> "Other GSD projects are unaffected. Start a new one any time with `/gsd:new-project`."

## Anti-Patterns

- Never delete workstream files manually — always use `workstream complete`.
- Never archive without user confirmation.
- Never assume there's only one active workstream — always check.
