function New-DotNetToolsBuildDirectory () {
    <#
    .SYNOPSIS
        Creates dockerfiles\.build under the repository root.
    .DESCRIPTION
        NuGet packages and their extracted contents are written under this folder.
    .NOTE
        1. Resolve dockerfiles\.build under RepositoryRoot.
        2. Create the directory when it does not exist.
        3. Return the absolute path.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, HelpMessage = 'Repository root under which dockerfiles\.build is created.')]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot
    )

    Begin {
        Write-Verbose ("BEGIN: {0}" -f $MyInvocation.MyCommand.Name)
        Write-Verbose ($PSBoundParameters | Out-String)
    }

    Process {

        $buildDirectory = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'dockerfiles\.build'))
        New-Item -ItemType Directory -Path $buildDirectory -Force | Out-Null
        return $buildDirectory
    }
}
