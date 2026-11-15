<#
    Règles de saisie d'une session locale à créer (itération 8, fonctionnalité F1).
    Mots de passe fictifs, construits caractère par caractère comme le fait une PasswordBox.
#>
BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core

    function New-TestSecret([string]$Text) {
        $secret = New-Object System.Security.SecureString
        foreach ($char in $Text.ToCharArray()) { $secret.AppendChar($char) }
        return $secret
    }

    function New-AccountSelection {
        param([string]$Name = 'jdupont', [string]$Password = 'Fictif-2026!')
        $selection = New-Selection
        $secret = if ($Password) { New-TestSecret $Password } else { $null }
        $selection.NewLocalAccounts.Items = @(New-LocalAccountRequest -Name $Name -Password $secret)
        return $selection
    }
}

Describe 'Get-LocalAccountNameError' {
    It 'nom acceptable : <Name>' -ForEach @(
        @{ Name = 'jdupont' }, @{ Name = 'Jean.Dupont' }, @{ Name = 'j-dupont_2' }, @{ Name = 'Élodie' }, @{ Name = 'a' * 20 }
    ) {
        Get-LocalAccountNameError -Name $Name -ExistingName @('Administrateur') -ComputerName @('PC-TEST') | Should -BeNullOrEmpty
    }

    It 'refus « <Expected> » pour <Name>' -ForEach @(
        @{ Name = ''; Expected = 'vide' }
        @{ Name = ('a' * 21); Expected = '21 caractères sur 20' }
        @{ Name = 'jean/dupont'; Expected = 'caractère interdit : /' }
        @{ Name = 'jean@dupont'; Expected = 'caractère interdit : @' }
        @{ Name = 'a"b'; Expected = 'caractère interdit' }
        @{ Name = '...'; Expected = 'uniquement des points' }
        @{ Name = '   '; Expected = 'uniquement des points ou des espaces' }
        @{ Name = 'jean.'; Expected = 'point' }
        @{ Name = ' jean'; Expected = 'espace' }
        @{ Name = "je`tan"; Expected = 'contrôle' }
    ) {
        Get-LocalAccountNameError -Name $Name | Should -Match ([regex]::Escape($Expected))
    }

    It 'nom déjà pris, sans tenir compte de la casse' {
        Get-LocalAccountNameError -Name 'ADMINISTRATEUR' -ExistingName @('Administrateur') | Should -Match 'existe déjà'
    }

    It 'nom identique au nom du poste (actuel ou futur)' {
        Get-LocalAccountNameError -Name 'pc-test' -ComputerName @('PC-TEST', 'PC-NEUF') | Should -Match 'nom du poste'
        Get-LocalAccountNameError -Name 'PC-NEUF' -ComputerName @('PC-TEST', 'PC-NEUF') | Should -Match 'nom du poste'
    }
}

Describe 'Get-LocalAccountPasswordError' {
    It 'mot de passe absent ou vide refusé' {
        Get-LocalAccountPasswordError -Password $null | Should -Match 'vide'
        Get-LocalAccountPasswordError -Password (New-TestSecret '') | Should -Match 'vide'
    }

    It 'plus de 127 caractères refusé, 127 accepté' {
        Get-LocalAccountPasswordError -Password (New-TestSecret ('x' * 128)) | Should -Match '128 caractères sur 127'
        Get-LocalAccountPasswordError -Password (New-TestSecret ('x' * 127)) | Should -BeNullOrEmpty
    }

    It 'confirmation identique acceptée' {
        Get-LocalAccountPasswordError -Password (New-TestSecret 'Fictif-2026!') -Confirmation (New-TestSecret 'Fictif-2026!') | Should -BeNullOrEmpty
    }

    It 'confirmation différente refusée (<Case>)' -ForEach @(
        @{ Case = 'dernier caractère'; Confirmation = 'Fictif-2026?' }
        @{ Case = 'casse'; Confirmation = 'fictif-2026!' }
        @{ Case = 'longueur'; Confirmation = 'Fictif-2026!!' }
        @{ Case = 'vide'; Confirmation = '' }
    ) {
        Get-LocalAccountPasswordError -Password (New-TestSecret 'Fictif-2026!') -Confirmation (New-TestSecret $Confirmation) | Should -Match 'confirmation'
    }

    It 'mot de passe déjà libéré : refus explicite' {
        $password = New-TestSecret 'Fictif-2026!'
        $password.Dispose()
        Get-LocalAccountPasswordError -Password $password | Should -Match 'déjà libéré'
    }

    It 'confirmation absente alors qu''elle est demandée : refus' {
        Get-LocalAccountPasswordError -Password (New-TestSecret 'Fictif-2026!') -Confirmation $null | Should -Match 'confirmation'
    }

    It 'les mots de passe comparés restent utilisables' {
        $password = New-TestSecret 'Fictif-2026!'
        $confirmation = New-TestSecret 'Fictif-2026!'
        [void](Get-LocalAccountPasswordError -Password $password -Confirmation $confirmation)
        $password.Length | Should -Be 12
        $confirmation.Length | Should -Be 12
    }
}

