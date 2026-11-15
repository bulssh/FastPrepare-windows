BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core

    function New-TestPrinter {
        param([string]$Name = 'Accueil', [string]$Address = '192.168.1.50', [string]$InfPath = 'C:\Drivers\Marque\pilote.inf', [string]$DriverName = 'Marque Universal PCL6')
        New-IpPrinterRequest -Name $Name -Address $Address -InfPath $InfPath -DriverName $DriverName
    }

    $script:InfText = @'
; Pilote d'exemple (fictif)
[Version]
Signature="$Windows NT$"
Class=Printer

[Manufacturer]
%MFG% = Modeles,NTamd64,NTarm64   ; commentaire
"Autre Marque" = Autres

[Modeles.NTamd64]
"Marque Universal PCL6" = INSTALL_PCL6, USBPRINT\MarqueUPD
%MODELE_B% = INSTALL_PS, USBPRINT\MarquePS
"Marque ; Série 500" = INSTALL_500   ; point-virgule entre guillemets

[Modeles.NTarm64]
"Marque Universal PCL6" = INSTALL_PCL6

[Autres]
Modele Sans Guillemets = INSTALL_X

[INSTALL_PCL6]
CopyFiles = FICHIERS

[Strings]
MFG = "Marque"
MODELE_B = "Marque Universal PS"   ; commentaire
'@
}

Describe 'Get-IpPrinterError' {
    It 'imprimante valable (adresse <Address>)' -ForEach @(
        @{ Address = '192.168.1.50' }, @{ Address = 'imprimante-accueil' }, @{ Address = 'copieur.exemple.local' }
    ) {
        Get-IpPrinterError -Printer (New-TestPrinter -Address $Address) -ExistingName @('Compta') | Should -BeNullOrEmpty
    }

    It 'refus : <Expected>' -ForEach @(
        @{ Printer = @{ Name = '' }; Expected = 'nom de l''imprimante vide' }
        @{ Printer = @{ Name = 'a\b' }; Expected = 'caractère interdit' }
        @{ Printer = @{ Name = 'compta' }; Expected = 'déjà dans la liste' }
        @{ Printer = @{ Address = '' }; Expected = 'adresse IP vide' }
        @{ Printer = @{ Address = '192.168.1.300' }; Expected = 'adresse IP \(ex' }
        @{ Printer = @{ Address = '192.168.1' }; Expected = 'adresse IP \(ex' }
        @{ Printer = @{ Address = 'nom avec espace' }; Expected = 'adresse IP \(ex' }
        @{ Printer = @{ InfPath = '' }; Expected = 'non choisi' }
        @{ Printer = @{ InfPath = 'C:\Drivers\setup.exe' }; Expected = 'fichier \.inf' }
        @{ Printer = @{ DriverName = '' }; Expected = 'modèle' }
    ) {
        $arguments = $Printer
        Get-IpPrinterError -Printer (New-TestPrinter @arguments) -ExistingName @('Compta') | Should -Match $Expected
    }
}

Describe 'Get-IpPrinterPortName' {
    It 'convention de Windows' { Get-IpPrinterPortName -Address '192.168.1.50' | Should -Be 'IP_192.168.1.50' }
}

Describe 'Get-InfPrinterModel' {
    It 'liste les modèles : guillemets, jetons %…% résolus, variantes d''architecture, sans doublon' {
        $models = @(Get-InfPrinterModel -Content $script:InfText)
        $models | Should -Be @('Marque ; Série 500', 'Marque Universal PCL6', 'Marque Universal PS', 'Modele Sans Guillemets')
    }
    It 'fins de ligne Unix acceptées' {
        @(Get-InfPrinterModel -Content ($script:InfText -replace "`r", '')).Count | Should -Be 4
    }
    It 'fichier vide ou sans section [Manufacturer] : liste vide' {
        @(Get-InfPrinterModel -Content '') | Should -BeNullOrEmpty
        @(Get-InfPrinterModel -Content "[Version]`nClass=Printer") | Should -BeNullOrEmpty
    }
}

Describe 'Format-IpPrinterSummary' {
    It 'nom, adresse, modèle et fichier du pilote' {
        Format-IpPrinterSummary -Printer (New-TestPrinter) | Should -Be 'Accueil → 192.168.1.50 · Marque Universal PCL6 (pilote.inf)'
    }
}
