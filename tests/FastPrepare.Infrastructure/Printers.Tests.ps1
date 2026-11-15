<#
    Installation d'une imprimante IP (itération 17) : jamais exécutée pour de vrai.
    Les applets d'impression et pnputil sont remplacés par des simulacres.
#>
BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core, Infrastructure
    $m = @{ ModuleName = 'FastPrepare.Infrastructure' }
    $inf = Join-Path $TestDrive 'pilote.inf'
    Set-Content -LiteralPath $inf -Value '[Version]'
    $common = @{ Name = 'Accueil'; Address = '192.168.1.50'; InfPath = $inf; DriverName = 'Marque Universal PCL6'; PortName = 'IP_192.168.1.50' }
}

Describe 'Install-IpPrinter' {
    BeforeEach {
        Mock @m Get-Printer { }
        Mock @m Get-PrinterDriver { }
        Mock @m Get-PrinterPort { }
        Mock @m Add-PrinterDriver { }
        Mock @m Add-PrinterPort { }
        Mock @m Add-Printer { }
        Mock @m Get-SystemExecutablePath { "C:\Windows\System32\$Name" }
        Mock @m Invoke-ExternalProcess { [pscustomobject]@{ ExitCode = 0; RebootRequired = $false } }
    }

    It 'poste vierge : pilote au magasin, pilote d''impression, port, imprimante' {
        $result = Install-IpPrinter @common
        $result.RebootRequired | Should -BeFalse
        Should -Invoke @m Invoke-ExternalProcess -Times 1 -ParameterFilter { $FilePath -like '*pnputil.exe' -and $ArgumentList -eq ('/add-driver "{0}" /install' -f $inf) }
        Should -Invoke @m Add-PrinterDriver -Times 1 -ParameterFilter { $Name -eq 'Marque Universal PCL6' }
        Should -Invoke @m Add-PrinterPort -Times 1 -ParameterFilter { $Name -eq 'IP_192.168.1.50' -and $PrinterHostAddress -eq '192.168.1.50' }
        Should -Invoke @m Add-Printer -Times 1 -ParameterFilter { $Name -eq 'Accueil' -and $DriverName -eq 'Marque Universal PCL6' -and $PortName -eq 'IP_192.168.1.50' }
    }

    It 'pilote et port déjà présents : seule l''imprimante est ajoutée' {
        Mock @m Get-PrinterDriver { [pscustomobject]@{ Name = 'Marque Universal PCL6' } }
        Mock @m Get-PrinterPort { [pscustomobject]@{ Name = 'IP_192.168.1.50' } }
        [void](Install-IpPrinter @common)
        Should -Invoke @m Invoke-ExternalProcess -Times 0
        Should -Invoke @m Add-PrinterDriver -Times 0
        Should -Invoke @m Add-PrinterPort -Times 0
        Should -Invoke @m Add-Printer -Times 1
    }

    It 'imprimante du même nom déjà présente : refus, rien n''est modifié' {
        Mock @m Get-Printer { [pscustomobject]@{ Name = 'Accueil' } }
        { Install-IpPrinter @common } | Should -Throw '*existe déjà*'
        Should -Invoke @m Add-Printer -Times 0
        Should -Invoke @m Invoke-ExternalProcess -Times 0
    }

    It 'fichier .inf absent : refus avant pnputil' {
        $missing = $common.Clone()
        $missing.InfPath = Join-Path $TestDrive 'absent.inf'
        { Install-IpPrinter @missing } | Should -Throw '*pilote introuvable*'
        Should -Invoke @m Invoke-ExternalProcess -Times 0
    }

    It 'modèle absent du pilote : message explicite, imprimante non créée' {
        Mock @m Add-PrinterDriver { throw 'Le pilote spécifié n''existe pas dans le magasin de pilotes.' }
        { Install-IpPrinter @common } | Should -Throw '*comme dans le fichier .inf*'
        Should -Invoke @m Add-Printer -Times 0
    }

    It 'redémarrage demandé par pnputil : remonté' {
        Mock @m Invoke-ExternalProcess { [pscustomobject]@{ ExitCode = 3010; RebootRequired = $true } }
        (Install-IpPrinter @common).RebootRequired | Should -BeTrue
    }
}

Describe 'Get-PrinterDriverInf' {
    It 'liste les .inf, sous-dossiers compris ; dossier absent : liste vide' {
        $folder = Join-Path $TestDrive 'Drivers'
        New-Item -ItemType Directory -Path (Join-Path $folder 'Marque') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $folder 'a.inf') -Value 'x'
        Set-Content -LiteralPath (Join-Path (Join-Path $folder 'Marque') 'b.inf') -Value 'x'
        Set-Content -LiteralPath (Join-Path $folder 'lisezmoi.txt') -Value 'x'
        @(Get-PrinterDriverInf -Folder $folder).Count | Should -Be 2
        @(Get-PrinterDriverInf -Folder (Join-Path $TestDrive 'absent')) | Should -BeNullOrEmpty
    }
}

Describe 'Read-InfContent' {
    It 'lit un fichier UTF-16 avec marque d''ordre d''octets' {
        $path = Join-Path $TestDrive 'utf16.inf'
        [System.IO.File]::WriteAllText($path, "[Manufacturer]`r`n""Marque""=M", [System.Text.Encoding]::Unicode)
        Read-InfContent -Path $path | Should -Match '^\[Manufacturer\]'
    }
}
