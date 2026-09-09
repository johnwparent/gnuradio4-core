<#
    .SYNOPSIS
        Reads and maintains the shared GNU Radio 4 install manifest.

    .DESCRIPTION
        Every GNU Radio 4 installer (gr-core, gr-library, ... and the combined
        superbuild installer) shares one manifest per plugin API version.  It
        records where the runtime libraries and the plugins live, plus the
        version of every component and plugin that is currently installed.

        Results are written as 'key=value' lines to -OutFile (UTF-8) so the
        caller does not depend on console encoding or redirection.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet('query', 'register', 'unregister')][string] $Action,
    [Parameter(Mandatory = $true)][string] $ManifestPath,
    [string] $OutFile = '',
    [string] $ApiVersion = '',
    [string] $InstallRoot = '',
    [string] $PluginRoot = '',
    # '|'-separated 'name=version' pairs, e.g. 'gr-core=4.0.0|gr-library=4.0.0'
    [string] $Components = '',
    [string] $Plugins = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:schemaVersion = 1
$script:resultLines = New-Object System.Collections.Generic.List[string]

function Add-ResultLine {
    param([string] $Key, [string] $Value)
    $script:resultLines.Add("$Key=$Value")
}

function Write-Result {
    $text = ($script:resultLines -join "`r`n") + "`r`n"
    if ([string]::IsNullOrEmpty($OutFile)) {
        Write-Output $text
        return
    }
    [System.IO.File]::WriteAllText($OutFile, $text, (New-Object System.Text.UTF8Encoding($false)))
}

function ConvertTo-OrderedDictionary {
    param($InputObject)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $converted = [ordered]@{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $converted[$property.Name] = ConvertTo-OrderedDictionary $property.Value
        }
        return $converted
    }
    return $InputObject
}

function Read-Manifest {
    # -Repair moves an unparseable manifest aside so a fresh one can be written;
    # reads that only report never mutate what is on disc
    param([switch] $Repair)

    if (-not (Test-Path -LiteralPath $ManifestPath)) { return $null }
    # the manifest is written as UTF-8 without a BOM; without -Encoding, Windows
    # PowerShell decodes it as ANSI and mangles non-ASCII install paths
    $raw = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }

    try {
        return ConvertTo-OrderedDictionary (ConvertFrom-Json $raw)
    } catch {
        Add-ResultLine 'manifest-unreadable' '1'
        if (-not $Repair) { return $null }
        $corrupt = "$ManifestPath.corrupt"
        Move-Item -LiteralPath $ManifestPath -Destination $corrupt -Force
        Add-ResultLine 'manifest-replaced' $corrupt
        return $null
    }
}

function Write-Manifest {
    param($Manifest)
    $directory = Split-Path -Parent $ManifestPath
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    # write to a sibling temporary file first so a crash cannot truncate the manifest
    $temporary = "$ManifestPath.new"
    $json = $Manifest | ConvertTo-Json -Depth 6
    [System.IO.File]::WriteAllText($temporary, $json, (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporary -Destination $ManifestPath -Force
}

function New-Manifest {
    return [ordered]@{
        'schema'       = $script:schemaVersion
        'api-version'  = $ApiVersion
        'install-root' = $InstallRoot
        'plugin-root'  = $PluginRoot
        'components'   = [ordered]@{}
        'plugins'      = [ordered]@{}
    }
}

function Get-Section {
    param($Manifest, [string] $Name)
    if (-not $Manifest.Contains($Name) -or $null -eq $Manifest[$Name]) {
        $Manifest[$Name] = [ordered]@{}
    }
    return $Manifest[$Name]
}

function Split-Entries {
    param([string] $Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
    return $Value.Split('|') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
}

function Invoke-Query {
    $manifest = Read-Manifest
    if ($null -eq $manifest) {
        Add-ResultLine 'manifest-present' '0'
        return
    }
    Add-ResultLine 'manifest-present' '1'
    foreach ($key in @('install-root', 'plugin-root', 'api-version')) {
        if ($manifest.Contains($key)) { Add-ResultLine $key ([string] $manifest[$key]) }
    }
    foreach ($section in @('components', 'plugins')) {
        if (-not $manifest.Contains($section) -or $null -eq $manifest[$section]) { continue }
        $prefix = $section.Substring(0, $section.Length - 1)
        foreach ($name in $manifest[$section].Keys) {
            $entry = $manifest[$section][$name]
            $version = ''
            if ($entry -is [System.Collections.IDictionary] -and $entry.Contains('version')) {
                $version = [string] $entry['version']
            }
            Add-ResultLine "$prefix.$name" $version
        }
    }
}

function Invoke-Register {
    $manifest = Read-Manifest -Repair
    if ($null -eq $manifest) { $manifest = New-Manifest }

    $manifest['schema'] = $script:schemaVersion
    foreach ($pair in @{ 'api-version' = $ApiVersion; 'install-root' = $InstallRoot; 'plugin-root' = $PluginRoot }.GetEnumerator()) {
        if (-not [string]::IsNullOrWhiteSpace($pair.Value)) { $manifest[$pair.Key] = $pair.Value }
    }

    foreach ($section in @(@{ Name = 'components'; Entries = $Components }, @{ Name = 'plugins'; Entries = $Plugins })) {
        $target = Get-Section $manifest $section.Name
        foreach ($entry in Split-Entries $section.Entries) {
            $separator = $entry.IndexOf('=')
            if ($separator -lt 1) { throw "malformed entry '$entry', expected 'name=version'" }
            $name = $entry.Substring(0, $separator)
            $target[$name] = [ordered]@{ 'version' = $entry.Substring($separator + 1) }
            Add-ResultLine 'registered' $name
        }
    }

    Write-Manifest $manifest
}

function Invoke-Unregister {
    $manifest = Read-Manifest
    if ($null -eq $manifest) { return }

    foreach ($section in @(@{ Name = 'components'; Entries = $Components }, @{ Name = 'plugins'; Entries = $Plugins })) {
        $target = Get-Section $manifest $section.Name
        foreach ($entry in Split-Entries $section.Entries) {
            $separator = $entry.IndexOf('=')
            $name = $entry
            if ($separator -gt 0) { $name = $entry.Substring(0, $separator) }
            if ($target.Contains($name)) {
                $target.Remove($name)
                Add-ResultLine 'unregistered' $name
            }
        }
    }

    if ((Get-Section $manifest 'components').Count -eq 0 -and (Get-Section $manifest 'plugins').Count -eq 0) {
        Remove-Item -LiteralPath $ManifestPath -Force
        Add-ResultLine 'manifest-removed' '1'
        return
    }
    Write-Manifest $manifest
}

try {
    switch ($Action) {
        'query' { Invoke-Query }
        'register' { Invoke-Register }
        'unregister' { Invoke-Unregister }
    }
    Add-ResultLine 'status' 'ok'
    Write-Result
    exit 0
} catch {
    Add-ResultLine 'status' 'error'
    Add-ResultLine 'message' ($_.Exception.Message -replace '[\r\n]+', ' ')
    Write-Result
    exit 1
}
