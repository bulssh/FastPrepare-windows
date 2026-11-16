<#
    Page « Analyse de disque » (hors parcours, lecture seule) : arborescence triée par taille,
    types de fichiers et carte des tailles (treemap), liés entre eux — même principe que les
    analyseurs de disque classiques, aux couleurs de l'outil.
    Affichage seulement : le parcours du disque et le modèle sont dans FastPrepare.Application
    (DiskUsage.ps1), les règles de mise en forme et le découpage dans FastPrepare.Core.
    L'analyse tourne en arrière-plan ; rien n'est modifié sur le poste, quel que soit le mode.
#>

Register-UiSection -Id 'disk-usage' -Number 110 -Page 'disque' -Column Left -XamlFile 'Sections\DiskUsage.xaml' -Initialize {
    param($Section, $Context)
    $c = $Section.Controls
    $state = $Section.State
    $state.Model = $null            # résultat de la dernière analyse
    $state.Treemap = $null          # découpage affiché
    $state.Progress = $null         # état partagé avec l'analyse en cours
    $state.Scanning = $false
    $state.Rows = @{}               # nœud → ligne affichée de l'arborescence
    $state.MoreRows = @{}           # dossier → ligne « autres éléments »
    $state.SelectedNode = -1
    $state.SelectedExtension = -1
    $state.Loading = $false         # sélection modifiée par le code : pas d'événement à traiter
    $state.ResizeTicks = 0          # battements restants avant de redessiner après un redimensionnement
    $state.HoverPoint = $null       # dernière position de la souris sur la carte, à traiter au battement

    foreach ($drive in @(Get-DiskUsageDrive)) {
        $item = [System.Windows.Controls.ComboBoxItem]::new()
        $label = if ($drive.Label) { ' {0}' -f $drive.Label } else { '' }
        $item.Content = '{0}{1} — {2} libres sur {3}' -f $drive.Name, $label, (Format-ByteSize -Bytes $drive.FreeBytes), (Format-ByteSize -Bytes $drive.TotalBytes)
        $item.Tag = $drive.Name
        [void]$c.CmbDiskTarget.Items.Add($item)
    }
    if ($c.CmbDiskTarget.Items.Count -gt 0) { $c.CmbDiskTarget.SelectedIndex = 0 }

    $c.BtnDiskScan.Add_Click({ Invoke-UiAction -Name 'analyse de disque' -Action { Start-DiskUsageView } })
    $c.BtnDiskStop.Add_Click({ Invoke-UiAction -Name 'arrêt de l''analyse' -Action { Stop-DiskUsageView } })
    $c.BtnDiskOpen.Add_Click({ Invoke-UiAction -Name 'ouverture dans l''Explorateur' -Action { Open-DiskUsageSelection } })
    $c.LstDiskTree.Add_SelectionChanged({ Invoke-UiAction -Name 'analyse de disque' -Action { Update-DiskTreeSelection } })
    $c.LstDiskExt.Add_SelectionChanged({ Invoke-UiAction -Name 'analyse de disque' -Action { Update-DiskExtensionSelection } })
    $c.GrdDiskMap.Add_SizeChanged({ (Get-DiskUsageSection).State.ResizeTicks = 2 })
    $c.GrdDiskMap.Add_MouseMove({
            param($source, $mouseArgs)
            (Get-DiskUsageSection).State.HoverPoint = $mouseArgs.GetPosition($source)
        })
    $c.GrdDiskMap.Add_MouseLeftButtonUp({
            param($source, $mouseArgs)
            $point = $mouseArgs.GetPosition($source)
            Invoke-UiAction -Name 'analyse de disque' -Action { Select-DiskMapPoint -X $point.X -Y $point.Y }
        })
    Register-UiTickHandler -Name 'analyse-disque' -ScriptBlock { Invoke-DiskUsageTick }
} -Dispose {
    param($Section)
    if ($Section.State.Progress) { $Section.State.Progress.Cancel = $true }
}

