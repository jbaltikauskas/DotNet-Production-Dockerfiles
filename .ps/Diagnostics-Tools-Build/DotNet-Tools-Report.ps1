#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Scans dockerfiles\.dotnet-tools and writes a markdown report of every artifact.

.DESCRIPTION
    Top-down flow when this script runs:

        1. Resolve the tools folder and the report path.
        2. Load helper functions from Core.
        3. Print the settings block.
        4. Enumerate every file under the tools folder, recursively, skipping
           the report file itself.
        5. For each file, collect size, SHA-256, Win32 version resource, and
           Authenticode signer (Windows only).
        6. For each *.dll, read .NET assembly metadata without loading it:
           AssemblyVersion, AssemblyFileVersion, AssemblyInformationalVersion,
           title, company, product, copyright, configuration, target framework,
           public key token, platform, MVID, and AssemblyMetadata pairs.
        7. For each *.runtimeconfig.json and *.deps.json, read the TFM,
           shared framework, roll-forward policy, and runtime target.
        8. Record files that cannot be read as warnings instead of failing.
        9. Build the markdown report and write it as UTF-8 without BOM.

    DotNet-Tools.ps1 writes the same report automatically after it publishes
    dockerfiles\.dotnet-tools. Run this script to regenerate it on its own.

.PARAMETER ToolsDirectory
    Folder to scan. Defaults to dockerfiles\.dotnet-tools under the repository root.

.PARAMETER OutputPath
    Markdown file to write. Defaults to
    dockerfiles\.dotnet-tools\dotnet-assembly-report.md under the repository
    root. The parent folder is created when missing.

.PARAMETER WaitOnExit
    When set, waits for Enter after success or failure so a double-clicked
    console window stays open. Omit it in a terminal or CI run. Defaults to off.

.INPUTS
    None.

.OUTPUTS
    Host messages and the markdown report file. Exit code 0 on success;
    exit code 1 on failure.

.NOTES
    Requires PowerShell 7.2+. Run DotNet-Tools.ps1 first to populate
    dockerfiles\.dotnet-tools. Authenticode signer details are only
    available on Windows.

.EXAMPLE
    PS> .\.ps\Diagnostics-Tools-Build\DotNet-Tools-Report.ps1
    Scans dockerfiles\.dotnet-tools and writes dockerfiles\.dotnet-tools\dotnet-assembly-report.md.

.EXAMPLE
    PS> .\.ps\Diagnostics-Tools-Build\DotNet-Tools-Report.ps1 -ToolsDirectory .\dockerfiles\.build\dotnet-tools -OutputPath .\docs\dotnet-tools-report.md
    Scans the staging folder and writes the report under docs.

.EXAMPLE
    PS> .\.ps\Diagnostics-Tools-Build\DotNet-Tools-Report.ps1 -WaitOnExit
    Writes the default report and waits for Enter before the window closes.
#>

#Requires -Version 7.2

[CmdletBinding()]
Param (
    [Parameter(Mandatory = $false, Position = 0, HelpMessage = 'Folder to scan for .NET artifacts.')]
    [ValidateNotNullOrEmpty()]
    [string]$ToolsDirectory = (Join-Path $PSScriptRoot '..\..\dockerfiles\.dotnet-tools'),

    [Parameter(Mandatory = $false, Position = 1, HelpMessage = 'Markdown report file to write.')]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('\.md$')]
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\..\dockerfiles\.dotnet-tools\dotnet-assembly-report.md'),

    [Parameter(Mandatory = $false, HelpMessage = 'Wait for Enter before exiting.')]
    [switch]$WaitOnExit
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

try {

    $toolsDirectoryPath = [System.IO.Path]::GetFullPath($ToolsDirectory)
    $outputFilePath = [System.IO.Path]::GetFullPath($OutputPath)
    $corePath = Join-Path $PSScriptRoot 'Core'

    Write-Output "Loading module files:"

    $moduleFiles = @(
        'Get-DotNetToolsAssemblyInfo.ps1'
        'Get-DotNetToolsFileInfo.ps1'
        'New-DotNetToolsMarkdownTable.ps1'
        'ConvertTo-DotNetToolsMarkdownReport.ps1'
        'Write-DotNetToolsAssemblyReport.ps1'
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
    Write-Output "Tools folder : $toolsDirectoryPath"
    Write-Output "Report file  : $outputFilePath"
    Write-Output ""
    $PSBoundParameters | Out-String | Write-Output
    Write-Output "---------------------------- END: Settings ----------------------------"
    Write-Output ""

    Write-Host "Writing assembly report:" -ForegroundColor Green
    $result = Write-DotNetToolsAssemblyReport -ToolsDirectory $toolsDirectoryPath -OutputPath $outputFilePath
    Write-Host "Done writing assembly report: $($result.ManagedCount) managed assemblies, $($result.OtherCount) other files, $($result.UnreadableCount) unreadable." -ForegroundColor Green
    Write-Output ""

    Write-Host "Report is in $($result.ReportPath)" -ForegroundColor Cyan
}
catch {

    Write-Host ""
    Write-Error "Caught an exception:" -ErrorAction Continue
    Write-Error "Exception Type: $($_.Exception.GetType().FullName)" -ErrorAction Continue
    Write-Error "Exception Message: $($_.Exception.Message)" -ErrorAction Continue
    Write-Host ""
    Write-Host "Script failed to execute." -ForegroundColor Red

    if ($WaitOnExit) {
        Read-Host "Press Enter to close the window ..."
    }

    EXIT 1
}

Write-Host ""
Write-Host "Script executed successfully." -ForegroundColor Green

if ($WaitOnExit) {
    Read-Host "Press Enter to close the window ..."
}

EXIT 0
