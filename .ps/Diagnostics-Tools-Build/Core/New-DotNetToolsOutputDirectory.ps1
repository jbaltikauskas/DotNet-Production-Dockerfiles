function New-DotNetToolsOutputDirectory () {
    <#
    .SYNOPSIS
        Creates the shared dotnet-tools folder under Build.
    .DESCRIPTION
        Runtime files copied from each extracted package are written here.
    .REMARKS
        1. Resolve Build\dotnet-tools.
        2. Create the directory when it does not exist.
        3. Return the absolute path.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$BuildDirectory
    )

    Begin {
        if ($PSBoundParameters.ContainsKey('Verbose') -or $VerbosePreference -eq 'Continue') {
            $PSBoundParameters | Out-String | Write-Host
        }
    }

    Process {

        $toolDirectory = [System.IO.Path]::GetFullPath((Join-Path $BuildDirectory 'dotnet-tools'))
        New-Item -ItemType Directory -Path $toolDirectory -Force | Out-Null
        return $toolDirectory
    }
}
