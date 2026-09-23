function Save-DotNetToolsNuGetPackage () {
    <#
    .SYNOPSIS
        Downloads one NuGet package into dockerfiles\.build.
    .DESCRIPTION
        Saves the .nupkg from the NuGet flat container and removes older
        archives for the same package id.
    .REMARKS
        1. Download the .nupkg.
        2. Remove older archives for the same package id.
        3. Return the archive path.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PackageId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Version,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$BuildDirectory
    )

    Begin {
        if ($PSBoundParameters.ContainsKey('Verbose') -or $VerbosePreference -eq 'Continue') {
            $PSBoundParameters | Out-String | Write-Host
        }
    }

    Process {

        $id = $PackageId.ToLowerInvariant()
        $nupkgName = "$id.$Version.nupkg"
        $nupkgPath = Join-Path $BuildDirectory $nupkgName
        $packageUri = "https://api.nuget.org/v3-flatcontainer/$id/$Version/$nupkgName"

        Write-Host "Package URI: $packageUri"
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $packageUri -OutFile $nupkgPath

        $previousPackages = Get-ChildItem -LiteralPath $BuildDirectory -Filter "$id.*.nupkg" -File |
            Where-Object { $_.FullName -ne $nupkgPath }
            
        foreach ($previousPackage in $previousPackages) {
            Remove-Item -LiteralPath $previousPackage.FullName -Force
        }

        return $nupkgPath
    }
}
