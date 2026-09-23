function Write-ImageBuildSummary () {
    <#
    .SYNOPSIS
        Prints the cyan "Built N image(s)" summary shown at the end of each run.
    .DESCRIPTION
        Called from the entry script once every build in ImageBuilds completes.
    .REMARKS
        1. Print the total count.
        2. Print each tag on its own line.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [object[]]$ImageBuilds
    )

    Process {

        Write-Host "Built $($ImageBuilds.Count) image(s):" -ForegroundColor Cyan
        foreach ($imageBuild in $ImageBuilds) {
            Write-Host "  $($imageBuild.Tag)" -ForegroundColor Cyan
        }
    }
}