function Get-DiskUsageSection { return (Get-UiSection -Id 'disk-usage') }

function Get-DiskMapBrush {
    <# Pinceau d'une couleur de la carte : indice de palette, -1 « autres types », -2 dossier vide. #>
    param([int]$Color)
    if ($Color -eq -2) { return (Get-ThemeResource -Key 'DiskMapEmpty') }
    if ($Color -lt 0) { return (Get-ThemeResource -Key 'DiskMapOther') }
    return (Get-ThemeResource -Key ('DiskMap{0}' -f $Color))
}

function Start-DiskUsageView {
    <# Bouton Analyser : lance le parcours en arrière-plan ; l'avancement s'affiche à chaque battement. #>
    $section = Get-DiskUsageSection
    $c = $section.Controls
    $state = $section.State
    if ($state.Scanning) { return }
    $selected = $c.CmbDiskTarget.SelectedItem
    $path = if ($selected) { [string]$selected.Tag } else { ([string]$c.CmbDiskTarget.Text).Trim() }
    if (-not $path) {
        Set-DiskUsageStatus -Text 'Choisir un disque ou saisir le chemin d''un dossier.' -IsError
        return
    }
    $state.Progress = New-DiskUsageProgress
    $state.Scanning = $true
    $c.BtnDiskScan.IsEnabled = $false
    $c.BtnDiskStop.IsEnabled = $true
    $c.CmbDiskTarget.IsEnabled = $false
    $c.PbDisk.IsIndeterminate = $true
    $c.PbDisk.Visibility = 'Visible'
    Set-DiskUsageStatus -Text ('Analyse de {0}…' -f $path)

    try {
        # La taille de la carte est transmise : son premier découpage est calculé avec l'analyse, en arrière-plan.
        $work = Start-DiskUsageScan -Context $script:Context -Path $path -Progress $state.Progress `
            -MapWidth ([math]::Floor($c.GrdDiskMap.ActualWidth)) -MapHeight ([math]::Floor($c.GrdDiskMap.ActualHeight))
    } catch {
        Complete-DiskUsageScanState
        Set-DiskUsageStatus -Text $_.Exception.Message -IsError
        throw
    }
    Register-UiBackgroundWork -Work $work -OnCompleted {
        param($result)
        Complete-DiskUsageScanState
        Show-DiskUsageModel -Model (@($result)[-1])
    } -OnFailed {
        param($message)
        Complete-DiskUsageScanState
        Set-DiskUsageStatus -Text ('Analyse impossible : {0}' -f $message) -IsError
    }
}

function Stop-DiskUsageView {
    <# Bouton Arrêter : le parcours s'interrompt au dossier suivant ; ce qui a été lu est affiché. #>
    $state = (Get-DiskUsageSection).State
    if ($state.Scanning -and $state.Progress) {
        $state.Progress.Cancel = $true
        Set-DiskUsageStatus -Text 'Arrêt demandé…'
    }
}

function Complete-DiskUsageScanState {
    <# Fin d'une analyse (réussie, interrompue ou en erreur) : commandes de nouveau disponibles. #>
    $section = Get-DiskUsageSection
    $c = $section.Controls
    $section.State.Scanning = $false
    $c.BtnDiskScan.IsEnabled = $true
    $c.BtnDiskStop.IsEnabled = $false
    $c.CmbDiskTarget.IsEnabled = $true
    $c.PbDisk.IsIndeterminate = $false
    $c.PbDisk.Visibility = 'Hidden'
}

function Set-DiskUsageStatus {
    param([string]$Text, [switch]$IsError)
    $status = (Get-DiskUsageSection).Controls.TxtDiskStatus
    $status.Text = $Text
    $status.Foreground = Get-ThemeResource -Key $(if ($IsError) { 'ErrorBrush' } else { 'TextSecondaryBrush' })
}

function Invoke-DiskUsageTick {
    <# À chaque battement : avancement de l'analyse, redessin après redimensionnement, survol de la carte. #>
    $section = Get-DiskUsageSection
    $state = $section.State
    if ($state.Scanning -and $state.Progress) {
        $progress = $state.Progress
        if (-not $progress.Cancel) {
            Set-DiskUsageStatus -Text ('{0:n0} fichiers · {1} · {2}' -f $progress.Files, (Format-ByteSize -Bytes $progress.Bytes), $progress.Path)
        }
        return
    }
    if (-not $state.Model) { return }
    if ($state.ResizeTicks -gt 0) {
        $state.ResizeTicks--
        if ($state.ResizeTicks -eq 0) { Update-DiskUsageMap }
    }
    if ($state.HoverPoint) {
        $point = $state.HoverPoint
        $state.HoverPoint = $null
        $rect = Find-DiskUsageTreemapRect -Treemap $state.Treemap -X $point.X -Y $point.Y
        if ($rect -ge 0) {
            $node = $state.Treemap.Node[$rect]
            $section.Controls.TxtDiskHover.Text = '{0} — {1}' -f (Format-DiskNodeLocation -Node $node), (Format-ByteSize -Bytes $state.Model.Size[$node])
        }
    }
}

function Format-DiskNodeLocation {
    <# Emplacement lisible d'un nœud : chemin, suivi du libellé pour un groupe de fichiers. #>
    param([int]$Node)
    $model = (Get-DiskUsageSection).State.Model
    $path = Get-DiskUsageNodePath -Model $model -Index $Node
    if ($model.Kind[$Node] -eq 2) { return ('{0}  ·  {1}' -f $path, (Get-DiskUsageNodeLabel -Model $model -Index $Node)) }
    return $path
}

function Show-DiskUsageModel {
    <# Analyse terminée : remplit l'arborescence, les types de fichiers et la carte. #>
    param($Model)
    $section = Get-DiskUsageSection
    $c = $section.Controls
    $state = $section.State
    $state.Model = $Model
    $state.Treemap = $null
    $state.Rows = @{}
    $state.MoreRows = @{}
    $state.SelectedNode = -1
    $state.SelectedExtension = -1

    $state.Loading = $true
    try {
        $c.LstDiskTree.Items.Clear()
        $c.LstDiskExt.Items.Clear()
        $root = New-DiskTreeRow -Node 0 -Depth 0
        [void]$c.LstDiskTree.Items.Add($root)
        $state.Rows[0] = $root
        Expand-DiskTreeRow -Item $root

        # Les types les plus volumineux ; un disque en compte souvent plus d'un millier.
        $total = [double]$Model.Bytes
        $shown = [math]::Min($Model.ExtensionOrder.Length, 80)
        for ($k = 0; $k -lt $shown; $k++) {
            [void]$c.LstDiskExt.Items.Add((New-DiskExtensionRow -Extension $Model.ExtensionOrder[$k] -Total $total))
        }
        if ($Model.ExtensionOrder.Length -gt $shown) {
            $note = [System.Windows.Controls.ListBoxItem]::new()
            $note.Content = '… et {0:n0} autres types, plus petits' -f ($Model.ExtensionOrder.Length - $shown)
            $note.Padding = [System.Windows.Thickness]::new(8, 3, 8, 3)
            $note.FontStyle = [System.Windows.FontStyles]::Italic
            $note.Foreground = Get-ThemeResource -Key 'TextSecondaryBrush'
            $note.IsEnabled = $false
            $note.Tag = -1
            [void]$c.LstDiskExt.Items.Add($note)
        }
    } finally {
        $state.Loading = $false
    }
    $c.BtnDiskOpen.IsEnabled = $false
    $c.TxtDiskHover.Text = 'Survoler la carte pour identifier une tuile ; cliquer pour la retrouver dans l''arborescence.'
    $c.TxtDiskMapEmpty.Visibility = 'Collapsed'
    Update-DiskUsageMap

    $summary = '{0} : {1} dans {2:n0} fichier(s) et {3:n0} dossier(s), en {4:n1} s' -f $Model.Root, (Format-ByteSize -Bytes $Model.Bytes), $Model.Files, $Model.Directories, $Model.Seconds
    if ($Model.Cancelled) { $summary = 'Analyse interrompue (résultat partiel) — ' + $summary }
    if ($Model.Inaccessible -gt 0) { $summary += ' · {0:n0} dossier(s) illisible(s) non compté(s)' -f $Model.Inaccessible }
    Set-DiskUsageStatus -Text $summary
}

function New-DiskTreeCell {
    <# Cellule de texte alignée à droite (taille, nombre de fichiers, pourcentage). #>
    param([string]$Text, [int]$Column)
    $block = [System.Windows.Controls.TextBlock]::new()
    $block.Text = $Text
    $block.TextAlignment = [System.Windows.TextAlignment]::Right
    $block.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    [System.Windows.Controls.Grid]::SetColumn($block, $Column)
    return $block
}

function New-DiskRowGrid {
    <# Grille d'une ligne : colonne de nom extensible, puis colonnes de largeur fixe. #>
    param([double[]]$Width)
    $grid = [System.Windows.Controls.Grid]::new()
    $column = [System.Windows.Controls.ColumnDefinition]::new()
    $column.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $grid.ColumnDefinitions.Add($column)
    foreach ($value in $Width) {
        $column = [System.Windows.Controls.ColumnDefinition]::new()
        $column.Width = [System.Windows.GridLength]::new($value)
        $grid.ColumnDefinitions.Add($column)
    }
    return $grid
}

function New-DiskSwatch {
    <# Pastille de la couleur d'un type de fichier. #>
    param([int]$Color)
    $swatch = [System.Windows.Controls.Border]::new()
    $swatch.Width = 11
    $swatch.Height = 11
    $swatch.CornerRadius = [System.Windows.CornerRadius]::new(2)
    $swatch.Margin = [System.Windows.Thickness]::new(0, 0, 7, 0)
    $swatch.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $swatch.Background = Get-DiskMapBrush -Color $Color
    return $swatch
}

function New-DiskTreeRow {
    <#
        Ligne de l'arborescence pour un nœud : flèche de dépliage (dossier), pastille de couleur
        (fichier ou groupe), nom, part du dossier parent, taille, nombre de fichiers.
        La ligne porte dans Tag { Node, Depth, Expanded, Toggle }.
    #>
    param([int]$Node, [int]$Depth)
    $model = (Get-DiskUsageSection).State.Model
    $kind = $model.Kind[$Node]
    $size = [double]$model.Size[$Node]
    $parentSize = if ($Node -gt 0) { [double]$model.Size[$model.Parent[$Node]] } else { $size }

    $grid = New-DiskRowGrid -Width @(70, 56, 80, 70)
    $name = [System.Windows.Controls.StackPanel]::new()
    $name.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $name.Margin = [System.Windows.Thickness]::new(11 * $Depth, 0, 8, 0)

    $toggle = [System.Windows.Controls.TextBlock]::new()
    $toggle.Width = 16
    $toggle.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $toggle.Foreground = Get-ThemeResource -Key 'TextSecondaryBrush'
    $expandable = ($kind -eq 0) -and $model.ChildCount[$Node] -gt 0
    if ($expandable) {
        $toggle.Text = '▸'
        $toggle.Cursor = [System.Windows.Input.Cursors]::Hand
    }
    [void]$name.Children.Add($toggle)
    if ($kind -ne 0) { [void]$name.Children.Add((New-DiskSwatch -Color $model.ExtensionColor[$model.Extension[$Node]])) }

    $label = [System.Windows.Controls.TextBlock]::new()
    $label.Text = Get-DiskUsageNodeLabel -Model $model -Index $Node
    $label.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
    $label.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    if ($kind -eq 0) { $label.FontWeight = [System.Windows.FontWeights]::SemiBold }
    elseif ($kind -eq 2) { $label.Foreground = Get-ThemeResource -Key 'TextSecondaryBrush' }
    [void]$name.Children.Add($label)
    [void]$grid.Children.Add($name)

    # Barre : part du dossier parent.
    $share = if ($parentSize -gt 0) { $size / $parentSize } else { 0 }
    $track = [System.Windows.Controls.Border]::new()
    $track.Height = 8
    $track.Width = 62
    $track.CornerRadius = [System.Windows.CornerRadius]::new(4)
    $track.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
    $track.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $track.Background = Get-ThemeResource -Key 'DiskBarTrackBrush'
    $bar = [System.Windows.Controls.Border]::new()
    $bar.Width = [math]::Max(0, [math]::Min(62, 62 * $share))
    $bar.CornerRadius = [System.Windows.CornerRadius]::new(4)
    $bar.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
    $bar.Background = Get-ThemeResource -Key 'DiskBarBrush'
    $track.Child = $bar
    [System.Windows.Controls.Grid]::SetColumn($track, 1)
    [void]$grid.Children.Add($track)
    [void]$grid.Children.Add((New-DiskTreeCell -Text (Format-DiskUsagePercent -Part $size -Total $parentSize) -Column 2))
    [void]$grid.Children.Add((New-DiskTreeCell -Text (Format-ByteSize -Bytes $size) -Column 3))
    [void]$grid.Children.Add((New-DiskTreeCell -Text ('{0:n0}' -f $model.Count[$Node]) -Column 4))

    $item = [System.Windows.Controls.ListBoxItem]::new()
    $item.Content = $grid
    $item.Padding = [System.Windows.Thickness]::new(8, 3, 8, 3)
    # Nom complet en info-bulle : en profondeur, la colonne du nom devient étroite.
    $item.ToolTip = $label.Text
    $item.Tag = [pscustomobject]@{ Node = $Node; Depth = $Depth; Expanded = $false; Toggle = $toggle; Expandable = $expandable }
    if ($expandable) {
        # La flèche retrouve sa ligne par Tag : aucune fermeture à conserver.
        $toggle.Tag = $item
        $toggle.Add_MouseLeftButtonDown({
                param($source, $mouseArgs)
                $mouseArgs.Handled = $true
                Invoke-UiAction -Name 'analyse de disque' -Action { Switch-DiskTreeRow -Item $source.Tag }
            })
        $item.Add_MouseDoubleClick({
                param($source, $mouseArgs)
                Invoke-UiAction -Name 'analyse de disque' -Action { Switch-DiskTreeRow -Item $source }
            })
    }
    return $item
}

function New-DiskMoreRow {
    <# Ligne « autres éléments » : ce qui dépasse la limite d'affichage d'un dossier. #>
    param([int]$Parent, [int]$Depth, [int]$Count, [double]$Size)
    $grid = New-DiskRowGrid -Width @(70, 56, 80, 70)
    $label = [System.Windows.Controls.TextBlock]::new()
    $label.Text = '… {0:n0} autres éléments plus petits' -f $Count
    $label.Margin = [System.Windows.Thickness]::new(11 * $Depth + 16, 0, 8, 0)
    $label.FontStyle = [System.Windows.FontStyles]::Italic
    $label.Foreground = Get-ThemeResource -Key 'TextSecondaryBrush'
    [void]$grid.Children.Add($label)
    [void]$grid.Children.Add((New-DiskTreeCell -Text (Format-ByteSize -Bytes $Size) -Column 3))
    $item = [System.Windows.Controls.ListBoxItem]::new()
    $item.Content = $grid
    $item.Padding = [System.Windows.Thickness]::new(8, 3, 8, 3)
    $item.Tag = [pscustomobject]@{ Node = $Parent; Depth = $Depth; Expanded = $false; Toggle = $null; Expandable = $false; More = $true }
    return $item
}

function Switch-DiskTreeRow {
    param($Item)
    if (-not $Item.Tag.Expandable) { return }
    if ($Item.Tag.Expanded) { Close-DiskTreeRow -Item $Item } else { Expand-DiskTreeRow -Item $Item }
}

function Expand-DiskTreeRow {
    <# Déplie un dossier : ses enfants, du plus gros au plus petit, sont insérés sous sa ligne (200 au plus). #>
    param($Item, [int]$Limit = 200)
    $info = $Item.Tag
    if (-not $info.Expandable -or $info.Expanded) { return }
    $section = Get-DiskUsageSection
    $state = $section.State
    $list = $section.Controls.LstDiskTree
    $model = $state.Model
    $children = Get-DiskUsageChild -Model $model -Index $info.Node
    $position = $list.Items.IndexOf($Item) + 1
    $shown = [math]::Min($children.Length, $Limit)
    for ($k = 0; $k -lt $shown; $k++) {
        $row = New-DiskTreeRow -Node $children[$k] -Depth ($info.Depth + 1)
        $list.Items.Insert($position + $k, $row)
        $state.Rows[$children[$k]] = $row
    }
    if ($children.Length -gt $shown) {
        $rest = 0.0
        for ($k = $shown; $k -lt $children.Length; $k++) { $rest += $model.Size[$children[$k]] }
        $more = New-DiskMoreRow -Parent $info.Node -Depth ($info.Depth + 1) -Count ($children.Length - $shown) -Size $rest
        $list.Items.Insert($position + $shown, $more)
        $state.MoreRows[$info.Node] = $more
    }
    $info.Expanded = $true
    $info.Toggle.Text = '▾'
}

function Close-DiskTreeRow {
    <# Replie un dossier : retire toutes les lignes de sa descendance. #>
    param($Item)
    $info = $Item.Tag
    if (-not $info.Expanded) { return }
    $section = Get-DiskUsageSection
    $state = $section.State
    $list = $section.Controls.LstDiskTree
    $position = $list.Items.IndexOf($Item) + 1
    while ($position -lt $list.Items.Count -and $list.Items[$position].Tag.Depth -gt $info.Depth) {
        $row = $list.Items[$position]
        if ($row.Tag.PSObject.Properties['More']) { $state.MoreRows.Remove($row.Tag.Node) }
        else { $state.Rows.Remove($row.Tag.Node) }
        $list.Items.RemoveAt($position)
    }
    $info.Expanded = $false
    $info.Toggle.Text = '▸'
}

function New-DiskExtensionRow {
    <# Ligne d'un type de fichier : couleur, extension, part du total, taille, nombre de fichiers. #>
    param([int]$Extension, [double]$Total)
    $model = (Get-DiskUsageSection).State.Model
    $bytes = [double]$model.ExtensionBytes[$Extension]
    $grid = New-DiskRowGrid -Width @(58, 72, 64)
    $name = [System.Windows.Controls.StackPanel]::new()
    $name.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    [void]$name.Children.Add((New-DiskSwatch -Color $model.ExtensionColor[$Extension]))
    $label = [System.Windows.Controls.TextBlock]::new()
    $label.Text = Get-DiskUsageExtensionLabel -Extension $model.ExtensionName[$Extension]
    $label.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
    [void]$name.Children.Add($label)
    [void]$grid.Children.Add($name)
    [void]$grid.Children.Add((New-DiskTreeCell -Text (Format-DiskUsagePercent -Part $bytes -Total $Total) -Column 1))
    [void]$grid.Children.Add((New-DiskTreeCell -Text (Format-ByteSize -Bytes $bytes) -Column 2))
    [void]$grid.Children.Add((New-DiskTreeCell -Text ('{0:n0}' -f $model.ExtensionFiles[$Extension]) -Column 3))
    $item = [System.Windows.Controls.ListBoxItem]::new()
    $item.Content = $grid
    $item.Padding = [System.Windows.Thickness]::new(8, 3, 8, 3)
    $item.Tag = $Extension
    return $item
}

function Update-DiskTreeSelection {
    <# Une ligne de l'arborescence est sélectionnée : elle est entourée sur la carte. #>
    $section = Get-DiskUsageSection
    $state = $section.State
    if ($state.Loading -or -not $state.Model) { return }
    $item = $section.Controls.LstDiskTree.SelectedItem
    $state.SelectedNode = if ($item) { [int]$item.Tag.Node } else { -1 }
    $section.Controls.BtnDiskOpen.IsEnabled = ($state.SelectedNode -ge 0)
    if ($state.SelectedNode -ge 0) {
        $section.Controls.TxtDiskHover.Text = '{0} — {1}' -f (Format-DiskNodeLocation -Node $state.SelectedNode), (Format-ByteSize -Bytes $state.Model.Size[$state.SelectedNode])
    }
    Update-DiskUsageOverlay
}

function Update-DiskExtensionSelection {
    <# Un type de fichier est sélectionné : toutes ses tuiles sont entourées sur la carte. #>
    $section = Get-DiskUsageSection
    $state = $section.State
    if ($state.Loading -or -not $state.Model) { return }
    $item = $section.Controls.LstDiskExt.SelectedItem
    $state.SelectedExtension = if ($item) { [int]$item.Tag } else { -1 }
    Update-DiskUsageOverlay
}

function Select-DiskMapPoint {
    <# Clic sur la carte : la tuile est retrouvée dans l'arborescence (dossiers dépliés jusqu'à elle). #>
    param([double]$X, [double]$Y)
    $state = (Get-DiskUsageSection).State
    if (-not $state.Treemap) { return }
    $rect = Find-DiskUsageTreemapRect -Treemap $state.Treemap -X $X -Y $Y
    if ($rect -lt 0) { return }
    Select-DiskTreeNode -Node $state.Treemap.Node[$rect]
}

function Select-DiskTreeNode {
    <#
        Sélectionne un nœud dans l'arborescence en dépliant ses dossiers parents. Un nœud au-delà
        de la limite d'affichage de son dossier sélectionne la ligne « autres éléments ».
    #>
    param([int]$Node)
    $section = Get-DiskUsageSection
    $state = $section.State
    $list = $section.Controls.LstDiskTree
    $model = $state.Model
    $chain = New-Object 'System.Collections.Generic.List[int]'
    for ($cursor = $Node; $cursor -ge 0; $cursor = $model.Parent[$cursor]) { $chain.Add($cursor) }
    $target = $null
    for ($k = $chain.Count - 1; $k -ge 0; $k--) {
        $row = $state.Rows[$chain[$k]]
        if (-not $row) {
            # Au-delà de la limite d'affichage du dossier parent.
            $target = $state.MoreRows[$model.Parent[$chain[$k]]]
            break
        }
        $target = $row
        if ($k -gt 0) { Expand-DiskTreeRow -Item $row }
    }
    if (-not $target) { return }
    $list.SelectedItem = $target
    $list.ScrollIntoView($target)
}

function Open-DiskUsageSelection {
    <# Bouton « Ouvrir dans l'Explorateur » : dossier ouvert, ou fichier sélectionné dans son dossier. #>
    $state = (Get-DiskUsageSection).State
    if (-not $state.Model -or $state.SelectedNode -lt 0) { return }
    Open-DiskUsageLocation -Model $state.Model -Index $state.SelectedNode -Log $script:Context.Log
}

function Update-DiskUsageMap {
    <# Recalcule le découpage à la taille actuelle de la carte et la redessine. #>
    $section = Get-DiskUsageSection
    $c = $section.Controls
    $state = $section.State
    if (-not $state.Model) { return }
    $width = [math]::Floor($c.GrdDiskMap.ActualWidth)
    $height = [math]::Floor($c.GrdDiskMap.ActualHeight)
    if ($width -lt 20 -or $height -lt 20) {
        # Page pas encore affichée (taille inconnue) : dessin au prochain redimensionnement.
        return
    }
    # Découpage déjà calculé avec l'analyse si la carte n'a pas changé de taille depuis.
    $treemap = $state.Model.Treemap
    if (-not $treemap -or $treemap.Width -ne $width -or $treemap.Height -ne $height) {
        $treemap = New-DiskUsageTreemap -Model $state.Model -Width $width -Height $height
    }
    $state.Treemap = $treemap

    $group = [System.Windows.Media.DrawingGroup]::new()
    $drawing = $group.Open()
    try {
        # Rectangle transparent : l'image garde exactement la taille de la carte.
        $drawing.DrawRectangle([System.Windows.Media.Brushes]::Transparent, $null, [System.Windows.Rect]::new(0, 0, $width, $height))
        $xs = $treemap.X; $ys = $treemap.Y; $ws = $treemap.W; $hs = $treemap.H; $leaf = $treemap.Leaf; $colors = $treemap.Color
        $brushes = @{}
        for ($r = 0; $r -lt $treemap.Count; $r++) {
            if (-not $leaf[$r]) { continue }
            $w = $ws[$r] - 1
            $h = $hs[$r] - 1
            if ($w -lt 0.5) { $w = 0.5 }
            if ($h -lt 0.5) { $h = 0.5 }
            $color = $colors[$r]
            $brush = $brushes[$color]
            if (-not $brush) { $brush = Get-DiskMapBrush -Color $color; $brushes[$color] = $brush }
            $drawing.DrawRectangle($brush, $null, [System.Windows.Rect]::new($xs[$r], $ys[$r], $w, $h))
        }
    } finally {
        $drawing.Close()
    }
    $group.Freeze()
    $c.ImgDiskMap.Source = [System.Windows.Media.DrawingImage]::new($group)
    Update-DiskUsageOverlay
}

function Update-DiskUsageOverlay {
    <# Surbrillance sur la carte : tuiles du type de fichier sélectionné, contour du nœud sélectionné. #>
    $section = Get-DiskUsageSection
    $c = $section.Controls
    $state = $section.State
    $treemap = $state.Treemap
    if (-not $treemap) { $c.ImgDiskOverlay.Source = $null; return }
    $model = $state.Model
    $highlight = Get-ThemeResource -Key 'DiskMapHighlightBrush'
    $thin = [System.Windows.Media.Pen]::new($highlight, 1)
    $thick = [System.Windows.Media.Pen]::new($highlight, 2.5)

    $group = [System.Windows.Media.DrawingGroup]::new()
    $drawing = $group.Open()
    try {
        $drawing.DrawRectangle([System.Windows.Media.Brushes]::Transparent, $null, [System.Windows.Rect]::new(0, 0, $treemap.Width, $treemap.Height))
        if ($state.SelectedExtension -ge 0) {
            for ($r = 0; $r -lt $treemap.Count; $r++) {
                if (-not $treemap.Leaf[$r]) { continue }
                $node = $treemap.Node[$r]
                if ($model.Extension[$node] -ne $state.SelectedExtension) { continue }
                if ($treemap.W[$r] -lt 2 -or $treemap.H[$r] -lt 2) { continue }
                $drawing.DrawRectangle($null, $thin, [System.Windows.Rect]::new($treemap.X[$r] + 0.5, $treemap.Y[$r] + 0.5, $treemap.W[$r] - 2, $treemap.H[$r] - 2))
            }
        }
        # Nœud sélectionné : sa tuile, ou celle du premier dossier parent dessiné.
        $rect = -1
        for ($cursor = $state.SelectedNode; $cursor -ge 0; $cursor = $model.Parent[$cursor]) {
            if ($treemap.RectOfNode.TryGetValue($cursor, [ref]$rect)) { break }
            $rect = -1
        }
        if ($rect -ge 0) {
            $w = [math]::Max(2, $treemap.W[$rect] - 2)
            $h = [math]::Max(2, $treemap.H[$rect] - 2)
            $drawing.DrawRectangle($null, $thick, [System.Windows.Rect]::new($treemap.X[$rect] + 0.5, $treemap.Y[$rect] + 0.5, $w, $h))
        }
    } finally {
        $drawing.Close()
    }
    $group.Freeze()
    $c.ImgDiskOverlay.Source = [System.Windows.Media.DrawingImage]::new($group)
}
