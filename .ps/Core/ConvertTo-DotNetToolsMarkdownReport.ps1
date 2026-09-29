function ConvertTo-DotNetToolsMarkdownReport () {
    <#
    .SYNOPSIS
        Builds the full markdown report for the scanned tools folder.
    .DESCRIPTION
        Returns one markdown string. Sections, in order: header and totals,
        assembly attribute reference, diagnostic tools, managed assembly
        summary, per-assembly details, native and other files, warnings.
    .NOTE
        1. Split Files into managed and other files, sorted by relative path.
        2. Collect lines from each section builder.
        3. Join the lines with LF and return the text.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, HelpMessage = 'Collected file-info objects from Get-DotNetToolsFileInfo.')]
        [AllowEmptyCollection()]
        [object[]]$Files,

        [Parameter(Mandatory = $true, HelpMessage = 'Records of files that could not be read, each with RelativePath and Message.')]
        [AllowEmptyCollection()]
        [object[]]$Failures,

        [Parameter(Mandatory = $true, HelpMessage = 'Absolute path of the scanned folder, shown in the report header.')]
        [ValidateNotNullOrEmpty()]
        [string]$ToolsDirectory
    )

    Begin {
        Write-Verbose ("BEGIN: {0}" -f $MyInvocation.MyCommand.Name)
        Write-Verbose ($PSBoundParameters | Out-String)
    }

    Process {

        $sortedFiles = @($Files | Sort-Object -Property RelativePath)
        $managedFiles = @($sortedFiles | Where-Object { $_.Kind -eq 'Managed assembly' })
        $otherFiles = @($sortedFiles | Where-Object { $_.Kind -ne 'Managed assembly' })

        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.AddRange([string[]](Get-DotNetToolsReportHeaderSection -Files $sortedFiles -Failures $Failures -ToolsDirectory $ToolsDirectory))
        $lines.AddRange([string[]](Get-DotNetToolsReportReferenceSection))
        $lines.AddRange([string[]](Get-DotNetToolsReportToolSection -Files $sortedFiles))
        $lines.AddRange([string[]](Get-DotNetToolsReportAssemblySection -ManagedFiles $managedFiles))
        $lines.AddRange([string[]](Get-DotNetToolsReportDetailSection -ManagedFiles $managedFiles))
        $lines.AddRange([string[]](Get-DotNetToolsReportOtherFileSection -OtherFiles $otherFiles))
        $lines.AddRange([string[]](Get-DotNetToolsReportWarningSection -ManagedFiles $managedFiles -Failures $Failures))

        return ($lines -join "`n") + "`n"
    }
}

function Get-DotNetToolsReportHeaderSection () {
    <#
    .SYNOPSIS
        Returns the report title, run context, and totals by kind.
    .DESCRIPTION
        Includes generation time (UTC), scanned folder, PowerShell and OS
        versions, a file count and size per kind, and unreadable file count.
    .NOTE
        1. Emit the title and run context list.
        2. Group files by kind and emit the totals table.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, HelpMessage = 'Collected file-info objects from Get-DotNetToolsFileInfo.')]
        [AllowEmptyCollection()]
        [object[]]$Files,

        [Parameter(Mandatory = $true, HelpMessage = 'Records of files that could not be read, each with RelativePath and Message.')]
        [AllowEmptyCollection()]
        [object[]]$Failures,

        [Parameter(Mandatory = $true, HelpMessage = 'Absolute path of the scanned folder, shown in the report header.')]
        [ValidateNotNullOrEmpty()]
        [string]$ToolsDirectory
    )

    Begin {
        Write-Verbose ("BEGIN: {0}" -f $MyInvocation.MyCommand.Name)
        Write-Verbose ($PSBoundParameters | Out-String)
    }

    Process {

        $rows = [System.Collections.Generic.List[string[]]]::new()

        foreach ($group in ($Files | Group-Object -Property Kind | Sort-Object -Property Name)) {
            $bytes = ($group.Group | Measure-Object -Property Length -Sum).Sum
            $rows.Add([string[]]@($group.Name, $group.Count, (Format-DotNetToolsFileSize -Bytes $bytes)))
        }

        $totalBytes = ($Files | Measure-Object -Property Length -Sum).Sum
        $rows.Add([string[]]@('**Total**', "**$($Files.Count)**", "**$(Format-DotNetToolsFileSize -Bytes ([long]$totalBytes))**"))

        $lines = @(
            '# .NET Tools Artifact Report'
            ''
            "- **Generated (UTC):** $([DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss'))"
            "- **Scanned folder:** ``$ToolsDirectory``"
            "- **PowerShell:** $($PSVersionTable.PSVersion) on $([System.Runtime.InteropServices.RuntimeInformation]::OSDescription.Trim())"
            "- **Unreadable files:** $($Failures.Count)"
            ''
            '## Contents by kind'
            ''
        )

        $lines += New-DotNetToolsMarkdownTable -Headers @('Kind', 'Files', 'Size') -Rows $rows
        $lines += ''
        return $lines
    }
}

