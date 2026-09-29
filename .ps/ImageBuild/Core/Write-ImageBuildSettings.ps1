function Write-ImageBuildSettings () {
    <#
    .SYNOPSIS
        Prints the settings banner used by every Image-Build-*.ps1 entry script.
    .DESCRIPTION
        Prints repository root, distro label, cache flag, dotnet-tools
        context path, and the list of image builds that will run.
    .NOTE
        1. Print a labelled header block.
        2. List each build's tag and buildx target.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, HelpMessage = 'Repository root shown in the settings block.')]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true, HelpMessage = 'Distro label shown in the settings block.')]
        [ValidateNotNullOrEmpty()]
        [string]$Distro,

        [Parameter(Mandatory = $true, HelpMessage = 'Whether --no-cache is passed to docker buildx build.')]
        [bool]$NoCache,

        [Parameter(Mandatory = $true, HelpMessage = 'Repository-relative dotnet-tools build context shown in the settings block.')]
        [ValidateNotNullOrEmpty()]
        [string]$DotNetToolsContext,

        [Parameter(Mandatory = $true, HelpMessage = 'The image-build definitions listed in the settings block.')]
        [ValidateNotNull()]
        [object[]]$ImageBuilds
    )

    Begin {
        Write-Verbose ("BEGIN: {0}" -f $MyInvocation.MyCommand.Name)
        Write-Verbose ($PSBoundParameters | Out-String)
    }

    Process {

        Write-Output ""
        Write-Output "--------------------------- BEGIN: Settings ---------------------------"
        Write-Output ""
        Write-Output "Repository root    : $RepositoryRoot"
        Write-Output "Distro             : $Distro"
        Write-Output "No cache           : $NoCache"
        Write-Output "dotnet-tools ctx   : $DotNetToolsContext"
        Write-Output "Image builds       : $($ImageBuilds.Count)"
        foreach ($imageBuild in $ImageBuilds) {
            Write-Output "  - $($imageBuild.Tag)  (target: $($imageBuild.BuildTarget))"
        }
        Write-Output ""
        Write-Output "---------------------------- END: Settings ----------------------------"
        Write-Output ""
    }
}
