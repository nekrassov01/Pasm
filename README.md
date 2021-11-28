# Pasm

[![build](https://github.com/nekrassov01/Pasm/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/nekrassov01/Pasm/actions/workflows/build.yml)  [![release](https://github.com/nekrassov01/Pasm/actions/workflows/release.yml/badge.svg)](https://github.com/nekrassov01/Pasm/actions/workflows/release.yml)

Pasm is a PowerShell module for simple management of public IP address ranges provided by AWS. By simply following simple rules and creating YAML templates, you can keep up with IP range changes, deploy and synchronize resources. The currently supported resources are SecurityGroup, NetworkACL, and PrefixList.

- [Pasm](#pasm)
  - [Compatible Editions](#compatible-editions)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
  - [Functions](#functions)
  - [Configuration Files](#configuration-files)
  - [Usage](#usage)
    - [Initialization](#initialization)
    - [Editing and Validation](#editing-and-validation)
    - [Generating Blueprint](#generating-blueprint)
    - [Deployment](#deployment)
    - [Clean up](#clean-up)
    - [Export to CSV](#export-to-csv)
  - [Same Thing, Shorter](#same-thing-shorter)
  - [Aliases](#aliases)
  - [Sample Template (outline.yml)](#sample-template-outlineyml)

## Compatible Editions

|Core|Desktop|
|--|--|
|:white_check_mark:|:white_check_mark:|

## Prerequisites

Install the modules required to use Pasm.

```ps1
Install-Module -Name PowerShell-Yaml, AWS.Tools.Installer -Scope CurrentUser
Install-AWSToolsModule -Name AWS.Tools.Common, AWS.Tools.EC2 -Scope CurrentUser
```

Set the AWS credential.

```ps1
Set-AWSCredential -AccessKey <AWS_ACCESS_KEY_ID> -SecretKey <AWS_SECRET_ACCESS_KEY> -StoreAs default
```

## Installation

Install Pasm with the following command.

```ps1
Install-Module -Name Pasm -Scope CurrentUser
```

## Functions

Pasm includes 6 functions.

|Function|Description|
|--|--|
|Invoke-PasmInitialize|Generate a working directory and a sample template.|
|Invoke-PasmValidation|Parse the Yaml template to validate if it can be loaded.|
|Invoke-PasmBlueprint|Based on the Yaml template, get the range of ip from [ip-ranges.json](https://ip-ranges.amazonaws.com/ip-ranges.json) and create a blueprint.|
|Invoke-PasmDeployment|Read the blueprint and deploy resources.|
|Invoke-PasmAutomation|Run the following in order: `Invoke-PasmValidation`, `Invoke-PasmBlueprint`, and `Invoke-PasmDeployment`|
|Invoke-PasmCleanUp|Clean up the deployed resources.|
|Invoke-PasmExport|Based on the Yaml template, get the range of ip from [ip-ranges.json](https://ip-ranges.amazonaws.com/ip-ranges.json) and create a simple csv for external use.|

## Configuration Files

The following are the default names. The function parameters `FilePath`, and `OutputFileName` allow you to override names.

|Name|Description|
|--|--|
|outline.yml|The user-controlled configuration file. You can use `Invoke-PasmInitialize` to generate and edit a template, or create one manually from scratch.|
|blueprint.yml|The configuration file that `Invoke-PasmBlueprint` generates by interpreting the 'outline.yml'. The Rules section will be subdivided by IP range.|

## Usage

There are few steps to follow.

### Initialization

A working directory will be created in the current directory and 'outline.yml' will be deployed as a sample template.

```ps1
Invoke-PasmInitialize -Name 'Pasm'
```

```text
BaseDirectory TemplateFile
------------- ------------
C:\Pasm       outline.yml
```

If the target vpc and subnets already exists, overwrite `VpcId` and `AssociationSubnetId`.

```ps1
$param = @{
    VpcId    = 'vpc-1qaz2wsx3edc4rfv5'
    SubnetId = 'subnet-zxcvasdfqwer12345', 'subnet-poiulkjhmnbv09876'
}
Invoke-PasmInitialize @param
```

### Editing and Validation

Go to your working directory and edit 'outline.yml'.

```ps1
Push-Location -LiteralPath 'Pasm'
code outline.yml
```

`Invoke-PasmValidation` is implicitly called by `Invoke-PasmBlueprint` in the next step, but can also be called by itself.

```ps1
Invoke-PasmValidation -FilePath outline.yml
```

```text
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

### Generating Blueprint

Generate 'blueprint.yml' based on the settings in 'outline.yml'.

```ps1
Invoke-PasmBlueprint -FilePath outline.yml -OutputFileName blueprint.yml
```

```text
Mode                 LastWriteTime         Length Name
----                 -------------         ------ ----
-a---          2021/10/05    00:00          99999 blueprint.yml
```

### Deployment

Deploy resources based on the settings in 'blueprint.yml'.

```ps1
Invoke-PasmDeployment -FilePath blueprint.yml
```

```text
 ResourceType ResourceName ResourceId            Action
 ------------ ------------ ----------            ------
SecurityGroup test-sg-01   sg-qaz741wsx852edc96  Create
   NetworkAcl test-acl-01  acl-zaq123xsw456cde78 Create
   PrefixList test-pl-01   pl-poilkjmnb159753az  Create
```

### Clean up

Clean up the deployed resources. Force detach of associated resources. Skip requester-managed ENIs, as they cannot be detached.

```ps1
Invoke-PasmCleanUp -FilePath blueprint.yml
```

```text
ResourceType : SecurityGroup
ResourceName : test-sg-01
ResourceId   : sg-0192837465qpwoeir
Detached     : eni-q1e2a3d4z5cxvsfwr
Skipped      : eni-w1r2s3f4x5vetdgcb
Action       : Skip

ResourceType : NetworkAcl
ResourceName : test-acl-01
ResourceId   : acl-e1t2d3g4c5bryfhvn
Detached     : {subnet-q1z2x3w4e5cvrtbny, subnet-w1x2c3e4r5vbtynmu}
Skipped      :
Action       : CleanUp

ResourceType : PrefixList
ResourceName : test-pl-01
ResourceId   : pl-a1d2s3f4d5gfhgjhk
Detached     : {rtb-a1b2c3d4e5fghijkl, rtb-x1y2z3x4y5zxyzxyz, sg-1a2s3d4f5g6h7j890}
Skipped      :
Action       : CleanUp
```

### Export to CSV

Output to simple CSV for external use.

```ps1
Invoke-PasmExport -FilePath outline.yml -OutputFileName output.csv
```

## Same Thing, Shorter

`Invoke-PasmAutomation` runs the following in order: `Invoke-PasmValidation`, `Invoke-PasmBlueprint`, and `Invoke-PasmDeployment`.

```ps1
Invoke-PasmAutomation -FilePath outline.yml -OutputFileName blueprint.yml
```

```text
 ResourceType ResourceName ResourceId            Action
 ------------ ------------ ----------            ------
SecurityGroup test-sg-01   sg-qaz741wsx852edc96  Sync
   NetworkAcl test-acl-01  acl-zaq123xsw456cde78 Sync
   PrefixList test-pl-01   pl-poilkjmnb159753az  Sync
```

## Aliases

You can execute the commands with aliases as follows.

```ps1
# Invoke-PasmInitialize -Path 'C:\' -Name 'Pasm' -VpcId 'vpc-id' -SubnetId 'subnet-id-1', 'subnet-id-2'
psmi -p 'C:\' -n 'Pasm' -vpc 'your-vpc-id' -sbn 'your-subnet-id-1', 'your-subnet-id-2'
```

```ps1
# Invoke-PasmValidation -FilePath 'C:\Pasm\outline.yml'
psmv -file 'C:\Pasm\outline.yml'
```

```ps1
# Invoke-PasmBlueprint -FilePath 'C:\Pasm\outline.yml' -OutputFileName 'blueprint.yml'
psmb -file 'C:\Pasm\outline.yml' -out 'blueprint.yml'
```

```ps1
# Invoke-PasmDeployment -FilePath 'C:\Pasm\blueprint.yml'
psmd -file 'C:\Pasm\blueprint.yml'
```

```ps1
# Invoke-PasmAutomation -FilePath 'C:\Pasm\blueprint.yml' -OutputFileName 'blueprint.yml'
psma -file 'C:\Pasm\outline.yml' -out 'blueprint.yml'
```

```ps1
# Invoke-PasmCleanUp -FilePath 'C:\Pasm\blueprint.yml'
psmc -file 'C:\Pasm\blueprint.yml'
```

```ps1
# Invoke-PasmExport -FilePath 'C:\Pasm\outline.yml' -OutputFileName 'output.csv'
psme -file 'C:\Pasm\outline.yml' -out 'output.csv'
```

## Sample Template (outline.yml)

'outline.yml' will be deployed with comments. Please overwrite it according to your environment.

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
      - IPv6
      Protocol: tcp
      FromPort: 443
      ToPort: 443
  NetworkAcl:                       # not-required - One of the following must be present: 'SecurityGroup','NetworkAcl', 'PrefixList'
  - ResourceName: test-acl-01       # required
    VpcId: vpc-00000000000000000    # required
    MaxEntry: 20                    # not-required - Range: 1-20
    FlowDirection: Ingress          # not-required - Enum: [Pasm.Parameter.FlowDirection]
    EphemeralPort: Default          # not-required - Enum: [Pasm.Parameter.EphemeralPort]
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
    - Id: 2
      ServiceKey: S3
      Region:
      - ap-northeast-1
      IpFormat:
      - IPv6
      Protocol: tcp
      FromPort: 443
      ToPort: 443
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
