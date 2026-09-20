[CmdletBinding()]
param(
  [string]$FirefoxDirectory,
  [string]$ProfileDirectory,
  [switch]$Force,
  [switch]$NoElevation,
  [switch]$AllowFirefoxRunning
)

$ErrorActionPreference = "Stop"
$PackageVersion = "1.0.0"
$StateVersion = 1

function Write-Status {
  param([string]$Message)
  Write-Host "[DnDFox] $Message"
}

function Test-IsAdministrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Quote-ProcessArgument {
  param([string]$Value)
  return '"' + $Value.Replace('"', '\"') + '"'
}

function Restart-Elevated {
  $arguments = @(
    "-NoLogo",
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", (Quote-ProcessArgument $PSCommandPath)
  )

  if ($FirefoxDirectory) {
    $arguments += @("-FirefoxDirectory", (Quote-ProcessArgument $FirefoxDirectory))
  }
  if ($ProfileDirectory) {
    $arguments += @("-ProfileDirectory", (Quote-ProcessArgument $ProfileDirectory))
  }
  if ($Force) {
    $arguments += "-Force"
  }
  if ($AllowFirefoxRunning) {
    $arguments += "-AllowFirefoxRunning"
  }

  Write-Status "Administrator access is required to configure Firefox."
  $process = Start-Process -FilePath "powershell.exe" -Verb RunAs -Wait -PassThru -ArgumentList ($arguments -join " ")
  exit $process.ExitCode
}

function Resolve-FirefoxDirectory {
  param([string]$RequestedDirectory)

  if ($RequestedDirectory) {
    $resolved = [IO.Path]::GetFullPath($RequestedDirectory)
    if (-not (Test-Path -LiteralPath (Join-Path $resolved "firefox.exe") -PathType Leaf)) {
      throw "firefox.exe was not found in '$resolved'."
    }
    return $resolved.TrimEnd('\')
  }

  $candidates = New-Object System.Collections.Generic.List[string]
  $registryPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\firefox.exe",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\firefox.exe",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\firefox.exe"
  )

  foreach ($registryPath in $registryPaths) {
    if (Test-Path -LiteralPath $registryPath) {
      $executable = (Get-Item -LiteralPath $registryPath).GetValue("")
      if ($executable) {
        $candidates.Add((Split-Path -Parent $executable))
      }
    }
  }

  $candidates.Add((Join-Path $env:ProgramFiles "Mozilla Firefox"))
  if (${env:ProgramFiles(x86)}) {
    $candidates.Add((Join-Path ${env:ProgramFiles(x86)} "Mozilla Firefox"))
  }

  $valid = @(
    $candidates |
      ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') } |
      Select-Object -Unique |
      Where-Object { Test-Path -LiteralPath (Join-Path $_ "firefox.exe") -PathType Leaf }
  )

  if ($valid.Count -eq 0) {
    throw "Firefox was not found. Install Firefox first or pass -FirefoxDirectory."
  }

  if ($valid.Count -gt 1) {
    Write-Status "Multiple Firefox installations found; using '$($valid[0])'."
  }

  return $valid[0]
}

function Read-IniSections {
  param([string]$Path)

  $sections = [ordered]@{}
  $currentSection = $null

  foreach ($line in Get-Content -LiteralPath $Path) {
    $trimmed = $line.Trim()
    if (-not $trimmed -or $trimmed.StartsWith(";") -or $trimmed.StartsWith("#")) {
      continue
    }
    if ($trimmed -match '^\[(.+)\]$') {
      $currentSection = $Matches[1]
      $sections[$currentSection] = [ordered]@{}
      continue
    }
    if ($currentSection -and $trimmed -match '^([^=]+)=(.*)$') {
      $sections[$currentSection][$Matches[1].Trim()] = $Matches[2].Trim()
    }
  }

  return $sections
}

