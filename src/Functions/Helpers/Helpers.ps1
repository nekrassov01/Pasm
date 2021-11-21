#Requires -Version 5.1
using namespace System.IO
using namespace System.Management.Automation
using namespace System.Collections.Generic
using namespace Amazon.Util
using namespace Amazon.EC2.Model

# Convert an array of key names to a string (Helper for helper functions)
function Get-ArrayToString {
    param (
        [string[]]$Array
    )
    if (1 -eq @($array).Length) {
        return $('''{0}''' -f $array)
    }
    else {
        return $('''{0}'', and ''{1}''' -f ($array[0..($array.Length - 2)] -join ''', '''), $array[-1])
    }
}

# Create log message line
function Out-PasmLogLine {
    param (
        [string]$Message,
        [switch]$TimePrefix,
        [string]$TimePrefixStyle = '{0} | {1}'
    )
    if ($PSBoundParameters.ContainsKey('TimePrefix')) {
        $message = $timePrefixStyle -f $(Get-Date), $message
    }
    return $message
}

# Import Yaml template file
function Import-PasmFile {
    param (
        [string]$FilePath,
        [switch]$Ordered
    )
    if (!(Test-Path -LiteralPath $filePath)) {
        throw [FileNotFoundException]::new($('Yaml template ''{0}'' does not exist.' -f [path]::GetFileName($filePath)))
    }
    try {
        ConvertFrom-Yaml -Yaml $(Get-Content -LiteralPath $filePath -Raw) -Ordered:$ordered
    }
    catch {
        throw [FormatException]::new($('Yaml template could not be loaded because invalid format detected in ''{0}''.' -f [path]::GetFileName($filePath)))
    }
}

# Yaml template validation: required keys
function Test-PasmRequiredKey {
    param (
        [object]$InputObject,
        [string]$Enum = 'Pasm.RequiredParameter.Parent'
    )
    $member = [enum]::GetNames($enum)
    $label =
    if ($enum -eq 'Pasm.RequiredParameter.Parent') {
        'top-level'
    }
    else {
        '''{0}''' -f $enum.Split('.')[-1]
    }
    foreach ($obj in $inputObject) {
        foreach ($m in $member) {
            if ($m -notin $obj.Keys) {
                throw [FormatException]::new($('The required key ''{0}'' is missing in {1} section.' -f $m, $label))
            }
        }
    }
}

# Yaml template validation: allowed keys
function Test-PasmInvalidKey {
    param (
        [object]$InputObject,
        [string]$Enum = 'Pasm.Parameter.Parent'
    )
    $member = [enum]::GetNames($enum)
    $label =
    if ($enum -eq 'Pasm.Parameter.Parent') {
        'top-level'
    }
    else {
        '''{0}''' -f $enum.Split('.')[-1]
    }
    foreach ($obj in $inputObject) {
        foreach ($o in $obj.GetEnumerator()) {
            if ($o.Key -notin $member) {
                throw [FormatException]::new($('Invalid parameter key ''{0}'' detected. Allowed in {1} section: {2}.' -f $o.Key, $label, $(Get-ArrayToString -Array $member)))
            }
        }
    }
}

# Yaml template validation: at least one key is present
function Test-PasmEmptyKey {
    param (
        [object]$InputObject,
        [string]$Enum = 'Pasm.Parameter.Parent'
    )
    $member = [enum]::GetNames($enum)
    foreach ($m in $member) {
        if ($inputObject.Contains($m)) {
            if ($null -eq $inputObject.$m) {
                throw [FormatException]::new($('Empty section exists: ''{0}''' -f $m))
            }
        }
    }
}

# Yaml template validation: only one value
function Test-PasmScalarValue {
    param (
        [object]$InputObject,
        [string[]]$Key
    )
    foreach ($k in $key) {
        foreach ($obj in $inputObject) {
            if ($obj.Contains($k)) {
                if (1 -ne @($obj.$k).Length) {
                    throw [FormatException]::new($('Only one value can be specified for ''{0}''.' -f $k))
                }
            }
        }
    }
}

