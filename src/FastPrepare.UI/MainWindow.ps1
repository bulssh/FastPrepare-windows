<#
    Assemblage de la fenêtre : coquille, pages du parcours, sections, pompe, bouton Lancer.
    Le parcours (pages, ordre, libellés) vient de FastPrepare.Core (Get-WizardPage).
    Aucune règle métier ici : la validité vient des sections (Validate), les actions du moteur
    (FastPrepare.Application).
#>

$script:Context = $null
$script:Shell = $null
$script:Snapshot = $null
$script:Running = $false
$script:ProgressText = $null
# Pages affichées : identifiant → { Page, Root, Nav, Panels } ; page courante.
$script:Pages = [ordered]@{}
$script:CurrentPageId = $null
# Profils entreprise : état de départ du formulaire (bouton Nouveau) ; vrai pendant que la liste est reconstruite.
$script:DefaultProfile = $null
$script:ProfileListUpdating = $false

function Start-MainWindow {
    <# Construit et affiche la fenêtre ; rend la main à sa fermeture. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Context)

    $window = New-MainWindow -Context $Context
    Start-UiPump -Log $Context.Log
    [void]$window.ShowDialog()
}

function New-MainWindow {
    <#
        Construit la fenêtre sans l'afficher : coquille, pages, sections, profils. Séparé de
        Start-MainWindow pour que les tests puissent construire toute l'interface sous Windows
        (tests/FastPrepare.UI/UiBuild.Tests.ps1) sans ouvrir de fenêtre ni démarrer la pompe.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Construit des objets en mémoire, ne modifie pas le poste.')]
    param([Parameter(Mandatory)]$Context)

    $script:Context = $Context
    $xamlFolder = Join-Path $PSScriptRoot 'Xaml'

    Initialize-WpfApplication -ThemePath (Join-Path $xamlFolder 'Theme.xaml')
    $script:Shell = Import-Xaml -Path (Join-Path $xamlFolder 'MainWindow.xaml')
    $shell = $script:Shell.Controls
    $window = $script:Shell.Root

    Initialize-LogView -RichTextBox $shell.RtbLog
    $shell.BdSimu.Visibility = if ($Context.Mode -eq 'Simulation') { 'Visible' } else { 'Collapsed' }
    $shell.BdReal.Visibility = if ($Context.Mode -eq 'Real') { 'Visible' } else { 'Collapsed' }
    Set-MemoText -TextBlock $shell.TxtMemo -Reminder @($Context.Config.ManualReminders)

    Initialize-WizardPage

    foreach ($section in (Get-UiSection)) {
        if ($section.XamlFile) {
            if (-not $script:Pages.Contains($section.Page)) { throw "Section '$($section.Id)' : page inconnue '$($section.Page)'." }
            $panels = $script:Pages[$section.Page].Panels
            if (-not $panels) { throw "Section '$($section.Id)' : la page '$($section.Page)' n'accueille pas de section." }
            $fragment = Import-Xaml -Path (Join-Path $xamlFolder $section.XamlFile)
            $section.Root = $fragment.Root
            $section.Controls = $fragment.Controls
            [void]$panels[$section.Column].Children.Add($fragment.Root)
        } else {
            $section.Controls = $shell
        }
        Invoke-UiSectionCallback -Section $section -Name Initialize -Arguments @($Context) | Out-Null
    }
    Complete-WizardPageLayout

    $shell.BtnGo.Add_Click({ Invoke-UiAction -Name 'Lancer' -Action { Invoke-Launch } })
    $shell.BtnReview.Add_Click({ Invoke-UiAction -Name 'récapitulatif' -Action { Show-WizardPage -Id 'recap' } })
    $shell.BtnNext.Add_Click({
            Invoke-UiAction -Name 'page suivante' -Action {
                $next = Get-WizardNeighbor -PageId $script:CurrentPageId -Direction Next
                if ($next) { Show-WizardPage -Id $next }
            }
        })
    $shell.BtnPrev.Add_Click({
            Invoke-UiAction -Name 'page précédente' -Action {
                $previous = Get-WizardNeighbor -PageId $script:CurrentPageId -Direction Previous
                if ($previous) { Show-WizardPage -Id $previous }
            }
        })
    Show-WizardPage -Id (@($script:Pages.Keys)[0])

    # Profils entreprise : l'état de départ sert de formulaire vierge au bouton Nouveau.
    $script:DefaultProfile = Get-UiProfile
    $shell.CmbProfile.Add_SelectionChanged({ Invoke-UiAction -Name 'choix du profil' -Action { Invoke-ProfileSelection } })
    $shell.BtnProfileSave.Add_Click({ Invoke-UiAction -Name 'enregistrement du profil' -Action { Save-UiProfile } })
    $shell.BtnProfileNew.Add_Click({ Invoke-UiAction -Name 'nouveau profil' -Action { Reset-UiProfile } })
    Invoke-UiAction -Name 'liste des profils' -Action { Update-ProfileList }

    # Le relevé démarre une fois la fenêtre affichée et tourne en arrière-plan : la fenêtre reste réactive.
    $window.Add_ContentRendered({
            Invoke-UiAction -Name 'relevé du poste' -Action { Start-MachineView }
        })
    # Fermeture pendant une exécution : confirmation (l'action en cours irait à son terme).
    $window.Add_Closing({
            param($source, $closingArgs)
            if ($script:Running) {
                $answer = [System.Windows.MessageBox]::Show(
                    "Une exécution est en cours.`nFermer quand même ? L'action en cours ne sera pas annulée proprement.",
                    'Préparation de poste', 'YesNo', 'Warning')
                if ($answer -ne 'Yes') { $closingArgs.Cancel = $true }
                else { Write-RunLog -Log $script:Context.Log -Level ATTN -Message 'Fenêtre fermée pendant l''exécution : exécution interrompue.' }
            }
        })
    $window.Add_Closed({
            Stop-UiPump
            foreach ($section in (Get-UiSection)) {
                try { Invoke-UiSectionCallback -Section $section -Name Dispose | Out-Null } catch { Write-Verbose $_.Exception.Message }
            }
        })

    return $window
}

