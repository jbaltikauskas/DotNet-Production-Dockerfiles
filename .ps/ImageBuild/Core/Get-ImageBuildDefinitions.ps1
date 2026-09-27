function Get-ImageBuildDefinitions () {
    <#
    .SYNOPSIS
        Builds the list of image builds for one distro.
    .DESCRIPTION
        Returns a List[pscustomobject] describing the docker builds to run. The
        first entry is always the diagnostics-tools image (target: final,
        IncludeTools true). Unless ToolsOnly is set, a second entry is the lean
        base image (target: BaseTarget, IncludeTools false). Dockerfile folder
        and image tags are derived from DistroLabel and DotNetVersion.
    .REMARKS
        1. Derive the version folder, Dockerfile path, and both image tags.
        2. Add the diagnostics-tools (final) build.
        3. Add the lean base build unless ToolsOnly is set.
        4. Return the list.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DistroLabel,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DotNetVersion,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$BaseTarget,

        [Parameter(Mandatory = $false)]
        [switch]$ToolsOnly
    )

    Begin {
        if ($PSBoundParameters.ContainsKey('Verbose') -or $VerbosePreference -eq 'Continue') {
            $PSBoundParameters | Out-String | Write-Host
        }
    }

    Process {

        $versionFolder = "dockerfiles/${DistroLabel}/${DotNetVersion}"
        $dockerfile = "${versionFolder}/Dockerfile"
        $toolsImageTag = "contoso/${DistroLabel}-net-dotnet-tools-${DotNetVersion}:latest"
        $baseImageTag = "contoso/${DistroLabel}-net-${DotNetVersion}:latest"

        $imageBuilds = [System.Collections.Generic.List[pscustomobject]]::new()

        $imageBuilds.Add([pscustomobject]@{
                Distro       = $DistroLabel
                Dockerfile   = $dockerfile
                BuildContext = $versionFolder
                BuildTarget  = 'final'
                Tag          = $toolsImageTag
                BuildArgs    = @{}
                IncludeTools = $true
            })

        if (-not $ToolsOnly) {
            $imageBuilds.Add([pscustomobject]@{
                    Distro       = $DistroLabel
                    Dockerfile   = $dockerfile
                    BuildContext = $versionFolder
                    BuildTarget  = $BaseTarget
                    Tag          = $baseImageTag
                    BuildArgs    = @{}
                    IncludeTools = $false
                })
        }

        return $imageBuilds
    }
}
