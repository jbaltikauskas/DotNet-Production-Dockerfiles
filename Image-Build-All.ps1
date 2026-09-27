#!/usr/bin/env pwsh
#Requires -Version 7.2
<#
.SYNOPSIS
    Publishes the diagnostic NuGet tools, then builds every Contoso .NET 10
    production Docker base image by invoking the three per-distro entry scripts.

.DESCRIPTION
    Top-down flow when this script runs:

        1. Resolve the repository root next to this script.
        2. Dot-source Write-ImageBuildError and Write-ImageBuildSuccess from
           .ps\ImageBuild\Core so failure and success paths mirror the
           per-distro scripts.
        3. Validate that DotNet-Tools.ps1 and the three per-distro scripts exist.
        4. Invoke .ps\Diagnostics-Tools-Build\DotNet-Tools.ps1, which writes
           dockerfiles\.build and dockerfiles\.dotnet-tools.
        5. Invoke Image-Build-Alpine.ps1          (primary base).
        6. Invoke Image-Build-Ubuntu.ps1          (secondary base).
        7. Invoke Image-Build-Ubuntu-Chiseled.ps1 (last-resort distroless).

    Each per-distro script builds its dotnet-tools image tagged `:latest` and
    prints its own settings, docker version, build progress, and summary
    banners. This script orders that tools publish and the three image builds,
    and forwards -DotNetVersion and -NoCache. It does not pass -WaitOnExit.

    A failure in the tools script or any per-distro script is caught by the
    outer try/catch, routed through Write-ImageBuildError, and the run exits
    with code 1 ($ErrorActionPreference = 'Stop'). On success
    Write-ImageBuildSuccess prints the green completion banner.

    Images produced across the three sub-scripts for -DotNetVersion 10
    (the default):

        - contoso/alpine-net-dotnet-tools-10:latest            (target: final)
        - contoso/ubuntu-net-dotnet-tools-10:latest            (target: final)
        - contoso/ubuntu-chiseled-net-dotnet-tools-10:latest   (target: final)

.PARAMETER DotNetVersion
    Forwarded verbatim to each per-distro script. .NET major version used
    in the Dockerfile folder and image tags. Defaults to 10.

.PARAMETER NoCache
    Forwarded verbatim to each per-distro script, along with -DotNetVersion.
    Defaults to $true to match
    the Copy-and-Paste examples in each Dockerfile. Use `-NoCache:$false` to
    allow the BuildKit cache.

.INPUTS
    None. Sub-scripts are fixed in this script.

.OUTPUTS
    Host messages from the tools publish, and docker CLI output from each
    image script. Exit code 0 on success; exit code 1 if any sub-script fails.

.NOTES
    Requires PowerShell 7.2+, a working Docker installation with buildx, and
    network access to NuGet. This script runs
    .ps\Diagnostics-Tools-Build\DotNet-Tools.ps1, which downloads the
    diagnostic packages into dockerfiles\.build and publishes the merged
    Linux tree to dockerfiles\.dotnet-tools.

.EXAMPLE
    PS> .\Image-Build-All.ps1
    Publishes dockerfiles\.build and dockerfiles\.dotnet-tools, then builds
    every image in all three distros.

.EXAMPLE
    PS> .\Image-Build-All.ps1 -NoCache:$false
    Builds every image while allowing the BuildKit cache.

.EXAMPLE
    PS> .\Image-Build-All.ps1 -DotNetVersion 10
    Builds every image under the dockerfiles/<distro>/10 folders.
#>

[CmdletBinding()]
Param (
    [Parameter(Mandatory = $false, HelpMessage = 'The .NET major version used in the Dockerfile folder and image tags. Forwarded to each per-distro script. Defaults to 10.')]
    [ValidateNotNullOrEmpty()]
    [string]$DotNetVersion = '10',

    [Parameter(Mandatory = $false, HelpMessage = 'Pass --no-cache to docker buildx build. Forwarded to each per-distro script. Defaults to $false.')]
    [bool]$NoCache = $false
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
. (Join-Path $modulePath 'Core\Write-ImageBuildSection.ps1')
. (Join-Path $modulePath 'Core\Invoke-ImageBuildScript.ps1')

try {

    $repositoryRoot = [System.IO.Path]::GetFullPath($scriptRoot)

    $distroScripts = @(
        'Image-Build-Alpine.ps1'
        'Image-Build-Ubuntu.ps1'
        'Image-Build-Ubuntu-Chiseled.ps1'
    )

    Invoke-ImageBuildScript `
        -RepositoryRoot $repositoryRoot `
        -RelativePath '.ps\Diagnostics-Tools-Build\DotNet-Tools.ps1'

    foreach ($relativePath in $distroScripts) {
        Invoke-ImageBuildScript `
            -RepositoryRoot $repositoryRoot `
            -RelativePath $relativePath `
            -Arguments @{ DotNetVersion = $DotNetVersion; NoCache = $NoCache } `
            -BannerSuffix "-DotNetVersion $DotNetVersion"
    }
}
catch {

    Write-ImageBuildError -ErrorRecord $_
    EXIT 1
}

Write-ImageBuildSuccess
