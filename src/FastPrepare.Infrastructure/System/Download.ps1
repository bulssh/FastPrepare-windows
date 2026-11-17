<#
    Téléchargements et vérification des exécutables avant lancement (plan d'architecture §7.1).
    HTTPS uniquement ; BITS (fourni avec Windows, cahier des charges), repli HttpClient ;
    écriture sous un nom temporaire puis renommage : un fichier partiel n'est jamais réutilisé.
#>

function Save-RemoteFile {
    <# Télécharge -Url vers -Destination ; vérifie l'empreinte SHA-256 si fournie. Renvoie le chemin. #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Destination,
        [AllowEmptyString()][string]$Sha256,
        $Log
    )

    if ($Url -notmatch '^https://') { throw "Téléchargement refusé (lien https:// attendu) : $Url" }
    $folder = Split-Path -Path $Destination -Parent
    if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
    $partial = "$Destination.partiel"
    if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }

    if ($Log) { Write-RunLog -Log $Log -Level DEBUG -Message "Téléchargement : $Url → $Destination" }
    try {
        Start-BitsTransfer -Source $Url -Destination $partial -ErrorAction Stop
    } catch {
        if ($Log) { Write-RunLog -Log $Log -Level DEBUG -Message "BITS indisponible ($($_.Exception.Message)), repli HttpClient" }
        Save-HttpFile -Url $Url -Destination $partial
    }

    if ($Sha256) {
        $actual = (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash
        if ($actual -ne $Sha256.Trim().ToUpperInvariant()) {
            Remove-Item -LiteralPath $partial -Force
            throw "Empreinte SHA-256 inattendue pour $Url (attendue $Sha256, obtenue $actual) : fichier supprimé."
        }
    }
    Move-Item -LiteralPath $partial -Destination $Destination -Force
    return $Destination
}

function Save-RemoteInstaller {
    <#
        Télécharge un installateur dans -Folder puis lui donne -FileName, son nom d'origine
        (l'installateur Bitdefender lit son identifiant de société dans son propre nom, crochets
        compris). Le téléchargement se fait sous un nom neutre : BITS interprète les crochets.
        Renvoie le chemin du fichier.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Folder,
        [Parameter(Mandatory)][string]$FileName,
        $Log
    )
    if ($FileName -ne [System.IO.Path]::GetFileName($FileName)) { throw "Nom de fichier refusé : $FileName" }
    $neutral = Save-RemoteFile -Url $Url -Destination (Join-Path $Folder 'telechargement.bin') -Log $Log
    $target = [System.IO.Path]::Combine($Folder, $FileName)
    if ([System.IO.File]::Exists($target)) { [System.IO.File]::Delete($target) }
    [System.IO.File]::Move($neutral, $target)
    return $target
}

function Save-HttpFile {
    param([string]$Url, [string]$Destination)
    $client = New-Object System.Net.Http.HttpClient
    try {
        $client.Timeout = [TimeSpan]::FromMinutes(30)
        $response = $client.GetAsync($Url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        [void]$response.EnsureSuccessStatusCode()
        $source = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $target = [System.IO.File]::Create($Destination)
        try { $source.CopyTo($target) } finally { $target.Dispose(); $source.Dispose() }
    } finally {
        $client.Dispose()
    }
}

function Expand-DownloadedArchive {
    <#
        Extrait l'archive .zip -Path dans un dossier neuf, voisin de l'archive et du même nom
        (l'ancien est supprimé : jamais de mélange avec une extraction précédente), puis renvoie le
        chemin de l'unique fichier nommé -FileName qu'elle contient. Le format ZIP de .NET refuse
        les chemins qui sortiraient du dossier d'extraction.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$FileName,
        $Log
    )
    if ($FileName -ne [System.IO.Path]::GetFileName($FileName)) { throw "Nom de fichier refusé : $FileName" }
    $folder = Join-Path (Split-Path -Path $Path -Parent) ([System.IO.Path]::GetFileNameWithoutExtension($Path))
    if (Test-Path -LiteralPath $folder) { Remove-Item -LiteralPath $folder -Recurse -Force }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if ($Log) { Write-RunLog -Log $Log -Level DEBUG -Message "Extraction : $Path → $folder" }
    [System.IO.Compression.ZipFile]::ExtractToDirectory($Path, $folder)
    $found = @(Get-ChildItem -LiteralPath $folder -Recurse -File -Filter $FileName)
    if ($found.Count -ne 1) {
        throw ("{0} : {1} fichier(s) « {2} » dans l'archive, un seul attendu." -f [System.IO.Path]::GetFileName($Path), $found.Count, $FileName)
    }
    return $found[0].FullName
}

function Assert-TrustedExecutable {
    <#
        Refuse de laisser lancer un exécutable dont la signature Authenticode n'est pas valide, ou
        dont le certificat ne mentionne pas l'éditeur attendu (-ExpectedSigner, ex. « Microsoft »).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowEmptyString()][string]$ExpectedSigner
    )
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
        throw ("Signature de {0} non valide ({1}) : exécutable non lancé." -f [System.IO.Path]::GetFileName($Path), $signature.Status)
    }
    $subject = [string]$signature.SignerCertificate.Subject
    if ($ExpectedSigner -and $subject -notmatch [regex]::Escape($ExpectedSigner)) {
        throw ("{0} est signé par « {1} », et non par « {2} » : exécutable non lancé." -f [System.IO.Path]::GetFileName($Path), $subject, $ExpectedSigner)
    }
}

function Test-RemoteFile {
    <#
        Vérifie un lien de téléchargement SANS télécharger le fichier (test du catalogue, DEC18) :
        requête HEAD, ou GET dont seuls les en-têtes sont lus si le serveur refuse HEAD.
        Redirections suivies. Renvoie { StatusCode, ContentType, ContentLength, FinalUrl }.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Url)
    if ($Url -notmatch '^https://') { throw "Lien refusé (https:// attendu) : $Url" }
    $result = Invoke-HttpHeaderRequest -Url $Url -Method 'HEAD'
    if (@(403, 405, 501) -contains $result.StatusCode) { $result = Invoke-HttpHeaderRequest -Url $Url -Method 'GET' }
    return $result
}

function Invoke-HttpHeaderRequest {
    <# Une requête dont seuls le code et les en-têtes sont lus ; le corps n'est jamais téléchargé. #>
    param([string]$Url, [string]$Method)
    $client = New-Object System.Net.Http.HttpClient
    try {
        $client.Timeout = [TimeSpan]::FromSeconds(30)
        $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new($Method), $Url)
        $response = $client.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        try {
            $content = $response.Content
            return [pscustomobject]@{
                StatusCode    = [int]$response.StatusCode
                ContentType   = $(if ($content -and $content.Headers.ContentType) { [string]$content.Headers.ContentType.MediaType } else { '' })
                ContentLength = $(if ($content) { $content.Headers.ContentLength } else { $null })
                FinalUrl      = [string]$response.RequestMessage.RequestUri
            }
        } finally {
            # Ferme la connexion avant la lecture du corps.
            $response.Dispose()
        }
    } catch {
        $inner = $_.Exception
        while ($inner.InnerException) { $inner = $inner.InnerException }
        throw "Lien injoignable ($Url) : $($inner.Message)"
    } finally {
        $client.Dispose()
    }
}
