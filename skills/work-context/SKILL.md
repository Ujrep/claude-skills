---
name: work-context
description: Manage Tasks in Notion, including their embedded investigations. Use when the user asks to update an investigation, log work on a ticket, mark work as shipped, or create/update a task for a ticket. Investigations live inside the Task body, not as separate pages.
user_invocable: true
---

# Work Context — Tasks (with embedded investigations)

Manage ticket work in Notion through a single artifact: the Task. Every action on a ticket updates one Task (find-or-create by ticket ID). Investigation content lives **inside the Task body** as an `## Investigation` section — do NOT create standalone investigation pages.

**No more Daily Work anything.** The old Daily Work DB is trashed. Ticket-level detail lives in the Tasks DB; hours live in the separate Hours Log DB (owned by the work-stats skill).

**No more investigation pages.** The old Investigations parent page (`3501055f54618132899be65e6e52acac`) is a legacy archive — read it when historical context helps, link to a legacy page from a Task if one exists, but never create or extend pages there.

## Inputs the user must provide (or that must already be in memory)

Check memory for these. If missing, ask **once** and save under type `user`:

- **Ticket prefix** — e.g. `BAB` — the project's Linear/Jira identifier
- **Linear workspace slug** — used to build Linear URLs as `https://linear.app/<slug>/issue/<TICKET>`

Use these wherever the workflow references a ticket or Linear URL.

## Notion structure

All IDs below are stable — use them directly without searching.

### Tasks DB
- Database: `7b81055f54618312a485818ba4a8e8e5`
- Data source: `collection://4b71055f-5461-8315-9841-875a168162a4`
- Schema (writable):
  - `Name` (title) — `**<TICKET>** <short title>` or `<short title>` for non-ticket work
  - `Status` (status) — `To Do` / `Doing` / `Done` / `Archived`
  - `Project` (relation → Projects DB)
  - `Context` (select) — `Focus` / `Maintenance` / `Hands` / `Outdoor` / `Phone` / `People` / `Explore` / `Review`
  - `Energy` (select) — `⚡ Low` / `🔋 Normal` / `🪫 High`
  - `Due` (date, optional)
  - `Hours` (number, optional — informational only, does NOT drive work-stats)
  - `My Day` (checkbox) — on when picked for today's execute list

### Projects DB
- Data source: `collection://8fd1055f-5461-83ca-88e9-070af04ff417`
- **Babele project**: `3911055f-5461-8129-a1dd-f378c36c2b25` — use this for all `BAB-*` tickets

### Legacy Investigations archive (read-only)
- Parent page: `3501055f54618132899be65e6e52acac`
- Contains pre-2026-07-13 standalone investigation pages. Never create or extend pages here. If a legacy page exists for a ticket, link it from the Task header line; new investigation content still goes in the Task body.

### Hours Log DB (hours only — owned by work-stats)
- Data source: `collection://c1eaa722-a204-41e2-8dc1-f9b88b2bfa63`
- One row per worked day: `Date` (title), `Work Date` (date), `Hours` (number). This skill never writes to it.
- Do NOT write ticket summaries here anymore. The `Summary` field is deprecated for new entries.

## Task conventions

**One Task per ticket, forever.** Never create a second Task for the same ticket — always find-or-create by ticket ID in the Name.

### Task Name format

- Ticket work: `**<TICKET>** <short title>` (bold prefix — matches daily-scrum output)
- Non-ticket work: `<short title>` (no prefix, e.g. `Gate risky git commands behind confirmation prompts`)

### Task property defaults

| Property | Ticket work | Non-ticket |
|---|---|---|
| Status | `To Do` → `Doing` → `Done` | same |
| Project | → Babele (`3911055f-5461-8129-a1dd-f378c36c2b25`) | none, unless obviously project-scoped |
| Context | `Focus` (coding) or `Maintenance` (batch/emails/reviews) | context-appropriate |
| Energy | `🔋 Normal` default, `🪫 High` for hard bugs / heavy refactors | same |
| Due | only if user specifies | same |
| My Day | on when user picks it for today | same |

### Task body (page content)

The task body is the single record for the ticket: progress log, PRs, notes, and — when the ticket needed one — the full investigation. Section order:

```markdown
**Linear:** [https://linear.app/<slug>/issue/<TICKET>](...)
**Legacy investigation:** [<TICKET> — <title>](notion-url)   ← only if a pre-cutover page exists

## Progress
- YYYY-MM-DD — <what was done that day>
- YYYY-MM-DD — <what was done that day>

## PRs
- [PR #N](url) — <short description>

## Investigation                        ← only when the ticket required one
**Status:** <one short sentence, kept current — see status vocabulary>

### Problem
<what's broken / what was asked>

### Root cause / Analysis
<findings, options, why-not-X discussion, file:line references>

### Plan / Quick-fix plan
<the agreed approach>

### Key files
<file — role bullets>

### Implementation ([PR #X](url))      ← appended after implementation; never replaces the plan
<what actually shipped, deviations from plan>

## Notes
<free-form observations, follow-ups, edge cases, decisions>
```

Rules:
- **Ticket needing an investigation** → the `## Investigation` section is the deep record. Append to it; never rewrite it — it is the historical record. Stakeholder feedback lands as a `### <Person>'s responses (YYYY-MM-DD)` subsection replacing an `### Open questions` subsection if one existed.
- **Ticket without investigation** → omit the `## Investigation` section entirely; deeper context goes in Notes.
- **Non-ticket task** → no Linear line, just Progress + Notes.

