## START TAB COMPLETION

# show all tab completion options for a command
Set-PSReadlineKeyHandler -Key Tab -Function MenuComplete

# az cli tab completion:
Register-ArgumentCompleter -Native -CommandName az -ScriptBlock {
    param($commandName, $wordToComplete, $cursorPosition)
    $completion_file = New-TemporaryFile
    $env:ARGCOMPLETE_USE_TEMPFILES = 1
    $env:_ARGCOMPLETE_STDOUT_FILENAME = $completion_file
    $env:COMP_LINE = $wordToComplete
    $env:COMP_POINT = $cursorPosition
    $env:_ARGCOMPLETE = 1
    $env:_ARGCOMPLETE_SUPPRESS_SPACE = 0
    $env:_ARGCOMPLETE_IFS = "`n"
    $env:_ARGCOMPLETE_SHELL = 'powershell'
    az 2>&1 | Out-Null
    Get-Content $completion_file | Sort-Object | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, "ParameterValue", $_)
    }
    Remove-Item $completion_file, Env:\_ARGCOMPLETE_STDOUT_FILENAME, Env:\ARGCOMPLETE_USE_TEMPFILES, Env:\COMP_LINE, Env:\COMP_POINT, Env:\_ARGCOMPLETE, Env:\_ARGCOMPLETE_SUPPRESS_SPACE, Env:\_ARGCOMPLETE_IFS, Env:\_ARGCOMPLETE_SHELL
}

# winget tab completion: 
Register-ArgumentCompleter -Native -CommandName winget -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
        [Console]::InputEncoding = [Console]::OutputEncoding = $OutputEncoding = [System.Text.Utf8Encoding]::new()
        $Local:word = $wordToComplete.Replace('"', '""')
        $Local:ast = $commandAst.ToString().Replace('"', '""')
        winget complete --word="$Local:word" --commandline "$Local:ast" --position $cursorPosition | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
}

# 1. Generate completion scripts off the main thread so that the prompt is instantly available
$global:__completionJob = Start-ThreadJob {
    dotnet completions script pwsh
    gh completion -s powershell
    glab completion -s powershell
    azd completion powershell
    uv generate-shell-completion powershell
    uvx --generate-shell-completion powershell
}

# 2. When the prompt is idle and the job is done, load everything into this session
$null = Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -Action {
    if ($global:__completionJob.State -notin 'Completed', 'Failed') { return }   # not ready, try next idle
    $lines = (Receive-Job $global:__completionJob | Out-String) -split '\r?\n'
    Remove-Job $global:__completionJob
    # `using` statements must come first in a script, and dotnet's and uv's completion
    # scripts each start with the same ones. Move them to the top, once each: a repeated
    # `using namespace` silently breaks the -Native completers that rely on it.
    $using = $lines | Where-Object { $_ -match '^\s*using\s' } | ForEach-Object Trim | Select-Object -Unique
    $rest  = $lines | Where-Object { $_ -notmatch '^\s*using\s' }
    Invoke-Expression ((@($using) + @($rest)) -join "`n")
    Import-Module posh-git -Global
    Unregister-Event -SubscriptionId $EventSubscriber.SubscriptionId
}

## END TAB COMPLETION


# PSReadLine Tweaks

Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward        # type "git", press Up: only git history
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
Set-PSReadLineOption -HistoryNoDuplicates