---
name: work-context
description: Manage investigation pages and tie them to the Daily Work log in Notion. Use when the user asks to update an investigation, log work on a ticket, mark an investigation as shipped, or add a Daily Work entry for a ticket. Keeps investigations and Daily Work cross-linked.
user_invocable: true
---

Manage investigation pages and Daily Work entries in Notion as a single workflow. Every action on an investigation gets reflected in Daily Work, and every Daily Work entry that touches an investigation links back to it.

## Inputs the user must provide (or that must already be in memory)

Before doing anything ticket-related, check memory for these. If missing, ask **once** and save under the type `user`:

- **Ticket prefix** — e.g. `BAB`, `ABC` — the project's Linear/Jira identifier
- **Linear workspace slug** — used to build Linear URLs as `https://linear.app/<slug>/issue/<TICKET>`
- **Investigations parent page name** — for display only (e.g. "Investigations")

Use these wherever the workflow references a ticket or Linear URL.

## Notion structure

All IDs below are stable — use them directly without searching.

### Investigations
- Parent page: `https://www.notion.so/3501055f54618132899be65e6e52acac` (ID `3501055f54618132899be65e6e52acac`)
- Each investigation is a standalone Notion page (not a database row)
- Title format: `<TICKET_PREFIX>-XXX — <short description>` (e.g. `BAB-442 — Custom DNS communities favicon/title`)
- Icon convention: `🏷️` for new investigations (existing ones may use other emojis — leave them)

### Daily Work
- Database: `https://www.notion.so/6f4a5a0723764e1b96f300dd475afe24` (ID `6f4a5a0723764e1b96f300dd475afe24`)
- Data source: `collection://fe44d695-a91a-4f0e-9740-38c5b65cb569`
- Schema:
  - `Date` (title, plain text) — usually the ISO date `YYYY-MM-DD`
  - `Summary` (text) — markdown bullets with ticket tags and links
  - `Hours worked` (number)
  - `Work Date` (date) — the actual day the work was done
  - `Status` (status: `Not started` / `In progress` / `Done`)

## Investigation page conventions

Every investigation page should have, in order:

1. **Linear link line:** `**Linear:** [https://linear.app/<workspace>/issue/<TICKET>](https://linear.app/<workspace>/issue/<TICKET>)`
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

## Daily Work entry conventions

The `Summary` field is markdown. Format for each work item:

```
- \[<TICKET>\] <short title> — <what you did today> ([investigation](notion-url), [PR #X](pr-url), [Linear](linear-url))
```

Rules:
- Bracket-escape ticket IDs: `\[<TICKET>\]` (matches existing pattern in the database)
- Multiple items in one day: separate bullets with `<br>` (newlines render the same but `<br>` is what the existing entries use)
- Always link the investigation if one exists for the ticket
- Always link the PR if one exists
- Linear link is optional but nice for tickets without an investigation
- Keep titles short — don't paste the full Linear title

Status for the entry:
- `Done` — work for the ticket is shipped (PR merged or pushed for review with implementation complete)
- `In progress` — work is ongoing across days
- `Not started` — placeholder (rare)

`Hours worked` — leave blank (do not set). The user fills in hours at the end of the day; never ask, never guess, never auto-populate.

## Workflows

### A. Resolve an investigation (work shipped)

Triggers: "mark <TICKET> as shipped", "update investigation with PR #N", "close out <TICKET>", "I just merged <TICKET>".

1. Fetch the investigation page (search by ticket ID if needed; list under the Investigations parent page if title is fuzzy).
2. Update the **Status** line to `Shipped in [PR #X](url) — awaiting review and manual QA` (or whatever fits — see vocabulary).
3. If there was an "Open questions to <Person>" section and the questions have been resolved, replace it with `## <Person>'s responses (YYYY-MM-DD)` summarizing answers.
4. Append (do not replace) an `## Implementation ([PR #X](url))` section with 3–6 bullets covering: files added/changed, key design decisions, why this shape and not another. Keep it tight — the PR has the full diff.
5. Then run workflow C (log Daily Work) for the same date.

### B. Update an investigation status only (no PR yet)

Triggers: "<TICKET> is now in implementation", "update <TICKET> status to <X>".

1. Fetch the investigation page.
2. Update only the **Status** line. Don't append sections unless asked.

### C. Log Daily Work entry

Triggers: "log today's work on <TICKET>", "add daily work entry", "I worked X hours on <TICKET> today".

1. Resolve today's date (use the system `currentDate` reminder, never guess).
2. Search the Daily Work data source for an entry with `Work Date == today`. If one exists, you'll **update** it (append a new bullet to `Summary`) instead of creating a duplicate.
3. Build the bullet for the ticket (see Daily Work conventions above). Always include the investigation link if one exists.
4. Create or update the page:
   - **Create:** parent = `data_source_id: fe44d695-a91a-4f0e-9740-38c5b65cb569`. Set `Date`, `Status`, `date:Work Date:start`, `date:Work Date:is_datetime: 0`, `Summary`. Do NOT set `Hours worked` — the user fills it at end of day.
   - **Update:** use `mcp__notion__notion-update-page` with `update_properties` to overwrite `Summary` (concatenated with `<br>`). Do NOT touch `Hours worked`.

### D. Close out (combined): A + C

Triggers: "update Notion after a PR is opened/merged", "tie up <TICKET>", or after the user says `commit push make pR` — proactively offer to run this workflow once the PR exists.

Run workflow A, then workflow C, in that order. The investigation update happens first so the Daily Work bullet can link to a freshly-updated investigation.

## The tie (most important)

Investigations and Daily Work must stay cross-linked.

- **Daily Work → Investigation:** every Daily Work bullet for a ticket that has an investigation MUST include `[investigation](notion-url)` in its links. No exceptions.
- **Investigation → PR:** every shipped investigation MUST have the PR link in both the Status line AND the Implementation section heading.
- **Investigation → Linear:** every investigation has the Linear link as its first content line. Don't lose this when editing.
- **Daily Work → PR:** every Daily Work bullet that produced a PR MUST include `[PR #X](url)`.

If you find an investigation that has been worked on (Daily Work entries reference it) but has no Status update, flag it — the link is broken.

## Tools to use

- `mcp__notion__notion-fetch` — read pages and database schemas
- `mcp__notion__notion-search` with `data_source_url: "collection://fe44d695-a91a-4f0e-9740-38c5b65cb569"` to find Daily Work entries by date
- `mcp__notion__notion-search` with `page_url: "3501055f54618132899be65e6e52acac"` to find investigations by ticket ID (semantic match)
- `mcp__notion__notion-update-page` with `update_content` for surgical edits to investigation pages (search-and-replace on existing markdown)
- `mcp__notion__notion-update-page` with `update_properties` for editing Daily Work entry properties
- `mcp__notion__notion-create-pages` for new Daily Work entries (parent: `data_source_id`)

## Important

- Never overwrite an investigation's Linear link, Problem section, or original investigation body. The investigation is the historical record of how a problem was understood — append, don't rewrite.
- Always escape brackets in Daily Work `Summary` field: `\[<TICKET>\]`.
- Always pull today's date from the system `currentDate` context — do not guess or use the model's training date.
- If the user asks to "update Notion" without specifying which investigation, ask which ticket. Don't assume the most recent one.
- Hours worked: never set, never ask, never invent. The user adds the hours manually at the end of the day.
