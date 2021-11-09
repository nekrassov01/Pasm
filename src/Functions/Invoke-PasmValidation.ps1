#Requires -Version 5.1
using namespace System.IO

function Invoke-PasmValidation {
    [CmdletBinding()]
    [OutputType([void])]
    param (
        # Specify the path to the Yaml template.
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('file')]
        [ValidateNotNullOrEmpty()]
        [string[]]$FilePath = $($PWD, $('{0}.yml' -f [Pasm.Template.Name]::outline) -join [path]::DirectorySeparatorChar)
    )

    begin {
        try {
            Set-StrictMode -Version Latest

            # Load helper functions
            . $($PSScriptRoot, 'Helpers', 'Helpers.ps1' -join [path]::DirectorySeparatorChar)
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($PSItem)
        }
    }

    process {
        try {
            foreach ($file in $filePath) {
                # Load outline file
                $obj = Import-PasmFile -FilePath $file -Ordered

                Out-PasmLogLine -Message $('Validation started: {0}' -f [path]::GetFileName($file))

                # Yaml validation: top-level layer
                Test-PasmRequiredKey $obj
                Test-PasmInvalidKey  $obj
                Test-PasmEmptyKey    $obj

                Out-PasmLogLine -Message 'Validation passed: Parent'

                # Yaml validation: 'Common' section
                $common = $obj.Common
                Test-PasmRequiredKey $common -Enum 'Pasm.RequiredParameter.Common'
                Test-PasmInvalidKey  $common -Enum 'Pasm.Parameter.Common'
                Test-PasmEmptyKey    $common -Enum 'Pasm.Parameter.Common'
                Test-PasmScalarValue $common -Key  'ProfileName', 'Region'
                Test-PasmProfileName $common
                Test-PasmRegion      $common

                Out-PasmLogLine -Message 'Validation passed: Common'

                # Yaml validation: 'Resource' section
                $resource = $obj.Resource
                Test-PasmInvalidKey $resource -Enum 'Pasm.Parameter.Resource'
                Test-PasmEmptyKey   $resource -Enum 'Pasm.Parameter.Resource'

                Out-PasmLogLine -Message 'Validation passed: Resource'

                # Set AWS default settings for this session
                Set-AWSCredential -ProfileName $common.ProfileName -Scope Local
                Set-DefaultAWSRegion -Region $common.Region -Scope Local

                # Yaml validation: 'SecurityGroup' section
                if ($resource.Contains('SecurityGroup')) {
                    $securityGroup = $obj.Resource.SecurityGroup
                    foreach ($sg in $securityGroup) {
                        Test-PasmRequiredKey  $sg -Enum 'Pasm.RequiredParameter.SecurityGroup'
                        Test-PasmInvalidKey   $sg -Enum 'Pasm.Parameter.SecurityGroup'
                        Test-PasmEmptyKey     $sg -Enum 'Pasm.Parameter.SecurityGroup'
                        Test-PasmScalarValue  $sg -Key  'ResourceName', 'VpcId', 'MaxEntry', 'FlowDirection', 'Description'
                        Test-PasmInvalidValue $sg -Key  'FlowDirection'
                        Test-PasmRange        $sg -Key  'MaxEntry' -Start 1 -End 60

                        Out-PasmLogLine -Message $('Validation passed: SecurityGroup ''{0}'' Parent' -f $sg.ResourceName)

                        if ($sg.Contains('Rules')) {
                            $sgRules = $obj.Resource.SecurityGroup.Rules
                            Test-PasmRequiredKey  $sgRules -Enum 'Pasm.RequiredParameter.SecurityGroupRules'
                            Test-PasmInvalidKey   $sgRules -Enum 'Pasm.Parameter.SecurityGroupRules'
                            Test-PasmEmptyKey     $sgRules -Enum 'Pasm.Parameter.SecurityGroupRules'
                            Test-PasmScalarValue  $sgRules -Key  'Id', 'ServiceKey', 'Protocol', 'FromPort', 'ToPort'
                            Test-PasmInvalidValue $sgRules -Key  'Protocol', 'IpFormat'
                            Test-PasmRange        $sgRules -Key  'FromPort', 'ToPort' -Start -1 -End 65535
                            Test-PasmFromTo       $sgRules -From 'FromPort' -To 'ToPort'
                            Test-PasmServiceKey   $sgRules
                            Test-PasmRegion       $sgRules

                            Out-PasmLogLine -Message $('Validation passed: SecurityGroup ''{0}'' Rules' -f $sg.ResourceName)
                        }

                        if ($sg.Contains('VpcId')) {
                            [void](Test-PasmVpcId -VpcId $sg.VpcId)
                            Out-PasmLogLine -Message $('Validation passed: SecurityGroup ''{0}'' VpcId' -f $sg.ResourceName)
                        }
                    }
                }

                # Yaml validation: 'NetworkAcl' section
                if ($resource.Contains('NetworkAcl')) {
                    $networkAcl = $obj.Resource.NetworkAcl
                    foreach ($nacl in $networkAcl) {
                        Test-PasmRequiredKey  $nacl -Enum 'Pasm.RequiredParameter.NetworkAcl'
                        Test-PasmInvalidKey   $nacl -Enum 'Pasm.Parameter.NetworkAcl'
                        Test-PasmEmptyKey     $nacl -Enum 'Pasm.Parameter.NetworkAcl'
                        Test-PasmScalarValue  $nacl -Key  'ResourceName', 'VpcId', 'MaxEntry', 'FlowDirection', 'EphemeralPort'
                        Test-PasmInvalidValue $nacl -Key  'FlowDirection'
                        Test-PasmRange        $nacl -Key  'MaxEntry' -Start 1 -End 20

                        if ($nacl.Contains('RuleNumber')) {
                            $ruleNumber = $obj.Resource.NetworkAcl.RuleNumber
                            Test-PasmInvalidKey  $ruleNumber -Enum 'Pasm.Parameter.RuleNumber'
                            Test-PasmEmptyKey    $ruleNumber -Enum 'Pasm.Parameter.RuleNumber'
                            Test-PasmScalarValue $ruleNumber -Key  'StartNumber', 'Interval'
                            Test-PasmRange       $ruleNumber -Key  'StartNumber' -Start 1 -End 32766
                            Test-PasmRange       $ruleNumber -Key  'Interval'    -Start 1 -End 10
                        }

                        Out-PasmLogLine -Message $('Validation passed: NetworkAcl ''{0}'' Parent' -f $nacl.ResourceName)

                        if ($nacl.Contains('Rules')) {
                            $naclRules = $obj.Resource.NetworkAcl.Rules
                            Test-PasmRequiredKey  $naclRules -Enum 'Pasm.RequiredParameter.NetworkAclRules'
                            Test-PasmInvalidKey   $naclRules -Enum 'Pasm.Parameter.NetworkAclRules'
                            Test-PasmEmptyKey     $naclRules -Enum 'Pasm.Parameter.NetworkAclRules'
                            Test-PasmScalarValue  $naclRules -Key  'Id', 'ServiceKey', 'Protocol', 'FromPort', 'ToPort'
                            Test-PasmInvalidValue $naclRules -Key  'Protocol', 'IpFormat'
                            Test-PasmRange        $naclRules -Key  'FromPort', 'ToPort' -Start -1 -End 65535
                            Test-PasmFromTo       $naclRules -From 'FromPort' -To 'ToPort'
                            Test-PasmServiceKey   $naclRules
                            Test-PasmRegion       $naclRules

                            Out-PasmLogLine -Message $('Validation passed: NetworkAcl ''{0}'' Rules' -f $nacl.ResourceName)
                        }

                        if ($nacl.Contains('VpcId')) {
                            [void](Test-PasmVpcId -VpcId $nacl.VpcId)
                            Out-PasmLogLine -Message $('Validation passed: NetworkAcl ''{0}'' VpcId' -f $nacl.ResourceName)
                        }

                        if ($nacl.Contains('AssociationSubnetId')) {
                            [void](Test-PasmSubnetId -SubnetId $nacl.AssociationSubnetId)
                            Out-PasmLogLine -Message $('Validation passed: NetworkAcl ''{0}'' SubnetId' -f $nacl.ResourceName)
                        }
                    }
                }

                # Yaml validation: 'PerfixList' section
                if ($resource.Contains('PrefixList')) {
                    $prefixList = $obj.Resource.PrefixList
                    foreach ($pl in $prefixList) {
                        Test-PasmRequiredKey  $pl -Enum 'Pasm.RequiredParameter.PrefixList'
                        Test-PasmInvalidKey   $pl -Enum 'Pasm.Parameter.PrefixList'
                        Test-PasmEmptyKey     $pl -Enum 'Pasm.Parameter.PrefixList'
                        Test-PasmScalarValue  $pl -Key  'ResourceName', 'VpcId', 'MaxEntry', 'AddressFamily'
                        Test-PasmInvalidValue $pl -Key  'IpFormat'
                        Test-PasmRange        $pl -Key  'MaxEntry' -Start 1 -End 1000

                        Out-PasmLogLine -Message $('Validation passed: PrefixList ''{0}'' Parent' -f $pl.ResourceName)

                        if ($pl.Contains('Rules')) {
                            $plRules = $obj.Resource.PrefixList.Rules
                            Test-PasmRequiredKey $plRules -Enum 'Pasm.RequiredParameter.PrefixListRules'
                            Test-PasmInvalidKey  $plRules -Enum 'Pasm.Parameter.PrefixListRules'
                            Test-PasmEmptyKey    $plRules -Enum 'Pasm.Parameter.PrefixListRules'
                            Test-PasmScalarValue $plRules -Key  'Id', 'ServiceKey'
                            Test-PasmServiceKey  $plRules
                            Test-PasmRegion      $plRules

                            Out-PasmLogLine -Message $('Validation passed: PrefixList ''{0}'' Rules' -f $pl.ResourceName)
                        }

                        if ($pl.Contains('VpcId')) {
                            [void](Test-PasmVpcId -VpcId $pl.VpcId)
                            Out-PasmLogLine -Message $('Validation passed: PrefixList ''{0}'' VpcId' -f $pl.ResourceName)
                        }
                    }
                }

                # Clear AWS default settings for this session
                Clear-AWSDefaultConfiguration -SkipProfileStore

                Out-PasmLogLine -Message $('Validation finished: {0}' -f [path]::GetFileName($file))
            }
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($PSItem)
        }

    }

    end {
        # Clean up processes, if any
    }

    <#
        .SYNOPSIS
        Parse the Yaml template to validate if it can be loaded for use with Pasm.

        .DESCRIPTION
        Parse the Yaml template to validate if it can be loaded for use with Pasm.
        See the following source for details: https://github.com/nekrassov01/Pasm/blob/main/src/Functions/Helpers/Helpers.ps1
    
        .EXAMPLE
        # Default file path: ${PWD}/outline.yml
        Invoke-PasmValidation

        .EXAMPLE
        # Loading multiple files
        Invoke-PasmValidation -FilePath 'C:/Pasm/outline-sg.yml', 'C:/Pasm/outline-nacl.yml', 'C:/Pasm/outline-pl.yml'

        .EXAMPLE
        # Loading multiple files from pipeline
        'C:/Pasm/outline-sg.yml', 'C:/Pasm/outline-nacl.yml', 'C:/Pasm/outline-pl.yml' | Invoke-PasmValidation

        .LINK
        https://github.com/nekrassov01/Pasm
    #>
}
