#!/bin/bash
# Create a new experiment from experiment/conf and experiment/scenarios, run it and summarise.
# Usage: scripts/run-scenario.sh FAULT_KIND VALIDATION
#   FAULT_KIND  none | empty | truncate   (fault in chunk 2 of SIM, see project/templates/sim.sh)
#   VALIDATION  fail | warn | off         (fail: a failed check fails the job; warn: it is only logged;
#                                          off: plain Autosubmit, no checks)
# Requires scripts/setup.sh.
set -uo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd); AS=$HERE/scripts/as.sh
mkdir -p "$HERE/data"
KIND=${1:?FAULT_KIND: none|empty|truncate}; VALIDATION=${2:?VALIDATION: fail|warn|off}

EXPID=$($AS expid -H local -d "Format validation PoC: fault=$KIND validation=$VALIDATION" 2>&1 | grep -ao "Experiment [a-z0-9]\{4\} created" | awk '{print $2}')
[ -n "$EXPID" ] || { echo "autosubmit expid failed" >&2; exit 1; }

# Replace the generated default configuration by ours (one file per template, named <name>_<expid>.yml),
# then add the scenario's overrides from experiment/scenarios (none for the defaults: no fault, ON_FAILURE fail).
# Autosubmit merges conf/*.yml in name order, later files winning, so the overrides sort last (zz_).
CONF=$HERE/autosubmit/experiments/$EXPID/conf
rm -f "$CONF"/*.yml
render() { sed -e "s|@EXPID@|$EXPID|g" -e "s|@REPO@|$HERE|g" "$1" > "$CONF/${2:-}$(basename "$1" .yml)_$EXPID.yml"; }
for f in "$HERE"/experiment/conf/*.yml; do render "$f"; done
[ "$KIND" = none ] || render "$HERE/experiment/scenarios/fault-$KIND.yml" zz_ || exit 1
[ "$VALIDATION" = fail ] || render "$HERE/experiment/scenarios/validation-$VALIDATION.yml" zz_ || exit 1

$AS create "$EXPID" -np > "$HERE/data/create-$EXPID.log" 2>&1 || { echo "autosubmit create failed, see data/create-$EXPID.log" >&2; exit 1; }
$AS run "$EXPID" > "$HERE/data/run-$EXPID.log" 2>&1

echo "== $EXPID  fault=$KIND  validation=$VALIDATION"
echo "-- jobs (never run: not listed)"
grep -aoE "Job ${EXPID}_\S+ changed from RUNNING to (COMPLETED|FAILED)" "$HERE/data/run-$EXPID.log" | sed -e 's/changed from RUNNING to //' -e "s/Job ${EXPID}_20000101_fc0_/  /"
LOG=$HERE/data/$EXPID/validation.jsonl
echo "-- format checks ($LOG)"
[ -f "$LOG" ] && python3 -c '
import json, sys
for r in map(json.loads, open(sys.argv[1])):
    job, file = r["job"].split("_fc0_")[-1], r["path"].rsplit("/", 1)[-1]
    print("  %-7s %-4s %-10s %-8s%s" % (job, r["phase"], file, r["status"], "  -> job fails" * r["failed_job"]))
' "$LOG"
echo "-- post-processed files"
shopt -s nullglob
for f in "$HERE"/data/$EXPID/20000101/fc0/post_*.nc; do
  printf '  %s: ' "$(basename "$f")"
  "$HERE/envs/toy/bin/python" -c "import sys, xarray as xr; print('data variables', list(xr.open_dataset(sys.argv[1]).data_vars))" "$f"
done
echo "Job logs: autosubmit/experiments/$EXPID/tmp/LOG_$EXPID/"
