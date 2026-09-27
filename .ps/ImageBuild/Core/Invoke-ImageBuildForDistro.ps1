function Invoke-ImageBuildForDistro () {
    <#
    .SYNOPSIS
        Runs the full image-build flow for one distro.
    .DESCRIPTION
        Shared engine behind Image-Build-Alpine.ps1, Image-Build-Ubuntu.ps1,
        and Image-Build-Ubuntu-Chiseled.ps1. Builds the image-definition list,
        ensures the dotnet-tools context, prints the settings block, verifies
        the docker CLI, runs every build, and prints the summary. Each entry
        script supplies only its distro label and lean base target, so all three
        remain runnable on their own.
    .REMARKS
        1. Build the image definitions with Get-ImageBuildDefinitions.
        2. Ensure the tools context with Initialize-ImageBuildToolsContext.
        3. Print the settings block.
        4. Verify the docker CLI.
        5. Run the builds and print the summary.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DistroLabel,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DotNetVersion,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$BaseTarget,

        [Parameter(Mandatory = $true)]
        [bool]$NoCache,

        [Parameter(Mandatory = $false)]
        [switch]$ToolsOnly
    )

    Begin {
        if ($PSBoundParameters.ContainsKey('Verbose') -or $VerbosePreference -eq 'Continue') {
            $PSBoundParameters | Out-String | Write-Host
        }
    }

    Process {

        $dotnetToolsContext = 'dockerfiles/.dotnet-tools'

        $imageBuilds = Get-ImageBuildDefinitions `
            -DistroLabel $DistroLabel `
            -DotNetVersion $DotNetVersion `
            -BaseTarget $BaseTarget `
            -ToolsOnly:$ToolsOnly

        Initialize-ImageBuildToolsContext `
            -RepositoryRoot $RepositoryRoot `
            -DotNetToolsContext $dotnetToolsContext `
            -ImageBuilds $imageBuilds

        Write-ImageBuildSettings `
            -RepositoryRoot $RepositoryRoot `
            -Distro $DistroLabel `
            -NoCache $NoCache `
            -DotNetToolsContext $dotnetToolsContext `
            -ImageBuilds $imageBuilds

        Write-Host "Verifying docker CLI:" -ForegroundColor Green
        $dockerVersion = Assert-ImageBuildDockerCli
        Write-Host "Done verifying docker CLI: $dockerVersion" -ForegroundColor Green
        Write-Output ""

        Invoke-ImageBuildBatch `
            -RepositoryRoot $RepositoryRoot `
            -ImageBuilds $imageBuilds `
            -DotNetToolsContext $dotnetToolsContext `
            -NoCache $NoCache

        Write-ImageBuildSummary -ImageBuilds $imageBuilds
    }
}
