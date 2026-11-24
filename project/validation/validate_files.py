#!/usr/bin/env python3
"""Validate the files of an Autosubmit job with the format-validator command line tool.

Reads the job's VALIDATE_INPUTS or VALIDATE_OUTPUTS from stdin, as Autosubmit writes them
into the job script (a Python literal), e.g.

    {'SIM_OUT': {'FORMAT': 'https://dfg-sos.github.io/ontologies/eo-formats#NetCDF_CF',
                 'PATH': '/data/a000/20000101/fc0/sim_1.nc'}}

turns them into a manifest for `format-validator validate --manifest - --json`, prints and
logs the result of each file, and exits 1 if a check failed: FAILURE, or ERROR (the file could
not be validated, e.g. its format has no mapping, or the validator could not run at all).
UNCERTAIN only warns. Standard library only, so it runs with any python3 on the node.
"""

import argparse
import ast
import json
import subprocess
import sys


def validate(args, manifest):
    """The validator's report of each file in the manifest: name, path, format, status, errors.
    Its diagnostics (UNCERTAIN warnings, configuration errors) go straight to stderr."""
    cmd = [args.validator, "validate", "--mappings", args.mappings, "--mode", args.mode,
           "--manifest", "-", "--json", "--color", "never"]
    try:
        proc = subprocess.run(cmd, input=json.dumps(manifest), capture_output=True, text=True)
        sys.stderr.write(proc.stderr)
        return json.loads(proc.stdout)["results"]
    except OSError as e:  # validator not installed
        reason = f"cannot run {args.validator}: {e}"
    except (ValueError, KeyError):  # exit status 2: arguments or mappings wrong, nothing validated
        reason = f"format-validator exited with status {proc.returncode} without results"
    return [{"name": name, "path": entry["path"], "format": entry["format"], "status": "ERROR",
             "errors": [{"message": reason}]} for name, entry in manifest.items()]


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--validator", required=True, help="the format-validator executable")
    p.add_argument("--mappings", required=True, help="directory of the ontology mapping files")
    p.add_argument("--mode", required=True, help="basic, metadata or content")
    p.add_argument("--phase", choices=["pre", "post"], required=True, help="inputs (pre) or outputs (post)")
    p.add_argument("--job", required=True, help="Autosubmit job name")
    p.add_argument("--on-failure", choices=["fail", "warn"], required=True)
    p.add_argument("--log", required=True, help="JSON lines file the results are appended to")
    args = p.parse_args()

    text = sys.stdin.read().strip()
    declarations = ast.literal_eval(text) if text else {}  # empty: the job declares no files
    if not declarations:
        return 0
    manifest = {name: {"format": d["FORMAT"], "path": d["PATH"]} for name, d in declarations.items()}
    failed = False
    with open(args.log, "a") as log:
        for r in validate(args, manifest):
            fails = r["status"] in ("FAILURE", "ERROR") and args.on_failure == "fail"
            failed |= fails
            out = sys.stdout if r["status"] == "SUCCESS" else sys.stderr
            print(f"[validation] {args.job} {args.phase} {r['name']} {r['path']}: {r['status']}", file=out)
            for error in r["errors"]:
                print(f"[validation]   {error['message']}", file=out)
            log.write(json.dumps({"job": args.job, "phase": args.phase, "file": r["name"], "format": r["format"],
                                  "path": r["path"], "status": r["status"], "failed_job": fails}) + "\n")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
