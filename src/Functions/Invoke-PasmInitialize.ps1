#Requires -Version 5.1
using namespace System.IO

function Invoke-PasmInitialize {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        # Where to create a working directory.
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$Path = $PWD,

        # The name of the new directory where the Yaml templates will be placed.
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$Name = 'Pasm',

        # Force overwriting of template if it already exists.
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    end {
        try {
            Set-StrictMode -Version Latest
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

            $baseDir = New-Item -Path $path -Name $name -ItemType Directory -Force
            $outputFilePath = $($baseDir.FullName, $('{0}.yml' -f [Pasm.Template.Name]::outline) -join [path]::DirectorySeparatorChar)
            $obj = [PSCustomObject]@{ BaseDirectory = $baseDir; TemplateFile = $outputFilePath }

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

        .LINK
        https://github.com/nekrassov01/Pasm
    #>
}