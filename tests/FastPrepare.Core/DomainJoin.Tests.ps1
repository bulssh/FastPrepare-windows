BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core

    function New-TestSecret([string]$Text) {
        $secret = New-Object System.Security.SecureString
        foreach ($char in $Text.ToCharArray()) { $secret.AppendChar($char) }
        return $secret
    }
}

Describe 'Get-DomainJoinError' {
    It 'demande valable : compte <Account>' -ForEach @(
        @{ Account = 'adm-jonction' }, @{ Account = 'ENTREPRISE\adm-jonction' }, @{ Account = 'adm-jonction@entreprise.local' }
    ) {
        Get-DomainJoinError -Domain 'entreprise.local' -Account $Account -Password (New-TestSecret 'Fictif-2026!') | Should -BeNullOrEmpty
    }

    It 'refus : domaine « <Domain> », compte « <Account> »' -ForEach @(
        @{ Domain = ''; Account = 'adm'; Expected = 'nom du domaine vide' }
        @{ Domain = 'ENTREPRISE'; Account = 'adm'; Expected = 'nom DNS complet' }
        @{ Domain = 'entreprise .local'; Account = 'adm'; Expected = 'nom DNS complet' }
        @{ Domain = '-entreprise.local'; Account = 'adm'; Expected = 'nom DNS complet' }
        @{ Domain = 'entreprise.local'; Account = ''; Expected = 'compte autorisé' }
        @{ Domain = 'entreprise.local'; Account = 'a b'; Expected = 'caractère interdit' }
        @{ Domain = 'entreprise.local'; Account = 'A\B\c'; Expected = 'sous la forme' }
        @{ Domain = 'entreprise.local'; Account = 'A\b@c'; Expected = 'sous la forme' }
        @{ Domain = 'entreprise.local'; Account = 'adm@'; Expected = 'sous la forme' }
    ) {
        Get-DomainJoinError -Domain $Domain -Account $Account -Password (New-TestSecret 'x') | Should -Match $Expected
    }

    It 'mot de passe absent, vide ou libéré : refus ; non vérifié s''il n''est pas fourni' {
        Get-DomainJoinError -Domain 'entreprise.local' -Account 'adm' -Password $null | Should -Match 'mot de passe du compte vide'
        Get-DomainJoinError -Domain 'entreprise.local' -Account 'adm' -Password (New-Object System.Security.SecureString) | Should -Match 'mot de passe du compte vide'
        $released = New-TestSecret 'x'
        $released.Dispose()
        Get-DomainJoinError -Domain 'entreprise.local' -Account 'adm' -Password $released | Should -Match 'déjà libéré'
        Get-DomainJoinError -Domain 'entreprise.local' -Account 'adm' | Should -BeNullOrEmpty
    }
}

Describe 'Split-DomainAccount' {
    It 'utilisateur seul : rattaché au domaine à joindre' {
        $a = Split-DomainAccount -Domain 'entreprise.local' -Account 'adm'
        $a.User | Should -Be 'adm'
        $a.Domain | Should -Be 'entreprise.local'
        $a.Qualified | Should -Be 'entreprise.local\adm'
    }
    It 'DOMAINE\utilisateur : conservé' {
        $a = Split-DomainAccount -Domain 'entreprise.local' -Account 'ENTREPRISE\adm'
        $a.User | Should -Be 'adm'
        $a.Domain | Should -Be 'ENTREPRISE'
        $a.Qualified | Should -Be 'ENTREPRISE\adm'
    }
    It 'utilisateur@domaine : nom complet, sans domaine séparé' {
        $a = Split-DomainAccount -Domain 'entreprise.local' -Account 'adm@entreprise.local'
        $a.User | Should -Be 'adm@entreprise.local'
        $a.Domain | Should -BeNullOrEmpty
        $a.Qualified | Should -Be 'adm@entreprise.local'
    }
}

Describe 'Test-SameDomain' {
    It 'casse et point final ignorés' {
        Test-SameDomain -First 'Entreprise.LOCAL.' -Second 'entreprise.local' | Should -BeTrue
        Test-SameDomain -First 'entreprise.local' -Second 'autre.local' | Should -BeFalse
        Test-SameDomain -First '' -Second '' | Should -BeFalse
    }
}
