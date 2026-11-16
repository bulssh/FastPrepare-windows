<#
    Analyse de disque (page hors parcours) : modèle affiché par la section « Analyse de disque ».
    Lecture seule : rien n'est modifié sur le poste, en simulation comme en mode réel.
    Le parcours est fait par FastPrepare.Infrastructure (Read-DiskUsage), les règles de mise en
    forme et le découpage du treemap par FastPrepare.Core. Aucun type WPF ici.
#>

function Get-DiskUsageDrive {
    <# Disques proposés à l'analyse : { Name, Label, TotalBytes, FreeBytes }. #>
    [CmdletBinding()]
    param()
    return @(Get-FixedDrive)
}

function New-DiskUsageProgress {
    <# État partagé entre l'analyse (arrière-plan) et la fenêtre : avancement et demande d'arrêt. #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Construit un objet en mémoire, ne modifie pas le poste.')]
    param()
    return [hashtable]::Synchronized(@{ Files = 0; Bytes = [long]0; Path = ''; Cancel = $false })
}

function Get-DiskUsage {
    <#
        Analyse -Path et renvoie le modèle complet : l'arbre de Read-DiskUsage, plus
          ChildCache     : enfants triés des dossiers déjà consultés (Get-DiskUsageChild) ;
          ExtensionOrder : indices des extensions, de la plus volumineuse à la moins volumineuse ;
          ExtensionColor : couleur de chaque extension (indice de palette, -1 = « autres »).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        $Progress,
        $Log,
        # Taille à partir de laquelle un fichier a sa propre ligne et sa propre tuile.
        [long]$LargeFileBytes = 1MB,
        # Taille de la carte affichée : le premier découpage est alors calculé ici (Treemap), hors du fil de l'interface.
        [double]$MapWidth = 0,
        [double]$MapHeight = 0
    )
    $model = Read-DiskUsage -Path $Path -Progress $Progress -LargeFileBytes $LargeFileBytes
    $extensionCount = $model.ExtensionName.Count
    $order = New-Object 'int[]' $extensionCount
    $orderKeys = New-Object 'long[]' $extensionCount
    for ($k = 0; $k -lt $extensionCount; $k++) { $order[$k] = $k; $orderKeys[$k] = - $model.ExtensionBytes[$k] }
    [System.Array]::Sort($orderKeys, $order)
    $colors = New-Object 'int[]' $extensionCount
    for ($rank = 0; $rank -lt $extensionCount; $rank++) { $colors[$order[$rank]] = Get-DiskUsageColorIndex -Rank $rank }

    $model | Add-Member -NotePropertyName ChildCache -NotePropertyValue (New-Object 'System.Collections.Generic.Dictionary[int,int[]]')
    $model | Add-Member -NotePropertyName ExtensionOrder -NotePropertyValue $order
    $model | Add-Member -NotePropertyName ExtensionColor -NotePropertyValue $colors
    $treemap = $null
    if ($MapWidth -gt 0 -and $MapHeight -gt 0) { $treemap = New-DiskUsageTreemap -Model $model -Width $MapWidth -Height $MapHeight }
    $model | Add-Member -NotePropertyName Treemap -NotePropertyValue $treemap

    if ($Log) {
        $state = if ($model.Cancelled) { 'interrompue' } else { 'terminée' }
        $message = 'Analyse de disque {0} : {1} — {2:n0} fichier(s), {3:n0} dossier(s), {4} en {5:n1} s' -f $state, $model.Root, $model.Files, $model.Directories, (Format-ByteSize -Bytes $model.Bytes), $model.Seconds
        if ($model.Inaccessible -gt 0) { $message += ' ; {0:n0} dossier(s) illisible(s) non compté(s)' -f $model.Inaccessible }
        Write-RunLog -Log $Log -Level $(if ($model.Cancelled) { 'ATTN' } else { 'OK' }) -Message $message
    }
    return $model
}

