#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Downloads the latest dotnet diagnostic NuGet packages and extracts them.

.DESCRIPTION
    Top-down flow when this script runs:

        1. Load helper functions from Core.
        2. Create dockerfiles\.build.
        3. Resolve the latest listed stable version of each package.
        4. Download each .nupkg into dockerfiles\.build.
        5. Extract each package into dockerfiles\.build\<package-id>.
        6. Create dockerfiles\.build\dotnet-tools.
        7. Copy root *.dll and *.json files from each tools\net8.0\any folder into dockerfiles\.build\dotnet-tools.
        8. When present under tools\net8.0\any, copy runtimes into dockerfiles\.build\dotnet-tools.
        9. When present under tools\net8.0\any, copy linux-x64 into dockerfiles\.build\dotnet-tools.
       10. When present under tools\net8.0\any, copy linux-musl-x64 into dockerfiles\.build\dotnet-tools.
       11. Delete win* and browser subfolders from dockerfiles\.build\dotnet-tools\runtimes.
       12. Create dockerfiles\.dotnet-tools, or clear it when it already exists.
       13. Copy dockerfiles\.build\dotnet-tools into dockerfiles\.dotnet-tools.
       14. Scan dockerfiles\.dotnet-tools and write the assembly version report
           to dockerfiles\.dotnet-tools\dotnet-assembly-report.md.

    Image-Build-All.ps1 and Image-TestBuild-DotNet-Tools-TestApp.ps1 invoke
    this script before any image build. Each per-distro script invokes it
    when dockerfiles\.dotnet-tools is missing or empty. None of them pass
    -WaitOnExit.

.PARAMETER WaitOnExit
    When set, waits for Enter after success or failure so a double-clicked
    console window stays open. Omit it in a terminal or CI run. Defaults to off.

.INPUTS
    None. Package ids are fixed in this script.

.OUTPUTS
    Host messages, files under dockerfiles\.build, the merged tree in
    dockerfiles\.dotnet-tools, and dotnet-assembly-report.md in that folder.
    Exit code 0 on success; exit code 1 on failure.

.NOTES
    Requires PowerShell 7.2+ and network access to NuGet.

.EXAMPLE
    PS> .\.ps\Diagnostics-Tools-Build\DotNet-Tools.ps1
    Downloads the diagnostic packages and publishes dockerfiles\.dotnet-tools.

.EXAMPLE
    PS> .\.ps\Diagnostics-Tools-Build\DotNet-Tools.ps1 -WaitOnExit
    Publishes the tools folders and waits for Enter before the window closes.
#>

#Requires -Version 7.2

[CmdletBinding()]
Param (
    [Parameter(Mandatory = $false, HelpMessage = 'Wait for Enter after success or failure so a double-clicked console window stays open. Omit it in a terminal or CI run.')]
    [switch]$WaitOnExit
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true


$scriptRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptRoot)) {
    $scriptRoot = (Get-Location).Path
}

$modulePath = $scriptRoot
$corePath = Join-Path $modulePath 'Core'
if (-not (Test-Path -LiteralPath $corePath -PathType Container)) {
    throw "Required helper folder not found: '$corePath'."
}

