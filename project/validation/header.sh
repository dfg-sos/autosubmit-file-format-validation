#!/bin/bash
#############################################
# Format validation: check the job inputs
#############################################
# Appended by Autosubmit after its header (job key EXTENDED_HEADER_PATH).
# The inputs are declared per job section in VALIDATE_INPUTS; Autosubmit writes that mapping into
# the heredoc below as a Python literal, which validate_files.py reads from stdin and hands to
# the format-validator command line tool. The quoted heredoc keeps bash from interpreting its
# quotes and braces.
# No backslashes in this file: Autosubmit would re.escape the whole script.
%VALIDATION.PYTHON% %PROJDIR%/validation/validate_files.py --phase pre --job %JOBNAME% --validator %VALIDATION.VALIDATOR% --mappings %VALIDATION.MAPPINGS% --mode %VALIDATION.MODE% --on-failure %VALIDATION.ON_FAILURE% --log %VALIDATION.LOG% <<'VALIDATE_DECLARATIONS' || exit 1
%CURRENT_VALIDATE_INPUTS%
VALIDATE_DECLARATIONS