Describe 'Get-LocalAccountGroupSid' {
    It 'utilisateur standard : groupe Utilisateurs seulement (SID bien connu)' {
        Get-LocalAccountGroupSid | Should -Be @('S-1-5-32-545')
    }
    It 'administrateur : Utilisateurs et Administrateurs' {
        Get-LocalAccountGroupSid -Administrator | Should -Be @('S-1-5-32-545', 'S-1-5-32-544')
    }
}

Describe 'Format-LocalAccountSummary' {
    It 'décrit la session sans mot de passe' {
        Format-LocalAccountSummary -Name 'jdupont' -FullName 'Jean Dupont' -Administrator -MustChangePassword |
            Should -Be "'jdupont' (Jean Dupont) · administrateur du poste · mot de passe à changer à la première ouverture"
        Format-LocalAccountSummary -Name 'jdupont' -PasswordNeverExpires |
            Should -Be "'jdupont' · utilisateur standard · mot de passe qui n'expire jamais"
        Format-LocalAccountSummary -Name 'accueil' -PasswordNeverExpires -CannotChangePassword -Disabled |
            Should -Be "'accueil' · utilisateur standard · mot de passe qui n'expire jamais · mot de passe non modifiable par l'utilisateur · compte désactivé"
    }
}

Describe 'Get-LocalAccountOptionError' {
    It 'options compatibles : aucun motif' {
        Get-LocalAccountOptionError -Description 'Poste accueil' -PasswordNeverExpires -CannotChangePassword | Should -BeNullOrEmpty
        Get-LocalAccountOptionError -MustChangePassword | Should -BeNullOrEmpty
    }
    It '« à changer » avec « n''expire jamais » : refus' {
        Get-LocalAccountOptionError -MustChangePassword -PasswordNeverExpires | Should -Match 'incompatibles'
    }
    It '« à changer » avec « ne peut pas être changé » : refus' {
        Get-LocalAccountOptionError -MustChangePassword -CannotChangePassword | Should -Match 'ne peut pas être changé'
    }
    It 'description de plus de 48 caractères : refus' {
        Get-LocalAccountOptionError -Description ('d' * 49) | Should -Match '49 caractères sur 48'
        Get-LocalAccountOptionError -Description ('d' * 48) | Should -BeNullOrEmpty
    }
}

