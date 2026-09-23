#!/usr/bin/env pwsh
#Requires -Version 7.2
<#
.SYNOPSIS
    Builds the Contoso .NET 10 production Docker base images for Alpine.

.DESCRIPTION
    Top-down flow when this script runs:

        1. Resolve the repository root next to this script.
        2. Load helper functions from .ps\ImageBuild\Core.
        3. Verify that the docker CLI is available.
        4. Build Alpine images tagged :latest. The lean aspnet-base image
           is always built. -ToolsOnly appends the diagnostics-tools image
           (target: final):
             a. aspnet-base without the dotnet-tools build context
             b. final with --build-context dotnet-tools=dockerfiles/.dotnet-tools
                when -ToolsOnly is set
        5. Compose docker buildx build arguments per image.
        6. Invoke docker from the repository root and stream the output.

    Images produced for -DotNetVersion 10 (the default):

        - contoso/alpine-net-10:latest                 (target: aspnet-base)
        - contoso/alpine-net-dotnet-tools-10:latest    (target: final, -ToolsOnly)

    Dockerfile, build context, and tags use -DotNetVersion:
    dockerfiles/alpine/<DotNetVersion> and
    contoso/alpine-net-dotnet-tools-<DotNetVersion>:latest.

.PARAMETER DotNetVersion
    .NET major version. Selects the Dockerfile folder and the version
    segment of each image tag. Defaults to 10.

.PARAMETER NoCache
    Passes --no-cache to docker buildx build. Defaults to $true to match the
    Copy-and-Paste examples in the Dockerfile. Use -NoCache:$false to allow
    the BuildKit cache.

.PARAMETER ToolsOnly
    Appends the diagnostics-tools image (target: final) to the build list.
    The lean aspnet-base image is always built. Omit it to build only
    aspnet-base.

.PARAMETER WaitOnExit
    When set, waits for Enter after success or failure so a double-clicked
    console window stays open. Omit it in a terminal or CI run. Defaults to off.

.INPUTS
    None. Pass -DotNetVersion to select a folder other than dockerfiles/alpine/10.

.OUTPUTS
    Host messages and docker CLI output. Exit code 0 on success.

.NOTES
    Requires PowerShell 7.2+ and a working Docker installation with buildx.
    The tools image requires the dockerfiles/.dotnet-tools folder produced by
    .ps\Diagnostics-Tools-Build\DotNet-Tools.ps1. The lean aspnet-base image does not.

.EXAMPLE
    PS> .\Image-Build-Alpine.ps1
    Builds contoso/alpine-net-10:latest.

.EXAMPLE
    PS> .\Image-Build-Alpine.ps1 -DotNetVersion 10
    Builds the Alpine aspnet-base image under dockerfiles/alpine/10.

.EXAMPLE
    PS> .\Image-Build-Alpine.ps1 -NoCache:$false
    Builds the Alpine aspnet-base image with BuildKit cache enabled.

.EXAMPLE
    PS> .\Image-Build-Alpine.ps1 -ToolsOnly
    Builds contoso/alpine-net-10:latest and contoso/alpine-net-dotnet-tools-10:latest.

.EXAMPLE
    PS> .\Image-Build-Alpine.ps1 -WaitOnExit
    Builds the Alpine aspnet-base image and waits for Enter before the window closes.
#>

[CmdletBinding()]
Param (
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$DotNetVersion = '10',

    [Parameter(Mandatory = $false)]
    [bool]$NoCache = $true,

    [Parameter(Mandatory = $false)]
    [switch]$ToolsOnly,

    [Parameter(Mandatory = $false)]
    [switch]$WaitOnExit
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true


$scriptRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptRoot)) {
    $scriptRoot = (Get-Location).Path
}

$modulePath = Join-Path $scriptRoot '.ps\ImageBuild'
if (-not (Test-Path -LiteralPath $modulePath -PathType Container)) {
    throw "Required helper folder not found: '$modulePath'."
}

. (Join-Path $modulePath 'Core\Write-ImageBuildError.ps1')
. (Join-Path $modulePath 'Core\Write-ImageBuildSuccess.ps1')

try {

    $distroLabel = 'alpine'
    $repositoryRoot = [System.IO.Path]::GetFullPath($scriptRoot)
    $dotnetToolsContext = 'dockerfiles/.dotnet-tools'

    Write-Output "Loading module files:"

    $moduleFiles = @(
        'Core\Assert-ImageBuildDockerCli.ps1'
        'Core\Invoke-DockerImageBuild.ps1'
        'Core\Invoke-ImageBuildBatch.ps1'
        'Core\Write-ImageBuildSettings.ps1'
        'Core\Write-ImageBuildSummary.ps1'
    )

    foreach ($relativePath in $moduleFiles) {
        $moduleFile = Join-Path $modulePath $relativePath
        Write-Output "  $moduleFile"
        . $moduleFile
    }

    Write-Host "Done loading module files." -ForegroundColor Green

    $versionFolder = "dockerfiles/alpine/${DotNetVersion}"
    $dockerfile = "${versionFolder}/Dockerfile"
    $toolsImageTag = "contoso/alpine-net-dotnet-tools-${DotNetVersion}:latest"
    $baseImageTag = "contoso/alpine-net-${DotNetVersion}:latest"

    $imageBuilds = [System.Collections.Generic.List[pscustomobject]]::new()

    $imageBuilds.Add([pscustomobject]@{
        Distro       = $distroLabel
        Dockerfile   = $dockerfile
        BuildContext = $versionFolder
        BuildTarget  = 'final'
        Tag          = $toolsImageTag
        BuildArgs    = @{}
        IncludeTools = $true
    })

    if (-not $ToolsOnly) {
        $imageBuilds.Add([pscustomobject]@{
            Distro       = $distroLabel
            Dockerfile   = $dockerfile
            BuildContext = $versionFolder
            BuildTarget  = 'aspnet-base'
            Tag          = $baseImageTag
            BuildArgs    = @{}
            IncludeTools = $false
        })
    }

    Write-ImageBuildSettings `
        -RepositoryRoot $repositoryRoot `
        -Distro $distroLabel `
        -NoCache $NoCache `
        -DotNetToolsContext $dotnetToolsContext `
        -ImageBuilds $imageBuilds

    Write-Host "Verifying docker CLI:" -ForegroundColor Green
    $dockerVersion = Assert-ImageBuildDockerCli
    Write-Host "Done verifying docker CLI: $dockerVersion" -ForegroundColor Green
    Write-Output ""

    Invoke-ImageBuildBatch `
        -RepositoryRoot $repositoryRoot `
        -ImageBuilds $imageBuilds `
        -DotNetToolsContext $dotnetToolsContext `
        -NoCache $NoCache

    Write-ImageBuildSummary -ImageBuilds $imageBuilds
}
catch {

    Write-ImageBuildError -ErrorRecord $_ -WaitOnExit:$WaitOnExit
    EXIT 1
}

Write-ImageBuildSuccess -WaitOnExit:$WaitOnExit
