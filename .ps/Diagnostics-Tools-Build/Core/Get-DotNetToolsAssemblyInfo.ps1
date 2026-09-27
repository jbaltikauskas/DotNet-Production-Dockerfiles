function Get-DotNetToolsAssemblyInfo () {
    <#
    .SYNOPSIS
        Reads .NET assembly identity and attribute metadata from a file.
    .DESCRIPTION
        Opens the file with System.Reflection.Metadata. The assembly is not
        loaded, so the file is not locked and any target framework works.
        Returns an object with IsManaged set to $false for files that are not
        PE images or have no .NET metadata (for example native libraries).
        Throws when a PE image with metadata cannot be read.
    .REMARKS
        1. Return IsManaged = $false when the file does not start with 'MZ'.
        2. Open a PEReader and return IsManaged = $false when there is no metadata.
        3. Read the assembly definition, PE headers, and module MVID.
        4. Read string attributes with Get-DotNetToolsAssemblyAttributes.
        5. Return the combined object.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    Begin {
        if ($PSBoundParameters.ContainsKey('Verbose') -or $VerbosePreference -eq 'Continue') {
            $PSBoundParameters | Out-String | Write-Host
        }
    }

    Process {

        $notManaged = [pscustomobject]@{ IsManaged = $false }

        if (-not (Test-DotNetToolsPortableExecutable -Path $Path)) {
            return $notManaged
        }

        $stream = [System.IO.File]::OpenRead($Path)
        try {

            $peReader = [System.Reflection.PortableExecutable.PEReader]::new($stream)
            if (-not $peReader.HasMetadata) {
                return $notManaged
            }

            $reader = [System.Reflection.Metadata.PEReaderExtensions]::GetMetadataReader($peReader)
            if (-not $reader.IsAssembly) {
                return $notManaged
            }

            $headers = $peReader.PEHeaders
            $corFlags = $headers.CorHeader.Flags
            $assemblyName = [System.Reflection.AssemblyName]::GetAssemblyName($Path)
            $tokenBytes = $assemblyName.GetPublicKeyToken()
            $attributes = Get-DotNetToolsAssemblyAttributes -Reader $reader

            return [pscustomobject]@{
                IsManaged            = $true
                AssemblyName         = $assemblyName.Name
                AssemblyVersion      = $assemblyName.Version.ToString()
                Culture              = $assemblyName.CultureName
                PublicKeyToken       = ($tokenBytes | ForEach-Object { $_.ToString('x2') }) -join ''
                FileVersion          = $attributes['FileVersion']
                InformationalVersion = $attributes['InformationalVersion']
                Title                = $attributes['Title']
                Description          = $attributes['Description']
                Company              = $attributes['Company']
                Product              = $attributes['Product']
                Copyright            = $attributes['Copyright']
                Trademark            = $attributes['Trademark']
                Configuration        = $attributes['Configuration']
                NeutralLanguage      = $attributes['NeutralLanguage']
                TargetFramework      = $attributes['TargetFramework']
                Tfm                  = ConvertTo-DotNetToolsTfm -FrameworkName $attributes['TargetFramework']
                Metadata             = $attributes['Metadata']
                Machine              = $headers.CoffHeader.Machine.ToString()
                Platform             = Resolve-DotNetToolsPlatform -Machine $headers.CoffHeader.Machine -CorFlags $corFlags
                IsILOnly             = [bool]($corFlags -band [System.Reflection.PortableExecutable.CorFlags]::ILOnly)
                Requires32Bit        = [bool]($corFlags -band [System.Reflection.PortableExecutable.CorFlags]::Requires32Bit)
                IsStrongNameSigned   = [bool]($corFlags -band [System.Reflection.PortableExecutable.CorFlags]::StrongNameSigned)
                Mvid                 = $reader.GetGuid($reader.GetModuleDefinition().Mvid).ToString()
                ReferenceCount       = $reader.AssemblyReferences.Count
            }
        }
        finally {
            $stream.Dispose()
        }
    }
}

