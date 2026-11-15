<#
    Étape 18 — Jonction au domaine Active Directory (section 15, itération 18). Toujours la
    DERNIÈRE étape : tout le reste de la préparation se fait avec les comptes locaux, et la
    jonction n'est effective qu'au redémarrage final, fait à la main (jamais automatique).
    Le mot de passe voyage en SecureString dans Parameters, que le moteur ne journalise jamais.
#>

Register-Step -Id 'join-domain' -Section 15 -Title 'Jonction au domaine' -Plan {
    param($Selection, $Snapshot, $Context)
    $domain = ([string]$Selection.DomainJoin.Domain).Trim()
    if (-not $domain) { return }
    $account = Split-DomainAccount -Domain $domain -Account $Selection.DomainJoin.Account

    New-StepAction -Label ('Jonction au domaine : Add-Computer -DomainName {0} (compte {1}) — sans redémarrage, effective au redémarrage final' -f $domain, $account.Qualified) -Parameters @{
        Kind     = 'DomainJoin'
        Domain   = $domain
        Account  = $account.Qualified
        Password = $Selection.DomainJoin.Password
    }
} -Invoke {
    param($Action, $Context)
    $p = $Action.Parameters
    $passwordError = Get-DomainJoinError -Domain $p.Domain -Account $p.Account -Password $p.Password
    if ($passwordError) { throw $passwordError }

    $state = Get-ComputerDomainState
    if ($state.PartOfDomain) {
        if (Test-SameDomain -First $state.Domain -Second $p.Domain) {
            Write-RunLog -Log $Context.Log -Message ('Le poste est déjà membre de {0} : rien à faire' -f $state.Domain)
            return
        }
        throw ("le poste est déjà membre d'un autre domaine ({0}) : il n'est pas modifié." -f $state.Domain)
    }

    Join-ComputerToDomain -Domain $p.Domain -QualifiedAccount $p.Account -Password $p.Password -Log $Context.Log
    Write-RunLog -Log $Context.Log -Message ('Poste joint à {0} ; la jonction sera effective au redémarrage final (à faire à la main)' -f $p.Domain)
    return [pscustomobject]@{ RebootRequired = $true }
}
