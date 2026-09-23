<#
.SYNOPSIS
    Build script for the solution using dotnet CLI, then the three test-app images.
.DESCRIPTION
    Builds the solution by using dotnet restore + dotnet build, copies artifacts
    to tests\.build, builds the three test-app Docker images, and starts each
    container detached.

    Steps performed:
      1. Kill any running VBCSCompiler and MSBuild processes to release file locks
      2. Verify dotnet CLI is available in PATH
      3. Resolve solution file: use -solutionFileName if provided, otherwise scan
            tests\DotNet-Tools-TestApp for the first *.slnx file found; throw if none exists
      4. Set build property EnableLocalDevelopment=true
      5. Run dotnet restore against the solution for linux-x64 only
      6. Run dotnet build for linux-x64 in selected configuration / x64 / minimal verbosity
      7. Copy linux-x64 artifacts to tests\.build (keeps .gitignore, .dockerignore, and .DotNet-Tools-Commands.txt)
      8. Build the three test-app images (alpine / ubuntu / ubuntu-chiseled)
      9. Run each test-app container detached (replaces any prior container of the same name)
     10. Report total elapsed build time
     11. On any error: print exception details and exit with code 1.
         When -WaitOnExit is set, pause for Enter before exit.

    Images / containers for -DotNetVersion 10 (the default):

        - contoso/alpine-net-dotnet-tools-testapp-10:latest
            container: dotnet-tools-testapp-alpine-10
        - contoso/ubuntu-net-dotnet-tools-testapp-10:latest
            container: dotnet-tools-testapp-ubuntu-10
        - contoso/ubuntu-chiseled-net-dotnet-tools-testapp-10:latest
            container: dotnet-tools-testapp-ubuntu-chiseled-10

    Requires the matching diagnostics-tools base images already built
    (e.g. via .\Image-TestBuild-DotNet-Tools-TestApp.ps1 or Image-Build-*-ToolsOnly).

.PARAMETER solutionFileName
    Optional solution file name to build. When omitted the script scans
    tests\DotNet-Tools-TestApp for the first *.slnx file it finds and uses that
    automatically.
.PARAMETER buildConfiguration
    Build configuration for dotnet build (Debug, Release, or custom). Defaults to Debug.
.PARAMETER DotNetVersion
    .NET major version used in image tags and Dockerfile build-arg. Defaults to 10.
.PARAMETER NoCache
    Passes --no-cache to docker buildx build. Defaults to $true. Use
    -NoCache:$false to allow the BuildKit cache.
.PARAMETER WaitOnExit
    When set, clears the console at start and waits for Enter after success
    or failure so a double-clicked console window stays open. Omit it when
    this script is called from .\Image-TestBuild-DotNet-Tools-TestApp.ps1 or from a terminal.
.EXAMPLE
    .\.ps\TestApp\Build-DotNet-Tools-TestApp.ps1
    .\.ps\TestApp\Build-DotNet-Tools-TestApp.ps1 -buildConfiguration "Debug"
    .\.ps\TestApp\Build-DotNet-Tools-TestApp.ps1 -solutionFileName "MyOther.slnx" -buildConfiguration "Release"
    .\.ps\TestApp\Build-DotNet-Tools-TestApp.ps1 -DotNetVersion 10 -NoCache:$false
    .\.ps\TestApp\Build-DotNet-Tools-TestApp.ps1 -WaitOnExit
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Solution file name (optional - auto-detected when omitted)")]
    [string]$solutionFileName = "",

    [Parameter(Mandatory = $false, HelpMessage = "Build configuration (Debug, Release, or custom)")]
    [ValidateNotNullOrEmpty()]
    [string]$buildConfiguration = "Debug",

    [Parameter(Mandatory = $false, HelpMessage = ".NET major version for image tags")]
    [ValidateNotNullOrEmpty()]
    [string]$DotNetVersion = "10",

    [Parameter(Mandatory = $false, HelpMessage = "Pass --no-cache to docker buildx build")]
    [bool]$NoCache = $true,

    [Parameter(Mandatory = $false, HelpMessage = "Wait for Enter before the window closes")]
    [switch]$WaitOnExit
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

