[![build](https://github.com/nekrassov01/Pasm/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/nekrassov01/Pasm/actions/workflows/build.yml)

# Pasm
Pasm is a PowerShell module for simple management of public IP address ranges provided by AWS. By simply following simple rules and creating YAML templates, you can keep up with IP range changes, deploy and synchronize resources. The currently supported resources are SecurityGroup, NetworkACL, and PrefixList.  

|Core|Desktop|
|--|--|
|:white_check_mark:|:white_check_mark:|

## Prerequisites for using Pasm 

Install the modules required to use Pasm.
```ps1
PS C:\> Install-Module -Name PowerShell-Yaml, AWS.Tools.Installer -Scope CurrentUser
PS C:\> Install-AWSToolsModule -Name AWS.Tools.Common, AWS.Tools.EC2 -Scope CurrentUser
```  

Set the AWS credential.
```ps1
PS C:\> Set-AWSCredential -AccessKey <AWS_ACCESS_KEY_ID> -SecretKey <AWS_SECRET_ACCESS_KEY> -StoreAs default
```

## Install

Install Pasm.
```ps1
PS C:\> Install-Module -Name Pasm -Scope CurrentUser
```

## Functions


|Function|Description|
|--|--|
|Invoke-PasmInitialize|Generate a working directory and a sample template.|
|Invoke-PasmValidation|Parse the Yaml template to validate if it can be loaded.|
|Invoke-PasmBlueprint|Get the ip ranges from [ip-ranges.json](https://ip-ranges.amazonaws.com/ip-ranges.json) as described in the Yaml template, and create a blueprint.|
|Invoke-PasmDeployment|Read the blueprint and deploy resources.|
|Invoke-PasmAutomation|Run the following in order: ```Invoke-PasmValidation```, ```Invoke-PasmBlueprint```, ```Invoke-PasmDeproyment```.|

## Configuration Files

The following are the default names. The function parameters ```FilePath```, and ```OutputFileName``` allow you to override names.

|Name|Description|
|--|--|
|outline.yml|The user-controlled configuration file. You can use ```Invoke-PasmInitialize``` to generate and edit a template, or create one manually from scratch.|
|blueprint.yml|The configuration file that ```Invoke-PasmBlueprint``` generates by interpreting the outline.yml. The Rules section will be subdivided by IP range.|

## Initialization

A working directory will be created in the current directory and outline.yml will be deployed as a sample template.
```ps1 
PS C:\> Invoke-PasmInitialize -Name 'Pasm'
```
```
BaseDirectory TemplateFile
------------- ------------
C:\Pasm       C:\Pasm\outline.yml
```

## Usage

Go to your working directory and edit 'outline.yml'.
```ps1
PS C:\> Push-Location -LiteralPath 'Pasm'
PS C:\Pasm> code outline.yml
```

Only validator processing can be called.
```ps1
PS C:\Pasm> Invoke-PasmValidation -FilePath C:\Pasm\outline.yml
```
```
Validation started: outline.yml
Validation passed: Parent
Validation passed: Common
Validation passed: Resource
Validation passed: SecurityGroup 'test-sg-01' Parent
Validation passed: SecurityGroup 'test-sg-01' Rules
Validation passed: SecurityGroup 'test-sg-01' VpcId
Validation passed: NetworkAcl 'test-acl-01' Parent
Validation passed: NetworkAcl 'test-acl-01' Rules
Validation passed: NetworkAcl 'test-acl-01' VpcId
Validation passed: NetworkAcl 'test-acl-01' SubnetId
Validation passed: PrefixList 'test-pl-01' Parent
Validation passed: PrefixList 'test-pl-01' Rules
Validation passed: PrefixList 'test-pl-01' VpcId
Validation finished: outline.yml
```

Generate 'blueprint.yml' based on the settings in 'outline.yml'.
```ps1
PS C:\Pasm> Invoke-PasmBlueprint -FilePath C:\Pasm\outline.yml -OutputFileName blueprint.yml
```
```
Mode                 LastWriteTime         Length Name
----                 -------------         ------ ----
-a---          2021/10/05    00:00          99999 blueprint.yml
```

Deploy resources based on the settings in 'blueprint.yml'.
```ps1
PS C:\Pasm> Invoke-PasmDeployment -FilePath C:\Pasm\blueprint.yml
```
```
 ResourceType ResourceName ResourceId            Action
 ------------ ------------ ----------            ------
SecurityGroup test-sg-01   sg-qaz741wsx852edc96  Create
   NetworkAcl test-acl-01  acl-zaq123xsw456cde78 Create
   PrefixList test-pl-01   pl-poilkjmnb159753az  Create
```

## Same Thing, Shorter

Invoke-PasmAutomation runs the following in order: ```Invoke-PasmValidation```, ```Invoke-PasmBlueprint```, and ```Invoke-PasmDeproyment```.
```ps1
PS C:\Pasm> Invoke-PasmAutomation -FilePath C:\Pasm\outline.yml -OutputFileName blueprint.yml
```
```
 ResourceType ResourceName ResourceId            Action
 ------------ ------------ ----------            ------
SecurityGroup test-sg-01   sg-qaz741wsx852edc96  Sync
   NetworkAcl test-acl-01  acl-zaq123xsw456cde78 Sync
   PrefixList test-pl-01   pl-poilkjmnb159753az  Sync
```

## Sample Template (outline.yml)

```yaml
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
```

## To do

- Implementing the cleanup process.
- Performance tuning.
