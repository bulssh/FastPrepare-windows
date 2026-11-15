<#
    Profils entreprise (itération 14) : liste, lecture et enregistrement sur la clé.
    Aucun type WPF : le sélecteur du menu latéral n'en est que l'affichage.
#>

function Get-CompanyProfileList {
    <#
        Profils de la clé : { Name, Path }, triés par nom. Un fichier illisible est signalé au
        journal et ignoré : il n'empêche pas d'utiliser les autres.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Context)
    $entries = foreach ($path in @(Get-CompanyProfileFile -Folder $Context.Paths.Profiles)) {
        try {
            $companyProfile = Read-CompanyProfile -Path $path
            [pscustomobject]@{ Name = [string]$companyProfile.Name; Path = $path }
        } catch {
            Write-RunLog -Log $Context.Log -Level ATTN -Message $_.Exception.Message
        }
    }
    return @($entries | Sort-Object -Property Name)
}

function Import-CompanyProfile {
    <# Lit un profil de la clé. Ses incohérences sont journalisées (niveau ATTN) sans empêcher le chargement : la fenêtre les signalera à la saisie. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$Path
    )
    $companyProfile = Read-CompanyProfile -Path $Path
    foreach ($problem in @(Get-CompanyProfileError -CompanyProfile $companyProfile)) {
        Write-RunLog -Log $Context.Log -Level ATTN -Message ('Profil « {0} » : {1}' -f $companyProfile.Name, $problem)
    }
    Write-RunLog -Log $Context.Log -Level OK -Message ('Profil « {0} » chargé ({1})' -f $companyProfile.Name, [System.IO.Path]::GetFileName($Path))
    return $companyProfile
}

function Export-CompanyProfile {
    <#
        Enregistre un profil sur la clé. Refus (erreur qui liste les problèmes) s'il est incohérent :
        rien n'est écrit. Un profil du même nom est remplacé. Renvoie { Name, Path }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$CompanyProfile
    )
    $normalized = ConvertTo-CompanyProfile -InputObject $CompanyProfile
    $problems = @(Get-CompanyProfileError -CompanyProfile $normalized)
    if ($problems.Count -gt 0) { throw ("Profil non enregistré :`n- " + ($problems -join "`n- ")) }

    $fileName = Get-CompanyProfileFileName -Name $normalized.Name
    # Deux noms différents peuvent donner le même fichier (accents, ponctuation) : on ne remplace que le profil du même nom.
    foreach ($existing in @(Get-CompanyProfileList -Context $Context)) {
        $sameFile = [string]::Equals([System.IO.Path]::GetFileName($existing.Path), $fileName, [System.StringComparison]::OrdinalIgnoreCase)
        $sameName = [string]::Equals($existing.Name, $normalized.Name, [System.StringComparison]::OrdinalIgnoreCase)
        if ($sameFile -and -not $sameName) { throw ("Profil non enregistré : son fichier ({0}) est déjà celui du profil « {1} ». Choisir un autre nom." -f $fileName, $existing.Name) }
        if ($sameName -and -not $sameFile) { $fileName = [System.IO.Path]::GetFileName($existing.Path) }
    }
    $path = Save-CompanyProfile -Folder $Context.Paths.Profiles -FileName $fileName -CompanyProfile $normalized
    Write-RunLog -Log $Context.Log -Level OK -Message ('Profil « {0} » enregistré ({1}) — aucun mot de passe n''y est écrit' -f $normalized.Name, $path)
    return [pscustomobject]@{ Name = [string]$normalized.Name; Path = $path }
}
