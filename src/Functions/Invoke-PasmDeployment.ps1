﻿#Requires -Version 5.1
using namespace System.IO
using namespace System.Management.Automation
using namespace System.Collections.Generic
using namespace Amazon.EC2.Model

function Invoke-PasmDeployment {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param (
        # Specify the path to the Yaml template.
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$FilePath = $($PWD, $('{0}.yml' -f [Pasm.Template.Name]::blueprint) -join [path]::DirectorySeparatorChar)
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
                # Load blueprint file
                $obj = Import-PasmFile -FilePath $file -Ordered

                # Rresource variables
                $resource = $obj.Resource
                if ($resource.Contains('SecurityGroup')) { $securityGroup = $obj.Resource.SecurityGroup }
                if ($resource.Contains('NetworkAcl')) { $networkAcl = $obj.Resource.NetworkAcl }
                if ($resource.Contains('PrefixList')) { $prefixList = $obj.Resource.PrefixList }

                # Set AWS default settings for this session
                Set-AWSCredential -ProfileName $obj.Common.ProfileName -Scope Local
                Set-DefaultAWSRegion -Region $obj.Common.Region -Scope Local

                # Deploy SecurityGroup: creating a new one if the resouce id does not exist, or updating the entry if it does
                if ($resource.Contains('SecurityGroup')) {
                    foreach ($sg in $securityGroup) {
                        $target = Get-EC2SecurityGroup -Filter @{ Name = 'group-id'; Values = $sg.ResourceId }
                        $ipPermissions = New-PasmSecurityGroupEntry -Rule $sg.Rules

                        if ($null -eq $target) {
                            $tags = @{ Key = 'Name'; Value = $sg.ResourceName }
                            $nameTag = [TagSpecification]::new()
                            $nameTag.ResourceType = 'security-group'
                            $nameTag.Tags.Add($tags)

                            $target = Get-EC2SecurityGroup -GroupId $(New-EC2SecurityGroup -GroupName $sg.ResourceName -Description $sg.Description -VpcId $sg.VpcId -TagSpecification $nameTag)

                            # Add entries
                            if ($sg.FlowDirection -eq 'Ingress') {
                                Grant-EC2SecurityGroupIngress -GroupId $target.GroupId -IpPermission $ipPermissions
                            }
                            if ($sg.FlowDirection -eq 'Egress') {
                                Grant-EC2SecurityGroupEgress -GroupId $target.GroupId -IpPermission $ipPermissions
                            }

                            # Overwrite ResourceId
                            $sg.ResourceId = $target.GroupId

                            Out-PasmDeploymentResult -ResourceType SecurityGroup -ResourceName $target.GroupName -ResourceId $target.GroupId -Action 'Create'
                        }
                        else {
                            # Replacing entries
                            if ($sg.FlowDirection -eq 'Ingress') {
                                if ($target.IpPermissions) {
                                    Revoke-EC2SecurityGroupIngress -GroupId $target.GroupId -IpPermission $target.IpPermissions | Out-Null
                                }
                                Grant-EC2SecurityGroupIngress -GroupId $target.GroupId -IpPermission $ipPermissions
                            }
                            if ($sg.FlowDirection -eq 'Egress') {
                                if ($target.IpPermissionsEgress) {
                                    Revoke-EC2SecurityGroupEgress  -GroupId $target.GroupId -IpPermission $target.IpPermissionsEgress | Out-Null
                                }
                                Grant-EC2SecurityGroupEgress -GroupId $target.GroupId -IpPermission $ipPermissions
                            }

                            # Overwrite ResourceId
                            $sg.ResourceId = $target.GroupId

                            Out-PasmDeploymentResult -ResourceType SecurityGroup -ResourceName $target.GroupName -ResourceId $target.GroupId -Action 'Sync'
                        }
                    }
                }

                # Deploy NetworkAcl: creating a new one if the resouce id does not exist, or updating the entry if it does
                if ($resource.Contains('NetworkAcl')) {
                    foreach ($nacl in $networkAcl) {
                        $target = Get-EC2NetworkAcl -Filter @{ Name = 'network-acl-id'; Values = $nacl.ResourceId }

                        if ($null -eq $target) {
                            $tags = @{ Key = 'Name'; Value = $nacl.ResourceName }
                            $nameTag = [TagSpecification]::new()
                            $nameTag.ResourceType = 'network-acl'
                            $nameTag.Tags.Add($tags)    

                            $target = New-EC2NetworkAcl -VpcId $nacl.VpcId -TagSpecification $nameTag

                            # Add entries to the network acl
                            New-PasmNetworkAclEntry $nacl -NetworkAcl $target

                            # Overwrite ResourceId
                            $nacl.ResourceId = $target.NetworkAclId

                            Out-PasmDeploymentResult -ResourceType NetworkAcl -ResourceName $target.Tags.Value -ResourceId $target.NetworkAclId -Action 'Create'
                        }
                        else {
                            $naclIngressRuleNumbers = $target.Entries.Where( { $_.Egress -eq $false -and $_.RuleNumber -ne 32767 } ).RuleNumber
                            $naclEgressRuleNumbers = $target.Entries.Where( { $_.Egress -eq $true -and $_.RuleNumber -ne 32767 } ).RuleNumber

                            # Remove entries from the network acl
                            foreach ($naclIngressRuleNumber in $naclIngressRuleNumbers) {
                                Remove-EC2NetworkAclEntry -NetworkAclId $target.NetworkAclId -RuleNumber $naclIngressRuleNumber -Egress $false -Confirm:$false
                            }
                            foreach ($naclEgressRuleNumber in $naclEgressRuleNumbers) {
                                Remove-EC2NetworkAclEntry -NetworkAclId $target.NetworkAclId -RuleNumber $naclEgressRuleNumber  -Egress $true  -Confirm:$false
                            }

                            # Add entries to the network acl
                            New-PasmNetworkAclEntry $nacl -NetworkAcl $target       

                            # Overwrite ResourceId
                            $nacl.ResourceId = $target.NetworkAclId

                            Out-PasmDeploymentResult -ResourceType NetworkAcl -ResourceName $target.Tags.Value -ResourceId $target.NetworkAclId -Action 'Sync'
                        }
                    }
                }

                # Deploy PrefixList: creating a new one if the resouce id does not exist, or updating the entry if it does
                if ($resource.Contains('PrefixList')) {
                    foreach ($pl in $prefixList) {
                        $target = Get-EC2ManagedPrefixList -Filter @{ Name = 'prefix-list-id'; Values = $pl.ResourceId }
                        $entries = New-PasmPrefixListEntry -Rule $pl.Rules

                        if ($null -eq $target) {
                            $tags = @{ Key = 'Name'; Value = $pl.ResourceName }
                            $nameTag = [TagSpecification]::new()
                            $nameTag.ResourceType = 'prefix-list'
                            $nameTag.Tags.Add($tags)    

                            $target = New-EC2ManagedPrefixList -PrefixListName $pl.ResourceName -AddressFamily $pl.AddressFamily -MaxEntry $pl.MaxEntry -Entry $entries -TagSpecification $nameTag

                            # Wait for the state to change
                            if ($target.PrefixListId) {
                                while ((Get-EC2ManagedPrefixList -PrefixListId $target.PrefixListId).State.Value -notin ('create-complete', 'modify-complete')) {
                                    Start-Sleep -Milliseconds 1
                                }
                            }

                            # Overwrite ResourceId
                            $pl.ResourceId = $target.PrefixListId

                            Out-PasmDeploymentResult -ResourceType PrefixList -ResourceName $target.PrefixListName -ResourceId $target.PrefixListId -Action 'Create'
                        }
                        else {
                            $existingEntries = Get-EC2ManagedPrefixListEntry -PrefixListId $target.PrefixListId

                            # Create an list of entries removing from the prefix list
                            # Delete only those entries that are not included in configuration file
                            $removeEntries = [list[RemovePrefixListEntry]]::new()
                            foreach ($existingEntry in $existingEntries) {
                                if ($existingEntry.Cidr -notin $pl.Rules.Ranges.IpPrefix) {
                                    $removeEntry = [RemovePrefixListEntry]::new()
                                    $removeEntry.Cidr = $existingEntry.Cidr
                                    $removeEntries.Add($removeEntry)
                                }
                            }

                            # Create an list of entries adding to the prefix list
                            # Add to the list only those entries that are not included in '$existingEntries'
                            $addEntries = [list[AddPrefixListEntry]]::new()
                            foreach ($range in $pl.Rules.Ranges) {
                                if ($range.IpPrefix -notin $existingEntries.Cidr) {
                                    $addEntry = [AddPrefixListEntry]::new()
                                    $addEntry.Cidr = $range.IpPrefix
                                    $addEntry.Description = $range.Description
                                    $addEntries.Add($addEntry)
                                }
                            }

                            # Update the prefix list
                            if ($removeEntries -and $addEntries) {
                                Edit-EC2ManagedPrefixList -PrefixListId $target.PrefixListId -RemoveEntry $removeEntries -AddEntry $addEntries -CurrentVersion $target.Version | Out-Null
                            }
                            if ($removeEntries -and -not $addEntries) {
                                Edit-EC2ManagedPrefixList -PrefixListId $target.PrefixListId -RemoveEntry $removeEntries -CurrentVersion $target.Version | Out-Null
                            }
                            if (-not $removeEntries -and $addEntries) {
                                Edit-EC2ManagedPrefixList -PrefixListId $target.PrefixListId -AddEntry $addEntries -CurrentVersion $target.Version | Out-Null
                            }

                            # Wait for the state to change
                            if ($target.PrefixListId) {
                                while ((Get-EC2ManagedPrefixList -PrefixListId $target.PrefixListId).State.Value -notin ('create-complete', 'modify-complete')) {
                                    Start-Sleep -Milliseconds 1
                                }
                            }

                            # Overwrite ResourceId
                            $pl.ResourceId = $target.PrefixListId

                            Out-PasmDeploymentResult -ResourceType PrefixList -ResourceName $target.PrefixListName -ResourceId $target.PrefixListId -Action 'Sync'
                        }
                    }
                }

                # Clear AWS default settings for this session
                Clear-AWSDefaultConfiguration -SkipProfileStore

                # Update metadata section
                if ($obj.Contains('MetaData')) {
                    $metadata = [ordered]@{}
                    $metadata.UpdateNumber = $obj.MetaData.UpdateNumber
                    $metadata.DeployNumber = if ($obj.MetaData.Contains('DeployNumber')) { $obj.MetaData.DeployNumber + 1 } else { 1 }
                    $metadata.PublishedAt = Get-AWSPublicIpAddressRange -OutputPublicationDate
                    $metadata.CreatedAt = ([datetime]$obj.MetaData.CreatedAt).ToUniversalTime()
                    $metadata.UpdatedAt = ([datetime]$obj.MetaData.UpdatedAt).ToUniversalTime()
                    $metadata.DeployedAt = (Get-Date).ToUniversalTime()
                    $obj.MetaData = $metadata
                }

                # Convert the object to Yaml format and overwrite the file
                $obj | ConvertTo-Yaml -OutFile $file -Force
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
        Reads the configuration generated by the blueprinting process and deploys the actual resources.

        .DESCRIPTION
        Reads the configuration generated by the blueprinting process and deploys the actual resources.
        See the following source for details: https://github.com/nekrassov01/Pasm/blob/main/src/Functions/Invoke-PasmDeployment.ps1
    
        .EXAMPLE
        # Default input file path: ${PWD}/blueprint.yml
        Invoke-PasmDeployment

        .EXAMPLE
        # Loading multiple files
        Invoke-PasmDeployment -FilePath 'C:/Pasm/blueprint-sg.yml', 'C:/Pasm/blueprint-nacl.yml', 'C:/Pasm/blueprint-pl.yml'

        .EXAMPLE
        # Loading multiple files from pipeline
        'C:/Pasm/blueprint-sg.yml', 'C:/Pasm/blueprint-nacl.yml', 'C:/Pasm/blueprint-pl.yml' | Invoke-PasmDeployment

        .LINK
        https://github.com/nekrassov01/Pasm
    #>
}
