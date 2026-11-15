<#
    Vérification sans fenêtre sur un poste de test Windows (machine virtuelle), par exemple à
    travers SSH. Ne modifie pas le poste : relevé réel en lecture, puis exécution en SIMULATION
    d'un plan qui passe par toutes les étapes ajoutées, puis construction de la fenêtre en mémoire.
    Écrit un compte rendu en UTF-8 dans -ResultPath.

    Usage : powershell -NoProfile -STA -ExecutionPolicy Bypass -File tools\Invoke-VmCheck.ps1
#>
[CmdletBinding()]
param(
    [string]$ResultPath
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $ResultPath) { $ResultPath = Join-Path $root 'resultat-vm.txt' }
$report = New-Object System.Collections.Generic.List[string]
function Add-ReportLine { param([string]$Text = '') $script:report.Add($Text) }
function Invoke-Stage {
    param([string]$Title, [scriptblock]$Action)
    Add-ReportLine ''
    Add-ReportLine "===== $Title ====="
    try { & $Action } catch {
        Add-ReportLine ('ERREUR : {0}' -f $_.Exception.Message)
        Add-ReportLine ('         {0}' -f ($_.ScriptStackTrace -split "`n" | Select-Object -First 3 | ForEach-Object { $_.Trim() }) -join ' | ')
    }
}

function New-CheckSecret {
    # Mot de passe fictif, construit caractère par caractère : jamais une chaîne en clair conservée.
    $secret = New-Object System.Security.SecureString
    foreach ($char in 'Fictif-Vm#2026'.ToCharArray()) { $secret.AppendChar($char) }
    $secret.MakeReadOnly()
    return $secret
}

