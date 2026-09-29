#!/usr/bin/env pwsh
#Requires -Version 7.2
<#
.SYNOPSIS
    Builds the Contoso .NET 10 production Docker base images for Alpine.

.DESCRIPTION
    Top-down flow when this script runs:

        1. Resolve the repository root next to this script.
        2. Load helper functions from .ps/Core and .ps/ImageBuild/Core.
        3. When dockerfiles/.dotnet-tools is missing or empty, invoke
           .ps/Diagnostics-Tools-Build/DotNet-Tools.ps1 before the tools
           image. That script writes dockerfiles/.build and
           dockerfiles/.dotnet-tools. -WaitOnExit is not forwarded.
           An existing folder is reused.
        4. Verify that the docker CLI is available.
        5. Build Alpine images tagged :latest. Both images run unless
           -ToolsOnly is set, in which case only the diagnostics-tools
           image (target: final) is built:
             a. final with --build-context dotnet-tools=dockerfiles/.dotnet-tools
             b. aspnet-base without the dotnet-tools build context
        6. Compose docker buildx build arguments per image.
        7. Invoke docker from the repository root and stream the output.

    Images produced for -DotNetVersion 10 (the default):

        - contoso/alpine-net-dotnet-tools-10:latest    (target: final)
        - contoso/alpine-net-10:latest                 (target: aspnet-base)

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
    Builds only the diagnostics-tools image (target: final). Skips the lean
    aspnet-base image. Omit it to build both images.

.PARAMETER WaitOnExit
    When set, waits for Enter after success or failure so a double-clicked
    console window stays open. Omit it in a terminal or CI run. Defaults to off.

.INPUTS
    None. Pass -DotNetVersion to select a folder other than dockerfiles/alpine/10.

.OUTPUTS
    Host messages and docker CLI output. Exit code 0 on success.

.NOTES
    Requires PowerShell 7.2+, a working Docker installation with buildx, and
    network access to NuGet when dockerfiles/.dotnet-tools is missing. This
    script then runs .ps/Diagnostics-Tools-Build/DotNet-Tools.ps1, which
    writes dockerfiles/.build and dockerfiles/.dotnet-tools. An existing
    tools folder is reused. The lean aspnet-base image does not need it.

.EXAMPLE
    PS> ./Image-Build-Alpine.ps1
    Publishes dockerfiles/.dotnet-tools when that folder is missing, then
    builds contoso/alpine-net-dotnet-tools-10:latest and contoso/alpine-net-10:latest.

.EXAMPLE
    PS> ./Image-Build-Alpine.ps1 -DotNetVersion 10
    Builds the Alpine images under dockerfiles/alpine/10.

.EXAMPLE
    PS> ./Image-Build-Alpine.ps1 -NoCache:$false
    Builds both Alpine images with BuildKit cache enabled.

.EXAMPLE
    PS> ./Image-Build-Alpine.ps1 -ToolsOnly
    Builds only contoso/alpine-net-dotnet-tools-10:latest.

.EXAMPLE
    PS> ./Image-Build-Alpine.ps1 -WaitOnExit
    Builds both Alpine images and waits for Enter before the window closes.
#>

[CmdletBinding()]
Param (
    [Parameter(Mandatory = $false, HelpMessage = 'The .NET major version used in the Dockerfile folder and image tags. Defaults to 10.')]
    [ValidateNotNullOrEmpty()]
    [string]$DotNetVersion = '10',

    [Parameter(Mandatory = $false, HelpMessage = 'Pass --no-cache to docker buildx build. Defaults to $false.')]
    [bool]$NoCache = $false,

    [Parameter(Mandatory = $false, HelpMessage = 'Build only the diagnostics-tools image (target: final) and skip the lean base image.')]
    [switch]$ToolsOnly,

    [Parameter(Mandatory = $false, HelpMessage = 'Wait for Enter after success or failure so a double-clicked console window stays open. Omit it in a terminal or CI run.')]
    [switch]$WaitOnExit
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true


$scriptRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptRoot)) {
    $scriptRoot = (Get-Location).Path
}

$modulePath = Join-Path $scriptRoot '.ps' 'ImageBuild'
if (-not (Test-Path -LiteralPath $modulePath -PathType Container)) {
    throw "Required helper folder not found: '$modulePath'."
}

. (Join-Path $modulePath '../Core/Write-ScriptError.ps1')
. (Join-Path $modulePath '../Core/Write-ScriptSuccess.ps1')

try {

    $repositoryRoot = [System.IO.Path]::GetFullPath($scriptRoot)

    Write-Output "Loading module files:"

    $moduleFiles = @(
        '../Core/Assert-Cli.ps1'
        '../Core/Assert-LastExitCode.ps1'
        '../Core/Write-Section.ps1'
        'Core/Invoke-DockerImageBuild.ps1'
        'Core/Invoke-ImageBuildBatch.ps1'
        'Core/Write-ImageBuildSettings.ps1'
        'Core/Write-ImageBuildSummary.ps1'
        'Core/Invoke-ImageBuildScript.ps1'
        'Core/Get-ImageBuildDefinitions.ps1'
        'Core/Initialize-ImageBuildToolsContext.ps1'
        'Core/Invoke-ImageBuildForDistro.ps1'
    )

    foreach ($relativePath in $moduleFiles) {
        $moduleFile = [System.IO.Path]::GetFullPath((Join-Path $modulePath $relativePath))
        Write-Output "  $moduleFile"
        . $moduleFile
    }

    Write-Host "Done loading module files." -ForegroundColor Green

    Invoke-ImageBuildForDistro `
        -RepositoryRoot $repositoryRoot `
        -DistroLabel 'alpine' `
        -DotNetVersion $DotNetVersion `
        -BaseTarget 'aspnet-base' `
        -NoCache $NoCache `
        -ToolsOnly:$ToolsOnly
}
catch {

    Write-ScriptError -ErrorRecord $_ -WaitOnExit:$WaitOnExit
    EXIT 1
}

Write-ScriptSuccess -WaitOnExit:$WaitOnExit
