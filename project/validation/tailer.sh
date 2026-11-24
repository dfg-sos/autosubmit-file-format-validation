#!/bin/bash
#############################################
# Format validation: check the job outputs
#############################################
# Appended by Autosubmit to its tailer (job key EXTENDED_TAILER_PATH), so it runs
# only if the job body succeeded. The outputs are declared in VALIDATE_OUTPUTS, passed
# to validate_files.py on stdin as in header.sh.
# No backslashes in this file: Autosubmit would re.escape the whole script.
# Autosubmit's tailer ends with `wait`, so a failed check must exit explicitly.
%VALIDATION.PYTHON% %PROJDIR%/validation/validate_files.py --phase post --job %JOBNAME% --validator %VALIDATION.VALIDATOR% --mappings %VALIDATION.MAPPINGS% --mode %VALIDATION.MODE% --on-failure %VALIDATION.ON_FAILURE% --log %VALIDATION.LOG% <<'VALIDATE_DECLARATIONS' || exit 1
%CURRENT_VALIDATE_OUTPUTS%
VALIDATE_DECLARATIONS
