BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core
}

Describe 'Test-DefaultComputerName (rappel du renommage)' {
    It '<Name> : nom attribué par Windows' -ForEach @(
        @{ Name = 'DESKTOP-7Q4K2LM' }
        @{ Name = 'LAPTOP-AB12CD34' }
        @{ Name = 'desktop-7q4k2lm' }
    ) {
        Test-DefaultComputerName -Name $Name | Should -BeTrue
    }

    It '<Name> : poste déjà renommé' -ForEach @(
        @{ Name = 'PC-0042' }
        @{ Name = 'ACCUEIL-01' }
        @{ Name = 'DESKTOP-01' }
        @{ Name = 'DESKTOPS-7Q4K2LM' }
        @{ Name = '' }
    ) {
        Test-DefaultComputerName -Name $Name | Should -BeFalse
    }
}
