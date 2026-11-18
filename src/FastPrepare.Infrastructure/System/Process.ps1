<#
    Point de passage unique vers un processus externe (règle §6 du plan d'architecture).
    Exécutable et arguments toujours séparés : jamais d'Invoke-Expression, jamais de chaîne shell.
    La commande effective, le code de sortie et la durée sont journalisés (niveau DEBUG).
#>

# Codes de sortie Windows Installer connus, traduits dans les messages d'erreur.
$script:KnownExitCodes = @{
    1602 = 'annulé par l''utilisateur'
    1603 = 'erreur fatale pendant l''installation'
    1618 = 'une autre installation est déjà en cours'
    1619 = 'paquet d''installation introuvable'
    1641 = 'succès, redémarrage lancé par l''installateur'
    3010 = 'succès, redémarrage nécessaire'
}

function Invoke-ExternalProcess {
    <#
        Lance -FilePath avec -ArgumentList et attend sa fin (au plus -TimeoutMinutes).
        Délai dépassé (DEC33, audit BUG-002) : jamais de processus laissé en cours pendant que
        l'exécution continue.
          -OnTimeout Kill (défaut) : le processus et ses enfants sont arrêtés, puis erreur.
          -OnTimeout Wait : rien n'est arrêté (mise à jour constructeur : BIOS possible) ; l'outil
                            l'écrit au journal et attend la fin, les étapes suivantes aussi.
        Renvoie { ExitCode, RebootRequired, Duration, Output }.
        Erreur si le code de sortie n'est ni dans -SuccessExitCode ni dans -RebootExitCode.
        -CaptureOutput : récupère la sortie standard (fenêtre masquée).
        -Interactive   : la fenêtre du programme est affichée (assistant à suivre par le technicien).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [AllowEmptyString()][string]$ArgumentList = '',
        [string]$WorkingDirectory,
        [double]$TimeoutMinutes = 60,
        [ValidateSet('Kill', 'Wait')][string]$OnTimeout = 'Kill',
        [int[]]$SuccessExitCode = @(0),
        [int[]]$RebootExitCode = @(3010, 1641),
        [switch]$CaptureOutput,
        [switch]$Interactive,
        # Sens des codes propres à l'outil (clé : code entier), prioritaire sur les codes MSI connus.
        [hashtable]$ExitCodeMessage = @{},
        $Log
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = $ArgumentList
    if ($WorkingDirectory) { $startInfo.WorkingDirectory = $WorkingDirectory }
    if ($Interactive) {
        $startInfo.UseShellExecute = $true
    } else {
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        if ($CaptureOutput) {
            $startInfo.RedirectStandardOutput = $true
            $startInfo.RedirectStandardError = $true
            $startInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        }
    }

    if ($Log) { Write-RunLog -Log $Log -Level DEBUG -Message ('Commande : "{0}" {1}' -f $FilePath, $ArgumentList) }
    $started = Get-Date
    try {
        $process = [System.Diagnostics.Process]::Start($startInfo)
    } catch {
        throw ('Lancement impossible de « {0} » : {1}' -f $FilePath, $_.Exception.Message)
    }

    try {
        $outputTask = $null
        $errorTask = $null
        if ($CaptureOutput -and -not $Interactive) {
            # Lecture asynchrone : un tampon plein bloquerait le processus.
            $outputTask = $process.StandardOutput.ReadToEndAsync()
            $errorTask = $process.StandardError.ReadToEndAsync()
        }
        $name = [System.IO.Path]::GetFileName($FilePath)
        if (-not $process.WaitForExit([int][Math]::Min([int]::MaxValue, $TimeoutMinutes * 60000))) {
            if ($OnTimeout -eq 'Kill') {
                Stop-ProcessTree -Id $process.Id
                [void]$process.WaitForExit(30000)
                throw ('« {0} » dépasse le délai de {1} min : arrêté avec ses processus enfants (PID {2})' -f $name, $TimeoutMinutes, $process.Id)
            }
            if ($Log) { Write-RunLog -Log $Log -Level ATTN -Message ('« {0} » dépasse le délai de {1} min : pas d''arrêt (mise à jour du BIOS possible), l''outil attend sa fin avant de continuer (PID {2})' -f $name, $TimeoutMinutes, $process.Id) }
            while (-not $process.WaitForExit(1800000)) {
                if ($Log) { Write-RunLog -Log $Log -Level ATTN -Message ('« {0} » toujours en cours ({1:N0} min) : attente de sa fin' -f $name, ((Get-Date) - $started).TotalMinutes) }
            }
        }
        $process.WaitForExit()
        $exitCode = $process.ExitCode
        $output = ''
        if ($outputTask) {
            # Un processus enfant peut garder la sortie ouverte après la fin du parent : lecture bornée.
            if ([System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]@($outputTask, $errorTask), 60000)) {
                $output = $outputTask.Result + $errorTask.Result
            } elseif ($Log) {
                Write-RunLog -Log $Log -Level DEBUG -Message ('Sortie de « {0} » non lue : encore ouverte par un processus enfant après 60 s' -f $name)
            }
        }
    } finally {
        $process.Dispose()
    }

    $duration = (Get-Date) - $started
    if ($Log) { Write-RunLog -Log $Log -Level DEBUG -Message ('Code de sortie {0} en {1:N0} s : {2}' -f $exitCode, $duration.TotalSeconds, [System.IO.Path]::GetFileName($FilePath)) }

    $reboot = $RebootExitCode -contains $exitCode
    if (-not $reboot -and $SuccessExitCode -notcontains $exitCode) {
        $meaning = if ($ExitCodeMessage.ContainsKey($exitCode)) { $ExitCodeMessage[$exitCode] } else { $script:KnownExitCodes[$exitCode] }
        $detail = if ($meaning) { " ($meaning)" } else { '' }
        throw ('« {0} » : code de sortie {1}{2}' -f [System.IO.Path]::GetFileName($FilePath), $exitCode, $detail)
    }
    return [pscustomobject]@{ ExitCode = $exitCode; RebootRequired = $reboot; Duration = $duration; Output = $output }
}

