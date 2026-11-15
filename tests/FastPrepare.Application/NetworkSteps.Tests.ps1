<#
    Étapes « lecteurs réseau » et « imprimantes IP » (itération 17) : plan, puis exécution réelle
    avec des simulacres (ni registre, ni pilote, ni imprimante touchés). Données fictives.
#>
BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core, Infrastructure, Application
    $m = @{ ModuleName = 'FastPrepare.Application' }

    function New-NetworkSelection {
        $selection = New-Selection
        $selection.NetworkDrives.Items = @(
            New-NetworkDriveRequest -Letter 'P' -Path '\\srv-fichiers\Commun' -Label 'Commun'
            New-NetworkDriveRequest -Letter 'S' -Path '\\srv-fichiers\Scans'
        )
        $selection.Printers.Items = @(New-IpPrinterRequest -Name 'Accueil' -Address '192.168.1.50' -InfPath 'C:\Drivers\Marque\pilote.inf' -DriverName 'Marque Universal PCL6')
        return $selection
    }
}

Describe 'Plan — lecteurs réseau et imprimantes IP' {
    It 'rien de demandé : aucune action' {
        $context = New-TestContext -Folder $TestDrive
        $plan = New-ExecutionPlan -Selection (New-Selection) -Snapshot (New-TestSnapshot) -Context $context
        @($plan.Actions | Where-Object { $_.StepId -in @('map-network-drives', 'add-ip-printers') }) | Should -BeNullOrEmpty
    }

    It 'une action par lecteur (rang 16) et par imprimante (rang 17)' {
        $context = New-TestContext -Folder $TestDrive
        $plan = New-ExecutionPlan -Selection (New-NetworkSelection) -Snapshot (New-TestSnapshot) -Context $context
        $drives = @($plan.Actions | Where-Object StepId -EQ 'map-network-drives')
        $printers = @($plan.Actions | Where-Object StepId -EQ 'add-ip-printers')
        $drives.Count | Should -Be 2
        $drives[0].StepNumber | Should -Be 16
        $drives[0].Label | Should -Be 'Lecteur réseau : P: → \\srv-fichiers\Commun (Commun) — mappage persistant pour la session ouverte (HKU\<SID>\Network\P)'
        $printers.Count | Should -Be 1
        $printers[0].StepNumber | Should -Be 17
        $printers[0].Label | Should -Match '^Imprimante IP : Accueil → 192\.168\.1\.50 · Marque Universal PCL6 \(pilote\.inf\) — .*Add-PrinterPort IP_192\.168\.1\.50, Add-Printer$'
        $printers[0].Parameters.PortName | Should -Be 'IP_192.168.1.50'
    }

    It 'même lettre demandée deux fois : plan refusé' {
        $context = New-TestContext -Folder $TestDrive
        $selection = New-NetworkSelection
        $selection.NetworkDrives.Items += New-NetworkDriveRequest -Letter 'p' -Path '\\srv\Autre'
        { New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $context } | Should -Throw '*déjà utilisée*'
    }

    It 'imprimante sans pilote : plan refusé' {
        $context = New-TestContext -Folder $TestDrive
        $selection = New-Selection
        $selection.Printers.Items = @(New-IpPrinterRequest -Name 'Accueil' -Address '192.168.1.50' -InfPath '' -DriverName '')
        { New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $context } | Should -Throw '*non choisi*'
    }
}

