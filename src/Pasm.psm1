#Requires -Version 5.1

Set-StrictMode -Version Latest
$moduleName = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)

Add-Type -TypeDefinition @"
namespace ${moduleName}.Parameter
{
    // Parameter values
    public enum Protocol            { tcp = 6, udp = 17, icmp = 1, icmpv6 = 58, all = -1 }
    public enum IpFormat            { IPv4, IPv6 }
    public enum FlowDirection       { Ingress, Egress }
    public enum EphemeralPort       { None, Default }

    // Parameter keys
    public enum Parent              { Common, Resource }
    public enum Common              { Region, ProfileName }
    public enum Resource            { SecurityGroup, NetworkAcl, PrefixList }
    public enum SecurityGroup       { ResourceName, VpcId, MaxEntry, FlowDirection, Description, Rules }
    public enum NetworkAcl          { ResourceName, VpcId, MaxEntry, FlowDirection, AssociationSubnetId, RuleNumber, Rules, EphemeralPort }
    public enum PrefixList          { ResourceName, VpcId, MaxEntry, AddressFamily, Rules }
    public enum SecurityGroupRules  { Id, ServiceKey, Region, Protocol, IpFormat, FromPort, ToPort }
    public enum NetworkAclRules     { Id, ServiceKey, Region, Protocol, IpFormat, FromPort, ToPort }
    public enum PrefixListRules     { Id, ServiceKey, Region }
    public enum RuleNumber          { StartNumber, Interval }
}
namespace ${moduleName}.RequiredParameter
{
    // Required keys
    public enum Parent              { Common, Resource }
    public enum Common              { Region, ProfileName }
    public enum SecurityGroup       { ResourceName, VpcId, Rules, Description }
    public enum NetworkAcl          { ResourceName, VpcId, Rules }
    public enum PrefixList          { ResourceName, VpcId, Rules }
    public enum SecurityGroupRules  { Id, ServiceKey, Protocol, FromPort, ToPort }
    public enum NetworkAclRules     { Id, ServiceKey, Protocol, FromPort, ToPort }
    public enum PrefixListRules     { Id, ServiceKey }
}
namespace ${moduleName}.Template
{
    // Yaml template default file name
    public enum Name                { outline, blueprint }
}
"@

$functionsDir = Join-Path -Path $PSScriptRoot -ChildPath 'Functions'
Get-ChildItem -LiteralPath $functionsDir -Filter '*.ps1' -Recurse | ForEach-Object { . $_.PSPath }

$map = @{
    'psmi' = 'Invoke-PasmInitialize'
    'psmv' = 'Invoke-PasmValidation'
    'psmb' = 'Invoke-PasmBlueprint'
    'psmd' = 'Invoke-PasmDeployment'
    'psma' = 'Invoke-PasmAutomation'
    'psmc' = 'Invoke-PasmCleanUp'
}
foreach ($m in $map.GetEnumerator()) {
    Set-Alias -Name $m.Key -Value $m.Value
}

Export-ModuleMember -Function * -Cmdlet * -Alias *
