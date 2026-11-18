<#
    Étape 3 — Désinstallation des programmes Microsoft : Office, Outlook, OneNote, Teams (section 3).
    Office Click-to-Run et MSI sont retirés par un seul passage d'ODT (XML de New-OdtRemoveXml).
    Outlook classique et OneNote Click-to-Run partent avec la suite (Remove All).
#>

Register-Step -Id 'remove-microsoft-apps' -Section 3 -Title 'Désinstallation des programmes Microsoft' -Plan {
    param($Selection, $Snapshot, $Context)
    $ms = $Selection.MicrosoftApps

    if ($ms.OfficeClickToRun -or $ms.OfficeMsi) {
        # Office MSI avec une installation d'Office prévue : retiré par l'installation (RemoveMSI dans
        # son XML, forme documentée par Microsoft), pas par un passage d'ODT à part.
        $msiWithInstall = [bool]$ms.OfficeMsi -and [bool]$Selection.Office.EditionKey
        $msiHere = [bool]$ms.OfficeMsi -and -not $msiWithInstall
        if ($ms.OfficeClickToRun -or $msiHere) {
            $parts = @()
            if ($ms.OfficeClickToRun) { $parts += 'Click-to-Run, toutes éditions et langues' }
            if ($msiHere) { $parts += 'MSI 2010-2016' }
            $label = 'Office : ODT /configure, suppression {0}' -f ($parts -join ' + ')
            if ($ms.OutlookClassic) { $label += ' · Outlook classique retiré avec la suite' }
            $label += ' · applications Office ouvertes fermées sans enregistrer'
            $xml = New-OdtRemoveXml -RemoveClickToRun:([bool]$ms.OfficeClickToRun) -RemoveMsi:$msiHere
            New-StepAction -Label $label -Details ($xml -split "`r`n") -Parameters @{ Kind = 'OdtRemove'; Xml = $xml; ClickToRun = [bool]$ms.OfficeClickToRun; Msi = $msiHere }
        }
        # $msiWithInstall : aucune action ici ; l'installation d'Office l'annonce et vérifie le
        # retrait (audit BUG-023 : pas d'action « réussie » avant que l'installation ait abouti).
    } elseif ($ms.OutlookClassic) {
        New-PlanWarning -Message 'Outlook classique coché sans « Office Click-to-Run » ni « Office MSI » : il n''est retiré qu''avec la suite Office, aucune action prévue (question ouverte QO1).'
    }

    if ($ms.OutlookNew) {
        New-StepAction -Label 'Nouvel Outlook : Remove-AppxPackage -AllUsers + Remove-AppxProvisionedPackage (Microsoft.OutlookForWindows)' -Parameters @{ Kind = 'AppxRemove'; Package = 'Microsoft.OutlookForWindows' }
    }

    if ($ms.OneNote) {
        New-StepAction -Label 'OneNote : Remove-AppxPackage -AllUsers + Remove-AppxProvisionedPackage (Microsoft.Office.OneNote)' -Parameters @{ Kind = 'AppxRemove'; Package = 'Microsoft.Office.OneNote' }
        if (-not $ms.OfficeClickToRun) {
            New-PlanWarning -Message 'OneNote : la version Click-to-Run n''est retirée qu''avec « Office Click-to-Run » (Remove All) ; seule l''application du Store sera retirée.'
        }
    }

    if ($ms.Teams) {
        New-StepAction -Label 'Teams classique : désinstallation MSI de « Teams Machine-Wide Installer »' -Parameters @{ Kind = 'MsiRemoveByName'; DisplayName = 'Teams Machine-Wide Installer' }
        New-StepAction -Label 'Teams classique : suppression du dossier %LocalAppData%\Microsoft\Teams' -Parameters @{ Kind = 'TeamsClassicFolder' }
        New-StepAction -Label 'Nouveau Teams : Remove-AppxPackage -AllUsers + Remove-AppxProvisionedPackage (MSTeams)' -Parameters @{ Kind = 'AppxRemove'; Package = 'MSTeams' }
        New-StepAction -Label 'Teams personnel : Remove-AppxPackage -AllUsers + Remove-AppxProvisionedPackage (MicrosoftTeams)' -Parameters @{ Kind = 'AppxRemove'; Package = 'MicrosoftTeams' }
    }
} -Invoke {
    param($Action, $Context)
    $log = $Context.Log
    $p = $Action.Parameters
    switch ($p.Kind) {
        'OdtRemove' {
            # Rien de ce qui est demandé n'est installé : l'outil de déploiement n'est ni téléchargé
            # ni lancé (sur un poste sans Office, sa suppression échoue avec le code -1).
            $present = Get-InstalledOfficeKind
            if (-not (($p.ClickToRun -and $present.ClickToRun) -or ($p.Msi -and $present.Msi))) {
                Write-RunLog -Log $log -Message 'Office : déjà absent (aucune installation Click-to-Run ni MSI à retirer)'
                return
            }
            $setup = Initialize-OdtFolder -Folder $Context.Paths.OdtFolder -SetupUrl $Context.Config.Office.OdtSetupUrl -Log $log
            $result = Invoke-Odt -SetupPath $setup -Xml $p.Xml -Name 'suppression' -Log $log
            # Contrôle après coup : un ODT terminé sans erreur ne suffit pas.
            $after = Get-InstalledOfficeKind
            if ($p.ClickToRun -and $after.ClickToRun) {
                throw ('ODT terminé, mais Office Click-to-Run encore présent ({0})' -f (@(Get-OfficeClickToRunProduct) -join ', '))
            }
            if ($p.Msi -and $after.Msi) {
                # Retrait non constaté : jamais annoncé réussi (audit BUG-023). Microsoft : il peut
                # se terminer au redémarrage, qui n'est pas imposé.
                throw (New-StepFailure -RebootRequired -Message ('ODT terminé, mais Office MSI encore inscrit sur le poste : ' +
                        'vérifier après le redémarrage final ; sinon, le désinstaller depuis Paramètres › Applications'))
            }
            Write-RunLog -Log $log -Message 'Office : suppression vérifiée sur le poste'
            [pscustomobject]@{ RebootRequired = $result.RebootRequired }
        }
        'AppxRemove' {
            # Applications fermées avant le retrait du paquet (nouvel Outlook, nouveau Teams).
            [void](Stop-ProcessByName -Name @('olk', 'ms-teams', 'msteams'))
            $result = Remove-AppxEverywhere -Name $p.Package -Log $log
            if (@($result.Installed).Count + @($result.Provisioned).Count -eq 0) {
                Write-RunLog -Log $log -Message ('{0} : déjà absent' -f $p.Package)
            }
        }
        'MsiRemoveByName' {
            $codes = @(Get-MsiProductCodeByName -DisplayName $p.DisplayName)
            if ($codes.Count -eq 0) { Write-RunLog -Log $log -Message ('{0} : déjà absent' -f $p.DisplayName); return }
            [void](Stop-ProcessByName -Name 'Teams')
            $reboot = $false
            foreach ($code in $codes) { if ((Uninstall-MsiProduct -ProductCode $code -Log $log).RebootRequired) { $reboot = $true } }
            [pscustomobject]@{ RebootRequired = $reboot }
        }
        'TeamsClassicFolder' {
            # Profil du compte connecté seulement (question ouverte QO2 : autres profils).
            [void](Stop-ProcessByName -Name 'Teams')
            $profiles = Get-ProfileLocation
            $folder = Join-Path $profiles.Current 'AppData\Local\Microsoft\Teams'
            $result = Remove-GuardedFolder -Path $folder -ProfilesRoot $profiles.Root -CurrentProfile $profiles.Current -AllowInsideProfile
            if (-not $result.Changed) { Write-RunLog -Log $log -Message "Dossier Teams classique déjà absent : $folder" }
        }
        default { throw "action inconnue : $($p.Kind)" }
    }
}