function Stop-ProcessTree {
    <# Arrête un processus et ses enfants (taskkill /T /F de System32), sans passer par Invoke-ExternalProcess. #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][int]$Id)
    if (-not $PSCmdlet.ShouldProcess("PID $Id", 'Arrêt du processus et de ses enfants')) { return }
    $taskkill = Get-SystemExecutablePath -Name 'taskkill.exe'
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $taskkill
    $info.Arguments = '/PID {0} /T /F' -f $Id
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $killer = [System.Diagnostics.Process]::Start($info)
    try { [void]$killer.WaitForExit(60000) } finally { $killer.Dispose() }
}

function Invoke-CmdLine {
    <#
        Repli pour une ligne de commande que Split-CommandLine ne sait pas découper (désinstalleurs
        aux chaînes atypiques) : cmd.exe /c, journalisé en ATTN. Jamais Invoke-Expression (DEC8).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CommandLine,
        [switch]$Interactive,
        [int]$TimeoutMinutes = 60,
        $Log
    )
    if ($Log) { Write-RunLog -Log $Log -Level ATTN -Message "Commande non analysable, exécutée par cmd.exe /c : $CommandLine" }
    return (Invoke-ExternalProcess -FilePath (Get-SystemExecutablePath -Name 'cmd.exe') -ArgumentList ('/d /c "{0}"' -f $CommandLine) -Interactive:$Interactive -TimeoutMinutes $TimeoutMinutes -Log $Log)
}

function Get-SystemExecutablePath {
    <# Chemin absolu d'un exécutable de System32 (jamais résolu par le PATH). #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Name)
    return (Join-Path ([Environment]::GetFolderPath('System')) $Name)
}