<#
    .DESCRIPTION
        Returns the solution file name to build.
        Uses the supplied name when provided; otherwise scans $searchDirectory for
        the first *.slnx file and returns its name. Throws if none is found.
#>
function Resolve-SolutionFileName {

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true, HelpMessage = "Directory to scan for a *.slnx file")]
        [ValidateNotNullOrEmpty()]
        [string]$searchDirectory
    )

    Begin {

        Write-Host ""
        Write-Host "--------------------------------- BEGIN: Resolve-SolutionFileName ---------------------------------------------" -ForegroundColor "Yellow"
        Write-Host ""

        $PSBoundParameters | Out-String | Write-Host
    }

    Process {
        $found = [System.IO.Directory]::GetFiles($searchDirectory, "*.slnx") | Select-Object -First 1

        if ($null -eq $found) {
            throw "No *.slnx file found in '$searchDirectory'. Supply -solutionFileName explicitly."
        }

        [string]$fileName = [System.IO.Path]::GetFileName($found)

        Write-Host "Solution file (auto-detected):"
        Write-Host "    $fileName" -ForegroundColor "Green"

        return $fileName
    }

    End {

        Write-Host ""
        Write-Host "--------------------------------- END: Resolve-SolutionFileName ---------------------------------------------" -ForegroundColor "Yellow"
        Write-Host ""
    }
}

<#
    .DESCRIPTION
        Restores and builds a solution by using dotnet CLI.
#>
function TaskCompileVSSolution {

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true, HelpMessage = "The solution root directory")]
        [ValidateNotNullOrEmpty()]
        [string]$workingDirectory,

        [Parameter(Mandatory = $true, HelpMessage = "MSBuild property flag, e.g. /p:EnableLocalDevelopment=true")]
        [ValidateNotNullOrEmpty()]
        [string]$enableLocalDevelopment,

        [Parameter(Mandatory = $true, HelpMessage = "Solution file name to build")]
        [ValidateNotNullOrEmpty()]
        [string]$resolvedSolutionFileName,

        [Parameter(Mandatory = $true, HelpMessage = "Build configuration name")]
        [ValidateNotNullOrEmpty()]
        [string]$configuration,

        [Parameter(Mandatory = $true, HelpMessage = "Runtime identifier (linux-x64 only)")]
        [ValidateSet("linux-x64")]
        [string]$runtimeIdentifier
    )

    Begin {

        Write-Host ""
        Write-Host "--------------------------------- BEGIN: TaskCompileVSSolution ---------------------------------------------" -ForegroundColor "Yellow"
        Write-Host ""

        $PSBoundParameters | Out-String | Write-Host
    }

    Process {

        [string]$solutionFile = Join-Path $workingDirectory $resolvedSolutionFileName

        [string[]]$restoreArgs = @(
            "restore"
            $solutionFile
            "--runtime"
            $runtimeIdentifier
            "--verbosity"
            "quiet"
            "--nologo"
        )

        [string[]]$buildArgs = @(
            "build"
            $solutionFile
            "-t:Rebuild"
            "--configuration"
            $configuration
            "--runtime"
            $runtimeIdentifier
            "--verbosity"
            "minimal"
            "--nologo"
            "/p:Platform=x64"
            "/p:RuntimeIdentifier=$runtimeIdentifier"
            $enableLocalDevelopment
        )

        Write-Host ""
        Write-Host "--------------------------------- BEGIN: Settings ---------------------------------------------" -ForegroundColor "Yellow"
        Write-Host ""
        Write-Host "Working Directory:"
        Write-Host "    $workingDirectory" -ForegroundColor "Green"
        Write-Host "Solution File:"
        Write-Host "    $solutionFile" -ForegroundColor "Green"
        Write-Host "Build Configuration:"
        Write-Host "    $configuration" -ForegroundColor "Green"
        Write-Host "Runtime Identifier:"
        Write-Host "    $runtimeIdentifier" -ForegroundColor "Green"
        Write-Host "Restore:"
        Write-Host "    dotnet $($restoreArgs -join ' ')" -ForegroundColor "Green"
        Write-Host "Build Args:"
        Write-Host "    $($buildArgs -join ' ')" -ForegroundColor "Green"
        Write-Host ""
        Write-Host "--------------------------------- END: Settings ---------------------------------------------" -ForegroundColor "Yellow"
        Write-Host ""

        Write-Host ""
        Write-Host "--------------------------------- BEGIN: dotnet restore ---------------------------------------------" -ForegroundColor "Yellow"
        Write-Host ""
        Push-Location -Path $workingDirectory
        try {
            Write-Host "dotnet restore CMD:"
            Write-Host "    dotnet $($restoreArgs -join ' ')" -ForegroundColor "Green"
            & dotnet @restoreArgs
            if ($LASTEXITCODE -ne 0) {
                throw "dotnet restore failed with exit code $LASTEXITCODE."
            }
        }
        finally {
            Pop-Location
        }
        Write-Host ""
        Write-Host "--------------------------------- END: dotnet restore ---------------------------------------------" -ForegroundColor "Yellow"

        Write-Host ""
        Write-Host "--------------------------------- BEGIN: dotnet build ---------------------------------------------" -ForegroundColor "Yellow"
        Write-Host ""
        [string]$buildCommandText = "dotnet " + ($buildArgs -join " ")
        Write-Host "dotnet build CMD:"
        Write-Host "    $buildCommandText" -ForegroundColor "Green"
        Write-Host ""
        Push-Location -Path $workingDirectory
        try {
            & dotnet @buildArgs
            if ($LASTEXITCODE -ne 0) {
                throw "dotnet build failed with exit code $LASTEXITCODE. Command: $buildCommandText"
            }
        }
        finally {
            Pop-Location
        }
        Write-Host ""
        Write-Host "--------------------------------- END: dotnet build ---------------------------------------------" -ForegroundColor "Yellow"
        Write-Host ""
    }

    End {

        Write-Host ""
        Write-Host "--------------------------------- END: TaskCompileVSSolution ---------------------------------------------" -ForegroundColor "Yellow"
        Write-Host ""
    }
}

