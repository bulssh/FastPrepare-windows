<#
    Étape « jonction au domaine » (itération 18) et son test préalable : plan, exécution réelle
    avec des simulacres (le poste n'est jamais joint), absence du mot de passe dans le journal.
#>
BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core, Infrastructure, Application
    $m = @{ ModuleName = 'FastPrepare.Application' }
    $secretText = 'Fictif-Kd4#2026'

    function New-TestSecret([string]$Text) {
        $secret = New-Object System.Security.SecureString
        foreach ($char in $Text.ToCharArray()) { $secret.AppendChar($char) }
        return $secret
    }

    function New-DomainSelection {
        $selection = New-Selection
        $selection.DomainJoin.Domain = 'entreprise.local'
        $selection.DomainJoin.Account = 'adm-jonction'
        $selection.DomainJoin.Password = New-TestSecret $secretText
        return $selection
    }

    function Get-LogText($Context) { [System.IO.File]::ReadAllText($Context.Log.FilePath) }
}

Describe 'Plan — jonction au domaine' {
    It 'domaine vide : aucune action' {
        $context = New-TestContext -Folder $TestDrive
        $plan = New-ExecutionPlan -Selection (New-Selection) -Snapshot (New-TestSnapshot) -Context $context
        @($plan.Actions | Where-Object StepId -EQ 'join-domain') | Should -BeNullOrEmpty
    }

    It 'toujours la dernière action (rang 18), libellé sans mot de passe' {
        $context = New-TestContext -Folder $TestDrive
        $selection = New-DomainSelection
        $selection.NewLocalAccounts.Items = @(New-LocalAccountRequest -Name 'jdupont' -Password (New-TestSecret $secretText))
        $selection.NetworkDrives.Items = @(New-NetworkDriveRequest -Letter 'P' -Path '\\srv\Commun')
        $plan = New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $context
        $action = $plan.Actions[-1]
        $action.StepId | Should -Be 'join-domain'
        $action.StepNumber | Should -Be 18
        (Get-StepOrder)[-1] | Should -Be 'join-domain'
        $action.Label | Should -Be 'Jonction au domaine : Add-Computer -DomainName entreprise.local (compte entreprise.local\adm-jonction) — sans redémarrage, effective au redémarrage final'
        $action.Parameters.Password | Should -BeOfType [System.Security.SecureString]
        $action.Label | Should -Not -Match ([regex]::Escape($secretText))
    }

    It 'mot de passe absent : plan refusé' {
        $context = New-TestContext -Folder $TestDrive
        $selection = New-DomainSelection
        $selection.DomainJoin.Password = $null
        { New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $context } | Should -Throw '*Jonction au domaine : mot de passe du compte vide*'
    }
}

