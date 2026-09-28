function Invoke-ImageBuildBatch () {
    <#
    .SYNOPSIS
        Runs every image build in the supplied list.
    .DESCRIPTION
        Iterates ImageBuilds and calls Invoke-DockerImageBuild once per entry.
        Adds the shared dotnet-tools build context whenever the entry's
        IncludeTools property is $true.
    .NOTE
        1. For each build print a green start banner.
        2. Splat the entry's fields into Invoke-DockerImageBuild.
        3. Append DotNetToolsContext when IncludeTools is $true.
        4. Print a green completion banner.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, HelpMessage = 'Absolute path the docker builds run from.')]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true, HelpMessage = 'The image-build definitions to run, one docker build per entry.')]
        [ValidateNotNull()]
        [object[]]$ImageBuilds,

        [Parameter(Mandatory = $true, HelpMessage = 'Repository-relative dotnet-tools folder added as a build context when an entry sets IncludeTools.')]
        [ValidateNotNullOrEmpty()]
        [string]$DotNetToolsContext,

        [Parameter(Mandatory = $true, HelpMessage = 'Pass --no-cache to docker buildx build for every entry.')]
        [bool]$NoCache
    )

    Process {

        foreach ($imageBuild in $ImageBuilds) {
            Write-Host "Building $($imageBuild.Tag) (target: $($imageBuild.BuildTarget)):" -ForegroundColor Green

            $invokeParameters = @{
                RepositoryRoot = $RepositoryRoot
                Dockerfile     = $imageBuild.Dockerfile
                BuildContext   = $imageBuild.BuildContext
                BuildTarget    = $imageBuild.BuildTarget
                Tag            = $imageBuild.Tag
                BuildArgs      = $imageBuild.BuildArgs
                NoCache        = $NoCache
            }

            if ($imageBuild.IncludeTools) {
                $invokeParameters['DotNetToolsContext'] = $DotNetToolsContext
            }

            Invoke-DockerImageBuild @invokeParameters
            Write-Host "Done building $($imageBuild.Tag)." -ForegroundColor Green
            Write-Output ""
        }
    }
}