function Get-DotNetToolsReportReferenceSection () {
    <#
    .SYNOPSIS
        Returns the static explainer for the assembly attributes in the report.
    .DESCRIPTION
        Explains the three version attributes and the descriptive attributes,
        and where each one shows up (runtime binding, Windows file properties).
    .NOTE
        1. Return the fixed markdown lines.
    #>

    Begin {
        Write-Verbose ("BEGIN: {0}" -f $MyInvocation.MyCommand.Name)
    }

    Process {

        return @(
            '## Assembly attribute reference'
            ''
            'In C#, assembly (DLL) attributes carry the metadata, versioning, and file details that the .NET runtime uses and that Windows shows in **File Properties → Details**.'
            ''
            '| Attribute | Purpose |'
            '| --- | --- |'
            '| `AssemblyVersion` | Version used by the .NET runtime for assembly identity, binding, and strong-name resolution. Change it only for major or breaking changes. |'
            '| `AssemblyFileVersion` | Physical build version of the file. Shown as **File version** in Windows File Properties → Details. Good for tracking individual builds. |'
            '| `AssemblyInformationalVersion` | Free-form product release label. Supports Semantic Versioning (`1.0.0-beta.2`) and build metadata such as a git commit hash (`1.0.0+abc123`). Shown as **Product version**. |'
            '| `AssemblyTitle` | Friendly name of the assembly. Shown as **File description** in Windows. |'
            '| `AssemblyDescription` | Longer description of what the assembly does. |'
            '| `AssemblyCompany` / `AssemblyProduct` | Publisher and product name. |'
            '| `AssemblyCopyright` / `AssemblyTrademark` | Legal notices. |'
            '| `AssemblyConfiguration` | Build configuration, for example `Release` or `Debug`. |'
            '| `TargetFramework` | Framework the assembly was compiled for, for example `net8.0` or `netstandard2.0`. |'
            '| `AssemblyMetadata` | Free-form key/value pairs, for example `RepositoryUrl`. |'
            ''
            'Other columns: **Public key token** identifies the strong-name key; **Assembly references** lists each referenced assembly name; **Signer** is the Authenticode signature status (Windows only).'
            ''
        )
    }
}

function Get-DotNetToolsReportToolSection () {
    <#
    .SYNOPSIS
        Returns the table of diagnostic tool entry points.
    .DESCRIPTION
        A tool is a managed assembly with a sibling <name>.runtimeconfig.json.
        Each row shows the tool versions and the shared framework it runs on.
    .NOTE
        1. Find runtime config files and their matching managed assembly.
        2. Read framework name, version, and rollForward from the config.
        3. Emit the table.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, HelpMessage = 'Collected file-info objects from Get-DotNetToolsFileInfo.')]
        [AllowEmptyCollection()]
        [object[]]$Files
    )

    Begin {
        Write-Verbose ("BEGIN: {0}" -f $MyInvocation.MyCommand.Name)
        Write-Verbose ($PSBoundParameters | Out-String)
    }

    Process {

        $rows = [System.Collections.Generic.List[string[]]]::new()

        foreach ($config in ($Files | Where-Object { $_.Kind -eq 'Runtime config' })) {
            $toolName = $config.Name.Substring(0, $config.Name.Length - '.runtimeconfig.json'.Length)
            $entryPath = $config.RelativePath -replace '\.runtimeconfig\.json$', '.dll'
            $entry = $Files | Where-Object { $_.RelativePath -eq $entryPath -and $_.Kind -eq 'Managed assembly' } | Select-Object -First 1
            $frameworks = @($config.RuntimeConfig.framework) + @($config.RuntimeConfig.frameworks) | Where-Object { $_ }
            $runtime = ($frameworks | ForEach-Object { "$($_.name) $($_.version)" }) -join ', '

            $rows.Add([string[]]@(
                    "**$toolName**"
                    $entry.Assembly.AssemblyVersion
                    $entry.Assembly.FileVersion
                    $entry.Assembly.InformationalVersion
                    $config.RuntimeConfig.tfm
                    $runtime
                    $config.RuntimeConfig.rollForward
                ))
        }

        $lines = @('## Diagnostic tools', '', 'Entry-point assemblies (those with a `*.runtimeconfig.json`).', '')
        $lines += New-DotNetToolsMarkdownTable `
            -Headers @('Tool', 'AssemblyVersion', 'FileVersion', 'InformationalVersion', 'TFM', 'Runtime', 'Roll forward') `
            -Rows $rows
        $lines += ''
        return $lines
    }
}

