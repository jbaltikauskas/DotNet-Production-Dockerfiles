function Write-ImageBuildSuccess () {
    <#
    .SYNOPSIS
        Prints the success banner after an Image-Build run.
    .DESCRIPTION
        Shared success path for the Image-Build entry scripts. Prompts for
        Enter only when -WaitOnExit is set, so a terminal or CI run exits
        immediately.
    .PARAMETER WaitOnExit
        When set, waits for Enter so a double-clicked console window stays open.
    .REMARKS
        1. Print the success banner.
        2. When WaitOnExit is set, wait for Enter.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $false)]
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
