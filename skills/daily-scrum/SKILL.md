---
name: daily-scrum
description: Generate the daily standup report (Yesterday / Today / Blockers) from Notion Tasks. Every line is just the ticket ID and the title — no details, no links. Use whenever the user asks for a daily scrum or a daily standup.
user_invocable: true
---

# Daily Scrum Report

Use this when the user asks for a daily scrum, daily standup, or "give me my standup".

For Notion writes (creating/updating Tasks, including their embedded Investigation sections), defer to the **work-context** skill. This skill covers only the *report* generation and the *format rule*.

## Inputs the user must provide (or that must already be in memory)

- **Ticket prefix** — e.g. `BAB`, `ABC` — the project's Linear/Jira identifier
- **Linear workspace slug** — used when building Linear URLs

If either is missing from memory, ask once and save it under the `user` type so future runs don't re-prompt.

## 1. Format Rule (applies everywhere)

**Every entry is just the ticket ID followed by the title. Nothing else.**

- Scrum bullet: `**<TICKET>** Title`

This matches the Task `Name` format created by work-context — usually no reformatting is needed. Read the Task Name and copy it verbatim.

No details, no links, no PR references, no status notes, no em-dash continuation. The Task holds all the detail — the scrum is for the standup channel and only needs the ticket and title.

The ticket ID is always first. The title comes immediately after. NEVER lead with a verb ("Shipped X", "Working on Y", "Continued Z") or with a description.

For tasks without a ticket (e.g. tooling, ops chores), the Task Name is a plain title. Use it as-is. Optionally prefix with a short tag: `**tooling** <title>`, `**ops** <title>`.

### Good

- `**BAB-442** Custom DNS communities favicon/title`
- `**BAB-129** Add map for members, projects, and entities`
- `**tooling** Gate risky git/gh commands behind confirmation prompts`

### Bad

- `**BAB-442** Custom DNS communities favicon/title — useTabTitle hook, PR #970 merged.` (details after the title)
- `Shipped favicon/title for BAB-442` (leads with verb)
- `Working on BAB-129 (map)` (leads with verb, ticket buried)
- `Custom DNS favicon — BAB-442` (ticket last)

## 2. Report Structure

Three sections, in this order, each as bullets that follow the format rule:

```
**Yesterday**
**<TICKET>** Title

**Today**
**<TICKET>** Title

**Blockers**
None.
```

If there are blockers, format them the same way: `**<TICKET>** Title` (one bullet per blocker). The user can elaborate verbally if needed.

## 3. Pulling the Data

Read from the **Tasks DB**: `collection://4b71055f-5461-8315-9841-875a168162a4`.

- **Yesterday**: Tasks where `Status = Done` AND `Last edited time` falls on the previous **workday** (skip weekends and gap days — Monday's scrum pulls Friday's Done tasks).
- **Today**: Tasks where `My Day = true` AND `Status ∈ {To Do, Doing}` — what the user picked for today's Execute list.
- **Blockers**: ask the user. Never invent.

Extract only the Task `Name`. It should already be in `**<TICKET>** Title` format if created via work-context.

If a Task Name lacks the bold ticket prefix but the user expects one (e.g. a task was created outside the skill), reformat: extract the ticket ID and title, output as `**<TICKET>** Title`.

## 4. Linear Ticket Bodies

Without a Linear MCP, ticket bodies aren't directly readable. Derive titles from URL slugs (`<ticket>-129/add-map-for-members-projects-and-entities` becomes "Add map for members, projects, and entities"). Never invent ticket content.

## 5. When today has no picked tasks yet

If the "Today" query returns nothing (nothing checked `My Day` yet), ask the user which tickets they're picking up. Optionally offer to run work-context workflow A to create/pick them up before generating the scrum.

## 6. Forbidden

- NEVER include details, PR links, investigation links, or status notes — ticket + title only
- NEVER lead a line with a verb instead of a ticket
- NEVER drop the ticket ID (unless the Task is genuinely non-ticket work)
- NEVER invent ticket titles when Linear isn't accessible — ask the user
- NEVER duplicate work-context's Notion-write logic here — defer to that skill
- NEVER read the deprecated Daily Work `Summary` field — the source of truth is now Tasks
