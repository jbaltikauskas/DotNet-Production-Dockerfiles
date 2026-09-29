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
    .NOTE
        1. Build the image definitions with Get-ImageBuildDefinitions.
        2. Ensure the tools context with Initialize-ImageBuildToolsContext.
        3. Print the settings block.
        4. Verify the docker CLI.
        5. Run the builds and print the summary.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, HelpMessage = 'Absolute path to the repository root that docker builds run from.')]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true, HelpMessage = 'Distro label used in the Dockerfile folder and image tags, for example alpine or ubuntu-chiseled.')]
        [ValidateNotNullOrEmpty()]
        [string]$DistroLabel,

        [Parameter(Mandatory = $true, HelpMessage = 'The .NET major version used in the Dockerfile folder and image tags.')]
        [ValidateNotNullOrEmpty()]
        [string]$DotNetVersion,

        [Parameter(Mandatory = $true, HelpMessage = 'Build target for the lean base image, for example aspnet-base or runtime-base.')]
        [ValidateNotNullOrEmpty()]
        [string]$BaseTarget,

        [Parameter(Mandatory = $true, HelpMessage = 'Pass --no-cache to docker buildx build.')]
        [bool]$NoCache,

        [Parameter(Mandatory = $false, HelpMessage = 'Build only the diagnostics-tools image (target: final) and skip the lean base image.')]
        [switch]$ToolsOnly
    )

    Begin {
        Write-Verbose ("BEGIN: {0}" -f $MyInvocation.MyCommand.Name)
        Write-Verbose ($PSBoundParameters | Out-String)
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
        $dockerVersion = Assert-Cli -Name 'docker' -VersionArgs @('version', '--format', '{{.Client.Version}}')
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
