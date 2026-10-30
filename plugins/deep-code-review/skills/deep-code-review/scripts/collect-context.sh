#!/usr/bin/env bash
# Collects everything the review needs into a private temp directory.
# Usage:
#   collect-context.sh [--scope branch|staged|unstaged|pr] [--base <ref>] [--pr <number>] [--since <sha>]
# Prints the output directory on the last stdout line. Bash 3.2 compatible (macOS).
set -uo pipefail

SCOPE="branch"
BASE=""
PR=""
SINCE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --scope) SCOPE="$2"; shift 2 ;;
    --base) BASE="$2"; shift 2 ;;
    --pr) PR="$2"; SCOPE="pr"; shift 2 ;;
    --since) SINCE="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 64 ;;
  esac
done

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repository" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT" || exit 2

OUT=$(mktemp -d "${TMPDIR:-/tmp}/deep-review.XXXXXX")
chmod 700 "$OUT"
mkdir -p "$OUT/rules"
: > "$OUT/notes.txt"

note() { printf '%s\n' "$*" >> "$OUT/notes.txt"; }

resolve_base() {
  if [ -n "$BASE" ]; then echo "$BASE"; return; fi
  local b
  b=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
  for cand in "$b" main master develop; do
    [ -z "$cand" ] && continue
    if git rev-parse --verify --quiet "origin/$cand" >/dev/null; then echo "origin/$cand"; return; fi
    if git rev-parse --verify --quiet "$cand" >/dev/null; then echo "$cand"; return; fi
  done
}

HEAD_SHA=$(git rev-parse HEAD)
BRANCH=$(git rev-parse --abbrev-ref HEAD)
BASE_REF=""
BASE_SHA=""
PR_HEAD_SHA=""
REVIEW_SHA="$HEAD_SHA"

