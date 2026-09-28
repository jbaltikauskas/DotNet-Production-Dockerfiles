function New-DotNetToolsMarkdownTable () {
    <#
    .SYNOPSIS
        Builds GitHub-flavored markdown table lines.
    .DESCRIPTION
        Returns a string array: header row, separator row, then one row per
        entry in Rows. Every cell is escaped with ConvertTo-DotNetToolsMarkdownCell.
        Returns a single '_None._' line when Rows is empty.
    .NOTE
        1. Return '_None._' when there are no rows.
        2. Emit the header and separator rows.
        3. Emit each data row with escaped cells.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, HelpMessage = 'Column header cells for the table, one per column.')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Headers,

        [Parameter(Mandatory = $true, HelpMessage = 'Data rows, each a string array with one cell per column. May be empty.')]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string[]]]$Rows
    )

    Begin {
        if ($PSBoundParameters.ContainsKey('Verbose') -or $VerbosePreference -eq 'Continue') {
            $PSBoundParameters | Out-String | Write-Host
        }
    }

    Process {

        if ($Rows.Count -eq 0) {
            return @('_None._')
        }

        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add('| ' + ($Headers -join ' | ') + ' |')
        $lines.Add('|' + (($Headers | ForEach-Object { ' --- ' }) -join '|') + '|')

        foreach ($row in $Rows) {
            $cells = $row | ForEach-Object { ConvertTo-DotNetToolsMarkdownCell -Value $_ }
            $lines.Add('| ' + ($cells -join ' | ') + ' |')
        }

        return $lines.ToArray()
    }
}

function ConvertTo-DotNetToolsMarkdownCell () {
    <#
    .SYNOPSIS
        Escapes a value for use inside a markdown table cell.
    .DESCRIPTION
        Returns '—' for null or empty values. Escapes '|' and replaces line
        breaks with spaces so the value cannot break the table layout.
    .NOTE
        1. Return '—' for empty input.
        2. Collapse line breaks and escape pipes.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $false, HelpMessage = 'The cell value to escape. Null or empty becomes an em dash.')]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Value
    )

    Begin {
        if ($PSBoundParameters.ContainsKey('Verbose') -or $VerbosePreference -eq 'Continue') {
            $PSBoundParameters | Out-String | Write-Host
        }
    }

    Process {

        if ([string]::IsNullOrWhiteSpace($Value)) {
            return '—'
        }

        return ($Value -replace '\r?\n', ' ').Replace('|', '\|')
    }
}

function Format-DotNetToolsFileSize () {
    <#
    .SYNOPSIS
        Formats a byte count as B, KB, or MB.
    .DESCRIPTION
        Uses 1024-based units with one decimal place for KB and MB.
    .NOTE
        1. Pick the largest unit that keeps the value at or above 1.
        2. Return the formatted string.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, HelpMessage = 'File size in bytes to format as B, KB, or MB.')]
        [ValidateRange(0, [long]::MaxValue)]
        [long]$Bytes
    )

    Begin {
        if ($PSBoundParameters.ContainsKey('Verbose') -or $VerbosePreference -eq 'Continue') {
            $PSBoundParameters | Out-String | Write-Host
        }
    }

    Process {

        if ($Bytes -ge 1MB) {
            return '{0:N1} MB' -f ($Bytes / 1MB)
        }

        if ($Bytes -ge 1KB) {
            return '{0:N1} KB' -f ($Bytes / 1KB)
        }

        return "$Bytes B"
    }
}
