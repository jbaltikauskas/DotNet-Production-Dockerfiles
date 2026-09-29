function Copy-DotNetToolsRuntimeFolder () {
    <#
    .SYNOPSIS
        Copies one optional folder from an extracted dotnet tool.
    .DESCRIPTION
        Looks for FolderName directly under tools/net8.0/any, beside the root
        assemblies. When the folder exists, copies it into the shared
        dotnet-tools folder and overwrites existing files. Returns false when
        the folder is absent.
    .NOTE
        1. Resolve tools/net8.0/any/FolderName.
        2. Return false when the folder is absent.
        3. Copy files into ToolDirectory/FolderName, overwriting existing files.
        4. Return true.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, HelpMessage = 'The dotnet diagnostic tool package id, for example dotnet-trace.')]
        [ValidateNotNullOrEmpty()]
        [string]$PackageId,

        [Parameter(Mandatory = $true, HelpMessage = 'Runtime subfolder name to copy, for example runtimes, linux-x64, or linux-musl-x64.')]
        [ValidateNotNullOrEmpty()]
        [string]$FolderName,

        [Parameter(Mandatory = $true, HelpMessage = 'Path to the dockerfiles/.build working folder.')]
        [ValidateNotNullOrEmpty()]
        [string]$BuildDirectory,

        [Parameter(Mandatory = $true, HelpMessage = 'Path to the merged dotnet-tools output folder that the subfolder is copied into.')]
        [ValidateNotNullOrEmpty()]
        [string]$ToolDirectory
    )

    Begin {
        Write-Verbose ("BEGIN: {0}" -f $MyInvocation.MyCommand.Name)
        Write-Verbose ($PSBoundParameters | Out-String)
    }

    Process {

        if ($FolderName -notmatch '^[A-Za-z0-9._-]+$') {
            throw "FolderName contains invalid characters: '$FolderName'."
        }

        $id = $PackageId.ToLowerInvariant()
        $sourceDirectory = Join-Path $BuildDirectory $id 'tools' 'net8.0' 'any' $FolderName
        if (-not (Test-Path -LiteralPath $sourceDirectory -PathType Container)) {
            return $false
        }

        $destinationDirectory = Join-Path $ToolDirectory $FolderName
        $sourceFiles = @(Get-ChildItem -LiteralPath $sourceDirectory -Recurse -File -Force)
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