try {
    Invoke-Stage 'Poste' {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $isAdmin = (New-Object System.Security.Principal.WindowsPrincipal($identity)).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
        Add-ReportLine ('Système        : {0} (build {1})' -f $os.Caption, $os.BuildNumber)
        Add-ReportLine ('PowerShell     : {0}, cloisonnement {1}' -f $PSVersionTable.PSVersion, [System.Threading.Thread]::CurrentThread.GetApartmentState())
        Add-ReportLine ('Compte         : {0} (administrateur élevé : {1})' -f $identity.Name, $isAdmin)
        Add-ReportLine ('Session        : {0}, interactive : {1}' -f (Get-Process -Id $PID).SessionId, [Environment]::UserInteractive)
        Add-ReportLine ('Culture        : {0}' -f (Get-Culture).Name)
    }

    Invoke-Stage 'Chargement des modules et de la configuration' {
        foreach ($module in 'FastPrepare.Core', 'FastPrepare.Infrastructure', 'FastPrepare.Application', 'FastPrepare.UI') {
            Import-Module -Name (Join-Path $root "src\$module\$module.psd1") -Force
        }
        $loaded = Read-AppConfig -Path (Join-Path $root 'config.json')
        $script:context = New-AppContext -Root $root -Config $loaded.Config -RequestedMode 'Simulation'
        Add-ReportLine ('Modules chargés ; mode {0} ; {1} avertissement(s) de configuration' -f $script:context.Mode, @($loaded.Warnings).Count)
        foreach ($warning in @($loaded.Warnings)) { Add-ReportLine ('  ATTN {0}' -f $warning) }
    }

    Invoke-Stage 'Relevé réel du poste (lecture seule)' {
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $script:snapshot = Get-MachineSnapshot -Context $script:context
        $s = $script:snapshot
        Add-ReportLine ('Durée          : {0:n1} s' -f $watch.Elapsed.TotalSeconds)
        Add-ReportLine ('Poste          : {0} — {1} — N/S {2} — {3}' -f $s.Identity.Manufacturer, $s.Identity.Model, $s.Identity.Serial, $s.Identity.OsLabel)
        Add-ReportLine ('Nom            : {0} (nom par défaut de Windows : {1})' -f $s.Identity.HostName, (Test-DefaultComputerName -Name $s.Identity.HostName))
        Add-ReportLine ('winget         : disponible {0}, source prête {1}' -f $s.WingetAvailable, $s.WingetSourceReady)
        Add-ReportLine ('Logiciels      : {0} relevé(s)' -f @($s.Software).Count)
        Add-ReportLine ('Sessions       : {0} ; supprimables : {1}' -f (@($s.LocalAccounts.Names) -join ', '), (@($s.LocalAccounts.Removable | ForEach-Object { $_.Name }) -join ', '))
        Add-ReportLine ('Cartes réseau  : {0}' -f (@($s.Adapters | ForEach-Object { $_.Name }) -join ', '))
        Add-ReportLine ('Utilitaire     : {0}' -f $s.SuggestedUtilityKey)
    }

    Invoke-Stage 'Accès système des nouvelles étapes (lecture seule)' {
        $user = Get-InteractiveUser
        Add-ReportLine ('Session ouverte        : {0}' -f $(if ($user) { '{0} ({1})' -f $user.Name, $user.Sid } else { 'aucune (aucun Explorateur en cours)' }))
        Add-ReportLine ('Lettres prises         : {0}' -f (@(Get-UsedDriveLetter) -join ' '))
        $state = Get-ComputerDomainState
        Add-ReportLine ('Domaine                : membre {0} ({1})' -f $state.PartOfDomain, $state.Domain)
        $folder = Get-PrinterDriverFolder -Context $script:context
        $catalog = @(Get-PrinterDriverCatalog -Context $script:context)
        Add-ReportLine ('Pilotes d''imprimante   : {0} fichier(s) .inf dans {1}' -f $catalog.Count, $folder)
        # Lecture des modèles sur un pilote d'imprimante fourni avec Windows.
        $inbox = Get-ChildItem -Path (Join-Path $env:windir 'INF') -Filter 'prn*.inf' -ErrorAction SilentlyContinue | Select-Object -First 3
        foreach ($inf in @($inbox)) {
            $models = @(Get-PrinterDriverModel -InfPath $inf.FullName)
            Add-ReportLine ('  {0} : {1} modèle(s){2}' -f $inf.Name, $models.Count, $(if ($models.Count) { ' — ex. ' + $models[0] } else { '' }))
        }
        Add-ReportLine ('Imprimantes présentes  : {0}' -f (@(Get-Printer -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) -join ', '))
        Add-ReportLine ('Profils entreprise     : {0}' -f @(Get-CompanyProfileList -Context $script:context).Count)
    }

    Invoke-Stage 'Plan complet et exécution en SIMULATION' {
        $selection = New-Selection
        $selection.SystemSettings.Power = $true
        $selection.Updates.WindowsUpdate = $true
        $selection.NewLocalAccounts.Items = @(
            New-LocalAccountRequest -Name 'fp-essai-1' -FullName 'Essai Un' -Description 'Compte de simulation' -Password (New-CheckSecret) -Administrator -PasswordNeverExpires
            New-LocalAccountRequest -Name 'fp-essai-2' -Password (New-CheckSecret) -CannotChangePassword -Disabled
        )
        $selection.Agents.RmmUrl = 'https://app.ninjarmm.example/agent/installer/0000/client-5.9.msi'
        $selection.Agents.AntivirusUrl = 'https://cloud.gravityzone.example/Packages/BSTWIN/0/setupdownloader_%5BaHR0cHM6Ly9leGVtcGxl%5D.exe'
        $selection.NetworkDrives.Items = @(New-NetworkDriveRequest -Letter 'P' -Path '\\srv-fichiers\Commun' -Label 'Commun')
        $selection.Printers.Items = @(New-IpPrinterRequest -Name 'Essai' -Address '192.168.56.250' -InfPath 'C:\Drivers\essai.inf' -DriverName 'Modèle d''essai')
        $selection.DomainJoin.Domain = 'entreprise.example'
        $selection.DomainJoin.Account = 'adm-jonction'
        $selection.DomainJoin.Password = New-CheckSecret
        try {
            $plan = New-ExecutionPlan -Selection $selection -Snapshot $script:snapshot -Context $script:context
            Add-ReportLine (Format-ExecutionPlanSummary -Plan $plan)
            $results = @(Invoke-ExecutionPlan -Plan $plan -Context $script:context)
            foreach ($result in $results) {
                Add-ReportLine ('  [{0,-9}] étape {1,2} · {2}' -f $result.Outcome, $result.Action.StepNumber, $result.Action.Label)
                if ($result.Error) { Add-ReportLine ('              {0}' -f $result.Error) }
            }
            foreach ($warning in @($plan.Warnings)) { Add-ReportLine ('  ATTN {0}' -f $warning) }
            $bad = @($results | Where-Object { $_.Outcome -ne 'Simulated' })
            Add-ReportLine ('Bilan : {0} action(s), {1} hors simulation' -f $results.Count, $bad.Count)
            Add-ReportLine ('Dernière action : {0}' -f $results[-1].Action.StepId)
        } finally {
            Clear-SelectionSecret -Selection $selection
        }
    }

    Invoke-Stage 'Construction de la fenêtre (sans affichage)' {
        $ui = Get-Module -Name FastPrepare.UI
        & $ui {
            param($Context, $Snapshot)
            $script:CheckWindow = New-MainWindow -Context $Context
            Complete-MachineView -Snapshot $Snapshot
            foreach ($id in @($script:Pages.Keys)) { Show-WizardPage -Id $id }
        } $script:context $script:snapshot
        $pages = & $ui { @($script:Pages.Keys) -join ', ' }
        $sections = & $ui { @(Get-UiSection | ForEach-Object { '{0}({1})' -f $_.Id, $_.Page }) -join ' ' }
        $problems = & $ui { @(Get-UiProblem | ForEach-Object { $_.Message }) }
        Add-ReportLine ('Fenêtre construite ; pages : {0}' -f $pages)
        Add-ReportLine ('Sections : {0}' -f $sections)
        Add-ReportLine ('Motifs de blocage au départ : {0}' -f $(if (@($problems).Count) { @($problems) -join ' | ' } else { 'aucun' }))
        & $ui { foreach ($section in (Get-UiSection)) { try { Invoke-UiSectionCallback -Section $section -Name Dispose | Out-Null } catch { Write-Verbose $_.Exception.Message } } }
    }

    Invoke-Stage 'Journal de cette vérification' {
        $path = $script:context.Log.FilePath
        if (Test-Path -LiteralPath $path) {
            $lines = @([System.IO.File]::ReadAllLines($path))
            $errors = @($lines | Where-Object { $_ -match '\[ERREUR\]' })
            $warnings = @($lines | Where-Object { $_ -match '\[ATTN\]' })
            Add-ReportLine ('{0} ligne(s), {1} ERREUR, {2} ATTN' -f $lines.Count, $errors.Count, $warnings.Count)
            foreach ($line in @($errors) + @($warnings)) { Add-ReportLine ('  ' + $line) }
        } else {
            Add-ReportLine 'Aucun journal écrit.'
        }
    }
} finally {
    [System.IO.File]::WriteAllLines($ResultPath, $report.ToArray(), (New-Object System.Text.UTF8Encoding($true)))
    $report | ForEach-Object { Write-Output $_ }
}
