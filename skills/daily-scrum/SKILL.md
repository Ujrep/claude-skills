---
name: daily-scrum
description: Generate the daily standup report (Yesterday / Today / Blockers) from Notion Daily Work entries. Every line is just the ticket ID and the title — no details, no links. Use whenever the user asks for a daily scrum or a daily standup.
user_invocable: true
---

# Daily Scrum Report

Use this when the user asks for a daily scrum, daily standup, or "give me my standup".

For Notion writes (creating or updating Daily Work entries, updating investigation pages), defer to the **work-context** skill. This skill covers only the *report* generation and the *format rule* that applies everywhere a ticket appears in a bullet.

## Inputs the user must provide (or that must already be in memory)

- **Ticket prefix** — e.g. `BAB`, `ABC` — the project's Linear/Jira identifier
- **Linear workspace slug** — used when building Linear URLs

If either is missing from memory, ask once and save it under the `user` type so future runs don't re-prompt.

## 1. Format Rule (applies everywhere)

**Every entry is just the ticket ID followed by the title. Nothing else.**

- Daily scrum text bullet: `**<TICKET>** Title`

No details, no links, no PR references, no status notes, no em-dash continuation. The Notion Daily Work entry holds all the detail — the scrum is for the standup channel and only needs the ticket and title.

The ticket ID is always first. The title comes immediately after. NEVER lead with a verb ("Shipped X", "Working on Y", "Continued Z") or with a description.

For lines without a ticket (e.g. tooling, ops chores), use a short tag in place of the ticket: `**tooling** <title>`, `**ops** <title>`.

### Good

- `**<TICKET>-442** Custom DNS communities favicon/title`
- `**<TICKET>-129** Add map for members, projects, and entities`
- `**tooling** Gate risky git/gh commands behind confirmation prompts`

### Bad

- `**<TICKET>-442** Custom DNS communities favicon/title — useTabTitle hook, PR #970 merged.` (details after the title)
- `Shipped favicon/title for <TICKET>-442` (leads with verb)
- `Working on <TICKET>-129 (map)` (leads with verb, ticket buried)
- `Custom DNS favicon — <TICKET>-442` (ticket last)

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

- **Yesterday:** the most recent prior Daily Work entry. That's the previous **workday**, which is not always 24 hours ago — skip weekends and gap days. From each `Summary` bullet, extract ONLY the ticket ID and title; drop everything after the em dash and drop all parenthesised links. Reformat from `- \[<TICKET>\] Title — details (links)` to `**<TICKET>** Title`.
- **Today:** today's Daily Work entry. Same extraction rule. If none exists yet, ask the user which tickets they're picking up, or run work-context workflow C to log them first.
- **Blockers:** ask the user. Never invent.

The Daily Work data source is `collection://fe44d695-a91a-4f0e-9740-38c5b65cb569` (search by date).

## 4. Linear Ticket Bodies

Without a Linear MCP, ticket bodies aren't directly readable. Derive titles from URL slugs (`<ticket>-129/add-map-for-members-projects-and-entities` becomes "Add map for members, projects, and entities"). Never invent ticket content.

## 5. Forbidden

- NEVER include details, PR links, investigation links, or status notes — ticket + title only
- NEVER lead a line with a verb instead of a ticket
- NEVER drop the ticket ID
- NEVER invent ticket titles when Linear isn't accessible — ask the user
- NEVER duplicate work-context's Notion-write logic here — defer to that skill
