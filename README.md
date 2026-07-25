# PC Optimizer

Windows utility written in PowerShell for:

- Junk-file cleanup
- Startup-item management
- Local privacy-trace cleanup
- Duplicate-file scan and quarantine
- GitHub Releases based updates

## Project layout

- `PCOptimizer.ps1`: main app
- `Run-PCOptimizer.bat`: local launcher
- `version.json`: current app version
- `appsettings.json`: GitHub release/update settings
- `scripts\Install-PCOptimizer.ps1`: installs the app for the current user
- `scripts\Uninstall-PCOptimizer.ps1`: removes the installed app
- `scripts\Build-Release.ps1`: builds release assets
- `.github\workflows\release.yml`: GitHub Actions release workflow

## Local usage

Run the app directly:

```powershell
powershell -ExecutionPolicy Bypass -File .\PCOptimizer.ps1
```

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

Default install location:

```text
%LOCALAPPDATA%\Programs\PCOptimizer
```

That installer copies the app files and creates Desktop and Start Menu shortcuts.

## Set up GitHub updates

1. Put this folder in its own Git repository.
2. Create a GitHub repository for it.
3. Edit `appsettings.json` and set:

```json
{
  "githubOwner": "your-github-name",
  "githubRepo": "your-repo-name"
}
```

4. Commit the project and push it to GitHub.
5. Create a version tag like `v0.1.0`.
6. Push the tag.

The included workflow will build and publish:

- `PCOptimizer-v0.1.0.zip`
- `latest.json`
- `Install-PCOptimizer.ps1`

The app checks:

```text
https://github.com/<owner>/<repo>/releases/latest/download/latest.json
```

## Build release assets manually

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Build-Release.ps1
```

Output goes to:

```text
.\dist
```

## Update flow

1. User installs the app.
2. You publish a new GitHub Release with a higher version in `version.json`.
3. The app reads `latest.json` from the latest release.
4. `SelfUpdate` downloads the new ZIP, verifies SHA-256, replaces the installed files, and relaunches the app.

## Important notes

- `appsettings.json` ships with placeholder GitHub values. Updates will not work until you replace them.
- Duplicate cleanup uses quarantine under `%LOCALAPPDATA%\PCOptimizer\Quarantine` instead of hard delete.
- Running cleanup as administrator improves access to system temp locations.
- This is a practical release system for a PowerShell app, not a signed commercial installer pipeline.
