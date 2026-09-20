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

1. Start Firefox at least once, then close every Firefox window. This creates
   the profile that the installer needs to locate.
2. Download the repository from **Code → Download ZIP** or download a release.
3. Extract the whole archive to a normal folder. Do not run the installer from
   inside the ZIP.
4. Double-click `install.cmd` and approve the Windows UAC prompt.
5. Wait for the installer to report `Installation completed successfully`.
6. Start Firefox and follow the quick test in [How to use](#how-to-use).

The installer automatically finds the standard Firefox installation and the
default profile. It installs a pinned copy of `fx-autoconfig`, installs the
DnDFox script, clears the affected startup cache, and saves backups under:

```text
%LOCALAPPDATA%\DnDFox
```

No network connection is needed during installation.

### Verify the installation

1. Create a Split View using Firefox's built-in Split View controls.
2. Keep at least one other, ordinary tab in the same window.
3. Drag that ordinary tab onto either visible Split View pane.

The pane should be highlighted while the pointer is over it. After the drop,
the dragged tab should occupy that pane and the displaced page should appear as
an ordinary tab in the tab strip.

## How to use

DnDFox extends an existing native Split View; it does not create Split View
itself.

1. Open two pages in Firefox Split View.
2. In the same Firefox window, press and hold an ordinary tab that is not
   already part of that Split View.
3. Drag it from the tab strip over the content of the left or right pane. The
   target pane receives a visual highlight.
4. Release the mouse button over the pane you want to replace.

For example:

```text
[ A | B ]  C  D    -- drag C onto B -->    [ A | C ]  B  D
```

The Split View remains active. The replaced page is preserved as a background
tab next to its previous tab-strip position, and the divider returns to its
previous ratio. Dropping outside either pane cancels the DnDFox operation and
leaves the Split View unchanged.

Only tabs from the current Firefox window are accepted. A tab that is already
inside the active Split View is not treated as a replacement source.

## How it works

DnDFox is a privileged browser-chrome script loaded at Firefox startup by the
vendored `fx-autoconfig` loader.

During a drag, the module:

1. Captures the active Split View on the initial mouse press, before Firefox
   switches selection to the dragged ordinary tab.
2. Restores the original Split View when the pointer enters the browser area.
3. Hit-tests the two pane browser rectangles and highlights the pane under the
   pointer.
4. On drop, records the divider ratio and duplicates the displaced page into a
   normal background tab so that it is not lost.
5. Uses Firefox's native `replaceTab` operation to insert the dragged tab, then
   selects it and restores the saved divider ratio after Firefox rebuilds the
   Split View layout.

Each operation carries its own identifier and validates that the tabs, window,
and Split View are still current before changing anything. Drag state and
visual highlighting are cleared on both drop and drag cancellation.

Because these are private Firefox APIs rather than a WebExtension API, a future
Firefox update can require a DnDFox compatibility update.

## Troubleshooting

- If the installer cannot find a profile, start Firefox once, close it, and run
  `install.cmd` again.
- If Firefox or the intended profile is installed in a non-standard location,
  use the explicit PowerShell command below.
- If a pane does not highlight, confirm that the source is an ordinary tab in
  the same window and that a native Split View is currently visible.
- Diagnostic messages use the prefix `[SplitView Drag Replace]` in Firefox's
  Browser Console.

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