function Initialize-WizardPage {
    <#
        Construit, pour chaque page du parcours, son entrée du menu latéral et son contenu :
        deux colonnes vides (Left, Right) dans une zone défilante. Le récapitulatif est décrit
        dans MainWindow.xaml (PageRecap) et n'accueille aucune section.
    #>
    $shell = $script:Shell.Controls
    $script:Pages = [ordered]@{}
    foreach ($page in (Get-WizardPage)) {
        $nav = [System.Windows.Controls.RadioButton]::new()
        $nav.Style = Get-ThemeResource -Key 'Nav'
        $nav.GroupName = 'WizardNav'
        $nav.Tag = $page.Id
        # La page visée est lue sur le bouton cliqué (Tag) : aucune fermeture à conserver.
        $nav.Add_Click({
                param($source, $clickArgs)
                Invoke-UiAction -Name 'changement de page' -Action { Show-WizardPage -Id ([string]$source.Tag) }
            })
        $navPanel = if (Test-WizardPageOnPath -Kind $page.Kind) { $shell.PnlNav } else { $shell.PnlNavSettings }
        [void]$navPanel.Children.Add($nav)

        $root = $null
        $panels = $null
        if ($page.Kind -eq 'Review') {
            $root = $shell.PageRecap
        } else {
            $grid = [System.Windows.Controls.Grid]::new()
            foreach ($width in @(1, 16, 1)) {
                $column = [System.Windows.Controls.ColumnDefinition]::new()
                if ($width -eq 1) { $column.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }
                else { $column.Width = [System.Windows.GridLength]::new($width) }
                $grid.ColumnDefinitions.Add($column)
            }
            # Page « outil » : sa section occupe toute la hauteur (pas d'empilement ni de défilement).
            $fill = ($page.Kind -eq 'Tool')
            $left = if ($fill) { [System.Windows.Controls.Grid]::new() } else { [System.Windows.Controls.StackPanel]::new() }
            $right = [System.Windows.Controls.StackPanel]::new()
            [System.Windows.Controls.Grid]::SetColumn($left, 0)
            [System.Windows.Controls.Grid]::SetColumn($right, 2)
            [void]$grid.Children.Add($left)
            [void]$grid.Children.Add($right)

            $root = [System.Windows.Controls.ScrollViewer]::new()
            $root.VerticalScrollBarVisibility = if ($fill) { [System.Windows.Controls.ScrollBarVisibility]::Disabled } else { [System.Windows.Controls.ScrollBarVisibility]::Auto }
            $root.Content = $grid
            $root.Visibility = [System.Windows.Visibility]::Collapsed
            [void]$shell.PageHost.Children.Add($root)
            $panels = @{ Left = $left; Right = $right }
        }

        $script:Pages[$page.Id] = [pscustomobject]@{ Page = $page; Root = $root; Nav = $nav; Panels = $panels }
    }
    Update-WizardNavigation
}

