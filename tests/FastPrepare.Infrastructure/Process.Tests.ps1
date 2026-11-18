BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Infrastructure
    $cmd = Join-Path ([Environment]::GetFolderPath('System')) 'cmd.exe'
}

Describe 'Invoke-ExternalProcess (commandes inoffensives)' {
    It 'code 0 : succès' {
        $result = Invoke-ExternalProcess -FilePath $cmd -ArgumentList '/c exit 0' -TimeoutMinutes 1
        $result.ExitCode | Should -Be 0
        $result.RebootRequired | Should -BeFalse
    }
    It 'code 3010 : succès avec redémarrage nécessaire' {
        (Invoke-ExternalProcess -FilePath $cmd -ArgumentList '/c exit 3010' -TimeoutMinutes 1).RebootRequired | Should -BeTrue
    }
    It 'code inattendu : erreur avec la signification connue' {
        { Invoke-ExternalProcess -FilePath $cmd -ArgumentList '/c exit 1603' -TimeoutMinutes 1 } | Should -Throw '*code de sortie 1603 (erreur fatale*'
    }
    It 'sens propre à l''outil (-ExitCodeMessage), prioritaire sur les codes MSI' {
        { Invoke-ExternalProcess -FilePath $cmd -ArgumentList '/c exit 16386' -ExitCodeMessage @{ 16386 = 'fichier de référence non pris en charge' } -TimeoutMinutes 1 } |
            Should -Throw '*code de sortie 16386 (fichier de référence non pris en charge)'
        { Invoke-ExternalProcess -FilePath $cmd -ArgumentList '/c exit 1603' -ExitCodeMessage @{ 1603 = 'sens de l''outil' } -TimeoutMinutes 1 } |
            Should -Throw '*code de sortie 1603 (sens de l''outil)'
    }
    It 'code inconnu, même avec une table : pas de détail' {
        { Invoke-ExternalProcess -FilePath $cmd -ArgumentList '/c exit 7' -ExitCodeMessage @{ 16386 = 'x' } -TimeoutMinutes 1 } | Should -Throw '*code de sortie 7'
    }
    It 'codes de succès propres à l''outil (-SuccessExitCode)' {
        (Invoke-ExternalProcess -FilePath $cmd -ArgumentList '/c exit 5' -SuccessExitCode 0, 5 -TimeoutMinutes 1).ExitCode | Should -Be 5
    }
    It 'capture la sortie standard' {
        (Invoke-ExternalProcess -FilePath $cmd -ArgumentList '/c echo bonjour' -CaptureOutput -TimeoutMinutes 1).Output | Should -Match 'bonjour'
    }
    It 'exécutable introuvable : erreur explicite' {
        { Invoke-ExternalProcess -FilePath 'C:\absent\inexistant.exe' -TimeoutMinutes 1 } | Should -Throw '*Lancement impossible*'
    }
    It 'journalise la commande et le code de sortie (DEBUG, fichier seulement)' {
        $log = New-RunLog -Folder (Join-Path $TestDrive 'logs') -FallbackFolder (Join-Path $TestDrive 'r') -HostName 'PC' -Stamp 'p'
        [void](Invoke-ExternalProcess -FilePath $cmd -ArgumentList '/c exit 0' -TimeoutMinutes 1 -Log $log)
        $text = Get-Content -LiteralPath $log.FilePath -Raw -Encoding UTF8
        $text | Should -Match '\[DEBUG\] Commande : ".*cmd\.exe" /c exit 0'
        $text | Should -Match '\[DEBUG\] Code de sortie 0'
        @(Receive-RunLogEntry -Log $log).Count | Should -Be 0
    }
}

Describe 'Invoke-ExternalProcess : ligne de commande masquée (audit SEC-003)' {
    It '-DisplayName : ni chemin ni arguments au journal ni dans l''erreur' {
        $log = New-RunLog -Folder (Join-Path $TestDrive 'logs') -FallbackFolder (Join-Path $TestDrive 'r') -HostName 'PC' -Stamp 'm'
        $message = try { [void](Invoke-ExternalProcess -FilePath $cmd -ArgumentList '/c exit 1603 & rem JETON-SECRET' -DisplayName 'agent.exe' -TimeoutMinutes 1 -Log $log); '' } catch { $_.Exception.Message }
        $message | Should -Be '« agent.exe » : code de sortie 1603 (erreur fatale pendant l''installation)'
        $text = Get-Content -LiteralPath $log.FilePath -Raw -Encoding UTF8
        $text | Should -Match 'Commande : agent\.exe \(ligne de commande masquée\)'
        $text | Should -Not -Match 'JETON-SECRET|cmd\.exe'
    }
}

Describe 'Invoke-ExternalProcess : délai dépassé (DEC33, audit BUG-002)' {
    It 'par défaut : le processus et ses enfants sont arrêtés, puis erreur' {
        $message = try { [void](Invoke-ExternalProcess -FilePath $cmd -ArgumentList '/c ping -n 30 127.0.0.1 >nul' -TimeoutMinutes 0.03); '' } catch { $_.Exception.Message }
        $found = $message -match 'dépasse le délai de .* min : arrêté avec ses processus enfants \(PID (\d+)\)'
        $found | Should -BeTrue -Because $message
        $processId = [int]$Matches[1]
        Get-Process -Id $processId -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        @(Get-CimInstance -ClassName Win32_Process -Filter "ParentProcessId=$processId" -ErrorAction SilentlyContinue).Count | Should -Be 0
    }
    It '-OnTimeout Wait : rien n''est arrêté, l''attente est journalisée et le code de sortie lu' {
        $log = New-RunLog -Folder (Join-Path $TestDrive 'logs') -FallbackFolder (Join-Path $TestDrive 'r') -HostName 'PC' -Stamp 'w'
        $result = Invoke-ExternalProcess -FilePath $cmd -ArgumentList '/c ping -n 4 127.0.0.1 >nul & exit 0' -TimeoutMinutes 0.01 -OnTimeout Wait -Log $log
        $result.ExitCode | Should -Be 0
        ((Receive-RunLogEntry -Log $log) | Where-Object Level -EQ 'ATTN').Line -join "`n" | Should -Match 'pas d''arrêt.*attend sa fin'
    }
}

Describe 'Get-SystemExecutablePath' {
    It 'chemin absolu dans System32' {
        Get-SystemExecutablePath -Name 'powercfg.exe' | Should -Be (Join-Path ([Environment]::GetFolderPath('System')) 'powercfg.exe')
    }
}