<#
    .DESCRIPTION
        Kill all processes with a supplied name.
#>
function Stop-UdfProcesses {

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true, HelpMessage = "The process name")]
        [ValidateNotNullOrEmpty()]
        [string]$processName
    )

    Begin {

        Write-Host ""
        Write-Host "--------------------------------- BEGIN: Stop-UdfProcesses ---------------------------------------------" -ForegroundColor "Yellow"
        Write-Host ""

        $PSBoundParameters | Out-String | Write-Host
    }

    Process {

        $process = Get-Process $processName -ErrorAction SilentlyContinue

        if ($null -eq $process) {

            Write-Host "No process is running with name:"
            Write-Host "    $processName"
            return
        }

        while ($process) {

            Write-Host "Killing process:" -ForegroundColor "Yellow"
            Write-Host "    $processName" -ForegroundColor "Yellow"

            $process | Stop-Process -Force -ErrorAction SilentlyContinue
            $process = Get-Process $processName -ErrorAction SilentlyContinue
        }
    }

    End {

        Write-Host ""
        Write-Host "--------------------------------- END: Stop-UdfProcesses ---------------------------------------------" -ForegroundColor "Yellow"
        Write-Host ""
    }
}

<#
    .DESCRIPTION
        Copies linux-x64 build output from the project bin folder into tests\.build.
