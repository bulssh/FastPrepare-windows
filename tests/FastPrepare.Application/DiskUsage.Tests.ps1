<#
    Analyse de disque : parcours (lecture seule, sur un dossier de test créé pour l'occasion),
    modèle et découpage du treemap. Aucun disque du poste n'est parcouru.
#>
BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core, Infrastructure, Application

    function New-TestFile {
        param([string]$Path, [int]$Bytes)
        $folder = Split-Path -Parent $Path
        if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
        [System.IO.File]::WriteAllBytes($Path, (New-Object 'byte[]' $Bytes))
    }

    # racine : gros.bin (3000), a.txt (100), b.txt (200), SansExtension (50)
    #   docs\ : c.TXT (300), d.log (10)
    #   docs\vide\ : (rien)
    #   images\ : e.png (2500)
    $script:Root = Join-Path $TestDrive 'disque'
    New-TestFile (Join-Path $script:Root 'gros.bin') 3000
    New-TestFile (Join-Path $script:Root 'a.txt') 100
    New-TestFile (Join-Path $script:Root 'b.txt') 200
    New-TestFile (Join-Path $script:Root 'SansExtension') 50
    New-TestFile (Join-Path $script:Root 'docs\c.TXT') 300
    New-TestFile (Join-Path $script:Root 'docs\d.log') 10
    New-Item -ItemType Directory -Path (Join-Path $script:Root 'docs\vide') -Force | Out-Null
    New-TestFile (Join-Path $script:Root 'images\e.png') 2500

    function Find-Node {
        param($Model, [string]$Name, [int]$Parent = -2)
        for ($i = 0; $i -lt $Model.Name.Count; $i++) {
            if ($Model.Name[$i] -eq $Name -and ($Parent -eq -2 -or $Model.Parent[$i] -eq $Parent)) { return $i }
        }
        return -1
    }
}

Describe 'Read-DiskUsage' {
    BeforeAll {
        $script:Scan = Read-DiskUsage -Path $script:Root -LargeFileBytes 1000
    }

    It 'totaux : fichiers, octets, dossiers' {
        $script:Scan.Files | Should -Be 7
        $script:Scan.Bytes | Should -Be 6160
        $script:Scan.Directories | Should -Be 4
        $script:Scan.Size[0] | Should -Be 6160
        $script:Scan.Count[0] | Should -Be 7
        $script:Scan.Cancelled | Should -BeFalse
        $script:Scan.Inaccessible | Should -Be 0
    }

    It 'un gros fichier a son propre nœud' {
        $node = Find-Node $script:Scan 'gros.bin'
        $node | Should -BeGreaterThan 0
        $script:Scan.Kind[$node] | Should -Be 1
        $script:Scan.Size[$node] | Should -Be 3000
        $script:Scan.Parent[$node] | Should -Be 0
    }

    It 'les petits fichiers d''un dossier sont regroupés par extension, sans tenir compte de la casse' {
        $group = Find-Node $script:Scan '.txt' 0
        $script:Scan.Kind[$group] | Should -Be 2
        $script:Scan.Size[$group] | Should -Be 300
        $script:Scan.Count[$group] | Should -Be 2
        $docs = Find-Node $script:Scan 'docs' 0
        $inDocs = Find-Node $script:Scan '.txt' $docs
        $script:Scan.Size[$inDocs] | Should -Be 300
        $script:Scan.Count[$inDocs] | Should -Be 1
    }

    It 'un dossier cumule ses fichiers ; un dossier vide vaut zéro' {
        $docs = Find-Node $script:Scan 'docs' 0
        $script:Scan.Kind[$docs] | Should -Be 0
        $script:Scan.Size[$docs] | Should -Be 310
        $script:Scan.Count[$docs] | Should -Be 2
        $empty = Find-Node $script:Scan 'vide' $docs
        $script:Scan.Size[$empty] | Should -Be 0
    }

    It 'statistiques par extension, fichiers sans extension compris' {
        $byName = @{}
        for ($i = 0; $i -lt $script:Scan.ExtensionName.Count; $i++) { $byName[$script:Scan.ExtensionName[$i]] = $i }
        $script:Scan.ExtensionBytes[$byName['.txt']] | Should -Be 600
        $script:Scan.ExtensionFiles[$byName['.txt']] | Should -Be 3
        $script:Scan.ExtensionBytes[$byName['.bin']] | Should -Be 3000
        $script:Scan.ExtensionBytes[$byName['']] | Should -Be 50
        ($script:Scan.ExtensionBytes | Measure-Object -Sum).Sum | Should -Be 6160
    }

    It 'dossier introuvable : erreur explicite' {
        { Read-DiskUsage -Path (Join-Path $TestDrive 'absent') } | Should -Throw '*introuvable*'
    }

    It 'arrêt demandé : résultat partiel marqué comme interrompu' {
        $progress = New-DiskUsageProgress
        $progress.Cancel = $true
        $partial = Read-DiskUsage -Path $script:Root -Progress $progress
        $partial.Cancelled | Should -BeTrue
        $partial.Files | Should -Be 0
    }

    It 'l''avancement est publié' {
        $progress = New-DiskUsageProgress
        [void](Read-DiskUsage -Path $script:Root -Progress $progress)
        $progress.Files | Should -Be 7
        $progress.Bytes | Should -Be 6160
        $progress.Path | Should -Not -BeNullOrEmpty
    }
}

