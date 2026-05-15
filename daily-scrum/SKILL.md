---
name: daily-scrum
description: Generate the daily standup report (Yesterday / Today / Blockers) from Notion Daily Work entries. Every line starts with the ticket ID, then the title, then details. Use whenever the user asks for a daily scrum or a daily standup.
---

# Daily Scrum Report

Use this when the user asks for a daily scrum, daily standup, or "give me my standup".

For Notion writes (creating or updating Daily Work entries, updating investigation pages), defer to the **work-context** skill. This skill covers only the *report* generation and the *format rule* that applies everywhere a ticket appears in a bullet.

## Inputs the user must provide (or that must already be in memory)

- **Ticket prefix** — e.g. `BAB`, `ABC` — the project's Linear/Jira identifier
- **Linear workspace slug** — used when building Linear URLs

If either is missing from memory, ask once and save it under the `user` type so future runs don't re-prompt.

## 1. Format Rule (applies everywhere)

**Every entry starts with the ticket ID, then the title, then a separator, then details.**

- Notion `Summary` bullet (handled by work-context): `- \[<TICKET>\] Title — details (links)`
- Daily scrum text bullet: `**<TICKET>** Title — details`

NEVER lead with a verb ("Shipped X", "Working on Y", "Continued Z") or with a description. The ticket ID is always first. The title comes immediately after. Details come last, separated by an em dash.

### Good

- `**<TICKET>-442** Custom DNS communities favicon/title — useTabTitle hook, useRouteTabTitle composer, configMap title backfill. PR #970 merged.`
- `**<TICKET>-129** Add map for members, projects, and entities — initial scaffold and data wiring.`

### Bad

- `Shipped favicon/title for <TICKET>-442` (leads with verb)
- `Working on <TICKET>-129 (map)` (leads with verb, ticket buried)
- `Custom DNS favicon — <TICKET>-442` (ticket last)

## 2. Report Structure

Three sections, in this order, each as bullets that follow the format rule:

```
**Yesterday**
**<TICKET>** Title — what was finished or progressed.

**Today**
**<TICKET>** Title — what will happen.

**Blockers**
None.
```

If there are blockers, format them the same way: `**<TICKET>** Title — specific blocker.`

## 3. Pulling the Data

- **Yesterday:** the most recent prior Daily Work entry. That's the previous **workday**, which is not always 24 hours ago — skip weekends and gap days. Use the entry's `Summary` bullets verbatim, reformatted from `- \[<TICKET>\] …` to `**<TICKET>** …`.
- **Today:** today's Daily Work entry. If none exists yet, ask the user which tickets they're picking up, or run work-context workflow C to log them first.
- **Blockers:** ask the user. Never invent.

The Daily Work data source is `collection://fe44d695-a91a-4f0e-9740-38c5b65cb569` (search by date).

## 4. Linear Ticket Bodies

Without a Linear MCP, ticket bodies aren't directly readable. Derive titles from URL slugs (`<ticket>-129/add-map-for-members-projects-and-entities` becomes "Add map for members, projects, and entities"). For details beyond the title, ask the user. Never invent ticket content.

## 5. Forbidden

- NEVER lead a line with a verb instead of a ticket
- NEVER drop the ticket ID
- NEVER invent ticket details when Linear isn't accessible — ask the user
- NEVER duplicate work-context's Notion-write logic here — defer to that skill
