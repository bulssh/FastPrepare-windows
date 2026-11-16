<#
    Analyse de disque (page hors parcours « Analyse de disque ») : règles pures.
    Mise en forme des tailles, libellé d'une extension, répartition des couleurs et découpage
    d'un rectangle en tuiles proportionnelles (treemap « squarified »). Le parcours du disque est
    dans FastPrepare.Infrastructure (Read-DiskUsage), le modèle dans FastPrepare.Application.
#>

function Format-ByteSize {
    <# Taille lisible, en unités françaises : « 512 octets », « 1,5 Mo », « 23,4 Go ». #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][double]$Bytes)
    $culture = [System.Globalization.CultureInfo]::GetCultureInfo('fr-FR')
    if ($Bytes -lt 1024) { return ('{0} octets' -f [long]$Bytes) }
    $units = @('Ko', 'Mo', 'Go', 'To', 'Po')
    $value = $Bytes / 1024
    $index = 0
    while ($value -ge 1024 -and $index -lt $units.Count - 1) {
        $value = $value / 1024
        $index++
    }
    $format = if ($value -ge 100) { '0' } else { '0.0' }
    return ('{0} {1}' -f $value.ToString($format, $culture), $units[$index])
}

function Format-DiskUsagePercent {
    <# Part d'un total : « 12,3 % » ; « < 0,1 % » pour une part infime, « — » sans total. #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][double]$Part, [Parameter(Mandatory)][double]$Total)
    if ($Total -le 0) { return '—' }
    $percent = 100 * $Part / $Total
    if ($percent -gt 0 -and $percent -lt 0.1) { return '< 0,1 %' }
    return ('{0} %' -f $percent.ToString('0.0', [System.Globalization.CultureInfo]::GetCultureInfo('fr-FR')))
}

function Get-DiskUsageExtensionLabel {
    <# Libellé affiché d'une extension normalisée (« .dll ») ; chaîne vide : fichiers sans extension. #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()][string]$Extension)
    if (-not $Extension) { return '(sans extension)' }
    return $Extension
}

function Get-DiskUsageColorIndex {
    <#
        Couleur d'une extension d'après son rang (0 = la plus volumineuse) : les -PaletteSize
        premières ont chacune leur couleur, les suivantes partagent la couleur « autres » (-1).
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param([Parameter(Mandatory)][int]$Rank, [int]$PaletteSize = 14)
    if ($Rank -ge 0 -and $Rank -lt $PaletteSize) { return $Rank }
    return -1
}

function Get-TreemapLayout {
    <#
        Découpe le rectangle (X, Y, Width, Height) en tuiles dont l'aire est proportionnelle à
        -Size, aussi carrées que possible (algorithme « squarified » de Bruls, Huizing et van Wijk).
        -Size doit être trié par ordre décroissant. Renvoie un tableau plat de 4 valeurs par
        élément, dans l'ordre de -Size : x, y, largeur, hauteur. Un élément de taille nulle reçoit
        une tuile vide.
        Fonction simple (sans CmdletBinding) : appelée une fois par dossier dessiné.
    #>
    [OutputType([double[]])]
    param(
        [double[]]$Size = @(),
        [double]$X = 0,
        [double]$Y = 0,
        [double]$Width = 0,
        [double]$Height = 0
    )
    $count = $Size.Length
    $result = New-Object 'double[]' (4 * $count)
    if ($count -eq 0 -or $Width -le 0 -or $Height -le 0) { return , $result }
    $total = 0.0
    foreach ($value in $Size) { if ($value -gt 0) { $total += $value } }
    if ($total -le 0) { return , $result }

    $scale = ($Width * $Height) / $total
    $left = $X
    $top = $Y
    $w = $Width
    $h = $Height
    $i = 0
    while ($i -lt $count) {
        $first = $Size[$i] * $scale
        if ($first -le 0) { break }   # tri décroissant : tout le reste est nul
        $side = if ($w -lt $h) { $w } else { $h }
        if ($side -le 0) { break }
        $sideSquare = $side * $side
        $rowSum = $first
        $worst = if ($sideSquare / $first -gt $first / $sideSquare) { $sideSquare / $first } else { $first / $sideSquare }
        $j = $i + 1
        while ($j -lt $count) {
            $area = $Size[$j] * $scale
            if ($area -le 0) { break }
            $sum = $rowSum + $area
            # La plus grande tuile de la rangée est la première, la plus petite la dernière.
            $ratioMax = $sideSquare * $first / ($sum * $sum)
            $ratioMin = ($sum * $sum) / ($sideSquare * $area)
            $candidate = if ($ratioMax -gt $ratioMin) { $ratioMax } else { $ratioMin }
            if ($candidate -gt $worst) { break }
            $rowSum = $sum
            $worst = $candidate
            $j++
        }
        $thickness = $rowSum / $side
        if ($w -ge $h) {
            # Rangée verticale à gauche : tuiles empilées de haut en bas.
            $offset = $top
            for ($k = $i; $k -lt $j; $k++) {
                $length = ($Size[$k] * $scale) / $thickness
                $base = 4 * $k
                $result[$base] = $left
                $result[$base + 1] = $offset
                $result[$base + 2] = $thickness
                $result[$base + 3] = $length
                $offset += $length
            }
            $left += $thickness
            $w -= $thickness
        } else {
            # Rangée horizontale en haut : tuiles côte à côte.
            $offset = $left
            for ($k = $i; $k -lt $j; $k++) {
                $length = ($Size[$k] * $scale) / $thickness
                $base = 4 * $k
                $result[$base] = $offset
                $result[$base + 1] = $top
                $result[$base + 2] = $length
                $result[$base + 3] = $thickness
                $offset += $length
            }
            $top += $thickness
            $h -= $thickness
        }
        $i = $j
    }
    return , $result
}
