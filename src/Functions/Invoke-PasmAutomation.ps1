#Requires -Version 5.1
using namespace System.IO

function Invoke-PasmAutomation {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
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
        [string[]]$OutputFileName = $('{0}.yml' -f [Pasm.Template.Name]::blueprint)
    )

    begin {
        Set-StrictMode -Version Latest
    }

    process {
        try {
            $i = 0
            foreach ($file in $filePath) {
                # Convert yaml file
                Invoke-PasmBlueprint -FilePath $file -OutputFileName $outputFileName[$i] | Out-Null

                # Deploy resources
                Invoke-PasmDeployment -FilePath $([path]::GetDirectoryName($file), $OutputFileName[$i] -join [path]::DirectorySeparatorChar)
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
        Run the following in order: Invoke-PasmValidation, Invoke-PasmBlueprint, Invoke-PasmDeproyment.

        .DESCRIPTION
        Run the following in order: Invoke-PasmValidation, Invoke-PasmBlueprint, Invoke-PasmDeproyment.
        See the following source for details: https://github.com/nekrassov01/Pasm/blob/main/src/Functions/Invoke-PasmAutomation.ps1

        .EXAMPLE
        # Default input file path: ${PWD}/outline.yml, default output file name: 'blueprint.yml'
        Invoke-PasmAutomation

        .EXAMPLE
        # Loading multiple files
        Invoke-PasmAutomation -FilePath 'C:/Pasm/outline-sg.yml', 'C:/Pasm/outline-nacl.yml', 'C:/Pasm/outline-pl.yml' -OutputFileName 'blueprint-sg.yml', 'blueprint-nacl.yml', 'blueprint-pl.yml'

        .EXAMPLE
        # Loading multiple files from pipeline
        'C:/Pasm/outline-sg.yml', 'C:/Pasm/outline-nacl.yml', 'C:/Pasm/outline-pl.yml' | Invoke-PasmAutomation -OutputFileName 'blueprint-sg.yml', 'blueprint-nacl.yml', 'blueprint-pl.yml'

        .LINK
        https://github.com/nekrassov01/Pasm
    #>
}