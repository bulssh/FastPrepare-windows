<#
    Mappage persistant d'un lecteur réseau (itération 17), écrit dans une ruche de test
    (TestRegistry de Pester) : le registre réel n'est jamais touché. Tests propres à Windows.
#>
BeforeDiscovery {
    $script:OnWindows = ($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows
}
BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core, Infrastructure
}

Describe 'Set-PersistentNetworkDrive' -Skip:(-not $script:OnWindows) {
    BeforeEach {
        $root = 'TestRegistry:\Utilisateur'
        if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        New-Item -Path $root -Force | Out-Null
        $common = @{ UserSid = 'S-1-5-21-1-2-3-1001'; UserRoot = $root; Letter = 'P'; Path = '\\srv-fichiers\Commun' }
    }

    It 'écrit les valeurs de « net use /persistent:yes » et le libellé' {
        $result = Set-PersistentNetworkDrive @common -Label 'Commun' -LabelKeyName '##srv-fichiers#Commun'
        $result.AlreadyPresent | Should -BeFalse
        $values = Get-ItemProperty -LiteralPath (Join-Path $root 'Network\P')
        $values.RemotePath | Should -Be '\\srv-fichiers\Commun'
        $values.ProviderName | Should -Be 'Microsoft Windows Network'
        $values.ProviderType | Should -Be 0x20000
        $values.ConnectionType | Should -Be 1
        $values.DeferFlags | Should -Be 4
        $values.UserName | Should -Be ''
        (Get-ItemProperty -LiteralPath (Join-Path $root 'Software\Microsoft\Windows\CurrentVersion\Explorer\MountPoints2\##srv-fichiers#Commun'))._LabelFromReg | Should -Be 'Commun'
    }

    It 'même lecteur déjà présent : laissé tel quel' {
        [void](Set-PersistentNetworkDrive @common)
        (Set-PersistentNetworkDrive @common).AlreadyPresent | Should -BeTrue
    }

    It 'lettre déjà connectée à un autre chemin : erreur, mappage inchangé' {
        [void](Set-PersistentNetworkDrive @common)
        $other = $common.Clone()
        $other.Path = '\\srv\Autre'
        { Set-PersistentNetworkDrive @other } | Should -Throw '*déjà connecté*'
        (Get-ItemProperty -LiteralPath (Join-Path $root 'Network\P')).RemotePath | Should -Be '\\srv-fichiers\Commun'
    }

    It 'ruche de l''utilisateur non chargée : erreur explicite' {
        $missing = $common.Clone()
        $missing.UserRoot = 'TestRegistry:\Absent'
        { Set-PersistentNetworkDrive @missing } | Should -Throw '*non chargé*'
    }
}
