function Remove-DotNetToolsRuntimeSubfolders () {
    <#
    .SYNOPSIS
        Deletes selected immediate subfolders from the copied runtimes folder.
    .DESCRIPTION
        Removes child folders of ToolDirectory\runtimes whose names match any
        pattern in SubfolderPatterns, such as win* or browser. Other runtime
        folders are left in place. Returns the names that were deleted.
    .REMARKS
        1. Resolve ToolDirectory\runtimes.
        2. Return no names when the runtimes folder is absent.
        3. Delete each immediate child folder that matches a pattern.
        4. Return the deleted folder names.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ToolDirectory,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$SubfolderPatterns
    )

    Begin {
        if ($PSBoundParameters.ContainsKey('Verbose') -or $VerbosePreference -eq 'Continue') {
            $PSBoundParameters | Out-String | Write-Host
        }
    }

    Process {

        $runtimesDirectory = Join-Path $ToolDirectory 'runtimes'
        if (-not (Test-Path -LiteralPath $runtimesDirectory -PathType Container)) {
            return @()
        }

        $removedNames = [System.Collections.Generic.List[string]]::new()
        $childFolders = @(Get-ChildItem -LiteralPath $runtimesDirectory -Directory)
        foreach ($childFolder in $childFolders) {
            $matchesPattern = $false
            foreach ($pattern in $SubfolderPatterns) {
                if ($childFolder.Name -like $pattern) {
                    $matchesPattern = $true
                    break
                }
            }

            if (-not $matchesPattern) {
                continue
            }

            Remove-Item -LiteralPath $childFolder.FullName -Recurse -Force
            $removedNames.Add($childFolder.Name)
        }

        return @($removedNames)
    }
}
