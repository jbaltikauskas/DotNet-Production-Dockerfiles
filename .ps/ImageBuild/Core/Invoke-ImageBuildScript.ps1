function Invoke-ImageBuildScript () {
    <#
    .SYNOPSIS
        Invokes a repository script and throws on a non-zero exit code.
    .DESCRIPTION
        Resolves RelativePath under RepositoryRoot, verifies the script exists,
        prints a section banner, runs it with the supplied arguments, and throws
        when $LASTEXITCODE is non-zero. Used to chain the diagnostics-tools
        script, the per-distro scripts, and the test-app script.
    .NOTE
        1. Resolve the script path and throw when it is missing.
        2. Print the section banner (RelativePath plus any argument summary).
        3. Invoke the script, splatting Arguments.
        4. Throw when $LASTEXITCODE is non-zero.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, HelpMessage = 'Absolute path to the repository root that RelativePath is resolved against.')]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true, HelpMessage = 'Repository-relative path of the .ps1 script to invoke.')]
        [ValidateNotNullOrEmpty()]
        [string]$RelativePath,

        [Parameter(Mandatory = $false, HelpMessage = 'Named arguments splatted into the invoked script. Defaults to none.')]
        [hashtable]$Arguments = @{},

        [Parameter(Mandatory = $false, HelpMessage = 'Extra text appended to the section banner, for example the forwarded switches.')]
        [string]$BannerSuffix
    )

    Begin {
        Write-Verbose ("BEGIN: {0}" -f $MyInvocation.MyCommand.Name)
        Write-Verbose ($PSBoundParameters | Out-String)
    }

    Process {

        $scriptPath = Join-Path $RepositoryRoot $RelativePath
        if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
            throw "Required script was not found: '$scriptPath'."
        }

        $bannerMessage = "Invoking $RelativePath"
        if (-not [string]::IsNullOrWhiteSpace($BannerSuffix)) {
            $bannerMessage = "$bannerMessage $BannerSuffix"
        }

        Write-Section -Message $bannerMessage

        & $scriptPath @Arguments

        Assert-LastExitCode -Activity $RelativePath
    }
}
