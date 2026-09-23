function Copy-DotNetToolsRuntimeFiles () {
    <#
    .SYNOPSIS
        Copies root runtime files from an extracted dotnet tool.
    .DESCRIPTION
        Copies *.dll and *.json files from tools\net8.0\any into the shared
        dotnet-tools folder. Only files in that folder root are copied.
        Files already in the destination are overwritten.
    .REMARKS
        1. Require the extracted tools\net8.0\any folder.
        2. Select root *.dll and *.json files.
        3. Overwrite files that already exist.
        4. Return the number of files copied.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PackageId,

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

        $id = $PackageId.ToLowerInvariant()
        $sourceDirectory = Join-Path $BuildDirectory "$id\tools\net8.0\any"
        if (-not (Test-Path -LiteralPath $sourceDirectory -PathType Container)) {
            throw "Tool folder was not found: '$sourceDirectory'."
        }

        $runtimeFiles = @(Get-ChildItem -LiteralPath $sourceDirectory -File |
            Where-Object { $_.Extension -in @('.dll', '.json') })

        if ($runtimeFiles.Count -eq 0) {
            throw "No root *.dll or *.json files were found in '$sourceDirectory'."
        }

        foreach ($runtimeFile in $runtimeFiles) {
            Copy-Item -LiteralPath $runtimeFile.FullName -Destination $ToolDirectory -Force
        }

        return $runtimeFiles.Count
    }
}
