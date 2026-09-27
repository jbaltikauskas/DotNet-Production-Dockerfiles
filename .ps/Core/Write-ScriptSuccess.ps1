function Write-ScriptSuccess () {
    <#
    .SYNOPSIS
        Prints the success banner after a script run.
    .DESCRIPTION
        Shared success path for entry scripts. Prompts for Enter only when
        -WaitOnExit is set, so a terminal or CI run exits immediately.
    .REMARKS
        1. Print the success banner.
        2. When WaitOnExit is set, wait for Enter.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $false, HelpMessage = 'Wait for Enter after the success banner so a double-clicked console window stays open.')]
        [switch]$WaitOnExit
    )

    Process {

        Write-Host ""
        Write-Host "Script executed successfully." -ForegroundColor Green

        if ($WaitOnExit) {
            Read-Host "Press Enter to close the window ..."
        }
    }
}
