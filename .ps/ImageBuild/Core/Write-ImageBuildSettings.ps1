function Write-ImageBuildSettings () {
    <#
    .SYNOPSIS
        Prints the settings banner used by every Image-Build-*.ps1 entry script.
    .DESCRIPTION
        Prints repository root, distro label, cache flag, dotnet-tools
        context path, and the list of image builds that will run.
    .REMARKS
        1. Print a labelled header block.
        2. List each build's tag and buildx target.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Distro,

        [Parameter(Mandatory = $true)]
        [bool]$NoCache,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DotNetToolsContext,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [object[]]$ImageBuilds
    )

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
