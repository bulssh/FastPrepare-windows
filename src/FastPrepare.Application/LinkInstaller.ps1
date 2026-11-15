<#
    Installation d'un agent RMM ou d'un antivirus depuis le lien collé par le technicien
    (itération 16). La reconnaissance du lien et la commande silencieuse sont dans
    FastPrepare.Core (Resolve-LinkInstaller) ; ici, le plan et l'exécution communs aux deux étapes.
#>

function New-LinkInstallerAction {
    <# Action du plan pour un lien saisi (aucune si le lien est vide). #>
    param(
        [Parameter(Mandatory)][ValidateSet('Rmm', 'Antivirus')][string]$Kind,
        [AllowEmptyString()][AllowNull()][string]$Url,
        [Parameter(Mandatory)][string]$Title
    )
    if (-not ([string]$Url).Trim()) { return }
    $installer = Resolve-LinkInstaller -Kind $Kind -Url $Url
    if ($installer.Error) { throw ('{0} : {1}' -f $Title, $installer.Error) }
    New-StepAction -Label ('{0} — {1}' -f $Title, (Format-LinkInstallerCommand -Installer $installer)) -Parameters @{
        Kind = 'LinkInstaller'; Installer = $installer
    }
}

function Invoke-LinkInstaller {
    <#
        Télécharge l'installateur, vérifie sa signature Authenticode (valide, quel que soit
        l'éditeur : le lien vient de la console du client) et le lance en silencieux.
        Renvoie { RebootRequired }.
    #>
    param(
        [Parameter(Mandatory)]$Installer,
        [Parameter(Mandatory)]$Context
    )
    $log = $Context.Log
    $folder = Join-Path (Join-Path $Context.Paths.Cache 'agents') $Installer.Kind.ToLowerInvariant()
    $path = Save-RemoteInstaller -Url $Installer.Url -Folder $folder -FileName $Installer.FileName -Log $log
    Assert-TrustedExecutable -Path $path -ExpectedSigner ''
    if ($Installer.Runner -eq 'msiexec') {
        $arguments = ('/i "{0}" {1}' -f $path, $Installer.Arguments).Trim()
        $result = Invoke-ExternalProcess -FilePath (Get-SystemExecutablePath -Name 'msiexec.exe') -ArgumentList $arguments -TimeoutMinutes 60 -Log $log
    } else {
        $result = Invoke-ExternalProcess -FilePath $path -ArgumentList ([string]$Installer.Arguments) -WorkingDirectory $folder -TimeoutMinutes 60 -Log $log
    }
    Write-RunLog -Log $log -Message ('{0} : installateur terminé (code {1})' -f $Installer.Product, $result.ExitCode)
    return [pscustomobject]@{ RebootRequired = $result.RebootRequired }
}
