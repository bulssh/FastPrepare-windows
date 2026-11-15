<#
    Pilotes d'imprimante disponibles sur le poste (itération 17) : dossier des pilotes
    (config.json, Printers.DriverFolder ; C:\Drivers par défaut) et modèles d'un fichier .inf.
    Aucun type WPF : la section « Imprimantes IP » n'en est que l'affichage.
#>

function Get-PrinterDriverFolder {
    <# Dossier où le technicien dépose les pilotes d'imprimante avant de lancer l'outil. #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)]$Context)
    $config = $Context.Config
    if ($config.PSObject.Properties['Printers'] -and $config.Printers.PSObject.Properties['DriverFolder'] -and $config.Printers.DriverFolder) {
        return [string]$config.Printers.DriverFolder
    }
    return 'C:\Drivers'
}

function Get-PrinterDriverCatalog {
    <# Fichiers .inf du dossier des pilotes : { Path, Display } (Display : chemin relatif au dossier). #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Context)
    $folder = Get-PrinterDriverFolder -Context $Context
    $prefix = $folder.TrimEnd('\') + '\'
    foreach ($path in @(Get-PrinterDriverInf -Folder $folder)) {
        $display = if ($path.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { $path.Substring($prefix.Length) } else { $path }
        [pscustomobject]@{ Path = $path; Display = $display }
    }
}

function Get-PrinterDriverModel {
    <# Modèles déclarés par un fichier .inf (liste vide si le fichier est illisible ou n'est pas un pilote d'imprimante). #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][string]$InfPath)
    try { $content = Read-InfContent -Path $InfPath } catch { return @() }
    return @(Get-InfPrinterModel -Content $content)
}
