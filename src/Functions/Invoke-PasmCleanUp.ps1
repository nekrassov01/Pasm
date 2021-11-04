#Requires -Version 5.1
using namespace System.IO
using namespace System.Management.Automation
using namespace System.Collections.Generic
using namespace Amazon.EC2.Model

function Invoke-PasmCleanUp {
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

                # Detach SecurityGroup association: ENI
                # Remove SecurityGroup
                if ($resource.Contains('SecurityGroup')) {
                    foreach ($sg in $securityGroup) {
                        $target = Get-EC2SecurityGroup -Filter @{ Name = 'group-id'; Values = $sg.ResourceId }
                        if ($null -ne $target) {
                            $groupList = [list[string]]::new()
                            $detachedList = [list[string]]::new()
                            $remainingList = [list[string]]::new()
                            $action = 'CleanUp'
                            
                            # Get the ENI to which the target security group is attached
                            $eni = Get-EC2NetworkInterface -Filter @{ Name = 'group-id'; Values = $sg.ResourceId }
                            if ($eni) {
                                # If it is a requester-managed ENI, it cannot be detached, so skip this step.
                                foreach ($e in $eni) {
                                    if ($e.RequesterManaged -eq $true) {
                                        $action = 'Skip'
                                        $remainingList.Add($e.NetworkInterfaceId)
                                    }
                                    else {
                                        foreach ($groupId in $e.Groups.GroupId) {
                                            if ($groupId -ne $sg.ResourceId) {
                                                $groupList.Add($groupId)
                                            }
                                        }
                                        if ($groupList) {
                                            Edit-EC2NetworkInterfaceAttribute -NetworkInterfaceId $e.NetworkInterfaceId -Group $groupList | Out-Null
                                        }
                                        else {
                                            $filter = @(
                                                @{ Name = 'group-name'; Values = 'default' }
                                                @{ Name = 'vpc-id'; Values = $sg.VpcId }
                                            )
                                            $defaultSg = Get-EC2SecurityGroup -Filter $filter
                                            Edit-EC2NetworkInterfaceAttribute -NetworkInterfaceId $e.NetworkInterfaceId -Group $defaultSg.GroupId | Out-Null
                                        }
                                        $detachedList.Add($e.NetworkInterfaceId)
                                    }
                                }
                            }
                            if ((!$eni) -or ($eni -and $eni.RequesterManaged -notcontains $true)) {
                                Remove-EC2SecurityGroup -GroupId $sg.ResourceId -Confirm:$false | Out-Null
                            }

                            $ret.Add(
                                [PSCustomObject]@{
                                    ResourceType = [Pasm.Parameter.Resource]::SecurityGroup
                                    ResourceName = $target.GroupName
                                    ResourceId = $target.GroupId
                                    Detached = if ($detachedList) { @($detachedList) } else { $null }
                                    Skipped = if ($remainingList) { @($remainingList) } else { $null }
                                    Action = $action
                                }
                            )

                        }
                    }
                }

                # Detach NetworkAcl association: subnets
                # Remove NetworkAcl
                if ($resource.Contains('NetworkAcl')) {
                    foreach ($nacl in $networkAcl) {
                        $target = Get-EC2NetworkAcl -Filter @{ Name = 'network-acl-id'; Values = $nacl.ResourceId }
                        if ($null -ne $target) {
                            if ($nacl.AssociationSubnetId) {
                                foreach ($subnetId in $nacl.AssociationSubnetId) {
                                    $naclAssocs = (Get-EC2NetworkAcl -Filter @{ Name = 'association.subnet-id'; Values = $subnetId }).Associations
                                    if ($naclAssocs.NetworkAclAssociationId) {
                                        $defautlNacl = Get-EC2NetworkAcl -Filter @(@{ Name = 'default'; Values = 'true' }; @{ Name = 'vpc-id'; Values = $nacl.VpcId })
                                        foreach ($naclAssoc in $naclAssocs) {
                                            Set-EC2NetworkAclAssociation -NetworkAclId $defautlNacl.NetworkAclId -AssociationId $naclAssoc.NetworkAclAssociationId | Out-Null
                                        }
                                    }
                                }
                            }
                            Remove-EC2NetworkAcl -NetworkAclId $nacl.ResourceId -Confirm:$false | Out-Null

                            $ret.Add(
                                [PSCustomObject]@{
                                    ResourceType = [Pasm.Parameter.Resource]::NetworkAcl
                                    ResourceName = $target.Tags.Value
                                    ResourceId = $target.NetworkAclId
                                    Detached = if ($naclAssocs) { $naclAssocs.SubnetId } else { $null }
                                    Skipped = $null
                                    Action = 'CleanUp'
                                }
                            )
                        }
                    }
                }

                # Detach PrefixList association: SecurityGroup, RouteTable
                # Remove PrefixList
                if ($resource.Contains('PrefixList')) {
                    foreach ($pl in $prefixList) {
                        $target = Get-EC2ManagedPrefixList -Filter @{ Name = 'prefix-list-id'; Values = $pl.ResourceId }
                        if ($null -ne $target) {
                            $plAssocs = Get-EC2ManagedPrefixListAssociation -PrefixListId $pl.ResourceId
                            if ($plAssocs) {               
                                foreach ($plAssoc in $plAssocs) {
                                    if ($plAssoc.ResourceId -match '^sg-[0-9a-z]{17}$') {
                                        $targetSg = Get-EC2SecurityGroup -Filter @{ Name = 'group-id'; Values = $plAssoc.ResourceId }
                                        if ($targetSg) {
                                            $ingressEntry = $targetSg.IpPermissions.Where( { $_.PrefixListIds } )
                                            if ($ingressEntry) {
                                                Revoke-EC2SecurityGroupIngress -GroupId $plAssoc.ResourceId -IpPermission $ingressEntry | Out-Null
                                            }
                                            $egressEntry = $targetSg.IpPermissionsEgress.Where( { $_.PrefixListIds } )
                                            if ($egressEntry) {
                                                Revoke-EC2SecurityGroupEgress -GroupId $plAssoc.ResourceId -IpPermission $egressEntry | Out-Null
                                            }
                                        }
                                    }
                                    if ($plAssoc.ResourceId -match '^rtb-[0-9a-z]{17}$') {
                                        $targetRoute = Get-EC2RouteTable -Filter @{ Name = 'route.destination-prefix-list-id'; Values = $pl.ResourceId }
                                        if ($targetRoute) {
                                            foreach ($routeTableId in $targetRoute.RouteTableId) {
                                                Remove-EC2Route -RouteTableId $routeTableId -DestinationPrefixListId $pl.ResourceId -Confirm:$false | Out-Null
                                            }
                                        }
                                    }
                                }
                            }
                            Remove-EC2ManagedPrefixList -PrefixListId $pl.ResourceId -Confirm:$false | Out-Null

                            $ret.Add(
                                [PSCustomObject]@{
                                    ResourceType = [Pasm.Parameter.Resource]::PrefixList
                                    ResourceName = $target.PrefixListName
                                    ResourceId = $target.PrefixListId
                                    Detached = if ($plAssocs) { @($plAssocs.ResourceId) } else { $null }
                                    Skipped = $null
                                    Action = 'CleanUp'
                                }
                            )
                        }
                    }
                }

                # Return result list
                $PSCmdlet.WriteObject($ret)

                # Clear AWS default settings for this session
                Clear-AWSDefaultConfiguration -SkipProfileStore

                # Update metadata section
                if ($obj.Contains('MetaData')) {
                    $metadata = [ordered]@{}
                    $metadata.UpdateNumber = if ($obj.MetaData.Contains('UpdateNumber')) { $obj.MetaData.UpdateNumber }
                    $metadata.DeployNumber = if ($obj.MetaData.Contains('DeployNumber')) { $obj.MetaData.DeployNumber }
                    $metadata.CleanUpNumber = if ($obj.MetaData.Contains('CleanUpNumber')) { $obj.MetaData.CleanUpNumber + 1 } else { 1 }
                    $metadata.PublishedAt = if ($obj.MetaData.Contains('PublishedAt')) { $obj.MetaData.PublishedAt }
                    $metadata.CreatedAt = if ($obj.MetaData.Contains('CreatedAt')) { $obj.MetaData.CreatedAt }
                    $metadata.UpdatedAt = if ($obj.MetaData.Contains('UpdatedAt')) { $obj.MetaData.UpdatedAt }
                    $metadata.DeployedAt = if ($obj.MetaData.Contains('DeployedAt')) { $obj.MetaData.DeployedAt }
                    $metadata.CleandAt = [datetime]::Now.ToUniversalTime()
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
        Clean up the deployed resources. Force detach of associated resources. Skip requester-managed ENIs, as they cannot be detached.

        .DESCRIPTION
        Clean up the deployed resources. Force detach of associated resources. Skip requester-managed ENIs, as they cannot be detached.
        See the following source for details: https://github.com/nekrassov01/Pasm/blob/main/src/Functions/Invoke-PasmCleanUp.ps1
    
        .EXAMPLE
        # Default input file path: ${PWD}/blueprint.yml
        Invoke-PasmCleanUp

        .EXAMPLE
        # Loading multiple files
        Invoke-PasmCleanUp -FilePath 'C:/Pasm/blueprint-sg.yml', 'C:/Pasm/blueprint-nacl.yml', 'C:/Pasm/blueprint-pl.yml'

        .EXAMPLE
        # Loading multiple files from pipeline
        'C:/Pasm/blueprint-sg.yml', 'C:/Pasm/blueprint-nacl.yml', 'C:/Pasm/blueprint-pl.yml' | Invoke-PasmCleanUp

        .LINK
        https://github.com/nekrassov01/Pasm
    #>
}