function Get-DiskUsageChild {
    <#
        Enfants d'un dossier, du plus gros au plus petit (tableau d'indices de nœuds). Triés à la
        première demande puis gardés : seuls les dossiers dépliés ou dessinés le sont, pas les
        dizaines de milliers de dossiers d'un disque.
        Fonction simple (sans CmdletBinding) : appelée pour chaque dossier dessiné.
    #>
    [OutputType([int[]])]
    param($Model, [int]$Index)
    $cache = $Model.ChildCache
    if ($cache.ContainsKey($Index)) { return , $cache[$Index] }
    $count = $Model.ChildCount[$Index]
    $items = New-Object 'int[]' $count
    if ($count -gt 0) {
        $start = $Model.ChildStart[$Index]
        $sizes = $Model.Size
        $keys = New-Object 'long[]' $count
        for ($k = 0; $k -lt $count; $k++) {
            $items[$k] = $start + $k
            $keys[$k] = - $sizes[$start + $k]
        }
        if ($count -gt 1) { [System.Array]::Sort($keys, $items) }
    }
    $cache[$Index] = $items
    return , $items
}

function Start-DiskUsageScan {
    <# Lance Get-DiskUsage dans un runspace : la fenêtre reste réactive et suit -Progress. #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Lecture seule du disque.')]
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Progress,
        [double]$MapWidth = 0,
        [double]$MapHeight = 0
    )
    return Start-BackgroundWork -Name 'analyse-disque' -ModulePath $Context.ModulePaths -Argument @($Path, $Progress, $Context.Log, $MapWidth, $MapHeight) -ScriptBlock {
        param([string]$Path, $Progress, $Log, [double]$MapWidth, [double]$MapHeight)
        Get-DiskUsage -Path $Path -Progress $Progress -Log $Log -MapWidth $MapWidth -MapHeight $MapHeight
    }
}

function Get-DiskUsageNodePath {
    <# Chemin complet d'un nœud ; pour un groupe de fichiers, le dossier qui les contient. #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)]$Model, [Parameter(Mandatory)][int]$Index)
    $node = $Index
    if ($Model.Kind[$node] -eq 2) { $node = $Model.Parent[$node] }
    $parts = New-Object 'System.Collections.Generic.List[string]'
    while ($node -gt 0) {
        $parts.Add($Model.Name[$node])
        $node = $Model.Parent[$node]
    }
    $path = [string]$Model.Root
    for ($k = $parts.Count - 1; $k -ge 0; $k--) { $path = [System.IO.Path]::Combine($path, $parts[$k]) }
    return $path
}

function Get-DiskUsageNodeLabel {
    <# Nom affiché d'un nœud : nom du dossier ou du fichier, « 12 fichiers .dll » pour un groupe. #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)]$Model, [Parameter(Mandatory)][int]$Index)
    if ($Model.Kind[$Index] -ne 2) { return [string]$Model.Name[$Index] }
    $count = $Model.Count[$Index]
    $label = Get-DiskUsageExtensionLabel -Extension $Model.ExtensionName[$Model.Extension[$Index]]
    if ($count -le 1) { return ('1 fichier {0}' -f $label) }
    return ('{0:n0} fichiers {1}' -f $count, $label)
}

