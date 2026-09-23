function Copy-DotNetToolsDirectoryTree () {
    <#
    .SYNOPSIS
        Copies every file and subfolder from one directory into another.
    .DESCRIPTION
        Recreates the source tree under DestinationDirectory. Files already
        present at the destination are overwritten.
    .REMARKS
        1. Require SourceDirectory.
        2. Copy each file, creating parent folders as needed.
        3. Return the number of files copied.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SourceDirectory,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DestinationDirectory
    )

    Begin {
        if ($PSBoundParameters.ContainsKey('Verbose') -or $VerbosePreference -eq 'Continue') {
            $PSBoundParameters | Out-String | Write-Host
        }
    }

    Process {

        if (-not (Test-Path -LiteralPath $SourceDirectory -PathType Container)) {
            throw "Source folder was not found: '$SourceDirectory'."
        }

        if (-not (Test-Path -LiteralPath $DestinationDirectory -PathType Container)) {
            throw "Destination folder was not found: '$DestinationDirectory'."
        }

        $sourceFiles = @(Get-ChildItem -LiteralPath $SourceDirectory -Recurse -File -Force)
        foreach ($sourceFile in $sourceFiles) {
            $relativePath = $sourceFile.FullName.Substring($SourceDirectory.Length).TrimStart('\', '/')
            $destinationFile = Join-Path $DestinationDirectory $relativePath
            $destinationParent = Split-Path -Parent $destinationFile
            if (-not (Test-Path -LiteralPath $destinationParent -PathType Container)) {
                New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
            }

            Copy-Item -LiteralPath $sourceFile.FullName -Destination $destinationFile -Force
        }

        return $sourceFiles.Count
    }
}
