function New-DotNetToolsBuildDirectory () {
    <#
    .SYNOPSIS
        Creates dockerfiles\.build under the repository root.
    .DESCRIPTION
        NuGet packages and their extracted contents are written under this folder.
    .REMARKS
        1. Resolve dockerfiles\.build under RepositoryRoot.
        2. Create the directory when it does not exist.
        3. Return the absolute path.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot
    )

    Begin {
        if ($PSBoundParameters.ContainsKey('Verbose') -or $VerbosePreference -eq 'Continue') {
            $PSBoundParameters | Out-String | Write-Host
        }
    }

    Process {

        $buildDirectory = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'dockerfiles\.build'))
        New-Item -ItemType Directory -Path $buildDirectory -Force | Out-Null
        return $buildDirectory
    }
}
