<#
    Jonction du poste à un domaine Active Directory (itération 18) : règles de saisie.
    Fonctions pures. Le mot de passe reste une SecureString (DEC15) ; aucune unité
    d'organisation n'est demandée : le poste arrive dans le conteneur par défaut du domaine.
#>

function Get-DomainJoinError {
    <# Motif lisible du refus d'une demande de jonction, ou $null. -Password facultatif : sans lui, seuls le domaine et le compte sont vérifiés. #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()][AllowNull()][string]$Domain,
        [AllowEmptyString()][AllowNull()][string]$Account,
        [AllowNull()][System.Security.SecureString]$Password
    )
    $name = ([string]$Domain).Trim()
    if (-not $name) { return 'nom du domaine vide' }
    if ($name.Length -gt 255 -or $name -notmatch '^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$') {
        return 'nom DNS complet du domaine attendu (ex. entreprise.local)'
    }
    $user = ([string]$Account).Trim()
    if (-not $user) { return 'compte autorisé à joindre le domaine vide' }
    if ($user -match '[\s"/\[\]:;|=,+*?<>]') { return 'caractère interdit dans le compte' }
    if (($user.Split('\').Count -gt 2) -or ($user.Split('@').Count -gt 2) -or ($user.Contains('\') -and $user.Contains('@'))) {
        return 'compte attendu sous la forme utilisateur, DOMAINE\utilisateur ou utilisateur@domaine'
    }
    if ($user.StartsWith('\') -or $user.EndsWith('\') -or $user.StartsWith('@') -or $user.EndsWith('@')) {
        return 'compte attendu sous la forme utilisateur, DOMAINE\utilisateur ou utilisateur@domaine'
    }
    if ($PSBoundParameters.ContainsKey('Password')) {
        if ($null -eq $Password) { return 'mot de passe du compte vide' }
        $length = $Password.Length
        if ($null -eq $length) { return 'mot de passe indisponible (déjà libéré) : saisissez-le de nouveau' }
        if ($length -eq 0) { return 'mot de passe du compte vide' }
    }
    return $null
}

function Split-DomainAccount {
    <#
        Décompose le compte saisi : { User, Domain, Qualified }.
        utilisateur → Domain = domaine à joindre ; DOMAINE\utilisateur → tel quel ;
        utilisateur@domaine → nom complet dans User, Domain vide. Qualified : forme à donner à Windows.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Domain,
        [Parameter(Mandatory)][string]$Account
    )
    $user = $Account.Trim()
    if ($user.Contains('\')) {
        $parts = $user.Split('\')
        return [pscustomobject]@{ User = $parts[1]; Domain = $parts[0]; Qualified = $user }
    }
    if ($user.Contains('@')) {
        return [pscustomobject]@{ User = $user; Domain = ''; Qualified = $user }
    }
    $name = $Domain.Trim()
    return [pscustomobject]@{ User = $user; Domain = $name; Qualified = ('{0}\{1}' -f $name, $user) }
}

function Test-SameDomain {
    <# Vrai si deux noms désignent le même domaine (casse et point final ignorés). #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([AllowEmptyString()][AllowNull()][string]$First, [AllowEmptyString()][AllowNull()][string]$Second)
    $a = ([string]$First).Trim().TrimEnd('.')
    $b = ([string]$Second).Trim().TrimEnd('.')
    return ($a -and [string]::Equals($a, $b, [System.StringComparison]::OrdinalIgnoreCase))
}
