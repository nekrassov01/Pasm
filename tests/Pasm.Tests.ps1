#requires -Modules AWS.Tools.Common
#requires -Modules AWS.Tools.EC2
#requires -Modules PowerShell-Yaml

using namespace System.IO
using namespace System.Collections.Generic

$script:sepalator = [path]::DirectorySeparatorChar

function script:New-PasmTestVpc {
    param (
        [string]$ProfileName = 'default'
    )

    # Set AWS default settings for this session
    Set-DefaultAWSRegion -Region 'ap-northeast-1' -Scope Local
    Set-AWSCredential -ProfileName $profileName -Scope Local

    # Create temporary vpc for test
    $vpc = New-EC2Vpc -CidrBlock '192.168.100.0/24' -InstanceTenancy default

    # Create temporary subnet for test
    $subnet_a = New-EC2Subnet -VpcId $vpc.VpcId -AvailabilityZone 'ap-northeast-1a' -CidrBlock '192.168.100.0/25'
    $subnet_c = New-EC2Subnet -VpcId $vpc.VpcId -AvailabilityZone 'ap-northeast-1c' -CidrBlock '192.168.100.128/25'

    # Create return object
    $resource = [ordered]@{}
    $resource.VpcId = $vpc.VpcId
    $resource.SubnetId_A = $subnet_a.SubnetId
    $resource.SubnetId_C = $subnet_c.SubnetId

    # Clear AWS default settings for this session
    Clear-AWSDefaultConfiguration -SkipProfileStore

    return $resource
}

function script:New-PasmTestTemplate {
    param (
        [object]$InputObject,
        [string]$TemplateFilePath,
        [switch]$SkipSubnetId
    )

    # Load the template file
    $template = ConvertFrom-Yaml -Yaml $(Get-Content -LiteralPath $templateFilePath -Raw) -Ordered

    # Set vpc id to the template: 'SecurityGroup'
    if ($template.Resource.Contains('SecurityGroup')) {
        foreach ($sg in $template.Resource.SecurityGroup) {
            if ($sg.Contains('VpcId')) {
                $sg.VpcId = $inputObject.VpcId 
            }
        }
    }

    # Set vpc id and subnet ids to the template: 'NetworkAcl'
    if ($template.Resource.Contains('NetworkAcl')) {
        foreach ($nacl in $template.Resource.NetworkAcl) {
            if ($nacl.Contains('VpcId')) {
                $nacl.VpcId = $inputObject.VpcId
            }
            if (!$PSBoundParameters.ContainsKey('SkipSubnetId')) {
                if ($nacl.Contains('AssociationSubnetId')) {
                    $subnets = [list[string]]::new()
                    if ($inputObject.Contains('SubnetId_A')) {
                        $subnets.Add($inputObject.SubnetId_A)
                    }
                    if ($inputObject.Contains('SubnetId_C')) {
                        $subnets.Add($inputObject.SubnetId_C)
                    }
                    $nacl.AssociationSubnetId = $subnets
                }
            }
        }
    }

    # Set vpc id to the template: 'PrefixList'
    if ($template.Resource.Contains('PrefixList')) {
        foreach ($pl in $template.Resource.PrefixList) {
            if ($pl.Contains('VpcId')) {
                $pl.VpcId = $inputObject.VpcId 
            }
        }
    }

    # Output template for test
    $workingDirectory = $PSScriptRoot, '.work' -join $sepalator
    New-Item -Path $workingDirectory -ItemType Directory -Force | Out-Null
    $outputFilePath = $workingDirectory, [path]::GetFileName($templateFilePath) -join $sepalator
    $template | ConvertTo-Yaml -OutFile $outputFilePath -Force

    return [fileinfo]::new($outputFilePath)
}

