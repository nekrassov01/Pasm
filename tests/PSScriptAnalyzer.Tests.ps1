#Requires -Modules PSScriptAnalyzer

using namespace System.IO

Describe 'Lint' {
    Context 'PSScriptAnalyzer' {
        BeforeAll {
            $script:targetDir = $PSScriptRoot, '..', 'src', 'Functions' -join [path]::DirectorySeparatorChar
        }
        It 'DefaultRules' {
            Invoke-ScriptAnalyzer -Path $targetDir -Severity Error, Warning | Should -BeNullOrEmpty
        }
        It 'CodeFormatting' {
            Invoke-ScriptAnalyzer -Path $targetDir -Settings CodeFormatting -ExcludeRule 'PSAlignAssignmentStatement' -Severity Error, Warning | Should -BeNullOrEmpty
        }
    }
}
