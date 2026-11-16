<#
    Règles pures de l'analyse de disque : mise en forme des tailles, couleurs des extensions,
    découpage du treemap.
#>
BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core
}

Describe 'Format-ByteSize' {
    It '<Bytes> octets → <Expected>' -ForEach @(
        @{ Bytes = 0; Expected = '0 octets' }
        @{ Bytes = 1023; Expected = '1023 octets' }
        @{ Bytes = 1024; Expected = '1,0 Ko' }
        @{ Bytes = 1536; Expected = '1,5 Ko' }
        @{ Bytes = 1048576; Expected = '1,0 Mo' }
        @{ Bytes = 157286400; Expected = '150 Mo' }
        @{ Bytes = 25125558681; Expected = '23,4 Go' }
        @{ Bytes = 2199023255552; Expected = '2,0 To' }
    ) {
        Format-ByteSize -Bytes $Bytes | Should -Be $Expected
    }
}

Describe 'Format-DiskUsagePercent' {
    It 'part ordinaire, avec une décimale et la virgule française' {
        Format-DiskUsagePercent -Part 123 -Total 1000 | Should -Be '12,3 %'
    }
    It 'part infime : « < 0,1 % » plutôt que zéro' {
        Format-DiskUsagePercent -Part 1 -Total 1000000 | Should -Be '< 0,1 %'
    }
    It 'part nulle et total nul' {
        Format-DiskUsagePercent -Part 0 -Total 1000 | Should -Be '0,0 %'
        Format-DiskUsagePercent -Part 0 -Total 0 | Should -Be '—'
    }
}

Describe 'Extensions' {
    It 'libellé : extension telle quelle, ou « (sans extension) »' {
        Get-DiskUsageExtensionLabel -Extension '.dll' | Should -Be '.dll'
        Get-DiskUsageExtensionLabel -Extension '' | Should -Be '(sans extension)'
    }
    It 'couleur : une par rang dans la palette, « autres » (-1) au-delà' {
        Get-DiskUsageColorIndex -Rank 0 | Should -Be 0
        Get-DiskUsageColorIndex -Rank 13 | Should -Be 13
        Get-DiskUsageColorIndex -Rank 14 | Should -Be -1
        Get-DiskUsageColorIndex -Rank 3 -PaletteSize 2 | Should -Be -1
    }
}

Describe 'Get-TreemapLayout' {
    BeforeAll {
        function Get-Tile {
            param([double[]]$Layout, [int]$Index)
            return [pscustomobject]@{ X = $Layout[4 * $Index]; Y = $Layout[4 * $Index + 1]; W = $Layout[4 * $Index + 2]; H = $Layout[4 * $Index + 3] }
        }
    }

    It 'un seul élément occupe tout le rectangle' {
        $layout = Get-TreemapLayout -Size @(42) -X 10 -Y 20 -Width 300 -Height 100
        $tile = Get-Tile $layout 0
        $tile.X | Should -Be 10
        $tile.Y | Should -Be 20
        $tile.W | Should -BeGreaterThan 299.99
        $tile.H | Should -BeGreaterThan 99.99
    }

    It 'aires proportionnelles aux tailles, somme égale à l''aire du rectangle' {
        $sizes = @(60.0, 30.0, 20.0, 10.0, 5.0, 3.0, 1.0)
        $layout = Get-TreemapLayout -Size $sizes -Width 400 -Height 250
        $total = ($sizes | Measure-Object -Sum).Sum
        $sum = 0.0
        for ($i = 0; $i -lt $sizes.Count; $i++) {
            $tile = Get-Tile $layout $i
            $area = $tile.W * $tile.H
            $sum += $area
            [math]::Abs($area - (400 * 250 * $sizes[$i] / $total)) | Should -BeLessThan 0.01 -Because "élément $i"
        }
        [math]::Abs($sum - 100000) | Should -BeLessThan 0.01
    }

    It 'les tuiles restent dans le rectangle et ne se chevauchent pas' {
        $sizes = @(50.0, 40.0, 30.0, 20.0, 10.0, 8.0, 6.0, 4.0, 2.0, 1.0)
        $layout = Get-TreemapLayout -Size $sizes -X 5 -Y 7 -Width 320 -Height 180
        $tiles = @(0..($sizes.Count - 1) | ForEach-Object { Get-Tile $layout $_ })
        foreach ($tile in $tiles) {
            $tile.X | Should -BeGreaterOrEqual 4.999
            $tile.Y | Should -BeGreaterOrEqual 6.999
            ($tile.X + $tile.W) | Should -BeLessOrEqual 325.001
            ($tile.Y + $tile.H) | Should -BeLessOrEqual 187.001
        }
        for ($a = 0; $a -lt $tiles.Count; $a++) {
            for ($b = $a + 1; $b -lt $tiles.Count; $b++) {
                $overlapW = [math]::Min($tiles[$a].X + $tiles[$a].W, $tiles[$b].X + $tiles[$b].W) - [math]::Max($tiles[$a].X, $tiles[$b].X)
                $overlapH = [math]::Min($tiles[$a].Y + $tiles[$a].H, $tiles[$b].Y + $tiles[$b].H) - [math]::Max($tiles[$a].Y, $tiles[$b].Y)
                ($overlapW -gt 0.001 -and $overlapH -gt 0.001) | Should -BeFalse -Because "tuiles $a et $b"
            }
        }
    }

    It 'tuiles proches du carré pour des tailles égales' {
        $layout = Get-TreemapLayout -Size @(1.0, 1.0, 1.0, 1.0) -Width 200 -Height 200
        foreach ($i in 0..3) {
            $tile = Get-Tile $layout $i
            $tile.W | Should -BeGreaterThan 99.9
            $tile.H | Should -BeGreaterThan 99.9
        }
    }

    It 'tailles nulles : tuiles vides ; liste vide ou rectangle vide : aucun calcul' {
        $layout = Get-TreemapLayout -Size @(10.0, 0.0, 0.0) -Width 100 -Height 50
        (Get-Tile $layout 0).W | Should -BeGreaterThan 99.9
        (Get-Tile $layout 1).W | Should -Be 0
        (Get-Tile $layout 2).H | Should -Be 0
        $empty = Get-TreemapLayout -Size @() -Width 100 -Height 50
        $empty.Length | Should -Be 0
        (Get-Tile (Get-TreemapLayout -Size @(5.0) -Width 0 -Height 50) 0).W | Should -Be 0
    }
}
