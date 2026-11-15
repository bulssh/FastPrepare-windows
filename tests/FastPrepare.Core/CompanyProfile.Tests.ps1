<#
    Profils entreprise (itération 14) : normalisation, règles, nom de fichier, et surtout
    l'absence de tout mot de passe dans un profil. Données fictives.
#>
BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core

    function New-TestProfileSource {
        @'
{
  "ProfileVersion": 1,
  "Name": "  Cabinet Exemple ",
  "MicrosoftApps": { "Teams": true, "OneDrive": true, "Inconnu": true },
  "Office": { "EditionKey": "m365-business", "WithoutTeams": true, "IncludedApps": ["Outlook"] },
  "Software": ["google-chrome", " 7-zip ", ""],
  "WindowsUpdate": false,
  "LocalAccounts": [
    { "Name": "accueil", "FullName": "Accueil", "Administrator": false, "PasswordNeverExpires": true, "Password": "NeDoitPasSortir", "MotDePasse": "NeDoitPasSortir" },
    { "Name": "" }
  ],
  "Agents": { "RmmUrl": "https://app.ninjarmm.example/agent.msi", "AntivirusUrl": "" },
  "NetworkDrives": [ { "Letter": "p:", "Path": "\\\\srv\\Commun\\", "Label": "Commun" } ],
  "Printers": [ { "Name": "Accueil", "Address": "192.168.1.50", "InfPath": "C:\\Drivers\\pilote.inf", "DriverName": "Marque PCL6" } ],
  "Domain": { "Domain": "entreprise.local", "Account": "adm-jonction", "Password": "NeDoitPasSortir" },
  "Password": "NeDoitPasSortir"
}
'@ | ConvertFrom-Json
    }
}

Describe 'New-CompanyProfile' {
    It 'profil vide : listes vides, Windows Update et alimentation cochés' {
        $p = New-CompanyProfile -Name 'Client'
        $p.Name | Should -Be 'Client'
        $p.ProfileVersion | Should -Be 1
        @($p.Software).Count | Should -Be 0
        @($p.LocalAccounts).Count | Should -Be 0
        $p.WindowsUpdate | Should -BeTrue
        $p.Power | Should -BeTrue
    }
}

Describe 'ConvertTo-CompanyProfile' {
    It 'normalise les champs connus' {
        $p = ConvertTo-CompanyProfile -InputObject (New-TestProfileSource)
        $p.Name | Should -Be 'Cabinet Exemple'
        $p.MicrosoftApps.Teams | Should -BeTrue
        $p.MicrosoftApps.OneNote | Should -BeFalse
        $p.MicrosoftApps.PSObject.Properties['Inconnu'] | Should -BeNullOrEmpty
        $p.Office.EditionKey | Should -Be 'm365-business'
        $p.Office.WithoutTeams | Should -BeTrue
        $p.Software | Should -Be @('google-chrome', '7-zip')
        $p.WindowsUpdate | Should -BeFalse
        $p.Power | Should -BeTrue
        @($p.LocalAccounts).Count | Should -Be 1
        $p.LocalAccounts[0].PasswordNeverExpires | Should -BeTrue
        $p.NetworkDrives[0].Letter | Should -Be 'P'
        $p.NetworkDrives[0].Path | Should -Be '\\srv\Commun'
        $p.Printers[0].DriverName | Should -Be 'Marque PCL6'
        $p.Domain.Account | Should -Be 'adm-jonction'
    }

    It 'aucun mot de passe ne traverse la normalisation, où qu''il soit dans le fichier' {
        $json = ConvertTo-CompanyProfile -InputObject (New-TestProfileSource) | ConvertTo-Json -Depth 6
        $json | Should -Not -Match 'NeDoitPasSortir'
        # Clé exacte : PasswordNeverExpires et consorts sont des options, pas des mots de passe.
        $json | Should -Not -Match '(?i)"(password|motdepasse)"\s*:'
    }

    It 'objet vide ou absent : profil vide' {
        (ConvertTo-CompanyProfile -InputObject $null).Name | Should -BeNullOrEmpty
        $p = ConvertTo-CompanyProfile -InputObject ('{}' | ConvertFrom-Json)
        @($p.Printers).Count | Should -Be 0
        $p.Agents.RmmUrl | Should -BeNullOrEmpty
    }

    It 'types inattendus : valeurs par défaut' {
        $p = ConvertTo-CompanyProfile -InputObject ('{ "Name": "X", "WindowsUpdate": "oui", "Software": "google-chrome", "Office": [] }' | ConvertFrom-Json)
        $p.WindowsUpdate | Should -BeTrue
        $p.Software | Should -Be @('google-chrome')
        $p.Office.EditionKey | Should -BeNullOrEmpty
    }

    It 'aller-retour JSON stable' {
        $first = ConvertTo-CompanyProfile -InputObject (New-TestProfileSource)
        $second = ConvertTo-CompanyProfile -InputObject ($first | ConvertTo-Json -Depth 6 | ConvertFrom-Json)
        ($second | ConvertTo-Json -Depth 6) | Should -Be ($first | ConvertTo-Json -Depth 6)
    }
}

Describe 'Get-CompanyProfileError' {
    It 'profil cohérent : aucune incohérence' {
        @(Get-CompanyProfileError -CompanyProfile (ConvertTo-CompanyProfile -InputObject (New-TestProfileSource)) -ExistingName @('Autre client')) | Should -BeNullOrEmpty
    }
    It 'nom vide, trop long, interdit ou déjà pris : refus' {
        Get-CompanyProfileError -CompanyProfile (New-CompanyProfile -Name ' ') | Should -Match 'nom du profil vide'
        Get-CompanyProfileError -CompanyProfile (New-CompanyProfile -Name ('n' * 61)) | Should -Match '61 caractères sur 60'
        Get-CompanyProfileError -CompanyProfile (New-CompanyProfile -Name 'a/b') | Should -Match 'caractère interdit'
        Get-CompanyProfileError -CompanyProfile (New-CompanyProfile -Name 'client') -ExistingName @('Client') | Should -Match 'existe déjà'
    }
    It 'version inconnue : refus' {
        $p = New-CompanyProfile -Name 'Client'
        $p.ProfileVersion = 2
        Get-CompanyProfileError -CompanyProfile $p | Should -Match 'version de profil 2'
    }
    It 'listes incohérentes : chaque motif est rapporté' {
        $p = ConvertTo-CompanyProfile -InputObject (New-TestProfileSource)
        $p.NetworkDrives += [pscustomobject]@{ Letter = 'P'; Path = '\\srv\Autre'; Label = '' }
        $p.Agents.AntivirusUrl = 'https://fichiers.example/setup.exe'
        $p.Domain.Domain = 'ENTREPRISE'
        $problems = @(Get-CompanyProfileError -CompanyProfile $p)
        $problems.Count | Should -Be 3
        ($problems -join ' | ') | Should -Match 'déjà utilisée.*non reconnu.*nom DNS complet'
    }
}

Describe 'Get-CompanyProfileFileName' {
    It '<Name> → <Expected>' -ForEach @(
        @{ Name = 'Cabinet Exemple'; Expected = 'cabinet-exemple.json' }
        @{ Name = 'Société Générale d''Études'; Expected = 'societe-generale-d-etudes.json' }
        @{ Name = '***'; Expected = 'profil.json' }
    ) {
        Get-CompanyProfileFileName -Name $Name | Should -Be $Expected
    }
}