function script:Remove-PasmTestResource {
    param (
        [string]$BlueprintFilePath,
        [string]$ProfileName = 'default'
    )

    # Set AWS default settings for this session
    Set-DefaultAWSRegion -Region 'ap-northeast-1' -Scope Local
    Set-AWSCredential -ProfileName $profileName -Scope Local

    # Load the blueprint file
    $blueprint = ConvertFrom-Yaml -Yaml $(Get-Content -LiteralPath $blueprintFilePath -Raw) -Ordered

    # Remove security group
    if ($blueprint.Resource.Contains('SecurityGroup')) {
        foreach ($sg in $blueprint.Resource.SecurityGroup) {
            $isExists = Get-EC2SecurityGroup -Filter @{ Name = 'group-id'; Values = $sg.ResourceId }
            if ($isExists) {
                Remove-EC2SecurityGroup -GroupId $sg.ResourceId -Force -Confirm:$false
            }
        }
    }

    # Replace the association and remove network acl
    if ($blueprint.Resource.Contains('NetworkAcl')) {
        foreach ($nacl in $blueprint.Resource.NetworkAcl) {
            if ($nacl.Contains('AssociationSubnetId')) {
                $isExists = Get-EC2NetworkAcl -Filter @{ Name = 'network-acl-id'; Values = $nacl.ResourceId }
                if ($isExists) {
                    $assocs = (Get-EC2NetworkAcl -NetworkAclId $nacl.ResourceId).Associations.NetworkAclAssociationId
                    foreach ($assoc in $assocs) {
                        $targetNacl = Get-EC2NetworkAcl -Filter @(@{ Name = 'vpc-id'; Values = $nacl.VpcId }; @{ Name = 'default'; Values = 'true' })
                        Set-EC2NetworkAclAssociation -NetworkAclId $targetNacl.NetworkAclId -AssociationId $assoc -Force -Confirm:$false
                    }
                    Remove-EC2NetworkAcl -NetworkAclId $nacl.ResourceId -Force -Confirm:$false
                }
            }
        }
    }

    # Remove prefix list
    if ($blueprint.Resource.Contains('PrefixList')) {
        foreach ($pl in $blueprint.Resource.PrefixList) {
            $isExists = Get-EC2ManagedPrefixList -Filter @{ Name = 'prefix-list-id'; Values = $pl.ResourceId }
            if ($isExists) {
                Remove-EC2ManagedPrefixList -PrefixListId $pl.ResourceId -Force -Confirm:$false
            }
        }
    }         

    # Clear AWS default settings for this session
    Clear-AWSDefaultConfiguration -SkipProfileStore
}

function script:Remove-PasmTestVpc {
    param (
        [object]$InputObject, # Passed from New-PasmTestVpc
        [string]$ProfileName = 'default'
    )

    # Set AWS default settings for this session
    Set-DefaultAWSRegion -Region 'ap-northeast-1' -Scope Local
    Set-AWSCredential -ProfileName $profileName -Scope Local

    # Remove temporary subnets
    Remove-EC2Subnet -SubnetId $inputObject.SubnetId_A -Force -Confirm:$false
    Remove-EC2Subnet -SubnetId $inputObject.SubnetId_C -Force -Confirm:$false

    # Remove temporary vpc
    Remove-EC2Vpc -VpcId $inputObject.VpcId -Force -Confirm:$false

    # Clear AWS default settings for this session
    Clear-AWSDefaultConfiguration -SkipProfileStore
}

Import-Module -Name $($PSScriptRoot, '..', 'src', 'Pasm.psm1' -join $sepalator) -Force

