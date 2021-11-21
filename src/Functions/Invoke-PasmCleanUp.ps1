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
        [string[]]$FilePath = $($PWD, $('{0}.yml' -f [Pasm.Template.Name]::blueprint) -join [path]::DirectorySeparatorChar),

        # If the ResourceName matches even if the ResourceId does not, cleanup is performed.
        [Parameter(Mandatory = $false)]
        [switch]$Force
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

                        if ($PSBoundParameters.ContainsKey('Force')) {
                            $evidence = Get-EC2SecurityGroup -Filter @{ Name = 'group-name'; Values = $sg.ResourceName }
                            if ($null -eq $target -and $null -ne $evidence) {
                                $target = $evidence
                            }
                        }

                        if ($null -ne $target) {
                            $groupList = [list[string]]::new()
                            $detachedList = [list[string]]::new()
                            $remainingList = [list[string]]::new()
                            $action = 'CleanUp'

                            # Get the ENI to which the target security group is attached
                            $eni = Get-EC2NetworkInterface -Filter @{ Name = 'group-id'; Values = $target.GroupId }
                            if ($eni) {
                                # If it is a requester-managed ENI, it cannot be detached, so skip this step
                                foreach ($e in $eni) {
                                    if ($e.RequesterManaged -eq $true) {
                                        $action = 'Skip'
                                        $remainingList.Add($e.NetworkInterfaceId)
                                    }
                                    else {
                                        foreach ($groupId in $e.Groups.GroupId) {
                                            if ($groupId -ne $target.GroupId) {
                                                $groupList.Add($groupId)
                                            }
                                        }
                                        if ($groupList) {
                                            Edit-EC2NetworkInterfaceAttribute -NetworkInterfaceId $e.NetworkInterfaceId -Group $groupList | Out-Null
                                        }
                                        else {
                                            $defaultSg = Get-EC2SecurityGroup -Filter @(@{ Name = 'group-name'; Values = 'default' }; @{ Name = 'vpc-id'; Values = $target.VpcId })
                                            Edit-EC2NetworkInterfaceAttribute -NetworkInterfaceId $e.NetworkInterfaceId -Group $defaultSg.GroupId | Out-Null
                                        }
                                        $detachedList.Add($e.NetworkInterfaceId)
                                    }
                                }
                            }

                            if ((!$eni) -or ($eni -and $eni.RequesterManaged -notcontains $true)) {
                                Remove-EC2SecurityGroup -GroupId $target.GroupId -Confirm:$false | Out-Null
                                $sg.ResourceId = 'cleaned'
                            }

                            $ret.Add(
                                [PSCustomObject]@{
                                    ResourceType = [Pasm.Parameter.Resource]::SecurityGroup
                                    ResourceName = $target.GroupName
                                    ResourceId = $target.GroupId
                                    Detached = if ($detachedList) { $detachedList } else { $null }
                                    Skipped = if ($remainingList) { $remainingList } else { $null }
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

                        if ($PSBoundParameters.ContainsKey('Force')) {
                            $evidence = Get-EC2NetworkAcl -Filter @{ Name = 'tag:Name'; Values = $nacl.ResourceName }
                            if ($null -eq $target -and $null -ne $evidence) {
                                $target = $evidence
                            }
                        }

                        if ($null -ne $target) {
                            $subnetList = [list[string]]::new()
                            $naclAssocs = $target.Associations
                            $defautlNacl = Get-EC2NetworkAcl -Filter @(@{ Name = 'default'; Values = 'true' }; @{ Name = 'vpc-id'; Values = $target.VpcId })
                            if ($naclAssocs) {
                                foreach ($naclAssoc in $naclAssocs) {
                                    Set-EC2NetworkAclAssociation -NetworkAclId $defautlNacl.NetworkAclId -AssociationId $naclAssoc.NetworkAclAssociationId | Out-Null
                                    $subnetList.Add($naclAssoc.SubnetId)
                                }
                            }
                            Remove-EC2NetworkAcl -NetworkAclId $target.NetworkAclId -Confirm:$false | Out-Null
                            $nacl.ResourceId = 'cleaned'

                            $ret.Add(
                                [PSCustomObject]@{
                                    ResourceType = [Pasm.Parameter.Resource]::NetworkAcl
                                    ResourceName = $target.Tags.Value
                                    ResourceId = $target.NetworkAclId
                                    Detached = if ($subnetList) { $subnetList } else { $null }
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

                        if ($PSBoundParameters.ContainsKey('Force')) {
                            $evidence = Get-EC2ManagedPrefixList -Filter @{ Name = 'prefix-list-name'; Values = $pl.ResourceName }
                            if ($null -eq $target -and $null -ne $evidence) {
                                $target = $evidence
                            }
                        }

                        if ($null -ne $target) {
                            $resourceList = [list[string]]::new()
                            $plAssocs = Get-EC2ManagedPrefixListAssociation -PrefixListId $target.PrefixListId
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
                                            $resourceList.Add($plAssoc.ResourceId)
                                        }
                                    }
                                    if ($plAssoc.ResourceId -match '^rtb-[0-9a-z]{17}$') {
                                        $targetRtb = Get-EC2RouteTable -Filter @{ Name = 'route.destination-prefix-list-id'; Values = $target.PrefixListId }
                                        if ($targetRtb) {
                                            foreach ($rtb in $targetRtb) {
                                                Remove-EC2Route -RouteTableId $rtb.RouteTableId -DestinationPrefixListId $target.PrefixListId -Confirm:$false | Out-Null
                                                $resourceList.Add($plAssoc.ResourceId)
                                            }
                                        }
                                    }
                                }
                            }
                            Remove-EC2ManagedPrefixList -PrefixListId $target.PrefixListId -Confirm:$false | Out-Null
                            $pl.ResourceId = 'cleaned'

                            $ret.Add(
                                [PSCustomObject]@{
                                    ResourceType = [Pasm.Parameter.Resource]::PrefixList
                                    ResourceName = $target.PrefixListName
                                    ResourceId = $target.PrefixListId
                                    Detached = if ($resourceList) { $resourceList } else { $null }
                                    Skipped = $null
                                    Action = 'CleanUp'
                                }
                            )
                        }
                    }
                }

                # Update metadata section
                if ($obj.Contains('MetaData')) {
                    $metadata = [ordered]@{}
                    $metadata.UpdateNumber = if ($obj.MetaData.Contains('UpdateNumber')) { $obj.MetaData.UpdateNumber }
                    $metadata.DeployNumber = if ($obj.MetaData.Contains('DeployNumber')) { $obj.MetaData.DeployNumber }
                    $metadata.CleanUpNumber = if ($obj.MetaData.Contains('CleanUpNumber')) { $obj.MetaData.CleanUpNumber + 1 } else { 1 }
                    $metadata.PublishedAt = if ($obj.MetaData.Contains('PublishedAt')) { $obj.MetaData.PublishedAt }
                    $metadata.CreatedAt = if ($obj.MetaData.Contains('CreatedAt')) { ([datetime]$obj.Metadata.CreatedAt).ToUniversalTime() }
                    $metadata.UpdatedAt = if ($obj.MetaData.Contains('UpdatedAt')) { ([datetime]$obj.Metadata.UpdatedAt).ToUniversalTime() }
                    $metadata.DeployedAt = if ($obj.MetaData.Contains('DeployedAt')) { ([datetime]$obj.Metadata.DeployedAt).ToUniversalTime() }
                    $metadata.CleandAt = [datetime]::Now.ToUniversalTime()
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

        .EXAMPLE
        # When the Force switch is enabled, even if the ResourceId does not match, if the ResourceName matches, cleanup will be performed
        Invoke-PasmCleanUp -Force

        .LINK
        https://github.com/nekrassov01/Pasm
    #>
}
