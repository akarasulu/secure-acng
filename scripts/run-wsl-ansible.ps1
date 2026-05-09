param(
  [string]$RepoPath = (Get-Location).Path,
  [string]$RunValidate = "0"
)

$ErrorActionPreference = "Stop"

Write-Host "secure-acng: running WSL Ansible helper from $RepoPath"
Write-Host "secure-acng: validation enabled: $RunValidate"

$SourceKey = Join-Path $env:USERPROFILE ".vagrant.d\insecure_private_keys\vagrant.key.rsa"
$TempKey = Join-Path $env:TEMP ("secure-acng-vagrant-{0}.key.rsa" -f ([guid]::NewGuid().ToString("N")))

if (Test-Path -LiteralPath $SourceKey) {
  Copy-Item -LiteralPath $SourceKey -Destination $TempKey -Force
  icacls.exe $TempKey /inheritance:r /grant:r "$env:USERNAME`:R" /remove:g Users "Authenticated Users" "Everyone" "CodexSandboxUsers" *> $null
  Write-Host "secure-acng: using restricted temporary SSH key $TempKey"
  $TempKeyForWsl = $TempKey -replace '\\', '/'
} else {
  Write-Host "secure-acng: Vagrant RSA key was not found at $SourceKey; using keys from vagrant ssh-config"
  $TempKeyForWsl = ""
}

& wsl.exe --cd $RepoPath env "SECURE_ACNG_RUN_VALIDATE=$RunValidate" "SECURE_ACNG_WINDOWS_SSH_KEY=$TempKeyForWsl" bash -c "tr -d '\r' < scripts/ansible-site-from-wsl.sh > /tmp/secure-acng-ansible-site-from-wsl.sh && bash /tmp/secure-acng-ansible-site-from-wsl.sh"
$exitCode = $LASTEXITCODE
Write-Host "secure-acng: WSL Ansible helper exited with code $exitCode"
exit $exitCode
