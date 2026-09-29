function Write-Section () {
    <#
    .SYNOPSIS
        Prints a cyan section banner.
    .DESCRIPTION
        Writes a blank line, a cyan rule, the message, and a cyan rule. Used to
        mark each phase of a script run in the console output.
    .NOTE
        1. Print a leading blank line and the top rule.
        2. Print the message and the bottom rule.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, HelpMessage = 'The banner text shown between the two cyan rules.')]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    Begin {
        Write-Verbose ("BEGIN: {0}" -f $MyInvocation.MyCommand.Name)
        Write-Verbose ($PSBoundParameters | Out-String)
    }

    Process {

        $rule = '============================================================='
        Write-Host ""
        Write-Host $rule -ForegroundColor Cyan
        Write-Host "  $Message" -ForegroundColor Cyan
        Write-Host $rule -ForegroundColor Cyan
    }
}