function New-DiskUsageTreemap {
    <#
        Découpe le rectangle -Width × -Height selon l'arbre : chaque dossier est partagé entre ses
        enfants (Get-TreemapLayout), jusqu'aux fichiers. Un dossier trop petit pour être détaillé
        (côté inférieur à -MinSide) est dessiné d'un bloc, de la couleur de son plus gros contenu.
        Renvoie { Width, Height, Count, X, Y, W, H, Node, Leaf, Color, RectOfNode } ; Color est
        l'indice de palette de l'extension (-1 « autres », -2 dossier vide).
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Calcul en mémoire.')]
    param(
        [Parameter(Mandatory)]$Model,
        [Parameter(Mandatory)][double]$Width,
        [Parameter(Mandatory)][double]$Height,
        [double]$MinSide = 5
    )
    $xs = New-Object 'System.Collections.Generic.List[double]'
    $ys = New-Object 'System.Collections.Generic.List[double]'
    $ws = New-Object 'System.Collections.Generic.List[double]'
    $hs = New-Object 'System.Collections.Generic.List[double]'
    $nodes = New-Object 'System.Collections.Generic.List[int]'
    $leaves = New-Object 'System.Collections.Generic.List[bool]'
    $colors = New-Object 'System.Collections.Generic.List[int]'
    $rectOfNode = New-Object 'System.Collections.Generic.Dictionary[int,int]'

    $pendingNode = New-Object 'System.Collections.Generic.Stack[int]'
    $pendingBox = New-Object 'System.Collections.Generic.Stack[double]'
    if ($Width -gt 0 -and $Height -gt 0 -and $Model.Size[0] -gt 0) {
        $pendingNode.Push(0)
        $pendingBox.Push($Height); $pendingBox.Push($Width); $pendingBox.Push(0); $pendingBox.Push(0)
    }
    # Tableaux du modèle en variables locales : la boucle les lit des milliers de fois.
    $kinds = $Model.Kind
    $nodeSizes = $Model.Size
    $childCounts = $Model.ChildCount
    $largest = $Model.Largest
    $nodeExtension = $Model.Extension
    $extensionColor = $Model.ExtensionColor
    while ($pendingNode.Count -gt 0) {
        $node = $pendingNode.Pop()
        $x = $pendingBox.Pop(); $y = $pendingBox.Pop(); $w = $pendingBox.Pop(); $h = $pendingBox.Pop()
        $rectOfNode[$node] = $nodes.Count
        $xs.Add($x); $ys.Add($y); $ws.Add($w); $hs.Add($h); $nodes.Add($node)

        $hasChildren = ($kinds[$node] -eq 0) -and $childCounts[$node] -gt 0
        if (-not $hasChildren -or $w -lt $MinSide -or $h -lt $MinSide) {
            $leaves.Add($true)
            # Couleur : l'extension du nœud, ou celle du plus gros contenu d'un dossier non détaillé.
            $probe = $node
            while ($probe -ge 0 -and $kinds[$probe] -eq 0) { $probe = $largest[$probe] }
            if ($probe -lt 0) { $colors.Add(-2) } else { $colors.Add($extensionColor[$nodeExtension[$probe]]) }
            continue
        }
        $leaves.Add($false)
        $colors.Add(-2)

        $items = Get-DiskUsageChild -Model $Model -Index $node
        $sizes = New-Object 'double[]' $items.Length
        for ($k = 0; $k -lt $items.Length; $k++) { $sizes[$k] = $nodeSizes[$items[$k]] }
        $layout = Get-TreemapLayout -Size $sizes -X $x -Y $y -Width $w -Height $h
        for ($k = 0; $k -lt $items.Length; $k++) {
            $base = 4 * $k
            $childWidth = $layout[$base + 2]
            $childHeight = $layout[$base + 3]
            # Tri décroissant : dès qu'une tuile passe sous le pixel, les suivantes aussi.
            if ($childWidth * $childHeight -lt 1) { break }
            $pendingNode.Push($items[$k])
            $pendingBox.Push($childHeight); $pendingBox.Push($childWidth); $pendingBox.Push($layout[$base + 1]); $pendingBox.Push($layout[$base])
        }
    }

    return [pscustomobject]@{
        PSTypeName = 'FastPrepare.DiskUsageTreemap'
        Width      = $Width
        Height     = $Height
        Count      = $nodes.Count
        X          = $xs.ToArray()
        Y          = $ys.ToArray()
        W          = $ws.ToArray()
        H          = $hs.ToArray()
        Node       = $nodes.ToArray()
        Leaf       = $leaves.ToArray()
        Color      = $colors.ToArray()
        RectOfNode = $rectOfNode
    }
}

function Find-DiskUsageTreemapRect {
    <# Indice de la tuile (feuille) sous le point (X, Y) du treemap, ou -1. #>
    [OutputType([int])]
    param($Treemap, [double]$X, [double]$Y)
    if (-not $Treemap) { return -1 }
    $xs = $Treemap.X; $ys = $Treemap.Y; $ws = $Treemap.W; $hs = $Treemap.H; $leaf = $Treemap.Leaf
    for ($r = 0; $r -lt $Treemap.Count; $r++) {
        if (-not $leaf[$r]) { continue }
        if ($X -ge $xs[$r] -and $Y -ge $ys[$r] -and $X -lt $xs[$r] + $ws[$r] -and $Y -lt $ys[$r] + $hs[$r]) { return $r }
    }
    return -1
}

function Open-DiskUsageLocation {
    <# Ouvre l'Explorateur de fichiers sur le nœud (dossier ouvert, fichier sélectionné). #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Model, [Parameter(Mandatory)][int]$Index, $Log)
    Show-PathInExplorer -Path (Get-DiskUsageNodePath -Model $Model -Index $Index) -Log $Log
}
