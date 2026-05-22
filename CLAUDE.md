# CLAUDE.md

This file keeps Claude Code compatible with the shared `AGENTS.md` guidance and adds Claude-only runtime behavior.

@AGENTS.md

---

## Local Overrides

If `CLAUDE.local.md` exists in this directory, **read it now** before anything else. Its `## Rules` entries and any other instructions extend and override this file for the entire session. This file is user-owned and never touched by updates.

---

## Claude Runtime

### Session Type Detection

Scan `brand_context/` for populated `.md` files (ls, not read).
- **No files** → first-run → run `/start-here`
- **Files exist** → returning mode → silent startup (below)

### Returning Mode (silent — zero output)

Do these five steps silently. Do NOT output anything — no greeting, no recap, no capabilities list.

1. Read `context/SOUL.md` (~3 KB). Fall back to `../../context/SOUL.md` if not in the current folder.
2. Read `context/USER.md` (~1.5 KB). Fall back to `../../context/USER.md`.
3. Read today's memory file `context/memory/{YYYY-MM-DD}.md`. Only read yesterday's if today has no prior sessions. If a `### Project` reference exists, load that brief. Note any `### Open threads`.
4. Read `context/MEMORY.md` (~2.5 KB max — curated working scratchpad with Active Threads, Environment Notes, Pending Decisions). Fall back to `../../context/MEMORY.md`. This is a frozen snapshot — mid-session writes persist to disk but only take effect on the next session.
5. Create or append a `## Session N` block in today's memory file. Scan `.claude/skills/` silently (ls only).

**What NOT to do at startup (deferred to wrap-up or on-demand):**
- Do NOT read `brand_context/` files — skills lazy-load these per Context Matrix when needed
- Do NOT read `context/learnings.md` — only loaded per-skill during execution
- Do NOT read yesterday's memory if today already has session blocks
- Do NOT flag stale `brand_context/` files — deferred to wrap-up
- Do NOT scan and report active projects — only load if memory references one
- Do NOT run reconciliation — deferred to wrap-up
- Do NOT check cron dispatcher status — only if user asks
- Do NOT auto-run `/start-here`
- Do NOT output anything

**GitHub backup check (once per day):** Only on the first session of the day (today's memory file had no prior session blocks). First check `.env` for `IS_TEMPLATE_MAINTAINER=true` — if set, skip entirely. Otherwise, if `origin` still points to the upstream template repo, warn once. Otherwise silent.

### Greeting Behaviour

- Don't greet proactively — wait for the user to speak
- If the user greets casually and open threads exist from the most recent memory, mention them in one line
- If the user states a task, begin immediately — no preamble, no scope prompt

### Checkpoint Behaviour

After completing a major deliverable (file saved to `projects/`, skill built/modified), ask: "Anything else, or wrap up?"

Don't checkpoint quick answers, research, or small edits.

### Daily Memory

Every Claude session writes to `context/memory/{YYYY-MM-DD}.md`.

Use one file per day with numbered session blocks:

```markdown
## Session N

### Project
[Project folder name if working on a Level 2 or 3 project. Omit for single tasks.]

### Goal
[One line — filled once the user states their goal]

### Deliverables
- `path/to/file` — what it is

### Decisions
- [Decision and rationale]

### Open threads
- [Anything unfinished for the next session]
```

When Claude reads a memory file and sees a `### Project` reference, load `projects/briefs/{project-name}/brief.md` for full context.

### Auto-Tracking (silent — never announce)

Track these events as they happen during the session. Never say "I've logged that to memory."

- File created/modified in `projects/` → append to `### Deliverables`
- File created in `brand_context/` or `.claude/skills/` → append to `### Deliverables`
- User states goal → fill `### Goal`
- User makes a directional decision → append to `### Decisions`
- Task left incomplete → append to `### Open threads`

### Session End

- Detect common sign-off messages and run the full `meta-wrap-up` skill automatically
- Finalise the existing session block rather than creating a new one
- Keep entries concise and skimmable
