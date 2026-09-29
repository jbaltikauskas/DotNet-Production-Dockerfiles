#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Scans a folder of .NET build artifacts and writes a markdown report of every file.

.DESCRIPTION
    Generic report over any folder and its subfolders. Top-down flow when this
    script runs:

        1. Resolve the scan folder and the report path.
        2. Load helper functions that sit beside this script.
        3. Print the settings block.
        4. Enumerate every file under the scan folder, recursively, skipping
           the report file itself.
        5. For each file, collect size, SHA-256, Win32 version resource, and
           Authenticode signer (Windows only).
        6. For each *.dll, read .NET assembly metadata without loading it:
           AssemblyVersion, AssemblyFileVersion, AssemblyInformationalVersion,
           title, company, product, copyright, configuration, target framework,
           public key token, referenced assembly names, and AssemblyMetadata pairs.
        7. For each *.runtimeconfig.json and *.deps.json, read the TFM,
           shared framework, roll-forward policy, and runtime target.
        8. Record files that cannot be read as warnings instead of failing.
        9. Build the markdown report and write it as UTF-8 without BOM.

    The script is not tied to any particular folder. Callers pass both the
    folder to scan and the report path.

.PARAMETER ToolsDirectory
    Folder to scan for .NET build artifacts. Scanned recursively. Mandatory.

.PARAMETER OutputPath
    Markdown file to write. The parent folder is created when missing. Mandatory.

.PARAMETER WaitOnExit
    When set, waits for Enter after success or failure so a double-clicked
    console window stays open. Omit it in a terminal or CI run. Defaults to off.

.INPUTS
    None.

.OUTPUTS
    Host messages and the markdown report file. Exit code 0 on success;
    exit code 1 on failure.

.NOTES
    Requires PowerShell 7.2+. Authenticode signer details are only available
    on Windows.

.EXAMPLE
    PS> ./.ps/Core/Export-DotNetArtifactReport.ps1 -ToolsDirectory ./dockerfiles/.dotnet-tools -OutputPath ./dockerfiles/.dotnet-tools/dotnet-assembly-report.md
    Scans the merged diagnostics-tools folder and writes its assembly report.

.EXAMPLE
    PS> ./.ps/Core/Export-DotNetArtifactReport.ps1 -ToolsDirectory ./src/MyApp/bin/Release/net8.0 -OutputPath ./artifacts/myapp-report.md
    Scans a published output folder and writes the report under artifacts.

.EXAMPLE
    PS> ./.ps/Core/Export-DotNetArtifactReport.ps1 -ToolsDirectory ./bin -OutputPath ./bin/report.md -WaitOnExit
    Writes the report and waits for Enter before the window closes.
#>

#Requires -Version 7.2

[CmdletBinding()]
Param (
    [Parameter(Mandatory = $true, Position = 0, HelpMessage = 'Folder to scan recursively for .NET build artifacts.')]
    [ValidateNotNullOrEmpty()]
    [string]$ToolsDirectory,

    [Parameter(Mandatory = $true, Position = 1, HelpMessage = 'Markdown report file to write.')]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('\.md$')]
    [string]$OutputPath,

    [Parameter(Mandatory = $false, HelpMessage = 'Wait for Enter before exiting.')]
    [switch]$WaitOnExit
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

. (Join-Path $PSScriptRoot 'Write-ScriptError.ps1')
. (Join-Path $PSScriptRoot 'Write-ScriptSuccess.ps1')

try {

    $toolsDirectoryPath = [System.IO.Path]::GetFullPath($ToolsDirectory)
    $outputFilePath = [System.IO.Path]::GetFullPath($OutputPath)
    $corePath = $PSScriptRoot

    Write-Output "Loading module files:"

    $moduleFiles = @(
        'Get-DotNetToolsAssemblyInfo.ps1'
        'Get-DotNetToolsFileInfo.ps1'
        'New-DotNetToolsMarkdownTable.ps1'
        'ConvertTo-DotNetToolsMarkdownReport.ps1'
        'Export-DotNetToolsAssemblyReport.ps1'
    )

    foreach ($moduleFileName in $moduleFiles) {
        $moduleFile = Join-Path $corePath $moduleFileName
        Write-Output "  $moduleFile"
        . $moduleFile
    }

    Write-Host "Done loading module files." -ForegroundColor Green

    Write-Output ""
    Write-Output "--------------------------- BEGIN: Settings ---------------------------"
    Write-Output ""
    Write-Output "Scan folder : $toolsDirectoryPath"
    Write-Output "Report file : $outputFilePath"
    Write-Output ""
    $PSBoundParameters | Out-String | Write-Output
    Write-Output "---------------------------- END: Settings ----------------------------"
    Write-Output ""

    Write-Host "Exporting assembly report:" -ForegroundColor Green
    $result = Export-DotNetToolsAssemblyReport -ToolsDirectory $toolsDirectoryPath -OutputPath $outputFilePath
    Write-Host "Done exporting assembly report: $($result.ManagedCount) managed assemblies, $($result.OtherCount) other files, $($result.UnreadableCount) unreadable." -ForegroundColor Green
    Write-Output ""

    Write-Host "Report is in $($result.ReportPath)" -ForegroundColor Cyan
}
catch {

    Write-ScriptError -ErrorRecord $_ -WaitOnExit:$WaitOnExit
    EXIT 1
}

Write-ScriptSuccess -WaitOnExit:$WaitOnExit

EXIT 0
