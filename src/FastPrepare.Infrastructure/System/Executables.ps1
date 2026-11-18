<#
    Recherche d'un outil installé (utilitaires constructeurs) : un chemin absolu est vérifié tel
    quel ; un simple nom de fichier est cherché dans les dossiers d'installation habituels, sur
    trois niveaux au plus, puis dans le PATH.
#>

function Find-InstalledExecutable {
    <# Chemin complet de l'exécutable ; erreur explicite s'il est introuvable. #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string[]]$SearchRoot = @(
            [Environment]::GetFolderPath('ProgramFiles'),
            [Environment]::GetFolderPath('ProgramFilesX86'),
            (Join-Path ([System.IO.Path]::GetPathRoot([Environment]::GetFolderPath('Windows'))) 'SWSetup')
        )
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        if (Test-Path -LiteralPath $Path -PathType Leaf) { return $Path }
        throw "Outil introuvable : $Path"
    }

    # Dossiers d'installation protégés d'abord ; le PATH (dossiers parfois modifiables sans droits
    # d'administrateur) en dernier recours seulement (audit SEC-002). La signature est vérifiée
    # par l'appelant juste avant le lancement.
    foreach ($root in ($SearchRoot | Where-Object { $_ } | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        $found = Get-ChildItem -LiteralPath $root -Filter $Path -File -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { return $found.FullName }
    }

    $command = Get-Command -Name $Path -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    throw ("Outil « {0} » introuvable (PATH, {1})." -f $Path, (($SearchRoot | Where-Object { $_ }) -join ', '))
}
