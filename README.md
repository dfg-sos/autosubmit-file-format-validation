# Autosubmit × SOS File Format Validator

This repository shows that the [SOS File Format Validator](https://github.com/dfg-sos/file-format-validator) can validate the files of an [Autosubmit](https://autosubmit.readthedocs.io/) workflow at run time, through its command line tool `format-validator` (v0.6.0). It needs no changes to Autosubmit, and none to the validator. It is the Autosubmit counterpart of the [format-aware CWL runner](https://github.com/dfg-sos/file-format-aware-cwl-runner). It is a proof of concept, not a finished extension.

## How the integration works

```yaml
# experiment/conf/jobs.yml
  POST:
    EXTENDED_HEADER_PATH: validation/header.sh   # check VALIDATE_INPUTS before the job's script
    EXTENDED_TAILER_PATH: validation/tailer.sh   # check VALIDATE_OUTPUTS after it
    VALIDATE_INPUTS:
      SIM_OUT:                            # a name for the file, used in logs
        FORMAT: "https://dfg-sos.github.io/ontologies/eo-formats#NetCDF_CF"   # the format it must have
        PATH: "%TOY.DATA_DIR%/%SDATE%/%MEMBER%/sim_%CHUNK%.nc"
    VALIDATE_OUTPUTS:
      TIME_MEAN:
        FORMAT: "https://dfg-sos.github.io/ontologies/eo-formats#NetCDF_CF"
        PATH: "%TOY.DATA_DIR%/%SDATE%/%MEMBER%/post_%CHUNK%.nc"
```

- **Hook points:** Autosubmit 4 appends a per-job script to its job header (`EXTENDED_HEADER_PATH`) and its tailer (`EXTENDED_TAILER_PATH`). The header checks a job's inputs before its body runs. The tailer checks its outputs after a successful body. A failed check exits non-zero, so Autosubmit marks the job `FAILED` and does not start its dependants, exactly like any other job failure.
- **Declarations:** the files to check come from custom job keys, `VALIDATE_INPUTS` and `VALIDATE_OUTPUTS`, because Autosubmit has no notion of job files. Each names a file and gives its `PATH` and its `FORMAT`, the full IRI of a format class in any ontology that [`mappings/`](mappings/) maps to the validator's format identifiers. Autosubmit fills in the `%SDATE%`, `%MEMBER%` and `%CHUNK%` placeholders per job.
- **Settings:** [`experiment/conf/validation.yml`](experiment/conf/validation.yml) holds the path of the `format-validator` executable and of the mappings, the mode (`basic`/`metadata`/`content`) and `ON_FAILURE` (`fail`/`warn`).
- **Adapter:** [`project/validation/validate_files.py`](project/validation/validate_files.py) turns the declarations into a manifest for `format-validator validate --manifest - --json`, prints and logs the result of each file, and exits non-zero if a check fails (`FAILURE`, or `ERROR`: the file could not be validated, e.g. its format has no mapping). The validator runs in its own environment (Python 3.13), so the adapter needs only a `python3` with the standard library.

The toy workflow in [`experiment/conf/jobs.yml`](experiment/conf/jobs.yml) runs over three chunks. `SIM` writes one CF NetCDF file per chunk, and `POST` computes its time mean. [`project/templates/sim.sh`](project/templates/sim.sh) can inject a fault into chunk 2:

- `empty`: the data variable is missing, as when a model writes only coordinates.
- `truncate`: the file is cut to 200 bytes, as on a wallclock kill or a full quota.

## Results

Autosubmit 4.1.17.2 on the `LOCAL` platform, format-validator 0.6.0 in `metadata` mode:

| Fault in SIM chunk 2 | Autosubmit | Autosubmit + format-validator | Autosubmit + format-validator, `ON_FAILURE: warn` |
|---|---|---|---|
| none | all jobs complete | all jobs complete | all jobs complete |
| `empty` | all jobs complete, `post_2.nc` has no data | SIM.2 fails, nothing downstream runs | as Autosubmit, the failed checks are logged |
| `truncate` | POST.2 fails with an HDF error | SIM.2 fails, nothing downstream runs | as Autosubmit, the failed checks are logged |

## Run it

Requires [uv](https://docs.astral.sh/uv/) and `python3`. [`scripts/setup.sh`](scripts/setup.sh) installs `format-validator` with its EO plugin from tag `v0.6.0` of the repository into `envs/validator` (set `VALIDATOR_REF` for another tag or branch). Everything the scripts create goes to gitignored directories in this repository (`envs/`, `autosubmit/`, `data/`). Autosubmit normally keeps its configuration in `~/.autosubmitrc` and its experiments in `~/autosubmit`; [`scripts/as.sh`](scripts/as.sh) points it to `autosubmit/.autosubmitrc` instead, so an existing Autosubmit setup on the machine is left alone.

```sh
scripts/setup.sh                       # venvs (Autosubmit, toy workflow, validator), Autosubmit configuration and database
scripts/run-scenario.sh empty off      # new experiment, run, summary; FAULT_KIND none|empty|truncate,
scripts/run-scenario.sh empty fail     #   VALIDATION off (plain Autosubmit) | fail | warn (ON_FAILURE)
scripts/run-scenario.sh empty warn
scripts/as.sh <autosubmit command>     # Autosubmit with this repository's configuration, e.g. `scripts/as.sh monitor a001`
```

## Layout

```
experiment/conf/   experiment configuration templates (@EXPID@, @REPO@ are filled in by run-scenario.sh)
experiment/scenarios/  overrides of that configuration per scenario (fault kind, validation warn or off)
project/           Autosubmit project (PROJECT_TYPE: local), copied into each experiment
  validation/      header.sh, tailer.sh and the adapter validate_files.py: the integration
  templates/       sim.sh, post.sh: the toy climate jobs with fault injection
mappings/          EO ontology → validator format identifier mapping (format-validator --mappings)
scripts/           setup, scenario runner, autosubmit wrapper
```
