# dotfiles

My Windows dev setup: a PowerShell 7 profile, shell tab completion, and the list of packages I install with winget.

## What's here

| Path | What it is |
| --- | --- |
| [`install.ps1`](install.ps1) | Sets up a machine from this repo. Safe to re-run. |
| [`pwsh/profile.ps1`](pwsh/profile.ps1) | PowerShell 7 profile. Tab completion for dotnet, az, git, winget, gh, glab, azd and uv, loaded in the background so the prompt appears right away. |
| [`git/gitconfig`](git/gitconfig) | Shared git settings (delta as the pager). `~/.gitconfig` includes it and keeps the machine-specific parts, like `user.email`. |
| [`readline/inputrc`](readline/inputrc) | Shared readline settings for Git Bash. `~/.inputrc` includes it with `$include` and keeps anything machine-specific. |
| [`pwsh/modules.txt`](pwsh/modules.txt) | PowerShell Gallery modules to install (one per line). |
| [`uv/tools.txt`](uv/tools.txt) | Python CLI tools to install with `uv tool install` (one per line). uv itself comes from the winget list. |
| [`winget/winget-packages.json`](winget/winget-packages.json) | Package lists in `winget export` format. `install.ps1` installs any listed package that's missing. |

## Set up a fresh machine

In Windows PowerShell (the one that ships with Windows):

```powershell
powershell -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/rarrarrarr/dotfiles/main/install.ps1 | iex"
```

This installs git and PowerShell 7, clones this repo, installs the packages in the winget lists, installs the modules in `pwsh/modules.txt`, installs the uv tools in `uv/tools.txt` and adds uv's tool folder (`~\.local\bin`) to your user PATH, makes `~/.inputrc` include `readline/inputrc`, and points PowerShell 7's `$PROFILE` at `pwsh/profile.ps1`. An existing profile is backed up first.

The repo is cloned to `X:\projects\github\rarrarrarr\dotfiles` if an `X:` drive exists, otherwise `~\src\dotfiles`. Pass `-DotfilesPath` to choose another location.

From an existing clone:

```powershell
.\install.ps1
```

Every run installs whatever is in the package lists, modules list, uv tools list and config but missing from the machine, and leaves everything else alone. To add a package, add it to a list in `winget/` and re-run.

## How the profile is linked

`$PROFILE` lists the places this repo might be cloned and dot-sources the profile from the first one that exists:

```powershell
foreach ($dotfilesProfile in @(
    'X:\projects\github\rarrarrarr\dotfiles\pwsh\profile.ps1'
    "$HOME\src\dotfiles\pwsh\profile.ps1"
)) {
    if (Test-Path $dotfilesProfile) { . $dotfilesProfile; break }
}
```

A list is needed because when Documents is backed up by OneDrive, `$PROFILE` lives there too and syncs to every PC on that account, and each PC may have the repo somewhere different. `install.ps1` keeps the locations already listed and adds the current PC's if it's missing (for example, one cloned with `-DotfilesPath`), so the PCs never overwrite each other's entries.

Edits to `pwsh/profile.ps1` take effect in the next new terminal, and committing them is all it takes to sync them.

`~/.inputrc` works the same way, using readline's `$include` directive. Its first line is:

```bash
$include X:/projects/github/rarrarrarr/dotfiles/readline/inputrc
```

Anything after that line is machine-specific and overrides the shared settings. Changes apply to new Git Bash windows, or press `Ctrl+X Ctrl+R` to reload in the current one.

## Updating the lists

- **Packages:** `winget export -o winget\winget-packages.json`
- **Modules:** add the module name to `pwsh/modules.txt`
- **uv tools:** add the package name to `uv/tools.txt` (`uv tool list` shows what's installed)

## License

[0BSD](LICENSE): copy anything you find useful, no attribution needed.
