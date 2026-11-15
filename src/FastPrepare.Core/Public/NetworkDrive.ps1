<#
    Lecteurs réseau à connecter pour l'utilisateur de la session ouverte (itération 17).
    Règles de saisie et noms de registre. Fonctions pures.
    Le mappage est celui que ferait « net use X: \\serveur\partage /persistent:yes » dans la
    session de l'utilisateur : des valeurs sous HKU\<SID>\Network\<lettre>. Aucun script ni tâche
    planifiée n'est laissé sur le poste.
#>

$script:MaxDriveLabelLength = 32

function New-NetworkDriveRequest {
    <# Lecteur réseau à connecter (une entrée de Selection.NetworkDrives.Items). Lettre en majuscule, chemin sans barre finale. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Letter,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Path,
        [string]$Label = ''
    )
    return [pscustomobject]@{
        PSTypeName = 'FastPrepare.NetworkDriveRequest'
        Letter     = ([string]$Letter).Trim().TrimEnd(':').ToUpperInvariant()
        Path       = ([string]$Path).Trim().TrimEnd('\')
        Label      = ([string]$Label).Trim()
    }
}

function Get-NetworkDriveError {
    <#
        Motif lisible du refus d'un lecteur réseau, ou $null.
        -UsedLetter : lettres déjà prises (disques du poste, lecteurs déjà demandés).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]$Drive,
        [AllowEmptyCollection()][string[]]$UsedLetter = @()
    )
    $letter = [string]$Drive.Letter
    if ($letter -notmatch '^[A-Z]$') { return 'lettre de lecteur attendue (une lettre de D à Z)' }
    if (@('A', 'B', 'C') -contains $letter) { return ('lettre {0}: réservée au poste' -f $letter) }
    foreach ($used in @($UsedLetter)) {
        if ($used -and ([string]$used).Trim().TrimEnd(':').ToUpperInvariant() -eq $letter) { return ('lettre {0}: déjà utilisée' -f $letter) }
    }
    $path = [string]$Drive.Path
    if (-not $path) { return 'chemin réseau vide' }
    # \\serveur\partage, sous-dossiers facultatifs ; aucun caractère interdit par Windows.
    if ($path -notmatch '^\\\\[^\\/:*?"<>|\s]+(\\[^\\/:*?"<>|]+)+$') { return 'chemin réseau attendu sous la forme \\serveur\partage' }
    $label = [string]$Drive.Label
    if ($label.Length -gt $script:MaxDriveLabelLength) { return ('libellé de {0} caractères sur {1} maximum' -f $label.Length, $script:MaxDriveLabelLength) }
    if ($label -match '[\\/:*?"<>|]') { return 'caractère interdit dans le libellé' }
    return $null
}

function Get-NetworkDriveLabelKeyName {
    <#
        Nom de la clé MountPoints2 qui porte le libellé d'un lecteur réseau dans l'Explorateur :
        le chemin UNC où chaque barre oblique inverse est remplacée par un dièse
        (\\serveur\partage → ##serveur#partage).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Path)
    return $Path.TrimEnd('\').Replace('\', '#')
}

function Format-NetworkDriveSummary {
    <# « P: → \\serveur\partage (Libellé) », pour la liste, le plan et le journal. #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)]$Drive)
    $text = '{0}: → {1}' -f $Drive.Letter, $Drive.Path
    if ($Drive.Label) { $text += ' ({0})' -f $Drive.Label }
    return $text
}
