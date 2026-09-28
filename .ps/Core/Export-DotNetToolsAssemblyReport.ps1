function Export-DotNetToolsAssemblyReport () {
    <#
    .SYNOPSIS
        Scans a tools folder and exports the markdown assembly report.
    .DESCRIPTION
        Collects Get-DotNetToolsFileInfo for every file under ToolsDirectory,
        except the report file itself so a re-run does not list the previous
        report. Files that cannot be read are reported as warnings instead of
        failing the run. Exports UTF-8 without BOM and creates the parent folder
        when missing. Returns an object with the report path and counts.
        Requires Get-DotNetToolsAssemblyInfo.ps1, Get-DotNetToolsFileInfo.ps1,
        New-DotNetToolsMarkdownTable.ps1, and
        ConvertTo-DotNetToolsMarkdownReport.ps1 to be dot-sourced first.
    .NOTE
        1. Require ToolsDirectory to exist.
        2. Enumerate files recursively, skipping OutputPath.
        3. Collect file info; record failures with their message.
        4. Build the markdown with ConvertTo-DotNetToolsMarkdownReport.
        5. Export the report and return path and counts.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, HelpMessage = 'Folder to scan recursively for .NET artifacts.')]
        [ValidateNotNullOrEmpty()]
        [string]$ToolsDirectory,

        [Parameter(Mandatory = $true, HelpMessage = 'Markdown report file to write. The parent folder is created when missing.')]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath
    )

    Begin {
        if ($PSBoundParameters.ContainsKey('Verbose') -or $VerbosePreference -eq 'Continue') {
            $PSBoundParameters | Out-String | Write-Host
        }
    }

    Process {

        $toolsDirectoryPath = [System.IO.Path]::GetFullPath($ToolsDirectory)
        $outputFilePath = [System.IO.Path]::GetFullPath($OutputPath)

        if (-not (Test-Path -LiteralPath $toolsDirectoryPath -PathType Container)) {
            throw "Tools folder was not found: '$toolsDirectoryPath'. Run DotNet-Tools.ps1 first."
        }

        $sourceFiles = @(Get-ChildItem -LiteralPath $toolsDirectoryPath -File -Recurse |
            Where-Object { $_.FullName -ne $outputFilePath })

        $files = [System.Collections.Generic.List[object]]::new()
        $failures = [System.Collections.Generic.List[object]]::new()

        foreach ($sourceFile in $sourceFiles) {
            try {

                $files.Add((Get-DotNetToolsFileInfo -Path $sourceFile.FullName -RootDirectory $toolsDirectoryPath))
            }
            catch {
                $relativePath = [System.IO.Path]::GetRelativePath($toolsDirectoryPath, $sourceFile.FullName).Replace('\', '/')
                Write-Host "  Could not read ${relativePath}: $($_.Exception.Message)" -ForegroundColor Yellow
                $failures.Add([pscustomobject]@{ RelativePath = $relativePath; Message = $_.Exception.Message })
            }
        }

        $report = ConvertTo-DotNetToolsMarkdownReport `
            -Files $files.ToArray() `
            -Failures $failures.ToArray() `
            -ToolsDirectory $toolsDirectoryPath

        New-Item -ItemType Directory -Path (Split-Path -Parent $outputFilePath) -Force | Out-Null
        Set-Content -LiteralPath $outputFilePath -Value $report -Encoding utf8NoBOM -NoNewline

        $managedCount = @($files | Where-Object { $_.Kind -eq 'Managed assembly' }).Count

        return [pscustomobject]@{
            ReportPath      = $outputFilePath
            ManagedCount    = $managedCount
            OtherCount      = $files.Count - $managedCount
            UnreadableCount = $failures.Count
        }
    }
}
