<#
    Agent RMM et antivirus installés depuis un lien collé par le technicien (itération 16).
    Le lien est celui que fournit la console de l'éditeur ; il change d'un client à l'autre et
    n'est donc jamais dans config.json. Fonctions pures : elles reconnaissent l'installateur à
    son lien et donnent la commande silencieuse, sans rien télécharger.
#>

# Caractères interdits dans un nom de fichier Windows.
$script:InvalidFileNameChars = '\/:*?"<>|'

function Resolve-LinkInstaller {
    <#
        Reconnaît l'installateur désigné par un lien.
        -Kind Rmm       : .msi (NinjaOne) → msiexec /i /qn /norestart ; .exe (Datto RMM) → lancé tel quel.
        -Kind Antivirus : Bitdefender setupdownloader_[…].exe → /bdparams /silent ; .msi → msiexec /qn ;
                          ESET PROTECT_Installer_*.exe → --silent --accepteula ;
                          installateur en ligne ESET → --silent --acceptterms.
        Renvoie { Kind, Product, Url, FileName, Runner ('msiexec' | 'exe'), Arguments, Error }.
        Error : motif lisible si le lien est refusé (les autres champs sont alors vides).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Rmm', 'Antivirus')][string]$Kind,
        [AllowEmptyString()][AllowNull()][string]$Url
    )
    $result = [pscustomobject]@{
        PSTypeName = 'FastPrepare.LinkInstaller'
        Kind       = $Kind
        Product    = ''
        Url        = ''
        FileName   = ''
        Runner     = ''
        Arguments  = ''
        Error      = $null
    }
    $text = ([string]$Url).Trim()
    if (-not $text) { $result.Error = 'lien vide'; return $result }
    $uri = $null
    if (-not [System.Uri]::TryCreate($text, [System.UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne 'https') {
        $result.Error = 'lien https:// attendu'
        return $result
    }

    $hostName = $uri.Host.ToLowerInvariant()
    $fileName = [System.Uri]::UnescapeDataString(($uri.AbsolutePath -split '/')[-1])
    foreach ($char in $fileName.ToCharArray()) {
        if ($script:InvalidFileNameChars.IndexOf($char) -ge 0 -or [char]::IsControl($char)) {
            $result.Error = 'nom de fichier invalide dans le lien'
            return $result
        }
    }
    $extension = ''
    if ($fileName -match '\.(msi|exe)$') { $extension = $Matches[1].ToLowerInvariant() }

    $product = ''
    $runner = ''
    $arguments = ''
    if ($Kind -eq 'Rmm') {
        $isDatto = ($hostName -match '(^|\.)centrastage\.net$' -or $hostName -match '(^|\.)rmm\.datto\.com$')
        if ($extension -eq 'msi') {
            $product = if ($hostName -match 'ninja') { 'NinjaOne' } else { 'Agent RMM (.msi)' }
            $runner = 'msiexec'
            $arguments = '/qn /norestart'
        } elseif ($extension -eq 'exe') {
            $product = if ($isDatto) { 'Datto RMM' } else { 'Agent RMM (.exe)' }
            $runner = 'exe'
        } elseif ($isDatto) {
            # Le lien de téléchargement de l'agent Datto RMM ne porte pas de nom de fichier.
            $product = 'Datto RMM'
            $runner = 'exe'
            $fileName = 'AgentSetup.exe'
        } else {
            $result.Error = 'le lien doit mener à un fichier .msi (NinjaOne) ou .exe (Datto RMM)'
            return $result
        }
    } else {
        if ($extension -eq 'msi') {
            $product = if ($hostName -match 'bitdefender') { 'Bitdefender' } elseif ($hostName -match 'eset') { 'ESET' } else { 'Antivirus (.msi)' }
            $runner = 'msiexec'
            $arguments = '/qn /norestart'
        } elseif ($extension -ne 'exe') {
            $result.Error = 'le lien doit mener à un fichier .exe ou .msi (Bitdefender ou ESET)'
            return $result
        } elseif ($fileName -match '^setupdownloader_\[.+\]\.exe$') {
            # Le nom du fichier porte l'identifiant de la société : il doit être conservé tel quel.
            $product = 'Bitdefender'
            $runner = 'exe'
            $arguments = '/bdparams /silent'
        } elseif ($fileName -match '^PROTECT_Installer') {
            $product = 'ESET'
            $runner = 'exe'
            $arguments = '--silent --accepteula'
        } elseif ($hostName -match 'eset' -or $fileName -match 'eset|live_installer|epi_win') {
            $product = 'ESET (installateur en ligne)'
            $runner = 'exe'
            $arguments = '--silent --acceptterms'
        } else {
            $result.Error = 'installateur non reconnu : Bitdefender (setupdownloader_[…].exe ou .msi) ou ESET attendu'
            return $result
        }
    }

    $result.Product = $product
    $result.Url = $text
    $result.FileName = $fileName
    $result.Runner = $runner
    $result.Arguments = $arguments
    return $result
}

function Format-LinkInstallerCommand {
    <# Commande lisible d'un installateur reconnu (interface, plan et journal). #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)]$Installer)
    $run = if ($Installer.Runner -eq 'msiexec') { 'msiexec /i {0}' -f $Installer.FileName } else { [string]$Installer.FileName }
    if ($Installer.Arguments) { $run += ' ' + $Installer.Arguments }
    return ('{0} : téléchargement de {1} → {2}, signature vérifiée' -f $Installer.Product, $Installer.Url, $run)
}
