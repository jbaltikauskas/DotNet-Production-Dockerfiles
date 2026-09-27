function Assert-Cli () {
    <#
    .SYNOPSIS
        Verifies a CLI is on PATH and optionally returns its version.
    .DESCRIPTION
        Throws when the named command is not found with Get-Command. When
        VersionArgs is supplied, runs the command with those arguments and
        returns the trimmed output (for example the docker client version);
        otherwise returns nothing.
    .REMARKS
        1. Locate the command with Get-Command; throw when missing.
        2. Return when no VersionArgs were supplied.
        3. Run the command with VersionArgs and return the trimmed output.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, HelpMessage = 'Name of the CLI executable to require, for example docker or dotnet.')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $false, HelpMessage = 'Arguments that print the version; when set, the trimmed output is returned.')]
        [string[]]$VersionArgs
    )

    Begin {
        if ($PSBoundParameters.ContainsKey('Verbose') -or $VerbosePreference -eq 'Continue') {
            $PSBoundParameters | Out-String | Write-Host
        }
    }

    Process {

        $command = Get-Command -Name $Name -ErrorAction SilentlyContinue
        if (-not $command) {
            throw "$Name CLI was not found in PATH."
        }

        if (-not $VersionArgs) {
            return
        }

        return (& $Name @VersionArgs).Trim()
    }
}
