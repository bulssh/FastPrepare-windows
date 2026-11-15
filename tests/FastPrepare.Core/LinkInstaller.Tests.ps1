<#
    Reconnaissance des installateurs d'agent RMM et d'antivirus à partir du lien collé (itération 16).
    Liens fictifs (domaines d'exemple).
#>
BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core
}

Describe 'Resolve-LinkInstaller — agent RMM' {
    It 'NinjaOne (.msi) : msiexec silencieux, sans redémarrage' {
        $r = Resolve-LinkInstaller -Kind Rmm -Url 'https://app.ninjarmm.example/agent/installer/0000/client-site-5.9.msi'
        $r.Error | Should -BeNullOrEmpty
        $r.Product | Should -Be 'NinjaOne'
        $r.Runner | Should -Be 'msiexec'
        $r.Arguments | Should -Be '/qn /norestart'
        $r.FileName | Should -Be 'client-site-5.9.msi'
    }
    It 'Datto RMM (.exe) : lancé tel quel' {
        $r = Resolve-LinkInstaller -Kind Rmm -Url 'https://fichiers.example/AgentSetup_Client.exe'
        $r.Error | Should -BeNullOrEmpty
        $r.Runner | Should -Be 'exe'
        $r.Arguments | Should -BeNullOrEmpty
    }
    It 'Datto RMM : lien de téléchargement sans nom de fichier' {
        $r = Resolve-LinkInstaller -Kind Rmm -Url 'https://zinfandel.centrastage.net/csm/profile/downloadAgent/00000000-0000-0000-0000-000000000000'
        $r.Error | Should -BeNullOrEmpty
        $r.Product | Should -Be 'Datto RMM'
        $r.FileName | Should -Be 'AgentSetup.exe'
        $r.Runner | Should -Be 'exe'
    }
    It 'les paramètres du lien (après ?) ne font pas partie du nom de fichier' {
        (Resolve-LinkInstaller -Kind Rmm -Url 'https://fichiers.example/agent.msi?jeton=abc').FileName | Should -Be 'agent.msi'
    }
    It 'refus : <Url>' -ForEach @(
        @{ Url = ''; Expected = 'lien vide' }
        @{ Url = 'http://fichiers.example/agent.msi'; Expected = 'https' }
        @{ Url = 'agent.msi'; Expected = 'https' }
        @{ Url = 'https://fichiers.example/page.html'; Expected = '\.msi' }
        @{ Url = 'https://fichiers.example/'; Expected = '\.msi' }
    ) {
        $r = Resolve-LinkInstaller -Kind Rmm -Url $Url
        $r.Error | Should -Match $Expected
        $r.Runner | Should -BeNullOrEmpty
    }
}

Describe 'Resolve-LinkInstaller — antivirus' {
    It 'Bitdefender setupdownloader : nom conservé (crochets compris), /bdparams /silent' {
        $r = Resolve-LinkInstaller -Kind Antivirus -Url 'https://cloud.gravityzone.example/Packages/BSTWIN/0/setupdownloader_%5BaHR0cHM6Ly9leGVtcGxl%5D.exe'
        $r.Error | Should -BeNullOrEmpty
        $r.Product | Should -Be 'Bitdefender'
        $r.FileName | Should -Be 'setupdownloader_[aHR0cHM6Ly9leGVtcGxl].exe'
        $r.Arguments | Should -Be '/bdparams /silent'
    }
    It 'Bitdefender (.msi) : msiexec /qn' {
        $r = Resolve-LinkInstaller -Kind Antivirus -Url 'https://download.bitdefender.example/eps_installer_x64.msi'
        $r.Product | Should -Be 'Bitdefender'
        $r.Runner | Should -Be 'msiexec'
        $r.Arguments | Should -Be '/qn /norestart'
    }
    It 'ESET PROTECT_Installer : --silent --accepteula' {
        $r = Resolve-LinkInstaller -Kind Antivirus -Url 'https://fichiers.example/PROTECT_Installer_x64_fr_FR.exe'
        $r.Product | Should -Be 'ESET'
        $r.Arguments | Should -Be '--silent --accepteula'
    }
    It 'ESET installateur en ligne : --silent --acceptterms' {
        $r = Resolve-LinkInstaller -Kind Antivirus -Url 'https://download.eset.example/epi_win_live_installer.exe'
        $r.Product | Should -Match 'ESET'
        $r.Arguments | Should -Be '--silent --acceptterms'
    }
    It 'exécutable inconnu : refus (aucune commande silencieuse sûre)' {
        (Resolve-LinkInstaller -Kind Antivirus -Url 'https://fichiers.example/setup.exe').Error | Should -Match 'non reconnu'
    }
    It 'nom de fichier invalide : refus' {
        (Resolve-LinkInstaller -Kind Antivirus -Url 'https://fichiers.example/a%3Ab.exe').Error | Should -Match 'nom de fichier invalide'
    }
}

Describe 'Format-LinkInstallerCommand' {
    It 'msi : msiexec /i et arguments' {
        $r = Resolve-LinkInstaller -Kind Rmm -Url 'https://app.ninjarmm.example/agent.msi'
        Format-LinkInstallerCommand -Installer $r | Should -Be 'NinjaOne : téléchargement de https://app.ninjarmm.example/agent.msi → msiexec /i agent.msi /qn /norestart, signature vérifiée'
    }
    It 'exe sans argument' {
        $r = Resolve-LinkInstaller -Kind Rmm -Url 'https://fichiers.example/AgentSetup.exe'
        Format-LinkInstallerCommand -Installer $r | Should -Match '→ AgentSetup\.exe, signature vérifiée$'
    }
}
