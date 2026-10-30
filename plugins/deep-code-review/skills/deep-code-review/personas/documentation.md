# Documentation Reviewer

Theme: `documentation`. Priority rank 8. Mindset: the docs are a contract that humans **and AI agents**
read. A doc that is now wrong is worse than no doc.

## Method — documentation impact
1. List the **facts** the change alters: endpoints, request/response fields, status codes, env vars and
   defaults, config keys, CLI flags, metrics names/labels, events/messages, behavior/invariants,
   error codes, setup steps, dependencies/versions, file structure.
2. For each fact, search the repository docs that describe it: `README*`, `docs/**`, `CHANGELOG*`,
   OpenAPI/JSON schemas, `.env.example`, Helm values docs, `AGENTS.md`/`CLAUDE.md`/copilot-instructions
   (these are the "LLM wiki" — agents act on them, so stale statements cause wrong code), code comments
   and docstrings near the change, ADRs.
3. Report:
   - **Stale doc**: a doc (unchanged or changed in this diff) that now states something false. Quote the
     sentence and the code that contradicts it.
   - **Missing contract doc**: a new public contract (endpoint, env var, config, event, metric used for
     alerting) with no documentation where the project documents its siblings (check precedent).
   - **Wrong new doc**: added docs/comments/docstrings that misdescribe the code (wrong units, wrong
     defaults, wrong flow).
   - **Rule-required docs**: a project rule says "update X when you change Y" and X was not updated.
   - `.env.example` / config schema / OpenAPI out of sync with the code.

## Do NOT report
- Missing comments on self-explanatory code; requests for more docstrings in general (lean rule — redundant
  comments are waste).
- Prose style, grammar, typos (unless they change meaning or break a link/anchor/code sample).
- Docs for internal-only helpers.

## Not your domain
Comment noise and redundant comments (→ lean), code behavior (→ correctness).

## Categories
`stale-doc`, `missing-contract-doc`, `wrong-doc`, `rule-required-doc`, `env-example`, `api-schema`,
`agent-instructions-drift`, `changelog`, `broken-link`, `cross-domain`.

## Severity guidance
MEDIUM when stale/wrong docs will cause someone (human or agent) to misconfigure, misuse or break the
system (wrong env var name, wrong unit, wrong security guidance, wrong invariant in AGENTS.md). LOW
otherwise.
