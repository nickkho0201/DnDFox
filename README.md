# DnDFox

[Русская версия](README.ru.md)

DnDFox adds direct drag-and-drop replacement to Firefox's native Split View.
Drag a regular tab from the tab strip onto the left or right Split View pane:

```text
[ A | B ]  C  D    -- drag C onto B -->    [ A | C ]  B  D
```

The existing Split View remains active, the displaced page is kept as a normal
tab, and the divider ratio is restored after the replacement.

## Requirements

- Windows 10 or Windows 11.
- Firefox 156.
- Firefox must have been started at least once so that a profile exists.
- Administrator access is required because Firefox Autoconfig files live next
  to `firefox.exe`.

DnDFox uses private Firefox browser-chrome APIs. Compatibility with later
Firefox versions is not guaranteed until that version has been tested.

## One-click installation

1. Download the repository from **Code → Download ZIP** or download a release.
2. Extract the whole archive. Do not run the installer from inside the ZIP.
3. Close every Firefox window.
4. Double-click `install.cmd` and approve the Windows UAC prompt.
5. Start Firefox.

The installer automatically finds the standard Firefox installation and the
default profile. It installs a pinned copy of `fx-autoconfig`, installs the
DnDFox script, clears the affected startup cache, and saves backups under:

```text
%LOCALAPPDATA%\DnDFox
```

No network connection is needed during installation.

## Uninstall

Close Firefox and double-click `uninstall.cmd`. A standalone copy of the
uninstaller is also saved to `%LOCALAPPDATA%\DnDFox` during installation.

Files that existed before DnDFox was installed are restored from backup.
Unrelated scripts and Firefox profile data are left untouched.

## Non-standard installations and profiles

Advanced installation can be run from PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-DnDFox.ps1 `
  -FirefoxDirectory "D:\Apps\Firefox" `
  -ProfileDirectory "D:\FirefoxProfile"
```

If more than one Firefox profile is used, run the installer with the explicit
profile path. Version 1.0 installs into one profile at a time.

## Existing Autoconfig installations

The installer recognizes an existing `fx-autoconfig` setup and backs up files
before updating it. It refuses to overwrite an unknown Autoconfig or an unknown
userChrome JavaScript loader. This is deliberate: enterprise policies and
other loaders may use the same Firefox entry points.

## Development

The repository is structured as follows:

```text
src/                         DnDFox browser-chrome script
scripts/                     installer and uninstaller
vendor/fx-autoconfig/        pinned third-party loader
.github/workflows/           syntax validation
```

Validate locally:

```powershell
node --check .\src\splitview-drag-replace.uc.js

$errors = @()
[void][System.Management.Automation.Language.Parser]::ParseFile(
  (Resolve-Path .\scripts\Install-DnDFox.ps1),
  [ref]$null,
  [ref]$errors
)
$errors
```

Build a release ZIP:

```powershell
.\scripts\Build-Release.ps1 -Version 1.0.0
```

## Security and licensing

Autoconfig scripts execute with privileged access to Firefox internals. Read
[`SECURITY.md`](SECURITY.md) before installing code from a fork.

DnDFox-specific code is distributed under the MIT License. The vendored
`fx-autoconfig` files retain their Mozilla Public License 2.0; see
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