Describe 'Get-DiskUsage (modèle)' {
    BeforeAll {
        $script:Model = Get-DiskUsage -Path $script:Root -LargeFileBytes 1000
    }

    It 'enfants d''un dossier triés du plus gros au plus petit' {
        $children = Get-DiskUsageChild -Model $script:Model -Index 0
        $sizes = @($children | ForEach-Object { $script:Model.Size[$_] })
        ($sizes -join ',') | Should -Be (($sizes | Sort-Object -Descending) -join ',')
        $script:Model.Size[$children[0]] | Should -Be 3000
        $children.Length | Should -Be 5
        # Dossier vide : aucun enfant ; second appel : même tableau (gardé en mémoire).
        $docs = Find-Node $script:Model 'docs' 0
        (Get-DiskUsageChild -Model $script:Model -Index (Find-Node $script:Model 'vide' $docs)).Length | Should -Be 0
        [object]::ReferenceEquals((Get-DiskUsageChild -Model $script:Model -Index 0), $children) | Should -BeTrue
    }

    It 'plus gros enfant de chaque dossier (couleur d''un dossier dessiné d''un bloc)' {
        $script:Model.Largest[0] | Should -Be (Find-Node $script:Model 'gros.bin')
        $docs = Find-Node $script:Model 'docs' 0
        $script:Model.Largest[$docs] | Should -Be (Find-Node $script:Model '.txt' $docs)
        $script:Model.Largest[(Find-Node $script:Model 'vide' $docs)] | Should -Be -1
    }

    It 'carte calculée avec l''analyse quand sa taille est fournie' {
        $withMap = Get-DiskUsage -Path $script:Root -LargeFileBytes 1000 -MapWidth 400 -MapHeight 200
        $withMap.Treemap.Width | Should -Be 400
        $withMap.Treemap.Count | Should -BeGreaterThan 3
        $script:Model.Treemap | Should -BeNullOrEmpty
    }

    It 'extensions classées par volume, couleur selon le rang' {
        $order = $script:Model.ExtensionOrder
        $script:Model.ExtensionName[$order[0]] | Should -Be '.bin'
        $script:Model.ExtensionColor[$order[0]] | Should -Be 0
        $script:Model.ExtensionColor[$order[1]] | Should -Be 1
    }

    It 'chemin d''un fichier et d''un groupe (dossier qui le contient)' {
        $docs = Find-Node $script:Model 'docs' 0
        $group = Find-Node $script:Model '.log' $docs
        Get-DiskUsageNodePath -Model $script:Model -Index $group | Should -Be (Join-Path $script:Root 'docs')
        $image = Find-Node $script:Model 'e.png'
        Get-DiskUsageNodePath -Model $script:Model -Index $image | Should -Be (Join-Path $script:Root 'images\e.png')
        Get-DiskUsageNodePath -Model $script:Model -Index 0 | Should -Be $script:Root
    }

    It 'libellé d''un groupe : nombre de fichiers et extension' {
        Get-DiskUsageNodeLabel -Model $script:Model -Index (Find-Node $script:Model '.txt' 0) | Should -Be '2 fichiers .txt'
        Get-DiskUsageNodeLabel -Model $script:Model -Index (Find-Node $script:Model '' 0) | Should -Be '1 fichier (sans extension)'
        Get-DiskUsageNodeLabel -Model $script:Model -Index (Find-Node $script:Model 'docs' 0) | Should -Be 'docs'
    }

    It 'journal : une ligne de bilan' {
        $context = New-TestContext -Folder (Join-Path $TestDrive 'journal')
        [void](Get-DiskUsage -Path $script:Root -Log $context.Log)
        $lines = [System.IO.File]::ReadAllLines($context.Log.FilePath)
        ($lines -join "`n") | Should -Match 'Analyse de disque terminée .* 7 fichier\(s\)'
    }
}

