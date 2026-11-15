<#
    Imprimantes IP à installer (itération 17) : règles de saisie et lecture des modèles d'un
    pilote (.inf). Fonctions pures : le contenu du fichier .inf est fourni par l'appelant.
#>

$script:MaxPrinterNameLength = 220

function New-IpPrinterRequest {
    <# Imprimante IP à installer (une entrée de Selection.Printers.Items). #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Name,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Address,
        [Parameter(Mandatory)][AllowEmptyString()][string]$InfPath,
        [Parameter(Mandatory)][AllowEmptyString()][string]$DriverName
    )
    return [pscustomobject]@{
        PSTypeName = 'FastPrepare.IpPrinterRequest'
        Name       = ([string]$Name).Trim()
        Address    = ([string]$Address).Trim()
        InfPath    = ([string]$InfPath).Trim()
        DriverName = ([string]$DriverName).Trim()
    }
}

function Get-IpPrinterError {
    <#
        Motif lisible du refus d'une imprimante, ou $null.
        -ExistingName : imprimantes déjà demandées (deux imprimantes ne portent pas le même nom).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]$Printer,
        [AllowEmptyCollection()][string[]]$ExistingName = @()
    )
    $name = [string]$Printer.Name
    if (-not $name) { return 'nom de l''imprimante vide' }
    if ($name.Length -gt $script:MaxPrinterNameLength) { return ('nom de {0} caractères sur {1} maximum' -f $name.Length, $script:MaxPrinterNameLength) }
    if ($name -match '[\\,!]') { return 'caractère interdit dans le nom (\ , !)' }
    foreach ($existing in @($ExistingName)) {
        if ($existing -and [string]::Equals($existing, $name, [System.StringComparison]::OrdinalIgnoreCase)) { return ("l'imprimante '{0}' est déjà dans la liste" -f $existing) }
    }

    $address = [string]$Printer.Address
    if (-not $address) { return 'adresse IP vide' }
    if (-not (Test-PrinterAddress -Address $address)) { return 'adresse IP (ex. 192.168.1.50) ou nom d''hôte attendu' }

    $inf = [string]$Printer.InfPath
    if (-not $inf) { return 'pilote (.inf) non choisi' }
    if ($inf -notmatch '\.inf$') { return 'le pilote doit être un fichier .inf' }
    if (-not [string]$Printer.DriverName) { return 'modèle (nom du pilote) vide' }
    return $null
}

function Test-PrinterAddress {
    <# Vrai pour une adresse IPv4 valide ou un nom d'hôte DNS. #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([AllowEmptyString()][string]$Address)
    if ($Address -match '^\d{1,3}(\.\d{1,3}){3}$') {
        foreach ($part in $Address.Split('.')) { if ([int]$part -gt 255) { return $false } }
        return $true
    }
    # Uniquement des chiffres et des points : adresse IP mal formée, pas un nom d'hôte.
    if ($Address -match '^[\d.]+$') { return $false }
    return ($Address -match '^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$')
}

function Get-IpPrinterPortName {
    <# Nom du port TCP/IP standard créé pour une adresse (convention de Windows : IP_<adresse>). #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Address)
    return ('IP_{0}' -f $Address)
}

function Get-InfPrinterModel {
    <#
        Noms des modèles (pilotes) déclarés par un fichier .inf d'imprimante, triés, sans doublon.
        Lit la section [Manufacturer], puis les sections de modèles qu'elle désigne (avec leurs
        variantes d'architecture, ex. .NTamd64) ; les %jetons% sont résolus par [Strings].
        Liste vide si le fichier n'est pas un .inf d'imprimante lisible.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([AllowEmptyString()][AllowNull()][string]$Content)
    if (-not $Content) { return @() }

    # Sections : nom (minuscules) → lignes utiles (sans commentaire).
    $sections = @{}
    $current = $null
    foreach ($raw in ($Content -split "`r?`n")) {
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith(';')) { continue }
        if ($line -match '^\[(.+)\]\s*(;.*)?$') {
            $current = $Matches[1].Trim().ToLowerInvariant()
            if (-not $sections.ContainsKey($current)) { $sections[$current] = New-Object System.Collections.Generic.List[string] }
            continue
        }
        if ($null -ne $current) { $sections[$current].Add($line) }
    }
    if (-not $sections.ContainsKey('manufacturer')) { return @() }

    $strings = @{}
    if ($sections.ContainsKey('strings')) {
        foreach ($line in $sections['strings']) {
            if ($line -match '^([^=\s]+)\s*=\s*(.*)$') {
                $strings[$Matches[1].Trim().ToLowerInvariant()] = (Remove-InfComment -Text $Matches[2]).Trim().Trim('"')
            }
        }
    }

    # [Manufacturer] : « nom = section[,variante…] » → section, section.variante…
    $modelSections = New-Object System.Collections.Generic.List[string]
    foreach ($line in $sections['manufacturer']) {
        $index = $line.IndexOf('=')
        if ($index -lt 0) { continue }
        $parts = @((Remove-InfComment -Text $line.Substring($index + 1)).Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if ($parts.Count -eq 0) { continue }
        $base = $parts[0].ToLowerInvariant()
        $modelSections.Add($base)
        for ($i = 1; $i -lt $parts.Count; $i++) { $modelSections.Add(('{0}.{1}' -f $base, $parts[$i].ToLowerInvariant())) }
    }

    $models = New-Object System.Collections.Generic.List[string]
    foreach ($name in $modelSections) {
        if (-not $sections.ContainsKey($name)) { continue }
        foreach ($line in $sections[$name]) {
            $model = $null
            if ($line -match '^"([^"]+)"\s*=') { $model = $Matches[1] }
            elseif ($line -match '^%([^%]+)%\s*=') {
                $token = $Matches[1].ToLowerInvariant()
                if ($strings.ContainsKey($token)) { $model = $strings[$token] }
            } elseif ($line -match '^([^=;]+?)\s*=') { $model = $Matches[1].Trim() }
            if ($model -and -not $models.Contains($model)) { $models.Add($model) }
        }
    }
    return @($models | Sort-Object)
}

function Remove-InfComment {
    <# Retire le commentaire de fin de ligne (« ; … ») situé hors des guillemets. #>
    param([string]$Text)
    $inQuotes = $false
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $char = $Text[$i]
        if ($char -eq '"') { $inQuotes = -not $inQuotes }
        elseif ($char -eq ';' -and -not $inQuotes) { return $Text.Substring(0, $i) }
    }
    return $Text
}

function Format-IpPrinterSummary {
    <# « Nom → adresse · modèle (fichier.inf) », pour la liste, le plan et le journal. #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)]$Printer)
    $file = ([string]$Printer.InfPath -split '[\\/]')[-1]
    return ('{0} → {1} · {2} ({3})' -f $Printer.Name, $Printer.Address, $Printer.DriverName, $file)
}
