function Get-DotNetToolsNuGetVersion () {
    <#
    .SYNOPSIS
        Resolves the latest listed stable NuGet version for a package.
    .DESCRIPTION
        Reads the NuGet registration index. Unlisted and prerelease versions are
        ignored. An unlisted upload can outrank the real tool build under SemVer.
    .REMARKS
        1. Read the package registration index.
        2. Flatten inline or paged catalog entries.
        3. Keep listed stable versions.
        4. Return the highest version.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PackageId
    )

    Begin {
        if ($PSBoundParameters.ContainsKey('Verbose') -or $VerbosePreference -eq 'Continue') {
            $PSBoundParameters | Out-String | Write-Host
        }
    }

    Process {

        $id = $PackageId.ToLowerInvariant()
        $indexUri = "https://api.nuget.org/v3/registration5-gz-semver2/$id/index.json"
        $index = Invoke-RestMethod -Uri $indexUri

        $entries = foreach ($page in @($index.items)) {
            $leaves = if ($page.items) {
                $page.items
            }
            else {
                (Invoke-RestMethod -Uri $page.'@id').items
            }

            foreach ($leaf in @($leaves)) {
                $leaf.catalogEntry
            }
        }

        $stable = @($entries | Where-Object {
                $_.listed -eq $true -and $_.version -notmatch '-'
            })

        if ($stable.Count -eq 0) {
            throw "NuGet returned no listed stable version for '$PackageId'."
        }

        $latest = $stable | Sort-Object { [version]$_.version } | Select-Object -Last 1
        return [string]$latest.version
    }
}