case "$SCOPE" in
  pr)
    command -v gh >/dev/null || { echo "gh CLI is required for --pr" >&2; exit 2; }
    GH_PAGER=cat gh pr view "$PR" --json number,title,body,author,baseRefName,baseRefOid,headRefName,headRefOid,url,labels,isDraft,additions,deletions,changedFiles \
      > "$OUT/pr.json" || { echo "cannot read PR $PR" >&2; exit 2; }
    PR_BASE=$(jq -r .baseRefName "$OUT/pr.json")
    BASE_REF="origin/$PR_BASE"
    PR_HEAD_SHA=$(jq -r .headRefOid "$OUT/pr.json")
    REVIEW_SHA="$PR_HEAD_SHA"
    # The PR's real repo (honours GH_REPO and renamed/transferred repos whose local remote is stale).
    REPO=$(jq -r '.url' "$OUT/pr.json" | sed -E 's#^https://[^/]+/([^/]+/[^/]+)/pull/.*#\1#')
    PR_HOST=$(jq -r '.url' "$OUT/pr.json" | sed -E 's#^(https://[^/]+)/.*#\1#')
    # Fetch writes objects and FETCH_HEAD only; no local refs or remotes are changed.
    git fetch --quiet origin "$PR_BASE" "pull/$PR/head" 2>/dev/null \
      || git fetch --quiet "$PR_HOST/$REPO.git" "$PR_BASE" "pull/$PR/head" 2>/dev/null \
      || note "fetch of the PR head failed; the diff comes from gh and local files may not match the PR head"
    if git cat-file -e "$PR_HEAD_SHA^{commit}" 2>/dev/null; then
      PR_BASE_OID=$(jq -r '.baseRefOid // empty' "$OUT/pr.json")
      if git rev-parse --verify --quiet "$BASE_REF" >/dev/null; then BASE_COMMIT="$BASE_REF"
      elif [ -n "$PR_BASE_OID" ] && git cat-file -e "$PR_BASE_OID^{commit}" 2>/dev/null; then
        BASE_COMMIT="$PR_BASE_OID"; BASE_REF="$PR_BASE@$PR_BASE_OID"
      else BASE_COMMIT=""; fi
      [ -n "$BASE_COMMIT" ] && BASE_SHA=$(git merge-base "$BASE_COMMIT" "$PR_HEAD_SHA" 2>/dev/null || true)
    fi
    if [ -n "$BASE_SHA" ]; then
      FROM="$BASE_SHA"; [ -n "$SINCE" ] && FROM="$SINCE"
      git diff --find-renames "$FROM" "$PR_HEAD_SHA" > "$OUT/review.diff"
      git diff --find-renames --name-status "$FROM" "$PR_HEAD_SHA" > "$OUT/files.txt"
      git log --format='%h %s' "$BASE_SHA..$PR_HEAD_SHA" > "$OUT/commits.txt"
    else
      GH_PAGER=cat gh pr diff "$PR" > "$OUT/review.diff"
      GH_PAGER=cat gh pr diff "$PR" --name-only | sed $'s/^/M\t/' > "$OUT/files.txt"
      note "PR head not available locally: read PR files through gh, not the working tree"
    fi
    if [ "$HEAD_SHA" != "$PR_HEAD_SHA" ]; then
      note "working tree is NOT the PR head; read PR files with: git show $PR_HEAD_SHA:<path>"
    fi
    if [ -n "$REPO" ]; then
      GH_PAGER=cat gh api --paginate "repos/$REPO/pulls/$PR/comments" \
        --jq '.[] | {id, path, line, user: .user.login, body, in_reply_to_id, commit_id, created_at}' \
        > "$OUT/pr-review-comments.jsonl" 2>/dev/null || note "could not read PR review comments"
      GH_PAGER=cat gh api --paginate "repos/$REPO/pulls/$PR/reviews" \
        --jq '.[] | {id, user: .user.login, state, body, commit_id}' \
        > "$OUT/pr-reviews.jsonl" 2>/dev/null || note "could not read PR reviews"
    fi
    ;;
  staged)
    git diff --staged --find-renames > "$OUT/review.diff"
    git diff --staged --find-renames --name-status > "$OUT/files.txt"
    BASE_SHA="$HEAD_SHA"
    ;;
  unstaged)
    git diff --find-renames > "$OUT/review.diff"
    git diff --find-renames --name-status > "$OUT/files.txt"
    BASE_SHA="$HEAD_SHA"
    ;;
  branch)
    BASE_REF=$(resolve_base)
    if [ -z "$BASE_REF" ]; then
      note "no base branch found; reviewed uncommitted changes against HEAD"
      git diff HEAD --find-renames > "$OUT/review.diff"
      git diff HEAD --find-renames --name-status > "$OUT/files.txt"
      BASE_SHA="$HEAD_SHA"
      SCOPE="working-tree"
    else
      BASE_SHA=$(git merge-base "$BASE_REF" HEAD)
      FROM="$BASE_SHA"; [ -n "$SINCE" ] && FROM="$SINCE"
      # Branch commits plus uncommitted work, so a pre-push review sees everything.
      git diff --find-renames "$FROM" > "$OUT/review.diff"
      git diff --find-renames --name-status "$FROM" > "$OUT/files.txt"
      git log --format='%h %s' "$BASE_SHA..HEAD" > "$OUT/commits.txt"
      git ls-files --others --exclude-standard > "$OUT/untracked.txt"
      [ -s "$OUT/untracked.txt" ] && note "untracked files exist and are NOT in the diff: see untracked.txt"
    fi
    ;;
  *) echo "invalid scope: $SCOPE" >&2; exit 64 ;;
esac

[ -s "$OUT/review.diff" ] || note "EMPTY_DIFF"

# Binary / generated / lock / vendored files: checked for presence only, never reviewed line by line.
grep -E '(\.(png|jpe?g|gif|ico|webp|pdf|woff2?|ttf|eot|zip|gz|jar|so|dylib|snap)|\.min\.(js|css)|package-lock\.json|yarn\.lock|pnpm-lock\.yaml|composer\.lock|poetry\.lock|Cargo\.lock|go\.sum|\.generated\.[a-z]+|(^|/)(dist|build|vendor|node_modules)/.*)$' \
  "$OUT/files.txt" > "$OUT/skipped-files.txt" 2>/dev/null || true