function Complete-WizardPageLayout {
    <# Une page dont la colonne de droite est vide donne toute la largeur à celle de gauche. #>
    foreach ($entry in $script:Pages.Values) {
        if (-not $entry.Panels) { continue }
        if ($entry.Panels.Right.Children.Count -eq 0) {
            [System.Windows.Controls.Grid]::SetColumnSpan($entry.Panels.Left, 3)
        }
    }
}

function Show-WizardPage {
    <# Affiche une page : contenu, titre, entrée du menu, boutons Précédent / Suivant. #>
    param([Parameter(Mandatory)][string]$Id)
    if (-not $script:Pages.Contains($Id)) { throw "Page inconnue : '$Id'." }
    $shell = $script:Shell.Controls
    $script:CurrentPageId = $Id
    foreach ($entry in $script:Pages.Values) {
        $shown = ($entry.Page.Id -eq $Id)
        $entry.Root.Visibility = if ($shown) { 'Visible' } else { 'Collapsed' }
        $entry.Nav.IsChecked = $shown
    }
    $page = $script:Pages[$Id].Page
    $shell.TxtPageTitle.Text = $page.Title
    $shell.TxtPageSub.Text = $page.Subtitle

    $nextLabel = Get-WizardNextLabel -PageId $Id
    $shell.BtnNext.Visibility = if ($nextLabel) { 'Visible' } else { 'Collapsed' }
    if ($nextLabel) { $shell.BtnNext.Content = $nextLabel }
    $hasPrevious = [bool](Get-WizardNeighbor -PageId $Id -Direction Previous)
    $shell.BtnPrev.Visibility = if ($hasPrevious) { 'Visible' } else { 'Collapsed' }
    $pathLength = @($script:Pages.Values | Where-Object { Test-WizardPageOnPath -Kind $_.Page.Kind }).Count
    $hint = 'Ces réglages sont enregistrés sur la clé, jamais sur le poste préparé.'
    if ($page.Kind -eq 'Step') { $hint = 'Étape {0} sur {1}' -f $page.Number, $pathLength }
    elseif ($page.Kind -eq 'Review') { $hint = 'Rien n''est lancé avant le clic sur Lancer. Aucun redémarrage automatique.' }
    elseif ($page.Kind -eq 'Tool') { $hint = 'Outil en lecture seule : il ne modifie rien sur le poste, quel que soit le mode.' }
    $shell.TxtFootHint.Text = $hint
    # Le récapitulatif reflète la sélection du moment.
    if ($page.Kind -eq 'Review') { Update-UiState }
}

function Get-UiProblem {
    <#
        Motifs qui empêchent de lancer, dans l'ordre des sections : { PageId, Message }.
        PageId est vide pour un motif de la coquille (connexion internet).
    #>
    foreach ($section in (Get-UiSection)) {
        $reason = Invoke-UiSectionCallback -Section $section -Name Validate
        if ($reason) { [pscustomobject]@{ PageId = [string]$section.Page; Message = [string]$reason } }
    }
}

function Update-WizardNavigation {
    <# Libellés du menu latéral : numéro et titre de la page, ⚠ si une de ses sections bloque le lancement. #>
    param([object[]]$Problem = @())
    $blocked = @($Problem | ForEach-Object { $_.PageId } | Where-Object { $_ })
    foreach ($entry in $script:Pages.Values) {
        $page = $entry.Page
        $label = if ($page.Number -gt 0) { '{0}.  {1}' -f $page.Number, $page.Title } else { $page.Title }
        if ($blocked -contains $page.Id) { $label += '  ⚠' }
        $entry.Nav.Content = $label
    }
}

