#Requires -Version 5.1
using namespace System.IO
using namespace System.Collections.Generic

function Invoke-PasmBlueprint {
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo[]])]
    param (
        # Specify the path to the Yaml template.
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('file')]
        [ValidateNotNullOrEmpty()]
        [string[]]$FilePath = $($PWD, $('{0}.yml' -f [Pasm.Template.Name]::outline) -join [path]::DirectorySeparatorChar),

        # Specify the output file name.
        [Parameter(Mandatory = $false)]
        [Alias('out')]
        [ValidateNotNullOrEmpty()]
        [string[]]$OutputFileName = $('{0}.yml' -f [Pasm.Template.Name]::blueprint)
    )

    begin {
        try {
            Set-StrictMode -Version Latest

            # Load helper functions
            . $($PSScriptRoot, 'Helpers', 'Helpers.ps1' -join [path]::DirectorySeparatorChar)

            # Implicitly run the validator process.
            Invoke-PasmValidation -FilePath $filePath | Out-Null

            # Datetime variables
            $published = Get-AWSPublicIpAddressRange -OutputPublicationDate
            $now = (Get-Date).ToUniversalTime()

            # Validation that the number of parameters match
            if ($filePath.Length -ne $outputFileName.Length) {
                throw [InvalidOperationException]::new('The length of the ''FilePath'' and the length of the ''OutputFileName'' must be the same.')
            }
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($PSItem)
        }
    }

    process {
        try {
            $i = 0
            foreach ($file in $filePath) {
                # Load outline file
                $obj = Import-PasmFile -FilePath $file -Ordered

                # Create output file path
                $outputFilePath = $([path]::GetDirectoryName($file), $OutputFileName[$i] -join [path]::DirectorySeparatorChar)

                # If the blueprint file already exists, load it
                # The original blueprint file will be used to update the metadata section and resource ids
                # If the blueprint file does not yet exist, it cannot be loaded here
                $update = Test-Path -LiteralPath $outputFilePath
                if ($update) {
                    $dest = Import-PasmFile -FilePath $outputFilePath -Ordered
                }
                
                # Create metadata section
                $metadata = [ordered]@{}
                $metadata.UpdateNumber = if ($update) { [int]$dest.Metadata.UpdateNumber + 1 } else { 1 }
                $metadata.DeployNumber = if ($update) { [int]$dest.Metadata.DeployNumber } else { 0 }
                $metadata.PublishedAt = $published
                $metadata.CreatedAt = if ($update) { ([datetime]$dest.Metadata.CreatedAt).ToUniversalTime() } else { $now }
                $metadata.UpdatedAt = $now
                $metadata.DeployedAt = if ($update) { ([datetime]$dest.Metadata.DeployedAt).ToUniversalTime() } else { (Get-Date -Date '1970/1/1 0:0:0 GMT').ToUniversalTime() }

                # Rresource variables
                $resource = $obj.Resource
                if ($resource.Contains('SecurityGroup')) { $securityGroup = $obj.Resource.SecurityGroup }
                if ($resource.Contains('NetworkAcl')) { $networkAcl = $obj.Resource.NetworkAcl }
                if ($resource.Contains('PrefixList')) { $prefixList = $obj.Resource.PrefixList }
                
                # Create outer container
                $parent = [ordered]@{}
                $parent.Common = $obj.Common
                $parent.Resource = [ordered]@{}

                # Parse the outline file and convert the 'Rules' section to CIDR units: 'SecurityGroup'
                if ($resource.Contains('SecurityGroup')) {
                    $sgContainer = [list[object]]::new()

                    # Multiple resource definitions are allowed, so process them one by one
                    foreach ($sg in $securityGroup) {
                        $sgRulesContainer = [list[object]]::new()

                        $obj = [ordered]@{}
                        $obj.ResourceName = $sg.ResourceName
                        $obj.ResourceId = if ($update) { $dest.Resource.SecurityGroup.ResourceId } else { 'not-deployed' }
                        $obj.VpcId = $sg.VpcId
                        $obj.MaxEntry = if ($sg.Contains('MaxEntry')) { $sg.MaxEntry } else { 60 }
                        $obj.IPv4Entry = $null
                        $obj.IPv6Entry = $null
                        $obj.FlowDirection = if ($sg.Contains('FlowDirection')) { $sg.FlowDirection } else { 'Ingress' }
                        $obj.Description = $sg.Description

                        # Multiple rules definitions are allowed, so process them one by one
                        foreach ($rule in $sg.Rules) {
                            $sgRangesContainer = [list[object]]::new()

                            $o = [ordered]@{}
                            $o.Id = $rule.Id
                            $o.ServiceKey = $rule.ServiceKey
                            $o.Protocol = $rule.Protocol
                            $o.FromPort = $rule.FromPort
                            $o.ToPort = $rule.ToPort

                            # For each rule, send API to 'ip-ranges.json' to get the IP range
                            $num = 1
                            foreach ($r in $(Get-PasmAWSIpRange $rule -Resource SecurityGroup)) {
                                $range = [ordered]@{}
                                $range.RangeId = $num
                                $range.IpPrefix = $r.IpPrefix
                                $range.IpFormat = $r.IpAddressFormat
                                $range.Region = $r.Region
                                $range.Description = 'Service:{0} Region:{1} Published:{2} Created:{3} Updated:{4}' -f (
                                    $rule.ServiceKey, 
                                    $r.Region, 
                                    $published.ToString('yyyy-MM-dd-HH-mm-ss'), 
                                    $(if ($update) { ([datetime]$dest.Metadata.CreatedAt).ToUniversalTime().ToString('yyyy-MM-dd-HH-mm-ss') } else { $now.ToString('yyyy-MM-dd-HH-mm-ss') }), 
                                    $now.ToString('yyyy-MM-dd-HH-mm-ss')
                                )
                                $sgRangesContainer.Add($range)
                                $num++
                            }
                            $o.Ranges = $sgRangesContainer
                            $sgRulesContainer.Add($o)
                        }
                        $obj.Rules = $sgRulesContainer

                        # Get the number of registered ipv4 and ipv6 addresses
                        $obj.IPv4Entry = @($obj.Rules.Ranges.Where( { $_.Ipformat -eq 'IPv4' } )).Length
                        $obj.IPv6Entry = @($obj.Rules.Ranges.Where( { $_.Ipformat -eq 'IPv6' } )).Length

                        # Validate the number of entries does not exceed the limit
                        Test-PasmMaxEntry -Entry $obj.IPv4Entry -MaxEntry $obj.MaxEntry -IpFormat 'IPv4' -ResourceType 'SecurityGroup'
                        Test-PasmMaxEntry -Entry $obj.IPv6Entry -MaxEntry $obj.MaxEntry -IpFormat 'IPv6' -ResourceType 'SecurityGroup'

                        $sgContainer.Add($obj)
                    }

                    $parent.Resource.SecurityGroup = $sgContainer
                }

                # Parse the outline file and convert the 'Rules' section to CIDR units: 'NetworkAcl'
                if ($resource.Contains('NetworkAcl')) {
                    $naclContainer = [list[object]]::new()

                    # Multiple resource definitions are allowed, so process them one by one
                    foreach ($nacl in $networkAcl) {
                        $naclRulesContainer = [list[object]]::new()
                        
                        $obj = [ordered]@{}
                        $obj.ResourceName = $nacl.ResourceName
                        $obj.ResourceId = if ($update) { $dest.Resource.NetworkAcl.ResourceId } else { 'not-deployed' }
                        $obj.VpcId = $nacl.VpcId
                        $obj.MaxEntry = if ($nacl.Contains('MaxEntry')) { $nacl.MaxEntry } else { 20 }
                        $obj.IPv4Entry = $null
                        $obj.IPv6Entry = $null
                        $obj.FlowDirection = if ($nacl.Contains('FlowDirection')) { $nacl.FlowDirection } else { 'Ingress' }

                        if ($nacl.Contains('AssociationSubnetId')) {
                            $obj.AssociationSubnetId = $nacl.AssociationSubnetId
                        }

                        $ruleNumber = $nacl.RuleNumber.StartNumber
                        $interval = $nacl.RuleNumber.Interval

                        # Multiple rules definitions are allowed, so process them one by one
                        foreach ($rule in $nacl.Rules) {
                            $naclRangesContainer = [list[object]]::new()

                            $o = [ordered]@{}
                            $o.Id = $rule.Id
                            $o.ServiceKey = $rule.ServiceKey
                            $o.Protocol = $rule.Protocol
                            $o.FromPort = $rule.FromPort
                            $o.ToPort = $rule.ToPort

                            # For each rule, send API to 'ip-ranges.json' to get the IP range
                            $num = 1
                            foreach ($r in $(Get-PasmAWSIpRange $rule -Resource NetworkAcl)) {
                                $range = [ordered]@{}
                                $range.RangeId = $num
                                $range.IpPrefix = $r.IpPrefix
                                $range.IpFormat = $r.IpAddressFormat
                                $range.Region = $r.Region
                                $range.RuleNumber = $ruleNumber
                                $range.EphemeralPort = if ($rule.Contains('EphemeralPort')) { $rule.EphemeralPort } else { $true }

                                $naclRangesContainer.Add($range)
                                $ruleNumber = $ruleNumber + $interval
                                $num++
                            }
                            $o.Ranges = $naclRangesContainer
                            $naclRulesContainer.Add($o)
                        }
                        $obj.Rules = $naclRulesContainer

                        # Get the number of registered ipv4 and ipv6 addresses
                        $obj.IPv4Entry = @($obj.Rules.Ranges.Where( { $_.Ipformat -eq 'IPv4' } )).Length
                        $obj.IPv6Entry = @($obj.Rules.Ranges.Where( { $_.Ipformat -eq 'IPv6' } )).Length

                        # Validate the number of entries does not exceed the limit
                        Test-PasmMaxEntry -Entry $obj.IPv4Entry -MaxEntry $obj.MaxEntry -IpFormat 'IPv4' -ResourceType 'NetworkAcl'
                        Test-PasmMaxEntry -Entry $obj.IPv6Entry -MaxEntry $obj.MaxEntry -IpFormat 'IPv6' -ResourceType 'NetworkAcl'

                        $naclContainer.Add($obj)
                    }                   
                    $parent.Resource.NetworkAcl = $naclContainer
                }

                # Parse the outline file and convert the 'Rules' section to CIDR units: 'PrefixList'
                if ($resource.Contains('PrefixList')) {
                    $plContainer = [list[object]]::new()

                    # Multiple resource definitions are allowed, so process them one by one
                    foreach ($pl in $prefixList) {
                        $plRulesContainer = [list[object]]::new()

                        $obj = [ordered]@{}
                        $obj.ResourceName = $pl.ResourceName
                        $obj.ResourceId = if ($update) { $dest.Resource.PrefixList.ResourceId } else { 'not-deployed' }
                        $obj.VpcId = $pl.VpcId
                        $obj.MaxEntry = if ($pl.Contains('MaxEntry')) { $pl.MaxEntry } else { 1000 }
                        $obj.IPv4Entry = $null
                        $obj.IPv6Entry = $null
                        $obj.AddressFamily = if ($pl.Contains('AddressFamily')) { $pl.AddressFamily } else { 'IPv4' }

                        # Multiple rules definitions are allowed, so process them one by one
                        foreach ($rule in $pl.Rules) {
                            $plRangesContainer = [list[object]]::new()

                            $o = [ordered]@{}
                            $o.Id = $rule.Id
                            $o.ServiceKey = $rule.ServiceKey

                            # For each rule, send API to 'ip-ranges.json' to get the IP range
                            $num = 1
                            foreach ($r in $(Get-PasmAWSIpRange $rule -Resource PrefixList -AddressFamily $obj.AddressFamily)) {
                                $range = [ordered]@{}
                                $range.RangeId = $num
                                $range.IpPrefix = $r.IpPrefix
                                $range.IpFormat = $r.IpAddressFormat
                                $range.Region = $r.Region
                                $range.Description = 'Service:{0} Region:{1} Published:{2} Created:{3} Updated:{4}' -f (
                                    $rule.ServiceKey, 
                                    $r.Region, 
                                    $published.ToString('yyyy-MM-dd-HH-mm-ss'), 
                                    $(if ($update) { ([datetime]$dest.Metadata.CreatedAt).ToUniversalTime().ToString('yyyy-MM-dd-HH-mm-ss') } else { $now.ToString('yyyy-MM-dd-HH-mm-ss') }), 
                                    $now.ToString('yyyy-MM-dd-HH-mm-ss')
                                )
                                $plRangesContainer.Add($range)
                                $num++
                            }
                            $o.Ranges = $plRangesContainer
                            $plRulesContainer.Add($o)
                        }
                        $obj.Rules = $plRulesContainer

                        # Get the number of registered ipv4 and ipv6 addresses
                        $obj.IPv4Entry = @($obj.Rules.Ranges.Where( { $_.IpFormat -eq 'IPv4' } )).Length
                        $obj.IPv6Entry = @($obj.Rules.Ranges.Where( { $_.IpFormat -eq 'IPv6' } )).Length

                        # Validate the number of entries does not exceed the limit
                        Test-PasmMaxEntry -Entry $obj.IPv4Entry -MaxEntry $obj.MaxEntry -IpFormat 'IPv4' -ResourceType 'PrefixList'
                        Test-PasmMaxEntry -Entry $obj.IPv6Entry -MaxEntry $obj.MaxEntry -IpFormat 'IPv6' -ResourceType 'PrefixList'

                        $plContainer.Add($obj)
                    }                    
                    $parent.Resource.PrefixList = $plContainer
                }

                # Add metadata section to object
                $parent.MetaData = $metadata

                # Converts the object to Yaml format and writes it to a file
                # If the file already exists, it will be overwritten
                $parent | ConvertTo-Yaml -OutFile $outputFilePath -Force
                $i++
                $PSCmdlet.WriteObject([fileinfo]::new($outputFilePath))
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
        Get the ip ranges from 'ip-ranges.json' as described in the Yaml template, and create a blueprint.

        .DESCRIPTION
        Get the ip ranges from 'ip-ranges.json' as described in the Yaml template, and create a blueprint.
        See the following source for details: https://github.com/nekrassov01/Pasm/blob/main/src/Functions/Invoke-PasmBlueprint.ps1
    
        .EXAMPLE
        # Default input file path: ${PWD}/outline.yml, default output file name: 'blueprint.yml'
        Invoke-PasmBlueprint

        .EXAMPLE
        # Loading multiple files
        Invoke-PasmBlueprint -FilePath 'C:/Pasm/outline-sg.yml', 'C:/Pasm/outline-nacl.yml', 'C:/Pasm/outline-pl.yml' -OutputFileName 'blueprint-sg.yml', 'blueprint-nacl.yml', 'blueprint-pl.yml'

        .EXAMPLE
        # Loading multiple files from pipeline
        'C:/Pasm/outline-sg.yml', 'C:/Pasm/outline-nacl.yml', 'C:/Pasm/outline-pl.yml' | Invoke-PasmBlueprint -OutputFileName 'blueprint-sg.yml', 'blueprint-nacl.yml', 'blueprint-pl.yml'

        .LINK
        https://github.com/nekrassov01/Pasm
    #>
}
