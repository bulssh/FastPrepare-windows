<#
    Imprimantes IP (itération 17) : pilotes .inf disponibles sur le poste et installation
    (magasin de pilotes, pilote d'impression, port TCP/IP standard, imprimante).
    Une imprimante existante n'est jamais modifiée.
#>

function Get-PrinterDriverInf {
    <# Fichiers .inf du dossier de pilotes (sous-dossiers compris), triés ; liste vide si le dossier n'existe pas. #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)][string]$Folder,
        [int]$Maximum = 500
    )
    if (-not (Test-Path -LiteralPath $Folder -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $Folder -Filter '*.inf' -File -Recurse -ErrorAction SilentlyContinue |
            Sort-Object -Property FullName | Select-Object -First $Maximum | ForEach-Object { $_.FullName })
}

function Read-InfContent {
    <# Texte d'un fichier .inf (UTF-16 ou UTF-8 reconnus à leur marque d'ordre d'octets, sinon page de codes du poste). #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Path)
    $reader = New-Object System.IO.StreamReader($Path, [System.Text.Encoding]::Default, $true)
    try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
}

function Install-IpPrinter {
    <#
        Installe une imprimante IP : pilote ajouté au magasin (pnputil) et déclaré
        (Add-PrinterDriver) s'il ne l'est pas, port TCP/IP créé s'il n'existe pas, puis imprimante.
        Imprimante du même nom déjà présente : erreur, rien n'est modifié.
        Renvoie { RebootRequired }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Address,
        [Parameter(Mandatory)][string]$InfPath,
        [Parameter(Mandatory)][string]$DriverName,
        [Parameter(Mandatory)][string]$PortName,
        $Log
    )
    if (@(Get-Printer -Name $Name -ErrorAction SilentlyContinue).Count -gt 0) { throw "l'imprimante '$Name' existe déjà : elle n'est pas modifiée." }

    $reboot = $false
    if (@(Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue).Count -eq 0) {
        if (-not (Test-Path -LiteralPath $InfPath -PathType Leaf)) { throw "pilote introuvable : $InfPath" }
        $pnputil = Get-SystemExecutablePath -Name 'pnputil.exe'
        # 259 : le pilote est déjà dans le magasin.
        $result = Invoke-ExternalProcess -FilePath $pnputil -ArgumentList ('/add-driver "{0}" /install' -f $InfPath) -SuccessExitCode @(0, 259) -TimeoutMinutes 15 -Log $Log
        $reboot = [bool]$result.RebootRequired
        try {
            Add-PrinterDriver -Name $DriverName -ErrorAction Stop
        } catch {
            throw ("pilote '{0}' refusé par Windows (le modèle doit être écrit comme dans le fichier .inf) : {1}" -f $DriverName, $_.Exception.Message)
        }
        if ($Log) { Write-RunLog -Log $Log -Level DEBUG -Message "Pilote d'impression '$DriverName' ajouté" }
    }

    if (@(Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue).Count -eq 0) {
        Add-PrinterPort -Name $PortName -PrinterHostAddress $Address -ErrorAction Stop
        if ($Log) { Write-RunLog -Log $Log -Level DEBUG -Message "Port $PortName créé ($Address)" }
    }
    Add-Printer -Name $Name -DriverName $DriverName -PortName $PortName -ErrorAction Stop
    return [pscustomobject]@{ RebootRequired = $reboot }
}
