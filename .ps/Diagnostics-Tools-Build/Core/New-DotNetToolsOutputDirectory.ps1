function New-DotNetToolsOutputDirectory () {
    <#
    .SYNOPSIS
        Creates the shared dotnet-tools folder under Build.
    .DESCRIPTION
        Runtime files copied from each extracted package are written here.
    .NOTE
        1. Resolve Build\dotnet-tools.
        2. Create the directory when it does not exist.
        3. Return the absolute path.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, HelpMessage = 'Build folder under which the dotnet-tools output folder is created.')]
        [ValidateNotNullOrEmpty()]
        [string]$BuildDirectory
    )

    Begin {
        Write-Verbose ("BEGIN: {0}" -f $MyInvocation.MyCommand.Name)
        Write-Verbose ($PSBoundParameters | Out-String)
    }

    Process {

        $toolDirectory = [System.IO.Path]::GetFullPath((Join-Path $BuildDirectory 'dotnet-tools'))
        New-Item -ItemType Directory -Path $toolDirectory -Force | Out-Null
        return $toolDirectory
    }
}
