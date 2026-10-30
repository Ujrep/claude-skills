#!/usr/bin/env bash
# Runs deterministic, read-only checks and stores their output in $CTX/tool-signals/.
# Never fixes, formats, installs or downloads project dependencies.
# Usage: tool-signals.sh <CTX> [--tests] [--audit]
#   --tests  also run the project's unit tests (can be slow)
#   --audit  also run dependency vulnerability audits (needs network)
# Bash 3.2 compatible.
set -uo pipefail

CTX="${1:?usage: tool-signals.sh <CTX> [--tests] [--audit]}"; shift
RUN_TESTS=0; RUN_AUDIT=0
for a in "$@"; do
  case "$a" in --tests) RUN_TESTS=1 ;; --audit) RUN_AUDIT=1 ;; *) echo "unknown flag $a" >&2; exit 64 ;; esac
done

ROOT=$(jq -r .root "$CTX/meta.json")
cd "$ROOT" || exit 2
OUT="$CTX/tool-signals"; mkdir -p "$OUT"
SUMMARY="$OUT/SUMMARY.txt"; : > "$SUMMARY"
LIMIT="${DEEP_REVIEW_TOOL_TIMEOUT:-300}"

# Portable timeout (macOS has no `timeout`).
with_timeout() { perl -e 'alarm shift; exec @ARGV' "$LIMIT" "$@"; }

run() {  # run <name> <cmd...>
  local name="$1"; shift
  local start=$(date +%s)
  with_timeout "$@" > "$OUT/$name.txt" 2>&1
  local rc=$?
  local secs=$(( $(date +%s) - start ))
  [ $rc -eq 142 ] && echo "TIMEOUT after ${LIMIT}s" >> "$OUT/$name.txt"
  printf '%-22s exit=%-4s %4ss  %s\n' "$name" "$rc" "$secs" "$*" >> "$SUMMARY"
}

# Changed, existing, reviewable files (no deletions, no skipped files).
awk -F'\t' '$1 !~ /^D/ {print $NF}' "$CTX/files.txt" | while IFS= read -r f; do
  [ -f "$f" ] && ! grep -qF "$f" "$CTX/skipped-files.txt" 2>/dev/null && echo "$f"
done > "$OUT/changed-files.txt"

JS_FILES=$(grep -E '\.(m|c)?(j|t)sx?$' "$OUT/changed-files.txt" | tr '\n' ' ')
PY_FILES=$(grep -E '\.py$' "$OUT/changed-files.txt" | tr '\n' ' ')
BIN="$ROOT/node_modules/.bin"

has_script() { [ -f package.json ] && jq -e --arg s "$1" '.scripts[$s] // empty' package.json >/dev/null 2>&1; }

# --- Built-in secret scan on added lines (fast, no dependencies) ---
# Provider-format keys are always reported; generic keyword assignments are skipped in test/fixture files.
awk '
  /^\+\+\+ / { file=substr($0,7); next }
  /^\+/ {
    line=substr($0,2)
    if (line ~ /(AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|xox[baprs]-[0-9A-Za-z-]{10,}|gh[pousr]_[0-9A-Za-z]{30,}|github_pat_[0-9A-Za-z_]{30,}|sk-[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{35}|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,})/) {
      print "provider-key\t" file "\t" line; next }
    if (file ~ /(^|\/)(test|tests|__tests__|spec|fixtures?|mocks?|__mocks__)\/|\.(test|spec)\.[a-z]+$|\.example$|\.sample$/) next
    l=tolower(line)
    if (l ~ /(password|passwd|secret|api[_-]?key|client[_-]?secret|access[_-]?token|private[_-]?key)["\047 ]*[:=] *["\047][^"\047 $<{]{12,}["\047]/) print "keyword\t" file "\t" line
  }' "$CTX/review.diff" > "$OUT/secret-patterns.txt" 2>/dev/null
printf '%-22s hits=%s (provider-format keys + keyword assignments outside tests; verify each)\n' \
  "secret-patterns" "$(grep -c . "$OUT/secret-patterns.txt")" >> "$SUMMARY"

# --- Unicode trojan-source / hidden characters on added lines ---
perl -CSD -ne 'print "$.: $_" if /^\+/ && /[\x{202A}-\x{202E}\x{2066}-\x{2069}\x{200B}-\x{200D}\x{FEFF}]/' \
  "$CTX/review.diff" > "$OUT/hidden-unicode.txt" 2>/dev/null