function Update-ReviewPage {
    <#
        Récapitulatif : points à corriger, résumé et liste des actions du plan (le même plan que
        celui qui sera exécuté). Rien n'est listé tant que le relevé du poste n'est pas prêt.
    #>
    param($Selection, [object[]]$Problem = @())
    $shell = $script:Shell.Controls
    $shell.PnlPlan.Children.Clear()

    $messages = @($Problem | ForEach-Object { '• ' + ($_.Message -replace '^Grisé : ', '') })
    $shell.BdProblems.Visibility = if ($messages.Count -gt 0) { 'Visible' } else { 'Collapsed' }
    $shell.TxtProblems.Text = $messages -join "`n"

    if (-not $script:Snapshot) {
        $shell.TxtPlanSummary.Text = 'Détection du poste en cours…'
        return
    }
    try {
        $plan = New-ExecutionPlan -Selection $Selection -Snapshot $script:Snapshot -Context $script:Context
    } catch {
        $shell.TxtPlanSummary.Text = 'Plan non construit : ' + $_.Exception.Message
        return
    }
    $shell.TxtPlanSummary.Text = Format-ExecutionPlanSummary -Plan $plan
    foreach ($action in @($plan.Actions)) {
        $prefix = if ($action.Interactive) { '⚠' } else { '•' }
        Add-ReviewLine -Text ('{0} {1}' -f $prefix, $action.Label)
    }
    foreach ($warning in @($plan.Warnings)) {
        Add-ReviewLine -Text ('⚠ ' + $warning) -BrushKey 'WarningBrush'
    }
}

function Add-ReviewLine {
    param([string]$Text, [string]$BrushKey)
    $line = [System.Windows.Controls.TextBlock]::new()
    $line.Text = $Text
    $line.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $line.Margin = [System.Windows.Thickness]::new(0, 2, 0, 2)
    if ($BrushKey) { $line.Foreground = Get-ThemeResource -Key $BrushKey }
    [void]$script:Shell.Controls.PnlPlan.Children.Add($line)
}

function Get-UiProfile {
    <# Profil entreprise correspondant à l'état actuel de la fenêtre : chaque section y écrit sa partie (jamais de mot de passe). #>
    param([string]$Name = '')
    $companyProfile = New-CompanyProfile -Name $Name
    foreach ($section in (Get-UiSection)) {
        Invoke-UiSectionCallback -Section $section -Name ExportProfile -Arguments @($companyProfile) | Out-Null
    }
    return $companyProfile
}

function Set-UiProfile {
    <# Applique un profil entreprise à la fenêtre : chaque section reprend sa partie ; une section en erreur n'empêche pas les autres. #>
    param([Parameter(Mandatory)]$CompanyProfile)
    foreach ($section in (Get-UiSection)) {
        try {
            Invoke-UiSectionCallback -Section $section -Name ImportProfile -Arguments @($CompanyProfile) | Out-Null
        } catch {
            Write-RunLog -Log $script:Context.Log -Level ERREUR -Message ("Profil : section {0} non remplie : {1}" -f $section.Number, $_.Exception.Message)
        }
    }
    Update-UiState
}

function Set-ProfileHint {
    param([string]$Text, [switch]$IsError)
    $hint = $script:Shell.Controls.TxtProfileHint
    $hint.Text = $Text
    $hint.Foreground = Get-ThemeResource -Key $(if ($IsError) { 'ErrorBrush' } else { 'TextSecondaryBrush' })
}

