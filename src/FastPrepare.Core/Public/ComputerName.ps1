<#
    Rappel du renommage du poste (étape Poste du cahier des charges).
    L'outil ne renomme pas le poste : le renommage se fait à la main, avant l'outil, suivi d'un
    redémarrage (le nouveau nom n'est effectif qu'après redémarrage, DEC22). Fonction pure.
#>

function Test-DefaultComputerName {
    <#
        Vrai si le nom est celui attribué automatiquement par Windows à l'installation
        (DESKTOP-XXXXXXX ou LAPTOP-XXXXXXXX) : le poste n'a donc pas encore été renommé.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowEmptyString()][AllowNull()][string]$Name
    )
    if ([string]::IsNullOrEmpty($Name)) { return $false }
    return ($Name -match '^(DESKTOP|LAPTOP)-[A-Z0-9]{7,8}$')
}
