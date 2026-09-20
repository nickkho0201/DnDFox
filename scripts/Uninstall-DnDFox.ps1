[CmdletBinding()]
param(
  [switch]$Force,
  [switch]$NoElevation,
  [switch]$AllowFirefoxRunning
)

$ErrorActionPreference = "Stop"

function Write-Status {
  param([string]$Message)
  Write-Host "[DnDFox] $Message"
}

function Test-IsAdministrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-FileHashValue {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return $null
  }
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Remove-ProfileStartupCache {
  param([string]$ProfilePath)

  $cacheCandidates = New-Object System.Collections.Generic.List[string]
  $cacheCandidates.Add((Join-Path $ProfilePath "startupCache"))

  $roamingFirefoxRoot = [IO.Path]::GetFullPath((Join-Path $env:APPDATA "Mozilla\Firefox")).TrimEnd('\')
  $normalizedProfile = [IO.Path]::GetFullPath($ProfilePath).TrimEnd('\')
  if ($normalizedProfile.StartsWith($roamingFirefoxRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    $relative = $normalizedProfile.Substring($roamingFirefoxRoot.Length + 1)
    $localProfile = Join-Path (Join-Path $env:LOCALAPPDATA "Mozilla\Firefox") $relative
    $cacheCandidates.Add((Join-Path $localProfile "startupCache"))
  }

  foreach ($cacheCandidate in ($cacheCandidates | Select-Object -Unique)) {
    $normalizedCache = [IO.Path]::GetFullPath($cacheCandidate)
    $normalizedParent = [IO.Path]::GetFullPath((Split-Path -Parent $cacheCandidate)).TrimEnd('\')
    if (-not $normalizedCache.StartsWith($normalizedParent + '\', [StringComparison]::OrdinalIgnoreCase)) {
      throw "Refusing to remove unexpected cache path '$normalizedCache'."
    }
    if (Test-Path -LiteralPath $normalizedCache -PathType Container) {
      Remove-Item -LiteralPath $normalizedCache -Recurse -Force
      Write-Status "Cleared startup cache: $normalizedCache"
    }
  }
}

try {
  if (-not $NoElevation -and -not (Test-IsAdministrator)) {
    $arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($Force) { $arguments += " -Force" }
    if ($AllowFirefoxRunning) { $arguments += " -AllowFirefoxRunning" }
    Write-Status "Administrator access is required to restore Firefox files."
    $process = Start-Process -FilePath "powershell.exe" -Verb RunAs -Wait -PassThru -ArgumentList $arguments
    exit $process.ExitCode
  }

  if (-not $AllowFirefoxRunning -and (Get-Process -Name "firefox" -ErrorAction SilentlyContinue)) {
    throw "Firefox is running. Close every Firefox window and run the uninstaller again."
  }

  $stateRoot = Join-Path $env:LOCALAPPDATA "DnDFox"
  $statePath = Join-Path $stateRoot "install-state.json"
  if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
    throw "No DnDFox installation state was found at '$statePath'."
  }

  $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json

  if (-not $Force) {
    foreach ($file in $state.Files) {
      if (Test-Path -LiteralPath $file.Target -PathType Leaf) {
        $currentHash = Get-FileHashValue $file.Target
        if ($file.InstalledHash -and $currentHash -ne $file.InstalledHash) {
          throw "Installed file '$($file.Target)' was modified after installation. It was not overwritten. Re-run with -Force only if discarding those changes is intended."
        }
      }
    }
  }

  foreach ($file in @($state.Files)[-1..-($state.Files.Count)]) {
    if ($file.HadOriginal) {
      if (-not $file.Backup -or -not (Test-Path -LiteralPath $file.Backup -PathType Leaf)) {
        throw "Backup required to restore '$($file.Target)' is missing."
      }
      New-Item -ItemType Directory -Path (Split-Path -Parent $file.Target) -Force | Out-Null
      Copy-Item -LiteralPath $file.Backup -Destination $file.Target -Force
      Write-Status "Restored $($file.Target)"
    } elseif (Test-Path -LiteralPath $file.Target -PathType Leaf) {
      Remove-Item -LiteralPath $file.Target -Force
      Write-Status "Removed $($file.Target)"
    }
  }

  Remove-ProfileStartupCache $state.ProfileDirectory

  $backupRoot = [IO.Path]::GetFullPath($state.BackupDirectory)
  $expectedStateRoot = [IO.Path]::GetFullPath($stateRoot).TrimEnd('\')
  if ($backupRoot.StartsWith($expectedStateRoot + '\', [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $backupRoot)) {
    Remove-Item -LiteralPath $backupRoot -Recurse -Force
  }

  Remove-Item -LiteralPath $statePath -Force
  Write-Status "DnDFox was removed and the previous Firefox files were restored."
  exit 0
} catch {
  Write-Host "[DnDFox] ERROR: $($_.Exception.Message)" -ForegroundColor Red
  exit 1
}
