BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core
}

Describe 'Get-WizardPage (parcours par étapes)' {
    It 'cinq étapes de saisie, le récapitulatif, puis le catalogue et l''analyse de disque hors parcours' {
        $pages = @(Get-WizardPage)
        ($pages | ForEach-Object { $_.Id }) -join ',' | Should -Be 'poste,nettoyage,comptes,installations,systeme,recap,catalogue,disque'
        @($pages | Where-Object { $_.Kind -eq 'Step' }).Count | Should -Be 5
        @($pages | Where-Object { $_.Kind -eq 'Review' }).Count | Should -Be 1
    }

    It 'les pages du parcours sont numérotées de 1 à 6, le catalogue ne l''est pas' {
        $pages = @(Get-WizardPage)
        ($pages | Where-Object { Test-WizardPageOnPath -Kind $_.Kind } | ForEach-Object { $_.Number }) -join ',' | Should -Be '1,2,3,4,5,6'
        ($pages | Where-Object { $_.Id -eq 'catalogue' }).Number | Should -Be 0
        ($pages | Where-Object { $_.Id -eq 'disque' }).Number | Should -Be 0
        ($pages | Where-Object { $_.Id -eq 'disque' }).Kind | Should -Be 'Tool'
    }

    It 'chaque page a un titre et un sous-titre' {
        foreach ($page in (Get-WizardPage)) {
            $page.Title | Should -Not -BeNullOrEmpty
            $page.Subtitle | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Get-WizardNeighbor' {
    It '<From> → <Direction> = <Expected>' -ForEach @(
        @{ From = 'poste'; Direction = 'Next'; Expected = 'nettoyage' }
        @{ From = 'systeme'; Direction = 'Next'; Expected = 'recap' }
        @{ From = 'recap'; Direction = 'Previous'; Expected = 'systeme' }
        @{ From = 'nettoyage'; Direction = 'Previous'; Expected = 'poste' }
    ) {
        Get-WizardNeighbor -PageId $From -Direction $Direction | Should -Be $Expected
    }

    It '<From> → <Direction> : aucune page' -ForEach @(
        @{ From = 'poste'; Direction = 'Previous' }
        @{ From = 'recap'; Direction = 'Next' }
        @{ From = 'catalogue'; Direction = 'Next' }
        @{ From = 'catalogue'; Direction = 'Previous' }
        @{ From = 'disque'; Direction = 'Next' }
        @{ From = 'disque'; Direction = 'Previous' }
        @{ From = 'inconnue'; Direction = 'Next' }
    ) {
        Get-WizardNeighbor -PageId $From -Direction $Direction | Should -BeNullOrEmpty
    }
}

Describe 'Get-WizardNextLabel' {
    It 'Suivant sur les étapes intermédiaires' {
        Get-WizardNextLabel -PageId 'poste' | Should -Be 'Suivant →'
    }
    It 'Vérifier et lancer sur la dernière étape de saisie' {
        Get-WizardNextLabel -PageId 'systeme' | Should -Be 'Vérifier et lancer →'
    }
    It 'aucun bouton sur le récapitulatif ni sur le catalogue' {
        Get-WizardNextLabel -PageId 'recap' | Should -BeNullOrEmpty
        Get-WizardNextLabel -PageId 'catalogue' | Should -BeNullOrEmpty
    }
}
