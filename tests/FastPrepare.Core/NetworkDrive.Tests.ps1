BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core
}

Describe 'New-NetworkDriveRequest' {
    It 'normalise la lettre et le chemin' {
        $drive = New-NetworkDriveRequest -Letter ' p: ' -Path ' \\srv-fichiers\Commun\ ' -Label ' Commun '
        $drive.Letter | Should -Be 'P'
        $drive.Path | Should -Be '\\srv-fichiers\Commun'
        $drive.Label | Should -Be 'Commun'
    }
}

Describe 'Get-NetworkDriveError' {
    It 'lecteur valable : <Path>' -ForEach @(
        @{ Path = '\\srv-fichiers\Commun' }
        @{ Path = '\\192.168.1.10\Compta$' }
        @{ Path = '\\srv.exemple.local\Partage\Sous dossier' }
    ) {
        Get-NetworkDriveError -Drive (New-NetworkDriveRequest -Letter 'P' -Path $Path -Label 'Commun') -UsedLetter @('C', 'D') | Should -BeNullOrEmpty
    }

    It 'refus : lettre <Letter>, chemin <Path>' -ForEach @(
        @{ Letter = ''; Path = '\\srv\p'; Expected = 'lettre de lecteur attendue' }
        @{ Letter = 'PP'; Path = '\\srv\p'; Expected = 'lettre de lecteur attendue' }
        @{ Letter = '1'; Path = '\\srv\p'; Expected = 'lettre de lecteur attendue' }
        @{ Letter = 'C'; Path = '\\srv\p'; Expected = 'réservée' }
        @{ Letter = 'D'; Path = '\\srv\p'; Expected = 'déjà utilisée' }
        @{ Letter = 'P'; Path = ''; Expected = 'chemin réseau vide' }
        @{ Letter = 'P'; Path = '\\srv'; Expected = '\\\\serveur\\partage' }
        @{ Letter = 'P'; Path = 'srv\partage'; Expected = '\\\\serveur\\partage' }
        @{ Letter = 'P'; Path = 'P:\dossier'; Expected = '\\\\serveur\\partage' }
        @{ Letter = 'P'; Path = '\\srv\par*tage'; Expected = '\\\\serveur\\partage' }
    ) {
        Get-NetworkDriveError -Drive (New-NetworkDriveRequest -Letter $Letter -Path $Path) -UsedLetter @('C:', 'd') | Should -Match $Expected
    }

    It 'libellé trop long ou avec un caractère interdit : refus' {
        Get-NetworkDriveError -Drive (New-NetworkDriveRequest -Letter 'P' -Path '\\srv\p' -Label ('x' * 33)) | Should -Match '33 caractères sur 32'
        Get-NetworkDriveError -Drive (New-NetworkDriveRequest -Letter 'P' -Path '\\srv\p' -Label 'a:b') | Should -Match 'caractère interdit'
    }
}

Describe 'Get-NetworkDriveLabelKeyName' {
    It 'chaque barre oblique inverse devient un dièse' {
        Get-NetworkDriveLabelKeyName -Path '\\srv-fichiers\Commun' | Should -Be '##srv-fichiers#Commun'
        Get-NetworkDriveLabelKeyName -Path '\\srv\Partage\Sous dossier\' | Should -Be '##srv#Partage#Sous dossier'
    }
}

Describe 'Format-NetworkDriveSummary' {
    It 'avec et sans libellé' {
        Format-NetworkDriveSummary -Drive (New-NetworkDriveRequest -Letter 'p' -Path '\\srv\Commun' -Label 'Commun') | Should -Be 'P: → \\srv\Commun (Commun)'
        Format-NetworkDriveSummary -Drive (New-NetworkDriveRequest -Letter 'S' -Path '\\srv\Scans') | Should -Be 'S: → \\srv\Scans'
    }
}