function Resolve-DotNetToolsPlatform () {
    <#
    .SYNOPSIS
        Returns the build platform label for a managed PE image.
    .DESCRIPTION
        Returns 'AnyCPU', 'AnyCPU (32-bit preferred)', 'x86', or the machine
        name (for example 'Amd64' or 'Arm64') for platform-specific images.
    .REMARKS
        1. I386 + ILOnly without Requires32Bit is AnyCPU.
        2. I386 + ILOnly + Requires32Bit + Prefers32Bit is AnyCPU 32-bit preferred.
        3. Other I386 images are x86; other machines return their name.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [System.Reflection.PortableExecutable.Machine]$Machine,

        [Parameter(Mandatory = $true)]
        [System.Reflection.PortableExecutable.CorFlags]$CorFlags
    )

    Begin {
        if ($PSBoundParameters.ContainsKey('Verbose') -or $VerbosePreference -eq 'Continue') {
            $PSBoundParameters | Out-String | Write-Host
        }
    }

    Process {

        if ($Machine -ne [System.Reflection.PortableExecutable.Machine]::I386) {
            return $Machine.ToString()
        }

        $flags = [System.Reflection.PortableExecutable.CorFlags]
        $isILOnly = [bool]($CorFlags -band $flags::ILOnly)
        $requires32Bit = [bool]($CorFlags -band $flags::Requires32Bit)
        $prefers32Bit = [bool]($CorFlags -band $flags::Prefers32Bit)

        if ($isILOnly -and -not $requires32Bit) {
            return 'AnyCPU'
        }

        if ($isILOnly -and $prefers32Bit) {
            return 'AnyCPU (32-bit preferred)'
        }

        return 'x86'
    }
}

function Test-DotNetToolsPortableExecutable () {
    <#
    .SYNOPSIS
        Tests whether a file starts with the 'MZ' PE signature.
    .DESCRIPTION
        Returns $true when the first two bytes are 'MZ'; otherwise $false.
        Never throws for short or empty files.
    .REMARKS
        1. Read up to two bytes from the start of the file.
        2. Return $true when they equal 0x4D 0x5A.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    Begin {
        if ($PSBoundParameters.ContainsKey('Verbose') -or $VerbosePreference -eq 'Continue') {
            $PSBoundParameters | Out-String | Write-Host
        }
    }

    Process {

        $bytes = [byte[]]::new(2)
        $stream = [System.IO.File]::OpenRead($Path)
        try {

            $read = $stream.Read($bytes, 0, 2)
        }
        finally {
            $stream.Dispose()
        }

        return ($read -eq 2 -and $bytes[0] -eq 0x4D -and $bytes[1] -eq 0x5A)
    }
}

function Get-DotNetToolsAssemblyAttributes () {
    <#
    .SYNOPSIS
        Reads string-valued assembly-level attributes from metadata.
    .DESCRIPTION
        Returns a hashtable keyed by short names (FileVersion,
        InformationalVersion, Title, Company, ...). AssemblyMetadata attributes
        are returned as an ordered dictionary under the 'Metadata' key.
        Attribute blobs are decoded directly: every mapped attribute has a
        single string constructor argument, and AssemblyMetadata has two.
    .REMARKS
        1. Walk the assembly definition custom attributes.
        2. Resolve each attribute type name; skip names that are not mapped.
        3. Skip blobs without the 0x0001 prolog.
        4. Read one serialized string (two for AssemblyMetadata).
        5. Return the hashtable.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [System.Reflection.Metadata.MetadataReader]$Reader
    )

    Begin {
        if ($PSBoundParameters.ContainsKey('Verbose') -or $VerbosePreference -eq 'Continue') {
            $PSBoundParameters | Out-String | Write-Host
        }
    }

    Process {

        $attributeMap = @{
            'AssemblyFileVersionAttribute'          = 'FileVersion'
            'AssemblyInformationalVersionAttribute' = 'InformationalVersion'
            'AssemblyTitleAttribute'                = 'Title'
            'AssemblyDescriptionAttribute'          = 'Description'
            'AssemblyCompanyAttribute'              = 'Company'
            'AssemblyProductAttribute'              = 'Product'
            'AssemblyCopyrightAttribute'            = 'Copyright'
            'AssemblyTrademarkAttribute'            = 'Trademark'
            'AssemblyConfigurationAttribute'        = 'Configuration'
            'NeutralResourcesLanguageAttribute'     = 'NeutralLanguage'
            'TargetFrameworkAttribute'              = 'TargetFramework'
            'AssemblyMetadataAttribute'             = 'Metadata'
        }

        $result = @{ Metadata = [ordered]@{} }

        foreach ($handle in $Reader.GetAssemblyDefinition().GetCustomAttributes()) {
            $attribute = $Reader.GetCustomAttribute($handle)
            $typeName = Get-DotNetToolsAttributeTypeName -Reader $Reader -Attribute $attribute
            if (-not $typeName -or -not $attributeMap.ContainsKey($typeName)) {
                continue
            }

            $blob = $Reader.GetBlobReader($attribute.Value)
            if ($blob.Length -lt 2 -or $blob.ReadUInt16() -ne 1) {
                continue
            }

            $key = $attributeMap[$typeName]
            $firstValue = $blob.ReadSerializedString()

            if ($key -eq 'Metadata') {
                $result.Metadata[$firstValue] = $blob.ReadSerializedString()
            }
            else {
                $result[$key] = $firstValue
            }
        }

        return $result
    }
}

