<#
    Étape 11 — MàJ de l'utilitaire constructeur : pilotes, BIOS (section 7).
#>

Register-Step -Id 'update-vendor-utility' -Section 7 -Title 'Mise à jour par l''utilitaire constructeur' -Plan {
    param($Selection, $Snapshot, $Context)
    $key = $Selection.VendorUtility.Key
    if (-not $key -or -not $Selection.Updates.VendorUtility) { return }
    $update = $Context.Config.Utilities.$key.Update
    New-StepAction -Label ('MàJ utilitaire : {0} {1}' -f $update.FilePath, $update.Arguments) -Parameters @{ Kind = 'UtilityUpdate'; UtilityKey = $key }
} -Invoke {
    param($Action, $Context)
    $update = $Context.Config.Utilities.($Action.Parameters.UtilityKey).Update
    $path = Find-InstalledExecutable -Path (Expand-ConfigPath -Path ([string]$update.FilePath) -Variables $Context.Paths.Variables)
    $rebootCodes = if ($update.PSObject.Properties['RebootExitCodes']) { [int[]]@($update.RebootExitCodes) } else { [int[]]@(3010, 1641) }
    # Sens des codes de sortie de l'outil (config.json), clé entière pour Invoke-ExternalProcess.
    $messages = @{}
    if ($update.PSObject.Properties['ExitCodeMessages'] -and $update.ExitCodeMessages) {
        foreach ($entry in $update.ExitCodeMessages.PSObject.Properties) { $messages[[int]$entry.Name] = [string]$entry.Value }
    }
    # Pilotes et BIOS : peut être long ; jamais de redémarrage automatique (arguments de config.json).
    $result = Invoke-ExternalProcess -FilePath $path -ArgumentList ([string]$update.Arguments) -SuccessExitCode ([int[]]@($update.SuccessExitCodes)) -RebootExitCode $rebootCodes `
        -ExitCodeMessage $messages -WorkingDirectory (Split-Path -Path $path -Parent) -TimeoutMinutes 180 -Log $Context.Log
    # Outil qui ne fait que lancer la mise à jour (Lenovo SU Helper) : rappel écrit au journal (Update.Notice).
    if ($update.PSObject.Properties['Notice'] -and $update.Notice) { Write-RunLog -Log $Context.Log -Level ATTN -Message ([string]$update.Notice) }
    [pscustomobject]@{ RebootRequired = $result.RebootRequired }
}