Describe 'New-DiskUsageTreemap' {
    BeforeAll {
        $script:Model = Get-DiskUsage -Path $script:Root -LargeFileBytes 1000
        $script:Map = New-DiskUsageTreemap -Model $script:Model -Width 600 -Height 300 -MinSide 2
    }

    It 'les feuilles couvrent la carte, chacune proportionnelle à sa taille' {
        $area = 0.0
        for ($r = 0; $r -lt $script:Map.Count; $r++) {
            if (-not $script:Map.Leaf[$r]) { continue }
            $tile = $script:Map.W[$r] * $script:Map.H[$r]
            $area += $tile
            $expected = 180000.0 * $script:Model.Size[$script:Map.Node[$r]] / 6160
            [math]::Abs($tile - $expected) | Should -BeLessThan 0.5
        }
        [math]::Abs($area - 180000) | Should -BeLessThan 1
    }

    It 'chaque nœud dessiné se retrouve par son indice ; un dossier détaillé n''est pas une feuille' {
        $script:Map.RectOfNode[0] | Should -Be 0
        $script:Map.Leaf[0] | Should -BeFalse
        $image = Find-Node $script:Model 'e.png'
        $rect = $script:Map.RectOfNode[$image]
        $script:Map.Leaf[$rect] | Should -BeTrue
        $script:Map.Color[$rect] | Should -Be $script:Model.ExtensionColor[$script:Model.Extension[$image]]
    }

    It 'un point de la carte désigne la tuile qui le contient' {
        $image = Find-Node $script:Model 'e.png'
        $rect = $script:Map.RectOfNode[$image]
        $x = $script:Map.X[$rect] + $script:Map.W[$rect] / 2
        $y = $script:Map.Y[$rect] + $script:Map.H[$rect] / 2
        Find-DiskUsageTreemapRect -Treemap $script:Map -X $x -Y $y | Should -Be $rect
        Find-DiskUsageTreemapRect -Treemap $script:Map -X 5000 -Y 5000 | Should -Be -1
    }

    It 'un dossier trop petit pour être détaillé est dessiné d''un bloc, de la couleur de son plus gros contenu' {
        $coarse = New-DiskUsageTreemap -Model $script:Model -Width 600 -Height 300 -MinSide 5000
        $coarse.Count | Should -Be 1
        $coarse.Leaf[0] | Should -BeTrue
        $coarse.Color[0] | Should -Be 0
    }
}

Describe 'Open-DiskUsageLocation' {
    It 'ouvre l''Explorateur sur le chemin du nœud' {
        $model = Get-DiskUsage -Path $script:Root -LargeFileBytes 1000
        Mock -ModuleName FastPrepare.Application Show-PathInExplorer { }
        Open-DiskUsageLocation -Model $model -Index (Find-Node $model 'docs' 0)
        Should -Invoke -ModuleName FastPrepare.Application Show-PathInExplorer -Times 1 -ParameterFilter { $Path -eq (Join-Path $script:Root 'docs') }
    }
}
