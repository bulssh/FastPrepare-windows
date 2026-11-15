<#
    Profils entreprise sur la clé (itération 14) : enregistrement, liste, lecture, refus, et
    absence de mot de passe dans le fichier écrit. Dossier de test, données fictives.
#>
BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core, Infrastructure, Application

    function New-TestProfile {
        param([string]$Name = 'Cabinet Exemple')
        $p = New-CompanyProfile -Name $Name
        $p.Software = @('google-chrome')
        $p.MicrosoftApps.Teams = $true
        $p.LocalAccounts = @([pscustomobject]@{ Name = 'accueil'; FullName = 'Accueil'; Description = ''; Administrator = $false; PasswordNeverExpires = $true; MustChangePassword = $false; CannotChangePassword = $false; Disabled = $false; Password = 'NeDoitPasSortir' })
        $p.NetworkDrives = @([pscustomobject]@{ Letter = 'P'; Path = '\\srv\Commun'; Label = 'Commun' })
        $p.Domain.Domain = 'entreprise.local'
        $p.Domain.Account = 'adm-jonction'
        return $p
    }
}

Describe 'Export-CompanyProfile / Get-CompanyProfileList / Import-CompanyProfile' {
    BeforeEach {
        $folder = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $folder | Out-Null
        $context = New-TestContext -Folder $folder
    }

    It 'enregistre dans profils\, sans mot de passe, JSON relisible' {
        $saved = Export-CompanyProfile -Context $context -CompanyProfile (New-TestProfile)
        $saved.Path | Should -Be (Join-Path $context.Paths.Profiles 'cabinet-exemple.json')
        $text = [System.IO.File]::ReadAllText($saved.Path)
        $text | Should -Not -Match 'NeDoitPasSortir'
        $text | Should -Not -Match '(?i)"password"\s*:'
        ($text | ConvertFrom-Json).Name | Should -Be 'Cabinet Exemple'
        [System.IO.File]::ReadAllBytes($saved.Path)[0] | Should -Be ([byte][char]'{')
    }

    It 'aller-retour : le profil relu est identique au profil enregistré' {
        $saved = Export-CompanyProfile -Context $context -CompanyProfile (New-TestProfile)
        $read = Import-CompanyProfile -Context $context -Path $saved.Path
        $read.Software | Should -Be @('google-chrome')
        $read.MicrosoftApps.Teams | Should -BeTrue
        $read.LocalAccounts[0].Name | Should -Be 'accueil'
        $read.NetworkDrives[0].Path | Should -Be '\\srv\Commun'
        $read.Domain.Domain | Should -Be 'entreprise.local'
    }

    It 'liste triée par nom ; dossier absent : liste vide' {
        @(Get-CompanyProfileList -Context $context) | Should -BeNullOrEmpty
        [void](Export-CompanyProfile -Context $context -CompanyProfile (New-TestProfile -Name 'Zèbre SARL'))
        [void](Export-CompanyProfile -Context $context -CompanyProfile (New-TestProfile -Name 'Atelier'))
        (@(Get-CompanyProfileList -Context $context) | ForEach-Object { $_.Name }) -join '|' | Should -Be 'Atelier|Zèbre SARL'
    }

    It 'même nom : le profil est remplacé, pas dupliqué' {
        [void](Export-CompanyProfile -Context $context -CompanyProfile (New-TestProfile))
        $changed = New-TestProfile
        $changed.Software = @('7-zip')
        [void](Export-CompanyProfile -Context $context -CompanyProfile $changed)
        $list = @(Get-CompanyProfileList -Context $context)
        $list.Count | Should -Be 1
        (Import-CompanyProfile -Context $context -Path $list[0].Path).Software | Should -Be @('7-zip')
    }

    It 'autre nom qui donnerait le même fichier : refus, rien n''est écrasé' {
        [void](Export-CompanyProfile -Context $context -CompanyProfile (New-TestProfile -Name 'Cabinet Exemple'))
        { Export-CompanyProfile -Context $context -CompanyProfile (New-TestProfile -Name 'Cabinet-Exemple') } | Should -Throw '*déjà celui du profil*'
        @(Get-CompanyProfileList -Context $context)[0].Name | Should -Be 'Cabinet Exemple'
    }

    It 'profil incohérent : refus, rien n''est écrit' {
        $bad = New-TestProfile -Name ''
        { Export-CompanyProfile -Context $context -CompanyProfile $bad } | Should -Throw '*nom du profil vide*'
        Test-Path -LiteralPath $context.Paths.Profiles | Should -BeFalse
    }

    It 'fichier illisible : ignoré dans la liste, signalé au journal' {
        [void](Export-CompanyProfile -Context $context -CompanyProfile (New-TestProfile))
        Set-Content -LiteralPath (Join-Path $context.Paths.Profiles 'casse.json') -Value '{ ceci n''est pas du JSON'
        @(Get-CompanyProfileList -Context $context).Count | Should -Be 1
        [System.IO.File]::ReadAllText($context.Log.FilePath) | Should -Match 'Profil illisible \(casse\.json\)'
    }

    It 'fichier écrit à la main avec un mot de passe : il n''est jamais relu' {
        New-Item -ItemType Directory -Path $context.Paths.Profiles -Force | Out-Null
        $path = Join-Path $context.Paths.Profiles 'main.json'
        Set-Content -LiteralPath $path -Value '{ "ProfileVersion": 1, "Name": "Main", "Domain": { "Domain": "entreprise.local", "Account": "adm", "Password": "NeDoitPasSortir" } }'
        $read = Import-CompanyProfile -Context $context -Path $path
        ($read | ConvertTo-Json -Depth 6) | Should -Not -Match 'NeDoitPasSortir'
    }
}
