function Get-DotNetToolsAssemblyInfo () {
    <#
    .SYNOPSIS
        Reads .NET assembly identity and attribute metadata from a file.
    .DESCRIPTION
        Opens the file with System.Reflection.Metadata. The assembly is not
        loaded, so the file is not locked and any target framework works.
        Returns an object with IsManaged set to $false when the image has no
        .NET metadata or is not an assembly (for example native libraries).
        Throws when the file is not a PE image, or when a PE image with
        metadata cannot be read.
    .NOTE
        1. Open a PEReader and return IsManaged = $false when there is no metadata.
        2. Return IsManaged = $false when the image is not an assembly.
        3. Read the assembly definition, the strong-name flag, and referenced assembly names.
        4. Read string attributes with Get-DotNetToolsAssemblyAttributes.
        5. Return the combined object.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, HelpMessage = 'Absolute path to the file to inspect.')]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    Begin {
        Write-Verbose ("BEGIN: {0}" -f $MyInvocation.MyCommand.Name)
        Write-Verbose ($PSBoundParameters | Out-String)
    }

    Process {

        $notManaged = [pscustomobject]@{ IsManaged = $false }

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

            $corFlags = $peReader.PEHeaders.CorHeader.Flags
            $assemblyName = [System.Reflection.AssemblyName]::GetAssemblyName($Path)
            $tokenBytes = $assemblyName.GetPublicKeyToken()
            $attributes = Get-DotNetToolsAssemblyAttributes -Reader $reader
            $assemblyReferences = [System.Collections.Generic.List[string]]::new()

            foreach ($handle in $reader.AssemblyReferences) {
                $reference = $reader.GetAssemblyReference($handle)
                $assemblyReferences.Add($reader.GetString($reference.Name))
            }

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
                IsStrongNameSigned   = [bool]($corFlags -band [System.Reflection.PortableExecutable.CorFlags]::StrongNameSigned)
                AssemblyReferences   = $assemblyReferences.ToArray()
                ReferenceCount       = $assemblyReferences.Count
            }
        }
        finally {
            $stream.Dispose()
        }
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
    .NOTE
        1. Walk the assembly definition custom attributes.
        2. Resolve each attribute type name; skip names that are not mapped.
        3. Skip blobs without the 0x0001 prolog.
        4. Read one serialized string (two for AssemblyMetadata).
        5. Return the hashtable.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, HelpMessage = 'The metadata reader opened on the assembly.')]
        [System.Reflection.Metadata.MetadataReader]$Reader
    )

    Begin {
        Write-Verbose ("BEGIN: {0}" -f $MyInvocation.MyCommand.Name)
        Write-Verbose ($PSBoundParameters | Out-String)
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
    .NOTE
        1. For MemberReference constructors, return the parent TypeReference name.
        2. For MethodDefinition constructors, return the declaring TypeDefinition name.
        3. Otherwise return $null.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, HelpMessage = 'The metadata reader opened on the assembly.')]
        [System.Reflection.Metadata.MetadataReader]$Reader,

        [Parameter(Mandatory = $true, HelpMessage = 'The custom attribute whose declaring type name is resolved.')]
        [System.Reflection.Metadata.CustomAttribute]$Attribute
    )

    Begin {
        Write-Verbose ("BEGIN: {0}" -f $MyInvocation.MyCommand.Name)
        Write-Verbose ($PSBoundParameters | Out-String)
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
    .NOTE
        1. Return $null for empty input.
        2. Match the identifier and version, then build the short name.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $false, HelpMessage = 'A TargetFrameworkAttribute value such as ".NETCoreApp,Version=v8.0".')]
        [string]$FrameworkName
    )

    Begin {
        Write-Verbose ("BEGIN: {0}" -f $MyInvocation.MyCommand.Name)
        Write-Verbose ($PSBoundParameters | Out-String)
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
