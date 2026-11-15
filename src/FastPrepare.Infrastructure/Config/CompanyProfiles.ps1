<#
    Fichiers des profils entreprise (itération 14) : un fichier JSON par profil dans le dossier
    profils\ de la clé, écrit par l'outil. config.json reste écrit à la main (DEC17).
    La normalisation (FastPrepare.Core, ConvertTo-CompanyProfile) est appliquée à la lecture
    comme à l'écriture : un profil ne peut pas contenir de mot de passe.
#>

function Get-CompanyProfileFile {
    <# Fichiers .json du dossier des profils, triés ; liste vide si le dossier n'existe pas. #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][string]$Folder)
    if (-not (Test-Path -LiteralPath $Folder -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $Folder -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object -Property Name | ForEach-Object { $_.FullName })
}

function Read-CompanyProfile {
    <# Lit et normalise un profil ; erreur lisible si le fichier n'est pas du JSON. Un nom absent prend celui du fichier. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    try {
        $raw = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    } catch {
        throw ("Profil illisible ({0}) : {1}" -f [System.IO.Path]::GetFileName($Path), $_.Exception.Message)
    }
    $companyProfile = ConvertTo-CompanyProfile -InputObject $raw
    if (-not $companyProfile.Name) { $companyProfile.Name = [System.IO.Path]::GetFileNameWithoutExtension($Path) }
    if ($raw -is [System.Management.Automation.PSCustomObject] -and $raw.PSObject.Properties['ProfileVersion']) {
        $companyProfile.ProfileVersion = $raw.ProfileVersion
    }
    return $companyProfile
}

function Save-CompanyProfile {
    <#
        Écrit un profil dans -Folder (créé au besoin) sous -FileName : fichier temporaire puis
        remplacement, JSON indenté, UTF-8 sans BOM. Renvoie le chemin du fichier.
        Clé protégée en écriture : erreur explicite, le profil existant reste intact.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Folder,
        [Parameter(Mandatory)][string]$FileName,
        [Parameter(Mandatory)]$CompanyProfile
    )
    if ($FileName -ne [System.IO.Path]::GetFileName($FileName)) { throw "Nom de fichier de profil refusé : $FileName" }
    $normalized = ConvertTo-CompanyProfile -InputObject ($CompanyProfile | ConvertTo-Json -Depth 6 | ConvertFrom-Json)
    $json = Format-JsonText -Json ($normalized | ConvertTo-Json -Depth 6 -Compress)
    $path = Join-Path $Folder $FileName
    $temporary = "$path.tmp"
    try {
        if (-not (Test-Path -LiteralPath $Folder -PathType Container)) { New-Item -ItemType Directory -Path $Folder -Force -ErrorAction Stop | Out-Null }
        [System.IO.File]::WriteAllText($temporary, $json + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temporary -Destination $path -Force -ErrorAction Stop
    } catch {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
        if ($_.Exception -is [System.UnauthorizedAccessException] -or $_.Exception.InnerException -is [System.UnauthorizedAccessException]) {
            throw "Profil non enregistré : la clé (ou le dossier $Folder) est protégée en écriture."
        }
        throw "Profil non enregistré ($path) : $($_.Exception.Message)"
    }
    return $path
}