# Yaml template validation: allowed values
function Test-PasmInvalidValue {
    param (
        [object]$InputObject,
        [string[]]$Key
    )
    foreach ($k in $key) {
        $member = [enum]::GetNames('Pasm.Parameter.{0}' -f $k)
        foreach ($obj in $inputObject) {
            if ($obj.Contains($k)) {
                foreach ($o in $obj.$k) {
                    if ($o -notin $member) {
                        throw [FormatException]::new($('Invalid parameter value ''{0}'' detected. Allowed in ''{1}'': {2}.' -f $o, $k, $(Get-ArrayToString -Array $member)))
                    }
                }
            }
        }
    }
}

# Yaml template validation: integer range
function Test-PasmRange {
    param (
        [object]$InputObject,
        [string[]]$Key,
        [int]$Start,
        [int]$End
    )
    foreach ($k in $key) {
        foreach ($obj in $inputObject) {
            if ($obj.Contains($k)) {
                foreach ($o in $obj.$k) {
                    if ($o -notin $start..$end) {
                        throw [FormatException]::new($('The ''{0}'' is set to an invalid value of {1}, please set it in the range of {2} to {3}.' -f $k, $o, $start, $end))
                    }
                }
            }
        }
    }
}

# Yaml template validation: from-to
function Test-PasmFromTo {
    param (
        [object]$InputObject,
        [string]$From,
        [string]$To
    )
    foreach ($obj in $inputObject) {
        if ($obj.Contains($from) -and $obj.Contains($to)) {
            if ($obj.$from -gt $obj.$to) {
                throw [FormatException]::new($('The value of FromPort({0}) exceeds ToPort({1}). Please set valid range.' -f $obj.$from, $obj.$to))
            }
        }
    }
}