InModuleScope 'Pasm' {
    Describe 'UnitTest' {
        BeforeAll {
            $script:workingDirectory = $PSScriptRoot, '.work' -join $sepalator
            $script:path = [path]::GetDirectoryName($workingDirectory)
            $script:name = [path]::GetFileName($workingDirectory)
            $script:obj = New-PasmTestVpc
            Write-Output $obj
        }
        Context 'RunWithBasicTemplate1' {
            BeforeAll {
                $script:templateFilePath = $PSScriptRoot, 'templates', 'outline.success.1.yml' -join $sepalator
                $script:outlineFilePath = (New-PasmTestTemplate $obj -TemplateFilePath $templateFilePath).FullName
                $script:blueprintFileName = 'blueprint.success.1.yml'
                $script:blueprintFilePath = $PSScriptRoot, '.work', $blueprintFileName -join $sepalator
            }
            Context 'ExpectedToPass' {
                It 'Validation' {
                    Invoke-PasmValidation -FilePath $outlineFilePath | Should -BeTrue
                }
                It 'Blueprint' {
                    Invoke-PasmBlueprint -FilePath $outlineFilePath -OutputFileName $blueprintFileName | Should -BeTrue
                }
                It 'Deployment: Create' {
                    Invoke-PasmDeployment -FilePath $blueprintFilePath | Should -BeTrue
                }
                It 'Deployment: Sync' {
                    Invoke-PasmDeployment -FilePath $blueprintFilePath | Should -BeTrue
                }
                It 'CleanUp' {
                    Invoke-PasmCleanUp -FilePath $blueprintFilePath | Should -BeTrue
                }
            }
            AfterAll {
                Remove-PasmTestResource -BlueprintFilePath $blueprintFilePath
            }
        }
        Context 'RunWithBasicTemplate2' {
            BeforeAll {
                $script:templateFilePath = $PSScriptRoot, 'templates', 'outline.success.2.yml' -join $sepalator
                $script:outlineFilePath = (New-PasmTestTemplate $obj -TemplateFilePath $templateFilePath).FullName
                $script:blueprintFileName = 'blueprint.success.2.yml'
                $script:blueprintFilePath = $PSScriptRoot, '.work', $blueprintFileName -join $sepalator
            }
            Context 'ExpectedToPass' {
                It 'Validation' {
                    Invoke-PasmValidation -FilePath $outlineFilePath | Should -BeTrue
                }
                It 'Blueprint' {
                    Invoke-PasmBlueprint -FilePath $outlineFilePath -OutputFileName $blueprintFileName | Should -BeTrue
                }
                It 'Deployment: Create' {
                    Invoke-PasmDeployment -FilePath $blueprintFilePath | Should -BeTrue
                }
                It 'Deployment: Sync' {
                    Invoke-PasmDeployment -FilePath $blueprintFilePath | Should -BeTrue
                }
                It 'CleanUp' {
                    Invoke-PasmCleanUp -FilePath $blueprintFilePath | Should -BeTrue
                }
            }
            AfterAll {
                Remove-PasmTestResource -BlueprintFilePath $blueprintFilePath
            }
        }
        Context 'InitializeWithTargetVpcParameter' {
            Context 'ExpectedToPass' {
                BeforeEach {
                    Set-AWSCredential -ProfileName 'default' -Scope Local
                    Set-DefaultAWSRegion -Region 'ap-northeast-1' -Scope Local
                }
                It 'Initialize: VpcId' {
                    Invoke-PasmInitialize -Path $path -Name $name -VpcId $obj.VpcId -Force | Should -BeTrue
                }
                It 'Initialize: AssociationSubnetId' {
                    Invoke-PasmInitialize -Path $path -Name $name -SubnetId $obj.SubnetId_A, $obj.SubnetId_C -Force | Should -BeTrue
                }
                It 'Initialize: Both' {
                    Invoke-PasmInitialize -Path $path -Name $name -VpcId $obj.VpcId -SubnetId $obj.SubnetId_A, $obj.SubnetId_C -Force | Should -BeTrue
                }
                It 'Blueprint' {
                    Invoke-PasmBlueprint -FilePath $($workingDirectory, $('{0}.yml' -f [Pasm.Template.Name]::outline) -join $sepalator) -OutputFileName $('{0}.yml' -f [Pasm.Template.Name]::blueprint) | Should -BeTrue
                }
                AfterEach {
                    Clear-AWSDefaultConfiguration -SkipProfileStore
                }
            }
            Context 'ExpectedToThrow' {
                BeforeEach {
                    Set-AWSCredential -ProfileName 'default' -Scope Local
                    Set-DefaultAWSRegion -Region 'ap-northeast-1' -Scope Local
                }
                It 'Initialize: VpcId' {
                    { Invoke-PasmInitialize -Path $path -Name $name -VpcId 'Vpc-01234567891234567' -Force } | Should -Throw
                }
                It 'Initialize: AssociationSubnetId' {
                    { Invoke-PasmInitialize -Path $path -Name $name -SubnetId 'subnet-01234567891234567', 'subnet-abcdefghijklmnopq!' -Force } | Should -Throw
                }
                It 'Initialize: Both' {
                    { Invoke-PasmInitialize -Path $path -Name $name -VpcId 'vpc-01234567891234567' -SubnetId 'subnet-01234567891234567', 'Subnet-abcdefghijklmnopq' -Force } | Should -Throw
                }
                AfterEach {
                    Clear-AWSDefaultConfiguration -SkipProfileStore
                }
            }
        }
        Context 'InvokeValidationError' {
            Context 'ExpectedToThrow' {
                It 'Parent: Key.Invalid' {
                    $templateName = 'outline.error.parent.key.invalid.yml'
                    $templateFilePath = $PSScriptRoot, 'templates', $templateName -join $sepalator
                    { Invoke-PasmValidation -FilePath $templateFilePath } | Should -Throw
                }
                It 'Parent: Key.NotRequired.Common' {
                    $templateName = 'outline.error.parent.key.not-required.common.yml'
                    $templateFilePath = $PSScriptRoot, 'templates', $templateName -join $sepalator
                    { Invoke-PasmValidation -FilePath $templateFilePath } | Should -Throw
                }
                It 'Parent: Key.NotRequired.Resource' {
                    $templateName = 'outline.error.parent.key.not-required.resource.yml'
                    $templateFilePath = $PSScriptRoot, 'templates', $templateName -join $sepalator
                    { Invoke-PasmValidation -FilePath $templateFilePath } | Should -Throw
                }
                It 'Parent: Key.Empty.Common' {
                    $templateName = 'outline.error.parent.key.empty.common.yml'
                    $templateFilePath = $PSScriptRoot, 'templates', $templateName -join $sepalator
                    { Invoke-PasmValidation -FilePath $templateFilePath } | Should -Throw
                }
                It 'Parent: Key.Empty.Resource' {
                    $templateName = 'outline.error.parent.key.empty.resource.yml'
                    $templateFilePath = $PSScriptRoot, 'templates', $templateName -join $sepalator
                    { Invoke-PasmValidation -FilePath $templateFilePath } | Should -Throw
                }
                It 'Common: Key.Invalid' {
                    $templateName = 'outline.error.common.key.invalid.yml'
                    $templateFilePath = $PSScriptRoot, 'templates', $templateName -join $sepalator
                    { Invoke-PasmValidation -FilePath $templateFilePath } | Should -Throw
                }
                It 'Common: Key.NotRequired.Region' {
                    $templateName = 'outline.error.common.key.not-required.region.yml'
                    $templateFilePath = $PSScriptRoot, 'templates', $templateName -join $sepalator
                    { Invoke-PasmValidation -FilePath $templateFilePath } | Should -Throw
                }
                It 'Common: Key.NotRequired.ProfileName' {
                    $templateName = 'outline.error.common.key.not-required.profile-name.yml'
                    $templateFilePath = $PSScriptRoot, 'templates', $templateName -join $sepalator
                    { Invoke-PasmValidation -FilePath $templateFilePath } | Should -Throw
                }
                It 'Common: Key.Empty.Region' {
                    $templateName = 'outline.error.common.key.empty.region.yml'
                    $templateFilePath = $PSScriptRoot, 'templates', $templateName -join $sepalator
                    { Invoke-PasmValidation -FilePath $templateFilePath } | Should -Throw
                }
                It 'Common: Key.Empty.ProfileName' {
                    $templateName = 'outline.error.common.key.empty.profile-name.yml'
                    $templateFilePath = $PSScriptRoot, 'templates', $templateName -join $sepalator
                    { Invoke-PasmValidation -FilePath $templateFilePath } | Should -Throw
                }
                It 'Common: Value.Scalar.Region' {
                    $templateName = 'outline.error.common.value.scalar.region.yml'
                    $templateFilePath = $PSScriptRoot, 'templates', $templateName -join $sepalator
                    { Invoke-PasmValidation -FilePath $templateFilePath } | Should -Throw
                }
                It 'Common: Value.Scalar.ProfileName' {
                    $templateName = 'outline.error.common.value.scalar.profile-name.yml'
                    $templateFilePath = $PSScriptRoot, 'templates', $templateName -join $sepalator
                    { Invoke-PasmValidation -FilePath $templateFilePath } | Should -Throw
                }
                It 'Common: Value.API.Region' {
                    $templateName = 'outline.error.common.value.api.region.yml'
                    $templateFilePath = $PSScriptRoot, 'templates', $templateName -join $sepalator
                    { Invoke-PasmValidation -FilePath $templateFilePath } | Should -Throw
                }
                It 'Common: Value.API.ProfileName' {
                    $templateName = 'outline.error.common.value.api.profile-name.yml'
                    $templateFilePath = $PSScriptRoot, 'templates', $templateName -join $sepalator
                    { Invoke-PasmValidation -FilePath $templateFilePath } | Should -Throw
                }
                It 'Resource: Key.Invalid' {
                    $templateName = 'outline.error.resource.key.invalid.yml'
                    $templateFilePath = $PSScriptRoot, 'templates', $templateName -join $sepalator
                    $outlineFilePath = (New-PasmTestTemplate $obj -TemplateFilePath $templateFilePath).FullName
                    { Invoke-PasmValidation -FilePath $outlineFilePath } | Should -Throw
                }
                It 'Resource: Key.Empty.SecurityGroup' {
                    $templateName = 'outline.error.resource.key.empty.security-group.yml'
                    $templateFilePath = $PSScriptRoot, 'templates', $templateName -join $sepalator
                    $outlineFilePath = (New-PasmTestTemplate $obj -TemplateFilePath $templateFilePath).FullName
                    { Invoke-PasmValidation -FilePath $outlineFilePath } | Should -Throw
                }
                It 'Resource: Key.Empty.NetworkAcl' {
                    $templateName = 'outline.error.resource.key.empty.network-acl.yml'
                    $templateFilePath = $PSScriptRoot, 'templates', $templateName -join $sepalator
                    $outlineFilePath = (New-PasmTestTemplate $obj -TemplateFilePath $templateFilePath).FullName
                    { Invoke-PasmValidation -FilePath $outlineFilePath } | Should -Throw
                }
                It 'Resource: Key.Empty.PrefixList' {
                    $templateName = 'outline.error.resource.key.empty.prefix-list.yml'
                    $templateFilePath = $PSScriptRoot, 'templates', $templateName -join $sepalator
                    $outlineFilePath = (New-PasmTestTemplate $obj -TemplateFilePath $templateFilePath).FullName
                    { Invoke-PasmValidation -FilePath $outlineFilePath } | Should -Throw
                }
                It 'Sample: Range' {
                    $templateName = 'outline.error.sample.range.yml'
                    $templateFilePath = $PSScriptRoot, 'templates', $templateName -join $sepalator
                    $outlineFilePath = (New-PasmTestTemplate $obj -TemplateFilePath $templateFilePath).FullName
                    { Invoke-PasmValidation -FilePath $outlineFilePath } | Should -Throw
                }
                It 'Sample: FromTo' {
                    $templateName = 'outline.error.sample.from-to.yml'
                    $templateFilePath = $PSScriptRoot, 'templates', $templateName -join $sepalator
                    $outlineFilePath = (New-PasmTestTemplate $obj -TemplateFilePath $templateFilePath).FullName
                    { Invoke-PasmValidation -FilePath $outlineFilePath } | Should -Throw
                }
                It 'Sample: Bool' {
                    $templateName = 'outline.error.sample.bool.yml'
                    $templateFilePath = $PSScriptRoot, 'templates', $templateName -join $sepalator
                    $outlineFilePath = (New-PasmTestTemplate $obj -TemplateFilePath $templateFilePath).FullName
                    { Invoke-PasmValidation -FilePath $outlineFilePath } | Should -Throw
                }
                It 'Sample: ServiceKey' {
                    $templateName = 'outline.error.sample.service-key.yml'
                    $templateFilePath = $PSScriptRoot, 'templates', $templateName -join $sepalator
                    $outlineFilePath = (New-PasmTestTemplate $obj -TemplateFilePath $templateFilePath).FullName
                    { Invoke-PasmValidation -FilePath $outlineFilePath } | Should -Throw
                }
                It 'Sample: Region' {
                    $templateName = 'outline.error.sample.region.yml'
                    $templateFilePath = $PSScriptRoot, 'templates', $templateName -join $sepalator
                    $outlineFilePath = (New-PasmTestTemplate $obj -TemplateFilePath $templateFilePath).FullName
                    { Invoke-PasmValidation -FilePath $outlineFilePath } | Should -Throw
                }
                It 'Sample: VpcId' {
                    $templateName = 'outline.error.sample.vpc-id.yml'
                    $templateFilePath = $PSScriptRoot, 'templates', $templateName -join $sepalator
                    { Invoke-PasmValidation -FilePath $templateFilePath } | Should -Throw
                }
                It 'Sample: SubnetId' {
                    $templateName = 'outline.error.sample.subnet-id.yml'
                    $templateFilePath = $PSScriptRoot, 'templates', $templateName -join $sepalator
                    $outlineFilePath = (New-PasmTestTemplate $obj -TemplateFilePath $templateFilePath -SkipSubnetId).FullName
                    { Invoke-PasmValidation -FilePath $outlineFilePath } | Should -Throw
                }
            }
        }
        Context 'RunWithAlias' {
            BeforeAll {
                $script:templateFilePath = $PSScriptRoot, 'templates', 'outline.success.1.yml' -join $sepalator
                $script:outlineFilePath = (New-PasmTestTemplate $obj -TemplateFilePath $templateFilePath).FullName
                $script:blueprintFileName = 'blueprint.success.1.yml'
                $script:blueprintFilePath = $PSScriptRoot, '.work', $blueprintFileName -join $sepalator
            }
            Context 'ExpectedToPass' {
                It 'Alias: psmi' {
                    psmi -p $path -n $name -vpc $obj.VpcId -sbn $obj.SubnetId_A, $obj.SubnetId_C -Force | Should -BeTrue
                }
                It 'Alias: psmv' {
                    psmv -file $outlineFilePath | Should -BeTrue
                }
                It 'Alias: psmb' {
                    psmb -file $outlineFilePath -out $blueprintFileName | Should -BeTrue
                }
                It 'Alias: psmd' {
                    psmd -file $blueprintFilePath | Should -BeTrue
                }
                It 'Alias: psma' {
                    psma -file $outlineFilePath -out $blueprintFileName | Should -BeTrue
                }
                It 'Alias: psmc' {
                    psmc -file $blueprintFilePath | Should -BeTrue
                }
                AfterAll {
                    Remove-PasmTestResource -BlueprintFilePath $blueprintFilePath
                }
            }
        }
        AfterAll {
            Remove-Item -LiteralPath $workingDirectory -Recurse -Force | Out-Null
            Remove-PasmTestVpc $obj
        }
    }
}
