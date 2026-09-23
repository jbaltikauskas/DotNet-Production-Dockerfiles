function Invoke-ImageBuildBatch () {
    <#
    .SYNOPSIS
        Runs every image build in the supplied list.
    .DESCRIPTION
        Iterates ImageBuilds and calls Invoke-DockerImageBuild once per entry.
        Adds the shared dotnet-tools build context whenever the entry's
        IncludeTools property is $true.
    .REMARKS
        1. For each build print a green start banner.
        2. Splat the entry's fields into Invoke-DockerImageBuild.
        3. Append DotNetToolsContext when IncludeTools is $true.
        4. Print a green completion banner.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [object[]]$ImageBuilds,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DotNetToolsContext,

        [Parameter(Mandatory = $true)]
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
