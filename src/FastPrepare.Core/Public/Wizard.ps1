<#
    Parcours par étapes de la fenêtre (itération 13) : cinq étapes de saisie, le récapitulatif
    (sixième page, seul endroit d'où l'on lance) et, à part, le catalogue des logiciels et
    l'analyse de disque. Fonctions pures : l'interface (FastPrepare.UI) ne fait qu'afficher ce parcours.
#>

function Test-WizardPageOnPath {
    <# Vrai pour une page du parcours Précédent / Suivant (Step ou Review) ; faux pour une page à part (Settings, Tool). #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Kind)
    return ($Kind -eq 'Step' -or $Kind -eq 'Review')
}

function Get-WizardPage {
    <#
        Pages de la fenêtre, dans l'ordre d'affichage. Kind : Step (étape de saisie), Review
        (récapitulatif, dernière page du parcours), Settings (réglages enregistrés sur la clé,
        hors parcours) ou Tool (outil en lecture seule, hors parcours, qui occupe toute la page).
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param()
    $pages = @(
        @{ Id = 'poste'; Kind = 'Step'; Title = 'Poste'; Subtitle = 'Vérifier le nom du poste et relever son numéro de série.' }
        @{ Id = 'nettoyage'; Kind = 'Step'; Title = 'Nettoyage'; Subtitle = 'Retirer les logiciels préinstallés, les applications Microsoft et les sessions inutiles.' }
        @{ Id = 'comptes'; Kind = 'Step'; Title = 'Comptes et domaine'; Subtitle = 'Créer les sessions locales du poste et le joindre au domaine.' }
        @{ Id = 'installations'; Kind = 'Step'; Title = 'Installations'; Subtitle = 'Utilitaire constructeur, Office, logiciels, agent RMM et antivirus.' }
        @{ Id = 'systeme'; Kind = 'Step'; Title = 'Système et réseau'; Subtitle = 'Mises à jour, réglages de Windows, lecteurs réseau et imprimantes.' }
        @{ Id = 'recap'; Kind = 'Review'; Title = 'Récapitulatif'; Subtitle = 'Relire les actions prévues, puis lancer.' }
        @{ Id = 'catalogue'; Kind = 'Settings'; Title = 'Catalogue logiciels'; Subtitle = 'Logiciels proposés à l''étape Installations, enregistrés sur la clé.' }
        @{ Id = 'disque'; Kind = 'Tool'; Title = 'Analyse de disque'; Subtitle = 'Voir ce qui occupe le disque : dossiers, types de fichiers et carte des tailles. Lecture seule.' }
    )
    $number = 0
    foreach ($page in $pages) {
        $number++
        [pscustomobject]@{
            PSTypeName = 'FastPrepare.WizardPage'
            Id         = $page.Id
            Kind       = $page.Kind
            Number     = if (Test-WizardPageOnPath -Kind $page.Kind) { $number } else { 0 }
            Title      = $page.Title
            Subtitle   = $page.Subtitle
        }
    }
}

function Get-WizardNeighbor {
    <#
        Identifiant de la page suivante ou précédente du parcours, ou $null (début, fin, ou page
        hors parcours comme le catalogue).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$PageId,
        [Parameter(Mandatory)][ValidateSet('Next', 'Previous')][string]$Direction
    )
    $path = @(Get-WizardPage | Where-Object { Test-WizardPageOnPath -Kind $_.Kind } | ForEach-Object { $_.Id })
    $index = [array]::IndexOf($path, $PageId)
    if ($index -lt 0) { return $null }
    $target = if ($Direction -eq 'Next') { $index + 1 } else { $index - 1 }
    if ($target -lt 0 -or $target -ge $path.Count) { return $null }
    return $path[$target]
}

function Get-WizardNextLabel {
    <#
        Libellé du bouton d'avancement : « Suivant → », « Vérifier et lancer → » avant le
        récapitulatif, $null quand il n'y a pas de page suivante.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$PageId)
    $next = Get-WizardNeighbor -PageId $PageId -Direction Next
    if (-not $next) { return $null }
    $page = Get-WizardPage | Where-Object { $_.Id -eq $next }
    if ($page.Kind -eq 'Review') { return 'Vérifier et lancer →' }
    return 'Suivant →'
}
