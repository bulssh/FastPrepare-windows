<#
    Étapes « agent RMM » et « antivirus » par lien (itération 16) : plan, puis exécution réelle
    avec des simulacres (rien n'est téléchargé ni lancé). Liens fictifs.
#>
BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core, Infrastructure, Application
    $m = @{ ModuleName = 'FastPrepare.Application' }
    $rmmUrl = 'https://app.ninjarmm.example/agent/installer/0000/client-5.9.msi'
    $avUrl = 'https://cloud.gravityzone.example/Packages/BSTWIN/0/setupdownloader_%5BaHR0cHM6Ly9leGVtcGxl%5D.exe'
}

Describe 'Plan — agent RMM et antivirus' {
    It 'liens vides : aucune action' {
        $context = New-TestContext -Folder $TestDrive
        $plan = New-ExecutionPlan -Selection (New-Selection) -Snapshot (New-TestSnapshot) -Context $context
        @($plan.Actions | Where-Object { $_.StepId -in @('install-rmm-agent', 'install-antivirus') }) | Should -BeNullOrEmpty
    }

    It 'deux liens : RMM (rang 14) puis antivirus (rang 15), commande silencieuse dans le libellé' {
        $context = New-TestContext -Folder $TestDrive
        $selection = New-Selection
        $selection.Agents.RmmUrl = $rmmUrl
        $selection.Agents.AntivirusUrl = $avUrl
        $plan = New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $context
        $rmm = @($plan.Actions | Where-Object StepId -EQ 'install-rmm-agent')
        $av = @($plan.Actions | Where-Object StepId -EQ 'install-antivirus')
        $rmm.Count | Should -Be 1
        $av.Count | Should -Be 1
        $rmm[0].StepNumber | Should -Be 14
        $av[0].StepNumber | Should -Be 15
        $rmm[0].Label | Should -Match 'Agent RMM — NinjaOne : .*msiexec /i client-5\.9\.msi /qn /norestart'
        $av[0].Label | Should -Match 'Antivirus — Bitdefender : .*setupdownloader_\[aHR0cHM6Ly9leGVtcGxl\]\.exe /bdparams /silent'
    }

    It 'lien refusé : plan non construit, motif explicite' {
        $context = New-TestContext -Folder $TestDrive
        $selection = New-Selection
        $selection.Agents.AntivirusUrl = 'https://fichiers.example/setup.exe'
        { New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $context } | Should -Throw '*Antivirus : installateur non reconnu*'
    }
}

Describe 'Mode réel — agent RMM et antivirus' {
    BeforeEach {
        Mock @m Save-RemoteInstaller { Join-Path $Folder $FileName }
        Mock @m Assert-TrustedExecutable { }
        Mock @m Get-SystemExecutablePath { "C:\Windows\System32\$Name" }
        Mock @m Invoke-ExternalProcess { [pscustomobject]@{ ExitCode = 0; RebootRequired = $false } }
        $context = New-TestContext -Folder $TestDrive -Mode Real
        $selection = New-Selection
    }

    It 'NinjaOne : téléchargé, signature vérifiée, msiexec /i … /qn /norestart' {
        $selection.Agents.RmmUrl = $rmmUrl
        $plan = New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $context
        $results = Invoke-ExecutionPlan -Plan $plan -Context $context
        $results[-1].Outcome | Should -Be 'Succeeded'
        Should -Invoke @m Save-RemoteInstaller -Times 1 -ParameterFilter { $Url -eq $rmmUrl -and $FileName -eq 'client-5.9.msi' }
        Should -Invoke @m Assert-TrustedExecutable -Times 1
        Should -Invoke @m Invoke-ExternalProcess -Times 1 -ParameterFilter {
            $FilePath -like '*msiexec.exe' -and $ArgumentList -match '^/i ".*client-5\.9\.msi" /qn /norestart$'
        }
    }

    It 'Bitdefender : exécutable lancé sous son nom d''origine avec /bdparams /silent' {
        $selection.Agents.AntivirusUrl = $avUrl
        $plan = New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $context
        $results = Invoke-ExecutionPlan -Plan $plan -Context $context
        $results[-1].Outcome | Should -Be 'Succeeded'
        Should -Invoke @m Invoke-ExternalProcess -Times 1 -ParameterFilter {
            $FilePath -like '*setupdownloader_`[aHR0cHM6Ly9leGVtcGxl`].exe' -and $ArgumentList -eq '/bdparams /silent'
        }
    }

    It 'signature non valide : installateur jamais lancé, action en échec' {
        Mock @m Assert-TrustedExecutable { throw 'Signature de client-5.9.msi non valide (NotSigned) : exécutable non lancé.' }
        $selection.Agents.RmmUrl = $rmmUrl
        $plan = New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $context
        $results = Invoke-ExecutionPlan -Plan $plan -Context $context
        $results[-1].Outcome | Should -Be 'Failed'
        $results[-1].Error | Should -Match 'non valide'
        Should -Invoke @m Invoke-ExternalProcess -Times 0
    }

    It 'échec du RMM : l''antivirus est tout de même installé' {
        Mock @m Save-RemoteInstaller { throw 'Lien injoignable' } -ParameterFilter { $Url -eq $rmmUrl }
        $selection.Agents.RmmUrl = $rmmUrl
        $selection.Agents.AntivirusUrl = $avUrl
        $plan = New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $context
        $results = Invoke-ExecutionPlan -Plan $plan -Context $context
        ($results | ForEach-Object { $_.Outcome }) -join ',' | Should -Be 'Failed,Succeeded'
    }
}
