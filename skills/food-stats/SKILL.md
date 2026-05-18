---
name: food-stats
description: Refresh the Food Tracker stats section in Notion (daily kcal + macros, protein hit rate, calorie compliance, current streak, last 7 days). Use when the user asks to refresh food stats, see eating history, or check progress vs daily targets.
user_invocable: true
---

# Food Tracker Stats — Refresh Workflow

Use this when the user asks to update / refresh / show calorie or macro stats.

## Inputs the user must provide (or that must already be in memory)

Check memory for these. If missing, ask **once** and save under the type `user`:

- **Daily calorie target** (kcal) — ceiling; below it = compliant
- **Daily protein target** (grams) — floor; at/above = hit
- **Bodyweight** (kg) — used for protein-per-kg sanity check

Default if user hasn't set: 2,000 kcal · 140g protein · 88kg.

## Entities (stable per workspace)

- **Food Tracker page**: `3641055f-5461-8100-8544-f1f67a66297e`
- **Foods data source**: `collection://06906287-5c86-43a1-b968-389a47664f97`
- **Food Log data source**: `collection://f5418177-17bf-4a07-84f8-880f2c380bfc`

## Food Log properties

- `Entry` (title) — free-form label
- `Date` (date) — meal date
- `Meal` (select: Breakfast / Lunch / Dinner / Snack)
- `Food` (relation → Foods)
- `Grams` (number)
- `Calories`, `Protein`, `Fat`, `Carbs` — formulas, auto-computed from Food × Grams / 100. **Read these for stats; never set.**
- `Logged` (created_time)

## Step 1 — Pull entries

Use `mcp__notion__notion-search` with `data_source_url=collection://f5418177-17bf-4a07-84f8-880f2c380bfc`. Search caps at 25 per call — paginate by date or meal name as needed.

For each entry, you need `Date`, `Calories`, `Protein`, `Fat`, `Carbs`. If the search result doesn't expose the formula results, fetch the page directly.

To minimize fetches: if a refresh happened recently, only re-pull entries `Logged > last_refresh_timestamp`.

## Step 2 — Compute stats

Group entries by `Date`. For each day:

- **kcal** = sum of `Calories`
- **P** = sum of `Protein` (g)
- **F** = sum of `Fat` (g)
- **C** = sum of `Carbs` (g)
- **Protein hit?** = P ≥ protein_target
- **Calorie compliant?** = kcal ≤ calorie_target
- **P/kg ratio** = P ÷ bodyweight

Then aggregate:

- **Days tracked** = count of distinct days with ≥1 entry
- **Protein hit rate** = days hitting protein / days tracked
- **Calorie compliance rate** = days under target / days tracked
- **Average kcal/day** = sum(kcal) ÷ days tracked
- **Average P/day** = sum(P) ÷ days tracked
- **Best protein day** = max(P) and which date
- **Current protein streak** = consecutive days from today backwards where P ≥ target (break on miss; exclude today if still in progress unless already hit)
- **Last 7 days** = last 7 calendar days' totals

## Step 3 — Update the Food Tracker page

### Page layout (preserve this order)

1. Daily targets callout
2. `## 📅 Today` — inline Food Log view
3. `## 📊 Stats` — this section (insert/refresh here)
4. `## 📚 Foods catalog` — inline Foods view

Place `## 📊 Stats` between `## 📅 Today` and `## 📚 Foods catalog`.

Use `mcp__notion__notion-update-page` with `update_content`. Use surgical edits on the callout block and table rows.

### Required structure

```markdown
## 📊 Stats

<callout icon="🎯" color="green_bg">
  **Today**: <kcal> / <kcal_target> kcal · <P>g P (<P_pct>%) · <F>g F · <C>g C <emoji>
  **7-day average**: <avg_kcal> kcal/day · <avg_P>g P/day
  **Protein hit rate**: <hits>/<days> days (<rate>%)
  **Calorie compliance**: <under>/<days> days (<rate>%)
  **Current protein streak**: <streak> days <emoji>
  **Best day**: <best_date> — <best_P>g protein 🥇
</callout>

### Last 7 days

<table header-row="true">
  <tr><td>Date</td><td>kcal</td><td>P</td><td>F</td><td>C</td><td>Status</td></tr>
  <tr><td>YYYY-MM-DD</td><td>N</td><td>Ng</td><td>Ng</td><td>Ng</td><td>✅/❌</td></tr>
  <!-- 7 rows, newest at top -->
</table>
```

Use `<table>` Notion markdown.

### Status column

For each day, status = combination of two flags:

- `✅` = both protein hit AND calorie compliant
- `🥩` = protein hit, but over calorie target
- `⬇️` = under calorie target, but missed protein
- `❌` = both missed
- `⏳` = today (in progress)

### Other emoji

- `🔥` streak ≥ 3 days
- `💪` streak ≥ 7 days
- `🥇` best protein day ever

## Step 4 — Sanity checks before saving

- Sum of Last 7 days kcal matches independent calc
- Streak excludes today if not full-day data yet (only count today if P ≥ target already)
- Best day reflects ALL history, not just the 7-day window
- Protein hit rate denominator = full days only (exclude today if partial)

## Things this skill does NOT do

- **Modify Foods catalog** — that's the user's job (or via /food-log)
- **Add new entries** — use the Notion UI or a future food-log skill
- **Override target values** — they live in memory; ask before changing
- **Track water** — that's the water-stats skill

## When to suggest a re-run

After a meal is logged or the user asks "how am I doing on calories today?" — gently offer to refresh.