function Update-ProfileList {
    <# Relit les profils de la clé et remplit le sélecteur ; -Select : nom du profil à afficher comme choisi (sans le recharger). #>
    param([string]$Select)
    $combo = $script:Shell.Controls.CmbProfile
    $script:ProfileListUpdating = $true
    try {
        $combo.Items.Clear()
        foreach ($entry in @(Get-CompanyProfileList -Context $script:Context)) {
            $item = [System.Windows.Controls.ComboBoxItem]::new()
            $item.Content = $entry.Name
            $item.Tag = $entry.Path
            [void]$combo.Items.Add($item)
            if ($Select -and [string]::Equals($entry.Name, $Select, [System.StringComparison]::OrdinalIgnoreCase)) { $combo.SelectedItem = $item }
        }
        if ($Select -and -not $combo.SelectedItem) { $combo.Text = $Select }
    } finally {
        $script:ProfileListUpdating = $false
    }
}

function Invoke-ProfileSelection {
    <# Un profil vient d'être choisi dans la liste : il pré-remplit les étapes. #>
    if ($script:ProfileListUpdating -or $script:Running) { return }
    $item = $script:Shell.Controls.CmbProfile.SelectedItem
    if (-not $item) { return }
    try {
        $companyProfile = Import-CompanyProfile -Context $script:Context -Path ([string]$item.Tag)
    } catch {
        Set-ProfileHint -Text $_.Exception.Message -IsError
        throw
    }
    Set-UiProfile -CompanyProfile $companyProfile
    Set-ProfileHint -Text ('Profil « {0} » appliqué. Mots de passe à saisir.' -f $companyProfile.Name)
}

function Save-UiProfile {
    <# Bouton Enregistrer : l'état actuel de la fenêtre devient le profil du nom saisi (confirmation avant de remplacer un profil existant). #>
    $shell = $script:Shell.Controls
    $name = ([string]$shell.CmbProfile.Text).Trim()
    if (-not $name) {
        Set-ProfileHint -Text 'Saisir un nom de profil avant d''enregistrer.' -IsError
        return
    }
    $existing = @(Get-CompanyProfileList -Context $script:Context | Where-Object { [string]::Equals($_.Name, $name, [System.StringComparison]::OrdinalIgnoreCase) })
    if ($existing.Count -gt 0) {
        $answer = [System.Windows.MessageBox]::Show(("Remplacer le profil « {0} » par les réglages actuels ?" -f $existing[0].Name), 'Profil entreprise', 'YesNo', 'Question')
        if ($answer -ne 'Yes') { return }
        $name = [string]$existing[0].Name
    }
    try {
        $saved = Export-CompanyProfile -Context $script:Context -CompanyProfile (Get-UiProfile -Name $name)
    } catch {
        Set-ProfileHint -Text $_.Exception.Message -IsError
        throw
    }
    Update-ProfileList -Select $saved.Name
    Set-ProfileHint -Text ('Profil « {0} » enregistré sur la clé, sans mot de passe.' -f $saved.Name)
}

function Reset-UiProfile {
    <# Bouton Nouveau : nom vidé, étapes remises dans leur état de départ. #>
    $combo = $script:Shell.Controls.CmbProfile
    $script:ProfileListUpdating = $true
    try {
        $combo.SelectedIndex = -1
        $combo.Text = ''
    } finally {
        $script:ProfileListUpdating = $false
    }
    Set-UiProfile -CompanyProfile $script:DefaultProfile
    Set-ProfileHint -Text 'Formulaire remis à zéro. Saisir un nom puis Enregistrer pour créer un profil.'
}

function Start-MachineView {
    <# Lance le relevé du poste en arrière-plan ; les sections sont remplies à son retour. #>
    $work = Start-MachineSnapshot -Context $script:Context
    Register-UiBackgroundWork -Work $work -OnCompleted {
        param($result)
        Complete-MachineView -Snapshot (@($result) | Select-Object -Last 1)
    } -OnFailed {
        param($message)
        Write-RunLog -Log $script:Context.Log -Level ERREUR -Message "Relevé du poste impossible : $message"
        $script:Shell.Controls.TxtPoste.Text = 'Détection du poste impossible (voir le journal)'
        $script:Shell.Controls.TxtGoHint.Text = 'Grisé : détection du poste impossible'
    }
}

