# Working on Projects

Not everything is a single task. When you have a larger piece of work — a product launch, a content series, a website overhaul — you need a way to scope it, track it, and keep context across sessions.

There are three levels. When you tell Claude your goal, it helps you pick the right one.

---

## The Three Levels

| Level | Name | When | Where |
|-------|------|------|-------|
| **1** | Single task | One or a few small deliverables | `projects/{category}/` |
| **2** | Planned project | Multi-deliverable, cross-session — campaigns, launches | `projects/briefs/{project-name}/` |
| **3** | GSD project | Complex multi-phase with dependencies | `projects/briefs/{project-name}/` + `.planning/` |

**"Your working folder"** = the root `agentic-os/` folder for solo/system-wide work, or `clients/client-name/` for client-specific work. All paths are relative to wherever you `cd`'d.

---

## Level 1: Single Task

Just ask Claude. Output goes to `projects/{category}-{type}/`. No brief, no project folder. Use Shift+Tab twice for plan mode if upfront thinking helps.

```
projects/mkt-copywriting/2026-03-24_blog-post.md
```

---

## Level 2: Planned Project

For multi-deliverable work — campaigns, launches, client deliverables. Claude runs a short scoping conversation (goal, deliverables, acceptance criteria, timeline) and writes a `brief.md`.

The project gets its own folder under `projects/briefs/`. ALL outputs for that project go inside it — not scattered across category folders. Projects are listed most-recent-first (by `created` date in frontmatter) when reporting to the user.

```
projects/briefs/q2-product-launch/   <- project folder
├── brief.md                         <- scope, deliverables, acceptance criteria
├── 2026-03-24_landing-page.md       <- outputs live WITH the brief
├── 2026-03-25_email-sequence.md
└── 2026-03-22_competitor-scan.md
```

### What goes in the brief

Claude scopes the project by asking:
- What's the goal? (one sentence)
- What are the deliverables? (checklist)
- How will you know it's done? (acceptance criteria)
- Any timeline or constraints?

The brief is saved as `projects/briefs/{project-name}/brief.md` with frontmatter:

```yaml
---
project: q2-product-launch
status: active
level: 2
created: 2026-03-24
---
```

---

## Level 3: GSD Project

For complex multi-phase work with dependencies and milestones.

GSD uses a `.planning/` folder at the workspace root to store its roadmap, phase plans, and verification reports. This folder always lives at the root of your session — `agentic-os/.planning/` for solo work, or `clients/client-name/.planning/` for a client workspace.

Your project's outputs and brief live in `projects/briefs/{project-name}/` as usual. GSD's `.planning/` is its own working space separate from your outputs.

```
projects/briefs/website-rebuild/     <- project folder (your outputs)
├── brief.md
├── 2026-03-24_homepage-copy.md
└── 2026-03-25_sitemap.excalidraw

.planning/                           <- GSD working space (at workspace root)
├── PROJECT.md
├── config.json
├── research/
└── workstreams/
    └── website-rebuild/             <- this project's planning state
        ├── ROADMAP.md
        ├── STATE.md
        └── phases/
            ├── 01-foundation/
            │   ├── PLAN.md
            │   └── VERIFICATION.md
            └── 02-build/
```

### Multiple GSD projects in parallel — workstreams

Each GSD project lives as a **workstream** inside `.planning/workstreams/{slug}/`. This means multiple projects can run in parallel in the same workspace — each with its own roadmap, state, and phases — without colliding.

When you start your first project, GSD creates a flat `.planning/` structure. When you start a second project, GSD automatically migrates the first into `.planning/workstreams/{name}/` and creates the new one alongside it.

```
.planning/
├── PROJECT.md
├── config.json
└── workstreams/
    ├── website-rebuild/       <- Project A (active)
    │   ├── ROADMAP.md
    │   ├── STATE.md
    │   └── phases/
    └── email-campaign/        <- Project B (active in parallel)
        ├── ROADMAP.md
        ├── STATE.md
        └── phases/
```

### Archiving a completed GSD project

When you're done with a GSD project, run `/archive-gsd`. This:

1. Completes the workstream — GSD archives it to `.planning/milestones/`
2. Updates the brief's status to `complete`

```
.planning/
├── milestones/
│   └── ws-website-rebuild-2026-05-15/   <- archived workstream
│       ├── ROADMAP.md
│       ├── STATE.md
│       └── phases/
└── workstreams/
    └── email-campaign/                  <- remaining active project
```

---

## How It All Fits Together

```
projects/
├── mkt-copywriting/                <- single task category folder (Level 1)
│   └── 2026-03-20_blog-post.md
├── str-trending-research/          <- single task category folder
│   └── 2026-03-18_ai-trends.md
└── briefs/                         <- all Level 2/3 projects (most recent first)
    ├── kanban-dashboard/           <- Level 2 planned project (has brief.md)
    │   ├── brief.md
    │   └── 2026-03-24_architecture.md
    ├── q2-product-launch/          <- Level 2 planned project
    │   ├── brief.md
    │   ├── 2026-03-24_landing-page.md
    │   ├── 2026-03-25_email-sequence.md
    │   └── 2026-03-22_competitor-scan.md
    └── website-rebuild/            <- Level 3 GSD project (has brief.md, links to .planning/)
        ├── brief.md
        ├── 2026-03-24_homepage-copy.md
        └── 2026-03-25_sitemap.excalidraw

.planning/                          <- GSD only (Level 3), at workspace root
├── PROJECT.md
├── config.json
└── workstreams/
    └── website-rebuild/            <- one workstream per Level 3 project
        ├── ROADMAP.md
        ├── STATE.md
        └── phases/
```

**How to tell them apart:**
- Category folders live directly under `projects/` using `{category}-{type}` naming (e.g., `mkt-copywriting`) — no `brief.md` inside
- Project folders live under `projects/briefs/` with descriptive names (e.g., `kanban-dashboard`) — always have a `brief.md` inside
- When listing projects, most recent first (by `created` date in frontmatter)

The heartbeat scans for `brief.md` files inside `projects/briefs/*/` to find active projects.

---

## Session Memory and Projects

When you're working on a Level 2 or 3 project, each session's memory block (`context/memory/YYYY-MM-DD.md`) includes a `### Project` field that links back to the project name. This means when Claude starts your next session and reads yesterday's memory, it automatically loads the project's `brief.md` for full context — you don't need to re-explain what you're working on.

For single tasks (Level 1), the project field is omitted and sessions work as before.

---

## Working Directory Matters

Be explicit about WHERE you work:

**Solo user or shared work:**
```bash
cd ~/Projects/agentic-os
claude
# "Start a project for Q2 product launch"
# -> Creates projects/briefs/q2-product-launch/brief.md
# -> All outputs go to projects/briefs/q2-product-launch/
```

**Client-specific projects:**
```bash
cd ~/Projects/agentic-os/clients/client-one
claude
# "Start a project for Q2 product launch"
# -> Creates projects/briefs/q2-product-launch/brief.md (inside client-one/)
# -> All outputs go to clients/client-one/projects/briefs/q2-product-launch/
```

The paths are always relative to your working directory. If you're in the wrong folder, outputs go to the wrong place. The heartbeat confirms which workspace you're in.

All three levels coexist. You might use Level 1 for daily requests, Level 2 for a campaign, and Level 3 for a website rebuild — all within the same workspace.
