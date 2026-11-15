<#
    Étape « Création d'une session locale » (itération 8) : plan, exécution réelle avec des
    simulacres, et absence du mot de passe dans le plan comme dans le fichier journal.
#>
BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core, Infrastructure, Application
    $m = @{ ModuleName = 'FastPrepare.Application' }
    # Mot de passe fictif, assez particulier pour être cherché dans le journal.
    $secretText = 'Fictif-Zq7#2026'

    function New-TestSecret([string]$Text) {
        $secret = New-Object System.Security.SecureString
        foreach ($char in $Text.ToCharArray()) { $secret.AppendChar($char) }
        return $secret
    }

    function New-AccountSelection {
        $selection = New-Selection
        $selection.NewLocalAccounts.Items = @(New-LocalAccountRequest -Name 'jdupont' -FullName 'Jean Dupont' -Description 'Comptabilité' -Password (New-TestSecret $secretText) -Administrator -MustChangePassword)
        return $selection
    }

    function Get-LogText($Context) { [System.IO.File]::ReadAllText($Context.Log.FilePath) }
}

Describe 'Plan — création d''une session locale' {
    It 'aucune session demandée : aucune action' {
        $context = New-TestContext -Folder $TestDrive
        $plan = New-ExecutionPlan -Selection (New-Selection) -Snapshot (New-TestSnapshot) -Context $context
        @($plan.Actions | Where-Object StepId -EQ 'create-local-account') | Should -BeNullOrEmpty
    }

    It 'une action (rang 13, section 11), libellé sans mot de passe' {
        $context = New-TestContext -Folder $TestDrive
        $selection = New-AccountSelection
        $plan = New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $context
        $action = $plan.Actions[-1]
        $action.StepId | Should -Be 'create-local-account'
        $action.StepNumber | Should -Be 13
        $action.Section | Should -Be 11
        $action.Label | Should -Be "Session locale : New-LocalUser 'jdupont' (Jean Dupont) · administrateur du poste · mot de passe à changer à la première ouverture"
        $action.Parameters.Password | Should -BeOfType [System.Security.SecureString]
        $action.Parameters.ComputerNames | Should -Be @('PC-TEST')
        ($action.Label + ($action.Details -join ' ')) | Should -Not -Match ([regex]::Escape($secretText))
    }

    It 'nom déjà pris sur le poste : plan refusé' {
        $context = New-TestContext -Folder $TestDrive
        $selection = New-AccountSelection
        $selection.NewLocalAccounts.Items[0].Name = 'technicien'
        { New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $context } | Should -Throw '*existe déjà*'
    }

    It 'plusieurs sessions : une action par session, dans l''ordre de saisie' {
        $context = New-TestContext -Folder $TestDrive
        $selection = New-AccountSelection
        $selection.NewLocalAccounts.Items += New-LocalAccountRequest -Name 'accueil' -Password (New-TestSecret $secretText) -PasswordNeverExpires -CannotChangePassword -Disabled
        $plan = New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $context
        $actions = @($plan.Actions | Where-Object StepId -EQ 'create-local-account')
        $actions.Count | Should -Be 2
        $actions[0].Parameters.Name | Should -Be 'jdupont'
        $actions[1].Parameters.Name | Should -Be 'accueil'
        $actions[1].Label | Should -Match 'non modifiable par l''utilisateur · compte désactivé'
        $actions[1].Parameters.Disabled | Should -BeTrue
        $actions[1].Parameters.CannotChangePassword | Should -BeTrue
    }

    It 'simulation : le journal décrit la session, jamais le mot de passe' {
        $context = New-TestContext -Folder $TestDrive -Mode Simulation
        $plan = New-ExecutionPlan -Selection (New-AccountSelection) -Snapshot (New-TestSnapshot) -Context $context
        [void](Invoke-ExecutionPlan -Plan $plan -Context $context)
        $text = Get-LogText $context
        $text | Should -Match "\[ETAPE 13/18 · section 11\] Session locale : New-LocalUser 'jdupont'"
        $text | Should -Not -Match ([regex]::Escape($secretText))
    }
}

Describe 'Mode réel — création d''une session locale' {
    BeforeEach {
        Mock @m Get-LocalAccount { @([pscustomobject]@{ Name = 'Administrateur'; Sid = 'S-1-5-21-1-2-3-500'; ProfilePath = $null }) }
        Mock @m New-LocalAccount { [pscustomobject]@{ Name = $Name; Sid = 'S-1-5-21-1-2-3-1005' } }
        $context = New-TestContext -Folder $TestDrive -Mode Real
    }

    It 'crée la session avec ses groupes et ses options, sans jamais journaliser le mot de passe' {
        $plan = New-ExecutionPlan -Selection (New-AccountSelection) -Snapshot (New-TestSnapshot) -Context $context
        $results = Invoke-ExecutionPlan -Plan $plan -Context $context
        $results[-1].Outcome | Should -Be 'Succeeded'
        Should -Invoke @m New-LocalAccount -Times 1 -ParameterFilter {
            $Name -eq 'jdupont' -and $FullName -eq 'Jean Dupont' -and $Description -eq 'Comptabilité' -and -not $Disabled -and -not $CannotChangePassword -and $Password -is [System.Security.SecureString] -and
            ($GroupSid -join ',') -eq 'S-1-5-32-545,S-1-5-32-544' -and $MustChangePassword -and -not $PasswordNeverExpires
        }
        $text = Get-LogText $context
        $text | Should -Match "Session 'jdupont' créée"
        $text | Should -Not -Match ([regex]::Escape($secretText))
    }

    It 'session apparue entre-temps sur le poste : échec, rien n''est créé' {
        Mock @m Get-LocalAccount { @([pscustomobject]@{ Name = 'JDUPONT'; Sid = 'S-1-5-21-1-2-3-1006'; ProfilePath = $null }) }
        $plan = New-ExecutionPlan -Selection (New-AccountSelection) -Snapshot (New-TestSnapshot) -Context $context
        $results = Invoke-ExecutionPlan -Plan $plan -Context $context
        $results[-1].Outcome | Should -Be 'Failed'
        $results[-1].Error | Should -Match 'existe déjà'
        Should -Invoke @m New-LocalAccount -Times 0
    }

    It 'refus de Windows (politique de mots de passe) : action en échec, message journalisé sans le mot de passe' {
        Mock @m New-LocalAccount { throw 'Le mot de passe ne répond pas aux exigences de la stratégie.' }
        $plan = New-ExecutionPlan -Selection (New-AccountSelection) -Snapshot (New-TestSnapshot) -Context $context
        $results = Invoke-ExecutionPlan -Plan $plan -Context $context
        $results[-1].Outcome | Should -Be 'Failed'
        $text = Get-LogText $context
        $text | Should -Match 'exigences de la stratégie'
        $text | Should -Not -Match ([regex]::Escape($secretText))
    }

    It 'mot de passe libéré avant l''exécution : échec explicite, rien n''est créé' {
        $selection = New-AccountSelection
        $plan = New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $context
        Clear-SelectionSecret -Selection $selection
        $results = Invoke-ExecutionPlan -Plan $plan -Context $context
        $results[-1].Outcome | Should -Be 'Failed'
        $results[-1].Error | Should -Match 'déjà libéré'
        Should -Invoke @m New-LocalAccount -Times 0
    }
}
