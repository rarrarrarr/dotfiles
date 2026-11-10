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
      4. winget import every *.json in the repo's winget\ folder
      5. Install the PowerShell 7 modules listed in pwsh\modules.txt
      6. Point PowerShell 7's $PROFILE at the repo's pwsh\profile.ps1

.EXAMPLE
    # Fresh machine, nothing cloned yet:
    powershell -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/rarrarrarr/dotfiles/master/install.ps1 | iex"

.EXAMPLE
    # From an existing clone:
    powershell -ExecutionPolicy Bypass -File .\install.ps1

.EXAMPLE
    # Skip the (slow) package import:
    .\install.ps1 -SkipPackages
#>
param(
    # Where the repo lives. Defaults to X:\projects\... if an X: drive exists, else ~\src\dotfiles.
    [string]$DotfilesPath = $(if (Test-Path 'X:\') { 'X:\projects\github\rarrarrarr\dotfiles' } else { Join-Path $HOME 'src\dotfiles' }),
    [switch]$SkipPackages
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
if ($SkipPackages) {
    Write-Step 'Skipping package import (-SkipPackages)'
}
else {
    $packageFiles = Get-ChildItem (Join-Path $DotfilesPath 'winget') -Filter *.json -ErrorAction SilentlyContinue
    if (-not $packageFiles) {
        Write-Warning "No package lists found in $DotfilesPath\winget\"
    }
    foreach ($file in $packageFiles) {
        Write-Step "Importing packages from $($file.Name) (this takes a while; some failures are normal)"
        winget import -i $file.FullName --accept-package-agreements --accept-source-agreements --ignore-unavailable --ignore-versions
        if ($LASTEXITCODE -ne 0) { Write-Warning "winget import reported problems (exit code $LASTEXITCODE). Scroll up for details." }
    }
    Update-SessionPath
}

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
        pwsh -NoProfile -Command "if (Get-Module -ListAvailable '$m') { '  $m is already installed' } else { Install-Module '$m' -Scope CurrentUser -Force; '  installed $m' }"
        if ($LASTEXITCODE -ne 0) { Write-Warning "Installing module $m failed." }
    }
}

# ---------------------------------------------------------------------------
# Ask pwsh 7 for its own $PROFILE path; 5.1's $PROFILE points somewhere else,
# and Documents may be redirected into OneDrive.
Write-Step 'Linking the PowerShell 7 profile'
$pwshProfile   = (pwsh -NoProfile -Command '$PROFILE').Trim()
$repoProfile   = Join-Path $DotfilesPath 'pwsh\profile.ps1'
$profileLine   = ". '$repoProfile'"

if ((Test-Path $pwshProfile) -and ((Get-Content $pwshProfile -Raw) -match [regex]::Escape($profileLine))) {
    Write-Host "  $pwshProfile already loads the repo profile"
}
else {
    if (Test-Path $pwshProfile) {
        $backup = "$pwshProfile.bak-$(Get-Date -Format yyyyMMddHHmmss)"
        Copy-Item $pwshProfile $backup
        Write-Host "  Backed up existing profile to $backup"
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $pwshProfile) | Out-Null
    Set-Content -Path $pwshProfile -Value $profileLine -Encoding UTF8
    Write-Host "  $pwshProfile now loads $repoProfile"
}

# ---------------------------------------------------------------------------
Write-Step 'Done'
Write-Host @"
Next:
  - Open a new Windows Terminal tab running PowerShell 7 (pwsh). If Windows Terminal
    still defaults to Windows PowerShell, change Settings > Startup > Default profile.
  - Completions load in the background a second or so after the prompt appears.
"@
