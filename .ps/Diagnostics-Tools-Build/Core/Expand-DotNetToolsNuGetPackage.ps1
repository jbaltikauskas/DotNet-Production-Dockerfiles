function Expand-DotNetToolsNuGetPackage () {
    <#
    .SYNOPSIS
        Extracts a downloaded .nupkg into its package folder.
    .DESCRIPTION
        A .nupkg is a zip archive. Each package is extracted to Build\<package-id>
        so package contents do not overwrite each other.
    .REMARKS
        1. Replace an existing extract folder.
        2. Extract the archive.
        3. Return the extract folder.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PackageId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$NupkgPath,

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

        if (-not (Test-Path -LiteralPath $NupkgPath -PathType Leaf)) {
            throw "NuGet package was not found: '$NupkgPath'."
        }

        $extractDirectory = Join-Path $BuildDirectory $PackageId.ToLowerInvariant()
        if (Test-Path -LiteralPath $extractDirectory) {
            Remove-Item -LiteralPath $extractDirectory -Recurse -Force
        }

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($NupkgPath, $extractDirectory)
        return $extractDirectory
    }
}
