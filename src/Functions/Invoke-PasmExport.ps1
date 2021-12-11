#Requires -Version 5.1
using namespace System.IO
using namespace System.Collections.Generic

function Invoke-PasmExport {
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
        [string[]]$OutputFileName = $('{0}.csv' -f [Pasm.Template.Name]::output)
    )

    begin {
        try {
            Set-StrictMode -Version Latest

            # Load helper functions
            . $($PSScriptRoot, 'Helpers', 'Helpers.ps1' -join [path]::DirectorySeparatorChar)

            # Implicitly run the validator process
            Invoke-PasmValidation -FilePath $filePath -SkipIdValidation | Out-Null

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

                # Create outer container
                $container = [list[object]]::new()

                foreach ($resource in $([enum]::GetNames([Pasm.Parameter.Resource]))) {
                    if ($obj.Resource.Contains($resource)) {
                        foreach ($res in $obj.Resource.$resource) {
                            foreach ($rule in $res.Rules) {
                                foreach ($r in $(Get-PasmAWSIpRange $rule -Resource $resource)) {
                                    $o = [ordered]@{}
                                    $o.ServiceKey = $rule.ServiceKey
                                    $o.IpPrefix = $r.IpPrefix
                                    $o.IpFormat = $r.IpAddressFormat
                                    $o.Region = $r.Region
                                    $container.Add($o)
                                }
                            }
                        }
                    }
                }
                # Converts the object to csv format and writes it to a file
                # If the file already exists, it will be overwritten
                $container | Export-Csv -LiteralPath $outputFilePath -NoTypeInformation -Force
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
        Get the ip ranges from 'ip-ranges.json' as described in the Yaml template, and create a simple csv.

        .DESCRIPTION
        Get the ip ranges from 'ip-ranges.json' as described in the Yaml template, and create a simple csv.
        See the following source for details: https://github.com/nekrassov01/Pasm/blob/main/src/Functions/Invoke-PasmExport.ps1

        .EXAMPLE
        # Default input file path: ${PWD}/outline.yml, default output file name: 'output.csv'
        Invoke-PasmExport

        .EXAMPLE
        # Loading multiple files
        Invoke-PasmExport -FilePath 'C:/Pasm/outline-sg.yml', 'C:/Pasm/outline-nacl.yml', 'C:/Pasm/outline-pl.yml' -OutputFileName 'blueprint-sg.csv', 'blueprint-nacl.csv', 'blueprint-pl.csv'

        .EXAMPLE
        # Loading multiple files from pipeline
        'C:/Pasm/outline-sg.yml', 'C:/Pasm/outline-nacl.yml', 'C:/Pasm/outline-pl.yml' | Invoke-PasmBlueprint -OutputFileName 'blueprint-sg.csv', 'blueprint-nacl.csv', 'blueprint-pl.csv'

        .LINK
        https://github.com/nekrassov01/Pasm
    #>
}