function Get-DotNetToolsAttributeTypeName () {
    <#
    .SYNOPSIS
        Returns the simple type name of a custom attribute.
    .DESCRIPTION
        Resolves the attribute constructor to its declaring type. Handles
        constructors defined in another assembly (MemberReference) and in the
        same assembly (MethodDefinition). Returns $null for other shapes.
    .REMARKS
        1. For MemberReference constructors, return the parent TypeReference name.
        2. For MethodDefinition constructors, return the declaring TypeDefinition name.
        3. Otherwise return $null.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [System.Reflection.Metadata.MetadataReader]$Reader,

        [Parameter(Mandatory = $true)]
        [System.Reflection.Metadata.CustomAttribute]$Attribute
    )

    Begin {
        if ($PSBoundParameters.ContainsKey('Verbose') -or $VerbosePreference -eq 'Continue') {
            $PSBoundParameters | Out-String | Write-Host
        }
    }

    Process {

        $constructor = $Attribute.Constructor

        if ($constructor.Kind -eq [System.Reflection.Metadata.HandleKind]::MemberReference) {
            $memberReference = $Reader.GetMemberReference([System.Reflection.Metadata.MemberReferenceHandle]$constructor)
            if ($memberReference.Parent.Kind -ne [System.Reflection.Metadata.HandleKind]::TypeReference) {
                return $null
            }

            $typeReference = $Reader.GetTypeReference([System.Reflection.Metadata.TypeReferenceHandle]$memberReference.Parent)
            return $Reader.GetString($typeReference.Name)
        }

        if ($constructor.Kind -eq [System.Reflection.Metadata.HandleKind]::MethodDefinition) {
            $methodDefinition = $Reader.GetMethodDefinition([System.Reflection.Metadata.MethodDefinitionHandle]$constructor)
            $typeDefinition = $Reader.GetTypeDefinition($methodDefinition.GetDeclaringType())
            return $Reader.GetString($typeDefinition.Name)
        }

        return $null
    }
}

function ConvertTo-DotNetToolsTfm () {
    <#
    .SYNOPSIS
        Converts a TargetFrameworkAttribute value to a short TFM.
    .DESCRIPTION
        Maps '.NETCoreApp,Version=v8.0' to 'net8.0', '.NETStandard,Version=v2.0'
        to 'netstandard2.0', and '.NETFramework,Version=v4.6.2' to 'net462'.
        Returns the input unchanged when it does not match, and $null for empty input.
    .REMARKS
        1. Return $null for empty input.
        2. Match the identifier and version, then build the short name.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $false)]
        [string]$FrameworkName
    )

    Begin {
        if ($PSBoundParameters.ContainsKey('Verbose') -or $VerbosePreference -eq 'Continue') {
            $PSBoundParameters | Out-String | Write-Host
        }
    }

    Process {

        if ([string]::IsNullOrWhiteSpace($FrameworkName)) {
            return $null
        }

        if ($FrameworkName -notmatch '^(?<id>[^,]+),Version=v(?<version>[\d\.]+)') {
            return $FrameworkName
        }

        $version = $Matches['version']

        switch ($Matches['id']) {
            '.NETCoreApp' {
                return "net$version"
            }
            '.NETStandard' {
                return "netstandard$version"
            }
            '.NETFramework' {
                return "net$($version.Replace('.', ''))"
            }
        }

        return $FrameworkName
    }
}