function Resolve-ProfileDirectory {
  param([string]$RequestedDirectory)

  if ($RequestedDirectory) {
    $resolved = [IO.Path]::GetFullPath($RequestedDirectory)
    if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
      throw "Firefox profile '$resolved' does not exist."
    }
    return $resolved.TrimEnd('\')
  }

  $firefoxDataRoot = Join-Path $env:APPDATA "Mozilla\Firefox"
  $profilesIni = Join-Path $firefoxDataRoot "profiles.ini"
  if (-not (Test-Path -LiteralPath $profilesIni -PathType Leaf)) {
    throw "profiles.ini was not found. Start Firefox once, close it, and run the installer again."
  }

  $sections = Read-IniSections $profilesIni
  $candidatePaths = New-Object System.Collections.Generic.List[string]

  foreach ($sectionName in $sections.Keys) {
    if ($sectionName -like "Install*" -and $sections[$sectionName].Contains("Default")) {
      $candidatePaths.Add($sections[$sectionName]["Default"])
    }
  }
  foreach ($sectionName in $sections.Keys) {
    $section = $sections[$sectionName]
    if ($sectionName -like "Profile*" -and $section["Default"] -eq "1" -and $section.Contains("Path")) {
      $candidatePaths.Add($section["Path"])
    }
  }
  foreach ($sectionName in $sections.Keys) {
    $section = $sections[$sectionName]
    if ($sectionName -like "Profile*" -and $section["Name"] -like "*default-release*" -and $section.Contains("Path")) {
      $candidatePaths.Add($section["Path"])
    }
  }
  foreach ($sectionName in $sections.Keys) {
    $section = $sections[$sectionName]
    if ($sectionName -like "Profile*" -and $section.Contains("Path")) {
      $candidatePaths.Add($section["Path"])
    }
  }

  foreach ($candidatePath in ($candidatePaths | Select-Object -Unique)) {
    $candidate = if ([IO.Path]::IsPathRooted($candidatePath)) {
      $candidatePath
    } else {
      Join-Path $firefoxDataRoot $candidatePath
    }
    $candidate = [IO.Path]::GetFullPath($candidate).TrimEnd('\')
    if (Test-Path -LiteralPath $candidate -PathType Container) {
      return $candidate
    }
  }

  throw "No usable Firefox profile was found. Start Firefox once, close it, and run the installer again."
}

function Get-FileHashValue {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return $null
  }
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Assert-CompatibleExistingConfiguration {
  param(
    [string]$ConfigPath,
    [string]$PrefsPath,
    [string]$BootPath,
    [string]$ManifestPath
  )

  if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) {
    $content = Get-Content -LiteralPath $ConfigPath -Raw
    if ($content -notmatch 'chrome://userchromejs/content/boot\.sys\.mjs') {
      throw "An unknown Firefox Autoconfig already exists at '$ConfigPath'. It was not overwritten."
    }
  }

  if (Test-Path -LiteralPath $PrefsPath -PathType Leaf) {
    $content = Get-Content -LiteralPath $PrefsPath -Raw
    if ($content -notmatch 'general\.config\.filename.+config\.js') {
      throw "An unknown Firefox Autoconfig preference file exists at '$PrefsPath'. It was not overwritten."
    }
  }

  if (Test-Path -LiteralPath $BootPath -PathType Leaf) {
    $content = Get-Content -LiteralPath $BootPath -Raw
    if ($content -notmatch 'Browser is executing custom scripts via autoconfig|fx-autoconfig') {
      throw "An unknown userChrome JavaScript loader exists at '$BootPath'. It was not overwritten."
    }
  }

  if (Test-Path -LiteralPath $ManifestPath -PathType Leaf) {
    $content = Get-Content -LiteralPath $ManifestPath -Raw
    if ($content -notmatch 'content\s+userchromejs') {
      throw "An unknown chrome manifest exists at '$ManifestPath'. It was not overwritten."
    }
  }
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
    Restart-Elevated
  }

  if (-not $AllowFirefoxRunning -and (Get-Process -Name "firefox" -ErrorAction SilentlyContinue)) {
    throw "Firefox is running. Close every Firefox window and run the installer again."
  }

  $projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
  $firefoxRoot = Resolve-FirefoxDirectory $FirefoxDirectory
  $profileRoot = Resolve-ProfileDirectory $ProfileDirectory

  Write-Status "Firefox: $firefoxRoot"
  Write-Status "Profile: $profileRoot"

  $vendorRoot = Join-Path $projectRoot "vendor\fx-autoconfig"
  $scriptSource = Join-Path $projectRoot "src\splitview-drag-replace.uc.js"
  $utilsSource = Join-Path $vendorRoot "profile\chrome\utils"

  $programConfigTarget = Join-Path $firefoxRoot "config.js"
  $programPrefsTarget = Join-Path $firefoxRoot "defaults\pref\config-prefs.js"
  $profileUtilsTarget = Join-Path $profileRoot "chrome\utils"
  $profileScriptTarget = Join-Path $profileRoot "chrome\JS\splitview-drag-replace.uc.js"

  Assert-CompatibleExistingConfiguration `
    -ConfigPath $programConfigTarget `
    -PrefsPath $programPrefsTarget `
    -BootPath (Join-Path $profileUtilsTarget "boot.sys.mjs") `
    -ManifestPath (Join-Path $profileUtilsTarget "chrome.manifest")

  $fileSpecs = New-Object System.Collections.Generic.List[object]
  $fileSpecs.Add([pscustomobject]@{
    Key = "program/config.js"
    Source = (Join-Path $vendorRoot "program\config.js")
    Target = $programConfigTarget
  })
  $fileSpecs.Add([pscustomobject]@{
    Key = "program/defaults/pref/config-prefs.js"
    Source = (Join-Path $vendorRoot "program\defaults\pref\config-prefs.js")
    Target = $programPrefsTarget
  })

  foreach ($utilsFile in Get-ChildItem -LiteralPath $utilsSource -File) {
    $fileSpecs.Add([pscustomobject]@{
      Key = "profile/chrome/utils/$($utilsFile.Name)"
      Source = $utilsFile.FullName
      Target = (Join-Path $profileUtilsTarget $utilsFile.Name)
    })
  }

  $fileSpecs.Add([pscustomobject]@{
    Key = "profile/chrome/JS/splitview-drag-replace.uc.js"
    Source = $scriptSource
    Target = $profileScriptTarget
  })

  foreach ($fileSpec in $fileSpecs) {
    if (-not (Test-Path -LiteralPath $fileSpec.Source -PathType Leaf)) {
      throw "Package file is missing: '$($fileSpec.Source)'. Download or extract the complete DnDFox release."
    }
  }

  $stateRoot = Join-Path $env:LOCALAPPDATA "DnDFox"
  $statePath = Join-Path $stateRoot "install-state.json"
  $previousState = $null
  if (Test-Path -LiteralPath $statePath -PathType Leaf) {
    $previousState = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    if (
      $previousState.FirefoxDirectory -ne $firefoxRoot -or
      $previousState.ProfileDirectory -ne $profileRoot
    ) {
      throw "DnDFox is already registered for another Firefox installation/profile. Uninstall it first or pass the original paths explicitly."
    }
  }

  if ($previousState) {
    foreach ($previousFile in $previousState.Files) {
      if (Test-Path -LiteralPath $previousFile.Target -PathType Leaf) {
        $currentHash = Get-FileHashValue $previousFile.Target
        $newSpec = $fileSpecs | Where-Object { $_.Target -eq $previousFile.Target } | Select-Object -First 1
        $newHash = if ($newSpec) { Get-FileHashValue $newSpec.Source } else { $null }
        if (
          $previousFile.InstalledHash -and
          $currentHash -ne $previousFile.InstalledHash -and
          $currentHash -ne $newHash -and
          -not $Force
        ) {
          throw "Installed file '$($previousFile.Target)' was modified after installation. Re-run with -Force only if overwriting it is intended."
        }
      }
    }
  }

  New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
  $backupRoot = if ($previousState) {
    $previousState.BackupDirectory
  } else {
    Join-Path $stateRoot ("backups\" + [DateTime]::UtcNow.ToString("yyyyMMdd-HHmmss"))
  }

  $stateFiles = New-Object System.Collections.Generic.List[object]
  foreach ($fileSpec in $fileSpecs) {
    $previousFile = if ($previousState) {
      $previousState.Files | Where-Object { $_.Target -eq $fileSpec.Target } | Select-Object -First 1
    } else {
      $null
    }

    if ($previousFile) {
      $hadOriginal = [bool]$previousFile.HadOriginal
      $backupPath = $previousFile.Backup
    } else {
      $hadOriginal = Test-Path -LiteralPath $fileSpec.Target -PathType Leaf
      $backupPath = if ($hadOriginal) {
        Join-Path $backupRoot ($fileSpec.Key -replace '/', '\')
      } else {
        $null
      }
      if ($hadOriginal) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $backupPath) -Force | Out-Null
        Copy-Item -LiteralPath $fileSpec.Target -Destination $backupPath -Force
      }
    }

    $stateFiles.Add([pscustomobject]@{
      Key = $fileSpec.Key
      Target = $fileSpec.Target
      Backup = $backupPath
      HadOriginal = $hadOriginal
      InstalledHash = (Get-FileHashValue $fileSpec.Source)
    })
  }

  $copiedTargets = New-Object System.Collections.Generic.List[string]
  try {
    foreach ($fileSpec in $fileSpecs) {
      New-Item -ItemType Directory -Path (Split-Path -Parent $fileSpec.Target) -Force | Out-Null
      Copy-Item -LiteralPath $fileSpec.Source -Destination $fileSpec.Target -Force
      $copiedTargets.Add($fileSpec.Target)
      Write-Status "Installed $($fileSpec.Key)"
    }
  } catch {
    Write-Status "Installation failed; restoring files already changed."
    foreach ($target in $copiedTargets) {
      $stateFile = $stateFiles | Where-Object { $_.Target -eq $target } | Select-Object -First 1
      if ($stateFile.HadOriginal -and $stateFile.Backup -and (Test-Path -LiteralPath $stateFile.Backup -PathType Leaf)) {
        Copy-Item -LiteralPath $stateFile.Backup -Destination $target -Force
      } elseif (Test-Path -LiteralPath $target -PathType Leaf) {
        Remove-Item -LiteralPath $target -Force
      }
    }
    throw
  }

  $state = [ordered]@{
    StateVersion = $StateVersion
    PackageVersion = $PackageVersion
    InstalledAtUtc = [DateTime]::UtcNow.ToString("o")
    FirefoxDirectory = $firefoxRoot
    ProfileDirectory = $profileRoot
    BackupDirectory = $backupRoot
    Files = $stateFiles.ToArray()
  }
  $state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statePath -Encoding UTF8

  Copy-Item -LiteralPath (Join-Path $projectRoot "scripts\Uninstall-DnDFox.ps1") -Destination (Join-Path $stateRoot "Uninstall-DnDFox.ps1") -Force
  Copy-Item -LiteralPath (Join-Path $projectRoot "uninstall.cmd") -Destination (Join-Path $stateRoot "uninstall.cmd") -Force

  Remove-ProfileStartupCache $profileRoot

  Write-Status "DnDFox $PackageVersion installed successfully."
  Write-Status "Start Firefox and test dragging a normal tab onto either Split View pane."
  Write-Status "A standalone uninstaller was saved to '$stateRoot'."
  exit 0
} catch {
  Write-Host "[DnDFox] ERROR: $($_.Exception.Message)" -ForegroundColor Red
  exit 1
}
