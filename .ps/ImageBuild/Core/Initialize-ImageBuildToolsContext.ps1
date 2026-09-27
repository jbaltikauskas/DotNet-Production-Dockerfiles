function Initialize-ImageBuildToolsContext () {
    <#
    .SYNOPSIS
        Ensures the dotnet-tools build context exists before a tools image build.
    .DESCRIPTION
        When any entry in ImageBuilds sets IncludeTools, the merged
        dockerfiles\.dotnet-tools folder must exist and be non-empty. When it is
        already populated it is reused; otherwise DotNet-Tools.ps1 is invoked to
        publish it. Does nothing when no build in the list includes the tools.
    .REMARKS
        1. Return early when no build in ImageBuilds includes the tools.
        2. Reuse the folder when it exists and contains files.
        3. Otherwise invoke DotNet-Tools.ps1 with Invoke-ImageBuildScript.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DotNetToolsContext,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [object[]]$ImageBuilds
    )

    Begin {
        if ($PSBoundParameters.ContainsKey('Verbose') -or $VerbosePreference -eq 'Continue') {
            $PSBoundParameters | Out-String | Write-Host
        }
    }

    Process {

        if ($ImageBuilds.IncludeTools -notcontains $true) {
            return
        }

        $toolsContextFull = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot $DotNetToolsContext))
        $toolsContextReady = $false
        if (Test-Path -LiteralPath $toolsContextFull -PathType Container) {
            $toolsContextReady = @(Get-ChildItem -LiteralPath $toolsContextFull -Force).Count -gt 0
        }

        if ($toolsContextReady) {
            Write-Host "Using existing ${DotNetToolsContext}." -ForegroundColor Green
            return
        }

        Invoke-ImageBuildScript `
            -RepositoryRoot $RepositoryRoot `
            -RelativePath '.ps\Diagnostics-Tools-Build\DotNet-Tools.ps1'
    }
}
