function Get-DotNetToolsFileInfo () {
    <#
    .SYNOPSIS
        Collects report data for one file under the tools folder.
    .DESCRIPTION
        Returns an object with the relative path, kind, size, timestamps,
        SHA-256, Win32 version resource, Authenticode signer (Windows only),
        runtime config or deps manifest details, and .NET assembly metadata
        for *.dll files. Kind is one of: Managed assembly, Native library,
        Runtime config, Dependency manifest, Other.
    .NOTE
        1. Resolve the file and its path relative to RootDirectory.
        2. Read the SHA-256 hash and the Win32 version resource.
        3. For *.dll, read assembly metadata with Get-DotNetToolsAssemblyInfo.
        4. For *.runtimeconfig.json and *.deps.json, read the JSON details.
        5. Resolve Kind and return the object.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, HelpMessage = 'Absolute path to the file to collect report data for.')]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true, HelpMessage = 'Scan root the reported relative path is computed against.')]
        [ValidateNotNullOrEmpty()]
        [string]$RootDirectory
    )

    Begin {
        if ($PSBoundParameters.ContainsKey('Verbose') -or $VerbosePreference -eq 'Continue') {
            $PSBoundParameters | Out-String | Write-Host
        }
    }

    Process {

        $item = Get-Item -LiteralPath $Path
        $relativePath = [System.IO.Path]::GetRelativePath($RootDirectory, $item.FullName).Replace('\', '/')
        $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($item.FullName)
        $assembly = $null
        $json = $null

        if ($item.Extension -eq '.dll') {
            $assembly = Get-DotNetToolsAssemblyInfo -Path $item.FullName
        }

        if ($item.Name.EndsWith('.runtimeconfig.json') -or $item.Name.EndsWith('.deps.json')) {
            $json = Get-Content -LiteralPath $item.FullName -Raw | ConvertFrom-Json
        }

        $kind = Resolve-DotNetToolsFileKind -Name $item.Name -Assembly $assembly

        $runtimeConfig = $null
        $depsTarget = $null

        if ($kind -eq 'Runtime config') {
            $runtimeConfig = $json.runtimeOptions
        }
        elseif ($kind -eq 'Dependency manifest') {
            $depsTarget = $json.runtimeTarget.name
        }

        return [pscustomobject]@{
            Name                = $item.Name
            RelativePath        = $relativePath
            Kind                = $kind
            Length              = $item.Length
            LastWriteUtc        = $item.LastWriteTimeUtc
            Sha256              = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            Win32FileVersion    = $versionInfo.FileVersion
            Win32ProductVersion = $versionInfo.ProductVersion
            OriginalFilename    = $versionInfo.OriginalFilename
            Signer              = Get-DotNetToolsSigner -Path $item.FullName
            Assembly            = $assembly
            RuntimeConfig       = $runtimeConfig
            DepsTarget          = $depsTarget
        }
    }
}

function Resolve-DotNetToolsFileKind () {
    <#
    .SYNOPSIS
        Classifies a tools-folder file for the report.
    .DESCRIPTION
        Returns 'Managed assembly', 'Native library', 'Runtime config',
        'Dependency manifest', or 'Other'. A *.dll without .NET metadata is
        reported as a native library.
    .NOTE
        1. Managed assembly when Assembly.IsManaged is true.
        2. Runtime config or dependency manifest by file-name suffix.
        3. Native library for *.so, *.dylib, and unmanaged *.dll.
        4. Otherwise Other.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, HelpMessage = 'File name (with extension) used to classify the file.')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $false, HelpMessage = 'Assembly info from Get-DotNetToolsAssemblyInfo; when IsManaged the file is a managed assembly.')]
        [object]$Assembly
    )

    Begin {
        if ($PSBoundParameters.ContainsKey('Verbose') -or $VerbosePreference -eq 'Continue') {
            $PSBoundParameters | Out-String | Write-Host
        }
    }

    Process {

        if ($Assembly -and $Assembly.IsManaged) {
            return 'Managed assembly'
        }

        if ($Name.EndsWith('.runtimeconfig.json')) {
            return 'Runtime config'
        }

        if ($Name.EndsWith('.deps.json')) {
            return 'Dependency manifest'
        }

        if ($Name -match '\.(so|dylib|dll)$' -or $Name -match '\.so\.\d') {
            return 'Native library'
        }

        return 'Other'
    }
}

function Get-DotNetToolsSigner () {
    <#
    .SYNOPSIS
        Returns the Authenticode signer summary for a binary.
    .DESCRIPTION
        Returns '<status>: <subject CN>' for *.dll and *.exe files on Windows.
        Returns $null on other platforms, for other file types (ELF .so files
        cannot carry Authenticode), and when Get-AuthenticodeSignature is
        unavailable.
    .NOTE
        1. Return $null when not on Windows or the file is not a PE binary.
        2. Read the signature and return status plus signer common name.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, HelpMessage = 'Absolute path to the binary whose Authenticode signer is read.')]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    Begin {
        if ($PSBoundParameters.ContainsKey('Verbose') -or $VerbosePreference -eq 'Continue') {
            $PSBoundParameters | Out-String | Write-Host
        }
    }

    Process {

        $isBinary = $Path -match '\.(dll|exe)$'
        $hasCmdlet = $null -ne (Get-Command -Name 'Get-AuthenticodeSignature' -ErrorAction SilentlyContinue)

        if (-not $IsWindows -or -not $isBinary -or -not $hasCmdlet) {
            return $null
        }

        $signature = Get-AuthenticodeSignature -LiteralPath $Path
        if (-not $signature.SignerCertificate) {
            return $signature.Status.ToString()
        }

        $subject = $signature.SignerCertificate.GetNameInfo([System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
        return "$($signature.Status): $subject"
    }
}