function Get-DotNetToolsReportAssemblySection () {
    <#
    .SYNOPSIS
        Returns the one-row-per-assembly version summary table.
    .DESCRIPTION
        Columns: path, AssemblyVersion, FileVersion, InformationalVersion,
        TFM, company, size.
    .NOTE
        1. Build one row per managed file.
        2. Emit the table.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, HelpMessage = 'Managed-assembly file-info objects, sorted by relative path.')]
        [AllowEmptyCollection()]
        [object[]]$ManagedFiles
    )

    Begin {
        Write-Verbose ("BEGIN: {0}" -f $MyInvocation.MyCommand.Name)
        Write-Verbose ($PSBoundParameters | Out-String)
    }

    Process {

        $rows = [System.Collections.Generic.List[string[]]]::new()

        foreach ($file in $ManagedFiles) {
            $assembly = $file.Assembly
            $rows.Add([string[]]@(
                    "``$($file.RelativePath)``"
                    $assembly.AssemblyVersion
                    $assembly.FileVersion
                    $assembly.InformationalVersion
                    $assembly.Tfm
                    $assembly.Company
                    (Format-DotNetToolsFileSize -Bytes $file.Length)
                ))
        }

        $lines = @('## Managed assemblies', '')
        $lines += New-DotNetToolsMarkdownTable `
            -Headers @('File', 'AssemblyVersion', 'FileVersion', 'InformationalVersion', 'TFM', 'Company', 'Size') `
            -Rows $rows
        $lines += ''
        return $lines
    }
}

function Get-DotNetToolsReportDetailSection () {
    <#
    .SYNOPSIS
        Returns a collapsible details block per managed assembly.
    .DESCRIPTION
        Each block lists every collected attribute and file property as a
        two-column Property / Value table inside <details>.
    .NOTE
        1. For each managed file, build the property rows.
        2. Append AssemblyMetadata key/value pairs.
        3. Append one row per referenced assembly name.
        4. Wrap the table in <details> with the name and version as summary.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, HelpMessage = 'Managed-assembly file-info objects, sorted by relative path.')]
        [AllowEmptyCollection()]
        [object[]]$ManagedFiles
    )

    Begin {
        Write-Verbose ("BEGIN: {0}" -f $MyInvocation.MyCommand.Name)
        Write-Verbose ($PSBoundParameters | Out-String)
    }

    Process {

        $lines = @('## Assembly details', '')

        foreach ($file in $ManagedFiles) {
            $a = $file.Assembly
            $rows = [System.Collections.Generic.List[string[]]]::new()
            $properties = [ordered]@{
                'Path'                         = "``$($file.RelativePath)``"
                'AssemblyVersion'              = $a.AssemblyVersion
                'AssemblyFileVersion'          = $a.FileVersion
                'AssemblyInformationalVersion' = $a.InformationalVersion
                'Title'                        = $a.Title
                'Description'                  = $a.Description
                'Company'                      = $a.Company
                'Product'                      = $a.Product
                'Copyright'                    = $a.Copyright
                'Trademark'                    = $a.Trademark
                'Configuration'                = $a.Configuration
                'Neutral language'             = $a.NeutralLanguage
                'Target framework'             = $a.TargetFramework
                'Culture'                      = $a.Culture
                'Public key token'             = $a.PublicKeyToken
                'Strong-name signed'           = $a.IsStrongNameSigned
                'Assembly references'          = $a.ReferenceCount
                'Win32 file version'           = $file.Win32FileVersion
                'Win32 product version'        = $file.Win32ProductVersion
                'Signer'                       = $file.Signer
                'Size'                         = "$(Format-DotNetToolsFileSize -Bytes $file.Length) ($($file.Length) bytes)"
                'Last write (UTC)'             = $file.LastWriteUtc.ToString('yyyy-MM-dd HH:mm:ss')
                'SHA-256'                      = "``$($file.Sha256)``"
            }

            foreach ($key in $properties.Keys) {
                $rows.Add([string[]]@($key, [string]$properties[$key]))
            }

            foreach ($key in $a.Metadata.Keys) {
                $rows.Add([string[]]@("Metadata: $key", $a.Metadata[$key]))
            }

            foreach ($referenceName in $a.AssemblyReferences) {
                $rows.Add([string[]]@('Assembly reference', $referenceName))
            }

            $summary = [System.Net.WebUtility]::HtmlEncode("$($a.AssemblyName) $($a.AssemblyVersion)")
            $lines += "<details><summary><strong>$summary</strong></summary>"
            $lines += ''
            $lines += New-DotNetToolsMarkdownTable -Headers @('Property', 'Value') -Rows $rows
            $lines += ''
            $lines += '</details>'
            $lines += ''
        }

        return $lines
    }
}

