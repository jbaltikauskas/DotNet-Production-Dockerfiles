function Assert-LastExitCode () {
    <#
    .SYNOPSIS
        Throws when the last native command exited non-zero.
    .DESCRIPTION
        Reads the automatic $LASTEXITCODE and throws a descriptive error that
        names the activity when it is non-zero. Call immediately after a native
        command so $LASTEXITCODE still reflects that command.
    .NOTE
        1. Return when $LASTEXITCODE is zero or unset.
        2. Otherwise throw "<Activity> failed with exit code <code>.".
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, HelpMessage = 'Short name of the native command whose exit code is checked, for example "dotnet restore".')]
        [ValidateNotNullOrEmpty()]
        [string]$Activity
    )

    Begin {
        if ($PSBoundParameters.ContainsKey('Verbose') -or $VerbosePreference -eq 'Continue') {
            $PSBoundParameters | Out-String | Write-Host
        }
    }

    Process {

        if ($LASTEXITCODE) {
            throw "$Activity failed with exit code $LASTEXITCODE."
        }
    }
}
