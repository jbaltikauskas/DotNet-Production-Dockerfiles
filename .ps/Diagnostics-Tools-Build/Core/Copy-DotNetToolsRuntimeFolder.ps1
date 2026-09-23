function Copy-DotNetToolsRuntimeFolder () {
    <#
    .SYNOPSIS
        Copies one optional folder from an extracted dotnet tool.
    .DESCRIPTION
        Looks for FolderName directly under tools\net8.0\any, beside the root
        assemblies. When the folder exists, copies it into the shared
        dotnet-tools folder and overwrites existing files. Returns false when
        the folder is absent.
    .REMARKS
        1. Resolve tools\net8.0\any\FolderName.
        2. Return false when the folder is absent.
        3. Copy files into ToolDirectory\FolderName, overwriting existing files.
        4. Return true.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PackageId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$FolderName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$BuildDirectory,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ToolDirectory
    )

    Begin {
        if ($PSBoundParameters.ContainsKey('Verbose') -or $VerbosePreference -eq 'Continue') {
            $PSBoundParameters | Out-String | Write-Host
        }
    }

    Process {

        if ($FolderName -notmatch '^[A-Za-z0-9._-]+$') {
            throw "FolderName contains invalid characters: '$FolderName'."
        }

        $id = $PackageId.ToLowerInvariant()
        $sourceDirectory = Join-Path $BuildDirectory "$id\tools\net8.0\any\$FolderName"
        if (-not (Test-Path -LiteralPath $sourceDirectory -PathType Container)) {
            return $false
        }

        $destinationDirectory = Join-Path $ToolDirectory $FolderName
        $sourceFiles = @(Get-ChildItem -LiteralPath $sourceDirectory -Recurse -File)
        foreach ($sourceFile in $sourceFiles) {
            $relativePath = $sourceFile.FullName.Substring($sourceDirectory.Length).TrimStart('\', '/')
            $destinationFile = Join-Path $destinationDirectory $relativePath
            $destinationParent = Split-Path -Parent $destinationFile
            if (-not (Test-Path -LiteralPath $destinationParent -PathType Container)) {
                New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
            }

            Copy-Item -LiteralPath $sourceFile.FullName -Destination $destinationFile -Force
        }

        return $true
    }
}
