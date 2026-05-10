param(
  [switch]$SkipUsbipd
)

$ErrorActionPreference = "Stop"

function Test-Command {
  param([string]$Name)
  $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

Write-Host "secure-acng: preparing Windows operator workstation dependencies"

if (-not $SkipUsbipd) {
  if (Test-Command "usbipd.exe") {
    Write-Host "secure-acng: usbipd-win is already installed"
  } else {
    if (-not (Test-Command "winget.exe")) {
      throw "winget.exe was not found. Install usbipd-win manually from https://github.com/dorssel/usbipd-win/releases or install winget first."
    }

    Write-Host "secure-acng: installing usbipd-win with winget"
    winget.exe install --id dorssel.usbipd-win -e
    if ($LASTEXITCODE -ne 0) {
      throw "winget failed to install usbipd-win with exit code $LASTEXITCODE"
    }
  }

  $service = Get-Service -Name "usbipd" -ErrorAction SilentlyContinue
  if ($null -eq $service) {
    Write-Warning "usbipd service was not found after installation. Reopen the shell or verify the usbipd-win install."
  } elseif ($service.Status -ne "Running") {
    Write-Host "secure-acng: starting usbipd service"
    Start-Service -Name "usbipd"
  }

  Write-Host "secure-acng: USB/IP exporter ready. Use an elevated PowerShell prompt for 'usbipd bind --busid <busid>'."
}

Write-Host "secure-acng: Windows dependency setup complete"
