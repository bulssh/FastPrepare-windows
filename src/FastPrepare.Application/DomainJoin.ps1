<#
    Test de la jonction au domaine (itération 18), sans rien modifier : règles de saisie, état du
    poste, contrôleurs annoncés par le DNS, ouverture de session avec le compte saisi.
    Aucun type WPF : la section « Jonction au domaine » n'en est que l'affichage.
#>

function Test-DomainJoinSetting {
    <#
        Renvoie { Succeeded, Lines = @({ Level ('OK'|'ERREUR'|'ATTN'|'INFO'), Text }) }.
        Le mot de passe n'apparaît dans aucune ligne.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Domain,
        [AllowEmptyString()][string]$Account,
        [AllowNull()][System.Security.SecureString]$Password
    )
    $lines = New-Object System.Collections.Generic.List[object]
    $add = { param($level, $text) $lines.Add([pscustomobject]@{ Level = $level; Text = $text }) }
    $finish = { param($succeeded) [pscustomobject]@{ Succeeded = [bool]$succeeded; Lines = $lines.ToArray() } }

    $problem = Get-DomainJoinError -Domain $Domain -Account $Account -Password $Password
    if ($problem) { & $add 'ERREUR' $problem; return (& $finish $false) }
    $name = $Domain.Trim()

    try {
        $state = Get-ComputerDomainState
        if ($state.PartOfDomain -and (Test-SameDomain -First $state.Domain -Second $name)) {
            & $add 'ATTN' ('Le poste est déjà membre de {0} : la jonction sera ignorée.' -f $state.Domain)
        } elseif ($state.PartOfDomain) {
            & $add 'ERREUR' ("Le poste est déjà membre d'un autre domaine ({0}) : la jonction échouera." -f $state.Domain)
            return (& $finish $false)
        }
    } catch {
        & $add 'ATTN' ('État du poste illisible : {0}' -f $_.Exception.Message)
    }

    try {
        $controllers = @(Find-DomainController -Domain $name)
        if ($controllers.Count -eq 0) { throw 'aucun contrôleur annoncé' }
        & $add 'OK' ('Domaine trouvé : {0}' -f (($controllers | Select-Object -First 3) -join ', '))
    } catch {
        & $add 'ERREUR' ('Domaine introuvable depuis ce poste (vérifier le DNS de la carte réseau) : {0}' -f $_.Exception.Message)
        return (& $finish $false)
    }

    # Nom distinct du paramètre -Account (PowerShell ne distingue pas la casse des variables).
    $identity = Split-DomainAccount -Domain $name -Account $Account
    try {
        Test-DomainCredential -Domain $name -User $identity.User -UserDomain $identity.Domain -Password $Password
        & $add 'OK' ('Compte {0} accepté par le domaine.' -f $identity.Qualified)
    } catch {
        & $add 'ERREUR' ('Compte {0} : {1}' -f $identity.Qualified, $_.Exception.Message)
        return (& $finish $false)
    }
    & $add 'INFO' 'Le droit de joindre un poste au domaine n''est vérifié qu''à la jonction elle-même.'
    return (& $finish $true)
}

function Start-DomainJoinTest {
    <# Lance Test-DomainJoinSetting dans un runspace (DNS et annuaire peuvent mettre plusieurs secondes à répondre). #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Context,
        [AllowEmptyString()][string]$Domain,
        [AllowEmptyString()][string]$Account,
        [AllowNull()][System.Security.SecureString]$Password
    )
    return Start-BackgroundWork -Name 'test-domaine' -ModulePath $Context.ModulePaths -Argument @($Domain, $Account, $Password) -ScriptBlock {
        param([string]$Domain, [string]$Account, [System.Security.SecureString]$Password)
        Test-DomainJoinSetting -Domain $Domain -Account $Account -Password $Password
    }
}
