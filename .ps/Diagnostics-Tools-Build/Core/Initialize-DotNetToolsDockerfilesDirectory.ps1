function Initialize-DotNetToolsDockerfilesDirectory () {
    <#
    .SYNOPSIS
        Prepares dockerfiles\.dotnet-tools for a fresh copy.
    .DESCRIPTION
        Creates the folder when it is missing. When it already exists, deletes
        every file and subfolder inside it and keeps the folder.
    .REMARKS
        1. Create DestinationDirectory when it is missing.
        2. Delete existing files and subfolders.
        3. Return DestinationDirectory.
    #>
    [CmdletBinding()]
    Param (
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

        if (-not (Test-Path -LiteralPath $DestinationDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $DestinationDirectory -Force | Out-Null
            return $DestinationDirectory
        }

        $existingItems = @(Get-ChildItem -LiteralPath $DestinationDirectory -Force)
        foreach ($existingItem in $existingItems) {
            Remove-Item -LiteralPath $existingItem.FullName -Recurse -Force
        }

        return $DestinationDirectory
    }
}