Describe 'Mode réel — lecteurs réseau' {
    BeforeEach {
        Mock @m Get-InteractiveUser { [pscustomobject]@{ Name = 'PC-TEST\jdupont'; Sid = 'S-1-5-21-1-2-3-1001' } }
        Mock @m Get-UsedDriveLetter { @('C', 'D') }
        Mock @m Set-PersistentNetworkDrive { [pscustomobject]@{ AlreadyPresent = $false } }
        $context = New-TestContext -Folder $TestDrive -Mode Real
        $selection = New-Selection
        $selection.NetworkDrives.Items = @(New-NetworkDriveRequest -Letter 'P' -Path '\\srv-fichiers\Commun' -Label 'Commun')
    }

    It 'écrit le mappage dans la ruche de l''utilisateur de la session ouverte' {
        $plan = New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $context
        $results = Invoke-ExecutionPlan -Plan $plan -Context $context
        $results[-1].Outcome | Should -Be 'Succeeded'
        Should -Invoke @m Set-PersistentNetworkDrive -Times 1 -ParameterFilter {
            $UserSid -eq 'S-1-5-21-1-2-3-1001' -and $Letter -eq 'P' -and $Path -eq '\\srv-fichiers\Commun' -and $Label -eq 'Commun' -and $LabelKeyName -eq '##srv-fichiers#Commun'
        }
        [System.IO.File]::ReadAllText($context.Log.FilePath) | Should -Match 'Lecteur P: connecté à \\\\srv-fichiers\\Commun pour PC-TEST\\jdupont'
    }

    It 'aucune session ouverte : échec, rien n''est écrit' {
        Mock @m Get-InteractiveUser { $null }
        $plan = New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $context
        $results = Invoke-ExecutionPlan -Plan $plan -Context $context
        $results[-1].Outcome | Should -Be 'Failed'
        Should -Invoke @m Set-PersistentNetworkDrive -Times 0
    }

    It 'lettre prise par un disque du poste : échec, rien n''est écrit' {
        Mock @m Get-UsedDriveLetter { @('C', 'P') }
        $plan = New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $context
        $results = Invoke-ExecutionPlan -Plan $plan -Context $context
        $results[-1].Error | Should -Match 'déjà utilisée par un disque'
        Should -Invoke @m Set-PersistentNetworkDrive -Times 0
    }
}

Describe 'Mode réel — imprimantes IP' {
    It 'transmet nom, adresse, pilote, modèle et port ; signale le redémarrage demandé' {
        Mock @m Install-IpPrinter { [pscustomobject]@{ RebootRequired = $true } }
        $context = New-TestContext -Folder $TestDrive -Mode Real
        $selection = New-Selection
        $selection.Printers.Items = @(New-IpPrinterRequest -Name 'Accueil' -Address '192.168.1.50' -InfPath 'C:\Drivers\Marque\pilote.inf' -DriverName 'Marque Universal PCL6')
        $plan = New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $context
        $results = Invoke-ExecutionPlan -Plan $plan -Context $context
        $results[-1].Outcome | Should -Be 'Succeeded'
        Should -Invoke @m Install-IpPrinter -Times 1 -ParameterFilter {
            $Name -eq 'Accueil' -and $Address -eq '192.168.1.50' -and $InfPath -eq 'C:\Drivers\Marque\pilote.inf' -and $DriverName -eq 'Marque Universal PCL6' -and $PortName -eq 'IP_192.168.1.50'
        }
    }
}

Describe 'Pilotes d''imprimante' {
    It 'dossier par défaut C:\Drivers, remplacé par config.Printers.DriverFolder' {
        $context = New-TestContext -Folder $TestDrive
        $context.Config.Printers.DriverFolder = 'D:\Pilotes'
        Get-PrinterDriverFolder -Context $context | Should -Be 'D:\Pilotes'
        $context.Config.PSObject.Properties.Remove('Printers')
        Get-PrinterDriverFolder -Context $context | Should -Be 'C:\Drivers'
    }

    It 'catalogue : chemin complet et chemin relatif au dossier' {
        Mock @m Get-PrinterDriverInf { @('C:\Drivers\Marque\pilote.inf', 'C:\Drivers\autre.inf') }
        $context = New-TestContext -Folder $TestDrive
        $context.Config.PSObject.Properties.Remove('Printers')
        $catalog = @(Get-PrinterDriverCatalog -Context $context)
        ($catalog | ForEach-Object { $_.Display }) -join '|' | Should -Be 'Marque\pilote.inf|autre.inf'
        $catalog[0].Path | Should -Be 'C:\Drivers\Marque\pilote.inf'
    }

    It 'modèles d''un fichier .inf ; fichier illisible : liste vide' {
        Mock @m Read-InfContent { "[Manufacturer]`n""Marque""=M`n[M]`n""Modele A""=X`n""Modele B""=Y" }
        Get-PrinterDriverModel -InfPath 'C:\Drivers\pilote.inf' | Should -Be @('Modele A', 'Modele B')
        Mock @m Read-InfContent { throw 'accès refusé' }
        @(Get-PrinterDriverModel -InfPath 'C:\Drivers\pilote.inf') | Should -BeNullOrEmpty
    }
}
