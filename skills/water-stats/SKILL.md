---
name: water-stats
description: Refresh the Water Tracker stats section in Notion (daily totals, goal hit rate, streaks, averages — all against the 3000 ml/day goal). Use when the user asks to refresh water stats, see hydration history, or check progress toward the daily goal.
user_invocable: true
---

# Water Tracker Stats — Refresh Workflow

Use this when the user asks to update / refresh / show water consumption stats.

## Entities

- **Water Tracker page**: `34e1055f-5461-809d-9778-d937a4da2576`
- **Drinks Log data source**: `collection://e253a790-7d40-46f8-8388-fc09b9924fa9`
- **Properties on Drinks Log**:
  - `Drink` (title)
  - `Type` (select: Water, Coffee, Tea, Zero-sugar)
  - `Amount` (number, ml)
  - `Logged` (created_time, ISO)
  - `Day` (formula, `formatDate(Logged, "YYYY-MM-DD")`)
  - `% of goal` (formula, `format(round(Amount / 30)) + "%"`)

## Constants

- **Daily goal**: 3000 ml
- **Default drink amounts** (matches the buttons; form drinks may differ): Water 330, Coffee 200, Tea 250, Zero-sugar 330

## Step 1 — Pull all drink entries

Use `mcp__notion__notion-search` with `data_source_url=collection://e253a790-7d40-46f8-8388-fc09b9924fa9`. Search caps at 25 results — paginate by varying query terms (`water`, `coffee`, `tea`, `zero`, plus date strings) until results stabilize.

For each entry, you need `Logged` date and `Amount`. If a search result doesn't surface Amount, fetch the page directly with `mcp__notion__notion-fetch`.

To minimize fetches: batch-fetch only entries not already cached. If a refresh was done recently, you can skip pulling pre-existing entries and just pull anything `Logged > last_refresh_timestamp`.

## Step 2 — Compute stats

Group drinks by `Day` (the formatDate result). For each day, compute:

- **Total ml** = sum of `Amount` for that day
- **Goal hit?** = Total ml ≥ 3000
- **% of goal** = round(Total ml / 30)

Then aggregate across days:

- **Days tracked** = count of distinct days with ≥1 drink
- **Days hitting goal** = count where Total ml ≥ 3000
- **Goal hit rate** = Days hitting goal ÷ Days tracked × 100
- **Average daily ml** = sum(Total ml) ÷ Days tracked
- **Best day** = max(Total ml) and which date
- **Current streak** = consecutive days from today backwards that hit the goal (break on miss; include today if hit)
- **Last 7 days** = last 7 calendar days' totals (whether or not drinks were logged)

## Step 3 — Update the Water Tracker page

### Page layout (preserve this order)

1. Hydration Dashboard callout
2. `## 💧 Quick add` — buttons
3. `## 📅 Today` — today's drinks view
4. `## 📊 Stats` — this section
5. Raw `View of Drinks Log` database at bottom

Do **not** re-introduce a `## 📒 Drinks Log — by day` section — Stefan removed it.

Place the `## 📊 Stats` section between the **Today** view and the bottom `View of Drinks Log` database.

Use `mcp__notion__notion-update-page` with `update_content` command. Use surgical edits on the callout block and table rows to keep button references intact.

### Required structure

```markdown
## 📊 Stats

<callout icon="💧" color="blue_bg">
  **Today**: <today_ml> / 3,000 ml — <today_pct>% <emoji_indicator>
  **7-day average**: <avg_7d> ml/day
  **Goal hit rate**: <hits>/<days> days (<rate>%)
  **Current streak**: <streak> days <emoji>
  **Best day**: <best_date> — <best_ml> ml
</callout>

### Last 7 days

| Date | Total | Goal | Status |
|---|---|---|---|
| <YYYY-MM-DD> | <ml> | 3,000 | ✅/❌ <pct>% |
<!-- 7 rows, newest at top -->
```

Use the `<table>` Notion markdown for the daily table, not Markdown pipe-tables (which Notion-flavored markdown renders inconsistently).

### Emoji indicators

- `🔥` = streak ≥ 3 days
- `💪` = streak ≥ 7 days
- `✅` = day hit goal
- `❌` = day missed goal
- `🥇` = best day ever
- (nothing) = nothing notable

## Step 4 — Sanity checks before saving

- Sum of Last 7 days totals matches independent calc
- Streak excludes today if it's still in progress (no full day yet) — only count today if currently at ≥ 3000 ml
- Best day reflects ALL history, not just the 7-day window

## Things this skill does NOT do

- **Modify buttons** — buttons stay as they are (just add to Drinks Log)
- **Modify the Today view** — it self-updates
- **Add new drinks** — that's the user's job via buttons or form
- **Modify the `% of goal` formula** — already in place
- **Touch Today's Progress or Days legacy databases** — they were removed earlier; do not re-introduce

## When to suggest a re-run

After the user mentions logging many new drinks, or asks "how am I doing on water?" — gently offer to refresh.
