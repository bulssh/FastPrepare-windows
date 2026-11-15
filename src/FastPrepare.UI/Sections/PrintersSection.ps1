<#
    Section 14 — Imprimantes IP (itération 17).
    Nom, adresse IP, pilote .inf choisi dans le dossier des pilotes du poste (C:\Drivers par
    défaut) et modèle lu dans ce fichier. Chaque imprimante de la liste devient une action du plan.
    Règles de saisie : FastPrepare.Core (Get-IpPrinterError).
#>

Register-UiSection -Id 'printers' -Number 14 -Page 'systeme' -Column Right -XamlFile 'Sections\Printers.xaml' -Initialize {
    param($Section, $Context)
    $c = $Section.Controls
    $Section.State.Printers = New-Object System.Collections.Generic.List[object]
    $Section.State.Folder = Get-PrinterDriverFolder -Context $Context
    $Section.State.DefaultHint = 'Déposer le pilote décompressé dans {0} avant de lancer l''outil, puis Actualiser.' -f $Section.State.Folder
    $c.TxtPrinterFolder.Text = 'Pilote (.inf) — dossier {0}' -f $Section.State.Folder

    $onChange = { Invoke-UiAction -Name 'imprimante' -Action { Update-PrintersView; Update-UiState } }
    $c.TxtPrinterName.Add_TextChanged($onChange)
    $c.TxtPrinterAddress.Add_TextChanged($onChange)
    $c.CmbPrinterInf.Add_SelectionChanged({ Invoke-UiAction -Name 'choix du pilote' -Action { Update-PrinterModelList; Update-PrintersView } })
    $c.BtnPrinterScan.Add_Click({ Invoke-UiAction -Name 'recherche des pilotes' -Action { Update-PrinterDriverList } })
    $c.BtnPrinterAdd.Add_Click({ Invoke-UiAction -Name 'ajout d''une imprimante' -Action { Add-PrinterFromForm } })
    $c.TxtPrinterHint.Text = $Section.State.DefaultHint
    Update-PrinterDriverList
} -GetSelection {
    param($Section, $Selection)
    $Selection.Printers.Items = @($Section.State.Printers.ToArray())
} -Validate {
    param($Section)
    if (([string]$Section.Controls.TxtPrinterName.Text).Trim()) {
        return 'Grisé : imprimante saisie mais pas ajoutée à la liste (Ajouter à la liste, ou vider le nom)'
    }
    return $null
} -ExportProfile {
    param($Section, $CompanyProfile)
    $CompanyProfile.Printers = @($Section.State.Printers | ForEach-Object { [pscustomobject][ordered]@{ Name = $_.Name; Address = $_.Address; InfPath = $_.InfPath; DriverName = $_.DriverName } })
} -ImportProfile {
    param($Section, $CompanyProfile)
    Set-PrinterList -Printer @($CompanyProfile.Printers | ForEach-Object { New-IpPrinterRequest -Name $_.Name -Address $_.Address -InfPath $_.InfPath -DriverName $_.DriverName })
}

function Update-PrinterDriverList {
    <# Relit le dossier des pilotes et remplit la liste des fichiers .inf (le choix courant est conservé s'il existe encore). #>
    $section = Get-UiSection -Id 'printers'
    $combo = $section.Controls.CmbPrinterInf
    $previous = if ($combo.SelectedItem) { [string]$combo.SelectedItem.Tag } else { '' }
    $combo.Items.Clear()
    $catalog = @(Get-PrinterDriverCatalog -Context $script:Context)
    foreach ($entry in $catalog) {
        # Élément affiché : chemin relatif au dossier ; Tag : chemin complet du fichier .inf.
        $item = [System.Windows.Controls.ComboBoxItem]::new()
        $item.Content = $entry.Display
        $item.Tag = $entry.Path
        [void]$combo.Items.Add($item)
        if ($previous -and $entry.Path -eq $previous) { $combo.SelectedItem = $item }
    }
    if ($catalog.Count -eq 0) {
        $section.Controls.TxtPrinterHint.Text = 'Aucun pilote (.inf) trouvé dans {0}.' -f $section.State.Folder
        $section.Controls.TxtPrinterHint.Foreground = Get-ThemeResource -Key 'WarningBrush'
    } else {
        Update-PrintersView
    }
}

