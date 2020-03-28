Set-StrictMode -Version Latest

Describe "Module scope separation" {
    Context "When users define variables with the same name as Pester parameters" {
        $test = "This is a test."

        It "does not hide user variables" {
            $test | Should -Be 'This is a test.'
        }
    }

    It "Does not expose Pester implementation details to the SUT" {
        # Changing the ConvertTo-PesterResult function's name would cause this test to pass artificially.
        # TODO : come up with a better way of verifying that only the desired commands from the Pester
        # module are visible to the SUT.

        (Get-Item function:\ConvertTo-PesterResult -ErrorAction SilentlyContinue) | Should -Be $null
    }
}

Describe "Executing test code inside a module" {
    New-Module -Name TestModule {
        function InternalFunction {
            'I am the internal function'
        }
        function PublicFunction {
            InternalFunction
        }
        Export-ModuleMember -Function PublicFunction
    } | Import-Module -Force

    It "Cannot call module internal functions, by default" {
        { InternalFunction } | Should -Throw
    }

    InModuleScope TestModule {
        It "Can call module internal functions using InModuleScope" {
            InternalFunction | Should -Be 'I am the internal function'
        }

        It "Can mock functions inside the module without using Mock -ModuleName" {
            Mock InternalFunction { 'I am the mock function.' }
            InternalFunction | Should -Be 'I am the mock function.'
        }
    }

    It "Can execute bound ScriptBlock inside the module scope" {
        $ScriptBlock = { Write-Output "I am a bound ScriptBlock" }
        InModuleScope TestModule $ScriptBlock | Should -BeExactly "I am a bound ScriptBlock"
    }

    It "Can execute unbound ScriptBlock inside the module scope" {
        $ScriptBlockString = 'Write-Output "I am an unbound ScriptBlock"'
        $ScriptBlock = [ScriptBlock]::Create($ScriptBlockString)
        InModuleScope TestModule $ScriptBlock | Should -BeExactly "I am an unbound ScriptBlock"
    }

    Remove-Module TestModule -Force
}

Describe "Get-ScriptModule behavior" {

    Context "When attempting to mock a command in a non-existent module" {

        It "should throw an exception" {
            {
                Mock -CommandName "Invoke-MyMethod" `
                    -ModuleName  "MyNonExistentModule" `
                    -MockWith { write-host "my mock called!" }
            } | Should Throw "No module named 'MyNonExistentModule' is currently loaded."
        }

    }

    Context "When mocking a command from Binary module" {
        $dll = "$PSScriptRoot/SomeModule.dll"
        # this will run in a job and we need to make sure we get rid of the dll
        # after we unload the process, so we create the type in the process and run
        # the second part of the test in $test, and then clean up
        $job = {
            param($dll, $test)
            Add-Type -OutputAssembly $dll -TypeDefinition '
                using System.Management.Automation;

                namespace SomeModule
                {
                    [Cmdlet(VerbsCommon.Get, "Something")]
                    public class GetSomethingCommand : PSCmdlet
                    {
                        [Parameter(Position = 0)]
                        public string InputObject { get; set; }

                        protected override void EndProcessing()
                        {
                            this.WriteObject(InputObject);
                        }
                    }
                }
            '

            Import-Module "$PSScriptRoot/SomeModule.dll"

            # run the actual test
            & $test
        }

        It "Is binary module" {

            try {
                $test = { (Get-Module SomeModule).ModuleType }
                Start-Job $job -ArgumentList $dll, $test
            }
            finally {
                if (Test-Path $dll) {
                    Remove-Item $dll -ErrorAction SilentlyContinue
                }
            }

            | Should -Be Binary
        }

        It "just passes the value when not mocked" {
            Get-Something "aaa" | Should -Be "aaa"
        }

        It "returns mock value when mocked" {
            Mock Get-Something { "hello" }

            Get-Something "aaa" | Should -Be "hello"
        }

        It "returns mock value when mocked with ModuleName, as long as the mocked function is exported from the module" {
            Mock Get-Something { "hello" } -ModuleName "SomeModule"

            Get-Something "aaa" | Should -Be "hello"
        }
    }

}