Describe 'Test-Selection — session à créer' {
    BeforeAll {
        $config = Get-TestConfig
        $snapshot = [pscustomobject]@{
            Identity      = [pscustomobject]@{ HostName = 'PC-TEST' }
            LocalAccounts = [pscustomobject]@{
                Removable = @([pscustomobject]@{ Name = 'ancien'; Sid = 'S-1-5-21-1-2-3-1002'; ProfilePath = 'C:\Users\ancien' })
                Excluded  = @('Administrateur')
                Names     = @('Administrateur', 'ancien')
            }
        }
    }

    It 'aucune session à créer : rien n''est vérifié' {
        $selection = New-Selection
        Test-Selection -Selection $selection -Config $config -Snapshot $snapshot | Should -BeNullOrEmpty
    }

    It 'saisie complète et cohérente : aucune incohérence' {
        Test-Selection -Selection (New-AccountSelection) -Config $config -Snapshot $snapshot | Should -BeNullOrEmpty
    }

    It 'nom déjà pris : refus' {
        Test-Selection -Selection (New-AccountSelection -Name 'ancien') -Config $config -Snapshot $snapshot | Should -Match 'existe déjà'
    }

    It 'nom libéré par une session cochée pour suppression : accepté' {
        $selection = New-AccountSelection -Name 'ancien'
        $selection.LocalAccounts.Items = @($snapshot.LocalAccounts.Removable)
        Test-Selection -Selection $selection -Config $config -Snapshot $snapshot | Should -BeNullOrEmpty
    }

    It 'nom identique au nom du poste : refus' {
        $selection = New-AccountSelection -Name 'PC-TEST'
        Test-Selection -Selection $selection -Config $config -Snapshot $snapshot | Should -Match 'nom du poste'
    }

    It 'mot de passe absent : refus' {
        Test-Selection -Selection (New-AccountSelection -Password '') -Config $config -Snapshot $snapshot | Should -Match 'mot de passe vide'
    }

    It 'options d''expiration contradictoires : refus' {
        $selection = New-AccountSelection
        $selection.NewLocalAccounts.Items[0].PasswordNeverExpires = $true
        $selection.NewLocalAccounts.Items[0].MustChangePassword = $true
        Test-Selection -Selection $selection -Config $config -Snapshot $snapshot | Should -Match 'incompatibles'
    }

    It 'plusieurs sessions cohérentes : aucune incohérence' {
        $selection = New-AccountSelection
        $selection.NewLocalAccounts.Items += New-LocalAccountRequest -Name 'accueil' -Password (New-TestSecret 'Fictif-2026!') -Disabled
        Test-Selection -Selection $selection -Config $config -Snapshot $snapshot | Should -BeNullOrEmpty
    }

    It 'même nom demandé deux fois (casse différente) : refus de la seconde' {
        $selection = New-AccountSelection
        $selection.NewLocalAccounts.Items += New-LocalAccountRequest -Name 'JDupont' -Password (New-TestSecret 'Fictif-2026!')
        $problems = @(Test-Selection -Selection $selection -Config $config -Snapshot $snapshot)
        $problems.Count | Should -Be 1
        $problems[0] | Should -Match "'JDupont' : nom refusé .*existe déjà"
    }

    It 'le motif nomme la session en cause' {
        $selection = New-AccountSelection
        $selection.NewLocalAccounts.Items += New-LocalAccountRequest -Name 'accueil' -Password $null
        Test-Selection -Selection $selection -Config $config -Snapshot $snapshot | Should -Match "Session à créer 'accueil' : mot de passe vide"
    }
}

Describe 'Clear-SelectionSecret' {
    It 'libère chaque mot de passe et le retire de la sélection' {
        $selection = New-AccountSelection
        $selection.NewLocalAccounts.Items += New-LocalAccountRequest -Name 'accueil' -Password (New-TestSecret 'Fictif-2026!')
        $passwords = @($selection.NewLocalAccounts.Items | ForEach-Object { $_.Password })
        Clear-SelectionSecret -Selection $selection
        foreach ($account in $selection.NewLocalAccounts.Items) { $account.Password | Should -BeNullOrEmpty }
        foreach ($password in $passwords) { { $password.AppendChar('x') } | Should -Throw }
    }
    It 'sans mot de passe ou sans sélection : sans effet' {
        { Clear-SelectionSecret -Selection (New-Selection) } | Should -Not -Throw
        { Clear-SelectionSecret -Selection $null } | Should -Not -Throw
    }
}