<#
# Yaml template validation: boolean type
function Test-PasmBoolean {
    param (
        [object]$InputObject,
        [string[]]$Key
    )
    foreach ($k in $key) {
        foreach ($obj in $inputObject) {
            if ($obj.Contains($k)) {
                foreach ($o in $obj.$k) {
                    if ($o -notin 'true', 'false') {
                        throw [FormatException]::new($('''{0}'' is boolean type. It must be set to either ''true'' or ''false''.' -f $k))
                    }
                }
            }
        }
    }
}
#>

# Yaml template validation: 'ProfileName'
function Test-PasmProfileName {
    param (
        [object]$InputObject
    )
    foreach ($obj in $inputObject) {
        if ($obj.Contains('ProfileName')) {
            foreach ($o in $obj.ProfileName) {
                if ($null -eq $(Get-AWSCredential -ProfileName $o)) {
                    throw [FormatException]::new($('Invalid credential ''{0}'' detected. Please set valid profile name.' -f $o))
                }
            }
        }
    }
}

# Yaml template validation: 'ServiceKey'
function Test-PasmServiceKey {
    param (
        [object]$InputObject
    )
    foreach ($obj in $inputObject) {
        if ($obj.Contains('ServiceKey')) {
            foreach ($o in $obj.ServiceKey) {
                if ($o -notin (Get-AWSPublicIpAddressRange -OutputServiceKeys)) {
                    throw [FormatException]::new($('Invalid service key ''{0}'' detected. Please set valid service key.' -f $o))
                }
            }
        }
    }
}

# Yaml template validation: 'Region'
function Test-PasmRegion {
    param (
        [object]$InputObject
    )
    foreach ($obj in $inputObject) {
        if ($obj.Contains('Region')) {
            foreach ($o in $obj.Region) {
                if ($o -notin (Get-AWSRegion -IncludeChina -IncludeGovCloud).Region) {
                    throw [FormatException]::new($('Invalid region ''{0}'' detected. Please set valid region.' -f $o))
                }
            }
        }
    }
}


# Yaml template validation: 'VpcId'
function Test-PasmVpcId {
    param (
        [string]$VpcId
    )
    try {
        Get-EC2Vpc -VpcId $vpcId
    }
    catch {
        throw [ItemNotFoundException]::new($('The VPC with Id ''{0}'' not found.' -f $vpcId))
    }
}

# Yaml template validation: 'SubnetId'
function Test-PasmSubnetId {
    param (
        [string[]]$SubnetId
    )
    foreach ($id in $subnetId) {
        try {
            Get-EC2Subnet -SubnetId $id
        }
        catch {
            throw [ItemNotFoundException]::new($('The Subnet with Id ''{0}'' not found.' -f $id))
        }
    }
}

# Parameter validation: 'MaxEntry'
function Test-PasmMaxEntry {
    param (
        [int]$Entry,
        [int]$MaxEntry,
        [Pasm.Parameter.IpFormat]$IpFormat,
        [Pasm.Parameter.Resource]$ResourceType,
        [Pasm.Parameter.EphemeralPort]$EphemeralPort = 'Default'
    )
    if ($ResourceType -eq [Pasm.Parameter.Resource]::NetworkAcl) {
        $entry = $entry + 1
        if ($ephemeralPort -eq 'Default') {
            $entry = $entry + 2
        }
    }
    if ($entry -ge $maxEntry) {
        throw [InvalidOperationException]::new(
            $(
                'The maximum number of {0} entries({1}) for the ''{2}'' you are trying to configure exceeds the quota limit({3}). Please review your settings. This entry number contains default entries.' -f
                $ipFormat, $entry, $resourceType, $maxEntry
            )
        )
    }
}

# Get Amazon.Util.AWSPublicIpAddressRange
function Get-PasmAWSIpRange {
    param (
        [object]$InputObject,
        [Pasm.Parameter.Resource]$Resource,
        [string]$AddressFamily
    )
    $obj =
    if ($resource -eq [Pasm.Parameter.Resource]::SecurityGroup -or $resource -eq [Pasm.Parameter.Resource]::NetworkAcl) {
        if ($inputObject.Contains('Region') -and $inputObject.Contains('IpFormat')) {
            (Get-AWSPublicIpAddressRange -ServiceKey $inputObject.ServiceKey -Region $inputObject.Region).Where( { $_.IpAddressFormat -in $inputObject.IpFormat } )
        }
        elseif (!$inputObject.Contains('Region') -and $inputObject.Contains('IpFormat')) {
            (Get-AWSPublicIpAddressRange -ServiceKey $inputObject.ServiceKey).Where( { $_.IpAddressFormat -in $inputObject.IpFormat } )
        }
        elseif ($inputObject.Contains('Region') -and !$inputObject.Contains('IpFormat')) {
            (Get-AWSPublicIpAddressRange -ServiceKey $inputObject.ServiceKey -Region $inputObject.Region)
        }
        elseif (!$inputObject.Contains('Region') -and !$inputObject.Contains('IpFormat')) {
            (Get-AWSPublicIpAddressRange -ServiceKey $inputObject.ServiceKey)
        }
        else {
            return
        }
    }
    elseif ($resource -eq [Pasm.Parameter.Resource]::PrefixList) {
        if ($inputObject.Contains('Region')) {
            (Get-AWSPublicIpAddressRange -ServiceKey $inputObject.ServiceKey -Region $inputObject.Region).Where( { $_.IpAddressFormat -eq $addressFamily } )
        }
        elseif (!$inputObject.Contains('Region')) {
            (Get-AWSPublicIpAddressRange -ServiceKey $inputObject.ServiceKey).Where( { $_.IpAddressFormat -eq $addressFamily } )
        }
        else {
            return
        }
    }
    return $obj
}

# Create resource entry object: 'SecurityGroup'
function New-PasmSecurityGroupEntry {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param (
        [object[]]$Rule
    )
    if ($PSCmdlet.ShouldProcess('SecurityGroup.Rules')) {
        $ipPermissions = [list[IpPermission]]::new()
        foreach ($r in $rule) {
            $ipPermission = [IpPermission]::new()
            $ipPermission.IpProtocol = $r.Protocol
            $ipPermission.FromPort = $r.FromPort
            $ipPermission.ToPort = $r.ToPort

            if ($r.Protocol -in 'icmp', 'icmpv6') {
                $ipPermission.FromPort = '-1'
                $ipPermission.ToPort = '-1'
            }

            foreach ($range in $r.Ranges) {
                if ($range.IpFormat -eq 'IPv4') {
                    $ipv4Range = [IpRange]::new()
                    $ipv4Range.CidrIp = $range.IpPrefix
                    $ipv4Range.Description = $range.Description
                    $ipPermission.Ipv4Ranges.Add($ipv4Range)
                }
                if ($range.IpFormat -eq 'IPv6') {
                    $ipv6Range = [Ipv6Range]::new()
                    $ipv6Range.CidrIpv6 = $range.IpPrefix
                    $ipv6Range.Description = $range.Description
                    $ipPermission.Ipv6Ranges.Add($ipv6Range)
                }
            }
            $ipPermissions.Add($ipPermission)
        }
        return $ipPermissions
    }
}

# Create resource entry object: 'NetworkAcl'
function New-PasmNetworkAclEntry {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param (
        [object]$InputObject,
        [NetworkAcl]$NetworkAcl
    )
    if ($PSCmdlet.ShouldProcess('NetworkAcl.Rules')) {
        if ($inputObject.Contains('Rules')) {
            foreach ($r in $inputObject.Rules) {
                foreach ($range in $r.Ranges) {
                    $param = @{
                        NetworkAclId = $networkAcl.NetworkAclId
                        Protocol = [Pasm.Parameter.Protocol]::$($r.Protocol).value__
                        PortRange_From = $r.FromPort
                        PortRange_To = $r.ToPort
                        RuleAction = 'allow'
                        RuleNumber = $range.RuleNumber
                    }
                    if ($range.IpFormat -eq 'Ipv4') {
                        $param.Add('CidrBlock', $range.IpPrefix)
                    }
                    if ($range.IpFormat -eq 'Ipv6') {
                        $param.Add('Ipv6CidrBlock', $range.IpPrefix)
                    }
                    if ($r.Protocol -in 'icmp', 'icmpv6') {
                        $param.Add('IcmpTypeCode_Code', '-1')
                        $param.Add('IcmpTypeCode_Type', '-1')
                    }
                    if ($inputObject.Contains('FlowDirection')) {
                        if ($inputObject.FlowDirection -eq 'Ingress') {
                            $param.Add('Egress', $false)
                        }
                        if ($inputObject.FlowDirection -eq 'Egress') {
                            $param.Add('Egress', $true)
                        }
                    }
                    New-EC2NetworkAclEntry @param
                }
            }
        }
        else {
            return
        }
        if (!($inputObject.Contains('EphemeralPort')) -or (($inputObject.Contains('EphemeralPort')) -and ($inputObject.EphemeralPort -eq 'Default'))) {
            $paramIpv4 = @{
                NetworkAclId = $networkAcl.NetworkAclId
                Protocol = 6
                PortRange_From = 1024
                PortRange_To = 65535
                RuleAction = 'allow'
                RuleNumber = 32765
                CidrBlock = '0.0.0.0/0'
                Egress = $null
            }
            $paramIpv6 = @{
                NetworkAclId = $networkAcl.NetworkAclId
                Protocol = 6
                PortRange_From = 1024
                PortRange_To = 65535
                RuleAction = 'allow'
                RuleNumber = 32766
                Ipv6CidrBlock = '::/0'
                Egress = $null
            }
            $paramIpv4.Egress = $false
            New-EC2NetworkAclEntry @paramIpv4
            $paramIpv6.Egress = $false
            New-EC2NetworkAclEntry @paramIpv6
            $paramIpv4.Protocol = -1
            $paramIpv4.PortRange_From = $null
            $paramIpv4.PortRange_To = $null
            $paramIpv4.Egress = $true
            New-EC2NetworkAclEntry @paramIpv4
            $paramIpv6.Protocol = -1
            $paramIpv6.PortRange_From = $null
            $paramIpv6.PortRange_To = $null
            $paramIpv6.Egress = $true
            New-EC2NetworkAclEntry @paramIpv6
        }
        if ($inputObject.Contains('AssociationSubnetId')) {
            $filter = @{
                Name = 'association.subnet-id'
                Values = @($inputObject.AssociationSubnetId)
            }
            $associationIds = (Get-EC2NetworkAcl -Filter $filter).Associations.Where( { $_.SubnetId -in $filter.Values } ).NetworkAclAssociationId
            foreach ($associationId in $associationIds) {
                Set-EC2NetworkAclAssociation -NetworkAclId $networkAcl.NetworkAclId -AssociationId $associationId | Out-Null
            }
        }
    }
}

# Create resource entry object: 'PrefixList'
function New-PasmPrefixListEntry {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param (
        [object[]]$Rule
    )
    if ($PSCmdlet.ShouldProcess('PrefixList.Rules')) {
        $entries = [list[AddPrefixListEntry]]::new()
        foreach ($r in $rule) {
            foreach ($range in $r.Ranges) {
                $entry = [AddPrefixListEntry]::new()
                $entry.Cidr = $range.IpPrefix
                $entry.Description = $range.Description
                $entries.Add($entry)
            }
        }
        return $entries
    }
}
