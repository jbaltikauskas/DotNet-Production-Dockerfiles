function Invoke-DockerImageBuild () {
    <#
    .SYNOPSIS
        Runs a single `docker buildx build` invocation.
    .DESCRIPTION
        Composes the argument list for a lean or tools image and streams the
        docker output. The dotnet-tools build context is added only when
        supplied, so aspnet-base / runtime-base targets do not require the
        tools folder.
    .REMARKS
        1. Validate that the Dockerfile and build context exist.
        2. Compose docker buildx build arguments in the same order used by the
           Copy-and-Paste examples in each Dockerfile.
        3. When DotNetToolsContext is supplied, validate the folder and add it
           as --build-context dotnet-tools=<path>.
        4. Push into RepositoryRoot so relative paths resolve like the examples.
        5. Invoke docker and rely on $PSNativeCommandUseErrorActionPreference
           to throw on a non-zero exit code.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Dockerfile,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$BuildContext,

        [Parameter(Mandatory = $true)]
        [ValidateSet('aspnet-base', 'runtime-base', 'final')]
        [string]$BuildTarget,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Tag,

        [Parameter(Mandatory = $false)]
        [string]$DotNetToolsContext,

        [Parameter(Mandatory = $false)]
        [hashtable]$BuildArgs = @{},

        [Parameter(Mandatory = $false)]
        [bool]$NoCache = $true
    )

    Begin {
        $PSBoundParameters | Out-String | Write-Host
    }

    Process {

        $dockerfileFull = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot $Dockerfile))
        if (-not (Test-Path -LiteralPath $dockerfileFull -PathType Leaf)) {
            throw "Dockerfile was not found: '$dockerfileFull'."
        }

        $contextFull = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot $BuildContext))
        if (-not (Test-Path -LiteralPath $contextFull -PathType Container)) {
            throw "Build context folder was not found: '$contextFull'."
        }

        $arguments = [System.Collections.Generic.List[string]]::new()
        $arguments.Add('buildx')
        $arguments.Add('build')
        if ($NoCache) {
            $arguments.Add('--no-cache')
        }
        $arguments.Add('--progress=plain')
        $arguments.Add('-f')
        $arguments.Add($Dockerfile)
        $arguments.Add('--target')
        $arguments.Add($BuildTarget)

        foreach ($key in ($BuildArgs.Keys | Sort-Object)) {
            $arguments.Add('--build-arg')
            $arguments.Add("$key=$($BuildArgs[$key])")
        }

        if (-not [string]::IsNullOrWhiteSpace($DotNetToolsContext)) {
            $toolsContextFull = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot $DotNetToolsContext))
            if (-not (Test-Path -LiteralPath $toolsContextFull -PathType Container)) {
                throw "dotnet-tools build context folder was not found: '$toolsContextFull'. Run .ps\Diagnostics-Tools-Build\DotNet-Tools.ps1 first."
            }

            $arguments.Add('--build-context')
            $arguments.Add("dotnet-tools=$DotNetToolsContext")
        }

        $arguments.Add('-t')
        $arguments.Add($Tag)
        $arguments.Add($BuildContext)

        Write-Output "docker $($arguments -join ' ')"

        Push-Location -LiteralPath $RepositoryRoot
        try {
            & docker @arguments
        }
        finally {
            Pop-Location
        }
    }
}
