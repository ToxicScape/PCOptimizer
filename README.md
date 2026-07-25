# PC Optimizer

Windows utility written in PowerShell with a desktop GUI for:

- Junk-file cleanup
- Startup-item management
- Local privacy-trace cleanup
- Duplicate-file scan and quarantine
- GitHub Releases based updates

## Project layout

- `PCOptimizer.ps1`: core optimizer logic and CLI entry point
- `PCOptimizer.GUI.ps1`: Windows desktop interface
- `Run-PCOptimizer.bat`: local launcher
- `Install-PCOptimizer.bat`: double-click bootstrap installer
- `version.json`: current app version
- `appsettings.json`: GitHub release/update settings
- `scripts\Install-PCOptimizer.ps1`: installs the app for the current user
- `scripts\Uninstall-PCOptimizer.ps1`: removes the installed app
- `scripts\Build-Release.ps1`: builds release assets
- `scripts\Publish-ManualRelease.ps1`: build, commit, tag, push, and open the GitHub release page
- `.github\workflows\release.yml`: GitHub Actions release workflow

## Local usage

Run the visual app:

```powershell
powershell -STA -ExecutionPolicy Bypass -File .\PCOptimizer.GUI.ps1
```

Or double-click `Run-PCOptimizer.bat`.

Show version:

```powershell
powershell -ExecutionPolicy Bypass -File .\PCOptimizer.ps1 -Action Version
```

Check for updates:

```powershell
powershell -ExecutionPolicy Bypass -File .\PCOptimizer.ps1 -Action UpdateCheck
```

Apply the latest update:

```powershell
powershell -ExecutionPolicy Bypass -File .\PCOptimizer.ps1 -Action SelfUpdate
```

## Install for other users

From the project folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-PCOptimizer.ps1
```

Or double-click:

```text
Install-PCOptimizer.bat
```

Default install location:

```text
%LOCALAPPDATA%\Programs\PCOptimizer
```

That installer copies the app files and creates Desktop and Start Menu shortcuts.

## Easiest release flow

When you want to ship an update, run one command:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Publish-ManualRelease.ps1 -Version 0.1.1
```

That script will:

- update `version.json`
- build the release files into `.\dist`
- commit the release changes
- create the git tag
- push `main` and the tag
- open the GitHub release page for that tag

Then upload the three files it prints:

- `PCOptimizer-v0.1.1.zip`
- `latest.json`
- `Install-PCOptimizer.ps1`
- `Install-PCOptimizer.bat`

If you do not want it to push yet:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Publish-ManualRelease.ps1 -Version 0.1.1 -NoPush -NoOpenReleasePage
```

## Update flow

1. User installs the app.
2. You publish a new GitHub Release with a higher version in `version.json`.
3. The app reads `latest.json` from the latest release.
4. `SelfUpdate` downloads the new ZIP, verifies SHA-256, replaces the installed files, and relaunches the app.

## Important notes

- `appsettings.json` is already pointed at `ToxicScape/PCOptimizer`.
- Duplicate cleanup uses quarantine under `%LOCALAPPDATA%\PCOptimizer\Quarantine` instead of hard delete.
- Running cleanup as administrator improves access to system temp locations.
- This is a practical release system for a PowerShell app, not a signed commercial installer pipeline.
