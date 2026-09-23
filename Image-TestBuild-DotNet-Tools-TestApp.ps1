#!/usr/bin/env pwsh
#Requires -Version 7.2
<#
.SYNOPSIS
    Builds the three diagnostics-tools Docker images, then the linux-x64 test
    app, its three images, and starts those containers detached.

.DESCRIPTION
    Top-down flow when this script runs:

        1. Resolve the repository root next to this script, then the tests
           folder under it.
        2. Dot-source Write-ImageBuildError and Write-ImageBuildSuccess from
           .ps\ImageBuild\Core so failure and success paths mirror the
           per-distro scripts.
        3. Validate that the three per-distro scripts and the test-app
           build script exist.
        4. Write tests\.build\.DotNet-Tools-Commands.txt (created before
           any docker build).
        5. Invoke Image-Build-Alpine.ps1          -ToolsOnly.
        6. Invoke Image-Build-Ubuntu.ps1          -ToolsOnly.
        7. Invoke Image-Build-Ubuntu-Chiseled.ps1 -ToolsOnly.
        8. Invoke .ps\TestApp\Build-DotNet-Tools-TestApp.ps1, which:
             - restores/builds DotNet-Tools-TestApp for linux-x64
             - copies artifacts to tests\.build
             - builds the three test-app images
             - starts each container detached

    Each per-distro script builds only its diagnostics-tools image tagged
    :latest (target: final). The lean aspnet-base and runtime-base images
    are skipped. -NoCache is forwarded. -WaitOnExit is not: this script is
    meant for a terminal or CI run.

    A failure in any sub-script is caught by the outer try/catch, routed
    through Write-ImageBuildError, and the run exits with code 1
    ($ErrorActionPreference = 'Stop'). On success Write-ImageBuildSuccess
    prints the green completion banner.

    Images produced for -DotNetVersion 10 (the default):

        - contoso/alpine-net-dotnet-tools-10:latest
        - contoso/ubuntu-net-dotnet-tools-10:latest
        - contoso/ubuntu-chiseled-net-dotnet-tools-10:latest
        - contoso/alpine-net-dotnet-tools-testapp-10:latest
        - contoso/ubuntu-net-dotnet-tools-testapp-10:latest
        - contoso/ubuntu-chiseled-net-dotnet-tools-testapp-10:latest

    Detached containers (from the test-app script):

        - dotnet-tools-testapp-alpine-10
        - dotnet-tools-testapp-ubuntu-10
        - dotnet-tools-testapp-ubuntu-chiseled-10

.PARAMETER DotNetVersion
    Forwarded verbatim to each per-distro script and to the test-app script.
    .NET major version used in the Dockerfile folder and image tags.
    Defaults to 10.

.PARAMETER NoCache
    Forwarded verbatim to each per-distro script and to the test-app script.
    Defaults to $true to match the Copy-and-Paste examples in each
    Dockerfile. Use `-NoCache:$false` to allow the BuildKit cache.

.PARAMETER BuildConfiguration
    Forwarded to .ps\TestApp\Build-DotNet-Tools-TestApp.ps1 as
    -buildConfiguration. Defaults to Debug.

.INPUTS
    None. Sub-scripts are fixed in this script.

.OUTPUTS
    Host messages, docker CLI output, and dotnet CLI output. Exit code 0 on
    success; exit code 1 if any sub-script fails.

.NOTES
    Requires PowerShell 7.2+, a working Docker installation with buildx, and
    the .NET SDK. The tools images require the dockerfiles/.dotnet-tools
    folder produced by .ps\Diagnostics-Tools-Build\DotNet-Tools.ps1.

.EXAMPLE
    PS> .\Image-TestBuild-DotNet-Tools-TestApp.ps1
    Builds the three diagnostics-tools images, the Debug linux-x64 test app,
    the three test-app images, and starts those containers detached.

.EXAMPLE
    PS> .\Image-TestBuild-DotNet-Tools-TestApp.ps1 -NoCache:$false
    Builds while allowing the BuildKit cache, then the test app, images,
    and detached containers.

.EXAMPLE
    PS> .\Image-TestBuild-DotNet-Tools-TestApp.ps1 -BuildConfiguration Release
    Builds the diagnostics-tools images, then the test app in Release,
    images, and detached containers.

.EXAMPLE
    PS> .\Image-TestBuild-DotNet-Tools-TestApp.ps1 -DotNetVersion 10
    Builds the .NET 10 diagnostics-tools and test-app images, then starts
    the containers detached.
#>

[CmdletBinding()]
Param (
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$DotNetVersion = '10',

    [Parameter(Mandatory = $false)]
    [bool]$NoCache = $true,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$BuildConfiguration = 'Debug'
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true


$scriptRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptRoot)) {
    $scriptRoot = (Get-Location).Path
}

$repositoryRoot = [System.IO.Path]::GetFullPath($scriptRoot)
$testsRoot = Join-Path $repositoryRoot 'tests'

$modulePath = Join-Path $repositoryRoot '.ps\ImageBuild'
if (-not (Test-Path -LiteralPath $modulePath -PathType Container)) {
    throw "Required helper folder not found: '$modulePath'."
}