### Investigation status vocabulary

The `**Status:**` line under `## Investigation` is the single most-read line. Pick the most specific phrase:

- `awaiting <Person>'s reply on Linear comment posted YYYY-MM-DD`
- `Root cause identified — awaiting decision on fix`
- `Plan approved — implementation in progress`
- `Shipped in [PR #X](url) — awaiting review and manual QA`
- `Merged in [PR #X](url) — verified on staging`
- `Closed — superseded by [<TICKET>](link)` / `Closed — won't fix`

Always include a date or PR link in the status when one exists, so the line is self-dating.

## Workflows

### A. Start / pick up a ticket (find-or-create Task)

Triggers: "start <TICKET>", "picking up <TICKET>", "add task for <TICKET>".

1. Search Tasks DB for a Task whose `Name` contains `<TICKET>`. Use `mcp__notion__notion-search` with `data_source_url: collection://4b71055f-5461-8315-9841-875a168162a4` and query the ticket ID.
2. **If exists**: `update_properties` — set `Status = Doing`, `My Day = true` (if starting today).
3. **If not exists**: `create_pages` — Name=`**<TICKET>** <title>`, Status=`Doing`, Project=Babele, Context=`Focus`, Energy=`🔋 Normal`, My Day=`true`.
4. Append today's date to the task body Progress section using `update_content`.

### B. Log progress on a ticket

Triggers: "worked on <TICKET>", "log progress on <TICKET>", "add note to <TICKET>".

1. Find the Task by ticket ID.
2. Append a Progress bullet under `## Progress`: `- YYYY-MM-DD — <what was done>`.
3. If Status was `To Do`, update to `Doing`.

### C. Record an investigation

Triggers: "investigated <TICKET>", "write up the investigation", "root cause found for <TICKET>".

1. Find-or-create the Task (workflow A), Status=`Doing`.
2. Add (or append to) the `## Investigation` section in the task body — Status line, Problem, Root cause / Analysis, Plan, Key files.
3. Add a Progress bullet summarizing the finding in one line.

### D. Mark a ticket done (close out)

Triggers: "shipped <TICKET>", "mark <TICKET> done", "closed out <TICKET>", "merged <TICKET>", or after `commit push make PR` when a PR exists.

1. Find the Task by ticket ID.
2. `update_properties`: `Status = Done`, `My Day = false`.
3. Append final Progress bullet: `- YYYY-MM-DD — Shipped in PR #N`.
4. If a PR URL is available, add it under `## PRs`.
5. If the task has an `## Investigation` section: update its Status line and append the `### Implementation ([PR #X](url))` subsection.

### E. Update investigation status only (no other Task changes)

Triggers: "<TICKET> is now in implementation", "update <TICKET> investigation status".

1. Find the Task by ticket ID.
2. Update only the `**Status:**` line inside `## Investigation`. Don't append sections unless asked.
3. If the update reflects a PR, also update the PR link.

### F. Non-ticket task

Triggers: "add task: <title>", "log tooling work: <title>".

1. Create a Task with Name=`<title>` (no ticket prefix, no bold).
2. Set Context/Energy/Project as appropriate.
3. All context in Notes.

## The tie (most important)

Tasks, their embedded investigations, and PRs must stay consistent.

- **Investigation → PR**: every shipped investigation section MUST have the PR link in both its Status line AND its Implementation subsection heading.
- **Task → PR**: every Task that produced a PR must have the PR link in the PRs section of the task body.
- **Task → Linear**: every ticket Task has the Linear link as its first content line. Don't lose this when editing.
- **Legacy pages**: a Task may link a pre-cutover investigation page in its header. Treat that page as frozen history — status updates go in the Task's own Investigation section (create one if the ticket is reopened).

If a Task is Done but its Investigation section's Status line was never updated past "in progress", flag it — the record is inconsistent.

## Tools to use

- `mcp__notion__notion-search` with `data_source_url: "collection://4b71055f-5461-8315-9841-875a168162a4"` — find Tasks by ticket ID in name
- `mcp__notion__notion-search` with `page_url: "3501055f54618132899be65e6e52acac"` — find LEGACY investigation pages by ticket ID (read-only)
- `mcp__notion__notion-fetch` — read Tasks or schemas
- `mcp__notion__notion-create-pages` — create Tasks (parent: `data_source_id: 4b71055f-5461-8315-9841-875a168162a4`)
- `mcp__notion__notion-update-page` with `update_properties` — Task Status, My Day, Hours
- `mcp__notion__notion-update-page` with `update_content` — append to Task Progress/PRs/Notes/Investigation

## Important

- **One Task per ticket, ever.** Always search first. Never create a duplicate.
- **All context in the task body**, not sub-tasks and not separate pages.
- **Never create standalone investigation pages.** The Investigations parent is a frozen legacy archive.
- **The Investigation section is the historical record** — append, never rewrite.
- **The old Daily Work DB is trashed** — never write to it; pages created there land in Notion trash silently.
- **Hours on the Task** is a separate, optional informational field. It does NOT drive work-stats; work-stats reads Hours Log.Hours (user-entered only — never auto-populate).
- Always pull today's date from the system `currentDate` context — do not guess.
- If the user asks to "update Notion" without specifying which ticket, ask. Don't assume.
