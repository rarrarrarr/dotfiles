<#
.SYNOPSIS
    Sets up a fresh Windows machine from the rarrarrarr/dotfiles repo.

.DESCRIPTION
    Written for Windows PowerShell 5.1, since that's all a fresh machine has.
    Safe to re-run: each step checks before it changes anything.

    Steps:
      1. Check winget is available
      2. Install git and PowerShell 7 (needed before anything else)
      3. Clone the dotfiles repo (or pull if already cloned)
      4. Install any package from the repo's winget\*.json lists that isn't installed yet
      5. Install the PowerShell 7 modules listed in pwsh\modules.txt
      6. Install the uv tools listed in uv\tools.txt and put uv's tool folder on PATH
      7. Make ~/.gitconfig include the repo's git\gitconfig
      8. Make ~/.inputrc include the repo's readline\inputrc
      9. Point PowerShell 7's $PROFILE at the repo's pwsh\profile.ps1

.EXAMPLE
    # Fresh machine, nothing cloned yet:
    powershell -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/rarrarrarr/dotfiles/main/install.ps1 | iex"

.EXAMPLE
    # From an existing clone:
    powershell -ExecutionPolicy Bypass -File .\install.ps1
#>
param(
    # Where the repo lives. Defaults to X:\projects\... if an X: drive exists, else ~\src\dotfiles.
    [string]$DotfilesPath = $(if (Test-Path 'X:\') { 'X:\projects\github\rarrarrarr\dotfiles' } else { Join-Path $HOME 'src\dotfiles' })
)

$ErrorActionPreference = 'Stop'
$RepoUrl = 'https://github.com/rarrarrarr/dotfiles'

# If this script is running from inside a clone, use that clone (unless a path was given explicitly).
if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot 'pwsh\profile.ps1')) -and -not $PSBoundParameters.ContainsKey('DotfilesPath')) {
    $DotfilesPath = $PSScriptRoot
}

function Write-Step($Message) { Write-Host "`n==> $Message" -ForegroundColor Cyan }

# winget installs update the registry PATH, not this session's PATH.
function Update-SessionPath {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}

function Install-WingetPackage($Id) {
    winget list --id $Id -e --accept-source-agreements *> $null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  $Id is already installed"
        return
    }
    winget install --id $Id -e --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { throw "winget failed to install $Id (exit code $LASTEXITCODE)" }
}

# ---------------------------------------------------------------------------
Write-Step 'Checking for winget'
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw "winget wasn't found. Install or update 'App Installer' from the Microsoft Store, then re-run this script."
}
winget --version

# ---------------------------------------------------------------------------
Write-Step 'Installing git and PowerShell 7'
Install-WingetPackage 'Git.Git'
Install-WingetPackage 'Microsoft.PowerShell'
Update-SessionPath

foreach ($tool in 'git', 'pwsh') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "$tool was installed but isn't on PATH yet. Open a new terminal and re-run this script."
    }
}

# ---------------------------------------------------------------------------
Write-Step "Getting the dotfiles repo at $DotfilesPath"
if (Test-Path (Join-Path $DotfilesPath '.git')) {
    git -C $DotfilesPath pull --ff-only
    if ($LASTEXITCODE -ne 0) { Write-Warning "Couldn't fast-forward $DotfilesPath; continuing with what's there." }
}
else {
    New-Item -ItemType Directory -Force -Path (Split-Path $DotfilesPath) | Out-Null
    git clone $RepoUrl $DotfilesPath
    if ($LASTEXITCODE -ne 0) { throw "git clone of $RepoUrl failed." }
}

# ---------------------------------------------------------------------------
# Install only what's in the package lists but missing from this machine. One
# `winget export` of the installed packages plus a diff is far faster than
# `winget import`, which checks every listed package one at a time.
Write-Step 'Installing missing winget packages'
$installed = @{}   # hashtable keys are case-insensitive
$installedFile = Join-Path ([IO.Path]::GetTempPath()) "winget-installed-$PID.json"
winget export -o $installedFile --accept-source-agreements *> $null
if (Test-Path $installedFile) {
    foreach ($id in (Get-Content $installedFile -Raw | ConvertFrom-Json).Sources.Packages.PackageIdentifier) { $installed[$id] = $true }
    Remove-Item $installedFile
}
else {
    Write-Warning "Couldn't list installed packages; winget will check each listed package itself."
}

