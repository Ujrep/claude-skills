# The Lean Code Rule

> **Every line of code and every test in a change must earn its place.** Code that adds no behavior,
> and tests that would not fail if the behavior broke, are defects of the change, not neutral extras.

This rule binds three parties:

1. **The `lean-reviewer` persona** reports violations in the diff.
2. **Every other persona** must not *suggest* violations: a suggestion never adds speculative code,
   wrappers, flags, defensive checks for impossible states, or tests that cannot fail.
3. **The challenge reviewer** rejects findings whose only remedy is "add more tests/code" without a
   concrete risk (`fp_lean_rule_unnecessary_addition`), and suppresses suggestions that bloat the code.

Sources: Kent Beck's four rules of simple design (passes the tests, reveals intention, **no duplication,
fewest elements**) — martinfowler.com/bliki/BeckDesignRules.html; Fowler's *Refactoring* smells
(Speculative Generality, Dead Code, Lazy Element, Middle Man, Duplicated Code, Comments);
test-smell catalogs (van Deursen et al.; tsDetect, arxiv.org/abs/2303.04234); YAGNI.

---

## A. Unnecessary or useless tests

Report a test added or changed in the diff when it matches one of these **and** you can state why it
gives no protection. Ask the mutation question for each: *"If I subtly broke the code under test
(flip a condition, drop a field, return early), would this test fail?"* If no — it is a finding.

| Smell | What it looks like | Why it is waste |
|-------|-------------------|-----------------|
| **Tautological test** | Asserts what the test itself set up; expected value computed with the same code under test; `expect(mock).toHaveBeenCalled()` right after calling the mock | Cannot fail |
| **Testing the mock** | Unit under test is itself mocked/stubbed, or every collaborator is mocked so the test only re-states the implementation's call sequence | Verifies wiring, not behavior; breaks on every refactor |
| **Framework/language test** | Tests that a getter returns what the setter set, that a constant equals itself, that `JSON.parse` parses, that the ORM saves, that a DI container injects | Tests someone else's code |
| **Duplicate test** | Same behavior and same equivalence class as an existing test (possibly in another file), only different literals | Maintenance cost, no new coverage |
| **Empty / assertion-free test** | No assertion, only "does not throw" where throwing is impossible, `expect(true).toBe(true)`, a skipped/`.only`/commented-out test | Passes by construction or blocks the suite |
| **Snapshot abuse** | Large snapshot of incidental output (whole objects, HTML, logs) with no targeted assertion | Approved blindly on update; asserts nothing intentional |
| **Implementation-detail test** | Asserts private functions, internal call counts/order, exact log strings or SQL text when the observable outcome is what matters | Fails on harmless refactors, passes on real bugs |
| **Sleepy / flaky test** | `sleep`/fixed timers to wait for async work, real clock, real network, order dependence | Slow and non-deterministic |
| **Coverage padding** | Tests that exist to raise a coverage number (e.g. calling a function and ignoring the result) | Inflates the metric, hides real gaps |
| **Over-parametrized / combinatorial** | Dozens of cases from the same equivalence class | Cost without discrimination; keep boundaries + one representative |
| **Assertion roulette / eager test** | One test checks many unrelated behaviors with no messages | Failures are undiagnosable; split or trim to the behavior that matters |

**Not a finding** (do not report): a test that pins a past bug (regression test), boundary and error-path
tests, contract tests at a service boundary, a characterization test added before a refactor, a test that
an explicit project rule requires.

## B. Useless or unnecessary production code

| Smell | What it looks like |
|-------|-------------------|
| **Dead code** | New function/export/branch/parameter/config key/metric/env var that nothing in the repo reads or calls; unreachable branch after an exhaustive check; commented-out code |
| **Speculative generality (YAGNI)** | Interface/abstract class/factory/strategy/registry with one implementation and no second consumer in the change; options/flags/hooks nothing sets; generic type parameters only ever bound to one type |
| **Middle man / lazy element** | Wrapper that only forwards to another function with the same arguments; a class whose only method calls one other method; a one-line helper used once that hides a clearer inline expression |
| **Duplicated logic** | Re-implements a helper/utility that already exists in the repo or its dependencies (search before reporting) |
| **Defensive checks for impossible states** | Null/type checks on values the type system, schema validation or a prior guard already guarantees; `try/catch` around code that cannot throw; catch-log-rethrow layers that add nothing; fallbacks that can never run |
| **Redundant comments** | Comments that restate the next line ("// increment i"), changelog-style comments ("// added for JIRA-123"), JSDoc that repeats the signature with no extra meaning |
| **Unused dependency** | New package in a manifest that the code never imports, or a heavy dependency for a one-liner the platform already provides |
| **Over-configured** | New env var/config with exactly one value everywhere and no documented reason to vary |
| **AI-slop patterns** | Verbose boilerplate, excessive logging of every step, broad `catch (e) {}` / `except Exception: pass`, re-declared types identical to existing ones, hallucinated APIs or packages (verify every new import exists in the installed version) |
| **Scope creep** | Unrelated refactors, renames or reformatting mixed into a functional change (makes review and revert harder) |

**Not a finding**: validation at a **trust boundary** (HTTP input, queue messages, external API responses,
env/config at startup) — that is required, not defensive bloat; an abstraction that the same change already
uses from ≥ 2 places; code required by an explicit project rule; public API surface intentionally added for
external consumers (check docs/changelog).

## C. Evidence a lean finding needs

- **Dead code:** the search you ran proving nothing references it (`grep`/`rg` for the symbol, exports
  index, dynamic access by string, DI/registration, reflection). Dynamic references are common — search
  for the string name too.
- **Duplicate:** the path and line of the existing helper or test.
- **Impossible state:** the guard/type/schema that already guarantees it.
- **Useless test:** the mutation you applied mentally and why the test would still pass.

## D. Severity on the lean scale

- **MEDIUM** — dead or duplicated code that will drift (a second implementation of a business rule), a test
  that gives *false confidence* on a risky path (it looks like coverage of auth/money/data integrity but
  cannot fail), a new unused dependency (supply-chain surface), scope creep that hides a behavior change.
- **LOW** — everything else in this file.
- Never HIGH/CRITICAL unless the waste *is* a real defect (e.g. a defensive `catch` that swallows a real
  error → that is a correctness finding, reported by correctness).

## E. Applying the rule to your own suggestions

Before any persona writes `suggestion`, it checks: *is this the smallest change that removes the defect?*
Do not suggest new abstractions, helper modules, config flags, extra logging, or tests unless the finding
is about their absence **and** the absence has a concrete consequence. "Add a test" is only a valid
suggestion when the change alters risky behavior (auth, money, persistence, concurrency, parsing,
public contracts, a bug fix) that no existing test exercises.
