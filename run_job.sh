#!/usr/bin/env bash
# The CASCADIA-WX batch job: fetch, compile, run. Writes job-log.txt.
# Every step's output and return code goes in the log. The job carries on
# through warnings (RC 4) and stops on RC >= 8, like a mainframe job step
# with COND=(8,LE).
set -u
export TZ=UTC
LOG=job-log.txt
START=$(date +%s.%N)
MAXRC=0
fcv=$(gfortran --version 2>/dev/null | head -1)
{
  echo "JOB CASCADWX   $(date '+%Y-%m-%d %H:%M:%S') UTC"
  echo "HOST           ${RUNNER_OS:-$(uname -s)} $(uname -m) · ${fcv:-gfortran not found} · $(python3 --version 2>&1)"
  [ -n "${GITHUB_RUN_NUMBER:-}" ] && echo "RUN            GitHub Actions run ${GITHUB_RUN_NUMBER} (${GITHUB_EVENT_NAME:-})"
  echo
} > "$LOG"

step () {   # step NAME command...
  local name=$1; shift
  local t0=$(date +%s.%N)
  local out; out=$("$@" 2>&1); local rc=$?
  local t=$(echo "$(date +%s.%N) - $t0" | bc)
  printf "STEP %-10s RC=%04d  %6.2fs  %s\n" "$name" "$rc" "$t" "$*" >> "$LOG"
  echo "$out" | grep -v -e '^$' | sed 's/^/    /' >> "$LOG"
  echo >> "$LOG"
  echo "$out"
  [ $rc -gt $MAXRC ] && MAXRC=$rc
  return $rc
}

step FETCH python3 fetch_wx.py; rc=$?; [ $rc -ge 8 ] && exit 1
step COMPILE gfortran -O2 -o cascadia-wx CASCADIA-WX.f90 || exit 1
step CASCADWX ./cascadia-wx; rc=$?; [ $rc -ge 8 ] && exit 1
T=$(echo "$(date +%s.%N) - $START" | bc)
printf "JOB CASCADWX   ENDED  MAXCC=%04d  %.1fs\n" "$MAXRC" "$T" >> "$LOG"
exit 0
