function Write-ImageBuildError () {
    <#
    .SYNOPSIS
        Prints the caught exception and the failure banner.
    .DESCRIPTION
        Shared catch handler for the Image-Build entry scripts. Prints the
        exception type and message, then the red failure line. Prompts for
        Enter only when -WaitOnExit is set, so a terminal or CI run exits
        immediately.
    .PARAMETER ErrorRecord
        The ErrorRecord from the caller's catch block.
    .PARAMETER WaitOnExit
        When set, waits for Enter so a double-clicked console window stays open.
    .REMARKS
        1. Print the exception type and message.
        2. Print the failure banner.
        3. When WaitOnExit is set, wait for Enter.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,

        [Parameter(Mandatory = $false)]
        [switch]$WaitOnExit
    )

    Process {

        Write-Host ""
        Write-Error "Caught an exception:" -ErrorAction Continue
        Write-Error "Exception Type: $($ErrorRecord.Exception.GetType().FullName)" -ErrorAction Continue
        Write-Error "Exception Message: $($ErrorRecord.Exception.Message)" -ErrorAction Continue
        Write-Host ""
        Write-Host "Script failed to execute." -ForegroundColor Red

        if ($WaitOnExit) {
            Read-Host "Press Enter to close the window ..."
        }
    }
}
