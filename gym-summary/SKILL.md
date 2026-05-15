---
name: gym-summary
description: Refresh the Stats summary on the Gym Tracker page (sessions/week, weekly volume, calories, current streak, top lifts, underworked muscle groups). Use when the user asks for a gym summary, weekly training review, or to refresh the Gym Tracker stats.
---

# Gym Summary — Stats Refresh

Use when the user asks for a gym summary, weekly training review, or to refresh the Gym Tracker stats.

## Entities (stable per workspace)

- **Gym Tracker page**: `34f1055f-5461-80b8-9973-f07ad4745957`
- **Gym Diary (Sessions) data source**: `collection://15edb51c-4b9e-43ad-af72-974f684d51a8`
- **Exercises data source**: `collection://bc144743-830c-401f-99ae-714dc63b5e65`
- **Sets data source**: `collection://4de5b5eb-a0ef-4a5b-8c57-22584b58992c`

## Existing page structure

```
<database url="Gym Diary"/>
---
## 📊 Stats
### Session efficiency
<database view: by week, with kg/min and Δ vs last>
### Muscle group balance
<database view: board grouped by muscle group>
---
<database url="Exercises"/>
<database url="Sets"/>
```

This skill inserts a `### Summary` block **above** `### Session efficiency`. Do not remove the existing views — they self-update.

## Step 1 — Pull sessions

Use `mcp__notion__notion-search` on the Sessions data source. Search caps at 25 per call — paginate by month if needed (`2026-04`, `2026-05`, …).

For each session, you need: title, Date, Type, Sport, Duration (min), Calories (formula), Status, RPE, Total volume (rollup), Total sets (rollup), kg/min (formula).

If a needed property isn't in the search result, fetch the page directly.

Only count sessions with `Status = Done` toward training stats. Skip "Not started" / "In progress" (those are templates / drafts).

## Step 2 — Compute stats

ISO week = Monday-start week. Use the `Week` formula already on Sessions, or compute from Date.

- **This week sessions**: count of Done sessions in current ISO week
- **This week volume**: sum of Total volume across this week
- **This week calories**: sum of Calories across this week
- **This week time**: sum of Duration (min)
- **This week avg RPE**: average of RPE
- **Current streak**: consecutive prior weeks (ending most recently) with ≥ 3 Done sessions. Break on a week with < 3.
- **PRs hit in last 14 days**: for each Exercise referenced by Sets in the last 14 days, check whether any Set's 1RM in that window equals Exercise's Best 1RM rollup. If so, mark the exercise+1RM as a PR hit.
- **Top 5 lifts (estimated 1RM)**: top 5 Exercises by `Best 1RM`. Include Last performed date.
- **Underworked muscle groups (last 7 days)**: list muscle groups (from Exercises.Muscle group through Sets) with **0** sets in the last 7 days. Don't list the ones that just weren't hit because of split rotation — only call out groups absent from the **last 14 days**.

## Step 3 — Update the Gym Tracker page

Use `mcp__notion__notion-update-page` with `update_content`. Find the anchor `## 📊 Stats\n### Session efficiency` and insert the Summary block between them.

### Required structure

```markdown
### Summary

<callout icon="🏋️" color="green_bg">
  **This week**: <N> sessions · <Vkg> kg volume · <Cal> cal · <Mmin> min · RPE avg <R>
  **Current streak**: <S> weeks at ≥ 3 sessions/week <emoji>
  **PRs hit (last 14 days)**: <list of Exercise — 1RM>, or "none"
  **Underworked (last 14 days)**: <list of muscle groups>, or "none — well balanced"
</callout>

#### Last 4 weeks

<table header-row="true">
  <tr><td>Week</td><td>Sessions</td><td>Volume (kg)</td><td>Calories</td><td>Avg kg/min</td></tr>
  <tr><td>YYYY-Www</td><td>N</td><td>V</td><td>C</td><td>X.X</td></tr>
  <!-- 4 rows, newest at top -->
</table>

#### Top 5 lifts (estimated 1RM)

<table header-row="true">
  <tr><td>Exercise</td><td>1RM (kg)</td><td>Last performed</td></tr>
  <tr><td>...</td><td>...</td><td>YYYY-MM-DD</td></tr>
  <!-- 5 rows -->
</table>
```

Use `<table>` Notion markdown, not pipe tables.

### Emoji indicators

- `🔥` streak ≥ 4 weeks
- `💪` streak ≥ 8 weeks
- `🏆` ≥ 1 PR hit this period
- (nothing) — nothing notable

## Step 4 — Sanity checks before saving

- Volume sums across weeks should match independent tally
- Sessions count matches the number of unique Session URLs aggregated this week
- Streak excludes the current week if it's still in progress (count it only if today is the last day of the week OR sessions ≥ 3 already)
- PRs reflect ALL history, not just the 14-day window (a "new PR" means the Set's 1RM equals the Exercise's all-time Best 1RM AND the Set is within last 14 days)

## What this skill does NOT do

- **Modify session/set/exercise rows** — read-only on those DBs
- **Compute calories or volume** — those are formulas; don't override
- **Re-introduce a manual Calories field** — formula stays
- **Touch the existing Session efficiency or Muscle group balance views** — they self-update
- **Suggest specific training programming** — that's interpretation, not summary. Surface the data; let the user decide.

## When to suggest a re-run

- After `/gym-log` creates a new session — offer to refresh the summary
- Weekly check-in (Sunday evening) — offer if the user asks "how was my week?"