function Complete-MachineView {
    <# Relevé terminé : en-tête, remplissage des sections, état du bouton Lancer. #>
    param([Parameter(Mandatory)]$Snapshot)
    $context = $script:Context
    $script:Snapshot = $Snapshot

    $shell = $script:Shell.Controls
    $shell.TxtPoste.Text = 'Poste détecté : {0} — {1}' -f $Snapshot.Identity.Manufacturer, $Snapshot.Identity.Model
    $shell.TxtOs.Text = $Snapshot.Identity.OsLabel

    foreach ($section in (Get-UiSection)) {
        try {
            Invoke-UiSectionCallback -Section $section -Name OnSnapshot -Arguments @($Snapshot, $context) | Out-Null
        } catch {
            Write-RunLog -Log $context.Log -Level ERREUR -Message ("Affichage de la section {0} impossible : {1}" -f $section.Number, $_.Exception.Message)
        }
    }
    Update-UiState
}

function Get-CurrentSelection {
    <# Sélection courante : chaque section y écrit sa partie. #>
    $selection = New-Selection
    foreach ($section in (Get-UiSection)) {
        Invoke-UiSectionCallback -Section $section -Name GetSelection -Arguments @($selection) | Out-Null
    }
    return $selection
}

function Update-UiState {
    <# À appeler après tout changement : informe les sections (Refresh) puis met à jour Lancer. #>
    $selection = Get-CurrentSelection
    try {
        foreach ($section in (Get-UiSection)) {
            Invoke-UiSectionCallback -Section $section -Name Refresh -Arguments @($selection) | Out-Null
        }
        Update-LaunchState
        # Le plan n'est recalculé que si le récapitulatif est affiché, et jamais pendant une exécution.
        if ($script:CurrentPageId -eq 'recap' -and -not $script:Running) {
            Update-ReviewPage -Selection $selection -Problem @(Get-UiProblem)
        }
    } finally {
        # La sélection n'est qu'un instantané : le mot de passe qu'elle porte est libéré aussitôt.
        Clear-SelectionSecret -Selection $selection
    }
}

function Update-LaunchState {
    <#
        Lancer est actif si le relevé est prêt et qu'aucune section ne le bloque ; sinon le premier
        motif est affiché. Le menu latéral signale les pages qui portent un motif.
    #>
    $shell = $script:Shell.Controls
    $problems = @(Get-UiProblem)
    Update-WizardNavigation -Problem $problems
    $reason = $null
    if ($script:Running) { $reason = if ($script:ProgressText) { $script:ProgressText } else { 'Exécution en cours…' } }
    elseif (-not $script:Snapshot) { $reason = 'Grisé : détection du poste en cours' }
    elseif ($problems.Count -gt 0) { $reason = $problems[0].Message }

    $shell.BtnGo.IsEnabled = (-not $reason)
    if ($reason) { $shell.TxtGoHint.Text = $reason }
    elseif ($script:Context.Mode -eq 'Simulation') { $shell.TxtGoHint.Text = 'Simulation : rien ne sera modifié' }
    else { $shell.TxtGoHint.Text = 'Aucun redémarrage automatique' }
}

function Invoke-Launch {
    <#
        Bouton Lancer : sélection → plan d'exécution (le même pour la simulation et le réel) →
        confirmation en mode réel → exécution en arrière-plan, formulaire verrouillé jusqu'à la fin.
    #>
    $context = $script:Context
    # Gardée jusqu'à la fin de l'exécution : les actions du plan référencent son mot de passe.
    $script:LaunchSelection = Get-CurrentSelection
    $started = $false
    $locked = $false
    try {
        $plan = New-ExecutionPlan -Selection $script:LaunchSelection -Snapshot $script:Snapshot -Context $context

        if ($context.Mode -ne 'Simulation') {
            $answer = [System.Windows.MessageBox]::Show(
                ("Lancer la préparation du poste ?`n`n{0}`n`nAucun redémarrage automatique." -f (Format-ExecutionPlanSummary -Plan $plan)),
                'Préparation de poste', 'YesNo', 'Question')
            if ($answer -ne 'Yes') { return }
        }

        Set-ExecutionLock -Locked $true
        $locked = $true
        $work = Start-ExecutionPlan -Plan $plan -Context $context
        Register-UiBackgroundWork -Work $work -OnCompleted {
            param($result)
            Complete-Launch
            Set-ExecutionLock -Locked $false
        } -OnFailed {
            param($message)
            Write-RunLog -Log $script:Context.Log -Level ERREUR -Message "Exécution interrompue : $message"
            Complete-Launch
            Set-ExecutionLock -Locked $false
        }
        $started = $true
    } finally {
        # Lancement abandonné ou en échec avant la prise en charge du travail : formulaire rendu
        # au technicien (audit BUG-010).
        if (-not $started) {
            Complete-Launch
            if ($locked) { Set-ExecutionLock -Locked $false }
        }
    }
}