printf '%-22s hits=%s\n' "hidden-unicode" "$(grep -c . "$OUT/hidden-unicode.txt")" >> "$SUMMARY"

# --- Suppressions added in the change ---
grep -nE '^\+' "$CTX/review.diff" | grep -E \
  '(eslint-disable|@ts-ignore|@ts-expect-error|@ts-nocheck|# *noqa|# *type: *ignore|nosec|NOSONAR|istanbul ignore|c8 ignore|\.only\(|\.skip\(|xit\(|xdescribe\(|@pytest\.mark\.skip|@Disabled)' \
  > "$OUT/suppressions.txt" 2>/dev/null
printf '%-22s hits=%s\n' "suppressions" "$(grep -c . "$OUT/suppressions.txt")" >> "$SUMMARY"

# Project tooling runs on the working tree, so it is meaningless when the tree is not the reviewed head.
if grep -q 'NOT the PR head' "$CTX/notes.txt" 2>/dev/null; then
  printf '%-22s SKIPPED: working tree is not the reviewed head (check out the PR to enable)\n' "project-tooling" >> "$SUMMARY"
  cat "$SUMMARY"; exit 0
fi

# --- JavaScript / TypeScript ---
if [ -f package.json ] && [ ! -d node_modules ]; then
  printf '%-22s SKIPPED: node_modules missing (run npm ci to enable lint/typecheck/tests)\n' "js-tooling" >> "$SUMMARY"
elif [ -f package.json ]; then
  if [ -n "$JS_FILES" ] && [ -x "$BIN/eslint" ]; then
    # shellcheck disable=SC2086
    run eslint "$BIN/eslint" --no-fix --format unix $JS_FILES
  elif has_script lint; then
    run lint npm run --silent lint
  fi
  if has_script typecheck; then run typecheck npm run --silent typecheck
  elif [ -x "$BIN/tsc" ] && [ -f tsconfig.json ]; then run typecheck "$BIN/tsc" --noEmit -p tsconfig.json
  fi
  [ -x "$BIN/knip" ] && run knip "$BIN/knip" --no-progress --reporter compact
  [ -x "$BIN/ts-prune" ] && run ts-prune "$BIN/ts-prune"
  if [ $RUN_TESTS -eq 1 ] && has_script test; then run tests env CI=true npm test --silent; fi
  [ $RUN_AUDIT -eq 1 ] && run npm-audit npm audit --omit=dev --audit-level=moderate
fi

# --- Python ---
if [ -n "$PY_FILES" ]; then
  # shellcheck disable=SC2086
  command -v ruff >/dev/null && run ruff ruff check --no-fix $PY_FILES
  # shellcheck disable=SC2086
  command -v mypy >/dev/null && run mypy mypy $PY_FILES
  # shellcheck disable=SC2086
  command -v vulture >/dev/null && run vulture vulture $PY_FILES
  # shellcheck disable=SC2086
  command -v bandit >/dev/null && run bandit bandit -q $PY_FILES
  if [ $RUN_TESTS -eq 1 ] && command -v pytest >/dev/null; then run tests pytest -q -x; fi
  [ $RUN_AUDIT -eq 1 ] && command -v pip-audit >/dev/null && run pip-audit pip-audit
fi

# --- Go ---
if [ -f go.mod ] && command -v go >/dev/null; then
  run go-vet go vet ./...
  [ $RUN_TESTS -eq 1 ] && run tests go test ./...
fi

# --- Shell / workflows / generic scanners (only if installed locally) ---
SH_FILES=$(grep -E '\.(sh|bash)$' "$OUT/changed-files.txt" | tr '\n' ' ')
# shellcheck disable=SC2086
[ -n "$SH_FILES" ] && command -v shellcheck >/dev/null && run shellcheck shellcheck $SH_FILES
if grep -q '^\.github/workflows/' "$OUT/changed-files.txt" && command -v actionlint >/dev/null; then
  run actionlint actionlint
fi
command -v gitleaks >/dev/null && run gitleaks gitleaks detect --no-banner --redact --log-opts="$(jq -r .base_sha "$CTX/meta.json")..HEAD"
command -v semgrep >/dev/null && [ -s "$OUT/changed-files.txt" ] && \
  run semgrep semgrep scan --metrics off --quiet --error --config p/default $(tr '\n' ' ' < "$OUT/changed-files.txt")
[ $RUN_AUDIT -eq 1 ] && command -v osv-scanner >/dev/null && run osv-scanner osv-scanner scan source -r .

cat "$SUMMARY"