$packageFiles = Get-ChildItem (Join-Path $DotfilesPath 'winget') -Filter *.json -ErrorAction SilentlyContinue
if (-not $packageFiles) { Write-Warning "No package lists found in $DotfilesPath\winget\" }
$attempted = 0
foreach ($file in $packageFiles) {
    foreach ($source in (Get-Content $file.FullName -Raw | ConvertFrom-Json).Sources) {
        foreach ($package in $source.Packages) {
            $id = $package.PackageIdentifier
            if ($installed.ContainsKey($id)) { continue }
            $attempted++
            Write-Host "  Installing $id"
            winget install --id $id -e --source $source.SourceDetails.Name --accept-package-agreements --accept-source-agreements
            if ($LASTEXITCODE -ne 0) { Write-Warning "$id didn't install (exit code $LASTEXITCODE)" }
            $installed[$id] = $true   # don't retry it if it's in more than one list
        }
    }
}
if ($attempted -eq 0) { Write-Host '  Everything in the package lists is already installed' }
Update-SessionPath

# ---------------------------------------------------------------------------
# Modules must be installed from PowerShell 7: modules installed from 5.1 land in a
# different folder (Documents\WindowsPowerShell\Modules) that pwsh 7 doesn't read.
$moduleList = Join-Path $DotfilesPath 'pwsh\modules.txt'
Write-Step "Installing PowerShell 7 modules from $moduleList"
if (-not (Test-Path $moduleList)) {
    Write-Warning "No module list at $moduleList"
}
else {
    # One module name per line; blank lines and # comments are ignored.
    $modules = Get-Content $moduleList |
        ForEach-Object { ($_ -replace '#.*$', '').Trim() } |
        Where-Object { $_ }
    foreach ($m in $modules) {
        pwsh -NoProfile -Command "if (Get-Module -ListAvailable '$m') { '  $m is already installed' } else { Install-PSResource '$m' -Scope CurrentUser -TrustRepository; '  installed $m' }"
        if ($LASTEXITCODE -ne 0) { Write-Warning "Installing module $m failed." }
    }
}

# ---------------------------------------------------------------------------
# uv itself comes from the winget list (astral-sh.uv). `uv tool install` puts each
# tool's executables in uv's tool bin folder (~\.local\bin), and
# `uv tool update-shell` adds that folder to the user PATH so every shell finds them.
$toolList = Join-Path $DotfilesPath 'uv\tools.txt'
Write-Step "Installing uv tools from $toolList"
if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    Write-Warning "uv isn't on PATH, so uv tools were skipped. Add astral-sh.uv to a winget list, or open a new terminal and re-run."
}
elseif (-not (Test-Path $toolList)) {
    Write-Warning "No uv tool list at $toolList"
}
else {
    # `uv tool list` prints "name vX.Y.Z" for each tool, then "- exe" lines for its executables.
    $installedTools = @{}
    foreach ($line in (uv tool list 2>$null)) {
        if ($line -match '^(\S+) v') { $installedTools[$Matches[1]] = $true }
    }
    # One package name per line; blank lines and # comments are ignored.
    $tools = Get-Content $toolList |
        ForEach-Object { ($_ -replace '#.*$', '').Trim() } |
        Where-Object { $_ }
    foreach ($t in $tools) {
        if ($installedTools.ContainsKey($t)) {
            Write-Host "  $t is already installed"
            continue
        }
        uv tool install $t
        if ($LASTEXITCODE -ne 0) { Write-Warning "uv tool install $t failed (exit code $LASTEXITCODE)" }
    }

    uv tool update-shell
    if ($LASTEXITCODE -ne 0) { Write-Warning "uv tool update-shell failed; add $(uv tool dir --bin) to PATH yourself." }
    Update-SessionPath
}

# ---------------------------------------------------------------------------
# ~/.gitconfig keeps machine-specific values (user.email, credential helpers) and
# includes the shared settings from the repo. A symlink wouldn't survive
# `git config --global`, which replaces the file whenever it writes.
$repoGitConfig = (Join-Path $DotfilesPath 'git\gitconfig') -replace '\\', '/'
Write-Step "Making ~/.gitconfig include $repoGitConfig"
$includes = @(git config --global --get-all include.path)
if ($includes -contains $repoGitConfig) {
    Write-Host '  ~/.gitconfig already includes it'
}
else {
    git config --global --add include.path $repoGitConfig
    if ($LASTEXITCODE -ne 0) { throw 'Adding include.path to ~/.gitconfig failed.' }
    Write-Host '  Added include.path to ~/.gitconfig'
}
if (-not (git config --global user.email)) {
    Write-Warning "user.email isn't set. Run: git config --global user.email <your GitHub noreply address>"
}