#>
function Copy-BuildArtifacts {

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true, HelpMessage = "The solution root directory")]
        [ValidateNotNullOrEmpty()]
        [string]$workingDirectory,

        [Parameter(Mandatory = $true, HelpMessage = "Build configuration name")]
        [ValidateNotNullOrEmpty()]
        [string]$configuration,

        [Parameter(Mandatory = $true, HelpMessage = "Runtime identifier (linux-x64 only)")]
        [ValidateSet("linux-x64")]
        [string]$runtimeIdentifier,

        [Parameter(Mandatory = $true, HelpMessage = "Destination folder for copied artifacts")]
        [ValidateNotNullOrEmpty()]
        [string]$destinationDirectory
    )

    Begin {

        Write-Host ""
        Write-Host "--------------------------------- BEGIN: Copy-BuildArtifacts ---------------------------------------------" -ForegroundColor "Yellow"
        Write-Host ""

        $PSBoundParameters | Out-String | Write-Host
    }

    Process {

        [string]$sourceDirectory = Join-Path $workingDirectory "bin\x64\$configuration\net10.0\$runtimeIdentifier"

        Write-Host "Source:"
        Write-Host "    $sourceDirectory" -ForegroundColor "Green"
        Write-Host "Destination:"
        Write-Host "    $destinationDirectory" -ForegroundColor "Green"
        Write-Host ""

        if (-not (Test-Path -LiteralPath $sourceDirectory -PathType Container)) {
            throw "Build output folder not found: '$sourceDirectory'"
        }

        if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) {
            New-Item -Path $destinationDirectory -ItemType Directory -Force | Out-Null
        }

        Write-Host "Clearing destination (keeping .gitignore, .dockerignore, and .DotNet-Tools-Commands.txt):"
        Write-Host "    $destinationDirectory" -ForegroundColor "Yellow"
        Get-ChildItem -LiteralPath $destinationDirectory -Force |
            Where-Object { $_.Name -notin @('.gitignore', '.dockerignore', '.DotNet-Tools-Commands.txt') } |
            Remove-Item -Recurse -Force

        Copy-Item -Path (Join-Path $sourceDirectory "*") -Destination $destinationDirectory -Recurse -Force

        Write-Host "Copied artifacts to:"
        Write-Host "    $destinationDirectory" -ForegroundColor "Green"
    }

    End {

        Write-Host ""
        Write-Host "--------------------------------- END: Copy-BuildArtifacts ---------------------------------------------" -ForegroundColor "Yellow"
        Write-Host ""
    }
}

<#
    .DESCRIPTION
        Returns the three test-app image definitions (Dockerfile, tag, container name).
#>
function Get-TestAppImageBuilds {

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DotNetVersion
    )

    Process {

        return @(
            [pscustomobject]@{
                Distro        = 'alpine'
                Dockerfile    = 'tests/dockerfiles/alpine/Dockerfile'
                Tag           = "contoso/alpine-net-dotnet-tools-testapp-${DotNetVersion}:latest"
                ContainerName = "dotnet-tools-testapp-alpine-${DotNetVersion}"
            }
            [pscustomobject]@{
                Distro        = 'ubuntu'
                Dockerfile    = 'tests/dockerfiles/ubuntu/Dockerfile'
                Tag           = "contoso/ubuntu-net-dotnet-tools-testapp-${DotNetVersion}:latest"
                ContainerName = "dotnet-tools-testapp-ubuntu-${DotNetVersion}"
            }
            [pscustomobject]@{
                Distro        = 'ubuntu-chiseled'
                Dockerfile    = 'tests/dockerfiles/ubuntu-chiseled/Dockerfile'
                Tag           = "contoso/ubuntu-chiseled-net-dotnet-tools-testapp-${DotNetVersion}:latest"
                ContainerName = "dotnet-tools-testapp-ubuntu-chiseled-${DotNetVersion}"
            }
        )
    }
}

<#
    .DESCRIPTION
        Builds the three test-app Docker images from tests\.build onto the
        diagnostics-tools bases. Context is always tests/.build.
