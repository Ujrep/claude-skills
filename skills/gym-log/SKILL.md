---
name: gym-log
description: Parse a freely-formatted workout transcript (typed or voice-memo dump) and create the matching Session + Sets in Notion. Use when the user pastes a workout summary like "push day 50min RPE 8, bench 60x8x3, incline DB 22x10x3..." and wants it logged.
user_invocable: true
---

# Gym Log — Workout Ingestion

Use this when the user pastes a workout summary (typically from a voice memo or quick text notes taken at the gym) and wants it logged to Notion.

## Entities (stable per workspace)

- **Gym Tracker page**: `34f1055f-5461-80b8-9973-f07ad4745957`
- **Gym Diary (Sessions) data source**: `collection://15edb51c-4b9e-43ad-af72-974f684d51a8`
- **Exercises data source**: `collection://bc144743-830c-401f-99ae-714dc63b5e65`
- **Sets data source**: `collection://4de5b5eb-a0ef-4a5b-8c57-22584b58992c`

## Session schema (Gym Diary)

- `Session` (title): e.g. "Chest day"
- `Date` (date)
- `Type` (select: Strength / Hypertrophy / Cardio / Mobility / Sport / Other)
- `Sport` (select: Squash / Badminton / Tennis / Running / Cycling / Swimming / Other) — only when Type=Sport
- `Duration (min)` (number)
- `RPE (1-10)` (number)
- `Notes` (text)
- `Status` (status: Not started / In progress / Done) — set to Done after logging
- `Previous session` (relation to same DB) — link to most recent same-name session
- `Calories` (formula, auto). Do **not** set manually.

## Exercise schema

- `Name` (title)
- `Muscle group` (multi-select: Chest, Back, Shoulders, Biceps, Triceps, Forearms, Core, Quads, Hamstrings, Glutes, Calves)
- `Equipment` (select: Barbell / Dumbbell / Machine / Cable / Bodyweight / Kettlebell / Other)
- `Weight convention` (select: Total / Per side) — default Total; set **Per side** for dumbbell / single-implement exercises so Volume doubles correctly

## Set schema

- `Set #` (number): 1, 2, 3… within (Session, Exercise)
- `Weight (kg)` (number): for per-side exercises, the weight **per implement** (e.g. 22kg per dumbbell)
- `Reps` (number)
- `RPE` (number, optional)
- `Exercise` (relation, required)
- `Session` (relation, required)
- `Notes` (text, optional)
- `Volume`, `1RM`, `Weight factor` are formulas/rollups. Do **not** set.

## Step 1 — Parse the transcript

Typical input shapes:

```
chest day, 50 min, RPE 8
bench 60x8x3
incline DB 22x10x3, 22x10, 20x10
dips bw x 10 x 3
triceps cable 30x12, 30x10, 27x8
```

Conventions to recognize:

- **First line**: session name + duration + RPE. e.g. `push day 50min RPE 8` or `legs 60min`. Canonical session names: `Push day` (chest, shoulders, triceps), `Pull day` (back, biceps, rear delts), `Leg day`, `Full body`, plus sport names. If the user says "chest day" or "arms day", map to `Push day` / `Pull day` (legacy aliases).
- **Each subsequent line**: an exercise. Format: `<exercise> <set-pattern>`.
- **Set pattern**:
  - `WxR` = one set of W kg × R reps
  - `WxRxS` = S sets of W × R (uniform)
  - `WxR, WxR, WxR` = explicit per-set list (variations allowed)
  - `bw` = bodyweight (Weight = 0)
  - `bw+N` = bodyweight + added load N kg (Weight = N)
- **Date**: if not explicit, default to today (from `currentDate` system reminder). User can prefix `yesterday: ...` or `2026-05-15: ...`.
- **Notes**: anything in `()` after a line goes into the Set's Notes for the relevant set(s); anything in `()` after the first line goes into the Session's Notes.

Ambiguity rule: parse literally. `bench 60x8` is one set of 60×8 unless an `x3` etc. suffix is present.

## Step 2 — Resolve exercises

For each exercise mention:

1. Search Exercises (`mcp__notion__notion-search` with `data_source_url=collection://bc144743-830c-401f-99ae-714dc63b5e65`) using the user's term.
2. If exactly one strong match — use it.
3. If multiple matches or no match — **ask** before deciding. Do not silently create.
4. When creating a new exercise, ask the user for `Muscle group`, `Equipment`, and `Weight convention`. Don't guess.

## Step 3 — Determine session Type / Sport

- Name matches a hypertrophy split (push, pull, legs, full body, upper, lower; or legacy aliases chest/arms/back/shoulders) → `Type = Hypertrophy` (default). Ask if it's actually Strength.
- Name matches a sport (squash, badminton, tennis, running, cycling, swimming) → `Type = Sport`, `Sport = <matched>`.
- Otherwise — ask.

When normalizing the title for storage, use the canonical name (`Push day`, `Pull day`, `Leg day`) regardless of what the user typed.

## Step 4 — Find Previous session

Query Sessions DB for the most recent prior session with:

- Same Type (and Sport if applicable), AND
- Same session title (case-insensitive, e.g. "Chest day" matches "chest day"), AND
- `Date < new session's Date`

Set as `Previous session`. If none, leave empty.

## Step 5 — Preview then write

Before writing anything, print a structured summary:

```
Session: <name>, <date>, <type>[/<sport>], <duration>min, RPE <rpe>
Previous session: <link or "none">
Exercises:
  - <exercise>: <weight>×<reps> [×N sets | per-set list]
  - ...
Total sets: <N>
```

Ask for confirmation. On "yes":

1. Create the Session page (parent: `data_source_id: 15edb51c-4b9e-43ad-af72-974f684d51a8`). Set `Session`, `date:Date:start`, `Type`, `Sport` (if any), `Duration (min)`, `RPE (1-10)`, `Notes`, `Status: Done`, `Previous session` (URL).
2. For each exercise, find or (after confirmation) create the Exercise page.
3. For each set: create the Set page (parent: `data_source_id: 4de5b5eb-a0ef-4a5b-8c57-22584b58992c`) with `Set #`, `Weight (kg)`, `Reps`, `Exercise` (URL), `Session` (URL of the new session).

## Step 6 — Report

Print:
- Link to the new Session page
- Set count
- Computed Calories (read back from the page after creation)
- Any new Exercises that were created

## Rules

- **Never set `Calories`** — formula, auto.
- **Never set `Volume` or `1RM` on Sets** — formula.
- **Per-side weight**: take the user's number at face value (e.g. DB Curl 22kg = 22kg per arm). The Volume formula doubles via the Exercise's Weight convention.
- **Set numbering**: per (Session, Exercise), starting at 1, incrementing.
- **Hours worked / Daily Work**: ignore — that's the work-context skill's domain.
- **No silent assumptions** about Muscle group / Equipment / Weight convention for new exercises — always ask.

## What this skill does NOT do

- Modify existing sessions or sets (use the Notion UI for edits)
- Compute calories or volume (formulas do it)
- Suggest training improvements (separate `gym-summary` skill)
- Delete sessions
- Backfill historical workouts unless explicitly asked

## When to suggest a re-run

If the user mentions they just finished a workout, or pastes a fresh transcript — gently offer to run this.
