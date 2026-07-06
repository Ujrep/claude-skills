---
name: work-stats
description: Refresh the Stats page in Notion (monthly hours, earnings, taxes, net income). Use when the user asks to update stats, recalculate earnings/taxes, refresh the stats page, or add new hours to the Hours Log.
user_invocable: true
---

# Work Stats — Refresh Workflow

Use this when the user asks to update / refresh / recalculate the Stats page.

## Inputs the user must provide (or that must already be in memory)

Before computing anything, check memory for these values. If missing, ask the user **once**, then save them to memory under the type `user` so future runs don't re-prompt:

- **Hourly rate** (EUR) — the user's billed hourly rate
- **Client / project identifier** — used in any client-facing copy
- **Tax system** — defaults to Romanian PFA real system; override if user is in a different setup
- **Min gross salary (RON, current year)** — verify yearly; defaults to 4,050 RON for 2026 unless told otherwise

If any of these change (rate increase, new tax year, new client), update memory.

## Entities (do not guess — these are stable per workspace)

- **Stats page**: `34f1055f-5461-81f4-8d32-d5fee62361ea`
- **Hours Log database**: `15ae2893-071b-4c18-9abf-19fb057203e3` (under the Trackers page)
- **Hours Log data source**: `collection://c1eaa722-a204-41e2-8dc1-f9b88b2bfa63`
- **Hours Log properties**: `Date` (title, YYYY-MM-DD), `Work Date` (date), `Hours` (number)

(The pre-2026-07 Daily Work DB is trashed; its hours history was migrated into Hours Log on 2026-07-06. Never write to the old DB.)

## Step 1 — Pull data

Use `mcp__notion__notion-query-data-sources` (SQL mode) on `collection://c1eaa722-a204-41e2-8dc1-f9b88b2bfa63`:

```sql
SELECT Date, Hours FROM "collection://c1eaa722-a204-41e2-8dc1-f9b88b2bfa63" WHERE Hours IS NOT NULL ORDER BY Date ASC
```

For each row, capture `Date` (title in `YYYY-MM-DD` format) and `Hours`.

If hours are missing on an entry, fetch the page individually to read its property.

## Step 2 — Get a current exchange rate

Always fetch the **BNR reference rate** before computing taxes:

```
WebFetch https://www.bnr.ro/nbrfxrates.xml
prompt: "What is the EUR to RON exchange rate today? Give the EUR/RON number and date."
```

Use the returned rate as the EUR→RON conversion. Note the date the rate was published.

## Step 3 — Compute monthly totals

For each month present in the data:

- **Hours** = sum of `Hours`
- **Days** = count of entries with `Hours > 0`
- **Avg/day** = Hours ÷ Days (2 decimals)
- **Gross (€)** = Hours × `<hourly_rate>` (from memory/input)
- **Tax (€)** = Gross × `<effective_rate>` (computed in Step 4)
- **Net (€)** = Gross − Tax

## Step 4 — Tax model (Romanian PFA, real system)

Tax is **annualized projection-based**, applied as a flat effective rate per month for display. Recompute the effective rate each run, since it depends on projected annual income.

**Annual projection:**
1. Project annual gross: `gross_ytd × 12 / months_elapsed_decimal`
2. Convert to RON using the BNR rate

**Annual contributions (RON, current year rules):**
- **CAS (pension)** = 25% on a base of:
  - `12 × min_gross_salary` if `12 × min_gross ≤ annual_net_income < 24 × min_gross`
  - `24 × min_gross_salary` if `annual_net_income ≥ 24 × min_gross`
  - 0 otherwise
- **CASS (health)** = 10% × annual_net_income (capped at `60 × min_gross`)
- **Income tax** = 10% × (annual_net_income − CAS − CASS)

**Effective rate** = total annual taxes ÷ annual gross. Recompute every run — it shifts whenever the annual projection crosses a CAS bracket threshold.

## Step 5 — Update the Stats page

Use `mcp__notion__notion-update-page` with `command: replace_content` on the Stats page. Use the exact structure below.

### Required structure (top → bottom)

```markdown
## Earnings

<table header-row="true">
  <tr><td>Month</td><td>Hours</td><td>Days</td><td>Avg/day</td><td>Gross</td><td>Tax</td><td>Net</td></tr>
  <!-- rows newest-month first -->
  <!-- Total row at the bottom, all values bolded -->
</table>

*Rate: €<RATE>/h. Tax: ~<EFFECTIVE_RATE>% effective (Romanian PFA real system, projection-based). EUR→RON @ <BNR_RATE> (BNR, <BNR_DATE>). No expenses deducted.*

*Annual projection at current pace: **€<GROSS_ANNUAL> gross → €<TAX_ANNUAL> tax → €<NET_ANNUAL> net**.*

<callout icon="📈" color="blue_bg">
  **Year progress: €<YTD_GROSS> of €<PROJECTED_GROSS> projected gross — <PCT>%**
  <progress_bar_in_text>  <YTD_MONTHS> / 12 months elapsed (<PCT_TIME>%)
  <one_line_on_pace_status>
</callout>

### <Month YYYY> breakdown
- <YYYY-MM-DD> — <H>h
<!-- days newest first, only days with hours > 0 -->
```

### Rules

- **Sort order**: newest month at the top of the table. Within each breakdown, newest day at the top.
- **Currency**: all values in **EUR** in the display. Do RON math behind the scenes for taxes; do not show RON in the page.
- **Total row** is bold. Days = sum of all days. Avg/day = total hours ÷ total days.
- **One table only.** Do not split into "earnings" + "averages" tables.
- **No per-day expenses or RON breakdowns** in the page. Keep it terse.

## Step 6 — Quick sanity checks before saving

- Sum of monthly gross == total gross
- Sum of monthly tax + monthly net == monthly gross
- Days count matches the number of breakdown bullets
- BNR rate and date appear in the footnote

## When new data arrives

If the user provides hours for a date (e.g. "today I worked 6h"):

1. **Find-or-create — never blind-create.** Check the rows already pulled in Step 1 for that date.
   - **If a row for the date exists**: `update_properties` to set its `Hours`. Do NOT create a second row.
   - **If no row exists**: create one with `mcp__notion__notion-create-pages` to data source `c1eaa722-a204-41e2-8dc1-f9b88b2bfa63`. Set `Date` (YYYY-MM-DD), `date:Work Date:start` (+ `date:Work Date:is_datetime: 0`), `Hours`.
2. Then re-run Steps 1–5 to refresh the page.

**Duplicate guard**: one Hours Log row per date. If you ever find two rows with the same date, keep one and flag the duplicate to the user (the MCP has no delete tool).

## Things this skill deliberately does not do

- **Quarterly payment reminders** — Romanian PFA on real system pays annually via Declarația Unică (~May 25 the following year). Do not add quarterly payment callouts.
- **Expense deductions** — not modeled. If the user asks about deductible expenses, do not auto-compute deductions without explicit input.
- **Multi-year comparisons** — wait until multi-year data exists.
- **Norma de venit alternative tax system** — only real system is modeled.

## Caveats to surface when relevant

- Min gross salary is verified yearly. If government publishes a different figure than what's in memory, update it.
- The effective rate shifts when annual gross crosses the CAS bracket thresholds (12× and 24× min gross). Recompute every run.
- CASS has a floor (6× min gross) and cap (60× min gross). Most freelancers fall between these but verify on edge cases.
