#Requires -Version 5.1
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
        [Alias('file')]
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

                # Create result object list
                $ret = [list[PSCustomObject]]::new()

                # Deploy SecurityGroup: creating a new one if the resouce id does not exist, or updating the entry if it does
                if ($resource.Contains('SecurityGroup')) {
                    foreach ($sg in $securityGroup) {
                        $target = Get-EC2SecurityGroup -Filter @{ Name = 'group-id'; Values = $sg.ResourceId }
                        $evidence = Get-EC2SecurityGroup -Filter @{ Name = 'group-name'; Values = $sg.ResourceName }
                        $ipPermissions = New-PasmSecurityGroupEntry -Rule $sg.Rules

                        # Even if there is no ID, if there is a name, it is considered to be a resource that already exists.
                        if ($null -eq $target -and $null -eq $evidence) {
                            $tags = @{ Key = 'Name'; Value = $sg.ResourceName }
                            $nameTag = [TagSpecification]::new()
                            $nameTag.ResourceType = 'security-group'
                            $nameTag.Tags.Add($tags)

                            $target = Get-EC2SecurityGroup -GroupId $(New-EC2SecurityGroup -GroupName $sg.ResourceName -Description $sg.Description -VpcId $sg.VpcId -TagSpecification $nameTag)

                            # Add entries
                            if ($sg.FlowDirection -eq 'Ingress') {
                                Grant-EC2SecurityGroupIngress -GroupId $target.GroupId -IpPermission $ipPermissions | Out-Null
                            }
                            if ($sg.FlowDirection -eq 'Egress') {
                                Grant-EC2SecurityGroupEgress -GroupId $target.GroupId -IpPermission $ipPermissions | Out-Null
                            }

                            # Overwrite ResourceId
                            $sg.ResourceId = $target.GroupId

                            # Add an object to the result list
                            $ret.Add(
                                [PSCustomObject]@{
                                    ResourceType = [Pasm.Parameter.Resource]::SecurityGroup
                                    ResourceName = $target.GroupName
                                    ResourceId = $target.GroupId
                                    Action = 'Create'
                                }
                            )
                        }
                        else {
                            if ($null -eq $target -and !($null -eq $evidence)) {
                                $target = $evidence
                            }

                            # Replacing entries
                            if ($sg.FlowDirection -eq 'Ingress') {
                                if ($target.IpPermissions) {
                                    Revoke-EC2SecurityGroupIngress -GroupId $target.GroupId -IpPermission $target.IpPermissions | Out-Null
                                }
                                Grant-EC2SecurityGroupIngress -GroupId $target.GroupId -IpPermission $ipPermissions | Out-Null
                            }
                            if ($sg.FlowDirection -eq 'Egress') {
                                if ($target.IpPermissionsEgress) {
                                    Revoke-EC2SecurityGroupEgress  -GroupId $target.GroupId -IpPermission $target.IpPermissionsEgress | Out-Null
                                }
                                Grant-EC2SecurityGroupEgress -GroupId $target.GroupId -IpPermission $ipPermissions | Out-Null
                            }

                            # Overwrite ResourceId
                            $sg.ResourceId = $target.GroupId

                            # Add an object to the result list
                            $ret.Add(
                                [PSCustomObject]@{
                                    ResourceType = [Pasm.Parameter.Resource]::SecurityGroup
                                    ResourceName = $target.GroupName
                                    ResourceId = $target.GroupId
                                    Action = 'Sync'
                                }
                            )
                        }
                    }
                }

                # Deploy NetworkAcl: creating a new one if the resouce id does not exist, or updating the entry if it does
                if ($resource.Contains('NetworkAcl')) {
                    foreach ($nacl in $networkAcl) {
                        $target = Get-EC2NetworkAcl -Filter @{ Name = 'network-acl-id'; Values = $nacl.ResourceId }
                        $evidence = Get-EC2NetworkAcl -Filter @{ Name = 'tag:Name'; Values = $nacl.ResourceName }

                        # Even if there is no ID, if there is a name, it is considered to be a resource that already exists.
                        if ($null -eq $target -and $null -eq $evidence) {
                            $tags = @{ Key = 'Name'; Value = $nacl.ResourceName }
                            $nameTag = [TagSpecification]::new()
                            $nameTag.ResourceType = 'network-acl'
                            $nameTag.Tags.Add($tags)

                            $target = New-EC2NetworkAcl -VpcId $nacl.VpcId -TagSpecification $nameTag

                            # Add entries to the network acl
                            New-PasmNetworkAclEntry $nacl -NetworkAcl $target

                            # Overwrite ResourceId
                            $nacl.ResourceId = $target.NetworkAclId

                            # Add an object to the result list
                            $ret.Add(
                                [PSCustomObject]@{
                                    ResourceType = [Pasm.Parameter.Resource]::NetworkAcl
                                    ResourceName = $target.Tags.Value
                                    ResourceId = $target.NetworkAclId
                                    Action = 'Create'
                                }
                            )
                        }
                        else {
                            if ($null -eq $target -and !($null -eq $evidence)) {
                                $target = $evidence
                            }

                            $naclIngressRules = $target.Entries.Where( { $_.Egress -eq $false -and $_.RuleNumber -ne 32767 } )
                            $naclEgressRules = $target.Entries.Where( { $_.Egress -eq $true -and $_.RuleNumber -ne 32767 } )

                            # Remove entries from the network acl
                            if ($null -ne $naclIngressRules) {
                                foreach ($naclIngressRule in $naclIngressRules) {
                                    Remove-EC2NetworkAclEntry -NetworkAclId $target.NetworkAclId -RuleNumber $naclIngressRule.RuleNumber -Egress $false -Confirm:$false | Out-Null
                                }
                            }
                            if ($null -ne $naclEgressRules) {
                                foreach ($naclEgressRule in $naclEgressRules) {
                                    Remove-EC2NetworkAclEntry -NetworkAclId $target.NetworkAclId -RuleNumber $naclEgressRule.RuleNumber  -Egress $true  -Confirm:$false | Out-Null
                                }
                            }

                            # Add entries to the network acl
                            New-PasmNetworkAclEntry $nacl -NetworkAcl $target

                            # Overwrite ResourceId
                            $nacl.ResourceId = $target.NetworkAclId

                            # Add an object to the result list
                            $ret.Add(
                                [PSCustomObject]@{
                                    ResourceType = [Pasm.Parameter.Resource]::NetworkAcl
                                    ResourceName = $target.Tags.Value
                                    ResourceId = $target.NetworkAclId
                                    Action = 'Sync'
                                }
                            )
                        }
                    }
                }

                # Deploy PrefixList: creating a new one if the resouce id does not exist, or updating the entry if it does
                if ($resource.Contains('PrefixList')) {
                    foreach ($pl in $prefixList) {
                        $target = Get-EC2ManagedPrefixList -Filter @{ Name = 'prefix-list-id'; Values = $pl.ResourceId }
                        $evidence = Get-EC2ManagedPrefixList -Filter @{ Name = 'prefix-list-name'; Values = $pl.ResourceName }
                        $entries = New-PasmPrefixListEntry -Rule $pl.Rules

                        # Even if there is no ID, if there is a name, it is considered to be a resource that already exists.
                        if ($null -eq $target -and $null -eq $evidence) {
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

                            # Add an object to the result list
                            $ret.Add(
                                [PSCustomObject]@{
                                    ResourceType = [Pasm.Parameter.Resource]::PrefixList
                                    ResourceName = $target.PrefixListName
                                    ResourceId = $target.PrefixListId
                                    Action = 'Create'
                                }
                            )
                        }
                        else {
                            if ($null -eq $target -and !($null -eq $evidence)) {
                                $target = $evidence
                            }

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

                            # Add an object to the result list
                            $ret.Add(
                                [PSCustomObject]@{
                                    ResourceType = [Pasm.Parameter.Resource]::PrefixList
                                    ResourceName = $target.PrefixListName
                                    ResourceId = $target.PrefixListId
                                    Action = 'Sync'
                                }
                            )
                        }
                    }
                }

                # Update metadata section
                if ($obj.Contains('MetaData')) {
                    $metadata = [ordered]@{}
                    $metadata.UpdateNumber = if ($obj.MetaData.Contains('UpdateNumber')) { $obj.MetaData.UpdateNumber }
                    $metadata.DeployNumber = if ($obj.MetaData.Contains('DeployNumber')) { $obj.MetaData.DeployNumber + 1 } else { 1 }
                    $metadata.CleanUpNumber = if ($obj.MetaData.Contains('CleanUpNumber')) { $obj.MetaData.CleanUpNumber }
                    $metadata.PublishedAt = if ($obj.MetaData.Contains('PublishedAt')) { $obj.MetaData.PublishedAt }
                    $metadata.CreatedAt = if ($obj.MetaData.Contains('CreatedAt')) { ([datetime]$obj.Metadata.CreatedAt).ToUniversalTime() }
                    $metadata.UpdatedAt = if ($obj.MetaData.Contains('UpdatedAt')) { ([datetime]$obj.Metadata.UpdatedAt).ToUniversalTime() }
                    $metadata.DeployedAt = [datetime]::Now.ToUniversalTime()
                    $metadata.CleandAt = if ($obj.MetaData.Contains('CleandAt')) { ([datetime]$obj.Metadata.CleandAt).ToUniversalTime() }
                    $obj.MetaData = $metadata
                }

                # Convert the object to Yaml format and overwrite the file
                $obj | ConvertTo-Yaml -OutFile $file -Force

                # Return result list
                $PSCmdlet.WriteObject($ret)

                # Clear AWS default settings for this session
                Clear-AWSDefaultConfiguration -SkipProfileStore
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