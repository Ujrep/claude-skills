# Observation Format and Severity

Every persona returns **only** a JSON object:

```json
{
  "persona": "security",
  "coverage": { "files_reviewed": ["src/a.ts"], "hunks_reviewed": 12, "files_skipped": [] },
  "observations": [
    {
      "id": "security-1",
      "theme": "security | correctness | performance | architecture | operations | lean | standards | documentation | i18n",
      "category": "<persona category slug>",
      "priority": "CRITICAL | HIGH | MEDIUM | LOW",
      "confidence": "HIGH | MEDIUM | LOW",
      "location": { "file": "path/from/repo/root.ext", "line": 42, "end_line": 45 },
      "observation": "What is wrong, stated as a fact, with `code refs`.",
      "trigger": "The concrete input/state/sequence that makes it happen, and who can cause it.",
      "concern": "The observable consequence (wrong value, crash, leak, data loss, exposure, cost).",
      "evidence": [
        "Changed line `x` does Y (review.diff hunk @@ -10,6 +10,9 @@)",
        "Searched `rg 'sanitize\\(' src/` — no caller sanitizes before this sink",
        "Rule: CLAUDE.md 'Gotchas' bullet 3 requires …"
      ],
      "pr_caused": "introduced | worsened | made-reachable",
      "references": ["CWE-918", "OWASP API7:2023"],
      "suggestion": { "description": "Imperative fix.", "code": "optional minimal replacement" },
      "uncertainty_reason": "Required when confidence is MEDIUM or LOW.",
      "history": { "kind": "new | recurring | addressed", "thread_id": null }
    }
  ],
  "summary": "N findings: …"
}
```

## Field rules

- **Exact types** (output is parsed mechanically; do not improvise shapes): raw JSON only, no code
  fences. `priority` ∈ `CRITICAL|HIGH|MEDIUM|LOW` and `confidence` ∈ `HIGH|MEDIUM|LOW` (uppercase).
  `theme` is your persona name, not a title. `pr_caused` is one of the three strings, never a boolean.
  `evidence` is an array of strings. `suggestion` is an object `{description, code?}`. `history` is
  `{kind, thread_id}`. `coverage.files_reviewed` is an array of paths.
- **Required:** `id`, `theme`, `category`, `priority`, `confidence`, `location.file`, `location.line`,
  `observation`, `trigger`, `concern`, `evidence` (≥ 1 entry, at least one being a verification you
  performed), `pr_caused`.
- `location.line` is a line in the **new** file version that is inside a diff hunk (added, modified or
  context line). Deleted lines cannot carry findings; anchor on the nearest surviving line and say so.
  Code read outside the diff is context only.
- `pr_caused`: findings must be caused by the change: the change **introduced** the defect, **worsened**
  it, or **made-reachable** a pre-existing defect (new caller, changed contract). Pre-existing issues the
  change does not touch are not reported (mention them in `summary` at most).
- `references`: CWE / OWASP / ASVS ids, project rule file + section, or library doc URL. Optional but
  expected for security, standards and documentation themes.
- `suggestion` only when you are confident of the fix and it follows the Lean Code Rule section E.
  Before writing executable `code`, mentally apply it and walk the contract states (first attempt,
  replay after success, replay after partial failure, concurrent duplicate, dependency recovery). If any
  state stays broken, give only `description` stating the invariant a correct fix must keep.
- `history`: only in PR/re-review mode. `recurring` = same mechanism already raised in an existing
  review thread (give its id); `addressed` = an earlier thread on this mechanism was fixed or answered
  convincingly — do not re-raise those.

## Phrasing

- State claims, not questions. No "consider…", "might want to…", "did you…?". Resolve what is lookupable,
  then assert it. Residual doubt goes to `confidence` / `uncertainty_reason`.
- Name the concrete trigger ("a `limit=0` query param", "SQS redelivery after a timeout"), not "edge cases".
- Use markdown backticks for code identifiers, paths, values.

## Priority (provisional — the challenge reviewer owns the final value)

| Priority | Meaning |
|----------|---------|
| CRITICAL | Exploitable vulnerability, data loss/corruption, outage for all callers, broken deploy/rollback |
| HIGH | Manifests under normal usage or ordinary transient faults; must fix before merge |
| MEDIUM | Realistic edge case, defense-in-depth on a real boundary, maintainability cost with evidence |
| LOW | Small but measurable benefit (most lean/standards/docs findings) |
| *don't report* | Taste, alternatives to a valid approach, education, vague "could be better" |

### Impact severity floor

A verified defect whose **realistic** trigger (normal operation, retries/restarts/network stalls, or an
untrusted caller) produces any of the following is **at least HIGH** regardless of theme:

- **Unbounded wait** — hang, deadlock, missing/ineffective timeout, leaked process/handle.
- **Data loss or corruption** — persisted, transmitted or returned data wrong, truncated, duplicated, lost.
- **Security boundary weakened** — authn, authz, tenant isolation, secret handling, untrusted-input validation.
- **Hard failure on a normal path** — crash/unhandled error on input ordinary callers produce.
- **Silent wrong result on a normal path** — the primary operation returns a wrong answer without error.

CRITICAL when broad and unrecoverable (persisted corruption, remotely reachable security break, outage
for every caller). The floor never raises style, naming, docs, test-quality, lean or bounded-performance
findings. Keep MEDIUM when an existing control contains and recovers the consequence — name the control.

## Confidence

| Confidence | Meaning |
|------------|---------|
| HIGH | Verified the defect exists and is not mitigated anywhere (other changed files, middleware, framework, callers) |
| MEDIUM | Mechanism is clear but one premise (caller, config, runtime) could not be checked |
| LOW | Plausible; should be rare — most LOW candidates should be dropped instead |

## Conventional Comments mapping (used in the final report and PR comments)

| Final priority | Label |
|----------------|-------|
| CRITICAL / HIGH | `issue (blocking):` |
| MEDIUM | `issue (non-blocking):` or `suggestion (non-blocking):` when it is an improvement |
| LOW | `nitpick (non-blocking):` |
| latent | `note (non-blocking):` |