#>
function Build-TestAppDockerImages {

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [object[]]$ImageBuilds,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DotNetVersion,

        [Parameter(Mandatory = $true)]
        [bool]$NoCache
    )

    Begin {

        Write-Host ""
        Write-Host "--------------------------------- BEGIN: Build-TestAppDockerImages ---------------------------------------------" -ForegroundColor "Yellow"
        Write-Host ""

        $PSBoundParameters | Out-String | Write-Host
    }

    Process {

        if ($null -eq (Get-Command docker -ErrorAction SilentlyContinue)) {
            throw "Required: Install Docker Engine with BuildKit and ensure 'docker' is available in PATH."
        }

        foreach ($imageBuild in $ImageBuilds) {
            $dockerfileFull = Join-Path $RepositoryRoot $imageBuild.Dockerfile
            if (-not (Test-Path -LiteralPath $dockerfileFull -PathType Leaf)) {
                throw "Required test-app Dockerfile was not found: '$dockerfileFull'."
            }
        }

        $buildContextFull = Join-Path $RepositoryRoot 'tests\.build'
        if (-not (Test-Path -LiteralPath $buildContextFull -PathType Container)) {
            throw "Required test-app build context folder was not found: '$buildContextFull'."
        }

        $apphostPath = Join-Path $buildContextFull 'DotNet-Tools-TestApp'
        if (-not (Test-Path -LiteralPath $apphostPath -PathType Leaf)) {
            throw "Test-app apphost was not found: '$apphostPath'."
        }

        Push-Location -LiteralPath $RepositoryRoot
        try {
            foreach ($imageBuild in $ImageBuilds) {
                Write-Host ""
                Write-Host "Building $($imageBuild.Tag):" -ForegroundColor "Green"

                $arguments = [System.Collections.Generic.List[string]]::new()
                $arguments.Add('buildx')
                $arguments.Add('build')
                if ($NoCache) {
                    $arguments.Add('--no-cache')
                }
                $arguments.Add('--progress=plain')
                $arguments.Add('-f')
                $arguments.Add($imageBuild.Dockerfile)
                $arguments.Add('--build-arg')
                $arguments.Add("DOTNET_VERSION=$DotNetVersion")
                $arguments.Add('-t')
                $arguments.Add($imageBuild.Tag)
                $arguments.Add('tests/.build')

                Write-Host "docker $($arguments -join ' ')" -ForegroundColor "Green"
                & docker @arguments
                if ($LASTEXITCODE -ne 0) {
                    throw "docker build for $($imageBuild.Tag) failed with exit code $LASTEXITCODE."
                }

                Write-Host "Done building $($imageBuild.Tag)." -ForegroundColor "Green"
            }
        }
        finally {
            Pop-Location
        }
    }

    End {

        Write-Host ""
        Write-Host "--------------------------------- END: Build-TestAppDockerImages ---------------------------------------------" -ForegroundColor "Yellow"
        Write-Host ""
    }
}

<#
    .DESCRIPTION
        Starts each test-app image detached. Removes any prior container with
        the same name so re-runs are idempotent.
#>
function Start-TestAppContainersDetached {

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [object[]]$ImageBuilds
    )

    Begin {

        Write-Host ""
        Write-Host "--------------------------------- BEGIN: Start-TestAppContainersDetached ---------------------------------------------" -ForegroundColor "Yellow"
        Write-Host ""

        $PSBoundParameters | Out-String | Write-Host
    }

    Process {

        foreach ($imageBuild in $ImageBuilds) {
            Write-Host ""
            Write-Host "Starting container $($imageBuild.ContainerName) from $($imageBuild.Tag):" -ForegroundColor "Green"

            $previousNativePreference = $PSNativeCommandUseErrorActionPreference
            $PSNativeCommandUseErrorActionPreference = $false
            try {
                $null = & docker container inspect $imageBuild.ContainerName 2>$null
                $containerExists = ($LASTEXITCODE -eq 0)
            }
            finally {
                $PSNativeCommandUseErrorActionPreference = $previousNativePreference
            }

            if ($containerExists) {
                Write-Host "Removing existing container:" -ForegroundColor "Yellow"
                Write-Host "    $($imageBuild.ContainerName)" -ForegroundColor "Yellow"
                & docker rm -f $imageBuild.ContainerName
                if ($LASTEXITCODE -ne 0) {
                    throw "docker rm -f $($imageBuild.ContainerName) failed with exit code $LASTEXITCODE."
                }
            }

            $runArgs = @(
                'run'
                '-d'
                '--name'
                $imageBuild.ContainerName
                $imageBuild.Tag
            )

            Write-Host "docker $($runArgs -join ' ')" -ForegroundColor "Green"
            $containerId = & docker @runArgs
            if ($LASTEXITCODE -ne 0) {
                throw "docker run -d for $($imageBuild.Tag) failed with exit code $LASTEXITCODE."
            }

            Write-Host "Started:" -ForegroundColor "Green"
            Write-Host "    name=$($imageBuild.ContainerName)" -ForegroundColor "Green"
            Write-Host "    id=$($containerId.ToString().Trim())" -ForegroundColor "Green"
        }

        Write-Host ""
        Write-Host "Detached containers:" -ForegroundColor "Green"
        & docker ps --filter "name=dotnet-tools-testapp-" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.ID}}"
    }

    End {

        Write-Host ""
        Write-Host "--------------------------------- END: Start-TestAppContainersDetached ---------------------------------------------" -ForegroundColor "Yellow"
        Write-Host ""
    }
}