Describe 'Mode réel — jonction au domaine' {
    BeforeEach {
        Mock @m Get-ComputerDomainState { [pscustomobject]@{ PartOfDomain = $false; Domain = 'WORKGROUP' } }
        Mock @m Join-ComputerToDomain { }
        $context = New-TestContext -Folder $TestDrive -Mode Real
    }

    It 'joint le poste, signale le redémarrage à faire, ne journalise jamais le mot de passe' {
        $plan = New-ExecutionPlan -Selection (New-DomainSelection) -Snapshot (New-TestSnapshot) -Context $context
        $results = Invoke-ExecutionPlan -Plan $plan -Context $context
        $results[-1].Outcome | Should -Be 'Succeeded'
        Should -Invoke @m Join-ComputerToDomain -Times 1 -ParameterFilter {
            $Domain -eq 'entreprise.local' -and $QualifiedAccount -eq 'entreprise.local\adm-jonction' -and $Password -is [System.Security.SecureString]
        }
        $text = Get-LogText $context
        $text | Should -Match 'Poste joint à entreprise\.local'
        $text | Should -Not -Match ([regex]::Escape($secretText))
    }

    It 'poste déjà membre du même domaine : rien à faire, succès' {
        Mock @m Get-ComputerDomainState { [pscustomobject]@{ PartOfDomain = $true; Domain = 'ENTREPRISE.LOCAL' } }
        $plan = New-ExecutionPlan -Selection (New-DomainSelection) -Snapshot (New-TestSnapshot) -Context $context
        $results = Invoke-ExecutionPlan -Plan $plan -Context $context
        $results[-1].Outcome | Should -Be 'Succeeded'
        Should -Invoke @m Join-ComputerToDomain -Times 0
    }

    It 'poste membre d''un autre domaine : échec, poste non modifié' {
        Mock @m Get-ComputerDomainState { [pscustomobject]@{ PartOfDomain = $true; Domain = 'autre.local' } }
        $plan = New-ExecutionPlan -Selection (New-DomainSelection) -Snapshot (New-TestSnapshot) -Context $context
        $results = Invoke-ExecutionPlan -Plan $plan -Context $context
        $results[-1].Outcome | Should -Be 'Failed'
        $results[-1].Error | Should -Match 'autre domaine'
        Should -Invoke @m Join-ComputerToDomain -Times 0
    }

    It 'refus du domaine : action en échec, message journalisé sans le mot de passe' {
        Mock @m Join-ComputerToDomain { throw 'Le nom d''utilisateur ou le mot de passe est incorrect.' }
        $plan = New-ExecutionPlan -Selection (New-DomainSelection) -Snapshot (New-TestSnapshot) -Context $context
        $results = Invoke-ExecutionPlan -Plan $plan -Context $context
        $results[-1].Outcome | Should -Be 'Failed'
        Get-LogText $context | Should -Not -Match ([regex]::Escape($secretText))
    }

    It 'mot de passe libéré avant l''exécution : échec explicite, aucune jonction' {
        $selection = New-DomainSelection
        $plan = New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $context
        Clear-SelectionSecret -Selection $selection
        $results = Invoke-ExecutionPlan -Plan $plan -Context $context
        $results[-1].Outcome | Should -Be 'Failed'
        Should -Invoke @m Join-ComputerToDomain -Times 0
    }
}

Describe 'Test-DomainJoinSetting' {
    BeforeEach {
        Mock @m Get-ComputerDomainState { [pscustomobject]@{ PartOfDomain = $false; Domain = 'WORKGROUP' } }
        Mock @m Find-DomainController { @('dc1.entreprise.local', 'dc2.entreprise.local') }
        Mock @m Test-DomainCredential { }
        $password = New-TestSecret $secretText
    }

    It 'tout répond : succès, compte qualifié transmis, mot de passe absent des lignes' {
        $result = Test-DomainJoinSetting -Domain 'entreprise.local' -Account 'adm-jonction' -Password $password
        $result.Succeeded | Should -BeTrue
        ($result.Lines | ForEach-Object { $_.Text }) -join ' ' | Should -Match 'dc1\.entreprise\.local'
        ($result.Lines | ForEach-Object { $_.Text }) -join ' ' | Should -Not -Match ([regex]::Escape($secretText))
        Should -Invoke @m Test-DomainCredential -Times 1 -ParameterFilter { $Domain -eq 'entreprise.local' -and $User -eq 'adm-jonction' -and $UserDomain -eq 'entreprise.local' }
    }

    It 'saisie incomplète : échec sans interroger le réseau' {
        $result = Test-DomainJoinSetting -Domain 'entreprise.local' -Account '' -Password $password
        $result.Succeeded | Should -BeFalse
        Should -Invoke @m Find-DomainController -Times 0
    }

    It 'domaine introuvable : échec, le compte n''est pas essayé' {
        Mock @m Find-DomainController { throw 'DNS name does not exist' }
        $result = Test-DomainJoinSetting -Domain 'entreprise.local' -Account 'adm' -Password $password
        $result.Succeeded | Should -BeFalse
        $result.Lines[-1].Text | Should -Match 'Domaine introuvable'
        Should -Invoke @m Test-DomainCredential -Times 0
    }

    It 'compte refusé : échec' {
        Mock @m Test-DomainCredential { throw 'compte ou mot de passe refusé par le domaine.' }
        $result = Test-DomainJoinSetting -Domain 'entreprise.local' -Account 'adm' -Password $password
        $result.Succeeded | Should -BeFalse
        $result.Lines[-1].Text | Should -Match 'refusé'
    }

    It 'poste déjà membre d''un autre domaine : échec immédiat' {
        Mock @m Get-ComputerDomainState { [pscustomobject]@{ PartOfDomain = $true; Domain = 'autre.local' } }
        $result = Test-DomainJoinSetting -Domain 'entreprise.local' -Account 'adm' -Password $password
        $result.Succeeded | Should -BeFalse
        Should -Invoke @m Find-DomainController -Times 0
    }
}
