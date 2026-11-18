BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core, Infrastructure, Application
}

Describe 'Relevé du poste en arrière-plan' -Tag 'Integration' {
    It 'relève le poste courant dans un runspace et exporte l''inventaire' {
        $config = Get-TestConfig
        $config.Logging.Folder = Join-Path $TestDrive 'logs'
        $context = New-AppContext -Root (Get-RepoRoot) -Config $config -RequestedMode Simulation

        $work = Start-MachineSnapshot -Context $context
        $deadline = (Get-Date).AddSeconds(120)
        while (-not (Test-BackgroundWorkCompleted -Work $work)) {
            if ((Get-Date) -gt $deadline) { throw 'Relevé trop long' }
            Start-Sleep -Milliseconds 100
        }
        $snapshot = @(Receive-BackgroundWork -Work $work) | Select-Object -Last 1

        $snapshot.PSObject.TypeNames | Should -Contain 'FastPrepare.MachineSnapshot'
        $snapshot.Identity.HostName | Should -Be $env:COMPUTERNAME
        $snapshot.InventoryText | Should -Match '^N/S'
        $snapshot.InventoryExport.Path | Should -Exist
        $lines = @(Receive-RunLogEntry -Log $context.Log).Line
        ($lines -join "`n") | Should -Match 'logiciels détectés'
    }
}

Describe 'Logiciels installés pour une seule session (audit SEC-001)' {
    It 'entrée HKCU : jamais silencieuse, désinstallation avec fenêtre ; entrée machine inchangée' {
        $m = @{ ModuleName = 'FastPrepare.Application' }
        Mock @m Get-UninstallEntry {
            [pscustomobject]@{ PSPath = 'Microsoft.PowerShell.Core\Registry::HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Outil'; DisplayName = 'Outil perso'; DisplayVersion = '1'; QuietUninstallString = '"C:\Users\t\AppData\Local\Outil\uninstall.exe" /S' }
            [pscustomobject]@{ PSPath = 'Microsoft.PowerShell.Core\Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Machine'; DisplayName = 'Outil machine'; DisplayVersion = '2'; QuietUninstallString = '"C:\Program Files\Outil\uninstall.exe" /S' }
        }
        Mock @m Get-ExecutableProbe { $null }
        $view = InModuleScope FastPrepare.Application { @(Get-InstalledSoftwareView) }
        $user = $view | Where-Object Name -EQ 'Outil perso'
        $user.Silent | Should -BeFalse
        $user.UserScope | Should -BeTrue
        $user.Method | Should -Match 'une seule session'
        $machine = $view | Where-Object Name -EQ 'Outil machine'
        $machine.Silent | Should -BeTrue
        $machine.UserScope | Should -BeFalse
    }
}

Describe 'Get-BackgroundModulePath' {
    It 'les trois modules non graphiques, sans FastPrepare.UI, et ils existent' {
        $paths = Get-BackgroundModulePath -Root (Get-RepoRoot)
        @($paths).Count | Should -Be 3
        ($paths -join ';') | Should -Not -Match 'FastPrepare\.UI'
        foreach ($path in $paths) { $path | Should -Exist }
    }
}