try {

    if ($WaitOnExit) {
        Clear-Host
    }

    Stop-UdfProcesses -processName "VBCSCompiler"
    
    Stop-UdfProcesses -processName "MSBuild"

    if ($null -eq (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        throw "Required: Install .NET SDK and ensure 'dotnet' is available in PATH. https://dotnet.microsoft.com/download"
    }

    [string]$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
    [string]$testsRoot = Join-Path $repositoryRoot 'tests'
    [string]$rootFolder = (Join-Path $testsRoot "DotNet-Tools-TestApp") + "\"

    if (-not (Test-Path -LiteralPath $rootFolder -PathType Container)) {
        throw "Solution folder not found: '$rootFolder'"
    }

    [string]$resolvedSolutionFileName = $solutionFileName
    if ([string]::IsNullOrWhiteSpace($resolvedSolutionFileName)) {
        $resolvedSolutionFileName = Resolve-SolutionFileName -searchDirectory $rootFolder
    }

    Write-Host ""
    Write-Host "--------------------------------- BEGIN: Settings ---------------------------------------------" -ForegroundColor "Yellow"
    Write-Host ""
    Write-Host "The script folder:"
    Write-Host "  $PSScriptRoot\" -ForegroundColor "Green"
    Write-Host "The tests folder:"
    Write-Host "  $testsRoot\" -ForegroundColor "Green"
    Write-Host "The solution folder:"
    Write-Host "  $rootFolder" -ForegroundColor "Green"
    Write-Host ""
    Write-Host "--------------------------------- END: Settings ---------------------------------------------" -ForegroundColor "Yellow"
    Write-Host ""

    [string]$enableLocalDevelopment = "/p:EnableLocalDevelopment=true"

    [System.Diagnostics.Stopwatch]$stopwatch = New-Object System.Diagnostics.Stopwatch
    $stopwatch.Start()

    [string]$runtimeIdentifier = "linux-x64"

    Write-Host "Setting build options:"
    Write-Host "    BuildConfiguration=$buildConfiguration" -ForegroundColor "Green"
    Write-Host "    RuntimeIdentifier=$runtimeIdentifier" -ForegroundColor "Green"
    Write-Host "    $enableLocalDevelopment" -ForegroundColor "Green"

    TaskCompileVSSolution `
        -workingDirectory $rootFolder `
        -enableLocalDevelopment $enableLocalDevelopment `
        -resolvedSolutionFileName $resolvedSolutionFileName `
        -configuration $buildConfiguration `
        -runtimeIdentifier $runtimeIdentifier

    [string]$artifactDestination = Join-Path $testsRoot ".build"
    Copy-BuildArtifacts `
        -workingDirectory $rootFolder `
        -configuration $buildConfiguration `
        -runtimeIdentifier $runtimeIdentifier `
        -destinationDirectory $artifactDestination

    $testAppImageBuilds = Get-TestAppImageBuilds -DotNetVersion $DotNetVersion

    Build-TestAppDockerImages `
        -RepositoryRoot $repositoryRoot `
        -ImageBuilds $testAppImageBuilds `
        -DotNetVersion $DotNetVersion `
        -NoCache $NoCache

    Start-TestAppContainersDetached -ImageBuilds $testAppImageBuilds

    $stopwatch.Stop()
    [string]$timeElapsed = $stopwatch.Elapsed

    Write-Host "Time elapsed:"
    Write-Host "    $timeElapsed" -ForegroundColor "Green"
}
catch {

    Write-Error "" -ErrorAction Continue
    Write-Error "Caught an exception:" -ErrorAction Continue
    Write-Error "Exception Type: $($_.Exception.GetType().FullName)" -ErrorAction Continue
    Write-Error "Exception Message: $($_.Exception.Message)" -ErrorAction Continue
    Write-Error "" -ErrorAction Continue

    Write-Host "Script failed to execute." -ForegroundColor "Red"

    if ($WaitOnExit) {
        Read-Host "Press Enter to close the window ..."
    }

    exit 1
}

Write-Host ""
Write-Host "Script executed successfully." -ForegroundColor "Green"

if ($WaitOnExit) {
    Read-Host "Press Enter to close the window ..."
}