try {

    $packageIds = @(
        'dotnet-counters'
        'dotnet-debug'
        'dotnet-gcdump'
        'dotnet-trace'
    )

    $runtimeFolderNames = @(
        'runtimes'
        'linux-x64'
        'linux-musl-x64'
    )

    $runtimeSubfoldersToRemove = @(
        'win*'
        'browser'
    )

    $repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptRoot '..\..'))
    $dockerfilesToolDirectory = Join-Path $repositoryRoot 'dockerfiles\.dotnet-tools'
    $assemblyReportPath = Join-Path $dockerfilesToolDirectory 'dotnet-assembly-report.md'

    Write-Output "Loading module files:"

    $moduleFiles = @(
        'Core\New-DotNetToolsBuildDirectory.ps1'
        'Core\New-DotNetToolsOutputDirectory.ps1'
        'Core\Copy-DotNetToolsRuntimeFiles.ps1'
        'Core\Copy-DotNetToolsRuntimeFolder.ps1'
        'Core\Remove-DotNetToolsRuntimeSubfolders.ps1'
        'Core\Initialize-DotNetToolsDockerfilesDirectory.ps1'
        'Core\Copy-DotNetToolsDirectoryTree.ps1'
        'Core\Get-DotNetToolsNuGetVersion.ps1'
        'Core\Save-DotNetToolsNuGetPackage.ps1'
        'Core\Expand-DotNetToolsNuGetPackage.ps1'
        '..\Core\Get-DotNetToolsAssemblyInfo.ps1'
        '..\Core\Get-DotNetToolsFileInfo.ps1'
        '..\Core\New-DotNetToolsMarkdownTable.ps1'
        '..\Core\ConvertTo-DotNetToolsMarkdownReport.ps1'
        '..\Core\Write-DotNetToolsAssemblyReport.ps1'
    )

    foreach ($relativePath in $moduleFiles) {
        $moduleFile = Join-Path $modulePath $relativePath
        Write-Output "  $moduleFile"
        . $moduleFile
    }

    Write-Host "Done loading module files." -ForegroundColor Green

    Write-Host "Creating build folder:" -ForegroundColor Green
    $buildDirectory = New-DotNetToolsBuildDirectory -RepositoryRoot $repositoryRoot
    Write-Host "Done creating build folder." -ForegroundColor Green

    Write-Output ""
    Write-Output "--------------------------- BEGIN: Settings ---------------------------"
    Write-Output ""
    Write-Output "Build folder    : $buildDirectory"
    Write-Output "Tool folder     : $(Join-Path $buildDirectory 'dotnet-tools')"
    Write-Output "Packages        : $($packageIds -join ', ')"
    Write-Output "Runtime folders : $($runtimeFolderNames -join ', ')"
    Write-Output "Remove from runtimes : $($runtimeSubfoldersToRemove -join ', ')"
    Write-Output "Dockerfiles tools : $dockerfilesToolDirectory"
    Write-Output "Assembly report : $assemblyReportPath"
    Write-Output ""
    Write-Output "---------------------------- END: Settings ----------------------------"
    Write-Output ""

    foreach ($packageId in $packageIds) {
        Write-Host "Resolving ${packageId}:" -ForegroundColor Green
        $version = Get-DotNetToolsNuGetVersion -PackageId $packageId
        Write-Host "Done resolving ${packageId}: $version" -ForegroundColor Green

        Write-Output ""
        Write-Host "Downloading ${packageId}:" -ForegroundColor Green
        $nupkgPath = Save-DotNetToolsNuGetPackage `
            -PackageId $packageId `
            -Version $version `
            -BuildDirectory $buildDirectory
        Write-Host "Done downloading ${packageId}." -ForegroundColor Green

        Write-Output ""
        Write-Host "Extracting ${packageId}:" -ForegroundColor Green
        $extractDirectory = Expand-DotNetToolsNuGetPackage `
            -PackageId $packageId `
            -NupkgPath $nupkgPath `
            -BuildDirectory $buildDirectory
        Write-Host "Done extracting ${packageId}: $extractDirectory" -ForegroundColor Green
        Write-Output ""
    }

    Write-Host "Creating dotnet-tools folder:" -ForegroundColor Green
    $toolDirectory = New-DotNetToolsOutputDirectory -BuildDirectory $buildDirectory
    Write-Host "Done creating dotnet-tools folder." -ForegroundColor Green
    Write-Output ""

    foreach ($packageId in $packageIds) {
        Write-Host "Copying ${packageId} runtime files:" -ForegroundColor Green
        $copiedCount = Copy-DotNetToolsRuntimeFiles `
            -PackageId $packageId `
            -BuildDirectory $buildDirectory `
            -ToolDirectory $toolDirectory
        Write-Host "Done copying ${packageId}: $copiedCount files" -ForegroundColor Green
        Write-Output ""

        foreach ($folderName in $runtimeFolderNames) {
            Write-Host "Copying ${packageId} ${folderName}:" -ForegroundColor Green
            $copiedFolder = Copy-DotNetToolsRuntimeFolder `
                -PackageId $packageId `
                -FolderName $folderName `
                -BuildDirectory $buildDirectory `
                -ToolDirectory $toolDirectory
            if ($copiedFolder) {
                Write-Host "Done copying ${packageId} ${folderName}." -ForegroundColor Green
            }
            else {
                Write-Output "Skipped ${packageId} ${folderName}: folder was not found."
            }
            Write-Output ""
        }
    }

    Write-Host "Removing excluded runtime subfolders:" -ForegroundColor Green
    $removedRuntimeFolders = @(Remove-DotNetToolsRuntimeSubfolders `
            -ToolDirectory $toolDirectory `
            -SubfolderPatterns $runtimeSubfoldersToRemove)
    if ($removedRuntimeFolders.Count -eq 0) {
        Write-Output "No matching runtime subfolders were found."
    }
    else {
        Write-Host "Done removing runtime subfolders: $($removedRuntimeFolders -join ', ')" -ForegroundColor Green
    }
    Write-Output ""

    Write-Host "Preparing dockerfiles dotnet-tools folder:" -ForegroundColor Green
    Initialize-DotNetToolsDockerfilesDirectory -DestinationDirectory $dockerfilesToolDirectory | Out-Null
    Write-Host "Done preparing dockerfiles dotnet-tools folder." -ForegroundColor Green
    Write-Output ""

    Write-Host "Copying tools into dockerfiles:" -ForegroundColor Green
    $publishedCount = Copy-DotNetToolsDirectoryTree `
        -SourceDirectory $toolDirectory `
        -DestinationDirectory $dockerfilesToolDirectory
    Write-Host "Done copying tools into dockerfiles: $publishedCount files" -ForegroundColor Green
    Write-Output ""

    Write-Host "Writing assembly report:" -ForegroundColor Green
    $report = Write-DotNetToolsAssemblyReport `
        -ToolsDirectory $dockerfilesToolDirectory `
        -OutputPath $assemblyReportPath
    Write-Host "Done writing assembly report: $($report.ManagedCount) managed assemblies, $($report.OtherCount) other files, $($report.UnreadableCount) unreadable." -ForegroundColor Green
    Write-Output ""

    Write-Host "Packages are in $buildDirectory" -ForegroundColor Cyan
    Write-Host "Runtime files are in $toolDirectory" -ForegroundColor Cyan
    Write-Host "Dockerfiles tools are in $dockerfilesToolDirectory" -ForegroundColor Cyan
    Write-Host "Assembly report is in $($report.ReportPath)" -ForegroundColor Cyan
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
