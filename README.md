# dotfiles

My Windows dev setup: a PowerShell 7 profile, shell tab completion, and the list of packages I install with winget.

## What's here

| Path | What it is |
| --- | --- |
| `install.ps1` | Sets up a machine from this repo. Safe to re-run. |
| `pwsh/profile.ps1` | PowerShell 7 profile. Tab completion for dotnet, az, git, winget, gh, glab and azd, loaded in the background so the prompt appears right away. |
| `git/gitconfig` | Shared git settings (delta as the pager). `~/.gitconfig` includes it and keeps the machine-specific parts, like `user.email`. |
| `pwsh/modules.txt` | PowerShell Gallery modules to install (one per line). |
| `winget/*.json` | Package lists in `winget export` format. `install.ps1` installs any listed package that's missing. |

## Set up a fresh machine

In Windows PowerShell (the one that ships with Windows):

```powershell
powershell -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/rarrarrarr/dotfiles/master/install.ps1 | iex"
```

This installs git and PowerShell 7, clones this repo, installs the packages in the winget lists, installs the modules in `pwsh/modules.txt`, and points PowerShell 7's `$PROFILE` at `pwsh/profile.ps1`. An existing profile is backed up first.

The repo is cloned to `X:\projects\github\rarrarrarr\dotfiles` if an `X:` drive exists, otherwise `~\src\dotfiles`. Pass `-DotfilesPath` to choose another location.

From an existing clone:

```powershell
.\install.ps1
```

Every run installs whatever is in the package lists, modules list and config but missing from the machine, and leaves everything else alone. To add a package, add it to a list in `winget/` and re-run.

## How the profile is linked

`$PROFILE` contains a single line that dot-sources the profile in this repo:

```powershell
. 'X:\projects\github\rarrarrarr\dotfiles\pwsh\profile.ps1'
```

Edits to `pwsh/profile.ps1` take effect in the next new terminal, and committing them is all it takes to sync them.

## Updating the lists

- **Packages:** `winget export -o winget\winget-packages.json`
- **Modules:** add the module name to `pwsh/modules.txt`

## License

[0BSD](LICENSE): copy anything you find useful, no attribution needed.
