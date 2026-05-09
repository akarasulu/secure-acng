param(
  [string]$RepoPath = (Get-Location).Path,
  [string]$RunValidate = "0"
)

$ErrorActionPreference = "Stop"

& wsl.exe --cd $RepoPath env "SECURE_ACNG_RUN_VALIDATE=$RunValidate" bash -c "tr -d '\r' < scripts/ansible-site-from-wsl.sh | bash"
exit $LASTEXITCODE
