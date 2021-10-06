#Requires -Version 5.1
using namespace System.IO

[CmdletBinding(DefaultParameterSetName = 'Update')]
[OutputType([void])]
param (
    [Parameter(Mandatory = $true, ParameterSetName = 'Update')]
    [Parameter(Mandatory = $true, ParameterSetName = 'Release')]
    [string]$Version,

    [Parameter(Mandatory = $true, ParameterSetName = 'Release')]
    [switch]$Release,

    [Parameter(Mandatory = $true, ParameterSetName = 'Release')]
    [string]$NuGetApiKey
)

end {
    Set-StrictMode -Version Latest

    $sepalator = [path]::DirectorySeparatorChar

    # Validate version string
    if ([string]::IsNullOrWhiteSpace($version)) {
        throw [InvalidOperationException]::new('The version is empty. Please specify it like ''1.0.0''.')
    }
    if (![version]::TryParse($version, [ref][version]'1.0.0')) {
        throw [InvalidOperationException]::new($('The version ''{0}'' is invalid. Please specify it like ''1.0.0''.' -f $version))
    }

    # Variables
    $module     = [path]::GetFileNameWithoutExtension($PSCommandPath)
    $moduleDir  = $PSScriptRoot, 'src' -join $sepalator
    $modulePath = $moduleDir, $('{0}.psd1' -f $module) -join $sepalator
    $releaseDir = $PSScriptRoot, 'release', $module -join $sepalator
    $author     = 'nekrassov01'

    # Manifest parameters
    $script:moduleManifest = @{
        Guid                       = [guid]::NewGuid().Guid
        Path                       = $modulePath
        Author                     = $author
        CompanyName                = 'Unknown'
        Copyright                  = '(c) {0} All rights reserved.' -f $author
        RootModule                 = '{0}.psm1' -f $module
        ModuleVersion              = $version
        Description                = '{0} is a PowerShell module for simple management of public IP address ranges provided by AWS.' -f $module
        PowerShellVersion          = '5.1'
        DotNetFrameworkVersion     = '4.5'
        ClrVersion                 = '4.0.0.0'
        CompatiblePSEditions       = @('Core', 'Desktop')
       #RequiredModules            = @()
       #RequiredAssemblies         = @()
        ExternalModuleDependencies = @('PowerShell-Yaml', 'AWS.Tools.Common', 'AWS.Tools.EC2')
        CmdletsToExport            = @()
        FunctionsToExport          = (Get-ChildItem -LiteralPath (Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath 'src') -ChildPath 'Functions') -Filter '*.ps1').ForEach( { [path]::GetFileNameWithoutExtension($_.Name) } )
        VariablesToExport          = '*'
        AliasesToExport            = @()
        Tags                       = @('AWS')
        ProjectUri                 = 'https://github.com/{0}/{1}' -f $author, $module
        LicenseUri                 = 'https://github.com/{0}/{1}/blob/main/LICENSE' -f $author, $module
        ReleaseNotes               = 'https://github.com{0}/{1}/releases/tag/{2}' -f $author, $module, $version
       #DefaultCommandPrefix       = $module
    }

    try {
        # Create or update manifest
        if (Test-Path -LiteralPath $modulePath) {
            $moduleManifest.Remove('Guid')
            Update-ModuleManifest @moduleManifest
        }
        else {
            New-ModuleManifest @moduleManifest
        }
        # Validate manifest
        Test-ModuleManifest -Path $modulePath
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }

    # Put the latest sources in the directory for public use
    if (Test-Path -LiteralPath $releaseDir) {
        Remove-Item -LiteralPath $releaseDir -Recurse -Force | Out-Null
    }
    New-Item -Path $releaseDir -ItemType Directory -Force | Out-Null
    New-Item -Path $($releaseDir, '..', '.gitkeep' -join $sepalator) -ItemType File -Force | Out-Null
    Copy-Item -Path $($moduleDir, '*' -join $sepalator), '*.md' -Destination $releaseDir -Recurse -Force | Out-Null

    # If the 'Release' switch is True, the module will be published
    if ($release) {
        if ([string]::IsNullOrWhiteSpace($nuGetApiKey)) {
            throw [InvalidOperationException]::new('The nuget api key is empty. Please specify it.')
        }
        Publish-Module -Path $releaseDir -NuGetApiKey $nuGetApiKey
    }
}