. (Join-Path $modulePath 'Core\Write-ImageBuildError.ps1')
. (Join-Path $modulePath 'Core\Write-ImageBuildSuccess.ps1')

try {

    $distroScripts = @(
        'Image-Build-Alpine.ps1'
        'Image-Build-Ubuntu.ps1'
        'Image-Build-Ubuntu-Chiseled.ps1'
    )

    $testAppScriptRelativePath = '.ps\TestApp\Build-DotNet-Tools-TestApp.ps1'

    foreach ($relativePath in $distroScripts) {
        $scriptPath = Join-Path $repositoryRoot $relativePath
        if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
            throw "Required per-distro script was not found: '$scriptPath'."
        }
    }

    $testAppScriptPath = Join-Path $repositoryRoot $testAppScriptRelativePath
    if (-not (Test-Path -LiteralPath $testAppScriptPath -PathType Leaf)) {
        throw "Required test-app build script was not found: '$testAppScriptPath'."
    }

    $buildDirectory = Join-Path $testsRoot '.build'
    if (-not (Test-Path -LiteralPath $buildDirectory -PathType Container)) {
        New-Item -Path $buildDirectory -ItemType Directory -Force | Out-Null
    }

    $commandsFilePath = Join-Path $buildDirectory '.DotNet-Tools-Commands.txt'
    Write-Host ""
    Write-Host "=============================================================" -ForegroundColor Cyan
    Write-Host "  Writing $commandsFilePath" -ForegroundColor Cyan
    Write-Host "=============================================================" -ForegroundColor Cyan

    $commandLines = @(
        '# dotnet-trace'
        'dotnet-trace collect -o ./app-data/trace.nettrace --process-id 1 --duration 00:00:15'
        'dotnet-trace collect -o ./app-data/trace-cpu.nettrace --process-id 1 --duration 00:00:15 --profile dotnet-sampled-thread-time'
        'dotnet-trace collect -o ./app-data/trace-gc.nettrace --process-id 1 --duration 00:00:15 --profile gc-verbose'
        'dotnet-trace convert ./app-data/trace.nettrace --format Speedscope -o ./app-data/trace.speedscope.json'
        'dotnet-trace report ./app-data/trace.nettrace topN -n 10'
        ''
        '# dotnet-gcdump'
        'dotnet-gcdump collect -o ./app-data/heap.gcdump --process-id 1'
        'dotnet-gcdump collect -o ./app-data/heap-verbose.gcdump --process-id 1 --verbose --timeout 60'
        'dotnet-gcdump report ./app-data/heap.gcdump'
        'dotnet-gcdump report --process-id 1'
        'dotnet-gcdump ps'
        ''
        '# dotnet-counters'
        'dotnet-counters collect -o ./app-data/counters.csv --format csv --process-id 1 --duration 00:00:15'
        'dotnet-counters collect -o ./app-data/counters.json --format json --process-id 1 --duration 00:00:15 System.Runtime'
        'dotnet-counters monitor --process-id 1 System.Runtime --refresh-interval 1 --duration 00:00:15'
        'dotnet-counters ps'
        ''
        '# dotnet-debug'
        'dotnet-debug attach 1 -c clrstack -c exit'
        'dotnet-debug attach 1 -c "dumpheap -stat" -c exit'
        'dotnet-debug attach 1 -c clrthreads -c exit'
        'dotnet-debug attach 1 -c threadpool -c exit'
        'dotnet-debug attach 1 -c gcheapstat -c exit'
    )
    Set-Content -LiteralPath $commandsFilePath -Value $commandLines -Encoding utf8
    Write-Host "Done writing $commandsFilePath" -ForegroundColor Green

    foreach ($relativePath in $distroScripts) {
        $scriptPath = Join-Path $repositoryRoot $relativePath
        Write-Host ""
        Write-Host "=============================================================" -ForegroundColor Cyan
        Write-Host "  Invoking $relativePath -ToolsOnly -DotNetVersion $DotNetVersion" -ForegroundColor Cyan
        Write-Host "=============================================================" -ForegroundColor Cyan

        & $scriptPath -DotNetVersion $DotNetVersion -NoCache $NoCache -ToolsOnly
        if ($LASTEXITCODE) {
            throw "$relativePath failed with exit code $LASTEXITCODE."
        }
    }

    Write-Host ""
    Write-Host "=============================================================" -ForegroundColor Cyan
    Write-Host "  Invoking $testAppScriptRelativePath (build app, images, run detached)" -ForegroundColor Cyan
    Write-Host "=============================================================" -ForegroundColor Cyan

    & $testAppScriptPath `
        -buildConfiguration $BuildConfiguration `
        -DotNetVersion $DotNetVersion `
        -NoCache $NoCache
    if ($LASTEXITCODE) {
        throw "$testAppScriptRelativePath failed with exit code $LASTEXITCODE."
    }
}
catch {

    Write-ImageBuildError -ErrorRecord $_
    EXIT 1
}

Write-ImageBuildSuccess
