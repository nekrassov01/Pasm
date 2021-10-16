#Requires -Version 5.1
using namespace System.IO

function Invoke-PasmInitialize {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        # Where to create a working directory.
        [Parameter(Mandatory = $false)]
        [Alias('p')]
        [ValidateNotNullOrEmpty()]
        [string]$Path = $PWD,

        # The name of the new directory where the Yaml templates will be placed.
        [Parameter(Mandatory = $false)]
        [Alias('n')]
        [ValidateNotNullOrEmpty()]
        [string]$Name = 'Pasm',

        # If the target vpc already exists, overwrite 'VpcId'.
        [Parameter(Mandatory = $false)]
        [Alias('vpc')]
        [ValidateNotNullOrEmpty()]
        [string]$VpcId,

        # If the target subnets already exists, overwrite 'SubnetId'.
        [Parameter(Mandatory = $false)]
        [Alias('sbn')]
        [ValidateNotNullOrEmpty()]
        [string[]]$SubnetId,

        # Force overwriting of template if it already exists.
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    end {
        try {
            Set-StrictMode -Version Latest

            # Load helper functions
            . $($PSScriptRoot, 'Helpers', 'Helpers.ps1' -join [path]::DirectorySeparatorChar)

            $content = @'
### sample template ###
Common:                             # required
  Region: ap-northeast-1            # required     - Cmdlet: (Get-AWSRegion -IncludeChina -IncludeGovCloud).Region
  ProfileName: default              # required     - Cmdlet: Get-AWSCredential -ProfileName $profileName
Resource:                           # required
  SecurityGroup:                    # not-required - One of the following must be present: 'SecurityGroup','NetworkAcl', 'PrefixList'
  - ResourceName: test-sg-01        # required
    VpcId: vpc-00000000000000000    # required
    MaxEntry: 60                    # not-required - Range: 1-60
    FlowDirection: Ingress          # not-required - Enum: [Pasm.Parameter.FlowDirection]
    Description: test message       # required
    Rules:                          # required
    - Id: 1                         # required
      ServiceKey: S3                # required     - Cmdlet: Get-AWSPublicIpAddressRange -OutputServiceKeys
      Region:                       # not-required - Cmdlet: (Get-AWSRegion -IncludeChina -IncludeGovCloud).Region
      - ap-northeast-1
      IpFormat:                     # not-required - Enum: [Pasm.Parameter.IpFormat]
      - IPv4
      Protocol: tcp                 # required     - Enum: [Pasm.Parameter.Protocol]
      FromPort: 80                  # required     - Range: 0-65535
      ToPort: 80                    # required     - Range: 0-65535
    - Id: 2
      ServiceKey: S3 
      Region:
      - ap-northeast-1
      IpFormat:
      - IPv4
      Protocol: tcp
      FromPort: 443
      ToPort: 443
  NetworkAcl:                       # not-required - One of the following must be present: 'SecurityGroup','NetworkAcl', 'PrefixList' 
  - ResourceName: test-acl-01       # required
    VpcId: vpc-00000000000000000    # required
    MaxEntry: 20                    # not-required - Range: 1-20
    FlowDirection: Ingress          # not-required - Enum: [Pasm.Parameter.FlowDirection]
    RuleNumber:                     # not-required
      StartNumber: 100              # not-required - Range: 1-32766
      Interval: 10                  # not-required - Range: 1-10
    AssociationSubnetId:            # not-required
    - subnet-00000000000000000      # not-required
    - subnet-11111111111111111      # not-required
    Rules:                          # required
    - Id: 1                         # required
      ServiceKey: S3                # required     - Cmdlet: Get-AWSPublicIpAddressRange -OutputServiceKeys
      Region:                       # not-required - Cmdlet: (Get-AWSRegion -IncludeChina -IncludeGovCloud).Region
      - ap-northeast-1
      IpFormat:                     # not-required - Enum: [Pasm.Parameter.IpFormat]
      - IPv4
      Protocol: tcp                 # required     - Enum: [Pasm.Parameter.Protocol]
      FromPort: 80                  # required     - Range: 0-65535
      ToPort: 80                    # required     - Range: 0-65535
      EphemeralPort: true           # not-required - bool
    - Id: 2
      ServiceKey: S3
      Region:
      - ap-northeast-1
      IpFormat:
      - IPv4
      Protocol: tcp
      FromPort: 443
      ToPort: 443
      EphemeralPort: true
  PrefixList:                       # not-required - One of the following must be present: 'SecurityGroup','NetworkAcl', 'PrefixList'
  - ResourceName: test-pl-01        # required
    VpcId: vpc-00000000000000000    # required
    MaxEntry: 30                    # not-required - Range: 1-1000
    AddressFamily: IPv4             # not-required - Enum: [Pasm.Parameter.IpFormat]
    Rules:                          # required
    - Id: 1                         # required
      ServiceKey: S3                # required     - Cmdlet: Get-AWSPublicIpAddressRange -OutputServiceKeys
      Region:                       # not-required - Cmdlet: (Get-AWSRegion -IncludeChina -IncludeGovCloud).Region
      - ap-northeast-1
    - Id: 2
      ServiceKey: S3
      Region:
      - ap-northeast-2
'@

            # If 'VpcId' or 'SubnetId' is passed from the parameter, it will overwrite the value in the sample template            
            $isPresent_VpcId = $PSBoundParameters.ContainsKey('VpcId')
            $isPresent_SubnetId = $PSBoundParameters.ContainsKey('SubnetId')

            if ($isPresent_VpcId -or $isPresent_SubnetId) {
                $yaml = ConvertFrom-Yaml -Yaml $content -Ordered           
                if ($isPresent_VpcId) {
                    foreach ($resource in 'SecurityGroup', 'NetworkAcl', 'PrefixList') {
                        foreach ($r in $yaml.Resource.$resource) {
                            if ($r.Contains('VpcId')) {
                                $r.VpcId = $vpcId
                            }
                        }
                    }
                }
                if ($isPresent_SubnetId) {
                    foreach ($n in $yaml.Resource.NetworkACL) {
                        if ($n.Contains('AssociationSubnetId')) {
                            $n.AssociationSubnetId = $subnetId
                        }
                    }
                }
                $content = $yaml | ConvertTo-Yaml
                $PSCmdlet.WriteWarning('If you overwrite the ''VpcId'' or ''AssociationSubnetId'', be sure to run ''Invoke-PasmValidation'' to validate the template.')
            }
                
            $baseDir = New-Item -Path $path -Name $name -ItemType Directory -Force
            $fileName = '{0}.yml' -f [Pasm.Template.Name]::outline
            $outputFilePath = $baseDir.FullName, $fileName -join [path]::DirectorySeparatorChar
            $obj = [PSCustomObject]@{ BaseDirectory = $baseDir; TemplateFile = $fileName }

            if (Test-Path -LiteralPath $baseDir.FullName) {
                if (Test-Path -LiteralPath $outputFilePath) {
                    if (!$PSBoundParameters.ContainsKey('Force')) {
                        if ((Read-Host 'The file already exists. Do you want to overwrite it? (y/n)') -notin 'y', 'yes') {
                            return 'Canceled.'
                        }
                    }
                }
                $content | Out-File -LiteralPath $outputFilePath -Force
                return $obj
            }
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($PSItem)
        }
    }
    <#
        .SYNOPSIS
        Run the initialization process for using Pasm. It is also possible to create a Yaml template manually without using this script.

        .DESCRIPTION
        Run the initialization process for using Pasm. It is also possible to create a Yaml template manually without using this script.
        See the following source for details: https://github.com/nekrassov01/Pasm/blob/main/src/Functions/Invoke-PasmInitialize.ps1
    
        .EXAMPLE
        # Default directory name: 'Pasm'
        Invoke-PasmInitialize

        .EXAMPLE
        # Build by specifying a directory name
        Invoke-PasmInitialize -Name 'Test'

        .EXAMPLE
        # 'VpcId' and 'AssociationSubnetId' can be overridden with actual values
        Invoke-PasmInitialize -VpcId 'vpc-1qaz2wsx3edc4rfv5' -SubnetId 'subnet-zxcvasdfqwer12345', 'subnet-poiulkjhmnbv09876'

        .EXAMPLE
        # To allow overwriting of an already existing template file
        Invoke-PasmInitialize -Force

        .LINK
        https://github.com/nekrassov01/Pasm
    #>
}