function Update-PrinterModelList {
    <# Pilote choisi : ses modèles sont proposés ; s'il n'en déclare qu'un, il est sélectionné. #>
    $c = (Get-UiSection -Id 'printers').Controls
    $c.CmbPrinterModel.Items.Clear()
    $c.CmbPrinterModel.Text = ''
    if (-not $c.CmbPrinterInf.SelectedItem) { return }
    $models = @(Get-PrinterDriverModel -InfPath ([string]$c.CmbPrinterInf.SelectedItem.Tag))
    foreach ($model in $models) { [void]$c.CmbPrinterModel.Items.Add($model) }
    if ($models.Count -eq 1) { $c.CmbPrinterModel.SelectedIndex = 0 }
}

function Get-PrinterFromForm {
    $c = (Get-UiSection -Id 'printers').Controls
    $inf = if ($c.CmbPrinterInf.SelectedItem) { [string]$c.CmbPrinterInf.SelectedItem.Tag } else { '' }
    return (New-IpPrinterRequest -Name ([string]$c.TxtPrinterName.Text) -Address ([string]$c.TxtPrinterAddress.Text) -InfPath $inf -DriverName ([string]$c.CmbPrinterModel.Text))
}

function Get-PrinterFormError {
    $section = Get-UiSection -Id 'printers'
    return (Get-IpPrinterError -Printer (Get-PrinterFromForm) -ExistingName @($section.State.Printers | ForEach-Object { $_.Name }))
}

function Add-PrinterFromForm {
    $section = Get-UiSection -Id 'printers'
    $c = $section.Controls
    $problem = Get-PrinterFormError
    if ($problem) {
        $c.TxtPrinterHint.Text = 'À corriger : {0}' -f $problem
        $c.TxtPrinterHint.Foreground = Get-ThemeResource -Key 'ErrorBrush'
        return
    }
    $section.State.Printers.Add((Get-PrinterFromForm))
    # Le pilote et le modèle restent choisis : plusieurs imprimantes du même modèle se suivent souvent.
    $c.TxtPrinterName.Text = ''
    $c.TxtPrinterAddress.Text = ''
    Update-PrintersList
    Update-PrintersView
    Update-UiState
}

function Update-PrintersList {
    $section = Get-UiSection -Id 'printers'
    $panel = $section.Controls.PnlPrinters
    $panel.Children.Clear()
    foreach ($printer in $section.State.Printers) {
        $row = New-RemovableRow -Text (Format-IpPrinterSummary -Printer $printer) -Item $printer -OnRemove {
            param($item)
            [void](Get-UiSection -Id 'printers').State.Printers.Remove($item)
            Update-PrintersList
            Update-UiState
        }
        [void]$panel.Children.Add($row)
    }
    $section.Controls.TxtPrintersNone.Visibility = if ($section.State.Printers.Count -eq 0) { 'Visible' } else { 'Collapsed' }
}

function Update-PrintersView {
    <# Consigne sous le formulaire : le motif du refus dès qu'un nom est saisi. #>
    $section = Get-UiSection -Id 'printers'
    $c = $section.Controls
    $problem = if (([string]$c.TxtPrinterName.Text).Trim()) { Get-PrinterFormError } else { $null }
    if ($problem) {
        $c.TxtPrinterHint.Text = 'À corriger : {0}' -f $problem
        $c.TxtPrinterHint.Foreground = Get-ThemeResource -Key 'ErrorBrush'
    } else {
        $c.TxtPrinterHint.Text = $section.State.DefaultHint
        $c.TxtPrinterHint.Foreground = Get-ThemeResource -Key 'TextSecondaryBrush'
    }
}

function Set-PrinterList {
    <# Remplace la liste des imprimantes (chargement d'un profil entreprise). #>
    param([AllowEmptyCollection()][object[]]$Printer = @())
    $section = Get-UiSection -Id 'printers'
    $section.State.Printers.Clear()
    foreach ($item in @($Printer)) { $section.State.Printers.Add($item) }
    Update-PrintersList
}