# Files that trigger the supply-chain / CI / infrastructure checklist.
grep -E '((^|/)(package\.json|requirements[^/]*\.txt|pyproject\.toml|setup\.py|go\.mod|pom\.xml|build\.gradle(\.kts)?|composer\.json|Gemfile|Cargo\.toml|\.npmrc|\.nvmrc|Makefile|Dockerfile[^/]*|docker-compose[^/]*|compose\.ya?ml)|lock|\.github/workflows/|\.github/actions/|\.gitlab-ci|Jenkinsfile|\.tf$|helm/|k8s/|argo/|\.ethos)' \
  "$OUT/files.txt" > "$OUT/supply-chain-files.txt" 2>/dev/null || true

# Project rules read at the base commit, so rule edits inside the change cannot steer the review.
RULE_TOTAL=0
RULE_CAP_FILE=204800
RULE_CAP_TOTAL=2097152
: > "$OUT/rules/INDEX.txt"
if git cat-file -e "$BASE_SHA^{commit}" 2>/dev/null; then
  git ls-tree -r --name-only "$BASE_SHA" | grep -E \
    '(^|/)(AGENTS\.md|CLAUDE\.md|CONTRIBUTING\.md|SECURITY\.md|REVIEWING\.md)$|^\.github/copilot-instructions\.md$|^\.github/instructions/.*\.instructions\.md$|^\.(claude|cursor|augment)/rules/.*\.mdc?$|^\.scout/review-policy\.md$|^docs/(adr|decisions)/.*\.md$' \
    | grep -v -E '(^|/)(node_modules|vendor|dist)/' > "$OUT/rule-candidates.txt" || true
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    size=$(git cat-file -s "$BASE_SHA:$f" 2>/dev/null || echo 0)
    if [ "$size" -gt "$RULE_CAP_FILE" ] || [ $((RULE_TOTAL + size)) -gt "$RULE_CAP_TOTAL" ]; then
      echo "skipped (size cap): $f" >> "$OUT/rules/INDEX.txt"; continue
    fi
    dest="$OUT/rules/$(printf '%s' "$f" | tr '/' '_')"
    if git show "$BASE_SHA:$f" > "$dest" 2>/dev/null; then
      RULE_TOTAL=$((RULE_TOTAL + size))
      echo "loaded: $f -> rules/$(basename "$dest")" >> "$OUT/rules/INDEX.txt"
    fi
  done < "$OUT/rule-candidates.txt"
  rm -f "$OUT/rule-candidates.txt"
fi

# OpenSpec / design docs touched by or relevant to the change (best effort).
ls openspec/changes/*/proposal.md > "$OUT/specs.txt" 2>/dev/null || : > "$OUT/specs.txt"

ADDED=$(grep -c '^+[^+]' "$OUT/review.diff" 2>/dev/null); ADDED=${ADDED:-0}
REMOVED=$(grep -c '^-[^-]' "$OUT/review.diff" 2>/dev/null); REMOVED=${REMOVED:-0}
NFILES=$(grep -c . "$OUT/files.txt" 2>/dev/null); NFILES=${NFILES:-0}

jq -n \
  --arg root "$ROOT" --arg scope "$SCOPE" --arg base_ref "$BASE_REF" --arg base_sha "$BASE_SHA" \
  --arg head_sha "$HEAD_SHA" --arg review_sha "$REVIEW_SHA" --arg branch "$BRANCH" --arg pr "$PR" \
  --arg since "$SINCE" --argjson added "$ADDED" --argjson removed "$REMOVED" --argjson files "$NFILES" \
  '{root:$root, scope:$scope, base_ref:$base_ref, base_sha:$base_sha, head_sha:$head_sha,
    review_sha:$review_sha, branch:$branch, pr:$pr, since:$since,
    lines_added:$added, lines_removed:$removed, files_changed:$files,
    size_class:(if ($added+$removed) > 1000 then "very-large" elif ($added+$removed) > 400 then "large" else "normal" end)}' \
  > "$OUT/meta.json"

echo "$OUT"
