<#
    Office Deployment Tool, partagé par la suppression (étape 3) et l'installation (étape 7).
    setup.exe est téléchargé depuis le lien de config.json et sa signature Microsoft vérifiée
    avant chaque utilisation.
#>

function Initialize-OdtFolder {
    <# Crée le dossier ODT et y place setup.exe (téléchargé si absent). Renvoie le chemin de setup.exe. #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Folder,
        [Parameter(Mandatory)][string]$SetupUrl,
        $Log
    )
    if (-not (Test-Path -LiteralPath $Folder)) { New-Item -ItemType Directory -Path $Folder -Force | Out-Null }
    $setup = Join-Path $Folder 'setup.exe'
    if (-not (Test-Path -LiteralPath $setup -PathType Leaf)) {
        if ($Log) { Write-RunLog -Log $Log -Message "Téléchargement de l'Office Deployment Tool dans $Folder" }
        [void](Save-RemoteFile -Url $SetupUrl -Destination $setup -Log $Log)
    }
    Assert-TrustedExecutable -Path $setup -ExpectedSigner 'Microsoft'
    return $setup
}

function Invoke-Odt {
    <#
        Écrit le XML dans le dossier ODT (configuration-<nom>-<horodatage>.xml) et lance
        setup.exe /configure. Renvoie { RebootRequired, ConfigurationPath }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SetupPath,
        [Parameter(Mandatory)][string]$Xml,
        [Parameter(Mandatory)][ValidatePattern('^[a-z0-9-]+$')][string]$Name,
        [int]$TimeoutMinutes = 90,
        $Log
    )
    $folder = Split-Path -Path $SetupPath -Parent
    $configuration = Join-Path $folder ('configuration-{0}-{1}.xml' -f $Name, (Get-Date -Format 'yyyyMMdd-HHmmss'))
    [System.IO.File]::WriteAllText($configuration, $Xml, (New-Object System.Text.UTF8Encoding($false)))
    # FORCEAPPSHUTDOWN (DEC34) : ODT ferme les applications Office ouvertes, sans enregistrer.
    $open = @(Get-RunningOfficeApp)
    if ($open.Count -gt 0 -and $Log) {
        Write-RunLog -Log $Log -Level ATTN -Message ('Office : applications ouvertes, fermées par ODT sans enregistrer : {0}' -f ($open -join ', '))
    }
    $result = Invoke-ExternalProcess -FilePath $SetupPath -ArgumentList ('/configure "{0}"' -f $configuration) -WorkingDirectory $folder -TimeoutMinutes $TimeoutMinutes -Log $Log
    return [pscustomobject]@{ RebootRequired = $result.RebootRequired; ConfigurationPath = $configuration }
}

function Get-RunningOfficeApp {
    <# Applications Office ouvertes (toutes sessions) : noms lisibles, sans doublon. #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $names = [ordered]@{
        WINWORD = 'Word'; EXCEL = 'Excel'; POWERPNT = 'PowerPoint'; OUTLOOK = 'Outlook'
        ONENOTE = 'OneNote'; MSACCESS = 'Access'; MSPUB = 'Publisher'; VISIO = 'Visio'; WINPROJ = 'Project'
    }
    $running = @(Get-Process -Name @($names.Keys) -ErrorAction SilentlyContinue | ForEach-Object { $_.ProcessName.ToUpperInvariant() })
    foreach ($key in $names.Keys) { if ($running -contains $key) { $names[$key] } }
}

function Get-InstalledOfficeKind {
    <#
        Office présent sur le poste : { ClickToRun, Msi }. Click-to-Run : au moins un produit dans
        sa configuration. MSI (2010 à 2016) : une entrée de désinstallation dont le code produit
        se termine par « 0000000FF1CE} », suffixe commun aux produits Office installés par MSI.
        Sert à ne pas lancer l'outil de déploiement d'Office pour une suppression sur un poste sans
        Office : il y échoue (code -1) au lieu de répondre « rien à retirer ».
    #>
    [CmdletBinding()]
    param()
    $msi = $false
    foreach ($root in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall') {
        $keys = @(Get-ChildItem -Path $root -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-0000000FF1CE\}$' })
        if ($keys.Count -gt 0) { $msi = $true; break }
    }
    return [pscustomobject]@{
        ClickToRun = (@(Get-OfficeClickToRunProduct).Count -gt 0)
        Msi        = $msi
    }
}

function Get-OfficeClickToRunProduct {
    <#
        Produits Office Click-to-Run installés (ProductReleaseIds de la configuration Click-to-Run),
        ex. « O365BusinessRetail ». Liste vide si Office Click-to-Run n'est pas installé.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()
    $configuration = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue
    if (-not $configuration -or -not $configuration.PSObject.Properties['ProductReleaseIds']) { return @() }
    return @(([string]$configuration.ProductReleaseIds).Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
