function Invoke-ImageBuildScript () {
    <#
    .SYNOPSIS
        Invokes a repository script and throws on a non-zero exit code.
    .DESCRIPTION
        Resolves RelativePath under RepositoryRoot, verifies the script exists,
        prints a section banner, runs it with the supplied arguments, and throws
        when $LASTEXITCODE is non-zero. Used to chain the diagnostics-tools
        script, the per-distro scripts, and the test-app script.
    .REMARKS
        1. Resolve the script path and throw when it is missing.
        2. Print the section banner (RelativePath plus any argument summary).
        3. Invoke the script, splatting Arguments.
        4. Throw when $LASTEXITCODE is non-zero.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RelativePath,

        [Parameter(Mandatory = $false)]
        [hashtable]$Arguments = @{},

        [Parameter(Mandatory = $false)]
        [string]$BannerSuffix
    )

    Begin {
        if ($PSBoundParameters.ContainsKey('Verbose') -or $VerbosePreference -eq 'Continue') {
            $PSBoundParameters | Out-String | Write-Host
        }
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

        Write-ImageBuildSection -Message $bannerMessage

        & $scriptPath @Arguments

        if ($LASTEXITCODE) {
            throw "$RelativePath failed with exit code $LASTEXITCODE."
        }
    }
}
