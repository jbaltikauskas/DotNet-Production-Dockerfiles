function Expand-DotNetToolsNuGetPackage () {
    <#
    .SYNOPSIS
        Extracts a downloaded .nupkg into its package folder.
    .DESCRIPTION
        A .nupkg is a zip archive. Each package is extracted to Build/<package-id>
        so package contents do not overwrite each other.
    .NOTE
        1. Replace an existing extract folder.
        2. Extract the archive.
        3. Return the extract folder.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, HelpMessage = 'The dotnet diagnostic tool package id, for example dotnet-trace.')]
        [ValidateNotNullOrEmpty()]
        [string]$PackageId,

        [Parameter(Mandatory = $true, HelpMessage = 'Path to the downloaded .nupkg file to extract.')]
        [ValidateNotNullOrEmpty()]
        [string]$NupkgPath,

        [Parameter(Mandatory = $true, HelpMessage = 'Path to the dockerfiles/.build working folder the package is extracted under.')]
        [ValidateNotNullOrEmpty()]
        [string]$BuildDirectory
    )

    Begin {
        Write-Verbose ("BEGIN: {0}" -f $MyInvocation.MyCommand.Name)
        Write-Verbose ($PSBoundParameters | Out-String)
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