function Get-DotNetToolsReportOtherFileSection () {
    <#
    .SYNOPSIS
        Returns the table of native libraries, JSON manifests, and other files.
    .DESCRIPTION
        Columns: path, kind, detail (TFM/runtime target or Win32 version),
        size, short SHA-256.
    .NOTE
        1. Resolve a per-kind detail value.
        2. Emit one row per file.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, HelpMessage = 'Non-managed file-info objects (native libraries, JSON manifests, and other files).')]
        [AllowEmptyCollection()]
        [object[]]$OtherFiles
    )

    Begin {
        Write-Verbose ("BEGIN: {0}" -f $MyInvocation.MyCommand.Name)
        Write-Verbose ($PSBoundParameters | Out-String)
    }

    Process {

        $rows = [System.Collections.Generic.List[string[]]]::new()

        foreach ($file in $OtherFiles) {
            $detail = $file.Win32FileVersion

            if ($file.Kind -eq 'Runtime config') {
                $detail = "tfm $($file.RuntimeConfig.tfm)"
            }
            elseif ($file.Kind -eq 'Dependency manifest') {
                $detail = "target $($file.DepsTarget)"
            }

            $rows.Add([string[]]@(
                    "``$($file.RelativePath)``"
                    $file.Kind
                    $detail
                    (Format-DotNetToolsFileSize -Bytes $file.Length)
                    "``$($file.Sha256.Substring(0, 16))``"
                ))
        }

        $lines = @('## Native libraries and other files', '')
        $lines += New-DotNetToolsMarkdownTable -Headers @('File', 'Kind', 'Detail', 'Size', 'SHA-256 (first 16)') -Rows $rows
        $lines += ''
        return $lines
    }
}

function Get-DotNetToolsReportWarningSection () {
    <#
    .SYNOPSIS
        Returns the warnings list.
    .DESCRIPTION
        Reports unreadable files, assemblies without a file or informational
        version, assemblies whose Authenticode status is not Valid, and
        assembly names present with more than one AssemblyVersion.
    .NOTE
        1. Collect warnings from each rule.
        2. Emit a bullet list, or '_None._' when empty.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, HelpMessage = 'Managed-assembly file-info objects, sorted by relative path.')]
        [AllowEmptyCollection()]
        [object[]]$ManagedFiles,

        [Parameter(Mandatory = $true, HelpMessage = 'Records of files that could not be read, each with RelativePath and Message.')]
        [AllowEmptyCollection()]
        [object[]]$Failures
    )

    Begin {
        Write-Verbose ("BEGIN: {0}" -f $MyInvocation.MyCommand.Name)
        Write-Verbose ($PSBoundParameters | Out-String)
    }

    Process {

        $warnings = [System.Collections.Generic.List[string]]::new()

        foreach ($failure in $Failures) {
            $warnings.Add("Could not read ``$($failure.RelativePath)``: $($failure.Message)")
        }

        foreach ($file in $ManagedFiles) {
            if (-not $file.Assembly.FileVersion) {
                $warnings.Add("``$($file.RelativePath)`` has no AssemblyFileVersion.")
            }

            if (-not $file.Assembly.InformationalVersion) {
                $warnings.Add("``$($file.RelativePath)`` has no AssemblyInformationalVersion.")
            }

            if ($file.Signer -and -not $file.Signer.StartsWith('Valid')) {
                $warnings.Add("``$($file.RelativePath)`` Authenticode status: $($file.Signer).")
            }
        }

        foreach ($group in ($ManagedFiles | Group-Object -Property { $_.Assembly.AssemblyName })) {
            $versions = @($group.Group | ForEach-Object { $_.Assembly.AssemblyVersion } | Sort-Object -Unique)
            if ($versions.Count -gt 1) {
                $warnings.Add("``$($group.Name)`` is present with different AssemblyVersion values: $($versions -join ', ').")
            }
        }

        $lines = @('## Warnings', '')

        if ($warnings.Count -eq 0) {
            $lines += '_None._'
        }
        else {
            $lines += $warnings | ForEach-Object { "- $_" }
        }

        return $lines
    }
}