# ---------------------------------------------------------------------------
# ~/.inputrc (read by Git Bash's readline) includes the shared settings from the
# repo with readline's $include directive, the same way ~/.gitconfig does.
# Existing lines are kept after the include, so they still apply and override it.
$repoInputrc  = (Join-Path $DotfilesPath 'readline\inputrc') -replace '\\', '/'
$homeInputrc  = Join-Path $HOME '.inputrc'
$includeLine  = "`$include $repoInputrc"
Write-Step "Making ~/.inputrc include $repoInputrc"
$existing = if (Test-Path $homeInputrc) { @(Get-Content $homeInputrc) } else { @() }
if ($existing | Where-Object { $_.Trim() -eq $includeLine }) {
    Write-Host '  ~/.inputrc already includes it'
}
else {
    if ($existing) {
        $backup = "$homeInputrc.bak-$(Get-Date -Format yyyyMMddHHmmss)"
        Copy-Item $homeInputrc $backup
        Write-Host "  Backed up existing ~/.inputrc to $backup"
    }
    # No BOM and LF endings: readline would treat a BOM as part of the first line.
    $content = (@($includeLine) + $existing) -join "`n"
    [IO.File]::WriteAllText($homeInputrc, "$content`n", (New-Object Text.UTF8Encoding $false))
    Write-Host "  Added `$include to ~/.inputrc"
}

# ---------------------------------------------------------------------------
# Ask pwsh 7 for its own $PROFILE path; 5.1's $PROFILE points somewhere else,
# and Documents may be redirected into OneDrive.
#
# When Documents is in OneDrive, $PROFILE syncs to every PC on that account, and
# each PC may have the repo somewhere different. So $PROFILE lists every known
# clone location and loads the first that exists. Locations already listed (by
# other PCs) are kept, and this PC's is added if it's missing, so every PC ends
# up writing the same file.
Write-Step 'Linking the PowerShell 7 profile'
$pwshProfile = (pwsh -NoProfile -Command '$PROFILE').Trim()
$repoProfile = Join-Path $DotfilesPath 'pwsh\profile.ps1'

# Entries are PowerShell string literals, written into $PROFILE as-is.
$candidates = [Collections.Generic.List[string]]@(
    "'X:\projects\github\rarrarrarr\dotfiles\pwsh\profile.ps1'"
    '"$HOME\src\dotfiles\pwsh\profile.ps1"'
)
$existingProfile = if (Test-Path $pwshProfile) { @(Get-Content $pwshProfile) } else { @() }
foreach ($line in $existingProfile) {
    if ($line -match '^    (''[^'']+''|"[^"]+")\s*$') { $literal = $Matches[1] }   # entry in our list
    elseif ($line -match "^\. '([^']+)'\s*$")       { $literal = "'$($Matches[1])'" }  # old one-line format
    else { continue }
    if ($candidates -notcontains $literal) { $candidates.Add($literal) }
}
$expand = { param($literal) $literal.Substring(1, $literal.Length - 2).Replace('$HOME', $HOME) }
if (-not ($candidates | Where-Object { (& $expand $_) -eq $repoProfile })) {
    $candidates.Add("'$repoProfile'")
}

$profileContent = @"
# Written by dotfiles\install.ps1; re-run it rather than editing this file.
# This file may sync between PCs through OneDrive, so it lists every place the
# dotfiles repo is cloned and loads the profile from the first one that exists.
foreach (`$dotfilesProfile in @(
$(($candidates | ForEach-Object { "    $_" }) -join "`n")
)) {
    if (Test-Path `$dotfilesProfile) { . `$dotfilesProfile; break }
}
Remove-Variable dotfilesProfile
"@

if (($existingProfile -join "`n").Trim() -eq ($profileContent -replace '\r', '').Trim()) {
    Write-Host "  $pwshProfile already loads the repo profile"
}
else {
    if ($existingProfile) {
        $backup = "$pwshProfile.bak-$(Get-Date -Format yyyyMMddHHmmss)"
        Copy-Item $pwshProfile $backup
        Write-Host "  Backed up existing profile to $backup"
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $pwshProfile) | Out-Null
    Set-Content -Path $pwshProfile -Value $profileContent -Encoding UTF8
    Write-Host "  $pwshProfile now loads the repo profile from the first of:"
    $candidates | ForEach-Object { Write-Host "    $_" }
}

# ---------------------------------------------------------------------------
Write-Step 'Done'
Write-Host @"
Next:
  - Open a new Windows Terminal tab running PowerShell 7 (pwsh). If Windows Terminal
    still defaults to Windows PowerShell, change Settings > Startup > Default profile.
  - Completions load in the background a second or so after the prompt appears.
"@