function Publish-SettingsChanged {
    <#
        Un réglage vient d'être enregistré (page Catalogue logiciels) : chaque section qui l'affiche se met
        à jour (OnSettingsChanged), puis l'état de Lancer est recalculé.
    #>
    foreach ($section in (Get-UiSection)) {
        try {
            Invoke-UiSectionCallback -Section $section -Name OnSettingsChanged -Arguments @($script:Context) | Out-Null
        } catch {
            Write-RunLog -Log $script:Context.Log -Level ERREUR -Message ("Mise à jour de la section {0} impossible : {1}" -f $section.Number, $_.Exception.Message)
        }
    }
    Update-UiState
}

function Complete-Launch {
    <# Fin (ou abandon) d'un lancement : libère le mot de passe de la sélection lancée. #>
    Clear-SelectionSecret -Selection $script:LaunchSelection
    $script:LaunchSelection = $null
}

function Set-RunProgress {
    <# Avancement publié par le moteur (Publish-RunProgress) : barre et texte sous le bouton Lancer. #>
    param([int]$Current, [int]$Total, [string]$Label)
    if (-not $script:Running -or $Total -le 0) { return }
    $shell = $script:Shell.Controls
    $shell.PbRun.Maximum = $Total
    $shell.PbRun.Value = $Current - 1
    $short = if ($Label.Length -gt 70) { $Label.Substring(0, 67) + '…' } else { $Label }
    $script:ProgressText = 'Action {0} / {1} : {2}' -f $Current, $Total, $short
    $shell.TxtGoHint.Text = $script:ProgressText
}

function Set-ExecutionLock {
    <# Verrouille (ou libère) le formulaire pendant une exécution ; le journal reste lisible. #>
    param([bool]$Locked)
    $script:Running = $Locked
    $script:ProgressText = $null
    $shell = $script:Shell.Controls
    $shell.PbRun.Value = 0
    $shell.PbRun.Visibility = if ($Locked) { 'Visible' } else { 'Collapsed' }
    # Aucun profil chargé ni enregistré pendant une exécution.
    $shell.CmbProfile.IsEnabled = -not $Locked
    $shell.BtnProfileSave.IsEnabled = -not $Locked
    $shell.BtnProfileNew.IsEnabled = -not $Locked
    # Pages de saisie et catalogue figés (aucun réglage modifié pendant une exécution, DEC19) ;
    # la navigation reste libre et le récapitulatif garde le journal lisible.
    foreach ($entry in $script:Pages.Values) {
        if ($entry.Panels) {
            $entry.Panels.Left.IsEnabled = -not $Locked
            $entry.Panels.Right.IsEnabled = -not $Locked
        }
    }
    Update-UiState
}

function Invoke-UiAction {
    <#
        Exécute le traitement d'un événement de l'interface : une erreur est journalisée au lieu
        de remonter dans la boucle de messages WPF (ce qui fermerait la fenêtre).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Action
    )
    try {
        & $Action
    } catch {
        Write-RunLog -Log $script:Context.Log -Level ERREUR -Message ("Erreur ({0}) : {1}" -f $Name, $_.Exception.Message)
    }
}

function Set-MemoText {
    param($TextBlock, [string[]]$Reminder)
    $TextBlock.Inlines.Clear()
    $title = New-Object System.Windows.Documents.Run('Mémo — fait à la main, hors outil : ')
    $title.FontWeight = [System.Windows.FontWeights]::SemiBold
    $TextBlock.Inlines.Add($title)
    $TextBlock.Inlines.Add((New-Object System.Windows.Documents.Run(($Reminder -join ' · '))))
}
