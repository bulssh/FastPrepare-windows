<#
    Construction réelle de la fenêtre (WPF), sans l'afficher : tous les fichiers XAML sont chargés,
    chaque section est initialisée, chaque page est affichée, un profil entreprise fait
    l'aller-retour. Tests propres à Windows (ignorés ailleurs) : ce sont les premiers à lancer
    sur un poste Windows, car l'interface a été écrite sans pouvoir être affichée.
#>
BeforeDiscovery {
    $script:OnWindows = ($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows
}

Describe 'Fenêtre principale (construction WPF)' -Skip:(-not $script:OnWindows) {
    BeforeAll {
        . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
        Import-FastPrepareModule Core, Infrastructure, Application, UI
        $script:BuildContext = New-TestContext -Folder $TestDrive
        $script:BuildSnapshot = New-TestSnapshot
        $script:BuildError = $null
        try {
            InModuleScope FastPrepare.UI -Parameters @{ Context = $script:BuildContext } {
                param($Context)
                $script:TestWindow = New-MainWindow -Context $Context
            }
        } catch {
            $script:BuildError = $_
        }
    }

    It 'se construit sans erreur (XAML, thème, sections, profils)' {
        $script:BuildError | Should -BeNullOrEmpty
        InModuleScope FastPrepare.UI { $script:TestWindow | Should -BeOfType [System.Windows.Window] }
    }

    It 'chaque section a reçu son fragment et ses contrôles' {
        InModuleScope FastPrepare.UI {
            foreach ($section in (Get-UiSection)) {
                $section.Controls | Should -Not -BeNullOrEmpty -Because "section $($section.Id)"
                if ($section.XamlFile) { $section.Root | Should -Not -BeNullOrEmpty -Because "section $($section.Id)" }
            }
        }
    }

    It 'chaque page s''affiche ; une seule est visible à la fois' {
        InModuleScope FastPrepare.UI {
            foreach ($id in @($script:Pages.Keys)) {
                { Show-WizardPage -Id $id } | Should -Not -Throw -Because "page $id"
                $visible = @($script:Pages.Values | Where-Object { $_.Root.Visibility -eq 'Visible' })
                $visible.Count | Should -Be 1
                $visible[0].Page.Id | Should -Be $id
                $script:Shell.Controls.TxtPageTitle.Text | Should -Be $script:Pages[$id].Page.Title
            }
        }
    }

    It 'Suivant et Précédent suivent le parcours' {
        InModuleScope FastPrepare.UI {
            Show-WizardPage -Id 'poste'
            [string]$script:Shell.Controls.BtnPrev.Visibility | Should -Be 'Collapsed'
            $script:Shell.Controls.BtnNext.Content | Should -Be 'Suivant →'
            Show-WizardPage -Id 'systeme'
            $script:Shell.Controls.BtnNext.Content | Should -Be 'Vérifier et lancer →'
            Show-WizardPage -Id 'recap'
            [string]$script:Shell.Controls.BtnNext.Visibility | Should -Be 'Collapsed'
            [string]$script:Shell.Controls.BtnPrev.Visibility | Should -Be 'Visible'
        }
    }

    It 'la sélection de départ se construit et ne demande rien de plus que les cases par défaut' {
        InModuleScope FastPrepare.UI {
            $selection = Get-CurrentSelection
            try {
                @($selection.NewLocalAccounts.Items).Count | Should -Be 0
                @($selection.NetworkDrives.Items).Count | Should -Be 0
                @($selection.Printers.Items).Count | Should -Be 0
                $selection.DomainJoin.Domain | Should -BeNullOrEmpty
                $selection.Agents.RmmUrl | Should -BeNullOrEmpty
            } finally {
                Clear-SelectionSecret -Selection $selection
            }
        }
    }

    It 'profil entreprise : appliqué puis relu à l''identique, sans mot de passe' {
        InModuleScope FastPrepare.UI {
            $source = New-CompanyProfile -Name 'Client de test'
            $source.MicrosoftApps.Teams = $true
            $source.WindowsUpdate = $false
            $source.Agents.RmmUrl = 'https://app.ninjarmm.example/agent.msi'
            $source.LocalAccounts = @([pscustomobject]@{ Name = 'accueil'; FullName = 'Accueil'; Description = 'Poste accueil'; Administrator = $false; PasswordNeverExpires = $true; MustChangePassword = $false; CannotChangePassword = $true; Disabled = $false })
            $source.NetworkDrives = @([pscustomobject]@{ Letter = 'P'; Path = '\\srv\Commun'; Label = 'Commun' })
            $source.Printers = @([pscustomobject]@{ Name = 'Accueil'; Address = '192.168.1.50'; InfPath = 'C:\Drivers\pilote.inf'; DriverName = 'Marque PCL6' })
            $source.Domain.Domain = 'entreprise.local'
            $source.Domain.Account = 'adm-jonction'

            Set-UiProfile -CompanyProfile (ConvertTo-CompanyProfile -InputObject $source)
            # Une section qui échoue à l'application du profil l'écrit au journal : rien ne doit y figurer.
            # Le fichier du journal n'existe que si quelque chose y a été écrit.
            $errors = @()
            if (Test-Path -LiteralPath $script:Context.Log.FilePath) {
                $errors = @([System.IO.File]::ReadAllLines($script:Context.Log.FilePath) | Where-Object { $_ -match 'ERREUR' })
            }
            $errors | Should -BeNullOrEmpty
            $read = Get-UiProfile -Name 'Client de test'

            $read.MicrosoftApps.Teams | Should -BeTrue
            $read.WindowsUpdate | Should -BeFalse
            $read.Agents.RmmUrl | Should -Be 'https://app.ninjarmm.example/agent.msi'
            $read.LocalAccounts[0].Name | Should -Be 'accueil'
            $read.LocalAccounts[0].CannotChangePassword | Should -BeTrue
            $read.NetworkDrives[0].Path | Should -Be '\\srv\Commun'
            $read.Printers[0].DriverName | Should -Be 'Marque PCL6'
            $read.Domain.Account | Should -Be 'adm-jonction'
            ($read | ConvertTo-Json -Depth 6) | Should -Not -Match '(?i)"password"\s*:'
        }
    }

    It 'session et domaine d''un profil sans mot de passe : lancement bloqué, page signalée' {
        InModuleScope FastPrepare.UI {
            $problems = @(Get-UiProblem)
            ($problems | ForEach-Object { $_.Message }) -join ' | ' | Should -Match 'mot de passe à saisir'
            ($problems | ForEach-Object { $_.PageId }) | Should -Contain 'comptes'
            Update-WizardNavigation -Problem $problems
            [string]$script:Pages['comptes'].Nav.Content | Should -Match '⚠'
        }
    }

    It 'Nouveau : les étapes reviennent à leur état de départ' {
        InModuleScope FastPrepare.UI {
            Set-UiProfile -CompanyProfile $script:DefaultProfile
            $read = Get-UiProfile
            @($read.LocalAccounts).Count | Should -Be 0
            @($read.NetworkDrives).Count | Should -Be 0
            $read.Domain.Domain | Should -BeNullOrEmpty
            ($read | ConvertTo-Json -Depth 6) | Should -Be ($script:DefaultProfile | ConvertTo-Json -Depth 6)
        }
    }

    It 'relevé du poste : l''affichage ne lève pas d''erreur' {
        InModuleScope FastPrepare.UI -Parameters @{ Snapshot = $script:BuildSnapshot } {
            param($Snapshot)
            { Complete-MachineView -Snapshot $Snapshot } | Should -Not -Throw
        }
    }

    AfterAll {
        if ($script:OnWindows) {
            InModuleScope FastPrepare.UI {
                foreach ($section in (Get-UiSection)) {
                    try { Invoke-UiSectionCallback -Section $section -Name Dispose | Out-Null } catch { Write-Verbose $_.Exception.Message }
                }
            }
        }
    }
}
