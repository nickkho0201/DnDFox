[CmdletBinding()]
param(
  [string]$Version = "1.0.0",
  [string]$OutputDirectory
)

$ErrorActionPreference = "Stop"
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$outputRoot = if ($OutputDirectory) {
  [IO.Path]::GetFullPath($OutputDirectory)
} else {
  Join-Path $projectRoot "dist"
}
$stagingRoot = Join-Path $env:TEMP ("DnDFox-release-" + [guid]::NewGuid().ToString("N"))
$packageRoot = Join-Path $stagingRoot ("DnDFox-" + $Version)
$archivePath = Join-Path $outputRoot ("DnDFox-" + $Version + ".zip")

try {
  New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
  New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null

  $rootFiles = @(
    "install.cmd",
    "uninstall.cmd",
    "README.md",
    "README.ru.md",
    "CHANGELOG.md",
    "SECURITY.md",
    "THIRD_PARTY_NOTICES.md",
    "LICENSE"
  )
  foreach ($file in $rootFiles) {
    Copy-Item -LiteralPath (Join-Path $projectRoot $file) -Destination $packageRoot -Force
  }

  foreach ($directory in @("scripts", "src", "vendor")) {
    Copy-Item -LiteralPath (Join-Path $projectRoot $directory) -Destination $packageRoot -Recurse -Force
  }

  if (Test-Path -LiteralPath $archivePath -PathType Leaf) {
    Remove-Item -LiteralPath $archivePath -Force
  }
  Compress-Archive -LiteralPath $packageRoot -DestinationPath $archivePath -CompressionLevel Optimal
  Write-Host "[DnDFox] Release archive created: $archivePath"
} finally {
  $normalizedStaging = [IO.Path]::GetFullPath($stagingRoot)
  $normalizedTemp = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')
  if (
    $normalizedStaging.StartsWith($normalizedTemp + '\', [StringComparison]::OrdinalIgnoreCase) -and
    (Test-Path -LiteralPath $normalizedStaging)
  ) {
    Remove-Item -LiteralPath $normalizedStaging -Recurse -Force
  }
}
