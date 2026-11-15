<#
    Section 13 — Lecteurs réseau (itération 17).
    Lettre, chemin \\serveur\partage et libellé ; chaque lecteur de la liste devient une action
    du plan. Règles de saisie : FastPrepare.Core (Get-NetworkDriveError). Le mappage est fait
    pour l'utilisateur de la session ouverte, sans script ni tâche planifiée.
#>

Register-UiSection -Id 'network-drives' -Number 13 -Page 'systeme' -Column Left -XamlFile 'Sections\NetworkDrives.xaml' -Initialize {
    param($Section, $Context)
    $c = $Section.Controls
    $Section.State.Drives = New-Object System.Collections.Generic.List[object]
    $Section.State.UsedLetters = @()
    $Section.State.DefaultHint = "Connectés pour l'utilisateur de la session ouverte, visibles à sa prochaine ouverture de session. Aucun script ni tâche planifiée n'est laissé sur le poste."
    foreach ($code in 68..90) { [void]$c.CmbDriveLetter.Items.Add([string][char]$code) }

    $onChange = { Invoke-UiAction -Name 'lecteur réseau' -Action { Update-NetworkDrivesView; Update-UiState } }
    $c.TxtDrivePath.Add_TextChanged($onChange)
    $c.TxtDriveLabel.Add_TextChanged($onChange)
    $c.CmbDriveLetter.Add_SelectionChanged($onChange)
    $c.BtnDriveAdd.Add_Click({ Invoke-UiAction -Name 'ajout d''un lecteur réseau' -Action { Add-NetworkDriveFromForm } })
    $c.TxtDriveHint.Text = $Section.State.DefaultHint
} -OnSnapshot {
    param($Section, $Snapshot, $Context)
    # Lettres des disques du poste : refusées dès la saisie (revérifiées à l'exécution).
    try { $Section.State.UsedLetters = @(Get-UsedDriveLetter) } catch { $Section.State.UsedLetters = @('C') }
} -GetSelection {
    param($Section, $Selection)
    $Selection.NetworkDrives.Items = @($Section.State.Drives.ToArray())
} -Validate {
    param($Section)
    if (([string]$Section.Controls.TxtDrivePath.Text).Trim()) {
        return 'Grisé : lecteur réseau saisi mais pas ajouté à la liste (Ajouter à la liste, ou vider le chemin)'
    }
    return $null
} -ExportProfile {
    param($Section, $CompanyProfile)
    $CompanyProfile.NetworkDrives = @($Section.State.Drives | ForEach-Object { [pscustomobject][ordered]@{ Letter = $_.Letter; Path = $_.Path; Label = $_.Label } })
} -ImportProfile {
    param($Section, $CompanyProfile)
    Set-NetworkDriveList -Drive @($CompanyProfile.NetworkDrives | ForEach-Object { New-NetworkDriveRequest -Letter $_.Letter -Path $_.Path -Label $_.Label })
}

function Get-NetworkDriveFromForm {
    <# Lecteur saisi dans le formulaire (normalisé par FastPrepare.Core). #>
    $c = (Get-UiSection -Id 'network-drives').Controls
    return (New-NetworkDriveRequest -Letter ([string]$c.CmbDriveLetter.SelectedItem) -Path ([string]$c.TxtDrivePath.Text) -Label ([string]$c.TxtDriveLabel.Text))
}

function Get-NetworkDriveFormError {
    <# Motif qui empêche d'ajouter le lecteur saisi, ou $null. #>
    $section = Get-UiSection -Id 'network-drives'
    $used = @($section.State.UsedLetters) + @($section.State.Drives | ForEach-Object { $_.Letter })
    return (Get-NetworkDriveError -Drive (Get-NetworkDriveFromForm) -UsedLetter $used)
}

function Add-NetworkDriveFromForm {
    $section = Get-UiSection -Id 'network-drives'
    $c = $section.Controls
    $problem = Get-NetworkDriveFormError
    if ($problem) {
        $c.TxtDriveHint.Text = 'À corriger : {0}' -f $problem
        $c.TxtDriveHint.Foreground = Get-ThemeResource -Key 'ErrorBrush'
        return
    }
    $section.State.Drives.Add((Get-NetworkDriveFromForm))
    $c.CmbDriveLetter.SelectedIndex = -1
    $c.TxtDrivePath.Text = ''
    $c.TxtDriveLabel.Text = ''
    Update-NetworkDrivesList
    Update-NetworkDrivesView
    Update-UiState
}

function Update-NetworkDrivesList {
    $section = Get-UiSection -Id 'network-drives'
    $panel = $section.Controls.PnlDrives
    $panel.Children.Clear()
    foreach ($drive in $section.State.Drives) {
        $row = New-RemovableRow -Text (Format-NetworkDriveSummary -Drive $drive) -Item $drive -OnRemove {
            param($item)
            [void](Get-UiSection -Id 'network-drives').State.Drives.Remove($item)
            Update-NetworkDrivesList
            Update-UiState
        }
        [void]$panel.Children.Add($row)
    }
    $section.Controls.TxtDrivesNone.Visibility = if ($section.State.Drives.Count -eq 0) { 'Visible' } else { 'Collapsed' }
}

function Update-NetworkDrivesView {
    <# Consigne sous le formulaire : le motif du refus dès qu'un chemin est saisi. #>
    $section = Get-UiSection -Id 'network-drives'
    $c = $section.Controls
    $problem = if (([string]$c.TxtDrivePath.Text).Trim()) { Get-NetworkDriveFormError } else { $null }
    if ($problem) {
        $c.TxtDriveHint.Text = 'À corriger : {0}' -f $problem
        $c.TxtDriveHint.Foreground = Get-ThemeResource -Key 'ErrorBrush'
    } else {
        $c.TxtDriveHint.Text = $section.State.DefaultHint
        $c.TxtDriveHint.Foreground = Get-ThemeResource -Key 'TextSecondaryBrush'
    }
}

function Set-NetworkDriveList {
    <# Remplace la liste des lecteurs (chargement d'un profil entreprise). #>
    param([AllowEmptyCollection()][object[]]$Drive = @())
    $section = Get-UiSection -Id 'network-drives'
    $section.State.Drives.Clear()
    foreach ($item in @($Drive)) { $section.State.Drives.Add($item) }
    Update-NetworkDrivesList
}
