---
name: work-context
description: Manage investigation pages and Tasks in Notion. Use when the user asks to update an investigation, log work on a ticket, mark work as shipped, or create/update a task for a ticket. Keeps investigations and Tasks cross-linked.
user_invocable: true
---

# Work Context — Investigations + Tasks

Manage investigation pages and Tasks in Notion as a single workflow. Every action on a ticket updates one Task (find-or-create by ticket ID) and its investigation page if one exists.

**No more Daily Work Summaries.** The Daily Work DB is still used for `Hours worked` only (consumed by work-stats). Ticket-level detail lives in the Tasks DB.

## Inputs the user must provide (or that must already be in memory)

Check memory for these. If missing, ask **once** and save under type `user`:

- **Ticket prefix** — e.g. `BAB` — the project's Linear/Jira identifier
- **Linear workspace slug** — used to build Linear URLs as `https://linear.app/<slug>/issue/<TICKET>`
- **Investigations parent page name** — for display only

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

### Investigations
- Parent page: `3501055f54618132899be65e6e52acac`
- Each investigation is a standalone Notion page (not a database row)
- Title format: `<TICKET> — <short description>`
- Icon convention: `🏷️` for new investigations (existing ones may use other emojis — leave them)

### Daily Work DB (Hours only)
- Data source: `collection://fe44d695-a91a-4f0e-9740-38c5b65cb569`
- Used ONLY for `Hours worked` (consumed by work-stats)
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

Append work notes inside the task body page as work progresses. Keep it lean:

```markdown
**Linear:** [https://linear.app/<slug>/issue/<TICKET>](...)
**Investigation:** [<TICKET> — <title>](notion-url)   ← only if investigation exists

## Progress
- YYYY-MM-DD — <what was done that day>
- YYYY-MM-DD — <what was done that day>

## PRs
- [PR #N](url) — <short description>

## Notes
<free-form observations, follow-ups, edge cases, decisions>
```

Rules:
- **Ticket with investigation** → investigation is the deep record; task body just links to it and tracks Progress bullets + PRs + short Notes
- **Ticket without investigation** → everything (including deeper context) goes in the task body Notes section
- **Non-ticket task** → no Linear/Investigation lines, just Progress + Notes

## Investigation page conventions

Investigations are separate long-form pages (unchanged from prior workflow). They live under the Investigations parent.

Every investigation page should have, in order:

1. **Linear link line:** `**Linear:** [https://linear.app/<workspace>/issue/<TICKET>](...)`
2. **Status line:** `**Status:** <one short sentence>` — kept current. See status vocabulary below.
3. **Problem** section
4. Investigation body (analysis, options, why-not-X discussion)
5. **Plan / Quick-fix plan** section
6. **Key files** section (when applicable)
7. After implementation: **Implementation ([PR #X](url))** section appended (do NOT replace the plan — the investigation is the historical record)
8. After stakeholder feedback: **<Person>'s responses (YYYY-MM-DD)** section replacing the original "Open questions" section

### Status vocabulary

Pick the most specific phrase that fits. The status line is the single most-read thing on the page.

- `awaiting <Person>'s reply on Linear comment posted YYYY-MM-DD`
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

### C. Mark a ticket done (close out)

Triggers: "shipped <TICKET>", "mark <TICKET> done", "closed out <TICKET>", "merged <TICKET>".

1. Find the Task by ticket ID.
2. `update_properties`: `Status = Done`, `My Day = false`.
3. Append final Progress bullet: `- YYYY-MM-DD — Shipped in PR #N`.
4. If a PR URL is available, add it under `## PRs`.
5. If an investigation exists for the ticket, run workflow E to update its status line.

### D. Combined close-out (Task + Investigation)

Triggers: "update Notion after PR #N is opened/merged", "tie up <TICKET>", or after `commit push make PR` when a PR exists.

Run workflow C, then E (in that order — Task first, so the investigation update reflects the final Task state).

### E. Update investigation status only (no Task changes)

Triggers: "<TICKET> is now in implementation", "update <TICKET> investigation status".

1. Fetch the investigation page (search by ticket ID; list under the Investigations parent page if title is fuzzy).
2. Update only the **Status** line. Don't append sections unless asked.
3. If the update reflects a PR, also update the PR link.

### F. Non-ticket task

Triggers: "add task: <title>", "log tooling work: <title>".

1. Create a Task with Name=`<title>` (no ticket prefix, no bold).
2. Set Context/Energy/Project as appropriate.
3. All context in Notes.

## The tie (most important)

Investigations, Tasks, and PRs must stay cross-linked.

- **Task ↔ Investigation**: every Task for a ticket that has an investigation MUST link to it in the task body header.
- **Investigation → PR**: every shipped investigation MUST have the PR link in both the Status line AND the Implementation section heading.
- **Task → PR**: every Task that produced a PR must have the PR link in the PRs section of the task body.
- **Investigation → Linear**: every investigation has the Linear link as its first content line. Don't lose this when editing.

If you find an investigation that has been worked on (a Task references it and is Done) but has no Status update on the investigation, flag it — the link is broken.

## Tools to use

- `mcp__notion__notion-search` with `data_source_url: "collection://4b71055f-5461-8315-9841-875a168162a4"` — find Tasks by ticket ID in name
- `mcp__notion__notion-search` with `page_url: "3501055f54618132899be65e6e52acac"` — find investigations by ticket ID
- `mcp__notion__notion-fetch` — read Tasks, Investigations, or schemas
- `mcp__notion__notion-create-pages` — create Tasks (parent: `data_source_id: 4b71055f-5461-8315-9841-875a168162a4`)
- `mcp__notion__notion-update-page` with `update_properties` — Task Status, My Day, Hours; Investigation status line
- `mcp__notion__notion-update-page` with `update_content` — append to Task Progress/PRs/Notes; edit investigation sections

## Important

- **One Task per ticket, ever.** Always search first. Never create a duplicate.
- **All context in the task body**, not sub-tasks.
- **Investigation pages remain the historical record** for tickets that have them — never rewrite; append.
- **Daily Work Summary is deprecated** — do NOT write summary bullets to Daily Work entries anymore. `Hours worked` on Daily Work is still set by the user only; never auto-populate.
- **Hours on the Task** is a separate, optional informational field. It does NOT drive work-stats; work-stats reads Daily Work.Hours worked.
- Always pull today's date from the system `currentDate` context — do not guess.
- If the user asks to "update Notion" without specifying which ticket, ask. Don't assume.
