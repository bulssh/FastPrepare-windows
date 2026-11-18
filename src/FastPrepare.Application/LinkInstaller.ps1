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
        Télécharge l'installateur, exige une signature Authenticode valide, compare l'éditeur aux
        éditeurs attendus (config.json, Agents.<type>.ExpectedSigners) et le lance en silencieux.
        Éditeur inattendu : lancé quand même, avec un avertissement (DEC37, décision du propriétaire).
        Le lien et le nom du fichier n'apparaissent qu'en forme masquée (audit SEC-003).
        Renvoie { RebootRequired }.
    #>
    param(
        [Parameter(Mandatory)]$Installer,
        [Parameter(Mandatory)]$Context
    )
    $log = $Context.Log
    $display = if ($Installer.PSObject.Properties['DisplayFileName'] -and $Installer.DisplayFileName) { [string]$Installer.DisplayFileName } else { 'installateur' }
    $displayUrl = if ($Installer.PSObject.Properties['DisplayUrl'] -and $Installer.DisplayUrl) { [string]$Installer.DisplayUrl } else { '(lien masqué)' }
    $folder = Join-Path (Join-Path $Context.Paths.Cache 'agents') $Installer.Kind.ToLowerInvariant()
    try {
        $path = Save-RemoteInstaller -Url $Installer.Url -Folder $folder -FileName $Installer.FileName -DisplayUrl $displayUrl -Log $log
        Assert-TrustedExecutable -Path $path -ExpectedSigner ''
        $signer = Get-ExecutableSigner -Path $path
        $expected = @()
        $agents = $Context.Config.PSObject.Properties['Agents']
        if ($agents -and $agents.Value.PSObject.Properties[$Installer.Kind]) { $expected = @($agents.Value.($Installer.Kind).ExpectedSigners) }
        $known = @($expected | Where-Object { $signer -match [regex]::Escape([string]$_) }).Count -gt 0
        if ($known) {
            Write-RunLog -Log $log -Message ('{0} : signé par « {1} »' -f $Installer.Product, $signer)
        } else {
            Write-RunLog -Log $log -Level ATTN -Message ('{0} : signé par « {1} », éditeur hors de la liste attendue ({2}) : lancé quand même, vérifier qu''il s''agit du bon produit' -f $Installer.Product, $signer, $(if ($expected.Count) { $expected -join ', ' } else { 'liste vide' }))
        }
        if ($Installer.Runner -eq 'msiexec') {
            $arguments = ('/i "{0}" {1}' -f $path, $Installer.Arguments).Trim()
            $result = Invoke-ExternalProcess -FilePath (Get-SystemExecutablePath -Name 'msiexec.exe') -ArgumentList $arguments -TimeoutMinutes 60 -DisplayName ('msiexec /i {0}' -f $display) -Log $log
        } else {
            $result = Invoke-ExternalProcess -FilePath $path -ArgumentList ([string]$Installer.Arguments) -WorkingDirectory $folder -TimeoutMinutes 60 -DisplayName $display -Log $log
        }
    } catch {
        # Dernier filet : aucune erreur ne laisse passer le lien ni le nom de fichier complets.
        $message = ([string]$_.Exception.Message).Replace([string]$Installer.Url, $displayUrl)
        if ($Installer.FileName) { $message = $message.Replace([string]$Installer.FileName, $display) }
        throw $message
    }
    Write-RunLog -Log $log -Message ('{0} : installateur terminé (code {1})' -f $Installer.Product, $result.ExitCode)
    return [pscustomobject]@{ RebootRequired = $result.RebootRequired }
}
