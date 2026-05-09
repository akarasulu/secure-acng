param(
  [string]$RepoPath = (Get-Location).Path,
  [string]$RunValidate = "0"
)

$ErrorActionPreference = "Stop"

$wslCommand = @"
set -euo pipefail
tmp=`$(mktemp)
trap 'rm -f "`$tmp"' EXIT
tr -d '\r' < scripts/ansible-site-from-wsl.sh > "`$tmp"
SECURE_ACNG_RUN_VALIDATE=$RunValidate bash "`$tmp"
"@

& wsl.exe --cd $RepoPath bash -lc $wslCommand
exit $LASTEXITCODE
